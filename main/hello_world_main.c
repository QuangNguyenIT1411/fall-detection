#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/i2c_master.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_err.h"
#include "esp_timer.h"
#include "esp_random.h"
#include "nvs_flash.h"

#include "app_config.h"
#include "cloud_event_service.h"
#include "manual_sos.h"
#include "buzzer_output.h"
#include "mqtt_manager.h"
#include "wifi_manager.h"

// =====================================================
// ALERT OUTPUTS
// =====================================================
#define BUZZER_GPIO GPIO_NUM_4
#define LED_RED_GPIO GPIO_NUM_5
#define CANCEL_BUTTON_GPIO GPIO_NUM_3

// =====================================================
// I2C
// =====================================================
#define I2C_SDA GPIO_NUM_6
#define I2C_SCL GPIO_NUM_7
#define IMU_ADDR 0x68

// =====================================================
// MPU6050 / MPU6500 REGISTERS
// =====================================================
#define REG_SMPLRT_DIV       0x19
#define REG_CONFIG           0x1A
#define REG_GYRO_CONFIG      0x1B
#define REG_ACCEL_CONFIG     0x1C
#define REG_ACCEL_CONFIG2    0x1D
#define REG_ACCEL_XOUT_H     0x3B
#define REG_PWR_MGMT_1       0x6B
#define REG_WHO_AM_I         0x75

// =====================================================
// SCALE
// =====================================================
#define ACCEL_SCALE 4096.0f      // +-8g
#define GYRO_SCALE 32.8f         // +-1000 dps

// =====================================================
// SAMPLING / FILTER
// =====================================================
#define SAMPLE_PERIOD_MS       10
#define CALIBRATION_SAMPLES    500
#define RAD_TO_DEG             57.2957795f
#define FILTER_ALPHA           0.98f

// =====================================================
// FALL DETECTION THRESHOLDS - V3.1
// =====================================================
#define FALL_LOW_G_THRESHOLD       0.60f
#define FALL_LOW_G_SAMPLES         3
#define IMPACT_THRESHOLD           2.20f
#define DIRECT_IMPACT_THRESHOLD    2.60f
#define ROTATION_THRESHOLD_DPS     180.0f

// POSE 3D
#define POSTURE_THRESHOLD_DEG              55.0f
#define POSTURE_HOLD_THRESHOLD_DEG         45.0f
#define POSTURE_RETURN_THRESHOLD_DEG       30.0f

// V3.1: nguoi bi te KHONG can nam im.
// Chi can tu the bat thuong ton tai du lau (cong don) sau impact.
#define POSTURE_EVIDENCE_TIME_MS           2500

// Chi huy su kien neu da tro lai gan tu the ban dau va GIU o do du lau.
#define POSTURE_RETURN_TIME_MS             2000

// V3.1: chi coi la da phuc hoi khi tu the gan moc, gia toc on dinh
// va GYRO thap. Nhu vay lan/nhuc nhich sau khi te se KHONG bi huy som.
#define RECOVERY_ACC_MIN                    0.85f
#define RECOVERY_ACC_MAX                    1.15f
#define RECOVERY_GYRO_MAX_DPS               25.0f

// POSE tu accelerometer chi dang tin khi tong gia toc gan 1g.
// Khong dung GYRO de bac bo cu te trong POSTURE.
#define POSE_VALID_ACC_MIN                 0.65f
#define POSE_VALID_ACC_MAX                 1.35f

// =====================================================
// TIMEOUT
// =====================================================
#define FALLING_TIMEOUT_MS                 1200
#define IMPACT_TIMEOUT_MS                  2000
#define POSTURE_TIMEOUT_MS                 12000

// =====================================================
// FALL STATES
// =====================================================
typedef enum
{
    STATE_NORMAL = 0,
    STATE_FALLING,
    STATE_IMPACT,
    STATE_POSTURE,
    STATE_FALL_DETECTED
} fall_state_t;

// =====================================================
// GLOBALS
// =====================================================
static const char *TAG = "FALL_SYSTEM";

static float gyro_offset_x = 0.0f;
static float gyro_offset_y = 0.0f;
static float gyro_offset_z = 0.0f;
static float accel_baseline = 1.0f;

static float roll = 0.0f;
static float pitch = 0.0f;
static float reference_roll = 0.0f;
static float reference_pitch = 0.0f;

// Vector trong luc calibration, da chuan hoa
static float reference_ax = 0.0f;
static float reference_ay = 0.0f;
static float reference_az = 1.0f;

static fall_state_t fall_state = STATE_NORMAL;
static int low_g_counter = 0;

static int64_t state_start_ms = 0;
static int64_t posture_return_start_ms = 0;

// V3: bang chung tu the bat thuong trong POSTURE duoc cong don.
static int64_t posture_last_sample_ms = 0;
static int64_t posture_abnormal_accum_ms = 0;
static int64_t posture_last_progress_log_ms = 0;

// V3: chi de THU DU LIEU, chua dung cac moc thoi gian nay de loai cu te.
static int64_t low_g_candidate_start_ms = 0;
static int64_t fall_low_g_start_ms = 0;
static int64_t fall_low_g_last_ms = 0;

static float peak_acc = 0.0f;
static float peak_gyro = 0.0f;

// Du lieu su kien duoc giu lai cho Phase 5.
static float final_pose = 0.0f;
static int64_t low_g_duration_ms = 0;
static int64_t low_g_to_impact_ms = 0;

// Phase 6: authoritative confirmation deadline starts when the device enters
// the latched FALL_DETECTED state. It is independent from MQTT/browser time.
static int64_t fall_detected_start_ms = 0;
static int64_t fall_confirm_next_enqueue_ms = 0;
static bool fall_confirm_enqueued = false;
static bool fall_confirm_deadline_logged = false;

#define SOS_PENDING_CAPACITY 32
static manual_sos_t manual_sos;
static char pending_sos_keys[SOS_PENDING_CAPACITY][37];
static unsigned int pending_sos_head = 0;
static unsigned int pending_sos_count = 0;

