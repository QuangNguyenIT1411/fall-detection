#include "cloud_event_service.h"

#include <stdio.h>
#include <string.h>

#include "app_config.h"
#include "cJSON.h"
#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "wifi_manager.h"

#define CLOUD_EVENT_QUEUE_LENGTH 4
#define CLOUD_SOS_QUEUE_LENGTH 8
#define CLOUD_EVENT_TASK_STACK_SIZE 8192
#define CLOUD_EVENT_TASK_PRIORITY 4
#define CLOUD_EVENT_URL_SIZE 192
#define CLOUD_EVENT_PAYLOAD_SIZE 384
#define CLOUD_EVENT_RESPONSE_SIZE 512
#define CLOUD_EVENT_ID_SIZE 37
#define CLOUD_HEARTBEAT_INTERVAL_MS 20000

typedef enum
{
    CLOUD_ACTION_CREATE_FALL = 0,
    CLOUD_ACTION_CANCEL_FALL,
    CLOUD_ACTION_CONFIRM_FALL,
} cloud_action_type_t;

typedef struct
{
    cloud_action_type_t type;
    cloud_fall_event_t fall;
} cloud_action_t;

typedef struct
{
    bool active;
    bool cancel_pending;
    bool confirm_pending;
    cloud_fall_event_t fall;
    char event_id[CLOUD_EVENT_ID_SIZE];
    unsigned int retry_index;
    int64_t next_attempt_ms;
} cloud_lifecycle_t;

typedef struct
{
    bool active;
    char request_key[CLOUD_EVENT_ID_SIZE];
    unsigned int retry_index;
    int64_t next_attempt_ms;
} cloud_sos_t;

typedef struct
{
    char data[CLOUD_EVENT_RESPONSE_SIZE];
    size_t length;
    bool truncated;
} http_response_buffer_t;

static const char *TAG = "CLOUD_EVENT";
#if CLOUD_EVENT_ENABLED
static QueueHandle_t s_action_queue = NULL;
static QueueHandle_t s_sos_queue = NULL;

static int64_t uptime_ms(void)
{
    return esp_timer_get_time() / 1000;
}

static const int64_t RETRY_DELAYS_MS[] = {5000, 10000, 30000};

static bool format_ok(int written, size_t capacity)
{
    return written >= 0 && (size_t)written < capacity;
}

static bool valid_uuid(const char *value)
{
    if (value == NULL || strlen(value) != 36)
        return false;

    for (size_t i = 0; i < 36; i++)
    {
        if (i == 8 || i == 13 || i == 18 || i == 23)
        {
            if (value[i] != '-')
                return false;
        }
        else if (!((value[i] >= '0' && value[i] <= '9') ||
                   (value[i] >= 'a' && value[i] <= 'f') ||
                   (value[i] >= 'A' && value[i] <= 'F')))
        {
            return false;
        }
    }

    return true;
}

static esp_err_t http_event_handler(esp_http_client_event_t *event)
{
    if (event->event_id != HTTP_EVENT_ON_DATA || event->user_data == NULL)
        return ESP_OK;

    http_response_buffer_t *response = event->user_data;
    size_t available = sizeof(response->data) - response->length - 1;
    size_t copy_length = (size_t)event->data_len;
    if (copy_length > available)
    {
        copy_length = available;
        response->truncated = true;
    }

    if (copy_length > 0)
    {
        memcpy(response->data + response->length, event->data, copy_length);
        response->length += copy_length;
        response->data[response->length] = '\0';
    }

    return ESP_OK;
}

