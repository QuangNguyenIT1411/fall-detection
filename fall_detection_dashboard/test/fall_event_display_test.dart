import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/screens/event_detail/event_detail_screen.dart';
import 'package:fall_detection_dashboard/widgets/fall_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  final detectedUtc = DateTime.parse('2026-09-27T17:52:48Z');
  final expectedBannerTime = DateFormat('HH:mm:ss - dd/MM/yyyy')
      .format(detectedUtc.toLocal());

  testWidgets('banner shows official event UUID and local detected time', (
    tester,
  ) async {
    final event = _event(FallEventStatus.detected);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallAlert(
            event: event,
            confirmationSecondsRemaining: 5,
            onDismiss: () {},
            onViewDetail: () {},
          ),
        ),
      ),
    );

    expect(find.text('Mã sự kiện: ${event.id}'), findsOneWidget);
    expect(find.text('device01 • $expectedBannerTime'), findsOneWidget);
    expect(find.textContaining(event.deviceId), findsNothing);
    if (detectedUtc.toLocal().timeZoneOffset == const Duration(hours: 7)) {
      expect(find.text('device01 • 00:52:48 - 28/09/2026'), findsOneWidget);
    }
  });

  testWidgets('zero countdown keeps DETECTED while server has not confirmed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FallAlert(
            event: _event(FallEventStatus.detected),
            confirmationSecondsRemaining: 0,
            onDismiss: () {},
            onViewDetail: () {},
          ),
        ),
      ),
    );

    expect(find.text('ĐÃ XÁC NHẬN TÉ NGÃ'), findsNothing);
    expect(
      find.text(
        'Đã hết thời gian phản hồi • đang chờ trạng thái chính thức từ máy chủ',
      ),
      findsOneWidget,
    );
  });

  testWidgets('detail shows event UUID and local confirmed/created times', (
    tester,
  ) async {
    final event = _event(FallEventStatus.confirmed);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(event: event, onBack: () {}),
        ),
      ),
    );

    expect(find.text('Mã sự kiện'), findsOneWidget);
    expect(find.text(event.id), findsOneWidget);
    expect(find.text(expectedBannerTime), findsOneWidget);
    expect(
      find.text(
        DateFormat('dd/MM/yyyy HH:mm:ss').format(event.confirmedAt!.toLocal()),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        DateFormat('dd/MM/yyyy HH:mm:ss').format(event.createdAt.toLocal()),
      ),
      findsOneWidget,
    );
  });

  testWidgets('detail shows cancelled_at in browser local time', (
    tester,
  ) async {
    final event = _event(FallEventStatus.cancelled);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(event: event, onBack: () {}),
        ),
      ),
    );

    expect(
      find.text(
        DateFormat('dd/MM/yyyy HH:mm:ss').format(event.cancelledAt!.toLocal()),
      ),
      findsOneWidget,
    );
  });

  testWidgets('detail displays caregiver ACK in local time, read only', (
    tester,
  ) async {
    final event = FallEvent.fromJson({
      ..._event(FallEventStatus.confirmed).toJson(),
      'acknowledged_at': '2026-09-28T01:20:00Z',
      'acknowledged_via': 'TELEGRAM',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(event: event, onBack: () {}),
        ),
      ),
    );
    expect(
      find.text('✅ Người thân đã xác nhận đã nhận cảnh báo'),
      findsOneWidget,
    );
    expect(
      find.text(
        DateFormat('dd/MM/yyyy HH:mm:ss')
            .format(event.acknowledgedAt!.toLocal()),
      ),
      findsOneWidget,
    );
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Đã nhận cảnh báo'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Đã nhận cảnh báo'), findsNothing);
  });

  testWidgets(
    'confirmed event without ACK says caregiver has not acknowledged',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailScreen(
              event: _event(FallEventStatus.confirmed),
              onBack: () {},
            ),
          ),
        ),
      );
      expect(
        find.text('Người thân chưa xác nhận đã nhận cảnh báo'),
        findsOneWidget,
      );
    },
  );
}

FallEvent _event(FallEventStatus status) => FallEvent.fromJson({
  'id': 'c1588ac0-1111-4111-8111-111111111111',
  'device_id': '00000000-0000-4000-8000-000000000001',
  'detected_at': '2026-09-27T17:52:48Z',
  'peak_acc': 3.1,
  'peak_gyro': 250,
  'final_pose': 70,
  'low_g_duration_ms': 100,
  'low_g_to_impact_ms': 200,
  'status': status.databaseValue,
  'cancelled_at': status == FallEventStatus.cancelled
      ? '2026-09-27T17:53:10Z'
      : null,
  'confirmed_at': status == FallEventStatus.confirmed
      ? '2026-09-27T17:53:20Z'
      : null,
  'created_at': '2026-09-27T17:52:50Z',
  'devices': {
    'id': '00000000-0000-4000-8000-000000000001',
    'device_code': 'device01',
    'name': 'Thiết bị người cao tuổi 01',
    'is_online': true,
    'last_seen': null,
    'created_at': '2026-09-01T01:00:00Z',
  },
});