// =====================================================
// TIME
// =====================================================
static int64_t millis_now(void)
{
    return esp_timer_get_time() / 1000;
}

// =====================================================
// STATE NAME
// =====================================================
static const char *state_to_string(fall_state_t state)
{
    switch (state)
    {
        case STATE_NORMAL:        return "NORMAL";
        case STATE_FALLING:       return "FALLING";
        case STATE_IMPACT:        return "IMPACT";
        case STATE_POSTURE:       return "POSTURE";
        case STATE_FALL_DETECTED: return "FALL_DETECTED";
        default:                  return "UNKNOWN";
    }
}

// =====================================================
// CHANGE STATE
// =====================================================
static void change_state(fall_state_t new_state)
{
    if (fall_state == new_state)
        return;

    ESP_LOGW(TAG, "STATE: %s -> %s",
             state_to_string(fall_state),
             state_to_string(new_state));

    fall_state = new_state;
    state_start_ms = millis_now();
    posture_return_start_ms = 0;

    // Enqueue non-blocking; neu MQTT offline, manager van ghi nho state hien tai.
    mqtt_publish_state(state_to_string(fall_state), state_start_ms);

    if (new_state == STATE_FALL_DETECTED)
    {
        fall_detected_start_ms = state_start_ms;
        fall_confirm_next_enqueue_ms = state_start_ms + FALL_CONFIRM_TIMEOUT_MS;
        fall_confirm_enqueued = false;
        fall_confirm_deadline_logged = false;
        ESP_LOGI(TAG,
                 "FALL confirm timer started: uptime=%lld ms, deadline=%lld ms",
                 (long long)fall_detected_start_ms,
                 (long long)fall_confirm_next_enqueue_ms);

        cloud_fall_event_t event = {
            .peak_acc = peak_acc,
            .peak_gyro = peak_gyro,
            .final_pose = final_pose,
            .low_g_duration_ms = low_g_duration_ms,
            .low_g_to_impact_ms = low_g_to_impact_ms,
            .device_uptime_ms = state_start_ms,
        };
        cloud_event_enqueue_fall(&event);
    }

    if (new_state == STATE_POSTURE)
    {
        posture_last_sample_ms = state_start_ms;
        posture_abnormal_accum_ms = 0;
        posture_last_progress_log_ms = 0;
    }
}

// =====================================================
// RESET FALL DETECTION
// =====================================================
static void reset_fall_detection(void)
{
    bool state_changed = fall_state != STATE_NORMAL;

    fall_state = STATE_NORMAL;
    low_g_counter = 0;
    state_start_ms = millis_now();
    posture_return_start_ms = 0;
    posture_last_sample_ms = 0;
    posture_abnormal_accum_ms = 0;
    posture_last_progress_log_ms = 0;
    low_g_candidate_start_ms = 0;
    fall_low_g_start_ms = 0;
    fall_low_g_last_ms = 0;
    peak_acc = 0.0f;
    peak_gyro = 0.0f;
    final_pose = 0.0f;
    low_g_duration_ms = 0;
    low_g_to_impact_ms = 0;
    fall_detected_start_ms = 0;
    fall_confirm_next_enqueue_ms = 0;
    fall_confirm_enqueued = false;
    fall_confirm_deadline_logged = false;

    if (state_changed)
        mqtt_publish_state(state_to_string(fall_state), state_start_ms);

    ESP_LOGI(TAG, "He thong tro ve NORMAL");
}

// =====================================================
// ALERT OUTPUT HELPERS
// =====================================================
static void alert_outputs_init(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << BUZZER_GPIO) | (1ULL << LED_RED_GPIO),
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    ESP_ERROR_CHECK(gpio_config(&io_conf));

    buzzer_output_set_alarm(false);
    gpio_set_level(LED_RED_GPIO, 0);

    ESP_LOGI(TAG, "Alert outputs ready: BUZZER=GPIO4, LED_RED=GPIO5");
}

static void update_alert_outputs(void)
{
    static bool last_alarm_on = false;
    bool alarm_on = (fall_state == STATE_FALL_DETECTED) || manual_sos.active;

    buzzer_output_set_alarm(alarm_on);
    gpio_set_level(LED_RED_GPIO, alarm_on ? 1 : 0);

    if (alarm_on != last_alarm_on)
    {
        if (alarm_on)
            ESP_LOGE(TAG, "CANH BAO: LED DO BAT, BUZZER THEO CAU HINH");
        else
            ESP_LOGI(TAG, "Canh bao da tat: LED DO + BUZZER TAT");

        last_alarm_on = alarm_on;
    }
}

static void generate_sos_key(char key[37])
{
    uint8_t bytes[16];
    esp_fill_random(bytes, sizeof(bytes));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    snprintf(key, 37,
             "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-"
             "%02x%02x%02x%02x%02x%02x",
             bytes[0], bytes[1], bytes[2], bytes[3],
             bytes[4], bytes[5], bytes[6], bytes[7],
             bytes[8], bytes[9], bytes[10], bytes[11],
             bytes[12], bytes[13], bytes[14], bytes[15]);
}

static void process_manual_sos_button(void)
{
    const int64_t now_ms = millis_now();
    manual_sos_result_t result = manual_sos_update(
        &manual_sos, fall_state == STATE_NORMAL,
        gpio_get_level(CANCEL_BUTTON_GPIO) == 1, now_ms);

    if (result.triggered)
    {
        ESP_LOGE(TAG, "MANUAL_SOS_TRIGGERED");
        if (pending_sos_count < SOS_PENDING_CAPACITY)
        {
            unsigned int tail = (pending_sos_head + pending_sos_count) %
                                SOS_PENDING_CAPACITY;
            generate_sos_key(pending_sos_keys[tail]);
            pending_sos_count++;
        }
        else
        {
            ESP_LOGE(TAG, "SOS pending buffer full; cloud action unavailable");
        }
    }
    if (result.silenced)
        ESP_LOGI(TAG, "MANUAL_SOS_SILENCED (cloud event unchanged)");

    if (pending_sos_count > 0 &&
        cloud_event_enqueue_sos(pending_sos_keys[pending_sos_head]))
    {
        pending_sos_head = (pending_sos_head + 1) % SOS_PENDING_CAPACITY;
        pending_sos_count--;
    }
}

