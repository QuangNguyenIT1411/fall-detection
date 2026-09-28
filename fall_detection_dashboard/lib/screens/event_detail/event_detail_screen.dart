import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fall_event.dart';
import '../../widgets/event_status_badge.dart';

class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({
    super.key,
    required this.event,
    required this.onBack,
    this.onRefresh,
  });

  final FallEvent? event;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final currentEvent = event;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(width < 600 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: currentEvent == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Quay lại lịch sử'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Chi tiết sự kiện',
                              style: TextStyle(
                                color: AppColors.navy,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (onRefresh != null)
                            IconButton.filledTonal(
                              key: const Key('refresh-event-button'),
                              tooltip: 'Làm mới sự kiện',
                              onPressed: onRefresh,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFBE123C), AppColors.red],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Wrap(
                          spacing: 18,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'PHÁT HIỆN TÉ NGÃ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  DateFormat(
                                    'HH:mm:ss - dd/MM/yyyy',
                                  ).format(currentEvent.detectedAt.toLocal()),
                                  style: const TextStyle(
                                    color: Color(0xFFFFE4E6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final itemWidth = constraints.maxWidth >= 700
                                  ? (constraints.maxWidth - 32) / 3
                                  : constraints.maxWidth >= 400
                                  ? (constraints.maxWidth - 16) / 2
                                  : constraints.maxWidth;
                              return Wrap(
                                spacing: 16,
                                runSpacing: 24,
                                children: [
                                  _DetailItem(
                                    width: itemWidth,
                                    label: 'Mã sự kiện',
                                    value: currentEvent.id,
                                  ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: 'Thiết bị',
                                    value: currentEvent.device == null
                                        ? currentEvent.deviceId
                                        : '${currentEvent.device!.name} '
                                              '(${currentEvent.device!.deviceCode})',
                                  ),
                                  SizedBox(
                                    width: itemWidth,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Trạng thái',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        EventStatusBadge(
                                          status: currentEvent.status,
                                        ),
                                      ],
                                    ),
                                  ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: currentEvent.isLocalRealtime
                                        ? 'ACC hiện tại'
                                        : 'Peak ACC',
                                    value: currentEvent.peakAcc == null
                                        ? '—'
                                        : '${currentEvent.peakAcc!.toStringAsFixed(2)} g',
                                  ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: currentEvent.isLocalRealtime
                                        ? 'GYRO hiện tại'
                                        : 'Peak GYRO',
                                    value: currentEvent.peakGyro == null
                                        ? '—'
                                        : '${currentEvent.peakGyro!.toStringAsFixed(1)} dps',
                                  ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: currentEvent.isLocalRealtime
                                        ? 'POSE hiện tại'
                                        : 'Final POSE',
                                    value: currentEvent.finalPose == null
                                        ? '—'
                                        : '${currentEvent.finalPose!.toStringAsFixed(1)}°',
                                  ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: 'LOW-G duration',
                                    value: currentEvent.lowGDurationMs == null
                                        ? '—'
                                        : '${currentEvent.lowGDurationMs} ms',
                                  ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: 'LOW-G → IMPACT',
                                    value: currentEvent.lowGToImpactMs == null
                                        ? '—'
                                        : '${currentEvent.lowGToImpactMs} ms',
                                  ),
                                  if (currentEvent.cancelledAt != null)
                                    _DetailItem(
                                      width: itemWidth,
                                      label: 'Đã huỷ lúc',
                                      value: DateFormat('dd/MM/yyyy HH:mm:ss')
                                          .format(
                                            currentEvent.cancelledAt!.toLocal(),
                                          ),
                                    ),
                                  if (currentEvent.confirmedAt != null)
                                    _DetailItem(
                                      width: itemWidth,
                                      label: 'Đã xác nhận lúc',
                                      value: DateFormat('dd/MM/yyyy HH:mm:ss')
                                          .format(
                                            currentEvent.confirmedAt!.toLocal(),
                                          ),
                                    ),
                                  if (currentEvent.notificationSentAt != null)
                                    _DetailItem(
                                      width: itemWidth,
                                      label: 'Đã gửi cảnh báo người thân lúc',
                                      value: DateFormat('dd/MM/yyyy HH:mm:ss')
                                          .format(
                                            currentEvent.notificationSentAt!
                                                .toLocal(),
                                          ),
                                    ),
                                  if (currentEvent.status ==
                                      FallEventStatus.confirmed)
                                    _DetailItem(
                                      width: itemWidth,
                                      label: 'Người thân xác nhận',
                                      value: currentEvent.acknowledgedAt == null
                                          ? 'Người thân chưa xác nhận đã nhận cảnh báo'
                                          : '✅ Người thân đã nhận cảnh báo',
                                    ),
                                  if (currentEvent.acknowledgedAt != null)
                                    _DetailItem(
                                      width: itemWidth,
                                      label: 'Đã nhận lúc',
                                      value: DateFormat('dd/MM/yyyy HH:mm:ss')
                                          .format(
                                            currentEvent.acknowledgedAt!
                                                .toLocal(),
                                          ),
                                    ),
                                  if (currentEvent.acknowledgedVia != null)
                                    _DetailItem(
                                      width: itemWidth,
                                      label: 'Qua',
                                      value:
                                          currentEvent.acknowledgedVia ==
                                              'TELEGRAM'
                                          ? 'Telegram'
                                          : currentEvent.acknowledgedVia!,
                                    ),
                                  _DetailItem(
                                    width: itemWidth,
                                    label: 'Ghi nhận lúc',
                                    value: DateFormat(
                                      'dd/MM/yyyy HH:mm:ss',
                                    ).format(currentEvent.createdAt.toLocal()),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.width,
    required this.label,
    required this.value,
  });
  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
