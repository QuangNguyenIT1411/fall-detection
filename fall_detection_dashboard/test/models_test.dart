import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Device', () {
    test('parse JSON đúng và xử lý last_seen null', () {
      final device = Device.fromJson({
        'id': '00000000-0000-4000-8000-000000000001',
        'device_code': 'device01',
        'name': 'Thiết bị người cao tuổi 01',
        'is_online': true,
        'last_seen': null,
        'created_at': '2026-09-01T01:00:00Z',
      });

      expect(device.deviceCode, 'device01');
      expect(device.name, 'Thiết bị người cao tuổi 01');
      expect(device.isOnline, isTrue);
      expect(device.lastSeen, isNull);
      expect(device.createdAt.isUtc, isTrue);
      expect(device.toJson()['device_code'], 'device01');
    });
  });

  group('FallEvent', () {
    test('parse JSON cùng thiết bị liên kết', () {
      final event = FallEvent.fromJson({
        'id': '10000000-0000-4000-8000-000000000102',
        'device_id': '00000000-0000-4000-8000-000000000001',
        'detected_at': '2026-09-22T08:30:00Z',
        'peak_acc': 5.8,
        'peak_gyro': 245.5,
        'final_pose': 72.4,
        'low_g_duration_ms': 180,
        'low_g_to_impact_ms': 220,
        'status': 'CANCELLED',
        'cancelled_at': '2026-09-22T08:31:10Z',
        'created_at': '2026-09-22T08:30:03Z',
        'devices': {
          'id': '00000000-0000-4000-8000-000000000001',
          'device_code': 'device01',
          'name': 'Thiết bị người cao tuổi 01',
          'is_online': true,
          'last_seen': '2026-09-24T02:20:00Z',
          'created_at': '2026-09-01T01:00:00Z',
        },
      });

      expect(event.status, FallEventStatus.cancelled);
      expect(event.id, '10000000-0000-4000-8000-000000000102');
      expect(event.deviceId, '00000000-0000-4000-8000-000000000001');
      expect(event.id, isNot(event.deviceId));
      expect(event.cancelledAt, isNotNull);
      expect(event.peakAcc, 5.8);
      expect(event.lowGDurationMs, 180);
      expect(event.device?.deviceCode, 'device01');
      expect(event.toJson()['status'], 'CANCELLED');
      expect(event.notificationSentAt, isNull);
      expect(event.acknowledgedAt, isNull);
      expect(event.acknowledgedVia, isNull);
    });

    test('parse caregiver acknowledgement from server fields', () {
      final event = FallEvent.fromJson({
        'id': '10000000-0000-4000-8000-000000000103',
        'device_id': '00000000-0000-4000-8000-000000000001',
        'detected_at': '2026-09-28T01:18:00Z',
        'status': 'CONFIRMED',
        'acknowledged_at': '2026-09-28T01:20:00Z',
        'acknowledged_via': 'TELEGRAM',
        'created_at': '2026-09-28T01:18:00Z',
      });
      expect(event.acknowledgedAt?.isUtc, isTrue);
      expect(event.acknowledgedVia, 'TELEGRAM');
      expect(event.toJson()['acknowledged_at'], '2026-09-28T01:20:00.000Z');
    });

    test('parse notification_sent_at khi Telegram đã gửi', () {
      final event = FallEvent.fromJson({
        'id': '10000000-0000-4000-8000-000000000103',
        'device_id': '00000000-0000-4000-8000-000000000001',
        'detected_at': '2026-09-28T01:18:00Z',
        'status': 'CONFIRMED',
        'confirmed_at': '2026-09-28T01:19:16Z',
        'notification_sent_at': '2026-09-28T01:19:17Z',
        'created_at': '2026-09-28T01:18:00Z',
      });
      expect(
        event.notificationSentAt?.toUtc().toIso8601String(),
        '2026-09-28T01:19:17.000Z',
      );
      expect(
        event.toJson()['notification_sent_at'],
        '2026-09-28T01:19:17.000Z',
      );
    });
  });
}