// =====================================================
// CANCEL BUTTON - GPIO3, ACTIVE LOW - V2.5
//
// Noi don gian:
// GPIO3 ------- BUTTON ------- GND
//
// ESP32-C3 bat internal pull-up:
// - Khong bam: GPIO3 = HIGH
// - Bam nut:   GPIO3 = LOW
//
// V2.5 chong CANCEL gia khi rung / nhuc nhich day:
// 1) Sau khi vua vao FALL_DETECTED, khoa CANCEL 2000 ms.
// 2) Sau thoi gian khoa, GPIO3 phai HIGH on dinh >= 500 ms moi ARM.
// 3) Nguoi dung phai GIU nut LOW >= 600 ms.
// 4) Sau do NHA nut ve HIGH on dinh >= 100 ms moi CANCEL.
// 5) Neu LOW qua 2500 ms thi xem nhu day bi chap / nut bi ket, KHONG CANCEL.
//
// Nhu vay mot xung LOW ngan do rung day se bi bo qua.
// FALL_DETECTED van duoc giu nguyen cho den khi co mot lan bam-nha hop le.
// =====================================================
#define CANCEL_LOCKOUT_MS            2000
#define CANCEL_ARM_HIGH_MS            500
#define CANCEL_LOW_MIN_MS             600
#define CANCEL_RELEASE_DEBOUNCE_MS     100
#define CANCEL_MAX_LOW_MS             2500

typedef enum
{
    CANCEL_LOCKED = 0,
    CANCEL_WAIT_HIGH,
    CANCEL_ARMED,
    CANCEL_PRESSING,
    CANCEL_WAIT_RELEASE
} cancel_state_t;

static cancel_state_t cancel_state = CANCEL_WAIT_HIGH;
static int64_t cancel_lockout_start_ms = 0;
static int64_t cancel_high_start_ms = 0;
static int64_t cancel_low_start_ms = 0;
static int64_t cancel_release_start_ms = 0;

static void cancel_button_init(void)
{
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << CANCEL_BUTTON_GPIO),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };

    ESP_ERROR_CHECK(gpio_config(&io_conf));

    cancel_state = CANCEL_WAIT_HIGH;
    cancel_lockout_start_ms = 0;
    cancel_high_start_ms = 0;
    cancel_low_start_ms = 0;
    cancel_release_start_ms = 0;

    ESP_LOGI(TAG,
             "Cancel button ready: GPIO3, internal pull-up, bam = LOW");
}

// Goi dung luc vua chuyen sang FALL_DETECTED.
static void cancel_button_rearm(void)
{
    cancel_state = CANCEL_LOCKED;
    cancel_lockout_start_ms = millis_now();
    cancel_high_start_ms = 0;
    cancel_low_start_ms = 0;
    cancel_release_start_ms = 0;

    ESP_LOGI(TAG,
             "CANCEL guard: khoa 2 giay, sau do bam-giu >= 600ms roi nha nut de huy");
}

// Tra ve true CHI sau mot lan bam co chu y:
// HIGH on dinh -> LOW >= 600 ms -> HIGH on dinh.
static bool cancel_button_click_event(void)
{
    const int level = gpio_get_level(CANCEL_BUTTON_GPIO);
    const int64_t now_ms = millis_now();

    switch (cancel_state)
    {
        case CANCEL_LOCKED:
        {
            // Bo qua moi thay doi cua nut trong 2 giay dau sau FALL_DETECTED.
            if ((now_ms - cancel_lockout_start_ms) >= CANCEL_LOCKOUT_MS)
            {
                cancel_state = CANCEL_WAIT_HIGH;
                cancel_high_start_ms = 0;
            }
            break;
        }

        case CANCEL_WAIT_HIGH:
        {
            if (level == 1)
            {
                if (cancel_high_start_ms == 0)
                    cancel_high_start_ms = now_ms;

                if ((now_ms - cancel_high_start_ms) >= CANCEL_ARM_HIGH_MS)
                {
                    cancel_state = CANCEL_ARMED;
                    cancel_high_start_ms = 0;
                    ESP_LOGI(TAG, "CANCEL armed: co the bam nut de huy canh bao");
                }
            }
            else
            {
                // Neu dang LOW do rung/day cam sai thi chua cho ARM.
                cancel_high_start_ms = 0;
            }
            break;
        }

        case CANCEL_ARMED:
        {
            if (level == 0)
            {
                cancel_low_start_ms = now_ms;
                cancel_release_start_ms = 0;
                cancel_state = CANCEL_PRESSING;
            }
            break;
        }

        case CANCEL_PRESSING:
        {
            int64_t low_time = now_ms - cancel_low_start_ms;

            if (level == 1)
            {
                // Nha qua som -> xem nhu nhieu/rung, khong CANCEL.
                if (low_time < CANCEL_LOW_MIN_MS)
                {
                    cancel_state = CANCEL_ARMED;
                    cancel_low_start_ms = 0;
                    ESP_LOGW(TAG,
                             "CANCEL xung ngan (%lld ms) -> bo qua",
                             (long long)low_time);
                }
                else if (low_time <= CANCEL_MAX_LOW_MS)
                {
                    // Da giu du lau, bat dau xac nhan HIGH sau khi nha.
                    cancel_release_start_ms = now_ms;
                    cancel_state = CANCEL_WAIT_RELEASE;
                }
                else
                {
                    // LOW qua lau -> co the nut bi ket / day chap GND.
                    cancel_state = CANCEL_WAIT_HIGH;
                    cancel_low_start_ms = 0;
                    cancel_high_start_ms = now_ms;
                    ESP_LOGW(TAG,
                             "CANCEL LOW qua lau -> bo qua, cho nut ve HIGH");
                }
            }
            else if (low_time > CANCEL_MAX_LOW_MS)
            {
                // Dang giu LOW qua lau: bo su kien nay.
                cancel_state = CANCEL_WAIT_HIGH;
                cancel_low_start_ms = 0;
                cancel_high_start_ms = 0;
                ESP_LOGW(TAG,
                         "CANCEL input LOW qua lau -> bo qua, cho nut tro lai HIGH");
            }
            break;
        }

        case CANCEL_WAIT_RELEASE:
        {
            if (level == 1)
            {
                if ((now_ms - cancel_release_start_ms) >= CANCEL_RELEASE_DEBOUNCE_MS)
                {
                    cancel_state = CANCEL_WAIT_HIGH;
                    cancel_high_start_ms = now_ms;
                    cancel_low_start_ms = 0;
                    cancel_release_start_ms = 0;
                    return true;
                }
            }
            else
            {
                // Neu nut bounce LOW lai sau khi nha, quay lai PRESSING.
                cancel_state = CANCEL_PRESSING;
                cancel_release_start_ms = 0;
            }
            break;
        }

        default:
            cancel_state = CANCEL_WAIT_HIGH;
            cancel_high_start_ms = 0;
            cancel_low_start_ms = 0;
            cancel_release_start_ms = 0;
            break;
    }

    return false;
}

