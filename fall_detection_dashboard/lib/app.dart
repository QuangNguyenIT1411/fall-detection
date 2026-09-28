import 'package:flutter/material.dart';

import 'core/navigation/app_route.dart';
import 'core/theme/app_theme.dart';
import 'models/fall_event.dart';
import 'screens/app_shell.dart';

class FallDetectionApp extends StatelessWidget {
  const FallDetectionApp({
    super.key,
    this.initialRoute,
    this.userEmail,
    this.onLogout,
  });

  final String? initialRoute;
  final String? userEmail;
  final Future<void> Function()? onLogout;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Giám sát té ngã',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      initialRoute: initialRoute,
      onGenerateRoute: (settings) {
        final route = AppRoute.fromPath(settings.name);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => AppShell(
            route: route,
            userEmail: userEmail,
            onLogout: onLogout,
            initialEvent: settings.arguments is FallEvent
                ? settings.arguments! as FallEvent
                : null,
          ),
        );
      },
    );
  }
}
