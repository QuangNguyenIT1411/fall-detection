import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/telemetry.dart';

class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.state, this.large = false});

  final FallState state;
  final bool large;

  Color get _color => switch (state) {
    FallState.normal => AppColors.green,
    FallState.falling => AppColors.amber,
    FallState.impact => const Color(0xFFEA580C),
    FallState.posture => const Color(0xFF7C3AED),
    FallState.fallDetected => AppColors.red,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 11,
        vertical: large ? 10 : 7,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            state.label,
            style: TextStyle(
              color: _color,
              fontSize: large ? 14 : 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
