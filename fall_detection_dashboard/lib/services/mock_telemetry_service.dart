import 'dart:async';
import 'dart:math';

import '../models/realtime_update.dart';
import '../models/telemetry.dart';
import 'telemetry_data_source.dart';

class MockTelemetryService implements TelemetryDataSource {
  final _controller = StreamController<RealtimeUpdate>.broadcast();
  final _random = Random();
  Timer? _timer;
  FallState _state = FallState.normal;
  bool _isSimulating = false;

  @override
  TelemetrySource get source => TelemetrySource.mock;

  @override
  String get deviceCode => 'device01';

  @override
  Stream<RealtimeUpdate> get updates => _controller.stream;

  @override
  bool get isSimulating => _isSimulating;

  @override
  bool get supportsSimulation => true;

  @override
  Future<void> start() async {
    _controller.add(
      DeviceStatusUpdate(
        deviceId: deviceCode,
        presence: DevicePresence.online,
        timestamp: DateTime.now(),
      ),
    );
    _emit();
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _emit(),
    );
  }

  @override
  Future<void> simulateFall() async {
    if (_isSimulating || _state == FallState.fallDetected) return;
    _isSimulating = true;

    for (final step in <(FallState, Duration)>[
      (FallState.falling, const Duration(milliseconds: 900)),
      (FallState.impact, const Duration(milliseconds: 800)),
      (FallState.posture, const Duration(milliseconds: 1200)),
      (FallState.fallDetected, Duration.zero),
    ]) {
      _state = step.$1;
      _emit();
      await Future<void>.delayed(step.$2);
    }

    _isSimulating = false;
  }

  @override
  void resetSimulation() {
    _state = FallState.normal;
    _isSimulating = false;
    _emit();
  }

  void _emit() {
    if (_controller.isClosed) return;

    final values = switch (_state) {
      FallState.normal => (
        0.9 + _random.nextDouble() * 0.2,
        _random.nextDouble() * 20,
        _random.nextDouble() * 20,
      ),
      FallState.falling => (
        0.25 + _random.nextDouble() * 0.25,
        120 + _random.nextDouble() * 80,
        25 + _random.nextDouble() * 20,
      ),
      FallState.impact => (
        5.8 + _random.nextDouble() * 1.5,
        260 + _random.nextDouble() * 70,
        55 + _random.nextDouble() * 20,
      ),
      FallState.posture => (
        0.9 + _random.nextDouble() * 0.2,
        20 + _random.nextDouble() * 20,
        78 + _random.nextDouble() * 12,
      ),
      FallState.fallDetected => (
        0.95 + _random.nextDouble() * 0.1,
        4 + _random.nextDouble() * 12,
        84 + _random.nextDouble() * 6,
      ),
    };

    _controller.add(
      TelemetryUpdate(
        Telemetry(
          deviceId: 'device01',
          acc: values.$1,
          gyro: values.$2,
          pose: values.$3,
          state: _state,
          timestamp: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