// Called on both successful and failed IMU reads. The latched event and its
// confirmation deadline must not depend on continued sensor I/O.
static void process_latched_fall_controls(void)
{
    process_manual_sos_button();
    if (cancel_button_click_event())
    {
        if (fall_state == STATE_FALL_DETECTED)
        {
            const int64_t cancel_now_ms = millis_now();
            const bool before_confirmation_deadline =
                fall_detected_start_ms > 0 &&
                (cancel_now_ms - fall_detected_start_ms) <
                    FALL_CONFIRM_TIMEOUT_MS &&
                !fall_confirm_enqueued;

            ESP_LOGW(TAG, "CANCEL PRESSED -> tat canh bao va reset ve NORMAL");
            if (before_confirmation_deadline)
            {
                cloud_event_enqueue_cancel();
            }
            else
            {
                ESP_LOGW(TAG,
                         "Confirmation deadline passed; button only resets local alarm");
            }
            reset_fall_detection();
        }
        else
        {
            ESP_LOGI(TAG, "CANCEL PRESSED (chua co FALL_DETECTED) -> bo qua");
        }
    }

    // A completed cancel is evaluated first. Once the deadline is reached,
    // retry a full queue at most once per second until one enqueue succeeds.
    const int64_t confirm_now_ms = millis_now();
    if (fall_state != STATE_FALL_DETECTED ||
        fall_confirm_enqueued ||
        fall_detected_start_ms <= 0 ||
        (confirm_now_ms - fall_detected_start_ms) < FALL_CONFIRM_TIMEOUT_MS)
        return;

    if (!fall_confirm_deadline_logged)
    {
        fall_confirm_deadline_logged = true;
        ESP_LOGW(TAG,
                 "FALL confirm deadline reached: elapsed=%lld ms",
                 (long long)(confirm_now_ms - fall_detected_start_ms));
    }

    if (confirm_now_ms >= fall_confirm_next_enqueue_ms)
    {
        fall_confirm_enqueued = cloud_event_enqueue_confirm();
        if (!fall_confirm_enqueued)
        {
            fall_confirm_next_enqueue_ms = confirm_now_ms + 1000;
            ESP_LOGW(TAG, "Cloud confirm enqueue failed; retry in 1000 ms");
        }
    }
}

// =====================================================
// I2C HELPERS
// =====================================================
static esp_err_t imu_write_reg(i2c_master_dev_handle_t dev,
                               uint8_t reg,
                               uint8_t value)
{
    uint8_t data[2] = {reg, value};
    return i2c_master_transmit(dev, data, sizeof(data), 1000);
}

static esp_err_t imu_read_reg(i2c_master_dev_handle_t dev,
                              uint8_t reg,
                              uint8_t *data,
                              size_t len)
{
    return i2c_master_transmit_receive(dev, &reg, 1, data, len, 1000);
}

static esp_err_t imu_read_raw(i2c_master_dev_handle_t imu_handle,
                              int16_t *raw_ax,
                              int16_t *raw_ay,
                              int16_t *raw_az,
                              int16_t *raw_gx,
                              int16_t *raw_gy,
                              int16_t *raw_gz)
{
    uint8_t data[14];
    esp_err_t ret = imu_read_reg(imu_handle, REG_ACCEL_XOUT_H, data, 14);

    if (ret != ESP_OK)
        return ret;

    *raw_ax = (int16_t)(((uint16_t)data[0] << 8) | data[1]);
    *raw_ay = (int16_t)(((uint16_t)data[2] << 8) | data[3]);
    *raw_az = (int16_t)(((uint16_t)data[4] << 8) | data[5]);
    *raw_gx = (int16_t)(((uint16_t)data[8] << 8) | data[9]);
    *raw_gy = (int16_t)(((uint16_t)data[10] << 8) | data[11]);
    *raw_gz = (int16_t)(((uint16_t)data[12] << 8) | data[13]);

    return ESP_OK;
}

