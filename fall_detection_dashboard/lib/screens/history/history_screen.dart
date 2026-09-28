import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fall_event.dart';
import '../../providers/fall_event_provider.dart';
import '../../widgets/event_status_badge.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.onOpenEvent});

  final ValueChanged<FallEvent> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FallEventProvider>();
    final width = MediaQuery.sizeOf(context).width;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(width < 600 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lịch sử té ngã',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            'Dữ liệu sự kiện được đọc từ Supabase',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const Key('refresh-history-button'),
                      onPressed: provider.status == FallEventLoadStatus.loading
                          ? null
                          : provider.refresh,
                      tooltip: 'Làm mới dữ liệu',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _HistoryBody(
                    provider: provider,
                    onOpenEvent: onOpenEvent,
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

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.provider, required this.onOpenEvent});

  final FallEventProvider provider;
  final ValueChanged<FallEvent> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    return switch (provider.status) {
      FallEventLoadStatus.initial || FallEventLoadStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      FallEventLoadStatus.error => _ErrorHistory(
        message: provider.errorMessage ?? 'Không thể tải dữ liệu từ máy chủ.',
        onRetry: provider.loadEvents,
      ),
      FallEventLoadStatus.success => RefreshIndicator(
        onRefresh: provider.refresh,
        child: provider.events.isEmpty
            ? const _EmptyHistory()
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: provider.events.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final event = provider.events[index];
                  return _EventTile(
                    event: event,
                    isNewest: index == 0,
                    onTap: () => onOpenEvent(event),
                  );
                },
              ),
      ),
    };
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.isNewest,
    required this.onTap,
  });

  final FallEvent event;
  final bool isNewest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final deviceLabel = event.device == null
        ? event.deviceId
        : '${event.device!.name} • ${event.device!.deviceCode}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.warning_rounded, color: AppColors.red),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNewest) ...[
                      Container(
                        key: const Key('latest-history-badge'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'MỚI NHẤT',
                          style: TextStyle(
                            color: AppColors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                    ],
                    Text(
                      deviceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm:ss')
                          .format(event.detectedAt.toLocal()),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (width < 700) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          EventStatusBadge(status: event.status),
                          Text(
                            '${event.peakAcc?.toStringAsFixed(2) ?? '—'} g • '
                            '${event.peakGyro?.toStringAsFixed(1) ?? '—'} dps • '
                            '${event.finalPose?.toStringAsFixed(1) ?? '—'}°',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (width >= 700) ...[
                Text(
                  '${event.peakAcc?.toStringAsFixed(2) ?? '—'} g  •  '
                  '${event.peakGyro?.toStringAsFixed(1) ?? '—'} dps  •  '
                  '${event.finalPose?.toStringAsFixed(1) ?? '—'}°',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 18),
                EventStatusBadge(status: event.status),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  color: AppColors.blue,
                  size: 46,
                ),
                SizedBox(height: 16),
                Text(
                  'Chưa có sự kiện té ngã.',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Kéo xuống hoặc nhấn nút làm mới để tải lại dữ liệu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorHistory extends StatelessWidget {
  const _ErrorHistory({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.red,
                size: 46,
              ),
              const SizedBox(height: 16),
              const Text(
                'Không thể tải dữ liệu từ máy chủ.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('retry-history-button'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
