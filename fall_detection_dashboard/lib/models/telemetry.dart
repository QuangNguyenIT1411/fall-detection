enum FallState {
  normal('NORMAL'),
  falling('FALLING'),
  impact('IMPACT'),
  posture('POSTURE'),
  fallDetected('FALL_DETECTED');

  const FallState(this.label);
  final String label;

  static FallState fromLabel(Object? value) {
    if (value is! String) {
      throw const FormatException('state phải là chuỗi.');
    }
    return FallState.values.firstWhere(
      (state) => state.label == value,
      orElse: () => throw FormatException('state không hợp lệ: $value'),
    );
  }
}

class Telemetry {
  const Telemetry({
    required this.deviceId,
    required this.acc,
    required this.gyro,
    required this.pose,
    required this.state,
    required this.timestamp,
  });

  final String deviceId;
  final double acc;
  final double gyro;
  final double pose;
  final FallState state;
  final DateTime timestamp;

  factory Telemetry.fromJson(Map<String, dynamic> json) {
    final deviceId = json['device_id'];
    if (deviceId is! String || deviceId.trim().isEmpty) {
      throw const FormatException('device_id không hợp lệ.');
    }

    return Telemetry(
      deviceId: deviceId,
      acc: _requiredDouble(json['acc'], 'acc'),
      gyro: _requiredDouble(json['gyro'], 'gyro'),
      pose: _requiredDouble(json['pose'], 'pose'),
      state: FallState.fromLabel(json['state']),
      timestamp: parseTimestamp(json['timestamp']),
    );
  }

  static DateTime parseTimestamp(Object? value) {
    if (value == null) return DateTime.now().toUtc();
    if (value is num && value.isFinite && value >= 0) {
      // ESP32 publishes uptime milliseconds, not Unix epoch time. Use the
      // browser receive time for realtime UI; official event time comes from
      // Supabase detected_at.
      return DateTime.now().toUtc();
    }
    throw const FormatException('timestamp uptime phải là số không âm.');
  }

  static double _requiredDouble(Object? value, String field) {
    if (value is! num || !value.isFinite) {
      throw FormatException('$field phải là số hữu hạn.');
    }
    return value.toDouble();
  }
}
