import 'package:fall_detection_dashboard/app.dart';
import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/providers/fall_event_provider.dart';
import 'package:fall_detection_dashboard/providers/telemetry_provider.dart';
import 'package:fall_detection_dashboard/services/fall_event_repository.dart';
import 'package:fall_detection_dashboard/services/mock_telemetry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget buildTestApp({String? initialRoute, FallEventRepository? repository}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(
        create: (_) => TelemetryProvider(MockTelemetryService())..start(),
      ),
      ChangeNotifierProvider(
        create: (_) => FallEventProvider(repository ?? _EmptyRepository())..loadEvents(),
      ),
    ],
    child: FallDetectionApp(initialRoute: initialRoute),
  );
}

class _EmptyRepository implements FallEventRepository {
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

  @override
  Future<List<FallEvent>> getFallEvents() async => [];
}

void main() {
  testWidgets('direct /history route renders after refresh', (tester) async {
    await tester.pumpWidget(buildTestApp(initialRoute: '/history'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch sử té ngã'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('direct /events/:id loads official event', (tester) async {
    const id = '10000000-0000-4000-8000-000000000103';
    await tester.pumpWidget(buildTestApp(
      initialRoute: '/events/$id',
      repository: _EventRepository(),
    ));
    await tester.pumpAndSettle();
    expect(find.text(id), findsOneWidget);
    expect(find.text('Đã gửi cảnh báo người thân lúc'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hiển thị dashboard và dữ liệu mock', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.text('Tổng quan hệ thống'), findsOneWidget);
    expect(find.text('Mô phỏng té ngã'), findsOneWidget);
    expect(find.textContaining('ONLINE'), findsOneWidget);
    expect(find.text('Gia tốc tổng'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mô phỏng đi đến cảnh báo té ngã', (tester) async {
    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    await tester.tap(find.byKey(const Key('simulate-fall-button')));
    await tester.pump();
    expect(find.text('FALLING'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();

    expect(find.text('PHÁT HIỆN TÉ NGÃ'), findsOneWidget);
    expect(find.text('FALL_DETECTED'), findsOneWidget);
    expect(find.text('Đặt lại mô phỏng'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dashboard và điều hướng không tràn trên mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp());
    await tester.pump();

    expect(find.text('Tổng quan hệ thống'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Realtime'));
    await tester.pumpAndSettle();
    expect(find.text('Theo dõi realtime'), findsOneWidget);

    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.text('Lịch sử té ngã'), findsOneWidget);
    expect(find.text('Chưa có sự kiện té ngã.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _EventRepository extends _EmptyRepository {
  @override
  Future<FallEvent?> getFallEventById(String id) async => FallEvent.fromJson({
    'id': id,
    'device_id': '00000000-0000-4000-8000-000000000001',
    'detected_at': '2026-09-28T01:18:00Z',
    'status': 'CONFIRMED',
    'confirmed_at': '2026-09-28T01:19:16Z',
    'notification_sent_at': '2026-09-28T01:19:17Z',
    'created_at': '2026-09-28T01:18:00Z',
  });
}