static esp_err_t post_json(const char *function_name,
                           const char *payload,
                           http_response_buffer_t *response,
                           int *status_code)
{
    char url[CLOUD_EVENT_URL_SIZE];
    int written = snprintf(url,
                           sizeof(url),
                           "%s/%s",
                           SUPABASE_FUNCTION_BASE_URL,
                           function_name);
    if (!format_ok(written, sizeof(url)))
        return ESP_ERR_INVALID_SIZE;

    memset(response, 0, sizeof(*response));
    *status_code = 0;

    esp_http_client_config_t config = {
        .url = url,
        .method = HTTP_METHOD_POST,
        .event_handler = http_event_handler,
        .user_data = response,
        .crt_bundle_attach = esp_crt_bundle_attach,
        .timeout_ms = CLOUD_EVENT_HTTP_TIMEOUT_MS,
        .buffer_size = CLOUD_EVENT_RESPONSE_SIZE,
    };

    esp_http_client_handle_t client = esp_http_client_init(&config);
    if (client == NULL)
        return ESP_FAIL;

    esp_err_t err = esp_http_client_set_header(client,
                                               "Content-Type",
                                               "application/json");
    if (err == ESP_OK)
        err = esp_http_client_set_header(client, "X-Device-Code", DEVICE_CODE);
    if (err == ESP_OK)
        err = esp_http_client_set_header(client, "X-Device-Key", DEVICE_API_KEY);
    if (err == ESP_OK)
        err = esp_http_client_set_post_field(client, payload, strlen(payload));
    if (err == ESP_OK)
        err = esp_http_client_perform(client);

    if (err == ESP_OK)
        *status_code = esp_http_client_get_status_code(client);

    esp_http_client_cleanup(client);

    if (response->truncated)
    {
        ESP_LOGW(TAG, "Cloud response was too large");
        return ESP_ERR_INVALID_SIZE;
    }

    return err;
}

static bool submit_create(const cloud_fall_event_t *fall,
                          char event_id[CLOUD_EVENT_ID_SIZE])
{
    char payload[CLOUD_EVENT_PAYLOAD_SIZE];
    int written = snprintf(payload,
                           sizeof(payload),
                           "{\"peak_acc\":%.2f,\"peak_gyro\":%.1f,"
                           "\"final_pose\":%.1f,\"low_g_duration_ms\":%lld,"
                           "\"low_g_to_impact_ms\":%lld,\"device_uptime_ms\":%lld}",
                           fall->peak_acc,
                           fall->peak_gyro,
                           fall->final_pose,
                           (long long)fall->low_g_duration_ms,
                           (long long)fall->low_g_to_impact_ms,
                           (long long)fall->device_uptime_ms);
    if (!format_ok(written, sizeof(payload)))
    {
        ESP_LOGE(TAG, "Fall event payload truncated");
        return false;
    }

    http_response_buffer_t response;
    int status_code = 0;
    esp_err_t err = post_json("create-fall-event",
                              payload,
                              &response,
                              &status_code);
    if (err != ESP_OK || status_code != 201)
    {
        ESP_LOGW(TAG,
                 "Create fall upload failed: transport=%s http=%d",
                 esp_err_to_name(err),
                 status_code);
        return false;
    }

    cJSON *root = cJSON_Parse(response.data);
    cJSON *success = root ? cJSON_GetObjectItemCaseSensitive(root, "success") : NULL;
    cJSON *id = root ? cJSON_GetObjectItemCaseSensitive(root, "event_id") : NULL;
    bool valid = cJSON_IsTrue(success) &&
                 cJSON_IsString(id) &&
                 valid_uuid(id->valuestring);

    if (valid)
        snprintf(event_id, CLOUD_EVENT_ID_SIZE, "%s", id->valuestring);

    cJSON_Delete(root);

    if (!valid)
    {
        ESP_LOGW(TAG, "Create fall response is invalid");
        return false;
    }

    ESP_LOGI(TAG, "Fall event uploaded: %s", event_id);
    return true;
}

