import 'dart:async';

import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/providers/fall_event_provider.dart';
import 'package:fall_detection_dashboard/screens/history/history_screen.dart';
import 'package:fall_detection_dashboard/services/fall_event_repository.dart';
import 'package:fall_detection_dashboard/models/device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final baseline = DateTime.utc(2026, 9, 28, 12);

  test(
    'History sort detected_at DESC and upsert deduplicates by UUID',
    () async {
      final oldest = _event('oldest', baseline);
      final middle = _event('middle', baseline.add(const Duration(minutes: 1)));
      final newest = _event('newest', baseline.add(const Duration(minutes: 2)));
      final repository = _HistoryRepository([middle, oldest]);
      final provider = FallEventProvider(repository);

      await provider.loadEvents();
      expect(provider.events.map((event) => event.id), ['middle', 'oldest']);

      provider.upsertOfficialEvent(newest);
      provider.upsertOfficialEvent(
        _event('newest', newest.detectedAt, status: FallEventStatus.confirmed),
      );
      expect(provider.events.map((event) => event.id), [
        'newest',
        'middle',
        'oldest',
      ]);
      expect(provider.events, hasLength(3));
      expect(provider.events.first.status, FallEventStatus.confirmed);
      final acknowledged = _event(
        'newest',
        newest.detectedAt,
        status: FallEventStatus.confirmed,
        acknowledgedAt: baseline.add(const Duration(minutes: 3)),
      );
      provider.upsertOfficialEvent(acknowledged);
      provider.upsertOfficialEvent(
        _event('newest', newest.detectedAt, status: FallEventStatus.confirmed),
      );
      expect(provider.events.first.acknowledgedAt, acknowledged.acknowledgedAt);
      provider.upsertOfficialEvent(newest);
      expect(provider.events.first.status, FallEventStatus.confirmed);
      provider.dispose();
    },
  );

  test(
    'Official upsert arriving during History load survives stale result',
    () async {
      final pending = Completer<List<FallEvent>>();
      final repository = _HistoryRepository(const [], pending: pending);
      final provider = FallEventProvider(repository);
      final loading = provider.loadEvents();
      final newEvent = _event('new', baseline.add(const Duration(minutes: 1)));

      provider.upsertOfficialEvent(newEvent);
      pending.complete([_event('old', baseline)]);
      await loading;

      expect(provider.events.map((event) => event.id), ['new', 'old']);
      provider.dispose();
    },
  );

  for (final size in [const Size(390, 844), const Size(1100, 844)]) {
    testWidgets('MỚI NHẤT badge appears once at width ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = FallEventProvider(
        _HistoryRepository([
          _event('old', baseline),
          _event(
            'new',
            baseline.add(const Duration(minutes: 1)),
            status: FallEventStatus.confirmed,
            acknowledgedAt: baseline.add(const Duration(minutes: 2)),
          ),
        ]),
      );
      await provider.loadEvents();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(body: HistoryScreen(onOpenEvent: (_) {})),
          ),
        ),
      );

      expect(find.byKey(const Key('latest-history-badge')), findsOneWidget);
      expect(find.text('MỚI NHẤT'), findsOneWidget);
      expect(find.text('ĐÃ NHẬN'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }
}

FallEvent _event(
  String id,
  DateTime detectedAt, {
  FallEventStatus status = FallEventStatus.detected,
  DateTime? acknowledgedAt,
}) => FallEvent(
  id: id,
  deviceId: 'device-uuid',
  detectedAt: detectedAt,
  peakAcc: 2.8,
  peakGyro: 200,
  finalPose: 70,
  lowGDurationMs: 100,
  lowGToImpactMs: 250,
  status: status,
  cancelledAt: null,
  confirmedAt: status == FallEventStatus.confirmed ? detectedAt : null,
  acknowledgedAt: acknowledgedAt,
  acknowledgedVia: acknowledgedAt == null ? null : 'TELEGRAM',
  createdAt: detectedAt,
);

class _HistoryRepository implements FallEventRepository {
  _HistoryRepository(this.events, {this.pending});

  final List<FallEvent> events;
  final Completer<List<FallEvent>>? pending;

  @override
  Future<List<FallEvent>> getFallEvents() =>
      pending?.future ?? Future.value(events);

  @override
  Future<Device?> getDeviceByCode(String code) async => null;

  @override
  Future<List<Device>> getDevices() async => [];

  @override
  Future<FallEvent?> getFallEventById(String id) async => null;

  @override
  Future<FallEvent?> getLatestFallEventForDevice(
    String deviceCode, {
    required DateTime detectedAfter,
  }) async => null;
}
