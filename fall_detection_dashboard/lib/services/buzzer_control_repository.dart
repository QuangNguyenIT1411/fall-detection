import '../models/device.dart';

class BuzzerSetting {
  const BuzzerSetting(this.enabled, this.updatedAt);
  final bool enabled;
  final DateTime updatedAt;
}

abstract interface class BuzzerControlRepository {
  Future<Device?> getDeviceByCode(String code);
  Future<BuzzerSetting> setBuzzerEnabled(bool enabled);
}