static bool submit_cancel(const char *event_id)
{
    char payload[CLOUD_EVENT_PAYLOAD_SIZE];
    int written = snprintf(payload,
                           sizeof(payload),
                           "{\"event_id\":\"%s\"}",
                           event_id);
    if (!format_ok(written, sizeof(payload)))
        return false;

    http_response_buffer_t response;
    int status_code = 0;
    esp_err_t err = post_json("cancel-fall-event",
                              payload,
                              &response,
                              &status_code);
    if (err != ESP_OK || status_code != 200)
    {
        ESP_LOGW(TAG,
                 "Cancel upload failed: transport=%s http=%d",
                 esp_err_to_name(err),
                 status_code);
        return false;
    }

    cJSON *root = cJSON_Parse(response.data);
    cJSON *success = root ? cJSON_GetObjectItemCaseSensitive(root, "success") : NULL;
    cJSON *status = root ? cJSON_GetObjectItemCaseSensitive(root, "status") : NULL;
    bool valid = cJSON_IsTrue(success) &&
                 cJSON_IsString(status) &&
                 strcmp(status->valuestring, "CANCELLED") == 0;
    cJSON_Delete(root);

    if (!valid)
    {
        ESP_LOGW(TAG, "Cancel response is invalid");
        return false;
    }

    ESP_LOGI(TAG, "Cancel event uploaded");
    return true;
}

static bool submit_confirm(const char *event_id)
{
    char payload[CLOUD_EVENT_PAYLOAD_SIZE];
    int written = snprintf(payload,
                           sizeof(payload),
                           "{\"event_id\":\"%s\"}",
                           event_id);
    if (!format_ok(written, sizeof(payload)))
        return false;

    http_response_buffer_t response;
    int status_code = 0;
    esp_err_t err = post_json("confirm-fall-event",
                              payload,
                              &response,
                              &status_code);
    ESP_LOGI(TAG,
             "Cloud confirm HTTP status=%d transport=%s",
             status_code,
             esp_err_to_name(err));
    if (err != ESP_OK || status_code != 200)
    {
        ESP_LOGW(TAG,
                 "Confirm upload failed: transport=%s http=%d",
                 esp_err_to_name(err),
                 status_code);
        return false;
    }

    cJSON *root = cJSON_Parse(response.data);
    cJSON *success = root ? cJSON_GetObjectItemCaseSensitive(root, "success") : NULL;
    cJSON *status = root ? cJSON_GetObjectItemCaseSensitive(root, "status") : NULL;
    bool valid = cJSON_IsTrue(success) &&
                 cJSON_IsString(status) &&
                 strcmp(status->valuestring, "CONFIRMED") == 0;
    cJSON_Delete(root);

    if (!valid)
    {
        ESP_LOGW(TAG, "Confirm response is invalid");
        return false;
    }

    ESP_LOGI(TAG, "Cloud confirm success: event_id=%s", event_id);
    return true;
}

static bool submit_heartbeat(void)
{
    http_response_buffer_t response;
    int status_code = 0;
    esp_err_t err = post_json("device-heartbeat", "{}", &response, &status_code);
    if (err != ESP_OK || status_code != 200)
    {
        ESP_LOGW(TAG, "Heartbeat failed: transport=%s http=%d",
                 esp_err_to_name(err), status_code);
        return false;
    }
    cJSON *root = cJSON_Parse(response.data);
    cJSON *success = root ? cJSON_GetObjectItemCaseSensitive(root, "success") : NULL;
    bool valid = cJSON_IsTrue(success);
    cJSON_Delete(root);
    if (!valid)
        ESP_LOGW(TAG, "Heartbeat response invalid");
    return valid;
}

