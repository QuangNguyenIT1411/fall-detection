import 'dart:async';

import 'package:fall_detection_dashboard/core/config/mqtt_config.dart';
import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/models/realtime_update.dart';
import 'package:fall_detection_dashboard/models/telemetry.dart';
import 'package:fall_detection_dashboard/providers/fall_event_provider.dart';
import 'package:fall_detection_dashboard/providers/telemetry_provider.dart';
import 'package:fall_detection_dashboard/screens/dashboard/dashboard_screen.dart';
import 'package:fall_detection_dashboard/screens/realtime/realtime_screen.dart';
import 'package:fall_detection_dashboard/services/fall_event_repository.dart';
import 'package:fall_detection_dashboard/services/telemetry_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  const config = MqttConfig(
    host: 'example.s1.eu.hivemq.cloud',
    port: 8884,
    username: 'dashboard',
    password: 'not-a-real-secret',
    useTls: true,
    websocketPath: '/mqtt',
    deviceCode: 'device01',
  );

  testWidgets('telemetry liên tục giữ ONLINE; ngừng quá 8 giây thành OFFLINE', (
    tester,
  ) async {
    final source = _FakeMqttSource();
    var receivedAt = DateTime.utc(2026, 9, 28, 8);
    final provider = TelemetryProvider(source, now: () => receivedAt)..start();

    source.emit(TelemetryUpdate(_watchdogTelemetry()));
    expect(provider.devicePresence, DevicePresence.online);
    receivedAt = receivedAt.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(provider.devicePresence, DevicePresence.online);

    source.emit(TelemetryUpdate(_watchdogTelemetry()));
    receivedAt = receivedAt.add(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 7));
    expect(provider.devicePresence, DevicePresence.online);

    receivedAt = receivedAt.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(provider.devicePresence, DevicePresence.offline);
    expect(provider.hasTelemetry, isFalse);
    provider.dispose();
  });

  testWidgets('LWT offline có hiệu lực ngay; telemetry mới phục hồi ONLINE', (
    tester,
  ) async {
    final source = _FakeMqttSource();
    final provider = TelemetryProvider(source)..start();
    source.emit(TelemetryUpdate(_watchdogTelemetry()));
    expect(provider.devicePresence, DevicePresence.online);

    source.emit(
      DeviceStatusUpdate(
        deviceId: 'device01',
        presence: DevicePresence.offline,
        timestamp: DateTime.now(),
      ),
    );
    expect(provider.devicePresence, DevicePresence.offline);
    expect(provider.hasTelemetry, isFalse);

    source.emit(TelemetryUpdate(_watchdogTelemetry()));
    expect(provider.devicePresence, DevicePresence.online);
    expect(provider.hasTelemetry, isTrue);
    provider.dispose();
  });

  testWidgets('retained online=true không có telemetry hết hạn sau watchdog', (
    tester,
  ) async {
    final source = _FakeMqttSource();
    var receivedAt = DateTime.utc(2026, 9, 28, 8);
    final provider = TelemetryProvider(source, now: () => receivedAt)..start();
    source.emit(
      DeviceStatusUpdate(
        deviceId: 'device01',
        presence: DevicePresence.online,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    );
    expect(provider.devicePresence, DevicePresence.online);
    expect(provider.lastDeviceMessageAt, receivedAt);
    receivedAt = receivedAt.add(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 9));
    expect(provider.devicePresence, DevicePresence.offline);
    provider.dispose();
  });

  testWidgets('state mới làm mới thời gian nhận và phục hồi ONLINE', (
    tester,
  ) async {
    final source = _FakeMqttSource();
    var receivedAt = DateTime.utc(2026, 9, 28, 8);
    final provider = TelemetryProvider(source, now: () => receivedAt)..start();
    source.emit(TelemetryUpdate(_watchdogTelemetry()));
    receivedAt = receivedAt.add(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 9));
    expect(provider.devicePresence, DevicePresence.offline);

    source.emit(
      FallStateUpdate(
        deviceId: 'device01',
        state: FallState.normal,
        timestamp: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );
    expect(provider.devicePresence, DevicePresence.online);
    expect(provider.lastDeviceMessageAt, receivedAt);
    provider.dispose();
  });

  testWidgets('OFFLINE không hiển thị STATE NORMAL như realtime', (
    tester,
  ) async {
    final source = _FakeMqttSource();
    final provider = TelemetryProvider(source)..start();
    source.emit(
      DeviceStatusUpdate(
        deviceId: 'device01',
        presence: DevicePresence.offline,
        timestamp: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<TelemetryProvider>.value(
        value: provider,
        child: MaterialApp(home: DashboardScreen(onOpenEvent: (_) {})),
      ),
    );
    expect(find.text('NORMAL'), findsNothing);
    expect(find.text('OFFLINE'), findsWidgets);

    await tester.pumpWidget(
      ChangeNotifierProvider<TelemetryProvider>.value(
        value: provider,
        child: const MaterialApp(home: RealtimeScreen()),
      ),
    );
    expect(find.text('NORMAL'), findsNothing);
    expect(find.text('OFFLINE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  test('MQTT topics và WebSocket URL được build từ config', () {
    expect(config.isConfigured, isTrue);
    expect(config.websocketUrl, 'wss://example.s1.eu.hivemq.cloud:8884/mqtt');
    expect(config.telemetryTopic, 'fall/device01/telemetry');
    expect(config.stateTopic, 'fall/device01/state');
    expect(config.statusTopic, 'fall/device01/status');
  });

  test('parse telemetry MQTT hợp lệ', () {
    final telemetry = Telemetry.fromJson({
      'device_id': 'device01',
      'acc': 1.04,
      'gyro': 12.3,
      'pose': 84.5,
      'state': 'POSTURE',
      'timestamp': 1720000000000,
    });

    expect(telemetry.deviceId, 'device01');
    expect(telemetry.acc, 1.04);
    expect(telemetry.state, FallState.posture);
    expect(telemetry.timestamp.isUtc, isTrue);
  });

  test('chấp nhận timestamp uptime nhỏ từ ESP32', () {
    final before = DateTime.now().toUtc();
    final telemetry = Telemetry.fromJson({
      'device_id': 'device01',
      'acc': 1.0,
      'gyro': 0.1,
      'pose': 0.1,
      'state': 'NORMAL',
      'timestamp': 21013,
    });
    final after = DateTime.now().toUtc();

    expect(telemetry.timestamp.isUtc, isTrue);
    expect(telemetry.timestamp.year, isNot(1970));
    expect(telemetry.timestamp.isBefore(before), isFalse);
    expect(telemetry.timestamp.isAfter(after), isFalse);
  });

  test('từ chối telemetry thiếu field hoặc state sai', () {
    expect(
      () => Telemetry.fromJson({
        'device_id': 'device01',
        'acc': 1.04,
        'pose': 84.5,
        'state': 'NORMAL',
      }),
      throwsFormatException,
    );
    expect(
      () => Telemetry.fromJson({
        'device_id': 'device01',
        'acc': 1.04,
        'gyro': 12.3,
        'pose': 84.5,
        'state': 'INVALID',
      }),
      throwsFormatException,
    );
  });

  test('provider nhận FALL_DETECTED từ state topic ngay lập tức', () async {
    final source = _FakeMqttSource();
    final provider = TelemetryProvider(source)..start();

    source.emit(
      FallStateUpdate(
        deviceId: 'device01',
        state: FallState.fallDetected,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          1720000000000,
          isUtc: true,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(provider.source, TelemetrySource.mqtt);
    expect(provider.current.state, FallState.fallDetected);
    expect(provider.alertVisible, isTrue);
    expect(provider.events.single.peakAcc, isNull);
    expect(provider.events.single.isLocalRealtime, isTrue);
    provider.dispose();
  });

  test('Supabase official event thay local event sau retry hữu hạn', () async {
    final source = _FakeMqttSource();
    final official = _officialEvent(FallEventStatus.detected);
    final repository = _FakeFallEventRepository([null, null, official]);
    final provider = TelemetryProvider(
      source,
      officialEventRepository: repository,
      officialRetryDelays: const [Duration.zero, Duration.zero, Duration.zero],
    )..start();

    source.emit(_fallState(FallState.fallDetected));
    await _flushAsync();

    expect(repository.latestCalls, 3);
    expect(provider.alertVisible, isTrue);
    expect(provider.events.single.id, official.id);
    expect(provider.events.single.isLocalRealtime, isFalse);
    expect(provider.events.single.lowGDurationMs, 100);
    provider.dispose();
  });

  test('CANCEL ẩn alert, giữ history và nhận CANCELLED từ Supabase', () async {
    final source = _FakeMqttSource();
    final detected = _officialEvent(FallEventStatus.detected);
    final cancelled = _officialEvent(FallEventStatus.cancelled);
    final repository = _FakeFallEventRepository([detected, cancelled]);
    final historyProvider = FallEventProvider(repository);
    final provider = TelemetryProvider(
      source,
      officialEventRepository: repository,
      onOfficialEvent: historyProvider.upsertOfficialEvent,
      officialRetryDelays: const [Duration.zero],
    )..start();

    source.emit(_fallState(FallState.fallDetected));
    await _flushAsync();
    expect(provider.alertVisible, isTrue);
    expect(historyProvider.events.single.status, FallEventStatus.detected);

    source.emit(_fallState(FallState.normal));
    await _flushAsync();

    expect(provider.alertVisible, isFalse);
    expect(provider.events, hasLength(1));
    expect(provider.events.single.status, FallEventStatus.cancelled);
    expect(provider.events.single.cancelledAt, isNotNull);
    expect(provider.confirmationSecondsRemaining, isNull);
    expect(historyProvider.events, hasLength(1));
    expect(historyProvider.events.single.status, FallEventStatus.cancelled);
    provider.dispose();
    historyProvider.dispose();
  });

  test(
    'countdown dùng detected_at official nên reload không reset 30 giây',
    () {
      final now = DateTime.utc(2026, 9, 25, 12);
      final event = _officialEvent(
        FallEventStatus.detected,
        detectedAt: now.subtract(const Duration(seconds: 21)),
      );

      expect(event.confirmationSecondsRemaining(now), 9);
    },
  );

  test('polling dừng countdown khi Supabase chuyển CONFIRMED', () async {
    final source = _FakeMqttSource();
    final detected = _officialEvent(FallEventStatus.detected);
    final confirmed = _officialEvent(
      FallEventStatus.confirmed,
      detectedAt: detected.detectedAt,
    );
    final repository = _FakeFallEventRepository(
      [detected],
      eventByIdResponses: [confirmed],
    );
    final provider = TelemetryProvider(
      source,
      officialEventRepository: repository,
      officialRetryDelays: const [Duration.zero],
      officialStatusPollInterval: const Duration(milliseconds: 1),
    )..start();

    source.emit(_fallState(FallState.fallDetected));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(provider.events.single.status, FallEventStatus.confirmed);
    expect(provider.events.single.confirmedAt, isNotNull);
    expect(provider.confirmationSecondsRemaining, isNull);
    final callsAtTerminal = repository.eventByIdCalls;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(repository.eventByIdCalls, callsAtTerminal);
    provider.dispose();
  });

  test('polling cập nhật CANCELLED và dừng ở trạng thái terminal', () async {
    final source = _FakeMqttSource();
    final detected = _officialEvent(FallEventStatus.detected);
    final cancelled = _officialEvent(
      FallEventStatus.cancelled,
      detectedAt: detected.detectedAt,
    );
    final repository = _FakeFallEventRepository(
      [detected],
      eventByIdResponses: [cancelled],
    );
    final history = FallEventProvider(repository);
    final provider = TelemetryProvider(
      source,
      officialEventRepository: repository,
      onOfficialEvent: history.upsertOfficialEvent,
      officialRetryDelays: const [Duration.zero],
      officialStatusPollInterval: const Duration(milliseconds: 2),
    )..start();

    source.emit(_fallState(FallState.fallDetected));
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(provider.events.single.status, FallEventStatus.cancelled);
    expect(history.events.single.status, FallEventStatus.cancelled);
    expect(provider.confirmationSecondsRemaining, isNull);
    final callsAtTerminal = repository.eventByIdCalls;
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(repository.eventByIdCalls, callsAtTerminal);
    provider.dispose();
    history.dispose();
  });

  test('polling không chạy khi official event đã terminal', () async {
    final source = _FakeMqttSource();
    final repository = _FakeFallEventRepository([
      _officialEvent(FallEventStatus.confirmed),
    ]);
    final provider = TelemetryProvider(
      source,
      officialEventRepository: repository,
      officialRetryDelays: const [Duration.zero],
      officialStatusPollInterval: const Duration(milliseconds: 2),
    )..start();

    source.emit(_fallState(FallState.fallDetected));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(provider.events.single.status, FallEventStatus.confirmed);
    expect(repository.eventByIdCalls, 0);
    provider.dispose();
  });

  test('DETECTED status polling stops after configured timeout', () async {
    final source = _FakeMqttSource();
    final detected = _officialEvent(FallEventStatus.detected);
    final repository = _FakeFallEventRepository(
      [detected],
      eventByIdResponses: [detected],
    );
    final provider = TelemetryProvider(
      source,
      officialEventRepository: repository,
      officialRetryDelays: const [Duration.zero],
      officialStatusPollInterval: const Duration(milliseconds: 2),
      officialStatusPollTimeout: const Duration(milliseconds: 15),
    )..start();

    source.emit(_fallState(FallState.fallDetected));
    await Future<void>.delayed(const Duration(milliseconds: 35));
    final callsAtTimeout = repository.eventByIdCalls;
    expect(callsAtTimeout, greaterThan(0));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(repository.eventByIdCalls, callsAtTimeout);
    provider.dispose();
  });
}

Telemetry _watchdogTelemetry() => Telemetry(
  deviceId: 'device01',
  acc: 1.0,
  gyro: 0.2,
  pose: 10.0,
  state: FallState.normal,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
);

FallStateUpdate _fallState(FallState state) => FallStateUpdate(
  deviceId: 'device01',
  state: state,
  timestamp: DateTime.now().toUtc(),
);

FallEvent _officialEvent(FallEventStatus status, {DateTime? detectedAt}) {
  detectedAt ??= DateTime.now().toUtc();
  return FallEvent(
    id: '10000000-0000-4000-8000-000000000999',
    deviceId: '00000000-0000-4000-8000-000000000001',
    detectedAt: detectedAt,
    peakAcc: 7.91,
    peakGyro: 355.7,
    finalPose: 83.7,
    lowGDurationMs: 100,
    lowGToImpactMs: 280,
    status: status,
    cancelledAt: status == FallEventStatus.cancelled
        ? detectedAt.add(const Duration(seconds: 2))
        : null,
    confirmedAt: status == FallEventStatus.confirmed
        ? detectedAt.add(const Duration(seconds: 30))
        : null,
    createdAt: detectedAt,
    device: Device(
      id: '00000000-0000-4000-8000-000000000001',
      deviceCode: 'device01',
      name: 'Thiết bị 01',
      isOnline: true,
      lastSeen: detectedAt,
      createdAt: detectedAt,
    ),
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeMqttSource implements TelemetryDataSource {
  final _controller = StreamController<RealtimeUpdate>.broadcast(sync: true);

  void emit(RealtimeUpdate update) => _controller.add(update);

  @override
  String get deviceCode => 'device01';

  @override
  bool get isSimulating => false;

  @override
  TelemetrySource get source => TelemetrySource.mqtt;

  @override
  bool get supportsSimulation => false;

  @override
  Stream<RealtimeUpdate> get updates => _controller.stream;

  @override
  Future<void> disconnect() async {}

  @override
  void dispose() => _controller.close();

  @override
  void resetSimulation() {}

  @override
  Future<void> simulateFall() async {}

  @override
  Future<void> start() async {}
}

class _FakeFallEventRepository implements FallEventRepository {
  _FakeFallEventRepository(
    this._latestResponses, {
    this.eventByIdResponses = const [],
  });

  final List<FallEvent?> _latestResponses;
  final List<FallEvent?> eventByIdResponses;
  var latestCalls = 0;
  var eventByIdCalls = 0;

  @override
  Future<FallEvent?> getLatestFallEventForDevice(
    String deviceCode, {
    required DateTime detectedAfter,
  }) async {
    final index = latestCalls.clamp(0, _latestResponses.length - 1);
    latestCalls++;
    return _latestResponses[index];
  }

  @override
  Future<Device?> getDeviceByCode(String code) async => null;

  @override
  Future<List<Device>> getDevices() async => [];

  @override
  Future<FallEvent?> getFallEventById(String id) async {
    if (eventByIdResponses.isEmpty) return null;
    final index = eventByIdCalls.clamp(0, eventByIdResponses.length - 1);
    eventByIdCalls++;
    return eventByIdResponses[index];
  }

  @override
  Future<List<FallEvent>> getFallEvents() async => [];
}
