import 'dart:async';

import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/services/buzzer_control_repository.dart';

class FakeBuzzerRepository implements BuzzerControlRepository {
  bool enabled = true;
  bool failWrite = false;
  bool failRead = false;
  int reads = 0;
  int writes = 0;
  Completer<BuzzerSetting>? writeWait;
  Completer<Device?>? readWait;
  Device get current => Device(
    id: 'device-1',
    deviceCode: 'device01',
    name: 'Thiết bị người cao tuổi',
    isOnline: true,
    lastSeen: null,
    createdAt: DateTime.utc(2026, 9, 30),
    buzzerEnabled: enabled,
  );

  @override
  Future<Device?> getDeviceByCode(String code) async {
    if (code != 'device01') throw StateError('Unexpected device');
    reads++;
    final wait = readWait;
    readWait = null;
    if (wait != null) return wait.future;
    if (failRead) throw StateError('Read unavailable');
    return current;
  }

  @override
  Future<BuzzerSetting> setBuzzerEnabled(bool value) async {
    writes++;
    if (failWrite) throw StateError('Write unavailable');
    final result = writeWait == null
        ? BuzzerSetting(value, DateTime.utc(2026, 9, 30))
        : await writeWait!.future;
    enabled = result.enabled;
    return result;
  }
}
