import '../core/config/mqtt_config.dart';
import 'mock_telemetry_service.dart';
import 'mqtt_service.dart';
import 'telemetry_data_source.dart';

TelemetryDataSource createTelemetrySource(MqttConfig config) {
  if (config.isConfigured) return MqttService(config);
  return MockTelemetryService();
}
