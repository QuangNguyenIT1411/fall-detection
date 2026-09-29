import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../core/theme/app_theme.dart';
import '../providers/fall_event_provider.dart';
import '../providers/telemetry_provider.dart';
import '../providers/buzzer_control_provider.dart';
import '../services/buzzer_control_repository.dart';
import '../services/fall_event_repository.dart';
import '../services/telemetry_data_source.dart';
import 'auth_service.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.auth,
    required this.repository,
    required this.telemetrySourceFactory,
    this.initialRoute,
    this.buzzerRepository,
  });

  final AuthService auth;
  final FallEventRepository repository;
  final TelemetryDataSource Function() telemetrySourceFactory;
  final String? initialRoute;
  final BuzzerControlRepository? buzzerRepository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<CaregiverIdentity?>? _subscription;
  CaregiverIdentity? _user;
  bool _checking = true;
  int _authRevision = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.auth.changes.listen((user) {
      if (!mounted) return;
      if (!_checking && _user?.id == user?.id) return;
      setState(() {
        _user = user;
        _checking = false;
        _authRevision++;
      });
    });
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final user = await widget.auth.restoreSession();
      if (!mounted || !_checking) return;
      setState(() {
        _user = user;
        _checking = false;
      });
    } catch (_) {
      if (!mounted || !_checking) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _logout() async {
    // Remove the authenticated subtree immediately, including MQTT and caches.
    setState(() {
      _user = null;
      _authRevision++;
    });
    await widget.auth.signOut();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final user = _user;
    if (user == null) {
      return MaterialApp(
        title: 'FallGuard — Đăng nhập',
        theme: AppTheme.light,
        home: LoginScreen(auth: widget.auth),
      );
    }
    return KeyedSubtree(
      key: ValueKey('${user.id}-$_authRevision'),
      child: MultiProvider(
        providers: [
          if (widget.buzzerRepository != null)
            ChangeNotifierProvider<BuzzerControlProvider>(
              create: (_) =>
                  BuzzerControlProvider(widget.buzzerRepository!)..start(),
            ),
          ChangeNotifierProvider<FallEventProvider>(
            create: (_) => FallEventProvider(widget.repository)
              ..loadEvents()
              ..startAutoRefresh(),
          ),
          ChangeNotifierProvider<TelemetryProvider>(
            create: (context) => TelemetryProvider(
              widget.telemetrySourceFactory(),
              officialEventRepository: widget.repository,
              onOfficialEvent: context
                  .read<FallEventProvider>()
                  .upsertOfficialEvent,
            )..start(),
          ),
        ],
        child: FallDetectionApp(
          initialRoute: widget.initialRoute,
          userEmail: user.email,
          onLogout: _logout,
        ),
      ),
    );
  }
}
