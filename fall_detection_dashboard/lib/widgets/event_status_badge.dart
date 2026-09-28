import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/fall_event.dart';

class EventStatusBadge extends StatelessWidget {
  const EventStatusBadge({super.key, required this.status});

  final FallEventStatus status;

  Color get _color => switch (status) {
    FallEventStatus.detected => AppColors.red,
    FallEventStatus.cancelled => AppColors.amber,
    FallEventStatus.confirmed => AppColors.green,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
      ),
      child: Text(
        status.databaseValue,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
