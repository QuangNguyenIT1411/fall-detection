import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fall_event.dart';
import '../../models/realtime_update.dart';
import '../../models/telemetry.dart';
import '../../providers/telemetry_provider.dart';
import '../../widgets/fall_alert.dart';
import '../../widgets/metric_card.dart';
import '../../widgets/state_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenEvent});

  final ValueChanged<FallEvent> onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TelemetryProvider>();
    final telemetry = provider.current;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1400
        ? 5
        : width >= 760
        ? 3
        : width >= 480
        ? 2
        : 1;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(width < 600 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(
                  isSimulating: provider.isSimulating,
                  isDetected: telemetry.state == FallState.fallDetected,
                  showSimulation:
                      provider.source == TelemetrySource.mock &&
                      provider.canSimulate,
                  onSimulate: provider.simulateFall,
                  onReset: provider.resetSimulation,
                ),
                if (provider.alertVisible && provider.events.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  FallAlert(
                    event: provider.events.first,
                    confirmationSecondsRemaining:
                        provider.confirmationSecondsRemaining,
                    onDismiss: provider.dismissAlert,
                    onViewDetail: () => onOpenEvent(provider.events.first),
                  ),
                ],
                const SizedBox(height: 26),
                _DeviceStatus(provider: provider),
                const SizedBox(height: 22),
                GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: width < 480 ? 2.15 : 1.25,
                  children: [
                    MetricCard(
                      label: 'Gia tốc tổng',
                      value: provider.hasTelemetry
                          ? telemetry.acc.toStringAsFixed(2)
                          : '—',
                      unit: 'g',
                      icon: Icons.speed_rounded,
                      color: AppColors.blue,
                      subtitle: 'ACC',
                    ),
                    MetricCard(
                      label: 'Vận tốc góc',
                      value: provider.hasTelemetry
                          ? telemetry.gyro.toStringAsFixed(1)
                          : '—',
                      unit: 'dps',
                      icon: Icons.screen_rotation_alt_rounded,
                      color: AppColors.cyan,
                      subtitle: 'GYRO',
                    ),
                    MetricCard(
                      label: 'Góc tư thế',
                      value: provider.hasTelemetry
                          ? telemetry.pose.toStringAsFixed(1)
                          : '—',
                      unit: '°',
                      icon: Icons.accessibility_new_rounded,
                      color: const Color(0xFF7C3AED),
                      subtitle: 'POSE',
                    ),
                    _StateCard(
                      telemetry: telemetry,
                      presence: provider.source == TelemetrySource.mqtt
                          ? provider.devicePresence
                          : DevicePresence.online,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _SystemOverview(provider: provider),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isSimulating,
    required this.isDetected,
    required this.showSimulation,
    required this.onSimulate,
    required this.onReset,
  });

  final bool isSimulating;
  final bool isDetected;
  final bool showSimulation;
  final VoidCallback onSimulate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 18,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng quan hệ thống',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Theo dõi an toàn người cao tuổi theo thời gian thực',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
        if (showSimulation)
          FilledButton.icon(
            key: const Key('simulate-fall-button'),
            onPressed: isSimulating
                ? null
                : (isDetected ? onReset : onSimulate),
            style: FilledButton.styleFrom(
              backgroundColor: isDetected ? AppColors.navy : AppColors.red,
            ),
            icon: Icon(
              isDetected ? Icons.restart_alt : Icons.warning_amber_rounded,
            ),
            label: Text(
              isDetected
                  ? 'Đặt lại mô phỏng'
                  : isSimulating
                  ? 'Đang mô phỏng...'
                  : 'Mô phỏng té ngã',
            ),
          ),
      ],
    );
  }
}

class _DeviceStatus extends StatelessWidget {
  const _DeviceStatus({required this.provider});

  final TelemetryProvider provider;

  @override
  Widget build(BuildContext context) {
    final device = provider.device;
    final lastSeen = device.lastSeen == null
        ? 'Chưa có telemetry'
        : 'Cập nhật ${DateFormat('HH:mm:ss').format(device.lastSeen!.toLocal())}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 18,
          runSpacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.sensors_rounded,
                      color: AppColors.blue,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${device.deviceCode} • $lastSeen',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _StatusPill(
              label: 'Nguồn',
              value: provider.source == TelemetrySource.mqtt ? 'MQTT' : 'MOCK',
              color: provider.source == TelemetrySource.mqtt
                  ? AppColors.blue
                  : const Color(0xFF7C3AED),
            ),
            if (provider.source == TelemetrySource.mqtt)
              _StatusPill(
                label: 'Broker',
                value: _brokerLabel(provider.brokerState),
                color: _brokerColor(provider.brokerState),
              ),
            _StatusPill(
              label: 'Thiết bị',
              value: _deviceLabel(provider.devicePresence),
              color: _deviceColor(provider.devicePresence),
            ),
          ],
        ),
      ),
    );
  }

  static String _brokerLabel(BrokerConnectionState state) => switch (state) {
    BrokerConnectionState.disconnected => 'DISCONNECTED',
    BrokerConnectionState.connecting => 'CONNECTING',
    BrokerConnectionState.connected => 'CONNECTED',
    BrokerConnectionState.reconnecting => 'RECONNECTING',
    BrokerConnectionState.error => 'ERROR',
  };

  static Color _brokerColor(BrokerConnectionState state) => switch (state) {
    BrokerConnectionState.connected => AppColors.green,
    BrokerConnectionState.connecting ||
    BrokerConnectionState.reconnecting => AppColors.amber,
    BrokerConnectionState.disconnected => AppColors.muted,
    BrokerConnectionState.error => AppColors.red,
  };

  static String _deviceLabel(DevicePresence presence) => switch (presence) {
    DevicePresence.online => 'ONLINE',
    DevicePresence.offline => 'OFFLINE',
    DevicePresence.unknown => 'UNKNOWN',
  };

  static Color _deviceColor(DevicePresence presence) => switch (presence) {
    DevicePresence.online => AppColors.green,
    DevicePresence.offline => AppColors.red,
    DevicePresence.unknown => AppColors.muted,
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.telemetry, required this.presence});
  final Telemetry telemetry;
  final DevicePresence presence;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_tree_outlined, color: AppColors.amber),
                Spacer(),
                Text(
                  'STATE',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'Trạng thái thuật toán',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (presence == DevicePresence.online)
              StateBadge(state: telemetry.state)
            else
              Text(
                presence == DevicePresence.offline
                    ? 'OFFLINE'
                    : 'KHÔNG CÓ KẾT NỐI',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SystemOverview extends StatelessWidget {
  const _SystemOverview({required this.provider});
  final TelemetryProvider provider;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Wrap(
          spacing: 40,
          runSpacing: 20,
          children: [
            _OverviewItem(
              label: 'Điểm dữ liệu đang giữ',
              value:
                  '${provider.history.length}/${TelemetryProvider.maxPoints}',
              icon: Icons.data_usage_rounded,
            ),
            _OverviewItem(
              label: 'Sự kiện phiên này',
              value: '${provider.events.length}',
              icon: Icons.event_note_rounded,
            ),
            _OverviewItem(
              label: 'Nguồn dữ liệu',
              value: provider.source == TelemetrySource.mqtt
                  ? 'MQTT'
                  : 'MOCK DATA',
              icon: Icons.science_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewItem extends StatelessWidget {
  const _OverviewItem({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          Icon(icon, color: AppColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
