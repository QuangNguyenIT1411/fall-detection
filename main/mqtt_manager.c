#include "mqtt_manager.h"

#include <stdio.h>
#include <string.h>

#include "app_config.h"
#include "esp_crt_bundle.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "mqtt_client.h"

#define MQTT_TOPIC_BUFFER_SIZE 96
#define MQTT_PAYLOAD_BUFFER_SIZE 256
#define MQTT_STATE_BUFFER_SIZE 24

static const char *TAG = "MQTT_MANAGER";
static esp_mqtt_client_handle_t s_client = NULL;
static volatile bool s_connected = false;
#if MQTT_ENABLED
static unsigned int s_connection_error_count = 0;
#endif

static char s_telemetry_topic[MQTT_TOPIC_BUFFER_SIZE];
static char s_state_topic[MQTT_TOPIC_BUFFER_SIZE];
static char s_status_topic[MQTT_TOPIC_BUFFER_SIZE];
#if MQTT_ENABLED
static char s_lwt_payload[MQTT_PAYLOAD_BUFFER_SIZE];
#endif
static char s_current_state[MQTT_STATE_BUFFER_SIZE] = "NORMAL";

#if MQTT_ENABLED
static int64_t uptime_ms(void)
{
    return esp_timer_get_time() / 1000;
}
#endif

static bool format_ok(int written, size_t capacity)
{
    return written >= 0 && (size_t)written < capacity;
}

#if MQTT_ENABLED
static bool build_topic(char *buffer, size_t capacity, const char *suffix)
{
    int written = snprintf(buffer,
                           capacity,
                           "fall/%s/%s",
                           DEVICE_CODE,
                           suffix);
    return format_ok(written, capacity);
}
#endif

static int enqueue_message(const char *topic,
                           const char *payload,
                           int qos,
                           bool retain,
                           bool store)
{
    if (!s_connected || s_client == NULL)
        return -1;

    return esp_mqtt_client_enqueue(s_client,
                                   topic,
                                   payload,
                                   0,
                                   qos,
                                   retain ? 1 : 0,
                                   store);
}

bool mqtt_manager_is_connected(void)
{
    return s_connected;
}

int mqtt_publish_telemetry(float acc,
                           float gyro,
                           float pose,
                           const char *state,
                           int64_t timestamp_ms)
{
    if (!s_connected)
        return -1;

    char payload[MQTT_PAYLOAD_BUFFER_SIZE];
    int written = snprintf(payload,
                           sizeof(payload),
                           "{\"device_id\":\"%s\",\"acc\":%.2f,\"gyro\":%.1f,"
                           "\"pose\":%.1f,\"state\":\"%s\",\"timestamp\":%lld}",
                           DEVICE_CODE,
                           acc,
                           gyro,
                           pose,
                           state,
                           (long long)timestamp_ms);
    if (!format_ok(written, sizeof(payload)))
    {
        ESP_LOGW(TAG, "Telemetry payload truncated");
        return -1;
    }

    return enqueue_message(s_telemetry_topic, payload, 0, false, true);
}

int mqtt_publish_state(const char *state, int64_t timestamp_ms)
{
    if (state == NULL)
        return -1;

    if (state != s_current_state)
    {
        int state_written = snprintf(s_current_state,
                                     sizeof(s_current_state),
                                     "%s",
                                     state);
        if (!format_ok(state_written, sizeof(s_current_state)))
        {
            ESP_LOGW(TAG, "State name too long");
            return -1;
        }
    }

    if (!s_connected)
        return -1;

    char payload[MQTT_PAYLOAD_BUFFER_SIZE];
    int written = snprintf(payload,
                           sizeof(payload),
                           "{\"device_id\":\"%s\",\"state\":\"%s\",\"timestamp\":%lld}",
                           DEVICE_CODE,
                           s_current_state,
                           (long long)timestamp_ms);
    if (!format_ok(written, sizeof(payload)))
    {
        ESP_LOGW(TAG, "State payload truncated");
        return -1;
    }

    int message_id = enqueue_message(s_state_topic, payload, 1, true, true);
    if (message_id >= 0)
        ESP_LOGI(TAG, "Published state: %s", s_current_state);
    return message_id;
}

