import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/screens/event_detail/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({String type = 'FALL', String? callStatus}) => {
  'id': '10000000-0000-4000-8000-000000000103',
  'device_id': '00000000-0000-4000-8000-000000000001',
  'event_type': type,
  'detected_at': '2026-09-28T01:19:16Z',
  'status': 'CONFIRMED',
  'confirmed_at': '2026-09-28T01:19:16Z',
  'emergency_call_requested_at': callStatus == null
      ? null
      : '2026-09-28T01:19:17Z',
  'emergency_call_status': callStatus,
  'emergency_call_sid': callStatus == 'ACCEPTED' ? 'CA${'b' * 32}' : null,
  'created_at': '2026-09-28T01:19:16Z',
};

void main() {
  test('old events parse with absent voice columns', () {
    final oldJson = _json()
      ..remove('emergency_call_requested_at')
      ..remove('emergency_call_status')
      ..remove('emergency_call_sid');
    final event = FallEvent.fromJson(oldJson);
    expect(event.emergencyCallStatus, isNull);
    expect(event.emergencyCallRequestedAt, isNull);
    expect(event.emergencyCallSid, isNull);
    expect(FallEvent.fromJson(event.toJson()).emergencyCallStatus, isNull);
  });

  for (final type in ['FALL', 'SOS']) {
    testWidgets('$type accepted call is visible without exposing SID', (
      tester,
    ) async {
      final event = FallEvent.fromJson(
        _json(type: type, callStatus: 'ACCEPTED'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailScreen(event: event, onBack: () {}),
          ),
        ),
      );
      expect(find.text('☎ Đã gửi yêu cầu gọi'), findsOneWidget);
      expect(find.text('☎ Twilio báo cuộc gọi đã được kết nối'), findsNothing);
      expect(
        find.text('✅ Người thân đã xác nhận đã nhận cảnh báo'),
        findsNothing,
      );
      expect(find.text('Thời gian yêu cầu gọi'), findsOneWidget);
      expect(find.textContaining(event.emergencyCallSid!), findsNothing);
      expect(
        find.text(
          type == 'SOS' ? '🆘 YÊU CẦU TRỢ GIÚP KHẨN CẤP' : 'PHÁT HIỆN TÉ NGÃ',
        ),
        findsOneWidget,
      );
      if (type == 'SOS') {
        expect(find.text('Peak ACC'), findsNothing);
      } else {
        expect(find.text('Peak ACC'), findsOneWidget);
      }
    });
  }

  testWidgets('REQUESTED has the same submitted label as ACCEPTED', (
    tester,
  ) async {
    final event = FallEvent.fromJson(_json(callStatus: 'REQUESTED'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(event: event, onBack: () {}),
        ),
      ),
    );
    expect(find.text('☎ Đã gửi yêu cầu gọi'), findsOneWidget);
    expect(
      find.text('✅ Người thân đã xác nhận đã nhận cảnh báo'),
      findsNothing,
    );
  });

  testWidgets('failed call shows safe message, never provider error', (
    tester,
  ) async {
    final event = FallEvent.fromJson(_json(callStatus: 'FAILED'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(event: event, onBack: () {}),
        ),
      ),
    );
    expect(
      find.text('⚠️ Không thể thực hiện cuộc gọi khẩn cấp'),
      findsOneWidget,
    );
    expect(find.textContaining('AUTH_ERROR'), findsNothing);
  });

  final deliveryCases = <String, Map<String, dynamic>>{
    '☎ Nhà mạng báo đang đổ chuông': {
      'emergency_call_ringing_at': '2026-09-28T01:19:18Z',
    },
    '☎ Twilio báo cuộc gọi đã được kết nối': {
      'emergency_call_ringing_at': '2026-09-28T01:19:18Z',
      'emergency_call_answered_at': '2026-09-28T01:19:20Z',
    },
    '☑ Phiên gọi đã kết thúc': {'emergency_call_final_status': 'COMPLETED'},
    '⚠️ Không có người trả lời': {'emergency_call_final_status': 'NO_ANSWER'},
    '⚠️ Máy bận': {'emergency_call_final_status': 'BUSY'},
    '⚠️ Cuộc gọi thất bại': {'emergency_call_final_status': 'FAILED'},
    'Cuộc gọi đã bị hủy': {'emergency_call_final_status': 'CANCELED'},
  };
  for (final entry in deliveryCases.entries) {
    testWidgets('delivery UI: ${entry.key}', (tester) async {
      final json = _json(callStatus: 'ACCEPTED')..addAll(entry.value);
      final event = FallEvent.fromJson(json);
      final roundTrip = FallEvent.fromJson(event.toJson());
      expect(roundTrip.emergencyCallDisplay, entry.key);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailScreen(event: event, onBack: () {}),
          ),
        ),
      );
      expect(find.text(entry.key), findsOneWidget);
      expect(find.text('☎ Đã thực hiện cuộc gọi khẩn cấp'), findsNothing);
      expect(find.textContaining(event.emergencyCallSid!), findsNothing);
      expect(
        find.text('✅ Người thân đã xác nhận đã nhận cảnh báo'),
        findsNothing,
      );
      expect(
        find.text('Người thân chưa xác nhận đã nhận cảnh báo'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Trạng thái cuộc gọi do nhà cung cấp viễn thông báo về và không đảm bảo điện thoại vật lý đã đổ chuông hoặc người nhận đã nghe máy.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Chưa xác minh người thân thực sự nghe máy.'),
        entry.key == '☑ Phiên gọi đã kết thúc' ? findsOneWidget : findsNothing,
      );
    });
  }

  testWidgets('COMPLETED plus Telegram ACK shows separate confirmation', (
    tester,
  ) async {
    final json = _json(callStatus: 'ACCEPTED')
      ..addAll({
        'emergency_call_final_status': 'COMPLETED',
        'acknowledged_at': '2026-09-28T01:20:00Z',
        'acknowledged_via': 'TELEGRAM',
      });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailScreen(
            event: FallEvent.fromJson(json),
            onBack: () {},
          ),
        ),
      ),
    );
    expect(find.text('☑ Phiên gọi đã kết thúc'), findsOneWidget);
    expect(
      find.text('✅ Người thân đã xác nhận đã nhận cảnh báo'),
      findsOneWidget,
    );
    expect(
      find.text('Chưa xác minh người thân thực sự nghe máy.'),
      findsOneWidget,
    );
    expect(find.text('Telegram'), findsOneWidget);
  });

  testWidgets(
    'first failure has pending retry; second failure has no third retry',
    (tester) async {
      final json = _json(callStatus: 'ACCEPTED')
        ..addAll({
          'emergency_call_final_status': 'NO_ANSWER',
          'emergency_call_retry_after': '2026-09-28T01:20:15Z',
        });
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailScreen(
              event: FallEvent.fromJson(json),
              onBack: () {},
            ),
          ),
        ),
      );
      await show();
      expect(find.text('Đang chuẩn bị gọi lại lần cuối'), findsOneWidget);
      json['emergency_call_retry_count'] = 1;
      json['emergency_call_retry_after'] = null;
      json['emergency_call_last_sid'] = 'CA${'c' * 32}';
      await show();
      expect(find.text('Đang chuẩn bị gọi lại lần cuối'), findsNothing);
      expect(find.text('Đã thử gọi lại 1 lần'), findsOneWidget);
      expect(find.text('⚠️ Không có người trả lời'), findsOneWidget);
      expect(
        find.textContaining(json['emergency_call_last_sid']),
        findsNothing,
      );
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets('delivery detail stays responsive at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final json = _json(callStatus: 'ACCEPTED')
        ..addAll({
          'emergency_call_final_status': 'COMPLETED',
          'emergency_call_initiated_at': '2026-09-28T01:19:17Z',
          'emergency_call_ringing_at': '2026-09-28T01:19:18Z',
          'emergency_call_answered_at': '2026-09-28T01:19:20Z',
          'emergency_call_completed_at': '2026-09-28T01:19:45Z',
          'emergency_call_retry_count': 1,
        });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventDetailScreen(
              event: FallEvent.fromJson(json),
              onBack: () {},
            ),
          ),
        ),
      );
      expect(find.text('☑ Phiên gọi đã kết thúc'), findsOneWidget);
      expect(find.text('Twilio báo kết nối lúc'), findsOneWidget);
      expect(find.text('Nhà mạng báo đổ chuông lúc'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'terminal state takes precedence over progress; requested is not accepted',
    () {
      final json = _json(callStatus: 'ACCEPTED')
        ..addAll({
          'emergency_call_final_status': 'COMPLETED',
          'emergency_call_ringing_at': '2026-09-28T01:19:18Z',
          'emergency_call_answered_at': '2026-09-28T01:19:20Z',
          'emergency_call_retry_count': 1,
        });
      expect(
        FallEvent.fromJson(json).emergencyCallDisplay,
        '☑ Phiên gọi đã kết thúc',
      );
      json['emergency_call_status'] = 'REQUESTED';
      expect(
        FallEvent.fromJson(json).emergencyCallDisplay,
        '☎ Đã gửi yêu cầu gọi',
      );
      expect(FallEvent.fromJson(_json()).emergencyCallRetryCount, 0);
    },
  );
}
