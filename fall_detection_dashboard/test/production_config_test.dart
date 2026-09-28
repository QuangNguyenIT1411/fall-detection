import 'package:fall_detection_dashboard/core/config/mqtt_config.dart';
import 'package:fall_detection_dashboard/core/config/supabase_config.dart';
import 'package:fall_detection_dashboard/core/navigation/app_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production MQTT requires WSS 8884 /mqtt', () {
    const secure = MqttConfig(
      host: 'example.s1.eu.hivemq.cloud',
      port: 8884,
      username: 'dashboard-reader',
      password: 'test-only',
      useTls: true,
      websocketPath: '/mqtt',
      deviceCode: 'device01',
    );
    expect(secure.websocketUrl,
        'wss://example.s1.eu.hivemq.cloud:8884/mqtt');
    expect(secure.isProductionCompatible, isTrue);
    expect(const MqttConfig(
      host: 'example.s1.eu.hivemq.cloud', port: 8883,
      username: 'reader', password: 'test-only', useTls: true,
      websocketPath: '/mqtt', deviceCode: 'device01',
    ).isProductionCompatible, isFalse);
    expect(const MqttConfig(
      host: 'example.s1.eu.hivemq.cloud', port: 8884,
      username: 'reader', password: 'test-only', useTls: false,
      websocketPath: '/mqtt', deviceCode: 'device01',
    ).isProductionCompatible, isFalse);
  });

  test('missing MQTT and non-public Supabase keys fail production validation', () {
    expect(MqttConfig.fromEnvironment().isProductionCompatible, isFalse);
    expect(SupabaseConfig.isPublicKey('sb_publishable_example'), isTrue);
    expect(SupabaseConfig.isPublicKey('sb_secret_example'), isFalse);
    expect(SupabaseConfig.isPublicKey('not-a-key'), isFalse);
  });

  test('SPA route parser preserves nested event path', () {
    expect(AppRoute.fromPath('/history').pageIndex, 2);
    expect(AppRoute.fromPath('/realtime').pageIndex, 1);
    expect(AppRoute.fromPath('/events/event-id').eventId, 'event-id');
    expect(AppRoute.pathForEvent('event-id'), '/events/event-id');
  });
}
