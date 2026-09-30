import 'dart:async';

import 'package:fall_detection_dashboard/models/realtime_update.dart';
import 'package:fall_detection_dashboard/models/telemetry.dart';
import 'package:fall_detection_dashboard/providers/telemetry_provider.dart';
import 'package:fall_detection_dashboard/screens/realtime/realtime_screen.dart';
import 'package:fall_detection_dashboard/services/telemetry_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Source implements TelemetryDataSource {
  final _updates = StreamController<RealtimeUpdate>.broadcast(sync: true);

  void emit(RealtimeUpdate update) => _updates.add(update);

  @override
  String get deviceCode => 'device01';
  @override
  TelemetrySource get source => TelemetrySource.mqtt;
  @override
  Stream<RealtimeUpdate> get updates => _updates.stream;
  @override
  bool get isSimulating => false;
  @override
  bool get supportsSimulation => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> simulateFall() async {}
  @override
  void resetSimulation() {}
  @override
  void dispose() => _updates.close();
}

TelemetryUpdate _telemetry(FallState state, {String deviceId = 'device01'}) =>
    TelemetryUpdate(
      Telemetry(
        deviceId: deviceId,
        acc: 1,
        gyro: 2,
        pose: 3,
        state: state,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1500),
      ),
    );

FallStateUpdate _state(FallState state, {String deviceId = 'device01'}) =>
    FallStateUpdate(
      deviceId: deviceId,
      state: state,
      timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
    );

void main() {
  test('first valid state, telemetry fallback and duplicate suppression', () {
    final source = _Source();
    var receivedAt = DateTime(2026, 9, 30, 12, 41, 20);
    final provider = TelemetryProvider(source, now: () => receivedAt)..start();
    expect(provider.recentStates, isEmpty);
    source.emit(const BrokerStatusUpdate(BrokerConnectionState.connected));
    source.emit(
      DeviceStatusUpdate(
        deviceId: 'device01',
        presence: DevicePresence.online,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    );
    expect(provider.recentStates, isEmpty);

    source.emit(_telemetry(FallState.normal, deviceId: 'other'));
    expect(provider.recentStates, isEmpty);
    source.emit(_telemetry(FallState.normal));
    expect(provider.recentStates.single.state, FallState.normal);
    expect(provider.recentStates.single.receivedAt, receivedAt);
    for (var i = 0; i < 10; i++) {
      source.emit(_telemetry(FallState.normal));
    }
    expect(provider.recentStates, hasLength(1));

    receivedAt = receivedAt.add(const Duration(seconds: 15));
    source.emit(_state(FallState.falling));
    source.emit(_telemetry(FallState.falling));
    source.emit(_telemetry(FallState.falling));
    expect(provider.recentStates, hasLength(2));
    expect(provider.recentStates.first.state, FallState.falling);
    expect(provider.recentStates.first.receivedAt, receivedAt);
    source.emit(_telemetry(FallState.impact)); // Telemetry fallback.
    source.emit(_state(FallState.posture));
    source.emit(_telemetry(FallState.posture));
    source.emit(_state(FallState.normal));
    expect(provider.recentStates.map((entry) => entry.state).toList(), [
      FallState.normal,
      FallState.posture,
      FallState.impact,
      FallState.falling,
      FallState.normal,
    ]);
    expect(provider.events, isEmpty);
    provider.dispose();
  });

  test('keeps only newest 50 transitions', () {
    final source = _Source();
    final provider = TelemetryProvider(source)..start();
    for (var i = 0; i < 60; i++) {
      source.emit(_telemetry(i.isEven ? FallState.normal : FallState.falling));
    }
    expect(provider.recentStates, hasLength(50));
    expect(provider.recentStates.first.state, FallState.falling);
    expect(provider.recentStates.last.state, FallState.normal);
    expect(() => provider.recentStates.clear(), throwsUnsupportedError);
    provider.dispose();
  });

  test(
    'clear retains current state, events and last observed dedupe state',
    () {
      final source = _Source();
      final provider = TelemetryProvider(source)..start();
      source.emit(_state(FallState.normal));
      source.emit(_state(FallState.falling));
      final current = provider.current;
      final history = provider.history.length;
      final events = provider.events.length;
      provider.clearRecentStates();
      expect(provider.recentStates, isEmpty);
      expect(provider.current, same(current));
      expect(provider.history.length, history);
      expect(provider.events.length, events);
      source.emit(_telemetry(FallState.falling));
      expect(provider.recentStates, isEmpty);
      source.emit(_state(FallState.impact));
      expect(provider.recentStates.single.state, FallState.impact);
      provider.dispose();
    },
  );

  test('offline and reconnect do not erase timeline', () {
    final source = _Source();
    final provider = TelemetryProvider(source)..start();
    source.emit(_state(FallState.normal));
    source.emit(
      DeviceStatusUpdate(
        deviceId: 'device01',
        presence: DevicePresence.offline,
        timestamp: DateTime.now(),
      ),
    );
    source.emit(const BrokerStatusUpdate(BrokerConnectionState.reconnecting));
    expect(provider.recentStates.single.state, FallState.normal);
    source.emit(_telemetry(FallState.normal));
    expect(provider.recentStates, hasLength(1));
    expect(provider.devicePresence, DevicePresence.online);
    source.emit(_state(FallState.falling));
    expect(provider.recentStates, hasLength(2));
    provider.dispose();
  });

  test('FALL_DETECTED still creates the existing local alert', () {
    final source = _Source();
    final provider = TelemetryProvider(source)..start();
    source.emit(_state(FallState.normal));
    source.emit(_state(FallState.fallDetected));
    expect(provider.recentStates.first.state, FallState.fallDetected);
    expect(provider.alertVisible, isTrue);
    expect(provider.events.single.isLocalRealtime, isTrue);
    provider.clearRecentStates();
    expect(provider.alertVisible, isTrue);
    expect(provider.events, hasLength(1));
    provider.dispose();
  });

  testWidgets('Realtime displays local time, state badges and guidance', (
    tester,
  ) async {
    final source = _Source();
    final receivedAt = DateTime(2026, 9, 30, 12, 41, 20);
    final provider = TelemetryProvider(source, now: () => receivedAt)..start();
    source.emit(_state(FallState.normal));
    source.emit(_state(FallState.falling));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: RealtimeScreen()),
      ),
    );
    expect(find.text('Nhật ký trạng thái gần đây'), findsOneWidget);
    expect(find.text('12:41:20'), findsNWidgets(2));
    expect(find.text('FALLING'), findsNWidgets(2));
    expect(find.text('NORMAL'), findsOneWidget);
    expect(
      find.text(
        'Trạng thái trung gian không đồng nghĩa đã tạo sự kiện té ngã.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('không kết nối Serial Monitor'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: RealtimeScreen()),
      ),
    );
    expect(find.text('Nhật ký trạng thái gần đây'), findsOneWidget);
    expect(provider.recentStates, hasLength(2));
    await tester.ensureVisible(find.byKey(const Key('clear-recent-states')));
    await tester.tap(find.byKey(const Key('clear-recent-states')));
    await tester.pump();
    expect(
      find.text('Chưa nhận được trạng thái nào từ thiết bị.'),
      findsOneWidget,
    );
    expect(provider.current.state, FallState.falling);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('timeline stays usable on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _Source();
    final provider = TelemetryProvider(source)..start();
    source.emit(_state(FallState.normal));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: RealtimeScreen()),
      ),
    );
    await tester.ensureVisible(find.text('Nhật ký trạng thái gần đây'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
