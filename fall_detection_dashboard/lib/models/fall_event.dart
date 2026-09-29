import 'device.dart';

enum FallEventType {
  fall('FALL'),
  sos('SOS');

  const FallEventType(this.databaseValue);
  final String databaseValue;

  static FallEventType fromDatabase(Object? value) =>
      value == 'SOS' ? FallEventType.sos : FallEventType.fall;
}

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

enum EmergencyCallStatus {
  requested('REQUESTED'),
  accepted('ACCEPTED'),
  failed('FAILED');

  const EmergencyCallStatus(this.databaseValue);
  final String databaseValue;

  static EmergencyCallStatus? fromDatabase(Object? value) {
    for (final status in values) {
      if (status.databaseValue == value) return status;
    }
    return null;
  }
}

enum EmergencyCallFinalStatus {
  completed('COMPLETED'),
  noAnswer('NO_ANSWER'),
  busy('BUSY'),
  failed('FAILED'),
  canceled('CANCELED');

  const EmergencyCallFinalStatus(this.databaseValue);
  final String databaseValue;

  static EmergencyCallFinalStatus? fromDatabase(Object? value) {
    for (final status in values) {
      if (status.databaseValue == value) return status;
    }
    return null;
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
    this.eventType = FallEventType.fall,
    this.confirmedAt,
    this.notificationSentAt,
    this.acknowledgedAt,
    this.acknowledgedVia,
    this.emergencyCallRequestedAt,
    this.emergencyCallSid,
    this.emergencyCallStatus,
    this.emergencyCallFinalStatus,
    this.emergencyCallInitiatedAt,
    this.emergencyCallRingingAt,
    this.emergencyCallAnsweredAt,
    this.emergencyCallCompletedAt,
    this.emergencyCallRetryCount = 0,
    this.emergencyCallLastSid,
    this.emergencyCallRetryAfter,
    this.device,
    this.isLocalRealtime = false,
  });

  final String id;
  final FallEventType eventType;
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
  final DateTime? emergencyCallRequestedAt;
  final String? emergencyCallSid;
  final EmergencyCallStatus? emergencyCallStatus;
  final EmergencyCallFinalStatus? emergencyCallFinalStatus;
  final DateTime? emergencyCallInitiatedAt;
  final DateTime? emergencyCallRingingAt;
  final DateTime? emergencyCallAnsweredAt;
  final DateTime? emergencyCallCompletedAt;
  final int emergencyCallRetryCount;
  final String? emergencyCallLastSid;
  final DateTime? emergencyCallRetryAfter;
  final DateTime createdAt;
  final Device? device;
  final bool isLocalRealtime;

  factory FallEvent.fromJson(Map<String, dynamic> json) {
    final deviceJson = json['devices'];
    return FallEvent(
      id: json['id'] as String,
      eventType: FallEventType.fromDatabase(json['event_type']),
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
      emergencyCallRequestedAt: _parseNullableDate(
        json['emergency_call_requested_at'],
      ),
      emergencyCallSid: json['emergency_call_sid'] as String?,
      emergencyCallStatus: EmergencyCallStatus.fromDatabase(
        json['emergency_call_status'],
      ),
      emergencyCallFinalStatus: EmergencyCallFinalStatus.fromDatabase(
        json['emergency_call_final_status'],
      ),
      emergencyCallInitiatedAt: _parseNullableDate(
        json['emergency_call_initiated_at'],
      ),
      emergencyCallRingingAt: _parseNullableDate(
        json['emergency_call_ringing_at'],
      ),
      emergencyCallAnsweredAt: _parseNullableDate(
        json['emergency_call_answered_at'],
      ),
      emergencyCallCompletedAt: _parseNullableDate(
        json['emergency_call_completed_at'],
      ),
      emergencyCallRetryCount: _toInt(json['emergency_call_retry_count']) ?? 0,
      emergencyCallLastSid: json['emergency_call_last_sid'] as String?,
      emergencyCallRetryAfter: _parseNullableDate(
        json['emergency_call_retry_after'],
      ),
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
    'event_type': eventType.databaseValue,
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
    'emergency_call_requested_at': emergencyCallRequestedAt
        ?.toUtc()
        .toIso8601String(),
    'emergency_call_sid': emergencyCallSid,
    'emergency_call_status': emergencyCallStatus?.databaseValue,
    'emergency_call_final_status': emergencyCallFinalStatus?.databaseValue,
    'emergency_call_initiated_at': emergencyCallInitiatedAt
        ?.toUtc()
        .toIso8601String(),
    'emergency_call_ringing_at': emergencyCallRingingAt
        ?.toUtc()
        .toIso8601String(),
    'emergency_call_answered_at': emergencyCallAnsweredAt
        ?.toUtc()
        .toIso8601String(),
    'emergency_call_completed_at': emergencyCallCompletedAt
        ?.toUtc()
        .toIso8601String(),
    'emergency_call_retry_count': emergencyCallRetryCount,
    'emergency_call_last_sid': emergencyCallLastSid,
    'emergency_call_retry_after': emergencyCallRetryAfter
        ?.toUtc()
        .toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  // API acceptance never implies that a phone rang or that someone answered.
  // Final delivery wins over old progress timestamps for the current attempt.
  String? get emergencyCallDisplay {
    if (emergencyCallStatus == EmergencyCallStatus.requested) {
      return '☎ Đã gửi yêu cầu gọi';
    }
    if (emergencyCallStatus == EmergencyCallStatus.failed) {
      return '⚠️ Không thể thực hiện cuộc gọi khẩn cấp';
    }
    final finalMessage = switch (emergencyCallFinalStatus) {
      EmergencyCallFinalStatus.completed => '☑ Phiên gọi đã kết thúc',
      EmergencyCallFinalStatus.noAnswer => '⚠️ Không có người trả lời',
      EmergencyCallFinalStatus.busy => '⚠️ Máy bận',
      EmergencyCallFinalStatus.failed => '⚠️ Cuộc gọi thất bại',
      EmergencyCallFinalStatus.canceled => 'Cuộc gọi đã bị hủy',
      null => null,
    };
    if (finalMessage != null) return finalMessage;
    if (emergencyCallAnsweredAt != null) {
      return '☎ Twilio báo cuộc gọi đã được kết nối';
    }
    if (emergencyCallRingingAt != null) {
      return '☎ Nhà mạng báo đang đổ chuông';
    }
    return emergencyCallStatus == EmergencyCallStatus.accepted
        ? '☎ Đã gửi yêu cầu gọi'
        : null;
  }

  bool get emergencyCallRetryPending =>
      emergencyCallRetryAfter != null &&
      emergencyCallRetryCount == 0 &&
      emergencyCallAnsweredAt == null;

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
