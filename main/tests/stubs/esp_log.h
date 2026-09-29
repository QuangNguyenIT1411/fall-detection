#pragma once
void test_log(const char *tag, const char *format, const char *value);
#define ESP_LOGI(tag, format, value) test_log(tag, format, value)
