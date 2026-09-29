import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'core/config/mqtt_config.dart';
import 'core/config/supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/telemetry_source_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  final mqttConfig = MqttConfig.fromEnvironment();
  if (const bool.fromEnvironment('PRODUCTION_BUILD')) {
    final errors = <String>[
      if (!mqttConfig.isProductionCompatible)
        'MQTT phải dùng WSS, port 8884, path /mqtt và tài khoản đọc riêng.',
      if (!SupabaseConfig.isProductionCompatible)
        'Thiếu cấu hình Supabase URL hoặc publishable/anon key hợp lệ.',
    ];
    if (errors.isNotEmpty) {
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Cấu hình production chưa hoàn chỉnh'),
                    for (final error in errors) Text(error),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }
  }
  if (!SupabaseConfig.isConfigured) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Thiếu cấu hình Supabase cho đăng nhập.')),
        ),
      ),
    );
    return;
  }
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Không thể khởi tạo đăng nhập Supabase.')),
        ),
      ),
    );
    return;
  }
  final client = Supabase.instance.client;
  final repository = SupabaseService(client);
  runApp(
    AuthGate(
      auth: SupabaseAuthService(client),
      repository: repository,
      buzzerRepository: repository,
      telemetrySourceFactory: () => createTelemetrySource(mqttConfig),
    ),
  );
}
