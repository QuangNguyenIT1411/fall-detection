#pragma once

// Copy this file to app_config.h and fill in the local credentials.
// app_config.h is intentionally ignored by Git.

#define DEVICE_CODE "device01"

#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// Keep disabled until the HiveMQ Cloud hostname and the ESP32 publisher
// credentials below have been filled in.
#define MQTT_ENABLED 0
#define MQTT_BROKER_URI "mqtts://YOUR_CLUSTER_HOST:8883"
#define MQTT_USERNAME "YOUR_ESP32_PUBLISH_USERNAME"
#define MQTT_PASSWORD "YOUR_ESP32_PUBLISH_PASSWORD"

#define MQTT_TELEMETRY_INTERVAL_MS 1000
#define MQTT_RECONNECT_TIMEOUT_MS 5000

// Supabase Edge Functions use HTTPS/TCP and custom per-device authentication.
#define CLOUD_EVENT_ENABLED 0
#define SUPABASE_FUNCTION_BASE_URL "https://YOUR_PROJECT_REF.supabase.co/functions/v1"
#define DEVICE_API_KEY "YOUR_RANDOM_DEVICE_SECRET_AT_LEAST_32_CHARACTERS"
#define CLOUD_EVENT_HTTP_TIMEOUT_MS 10000

// A latched fall that is not cancelled within this window is confirmed by
// the device. Flutter only displays the server-derived countdown.
#define FALL_CONFIRM_TIMEOUT_MS 30000
