#include "wifi_manager.h"

#include <stdio.h>
#include <string.h>

#include "app_config.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_wifi.h"

static const char *TAG = "WIFI_MANAGER";
static volatile bool s_connected = false;
static unsigned int s_disconnect_count = 0;

static void wifi_event_handler(void *arg,
                               esp_event_base_t event_base,
                               int32_t event_id,
                               void *event_data)
{
    (void)arg;
    (void)event_data;

    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START)
    {
        esp_err_t err = esp_wifi_connect();
        if (err != ESP_OK)
            ESP_LOGW(TAG, "WIFI initial connect failed: %s", esp_err_to_name(err));
    }
    else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED)
    {
        s_connected = false;
        s_disconnect_count++;

        // Log the first disconnect and then only every tenth retry.
        if (s_disconnect_count == 1 || (s_disconnect_count % 10) == 0)
        {
            ESP_LOGW(TAG,
                     "WIFI disconnected; reconnecting (attempt %u)",
                     s_disconnect_count);
        }

        esp_err_t err = esp_wifi_connect();
        if (err != ESP_OK && (s_disconnect_count % 10) == 1)
            ESP_LOGW(TAG, "WIFI reconnect request failed: %s", esp_err_to_name(err));
    }
    else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP)
    {
        const ip_event_got_ip_t *event = (const ip_event_got_ip_t *)event_data;
        s_connected = true;
        s_disconnect_count = 0;
        ESP_LOGI(TAG, "WIFI connected, IP=" IPSTR, IP2STR(&event->ip_info.ip));
    }
}

bool wifi_manager_is_connected(void)
{
    return s_connected;
}

esp_err_t wifi_manager_init(void)
{
    if (strlen(WIFI_SSID) == 0 || strlen(WIFI_SSID) >= sizeof(((wifi_config_t *)0)->sta.ssid) ||
        strlen(WIFI_PASSWORD) >= sizeof(((wifi_config_t *)0)->sta.password))
    {
        ESP_LOGE(TAG, "Invalid Wi-Fi SSID/password length");
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE)
        return err;

    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE)
        return err;

    if (esp_netif_create_default_wifi_sta() == NULL)
        return ESP_FAIL;

    wifi_init_config_t init_config = WIFI_INIT_CONFIG_DEFAULT();
    err = esp_wifi_init(&init_config);
    if (err != ESP_OK)
        return err;

    err = esp_event_handler_instance_register(WIFI_EVENT,
                                              ESP_EVENT_ANY_ID,
                                              wifi_event_handler,
                                              NULL,
                                              NULL);
    if (err != ESP_OK)
        return err;

    err = esp_event_handler_instance_register(IP_EVENT,
                                              IP_EVENT_STA_GOT_IP,
                                              wifi_event_handler,
                                              NULL,
                                              NULL);
    if (err != ESP_OK)
        return err;

    wifi_config_t wifi_config = {0};
    snprintf((char *)wifi_config.sta.ssid,
             sizeof(wifi_config.sta.ssid),
             "%s",
             WIFI_SSID);
    snprintf((char *)wifi_config.sta.password,
             sizeof(wifi_config.sta.password),
             "%s",
             WIFI_PASSWORD);
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    wifi_config.sta.sae_pwe_h2e = WPA3_SAE_PWE_BOTH;

    err = esp_wifi_set_storage(WIFI_STORAGE_RAM);
    if (err != ESP_OK)
        return err;

    err = esp_wifi_set_mode(WIFI_MODE_STA);
    if (err != ESP_OK)
        return err;

    err = esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    if (err != ESP_OK)
        return err;

    err = esp_wifi_start();
    if (err == ESP_OK)
        ESP_LOGI(TAG, "WIFI started (event-driven)");

    return err;
}
