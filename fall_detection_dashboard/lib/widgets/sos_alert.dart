import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/fall_event.dart';

class SosAlert extends StatelessWidget {
  const SosAlert({super.key, required this.event, required this.onViewDetail});

  final FallEvent event;
  final VoidCallback onViewDetail;

  @override
  Widget build(BuildContext context) {
    final deviceCode = event.device?.deviceCode ?? event.deviceId;
    return Container(
      key: const Key('sos-alert'),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E6),
        border: Border.all(color: AppColors.amber),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.sos_rounded, size: 42, color: AppColors.red),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🆘 YÊU CẦU TRỢ GIÚP KHẨN CẤP',
                style: TextStyle(
                  color: AppColors.red,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$deviceCode • ${DateFormat('HH:mm:ss - dd/MM/yyyy').format(event.detectedAt.toLocal())}',
              ),
              const Text('Người dùng đã chủ động kích hoạt SOS.'),
            ],
          ),
          OutlinedButton(
            onPressed: onViewDetail,
            child: const Text('Xem chi tiết'),
          ),
        ],
      ),
    );
  }
}
