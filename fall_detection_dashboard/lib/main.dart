import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/config/mqtt_config.dart';
import 'core/config/supabase_config.dart';
import 'providers/fall_event_provider.dart';
import 'providers/telemetry_provider.dart';
import 'services/fall_event_repository.dart';
import 'services/mock_telemetry_service.dart';
import 'services/mqtt_service.dart';
import 'services/supabase_service.dart';
import 'services/telemetry_data_source.dart';

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
      runApp(MaterialApp(
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
      ));
      return;
    }
  }
  final TelemetryDataSource telemetryDataSource;
  if (mqttConfig.isConfigured) {
    telemetryDataSource = MqttService(mqttConfig);
  } else {
    debugPrint(MqttConfig.missingConfigMessage);
    telemetryDataSource = MockTelemetryService();
  }

  FallEventRepository fallEventRepository;
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
      );
      fallEventRepository = SupabaseService(Supabase.instance.client);
    } catch (_) {
      debugPrint('Không thể khởi tạo Supabase.');
      fallEventRepository = const UnavailableFallEventRepository(
        'Không thể khởi tạo kết nối Supabase. Hãy kiểm tra cấu hình.',
      );
    }
  } else {
    debugPrint(SupabaseConfig.missingConfigMessage);
    fallEventRepository = UnavailableFallEventRepository(
      SupabaseConfig.missingConfigMessage,
    );
  }

  final fallEventProvider = FallEventProvider(fallEventRepository)
    ..loadEvents();
  final telemetryProvider = TelemetryProvider(
    telemetryDataSource,
    officialEventRepository: fallEventRepository,
    onOfficialEvent: fallEventProvider.upsertOfficialEvent,
  )..start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => telemetryProvider),
        ChangeNotifierProvider(create: (_) => fallEventProvider),
      ],
      child: const FallDetectionApp(),
    ),
  );
}
