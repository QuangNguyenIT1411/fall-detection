class MqttConfig {
  const MqttConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.useTls,
    required this.websocketPath,
    required this.deviceCode,
  });

  factory MqttConfig.fromEnvironment() {
    return const MqttConfig(
      host: String.fromEnvironment('MQTT_HOST'),
      port: int.fromEnvironment('MQTT_PORT', defaultValue: 8884),
      username: String.fromEnvironment('MQTT_USERNAME'),
      password: String.fromEnvironment('MQTT_PASSWORD'),
      useTls: bool.fromEnvironment('MQTT_USE_TLS', defaultValue: true),
      websocketPath: String.fromEnvironment(
        'MQTT_WEBSOCKET_PATH',
        defaultValue: '/mqtt',
      ),
      deviceCode: String.fromEnvironment(
        'MQTT_DEVICE_CODE',
        defaultValue: 'device01',
      ),
    );
  }

  final String host;
  final int port;
  final String username;
  final String password;
  final bool useTls;
  final String websocketPath;
  final String deviceCode;

  bool get isConfigured =>
      host.trim().isNotEmpty &&
      port > 0 &&
      port <= 65535 &&
      username.isNotEmpty &&
      password.isNotEmpty &&
      deviceCode.trim().isNotEmpty &&
      !deviceCode.contains(RegExp(r'[/+#]'));

  bool get isProductionCompatible =>
      isConfigured && useTls && port == 8884 && normalizedPath == '/mqtt' &&
      !host.contains('://') && !host.contains('/') && !host.contains(':');

  String get normalizedPath {
    final value = websocketPath.trim();
    if (value.isEmpty) return '';
    return value.startsWith('/') ? value : '/$value';
  }

  String get websocketUrl =>
      '${useTls ? 'wss' : 'ws'}://${host.trim()}:$port$normalizedPath';

  String get telemetryTopic => 'fall/$deviceCode/telemetry';
  String get stateTopic => 'fall/$deviceCode/state';
  String get statusTopic => 'fall/$deviceCode/status';

  static const missingConfigMessage =
      'Thiếu cấu hình MQTT; dashboard đang dùng MOCK DATA.';
}