// =====================================================
// CALIBRATION
// =====================================================
static void calibrate_sensor(i2c_master_dev_handle_t imu_handle)
{
    float sum_gx = 0.0f, sum_gy = 0.0f, sum_gz = 0.0f;
    float sum_acc = 0.0f;
    float sum_ax = 0.0f, sum_ay = 0.0f, sum_az = 0.0f;
    int valid_samples = 0;

    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "BAT DAU CALIBRATION");
    ESP_LOGI(TAG, "GIU CAM BIEN NAM YEN!");
    ESP_LOGI(TAG, "Khong cham vao cam bien trong ~7 giay");
    ESP_LOGI(TAG, "========================================");

    vTaskDelay(pdMS_TO_TICKS(2000));

    for (int i = 0; i < CALIBRATION_SAMPLES; i++)
    {
        int16_t raw_ax, raw_ay, raw_az;
        int16_t raw_gx, raw_gy, raw_gz;

        esp_err_t ret = imu_read_raw(
            imu_handle,
            &raw_ax, &raw_ay, &raw_az,
            &raw_gx, &raw_gy, &raw_gz
        );

        if (ret == ESP_OK)
        {
            float ax = raw_ax / ACCEL_SCALE;
            float ay = raw_ay / ACCEL_SCALE;
            float az = raw_az / ACCEL_SCALE;
            float gx = raw_gx / GYRO_SCALE;
            float gy = raw_gy / GYRO_SCALE;
            float gz = raw_gz / GYRO_SCALE;

            float total_acc = sqrtf(ax * ax + ay * ay + az * az);

            sum_ax += ax;
            sum_ay += ay;
            sum_az += az;
            sum_acc += total_acc;
            sum_gx += gx;
            sum_gy += gy;
            sum_gz += gz;
            valid_samples++;
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }

    if (valid_samples <= 0)
    {
        ESP_LOGE(TAG, "Calibration that bai!");
        return;
    }

    gyro_offset_x = sum_gx / valid_samples;
    gyro_offset_y = sum_gy / valid_samples;
    gyro_offset_z = sum_gz / valid_samples;

    accel_baseline = sum_acc / valid_samples;
    if (accel_baseline < 0.5f)
        accel_baseline = 1.0f;

    float avg_ax = sum_ax / valid_samples;
    float avg_ay = sum_ay / valid_samples;
    float avg_az = sum_az / valid_samples;

    float ref_length = sqrtf(
        avg_ax * avg_ax +
        avg_ay * avg_ay +
        avg_az * avg_az
    );

    if (ref_length > 0.1f)
    {
        reference_ax = avg_ax / ref_length;
        reference_ay = avg_ay / ref_length;
        reference_az = avg_az / ref_length;
    }

    roll = atan2f(avg_ay, avg_az) * RAD_TO_DEG;
    pitch = atan2f(
        -avg_ax,
        sqrtf(avg_ay * avg_ay + avg_az * avg_az)
    ) * RAD_TO_DEG;

    reference_roll = roll;
    reference_pitch = pitch;

    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "========= CALIBRATION HOAN TAT =========");
    ESP_LOGI(TAG, "Gyro offset X = %.3f dps", gyro_offset_x);
    ESP_LOGI(TAG, "Gyro offset Y = %.3f dps", gyro_offset_y);
    ESP_LOGI(TAG, "Gyro offset Z = %.3f dps", gyro_offset_z);
    ESP_LOGI(TAG, "ACC baseline = %.3f g", accel_baseline);
    ESP_LOGI(TAG, "Reference Roll = %.2f deg", reference_roll);
    ESP_LOGI(TAG, "Reference Pitch = %.2f deg", reference_pitch);
    ESP_LOGI(TAG, "Reference vector = [%.3f, %.3f, %.3f]",
             reference_ax, reference_ay, reference_az);
    ESP_LOGI(TAG, "========================================");
}

// =====================================================
// POSE 3D
// =====================================================
static float calculate_posture_angle(float ax, float ay, float az)
{
    float current_length = sqrtf(ax * ax + ay * ay + az * az);

    if (current_length < 0.1f)
        return 0.0f;

    float current_ax = ax / current_length;
    float current_ay = ay / current_length;
    float current_az = az / current_length;

    float dot =
        current_ax * reference_ax +
        current_ay * reference_ay +
        current_az * reference_az;

    if (dot > 1.0f) dot = 1.0f;
    if (dot < -1.0f) dot = -1.0f;

    return acosf(dot) * RAD_TO_DEG;
}

