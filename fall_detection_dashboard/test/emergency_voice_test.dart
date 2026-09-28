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
      expect(find.text('☎ Đã thực hiện cuộc gọi khẩn cấp'), findsOneWidget);
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
}
