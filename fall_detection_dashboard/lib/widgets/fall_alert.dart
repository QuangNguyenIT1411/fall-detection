import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../models/fall_event.dart';

class FallAlert extends StatelessWidget {
  const FallAlert({
    super.key,
    required this.event,
    required this.onDismiss,
    required this.onViewDetail,
    this.confirmationSecondsRemaining,
  });

  final FallEvent event;
  final VoidCallback onDismiss;
  final VoidCallback onViewDetail;
  final int? confirmationSecondsRemaining;

  @override
  Widget build(BuildContext context) {
    final isConfirmed = event.status == FallEventStatus.confirmed;
    final foreground = isConfirmed ? const Color(0xFF7F1D1D) : AppColors.red;
    final deviceLabel = event.device?.deviceCode ?? event.deviceId;
    return Container(
      decoration: BoxDecoration(
        color: isConfirmed ? const Color(0xFFFEE2E2) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 18,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_rounded, color: Colors.white),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240, maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConfirmed ? 'ĐÃ XÁC NHẬN TÉ NGÃ' : 'PHÁT HIỆN TÉ NGÃ',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$deviceLabel • ${DateFormat('HH:mm:ss - dd/MM/yyyy').format(event.detectedAt.toLocal())}',
                  style: const TextStyle(color: Color(0xFF9F1239)),
                ),
                if (!event.isLocalRealtime) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Mã sự kiện: ${event.id}',
                    style: const TextStyle(
                      color: Color(0xFF9F1239),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  event.isLocalRealtime
                      ? 'ACC hiện tại ${event.peakAcc?.toStringAsFixed(2) ?? '—'} g  •  '
                            'GYRO hiện tại ${event.peakGyro?.toStringAsFixed(1) ?? '—'} dps  •  '
                            'POSE hiện tại ${event.finalPose?.toStringAsFixed(1) ?? '—'}°'
                      : 'Peak ACC ${event.peakAcc?.toStringAsFixed(2) ?? '—'} g  •  '
                            'Peak GYRO ${event.peakGyro?.toStringAsFixed(1) ?? '—'} dps  •  '
                            'POSE ${event.finalPose?.toStringAsFixed(1) ?? '—'}°',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (event.isLocalRealtime) ...[
                  const SizedBox(height: 5),
                  const Text(
                    'Đang chờ dữ liệu sự kiện chính thức từ máy chủ.',
                    style: TextStyle(color: Color(0xFF9F1239), fontSize: 12),
                  ),
                ] else if (event.status == FallEventStatus.detected) ...[
                  const SizedBox(height: 5),
                  Text(
                    (confirmationSecondsRemaining ?? 0) > 0
                        ? 'Đang chờ người dùng phản hồi • '
                              'còn $confirmationSecondsRemaining giây'
                        : 'Đã hết thời gian phản hồi • '
                              'đang chờ trạng thái chính thức từ máy chủ',
                    style: const TextStyle(
                      color: Color(0xFF9F1239),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else if (isConfirmed) ...[
                  const SizedBox(height: 5),
                  const Text(
                    'Không nhận được phản hồi trong thời hạn 30 giây.',
                    style: TextStyle(
                      color: Color(0xFF7F1D1D),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onViewDetail,
            style: OutlinedButton.styleFrom(foregroundColor: foreground),
            child: const Text('Xem chi tiết'),
          ),
          IconButton(
            onPressed: onDismiss,
            tooltip: 'Ẩn cảnh báo',
            icon: Icon(Icons.close, color: foreground),
          ),
        ],
      ),
    );
  }
}
