import 'telemetry.dart';

enum TelemetrySource { mock, mqtt }

enum BrokerConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

enum DevicePresence { online, offline, unknown }

sealed class RealtimeUpdate {
  const RealtimeUpdate();
}

class TelemetryUpdate extends RealtimeUpdate {
  const TelemetryUpdate(this.telemetry);
  final Telemetry telemetry;
}

class FallStateUpdate extends RealtimeUpdate {
  const FallStateUpdate({
    required this.deviceId,
    required this.state,
    required this.timestamp,
  });

  final String deviceId;
  final FallState state;
  final DateTime timestamp;

  factory FallStateUpdate.fromJson(Map<String, dynamic> json) {
    final deviceId = json['device_id'];
    if (deviceId is! String || deviceId.trim().isEmpty) {
      throw const FormatException('device_id không hợp lệ.');
    }
    return FallStateUpdate(
      deviceId: deviceId,
      state: FallState.fromLabel(json['state']),
      timestamp: Telemetry.parseTimestamp(json['timestamp']),
    );
  }
}

class DeviceStatusUpdate extends RealtimeUpdate {
  const DeviceStatusUpdate({
    required this.deviceId,
    required this.presence,
    required this.timestamp,
  });

  final String deviceId;
  final DevicePresence presence;
  final DateTime timestamp;

  factory DeviceStatusUpdate.fromJson(Map<String, dynamic> json) {
    final deviceId = json['device_id'];
    final online = json['online'];
    if (deviceId is! String || deviceId.trim().isEmpty) {
      throw const FormatException('device_id không hợp lệ.');
    }
    if (online is! bool) {
      throw const FormatException('online phải là boolean.');
    }
    return DeviceStatusUpdate(
      deviceId: deviceId,
      presence: online ? DevicePresence.online : DevicePresence.offline,
      timestamp: Telemetry.parseTimestamp(json['timestamp']),
    );
  }
}

class BrokerStatusUpdate extends RealtimeUpdate {
  const BrokerStatusUpdate(this.state, {this.message});
  final BrokerConnectionState state;
  final String? message;
}