int mqtt_publish_status(bool online, int64_t timestamp_ms)
{
    if (!s_connected)
        return -1;

    char payload[MQTT_PAYLOAD_BUFFER_SIZE];
    int written = snprintf(payload,
                           sizeof(payload),
                           "{\"device_id\":\"%s\",\"online\":%s,\"timestamp\":%lld}",
                           DEVICE_CODE,
                           online ? "true" : "false",
                           (long long)timestamp_ms);
    if (!format_ok(written, sizeof(payload)))
    {
        ESP_LOGW(TAG, "Status payload truncated");
        return -1;
    }

    return enqueue_message(s_status_topic, payload, 1, true, true);
}

#if MQTT_ENABLED
static void mqtt_event_handler(void *handler_args,
                               esp_event_base_t base,
                               int32_t event_id,
                               void *event_data)
{
    (void)handler_args;
    (void)base;
    (void)event_data;

    switch ((esp_mqtt_event_id_t)event_id)
    {
        case MQTT_EVENT_CONNECTED:
            s_connected = true;
            s_connection_error_count = 0;
            ESP_LOGI(TAG, "MQTT connected");
            mqtt_publish_status(true, uptime_ms());
            mqtt_publish_state(s_current_state, uptime_ms());
            break;

        case MQTT_EVENT_DISCONNECTED:
            if (s_connected)
                ESP_LOGW(TAG, "MQTT disconnected; reconnecting");
            s_connected = false;
            break;

        case MQTT_EVENT_ERROR:
            s_connection_error_count++;
            if (s_connection_error_count == 1 ||
                (s_connection_error_count % 10) == 0)
            {
                ESP_LOGW(TAG,
                         "MQTT connection error; reconnecting (attempt %u)",
                         s_connection_error_count);
            }
            break;

        default:
            break;
    }
}
#endif

esp_err_t mqtt_manager_init(void)
{
#if !MQTT_ENABLED
    ESP_LOGW(TAG, "MQTT disabled in app_config.h");
    return ESP_OK;
#else
    if (strncmp(MQTT_BROKER_URI, "mqtts://", strlen("mqtts://")) != 0 ||
        strlen(MQTT_USERNAME) == 0 ||
        strlen(MQTT_PASSWORD) == 0)
    {
        ESP_LOGE(TAG, "MQTT TLS endpoint or credentials are invalid");
        return ESP_ERR_INVALID_ARG;
    }

    if (!build_topic(s_telemetry_topic, sizeof(s_telemetry_topic), "telemetry") ||
        !build_topic(s_state_topic, sizeof(s_state_topic), "state") ||
        !build_topic(s_status_topic, sizeof(s_status_topic), "status"))
    {
        ESP_LOGE(TAG, "MQTT topic is too long");
        return ESP_ERR_INVALID_SIZE;
    }

    int lwt_written = snprintf(s_lwt_payload,
                               sizeof(s_lwt_payload),
                               "{\"device_id\":\"%s\",\"online\":false,\"timestamp\":%lld}",
                               DEVICE_CODE,
                               (long long)uptime_ms());
    if (!format_ok(lwt_written, sizeof(s_lwt_payload)))
        return ESP_ERR_INVALID_SIZE;

    const esp_mqtt_client_config_t mqtt_config = {
        .broker = {
            .address.uri = MQTT_BROKER_URI,
            .verification.crt_bundle_attach = esp_crt_bundle_attach,
        },
        .credentials = {
            .username = MQTT_USERNAME,
            .authentication.password = MQTT_PASSWORD,
        },
        .session = {
            .last_will = {
                .topic = s_status_topic,
                .msg = s_lwt_payload,
                .msg_len = 0,
                .qos = 1,
                .retain = 1,
            },
        },
        .network = {
            .reconnect_timeout_ms = MQTT_RECONNECT_TIMEOUT_MS,
            .disable_auto_reconnect = false,
        },
    };

    s_client = esp_mqtt_client_init(&mqtt_config);
    if (s_client == NULL)
        return ESP_FAIL;

    esp_err_t err = esp_mqtt_client_register_event(s_client,
                                                   ESP_EVENT_ANY_ID,
                                                   mqtt_event_handler,
                                                   NULL);
    if (err != ESP_OK)
        return err;

    err = esp_mqtt_client_start(s_client);
    if (err == ESP_OK)
        ESP_LOGI(TAG, "MQTT client started (TLS/TCP, event-driven)");
    return err;
#endif
}
