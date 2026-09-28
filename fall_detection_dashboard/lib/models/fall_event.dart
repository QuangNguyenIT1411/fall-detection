import 'device.dart';

enum FallEventStatus {
  detected('DETECTED'),
  cancelled('CANCELLED'),
  confirmed('CONFIRMED');

  const FallEventStatus(this.databaseValue);
  final String databaseValue;

  static FallEventStatus fromDatabase(String value) {
    return FallEventStatus.values.firstWhere(
      (status) => status.databaseValue == value,
      orElse: () =>
          throw FormatException('Trạng thái sự kiện không hợp lệ: $value'),
    );
  }
}

class FallEvent {
  const FallEvent({
    required this.id,
    required this.deviceId,
    required this.detectedAt,
    required this.peakAcc,
    required this.peakGyro,
    required this.finalPose,
    required this.lowGDurationMs,
    required this.lowGToImpactMs,
    required this.status,
    required this.cancelledAt,
    required this.createdAt,
    this.confirmedAt,
    this.notificationSentAt,
    this.acknowledgedAt,
    this.acknowledgedVia,
    this.device,
    this.isLocalRealtime = false,
  });

  final String id;
  final String deviceId;
  final DateTime detectedAt;
  final double? peakAcc;
  final double? peakGyro;
  final double? finalPose;
  final int? lowGDurationMs;
  final int? lowGToImpactMs;
  final FallEventStatus status;
  final DateTime? cancelledAt;
  final DateTime? confirmedAt;
  final DateTime? notificationSentAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedVia;
  final DateTime createdAt;
  final Device? device;
  final bool isLocalRealtime;

  factory FallEvent.fromJson(Map<String, dynamic> json) {
    final deviceJson = json['devices'];
    return FallEvent(
      id: json['id'] as String,
      deviceId: json['device_id'] as String,
      detectedAt: DateTime.parse(json['detected_at'] as String),
      peakAcc: _toDouble(json['peak_acc']),
      peakGyro: _toDouble(json['peak_gyro']),
      finalPose: _toDouble(json['final_pose']),
      lowGDurationMs: _toInt(json['low_g_duration_ms']),
      lowGToImpactMs: _toInt(json['low_g_to_impact_ms']),
      status: FallEventStatus.fromDatabase(json['status'] as String),
      cancelledAt: _parseNullableDate(json['cancelled_at']),
      confirmedAt: _parseNullableDate(json['confirmed_at']),
      notificationSentAt: _parseNullableDate(json['notification_sent_at']),
      acknowledgedAt: _parseNullableDate(json['acknowledged_at']),
      acknowledgedVia: json['acknowledged_via'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      device: deviceJson is Map<String, dynamic>
          ? Device.fromJson(deviceJson)
          : deviceJson is Map
          ? Device.fromJson(Map<String, dynamic>.from(deviceJson))
          : null,
      isLocalRealtime: false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_id': deviceId,
    'detected_at': detectedAt.toUtc().toIso8601String(),
    'peak_acc': peakAcc,
    'peak_gyro': peakGyro,
    'final_pose': finalPose,
    'low_g_duration_ms': lowGDurationMs,
    'low_g_to_impact_ms': lowGToImpactMs,
    'status': status.databaseValue,
    'cancelled_at': cancelledAt?.toUtc().toIso8601String(),
    'confirmed_at': confirmedAt?.toUtc().toIso8601String(),
    'notification_sent_at': notificationSentAt?.toUtc().toIso8601String(),
    'acknowledged_at': acknowledgedAt?.toUtc().toIso8601String(),
    'acknowledged_via': acknowledgedVia,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  int? confirmationSecondsRemaining(
    DateTime now, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (isLocalRealtime || status != FallEventStatus.detected) return null;
    final remaining = detectedAt.toUtc().add(timeout).difference(now.toUtc());
    if (remaining <= Duration.zero) return 0;
    return (remaining.inMilliseconds / 1000).ceil();
  }

  static double? _toDouble(Object? value) => (value as num?)?.toDouble();
  static int? _toInt(Object? value) => (value as num?)?.toInt();

  static DateTime? _parseNullableDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.parse(value);
  }
}
