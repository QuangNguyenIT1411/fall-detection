class Device {
  const Device({
    required this.id,
    required this.deviceCode,
    required this.name,
    required this.isOnline,
    required this.lastSeen,
    required this.createdAt,
    this.buzzerEnabled = true,
    this.buzzerUpdatedAt,
  });

  final String id;
  final String deviceCode;
  final String name;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final bool buzzerEnabled;
  final DateTime? buzzerUpdatedAt;

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      deviceCode: json['device_code'] as String,
      name: json['name'] as String,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: _parseNullableDate(json['last_seen']),
      createdAt: DateTime.parse(json['created_at'] as String),
      buzzerEnabled: json['buzzer_enabled'] as bool? ?? true,
      buzzerUpdatedAt: _parseNullableDate(json['buzzer_updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'device_code': deviceCode,
    'name': name,
    'is_online': isOnline,
    'last_seen': lastSeen?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'buzzer_enabled': buzzerEnabled,
    'buzzer_updated_at': buzzerUpdatedAt?.toUtc().toIso8601String(),
  };

  static DateTime? _parseNullableDate(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.parse(value);
  }
}
