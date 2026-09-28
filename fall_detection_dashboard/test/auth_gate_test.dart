import 'dart:async';

import 'package:fall_detection_dashboard/auth/auth_gate.dart';
import 'package:fall_detection_dashboard/auth/auth_service.dart';
import 'package:fall_detection_dashboard/models/device.dart';
import 'package:fall_detection_dashboard/models/fall_event.dart';
import 'package:fall_detection_dashboard/models/realtime_update.dart';
import 'package:fall_detection_dashboard/services/fall_event_repository.dart';
import 'package:fall_detection_dashboard/services/telemetry_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth implements AuthService {
  _Auth([this.user]);
  CaregiverIdentity? user;
  final controller = StreamController<CaregiverIdentity?>.broadcast();
  Completer<void>? loginWait;
  bool rejectLogin = false;

  @override
  Stream<CaregiverIdentity?> get changes => controller.stream;
  @override
  Future<CaregiverIdentity?> restoreSession() async => user;
  @override
  Future<void> signIn(String email, String password) async {
    if (rejectLogin) {
      throw const AuthException('Invalid login credentials', statusCode: '400');
    }
    await loginWait?.future;
    user = CaregiverIdentity('caregiver-1', email);
    controller.add(user);
  }

  @override
  Future<void> signOut() async {
    user = null;
    controller.add(null);
  }

  void close() => controller.close();
}

class _Repository implements FallEventRepository {
  int loads = 0;
  int details = 0;
  @override
  Future<List<FallEvent>> getFallEvents() async {
    loads++;
    return [];
  }

  @override
  Future<FallEvent?> getFallEventById(String id) async {
    details++;
    return null;
  }

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

class _Telemetry implements TelemetryDataSource {
  int starts = 0;
  bool disposed = false;
  final controller = StreamController<RealtimeUpdate>.broadcast();
  @override
  TelemetrySource get source => TelemetrySource.mqtt;
  @override
  String get deviceCode => 'device01';
  @override
  Stream<RealtimeUpdate> get updates => controller.stream;
  @override
  bool get supportsSimulation => false;
  @override
  bool get isSimulating => false;
  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> disconnect() async {
    disposed = true;
  }

  @override
  Future<void> simulateFall() async {}
  @override
  void resetSimulation() {}
  @override
  void dispose() {
    disposed = true;
    controller.close();
  }
}

void main() {
  const caregiver = CaregiverIdentity('caregiver-1', 'caregiver@example.com');

  testWidgets(
    'unauthenticated deep link shows login without loading data or MQTT',
    (tester) async {
      final auth = _Auth();
      final repo = _Repository();
      var sourceCreations = 0;
      await tester.pumpWidget(
        AuthGate(
          auth: auth,
          repository: repo,
          initialRoute: '/events/10000000-0000-4000-8000-000000000103',
          telemetrySourceFactory: () {
            sourceCreations++;
            return _Telemetry();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập người thân'), findsOneWidget);
      expect(find.text('Tổng quan hệ thống'), findsNothing);
      expect(repo.loads, 0);
      expect(repo.details, 0);
      expect(sourceCreations, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.close();
    },
  );

  testWidgets(
    'restored session starts dashboard and logout disposes MQTT/cache',
    (tester) async {
      final auth = _Auth(caregiver);
      final repo = _Repository();
      final source = _Telemetry();
      await tester.pumpWidget(
        AuthGate(
          auth: auth,
          repository: repo,
          telemetrySourceFactory: () => source,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
      expect(repo.loads, 1);
      expect(source.starts, 1);
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      expect(find.text('Đăng nhập người thân'), findsOneWidget);
      expect(source.disposed, isTrue);
      expect(find.text('Tổng quan hệ thống'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.close();
    },
  );

  testWidgets('desktop navigation rail keeps logout accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _Auth(caregiver);
    await tester.pumpWidget(
      AuthGate(
        auth: auth,
        repository: _Repository(),
        telemetrySourceFactory: _Telemetry.new,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byKey(const Key('logout-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.close();
  });

  testWidgets('login validates fields, shows loading, maps bad credentials', (
    tester,
  ) async {
    final auth = _Auth()..rejectLogin = true;
    await tester.pumpWidget(
      AuthGate(
        auth: auth,
        repository: _Repository(),
        telemetrySourceFactory: _Telemetry.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Vui lòng nhập email.'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login-email')), 'bad');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(find.text('Email không hợp lệ.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'caregiver@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'incorrect',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Email hoặc mật khẩu không đúng.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    auth.close();
  });

  testWidgets(
    'successful login transitions from loading to authenticated app',
    (tester) async {
      final auth = _Auth()..loginWait = Completer<void>();
      final source = _Telemetry();
      await tester.pumpWidget(
        AuthGate(
          auth: auth,
          repository: _Repository(),
          telemetrySourceFactory: () => source,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('login-email')),
        'caregiver@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'password',
      );
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(source.starts, 0);
      auth.loginWait!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
      expect(source.starts, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.close();
    },
  );
}