static bool submit_sos(const char *request_key)
{
    char payload[CLOUD_EVENT_PAYLOAD_SIZE];
    int written = snprintf(payload, sizeof(payload),
                           "{\"request_id\":\"%s\"}", request_key);
    if (!format_ok(written, sizeof(payload)))
        return false;

    http_response_buffer_t response;
    int status_code = 0;
    esp_err_t err = post_json("create-sos-event", payload,
                              &response, &status_code);
    if (err != ESP_OK || (status_code != 200 && status_code != 201))
    {
        ESP_LOGW(TAG, "SOS upload failed: transport=%s http=%d",
                 esp_err_to_name(err), status_code);
        return false;
    }
    cJSON *root = cJSON_Parse(response.data);
    cJSON *success = root ? cJSON_GetObjectItemCaseSensitive(root, "success") : NULL;
    cJSON *id = root ? cJSON_GetObjectItemCaseSensitive(root, "event_id") : NULL;
    cJSON *status = root ? cJSON_GetObjectItemCaseSensitive(root, "status") : NULL;
    cJSON *type = root ? cJSON_GetObjectItemCaseSensitive(root, "event_type") : NULL;
    cJSON *sent_at = root ? cJSON_GetObjectItemCaseSensitive(root, "notification_sent_at") : NULL;
    bool valid = cJSON_IsTrue(success) && cJSON_IsString(id) &&
                 valid_uuid(id->valuestring) && cJSON_IsString(status) &&
                 strcmp(status->valuestring, "CONFIRMED") == 0 &&
                 cJSON_IsString(type) && strcmp(type->valuestring, "SOS") == 0 &&
                 cJSON_IsString(sent_at);
    if (valid)
        ESP_LOGI(TAG, "SOS event delivered: %s", id->valuestring);
    cJSON_Delete(root);
    return valid;
}

static void schedule_retry(cloud_lifecycle_t *lifecycle)
{
    size_t delay_count = sizeof(RETRY_DELAYS_MS) / sizeof(RETRY_DELAYS_MS[0]);
    size_t index = lifecycle->retry_index;
    if (index >= delay_count)
        index = delay_count - 1;

    int64_t delay_ms = RETRY_DELAYS_MS[index];
    if (lifecycle->retry_index < delay_count - 1)
        lifecycle->retry_index++;

    lifecycle->next_attempt_ms = uptime_ms() + delay_ms;
    const char *operation = lifecycle->event_id[0] == '\0'
        ? "create"
        : lifecycle->cancel_pending
            ? "cancel"
            : lifecycle->confirm_pending
                ? "confirm"
                : "cloud";
    ESP_LOGW(TAG,
             "Cloud %s retry scheduled in %lld ms",
             operation,
             (long long)delay_ms);
}

static void schedule_sos_retry(cloud_sos_t *sos)
{
    size_t count = sizeof(RETRY_DELAYS_MS) / sizeof(RETRY_DELAYS_MS[0]);
    size_t index = sos->retry_index;
    if (index >= count)
        index = count - 1;
    sos->next_attempt_ms = uptime_ms() + RETRY_DELAYS_MS[index];
    if (sos->retry_index < count - 1)
        sos->retry_index++;
    ESP_LOGW(TAG, "SOS retry scheduled in %lld ms",
             (long long)RETRY_DELAYS_MS[index]);
}

static void accept_action(cloud_lifecycle_t *lifecycle,
                          const cloud_action_t *action)
{
    if (action->type == CLOUD_ACTION_CREATE_FALL)
    {
        if (lifecycle->active)
        {
            ESP_LOGE(TAG, "Previous cloud fall lifecycle is still pending");
            return;
        }

        memset(lifecycle, 0, sizeof(*lifecycle));
        lifecycle->active = true;
        lifecycle->fall = action->fall;
        lifecycle->next_attempt_ms = uptime_ms();
    }
    else if (action->type == CLOUD_ACTION_CANCEL_FALL)
    {
        if (!lifecycle->active)
        {
            ESP_LOGW(TAG, "Cancel requested without an active cloud event");
            return;
        }

        lifecycle->cancel_pending = true;
        lifecycle->confirm_pending = false;
        lifecycle->retry_index = 0;
        lifecycle->next_attempt_ms = uptime_ms();
    }
    else if (action->type == CLOUD_ACTION_CONFIRM_FALL)
    {
        if (!lifecycle->active)
        {
            ESP_LOGW(TAG, "Confirm requested without an active cloud event");
            return;
        }

        // A cancel accepted before the deadline always wins locally.
        if (lifecycle->cancel_pending)
        {
            ESP_LOGW(TAG, "Confirm ignored because cancel is pending");
            return;
        }

        lifecycle->confirm_pending = true;
        lifecycle->retry_index = 0;
        lifecycle->next_attempt_ms = uptime_ms();
        if (lifecycle->event_id[0] == '\0')
            ESP_LOGI(TAG, "Cloud confirm waiting for create event id");
        else
            ESP_LOGI(TAG,
                     "Cloud confirm accepted: event_id=%s",
                     lifecycle->event_id);
    }
}

