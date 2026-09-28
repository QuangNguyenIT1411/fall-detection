import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../core/navigation/app_route.dart';
import '../models/fall_event.dart';
import '../providers/fall_event_provider.dart';
import '../providers/telemetry_provider.dart';
import 'dashboard/dashboard_screen.dart';
import 'event_detail/event_detail_screen.dart';
import 'history/history_screen.dart';
import 'realtime/realtime_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.route = const AppRoute('/', 0),
    this.initialEvent,
  });

  final AppRoute route;
  final FallEvent? initialEvent;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex;
  FallEvent? _selectedEvent;
  bool _loadingEvent = false;
  String? _eventLoadError;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.route.pageIndex;
    _selectedEvent = widget.initialEvent;
    if (widget.route.eventId != null &&
        (_selectedEvent == null || !_selectedEvent!.isLocalRealtime)) {
      _loadDeepLinkedEvent(widget.route.eventId!);
    }
  }

  Future<void> _loadDeepLinkedEvent(String id) async {
    _loadingEvent = _selectedEvent == null;
    try {
      final event = await context.read<FallEventProvider>().loadEventById(id);
      if (!mounted) return;
      setState(() {
        _selectedEvent = event ?? _selectedEvent;
        _eventLoadError = _selectedEvent == null
            ? 'Không tìm thấy sự kiện.'
            : null;
        _loadingEvent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _eventLoadError = 'Không thể tải chi tiết sự kiện.';
        _loadingEvent = false;
      });
    }
  }

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard_rounded),
      label: 'Tổng quan',
    ),
    NavigationDestination(
      icon: Icon(Icons.monitor_heart_outlined),
      selectedIcon: Icon(Icons.monitor_heart_rounded),
      label: 'Realtime',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      selectedIcon: Icon(Icons.history_rounded),
      label: 'Lịch sử',
    ),
  ];

  void _openEvent(FallEvent event) {
    Navigator.of(context)
        .pushNamed(AppRoute.pathForEvent(event.id), arguments: event);
  }

  void _selectPage(int index) {
    if (index == _selectedIndex) return;
    Navigator.of(context).pushNamed(AppRoute.pathForPage(index));
  }

  @override
  Widget build(BuildContext context) {
    final telemetryProvider = context.watch<TelemetryProvider>();
    final fallEventProvider = context.watch<FallEventProvider>();
    final selectedEvent = _resolveSelectedEvent(
      _selectedEvent,
      telemetryProvider.events,
      fallEventProvider.events,
    );
    final screens = <Widget>[
      DashboardScreen(onOpenEvent: _openEvent),
      const RealtimeScreen(),
      HistoryScreen(onOpenEvent: _openEvent),
      if (_loadingEvent)
        const Center(child: CircularProgressIndicator())
      else if (selectedEvent == null && _eventLoadError != null)
        Center(child: Text(_eventLoadError!))
      else
        EventDetailScreen(
          event: selectedEvent,
          onBack: () => _selectPage(2),
          onRefresh: selectedEvent != null && !selectedEvent.isLocalRealtime
              ? () => _loadDeepLinkedEvent(selectedEvent.id)
              : null,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 900;

        return Scaffold(
          body: Row(
            children: [
              if (useRail)
                NavigationRail(
                  selectedIndex: _selectedIndex.clamp(0, 2),
                  onDestinationSelected: _selectPage,
                  extended: constraints.maxWidth >= 1180,
                  minExtendedWidth: 230,
                  leading: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 22, 12, 28),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.blue,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.health_and_safety_rounded,
                            color: Colors.white,
                          ),
                        ),
                        if (constraints.maxWidth >= 1180) ...[
                          const SizedBox(width: 12),
                          const Text(
                            'FallGuard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  destinations: [
                    for (final item in _destinations)
                      NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                  ],
                ),
              Expanded(
                child: IndexedStack(index: _selectedIndex, children: screens),
              ),
            ],
          ),
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex.clamp(0, 2),
                  onDestinationSelected: _selectPage,
                  destinations: _destinations,
                ),
        );
      },
    );
  }

  static FallEvent? _resolveSelectedEvent(
    FallEvent? selected,
    List<FallEvent> realtimeEvents,
    List<FallEvent> officialEvents,
  ) {
    if (selected == null) return null;

    for (final event in officialEvents) {
      if (event.id == selected.id && event.acknowledgedAt != null) return event;
    }

    for (final event in realtimeEvents) {
      if (event.id == selected.id ||
          (selected.isLocalRealtime &&
              (event.deviceId == selected.deviceId ||
                  event.device?.deviceCode == selected.deviceId))) {
        return event;
      }
    }
    for (final event in officialEvents) {
      if (event.id == selected.id) return event;
    }
    return selected;
  }
}
