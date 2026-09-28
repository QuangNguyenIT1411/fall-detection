import '../models/device.dart';
import '../models/fall_event.dart';

abstract interface class FallEventRepository {
  Future<List<Device>> getDevices();
  Future<Device?> getDeviceByCode(String code);
  Future<List<FallEvent>> getFallEvents();
  Future<FallEvent?> getFallEventById(String id);
  Future<FallEvent?> getLatestFallEventForDevice(
    String deviceCode, {
    required DateTime detectedAfter,
  });
}

class UnavailableFallEventRepository implements FallEventRepository {
  const UnavailableFallEventRepository(this.message);

  final String message;

  Never _unavailable() => throw StateError(message);

  @override
  Future<Device?> getDeviceByCode(String code) async => _unavailable();

  @override
  Future<List<Device>> getDevices() async => _unavailable();

  @override
  Future<FallEvent?> getFallEventById(String id) async => _unavailable();

  @override
  Future<FallEvent?> getLatestFallEventForDevice(
    String deviceCode, {
    required DateTime detectedAfter,
  }) async => _unavailable();

  @override
  Future<List<FallEvent>> getFallEvents() async => _unavailable();
}
