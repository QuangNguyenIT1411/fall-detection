import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/providers/fall_event_provider.dart';
import 'package:fall_detection_dashboard/screens/event_detail/event_detail_screen.dart';
import 'package:fall_detection_dashboard/screens/history/history_screen.dart';
import 'package:fall_detection_dashboard/services/fall_event_repository.dart';
import 'package:fall_detection_dashboard/widgets/sos_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _eventId = '10000000-0000-4000-8000-000000000123';

FallEvent _sos({bool acknowledged = false}) => FallEvent.fromJson({
  'id': _eventId,
  'event_type': 'SOS',
  'device_id': '00000000-0000-4000-8000-000000000001',
  'detected_at': '2026-09-28T01:19:16Z',
  'status': 'CONFIRMED',
  'confirmed_at': '2026-09-28T01:19:16Z',
  'notification_sent_at': '2026-09-28T01:19:17Z',
  'acknowledged_at': acknowledged ? '2026-09-28T01:20:00Z' : null,
  'acknowledged_via': acknowledged ? 'TELEGRAM' : null,
  'created_at': '2026-09-28T01:19:16Z',
  'devices': {
    'id': '00000000-0000-4000-8000-000000000001',
    'device_code': 'device01',
    'name': 'Thiết bị người cao tuổi 01',
    'is_online': true,
    'created_at': '2026-09-01T01:00:00Z',
  },
});

void main() {
  test('legacy event defaults to FALL; SOS JSON round-trips', () {
    final sos = _sos();
    expect(sos.eventType, FallEventType.sos);
    expect(FallEvent.fromJson(sos.toJson()).eventType, FallEventType.sos);
    final legacy = Map<String, dynamic>.from(sos.toJson())
      ..remove('event_type');
    expect(FallEvent.fromJson(legacy).eventType, FallEventType.fall);
  });

  testWidgets('SOS History row has status and no fall metrics', (tester) async {
    final provider = FallEventProvider(_Repository([_sos(acknowledged: true)]));
    await provider.loadEvents();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(body: HistoryScreen(onOpenEvent: (_) {})),
        ),
      ),
    );
    expect(find.text('🆘 SOS'), findsOneWidget);
    expect(find.text('ĐÃ NHẬN'), findsOneWidget);
    expect(find.textContaining('g  •'), findsNothing);
    expect(find.textContaining('dps'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('SOS detail shows ACK but hides all fall metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(
            event: _sos(acknowledged: true),
            onBack: () {},
          ),
        ),
      ),
    );
    expect(find.text('🆘 YÊU CẦU TRỢ GIÚP KHẨN CẤP'), findsOneWidget);
    expect(find.text('Thời gian SOS'), findsOneWidget);
    expect(find.text('Đã gửi cảnh báo người thân lúc'), findsOneWidget);
    expect(
      find.text('✅ Người thân đã xác nhận đã nhận cảnh báo'),
      findsOneWidget,
    );
    expect(find.text('Telegram'), findsOneWidget);
    for (final label in [
      'Peak ACC',
      'Peak GYRO',
      'Final POSE',
      'LOW-G duration',
      'LOW-G → IMPACT',
      'PHÁT HIỆN TÉ NGÃ',
    ]) {
      expect(find.text(label), findsNothing);
    }
  });

  testWidgets('SOS overview banner uses emergency copy only', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SosAlert(event: _sos(), onViewDetail: () {}),
        ),
      ),
    );
    expect(find.byKey(const Key('sos-alert')), findsOneWidget);
    expect(find.text('Người dùng đã chủ động kích hoạt SOS.'), findsOneWidget);
    expect(find.textContaining('device01'), findsOneWidget);
    expect(find.textContaining('Phát hiện té ngã'), findsNothing);
    expect(find.textContaining('Peak ACC'), findsNothing);
  });
}

class _Repository implements FallEventRepository {
  _Repository(this.events);
  final List<FallEvent> events;
  @override
  Future<List<FallEvent>> getFallEvents() async => events;
  @override
  Future<FallEvent?> getFallEventById(String id) async => null;
  @override
  Future<FallEvent?> getLatestFallEventForDevice(
    String deviceCode, {
    required DateTime detectedAfter,
  }) async => null;
  @override
  Future<Device?> getDeviceByCode(String code) async => null;
  @override
  Future<List<Device>> getDevices() async => [];
}