// =====================================================
// FALL DETECTION STATE MACHINE - V3
//
// Diem khac V2:
// - POSTURE KHONG yeu cau GYRO thap / nam im lien tuc.
// - Nguoi bi te co the nhuc nhich, lan nhe, co nguoi...
// - Neu POSE bat thuong >= 45 deg khi ACC dang tin, ta CONG DON thoi gian.
// - Chi huy ve NORMAL neu POSE < 30 deg lien tuc 1.2 giay.
// - Sau 2.5 giay bang chung POSE bat thuong cong don -> FALL_DETECTED.
// - Ghi them LOW-G duration va LOW-G -> IMPACT de thu du lieu cho V3.x sau.
// =====================================================
static void process_fall_detection(float normalized_acc,
                                   float total_gyro,
                                   float posture_angle)
{
    int64_t now_ms = millis_now();

    if (normalized_acc > peak_acc)
        peak_acc = normalized_acc;

    if (total_gyro > peak_gyro)
        peak_gyro = total_gyro;

    // =================================================
    // NORMAL
    // =================================================
    if (fall_state == STATE_NORMAL)
    {
        peak_acc = normalized_acc;
        peak_gyro = total_gyro;

        if (normalized_acc < FALL_LOW_G_THRESHOLD)
        {
            if (low_g_counter == 0)
                low_g_candidate_start_ms = now_ms;

            low_g_counter++;
        }
        else
        {
            low_g_counter = 0;
            low_g_candidate_start_ms = 0;
        }

        if (low_g_counter >= FALL_LOW_G_SAMPLES)
        {
            fall_low_g_start_ms =
                (low_g_candidate_start_ms > 0)
                    ? low_g_candidate_start_ms
                    : now_ms;

            fall_low_g_last_ms = now_ms;

            ESP_LOGW(TAG,
                     "LOW-G! ACC = %.2f g (bat dau tai %lld ms)",
                     normalized_acc,
                     (long long)fall_low_g_start_ms);

            low_g_counter = 0;
            low_g_candidate_start_ms = 0;
            peak_acc = normalized_acc;
            peak_gyro = total_gyro;
            change_state(STATE_FALLING);
            return;
        }

        // Nhanh impact truc tiep van duoc giu de tiep tuc thu nghiem.
        if (normalized_acc > DIRECT_IMPACT_THRESHOLD &&
            total_gyro > ROTATION_THRESHOLD_DPS)
        {
            ESP_LOGW(TAG,
                     "STRONG IMPACT! ACC=%.2f GYRO=%.1f (khong co LOW-G truoc)",
                     normalized_acc,
                     total_gyro);

            fall_low_g_start_ms = 0;
            fall_low_g_last_ms = 0;
            low_g_duration_ms = 0;
            low_g_to_impact_ms = 0;
            peak_acc = normalized_acc;
            peak_gyro = total_gyro;
            change_state(STATE_IMPACT);
            return;
        }
    }

    // =================================================
    // FALLING
    // =================================================
    else if (fall_state == STATE_FALLING)
    {
        int64_t elapsed = now_ms - state_start_ms;

        if (normalized_acc < FALL_LOW_G_THRESHOLD)
            fall_low_g_last_ms = now_ms;

        if (normalized_acc > IMPACT_THRESHOLD)
        {
            low_g_to_impact_ms = 0;
            low_g_duration_ms = 0;

            if (fall_low_g_start_ms > 0)
            {
                low_g_to_impact_ms = now_ms - fall_low_g_start_ms;

                if (fall_low_g_last_ms >= fall_low_g_start_ms)
                    low_g_duration_ms =
                        fall_low_g_last_ms - fall_low_g_start_ms;
            }

            ESP_LOGW(TAG,
                     "IMPACT DETECTED! ACC = %.2f g",
                     normalized_acc);

            if (fall_low_g_start_ms > 0)
            {
                ESP_LOGI(TAG,
                         "TIMING: LOW-G duration = %lld ms | LOW-G -> IMPACT = %lld ms",
                         (long long)low_g_duration_ms,
                         (long long)low_g_to_impact_ms);
            }

            change_state(STATE_IMPACT);
            return;
        }

        if (elapsed > FALLING_TIMEOUT_MS)
        {
            ESP_LOGI(TAG, "Khong co va cham -> huy FALLING");
            reset_fall_detection();
            return;
        }
    }

    // =================================================
    // IMPACT
    // =================================================
    else if (fall_state == STATE_IMPACT)
    {
        int64_t elapsed = now_ms - state_start_ms;

        // Dung POSE 3D + dinh xoay de vao giai doan theo doi sau va cham.
        if (posture_angle > POSTURE_THRESHOLD_DEG &&
            peak_gyro > ROTATION_THRESHOLD_DPS)
        {
            ESP_LOGW(TAG,
                     "POSTURE CHANGE! POSE=%.1f deg PeakGyro=%.1f",
                     posture_angle,
                     peak_gyro);

            change_state(STATE_POSTURE);
            return;
        }

        if (elapsed > IMPACT_TIMEOUT_MS)
        {
            ESP_LOGI(TAG,
                     "Va cham nhung POSE khong doi du lon -> NORMAL");
            reset_fall_detection();
            return;
        }
    }

    // =================================================
    // POSTURE - V3
    // =================================================
    else if (fall_state == STATE_POSTURE)
    {
        int64_t elapsed = now_ms - state_start_ms;

        int64_t sample_dt_ms = now_ms - posture_last_sample_ms;
        if (sample_dt_ms < 0 || sample_dt_ms > 100)
            sample_dt_ms = SAMPLE_PERIOD_MS;
        posture_last_sample_ms = now_ms;

        bool pose_acc_valid =
            normalized_acc >= POSE_VALID_ACC_MIN &&
            normalized_acc <= POSE_VALID_ACC_MAX;

        bool posture_abnormal =
            posture_angle >= POSTURE_HOLD_THRESHOLD_DEG;

        bool posture_near_reference =
            posture_angle < POSTURE_RETURN_THRESHOLD_DEG;

        // -------------------------------------------------
        // 1) RECOVERY V3.1
        //    KHONG huy chi vi POSE tam thoi ve gan moc ban dau.
        //    Chi ve NORMAL khi dong thoi:
        //      - POSE < 30 deg
        //      - ACC on dinh gan 1g
        //      - GYRO thap (< 25 dps)
        //      - duy tri lien tuc 2 giay
        //
        //    Neu nguoi bi te dang lan/nhuc nhich, GYRO thuong tang va
        //    bo dem recovery se reset, nen su kien van duoc giu lai.
        // -------------------------------------------------
        bool recovery_acc_stable =
            normalized_acc >= RECOVERY_ACC_MIN &&
            normalized_acc <= RECOVERY_ACC_MAX;

        bool recovery_gyro_stable =
            total_gyro < RECOVERY_GYRO_MAX_DPS;

        bool recovery_candidate =
            posture_near_reference &&
            recovery_acc_stable &&
            recovery_gyro_stable;

        if (recovery_candidate)
        {
            if (posture_return_start_ms == 0)
            {
                posture_return_start_ms = now_ms;
                ESP_LOGI(TAG,
                         "RECOVERY candidate: POSE=%.1f ACC=%.2f GYRO=%.1f -> bat dau dem",
                         posture_angle,
                         normalized_acc,
                         total_gyro);
            }

            int64_t recovery_elapsed =
                now_ms - posture_return_start_ms;

            if (recovery_elapsed >= POSTURE_RETURN_TIME_MS)
            {
                ESP_LOGI(TAG,
                         "RECOVERY xac nhan %d ms: POSE=%.1f ACC=%.2f GYRO=%.1f -> NORMAL",
                         POSTURE_RETURN_TIME_MS,
                         posture_angle,
                         normalized_acc,
                         total_gyro);
                reset_fall_detection();
                return;
            }
        }
        else
        {
            // Chi reset bo dem phuc hoi.
            // KHONG reset evidence te nga da tich luy.
            posture_return_start_ms = 0;
        }

        // -------------------------------------------------
        // 2) CONG DON bang chung POSE bat thuong.
        //    Nguoi dung duoc phep nhuc nhich / lan nhe.
        //    Chi cong khi ACC gan 1g de POSE tu accelerometer dang tin hon.
        // -------------------------------------------------
        if (pose_acc_valid && posture_abnormal)
        {
            posture_abnormal_accum_ms += sample_dt_ms;
        }

        // In tien do moi ~500 ms de de theo doi, khong spam Serial.
        if (posture_last_progress_log_ms == 0 ||
            (now_ms - posture_last_progress_log_ms) >= 500)
        {
            ESP_LOGI(TAG,
                     "POSTURE V3.1: POSE=%.1f deg | GYRO=%.1f | evidence=%lld/%d ms",
                     posture_angle,
                     total_gyro,
                     (long long)posture_abnormal_accum_ms,
                     POSTURE_EVIDENCE_TIME_MS);

            posture_last_progress_log_ms = now_ms;
        }

        if (posture_abnormal_accum_ms >= POSTURE_EVIDENCE_TIME_MS)
        {
            final_pose = posture_angle;

            ESP_LOGE(TAG, "========================================");
            ESP_LOGE(TAG, "!!! FALL DETECTED !!!");
            ESP_LOGE(TAG, "Peak ACC  = %.2f g", peak_acc);
            ESP_LOGE(TAG, "Peak GYRO = %.1f dps", peak_gyro);
            ESP_LOGE(TAG, "Final POSE = %.1f deg", final_pose);
            ESP_LOGE(TAG,
                     "Abnormal POSE evidence = %lld ms",
                     (long long)posture_abnormal_accum_ms);
            ESP_LOGE(TAG, "========================================");

            change_state(STATE_FALL_DETECTED);
            return;
        }

        // -------------------------------------------------
        // 3) TIMEOUT: neu het 12 giay ma khong du bang chung va cung
        //    khong tro lai gan tu the ban dau thi su kien chua chac chan.
        //    V3.1 cho ve NORMAL de tranh ket POSTURE vo han.
        // -------------------------------------------------
        if (elapsed > POSTURE_TIMEOUT_MS)
        {
            ESP_LOGI(TAG,
                     "POSTURE timeout: evidence=%lld ms, chua du xac nhan -> NORMAL",
                     (long long)posture_abnormal_accum_ms);
            reset_fall_detection();
            return;
        }
    }

    // =================================================
    // FALL DETECTED
    // =================================================
    else if (fall_state == STATE_FALL_DETECTED)
    {
        // LATched: giu nguyen FALL_DETECTED cho den khi bam CANCEL.
        // Nhuc nhich / doi POSE / ACC / GYRO khong tu reset.
    }
}