static TickType_t worker_wait_ticks(const cloud_lifecycle_t *lifecycle,
                                    const cloud_sos_t *sos,
                                    int64_t next_heartbeat_ms)
{
    int64_t remaining_ms = next_heartbeat_ms - uptime_ms();
    if (remaining_ms <= 0)
        return 0;
    if (lifecycle->active &&
        (lifecycle->event_id[0] == '\0' || lifecycle->cancel_pending ||
         lifecycle->confirm_pending))
    {
        int64_t due = lifecycle->next_attempt_ms - uptime_ms();
        if (due < remaining_ms)
            remaining_ms = due;
    }
    if (sos->active)
    {
        int64_t due = sos->next_attempt_ms - uptime_ms();
        if (due < remaining_ms)
            remaining_ms = due;
    }
    if (remaining_ms <= 0)
        return 0;
    // Poll the independent SOS queue without blocking the sensor task.
    if (remaining_ms > 100)
        remaining_ms = 100;
    return pdMS_TO_TICKS(remaining_ms);
}

static void cloud_worker_task(void *arg)
{
    (void)arg;
    cloud_lifecycle_t lifecycle = {0};
    cloud_sos_t sos = {0};
    int64_t next_heartbeat_ms = uptime_ms();

    while (true)
    {
        cloud_action_t action;
        if (xQueueReceive(s_action_queue,
                          &action,
                          worker_wait_ticks(&lifecycle, &sos, next_heartbeat_ms)) == pdTRUE)
        {
            accept_action(&lifecycle, &action);
        }

        if (uptime_ms() >= next_heartbeat_ms)
        {
            // Single cloud worker: never more than one heartbeat in flight.
            // A failed request is retried at the next interval, without queueing.
            if (wifi_manager_is_connected())
                submit_heartbeat();
            next_heartbeat_ms = uptime_ms() + CLOUD_HEARTBEAT_INTERVAL_MS;
        }

        if (lifecycle.active && uptime_ms() >= lifecycle.next_attempt_ms &&
            (lifecycle.event_id[0] == '\0' || lifecycle.cancel_pending ||
             lifecycle.confirm_pending))
        {
            if (!wifi_manager_is_connected())
            {
                schedule_retry(&lifecycle);
            }
            else
            {
                bool success;
                if (lifecycle.event_id[0] == '\0')
                {
                    success = submit_create(&lifecycle.fall, lifecycle.event_id);
                    if (success)
                    {
                        lifecycle.retry_index = 0;
                        lifecycle.next_attempt_ms = (lifecycle.cancel_pending ||
                                                     lifecycle.confirm_pending)
                            ? uptime_ms() : 0;
                    }
                }
                else if (lifecycle.cancel_pending)
                {
                    success = submit_cancel(lifecycle.event_id);
                    if (success)
                        memset(&lifecycle, 0, sizeof(lifecycle));
                }
                else
                {
                    success = submit_confirm(lifecycle.event_id);
                    if (success)
                        memset(&lifecycle, 0, sizeof(lifecycle));
                }
                if (!success && lifecycle.active)
                    schedule_retry(&lifecycle);
            }
        }

        if (!sos.active &&
            xQueueReceive(s_sos_queue, sos.request_key, 0) == pdTRUE)
        {
            sos.active = true;
            sos.next_attempt_ms = uptime_ms();
            sos.retry_index = 0;
        }
        if (sos.active && uptime_ms() >= sos.next_attempt_ms)
        {
            if (!wifi_manager_is_connected() ||
                !submit_sos(sos.request_key))
            {
                schedule_sos_retry(&sos);
            }
            else
            {
                memset(&sos, 0, sizeof(sos));
            }
        }
    }
}
#endif