// =====================================================
// APP MAIN
// =====================================================
void app_main(void)
{
    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG, "HE THONG PHAT HIEN TE NGA - VERSION 3.1");
    ESP_LOGI(TAG, "Cloud confirmation firmware: Phase 6.1, 30s device deadline");
    ESP_LOGI(TAG, "ESP32-C3 + MPU6500 + POSE 3D V3.1 + LED/BUZZER + CANCEL");
    ESP_LOGI(TAG, "========================================");
    ESP_LOGI(TAG,
             "V3.1 recovery: POSE<%.0f deg + ACC %.2f..%.2f g + GYRO<%.0f dps trong %d ms",
             POSTURE_RETURN_THRESHOLD_DEG,
             RECOVERY_ACC_MIN,
             RECOVERY_ACC_MAX,
             RECOVERY_GYRO_MAX_DPS,
             POSTURE_RETURN_TIME_MS);
    ESP_LOGI(TAG, "POSTURE timeout = %d ms", POSTURE_TIMEOUT_MS);

    // 0. ALERT OUTPUTS + CANCEL BUTTON
    alert_outputs_init();
    cancel_button_init();
    manual_sos_init(&manual_sos);

    // 0b. NETWORKING (event-driven, khong cho ket noi trong app_main)
    esp_err_t nvs_err = nvs_flash_init();
    if (nvs_err == ESP_ERR_NVS_NO_FREE_PAGES ||
        nvs_err == ESP_ERR_NVS_NEW_VERSION_FOUND)
    {
        nvs_err = nvs_flash_erase();
        if (nvs_err == ESP_OK)
            nvs_err = nvs_flash_init();
    }

    if (nvs_err != ESP_OK)
    {
        ESP_LOGE(TAG, "NVS init failed; networking disabled: %s",
                 esp_err_to_name(nvs_err));
    }
    else
    {
        esp_err_t wifi_err = wifi_manager_init();
        if (wifi_err != ESP_OK)
            ESP_LOGE(TAG, "Wi-Fi init failed; sensor continues: %s",
                     esp_err_to_name(wifi_err));

        esp_err_t mqtt_err = mqtt_manager_init();
        if (mqtt_err != ESP_OK)
            ESP_LOGE(TAG, "MQTT init failed; sensor continues: %s",
                     esp_err_to_name(mqtt_err));

        esp_err_t cloud_err = cloud_event_service_init();
        if (cloud_err != ESP_OK)
            ESP_LOGE(TAG, "Cloud event init failed; sensor continues: %s",
                     esp_err_to_name(cloud_err));
    }

    // 1. I2C BUS
    i2c_master_bus_config_t bus_config = {
        .i2c_port = I2C_NUM_0,
        .sda_io_num = I2C_SDA,
        .scl_io_num = I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };

    i2c_master_bus_handle_t bus_handle;
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_config, &bus_handle));

    ESP_LOGI(TAG, "I2C OK");
    ESP_LOGI(TAG, "SDA = GPIO6");
    ESP_LOGI(TAG, "SCL = GPIO7");

    // 2. ADD SENSOR
    i2c_device_config_t imu_config = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = IMU_ADDR,
        .scl_speed_hz = 100000,
    };

    i2c_master_dev_handle_t imu_handle;
    ESP_ERROR_CHECK(
        i2c_master_bus_add_device(
            bus_handle,
            &imu_config,
            &imu_handle
        )
    );

    // 3. PROBE
    esp_err_t ret = i2c_master_probe(bus_handle, IMU_ADDR, 100);
    if (ret != ESP_OK)
    {
        ESP_LOGE(TAG, "Khong tim thay IMU!");
        return;
    }

    ESP_LOGI(TAG, "Tim thay IMU tai 0x68");

    // 4. WAKE
    ESP_ERROR_CHECK(
        imu_write_reg(imu_handle, REG_PWR_MGMT_1, 0x00)
    );
    vTaskDelay(pdMS_TO_TICKS(100));

    // 5. WHO AM I
    uint8_t who_am_i = 0;
    ESP_ERROR_CHECK(
        imu_read_reg(
            imu_handle,
            REG_WHO_AM_I,
            &who_am_i,
            1
        )
    );

    ESP_LOGI(TAG, "WHO_AM_I = 0x%02X", who_am_i);

    if (who_am_i == 0x68)
        ESP_LOGI(TAG, "MPU6050 detected");
    else if (who_am_i == 0x70)
        ESP_LOGI(TAG, "MPU6500 detected");
    else
    {
        ESP_LOGE(TAG, "Unknown IMU!");
        return;
    }

    // 6. CONFIG
    ESP_ERROR_CHECK(imu_write_reg(imu_handle, REG_SMPLRT_DIV, 9));
    ESP_ERROR_CHECK(imu_write_reg(imu_handle, REG_CONFIG, 0x03));
    ESP_ERROR_CHECK(imu_write_reg(imu_handle, REG_GYRO_CONFIG, 0x10));
    ESP_ERROR_CHECK(imu_write_reg(imu_handle, REG_ACCEL_CONFIG, 0x10));
    ESP_ERROR_CHECK(imu_write_reg(imu_handle, REG_ACCEL_CONFIG2, 0x03));

    vTaskDelay(pdMS_TO_TICKS(100));

    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "Accelerometer = +-8g");
    ESP_LOGI(TAG, "Gyroscope     = +-1000 dps");
    ESP_LOGI(TAG, "Sampling      = 100 Hz");

    // 7. CALIBRATION
    calibrate_sensor(imu_handle);
    reset_fall_detection();

    ESP_LOGI(TAG, "");
    ESP_LOGI(TAG, "SYSTEM READY");
    ESP_LOGI(TAG, "");

    TickType_t last_wake_time = xTaskGetTickCount();
    int64_t previous_time_us = esp_timer_get_time();
    int64_t last_telemetry_ms = 0;
    int print_counter = 0;

    while (1)
    {
        int16_t raw_ax, raw_ay, raw_az;
        int16_t raw_gx, raw_gy, raw_gz;

        ret = imu_read_raw(
            imu_handle,
            &raw_ax, &raw_ay, &raw_az,
            &raw_gx, &raw_gy, &raw_gz
        );

        if (ret != ESP_OK)
        {
            ESP_LOGE(TAG,
                     "Read IMU error: %s",
                     esp_err_to_name(ret));
            process_latched_fall_controls();
            update_alert_outputs();
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        // DELTA TIME
        int64_t current_time_us = esp_timer_get_time();
        float dt = (current_time_us - previous_time_us) / 1000000.0f;
        previous_time_us = current_time_us;

        if (dt <= 0.0f || dt > 0.05f)
            dt = 0.01f;

        // ACCEL
        float ax = raw_ax / ACCEL_SCALE;
        float ay = raw_ay / ACCEL_SCALE;
        float az = raw_az / ACCEL_SCALE;

        float total_acc = sqrtf(ax * ax + ay * ay + az * az);
        float normalized_acc = total_acc / accel_baseline;

        // POSE 3D
        float posture_angle = calculate_posture_angle(ax, ay, az);

        // GYRO
        float gx = (raw_gx / GYRO_SCALE) - gyro_offset_x;
        float gy = (raw_gy / GYRO_SCALE) - gyro_offset_y;
        float gz = (raw_gz / GYRO_SCALE) - gyro_offset_z;

        float total_gyro = sqrtf(gx * gx + gy * gy + gz * gz);

        // ROLL / PITCH de theo doi tren Serial
        float roll_acc = atan2f(ay, az) * RAD_TO_DEG;
        float pitch_acc = atan2f(
            -ax,
            sqrtf(ay * ay + az * az)
        ) * RAD_TO_DEG;

        roll = FILTER_ALPHA * (roll + gx * dt)
             + (1.0f - FILTER_ALPHA) * roll_acc;

        pitch = FILTER_ALPHA * (pitch + gy * dt)
              + (1.0f - FILTER_ALPHA) * pitch_acc;

        // STATE MACHINE V3.1: POSTURE cho phep nguoi bi te tiep tuc cu dong
        fall_state_t state_before_processing = fall_state;

        process_fall_detection(
            normalized_acc,
            total_gyro,
            posture_angle
        );

        // V2.5: vua vao FALL_DETECTED thi khoa CANCEL 2 giay va re-arm bo loc nut.
        // Nguoi dung bam giu khoang 0.6 giay roi nha nut de CANCEL.
        if (state_before_processing != STATE_FALL_DETECTED &&
            fall_state == STATE_FALL_DETECTED)
        {
            cancel_button_rearm();
        }

        process_latched_fall_controls();

        // FALL_DETECTED -> bat LED do + buzzer.
        // Khi he thong tro ve NORMAL, canh bao se tat.
        update_alert_outputs();

        // Telemetry chi enqueue moi 1 giay; khong publish nang trong loop 100 Hz.
        int64_t telemetry_now_ms = millis_now();
        if ((telemetry_now_ms - last_telemetry_ms) >=
            MQTT_TELEMETRY_INTERVAL_MS)
        {
            last_telemetry_ms = telemetry_now_ms;
            mqtt_publish_telemetry(normalized_acc,
                                   total_gyro,
                                   posture_angle,
                                   state_to_string(fall_state),
                                   telemetry_now_ms);
        }

        // PRINT 10 Hz
        print_counter++;
        if (print_counter >= 10)
        {
            printf(
                "ACC:%5.2f | "
                "GYRO:%7.1f | "
                "ROLL:%7.1f | "
                "PITCH:%7.1f | "
                "POSE:%6.1f | "
                "STATE:%s\n",
                normalized_acc,
                total_gyro,
                roll,
                pitch,
                posture_angle,
                state_to_string(fall_state)
            );

            print_counter = 0;
        }

        vTaskDelayUntil(
            &last_wake_time,
            pdMS_TO_TICKS(SAMPLE_PERIOD_MS)
        );
    }
}