esp_err_t cloud_event_service_init(void)
{
#if !CLOUD_EVENT_ENABLED
    ESP_LOGW(TAG, "Cloud event service disabled in app_config.h");
    return ESP_OK;
#else
    if (strncmp(SUPABASE_FUNCTION_BASE_URL,
                "https://",
                strlen("https://")) != 0 ||
        strlen(DEVICE_API_KEY) < 32)
    {
        ESP_LOGE(TAG, "Cloud endpoint or device key is invalid");
        return ESP_ERR_INVALID_ARG;
    }

    s_action_queue = xQueueCreate(CLOUD_EVENT_QUEUE_LENGTH,
                                  sizeof(cloud_action_t));
    if (s_action_queue == NULL)
        return ESP_ERR_NO_MEM;

    s_sos_queue = xQueueCreate(CLOUD_SOS_QUEUE_LENGTH, CLOUD_EVENT_ID_SIZE);
    if (s_sos_queue == NULL)
    {
        vQueueDelete(s_action_queue);
        s_action_queue = NULL;
        return ESP_ERR_NO_MEM;
    }

    BaseType_t task_created = xTaskCreate(cloud_worker_task,
                                         "cloud_event",
                                         CLOUD_EVENT_TASK_STACK_SIZE,
                                         NULL,
                                         CLOUD_EVENT_TASK_PRIORITY,
                                         NULL);
    if (task_created != pdPASS)
    {
        vQueueDelete(s_action_queue);
        vQueueDelete(s_sos_queue);
        s_action_queue = NULL;
        s_sos_queue = NULL;
        return ESP_ERR_NO_MEM;
    }

    ESP_LOGI(TAG, "Cloud event worker started");
    return ESP_OK;
#endif
}

bool cloud_event_enqueue_fall(const cloud_fall_event_t *event)
{
#if !CLOUD_EVENT_ENABLED
    (void)event;
    return false;
#else
    if (event == NULL || s_action_queue == NULL)
        return false;

    cloud_action_t action = {
        .type = CLOUD_ACTION_CREATE_FALL,
        .fall = *event,
    };

    if (xQueueSend(s_action_queue, &action, 0) != pdTRUE)
    {
        ESP_LOGE(TAG, "Cloud event queue full; fall event not queued");
        return false;
    }

    ESP_LOGI(TAG, "Cloud event queued");
    return true;
#endif
}

bool cloud_event_enqueue_cancel(void)
{
#if !CLOUD_EVENT_ENABLED
    return false;
#else
    if (s_action_queue == NULL)
        return false;

    cloud_action_t action = {
        .type = CLOUD_ACTION_CANCEL_FALL,
    };

    if (xQueueSend(s_action_queue, &action, 0) != pdTRUE)
    {
        ESP_LOGE(TAG, "Cloud event queue full; cancel not queued");
        return false;
    }

    ESP_LOGI(TAG, "Cloud cancel queued");
    return true;
#endif
}

bool cloud_event_enqueue_confirm(void)
{
#if !CLOUD_EVENT_ENABLED
    return false;
#else
    if (s_action_queue == NULL)
        return false;

    cloud_action_t action = {
        .type = CLOUD_ACTION_CONFIRM_FALL,
    };

    if (xQueueSend(s_action_queue, &action, 0) != pdTRUE)
    {
        ESP_LOGE(TAG, "Cloud event queue full; confirm not queued");
        return false;
    }

    ESP_LOGI(TAG, "Cloud confirm queued");
    return true;
#endif
}

bool cloud_event_enqueue_sos(const char request_key[37])
{
#if !CLOUD_EVENT_ENABLED
    (void)request_key;
    return false;
#else
    if (s_sos_queue == NULL || !valid_uuid(request_key))
        return false;
    if (xQueueSend(s_sos_queue, request_key, 0) != pdTRUE)
    {
        return false;
    }
    ESP_LOGI(TAG, "SOS cloud action queued");
    return true;
#endif
}
