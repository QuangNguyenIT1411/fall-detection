import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/fall_event.dart';
import '../models/realtime_update.dart';
import '../models/telemetry.dart';
import '../services/fall_event_repository.dart';
import '../services/telemetry_data_source.dart';

class TelemetryProvider extends ChangeNotifier {
  TelemetryProvider(
    this._dataSource, {
    this._officialEventRepository,
    this._onOfficialEvent,
    this._officialRetryDelays = const [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 2),
    ],
    this._officialStatusPollInterval = const Duration(seconds: 2),
    this._officialStatusPollTimeout = const Duration(seconds: 60),
    this.deviceOfflineTimeout = const Duration(seconds: 8),
    DateTime Function()? now,
  }) : _current = Telemetry(
         deviceId: _dataSource.deviceCode,
         acc: 0,
         gyro: 0,
         pose: 0,
         state: FallState.normal,
         timestamp: DateTime.now(),
       ),
       _devicePresence = _dataSource.source == TelemetrySource.mock
           ? DevicePresence.online
           : DevicePresence.unknown,
       _now = now ?? DateTime.now;

  static const maxPoints = 60;
  static const deviceWatchdogCheckInterval = Duration(seconds: 1);
  final TelemetryDataSource _dataSource;
  final FallEventRepository? _officialEventRepository;
  final void Function(FallEvent event)? _onOfficialEvent;
  final List<Duration> _officialRetryDelays;
  final Duration _officialStatusPollInterval;
  final Duration _officialStatusPollTimeout;
  final Duration deviceOfflineTimeout;
  final DateTime Function() _now;
  StreamSubscription<RealtimeUpdate>? _subscription;
  Timer? _deviceWatchdogTimer;
  Timer? _countdownTimer;
  Timer? _officialStatusTimer;
  bool _officialStatusRequestInFlight = false;
  String? _trackedOfficialEventId;
  DateTime? _officialPollStartedAt;

  Telemetry _current;
  DevicePresence _devicePresence;
  BrokerConnectionState _brokerState = BrokerConnectionState.disconnected;
  String? _connectionMessage;
  bool _hasTelemetry = false;
  final List<Telemetry> _history = [];
  final List<FallEvent> _events = [];
  bool _alertVisible = false;
  bool _disposed = false;
  DateTime? _activeFallReceivedAt;
  var _reconcileGeneration = 0;

  Telemetry get current => _current;
  List<Telemetry> get history => List.unmodifiable(_history);
  List<FallEvent> get events => List.unmodifiable(_events);
  bool get alertVisible => _alertVisible;
  bool get isSimulating => _dataSource.isSimulating;
  bool get canSimulate => _dataSource.supportsSimulation;
  bool get hasTelemetry => _hasTelemetry;
  TelemetrySource get source => _dataSource.source;
  BrokerConnectionState get brokerState => _brokerState;
  DevicePresence get devicePresence => _devicePresence;
  DateTime? get lastDeviceMessageAt => _lastDeviceMessageAt;
  String? get connectionMessage => _connectionMessage;
  int? get confirmationSecondsRemaining => _events.isEmpty
      ? null
      : _events.first.confirmationSecondsRemaining(DateTime.now().toUtc());

  Device get device => Device(
    id: source == TelemetrySource.mock
        ? 'local-${_dataSource.deviceCode}'
        : 'mqtt-${_dataSource.deviceCode}',
    deviceCode: _dataSource.deviceCode,
    name: source == TelemetrySource.mock
        ? 'Thiết bị phòng khách'
        : 'Thiết bị ${_dataSource.deviceCode}',
    isOnline: _devicePresence == DevicePresence.online,
    lastSeen: source == TelemetrySource.mqtt
        ? _lastDeviceMessageAt
        : _hasTelemetry
        ? _current.timestamp
        : null,
    createdAt: _current.timestamp,
  );

  void start() {
    _subscription ??= _dataSource.updates.listen(_onUpdate);
    if (source == TelemetrySource.mqtt) {
      _deviceWatchdogTimer ??= Timer.periodic(
        deviceWatchdogCheckInterval,
        (_) => _checkDevicePresence(),
      );
    }
    unawaited(_dataSource.start());
  }

  Future<void> simulateFall() async {
    if (!canSimulate) return;
    notifyListeners();
    await _dataSource.simulateFall();
    notifyListeners();
  }

  void resetSimulation() {
    if (!canSimulate) return;
    _alertVisible = false;
    _dataSource.resetSimulation();
  }

  void dismissAlert() {
    _alertVisible = false;
    notifyListeners();
  }

  void _onUpdate(RealtimeUpdate update) {
    switch (update) {
      case TelemetryUpdate(:final telemetry):
        if (telemetry.deviceId != _dataSource.deviceCode) break;
        _markDeviceMessageReceived();
        _onTelemetry(telemetry);
      case FallStateUpdate(:final deviceId, :final state, :final timestamp):
        if (deviceId == _dataSource.deviceCode) {
          _markDeviceMessageReceived();
        }
        _onState(deviceId, state, timestamp);
      case DeviceStatusUpdate(:final deviceId, :final presence):
        if (deviceId == _dataSource.deviceCode) {
          if (presence == DevicePresence.online) {
            _markDeviceMessageReceived();
          } else {
            _devicePresence = DevicePresence.offline;
            _hasTelemetry = false;
          }
        }
      case BrokerStatusUpdate(:final state, :final message):
        _brokerState = state;
        _connectionMessage = message;
    }
    notifyListeners();
  }

  DateTime? _lastDeviceMessageAt;

  void _markDeviceMessageReceived() {
    if (source != TelemetrySource.mqtt) return;
    _lastDeviceMessageAt = _now();
    _devicePresence = DevicePresence.online;
  }

  void _checkDevicePresence() {
    if (_disposed || _devicePresence != DevicePresence.online) return;
    final lastMessage = _lastDeviceMessageAt;
    if (lastMessage == null ||
        _now().difference(lastMessage) <= deviceOfflineTimeout) {
      return;
    }
    _devicePresence = DevicePresence.offline;
    _hasTelemetry = false;
    notifyListeners();
  }

  void _onTelemetry(Telemetry telemetry) {
    final wasDetected = _current.state == FallState.fallDetected;
    _current = telemetry;
    _hasTelemetry = true;
    _history.add(telemetry);
    if (_history.length > maxPoints) _history.removeAt(0);
    _handleFallTransition(wasDetected, telemetry.timestamp);
  }

  void _onState(String deviceId, FallState state, DateTime timestamp) {
    if (deviceId != _dataSource.deviceCode) return;
    final wasDetected = _current.state == FallState.fallDetected;
    _current = Telemetry(
      deviceId: deviceId,
      acc: _current.acc,
      gyro: _current.gyro,
      pose: _current.pose,
      state: state,
      timestamp: timestamp,
    );
    _handleFallTransition(wasDetected, timestamp);
  }

  void _handleFallTransition(bool wasDetected, DateTime receivedAt) {
    if (_current.state == FallState.fallDetected && !wasDetected) {
      _createFallAlert(receivedAt);
      return;
    }

    if (wasDetected && _current.state == FallState.normal) {
      _alertVisible = false;
      final activeEvent = _events.isEmpty ? null : _events.first;
      if (activeEvent != null &&
          !activeEvent.isLocalRealtime &&
          activeEvent.status == FallEventStatus.confirmed) {
        _activeFallReceivedAt = null;
        _stopOfficialStatusTracking();
        return;
      }
      final fallReceivedAt = _activeFallReceivedAt ?? receivedAt;
      _startOfficialReconciliation(
        fallReceivedAt: fallReceivedAt,
        requireCancelled: true,
      );
    }
  }

  void _createFallAlert(DateTime receivedAt) {
    _stopOfficialStatusTracking();
    _alertVisible = true;
    _activeFallReceivedAt = receivedAt;
    _events.insert(
      0,
      FallEvent(
        id: 'LOCAL-${DateTime.now().millisecondsSinceEpoch}',
        deviceId: _current.deviceId,
        detectedAt: receivedAt,
        peakAcc: _hasTelemetry ? _current.acc : null,
        peakGyro: _hasTelemetry ? _current.gyro : null,
        finalPose: _hasTelemetry ? _current.pose : null,
        lowGDurationMs: null,
        lowGToImpactMs: null,
        status: FallEventStatus.detected,
        cancelledAt: null,
        createdAt: receivedAt,
        isLocalRealtime: true,
      ),
    );
    _startOfficialReconciliation(
      fallReceivedAt: receivedAt,
      requireCancelled: false,
    );
  }

  void _startOfficialReconciliation({
    required DateTime fallReceivedAt,
    required bool requireCancelled,
  }) {
    final repository = _officialEventRepository;
    if (repository == null || _officialRetryDelays.isEmpty) return;
    final generation = ++_reconcileGeneration;
    unawaited(
      _reconcileOfficialEvent(
        repository: repository,
        generation: generation,
        fallReceivedAt: fallReceivedAt,
        requireCancelled: requireCancelled,
      ),
    );
  }

  Future<void> _reconcileOfficialEvent({
    required FallEventRepository repository,
    required int generation,
    required DateTime fallReceivedAt,
    required bool requireCancelled,
  }) async {
    for (final delay in _officialRetryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (_disposed || generation != _reconcileGeneration) return;

      try {
        final official = await repository.getLatestFallEventForDevice(
          _dataSource.deviceCode,
          detectedAfter: fallReceivedAt.subtract(const Duration(seconds: 15)),
        );
        if (_disposed || generation != _reconcileGeneration) return;
        if (official == null ||
            (requireCancelled && official.status == FallEventStatus.detected)) {
          continue;
        }

        final index = _events.indexWhere(
          (event) =>
              event.id == official.id ||
              (event.isLocalRealtime &&
                  event.deviceId == _dataSource.deviceCode),
        );
        if (index >= 0) {
          _events[index] = official;
        } else {
          _events.insert(0, official);
        }
        _onOfficialEvent?.call(official);
        _trackOfficialStatus(official);
        if (requireCancelled) _activeFallReceivedAt = null;
        notifyListeners();
        return;
      } catch (error, stackTrace) {
        debugPrint('Chưa thể đối chiếu fall event Supabase: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void _trackOfficialStatus(FallEvent event) {
    _stopOfficialStatusTracking();
    if (event.isLocalRealtime || event.status != FallEventStatus.detected) {
      if (event.status == FallEventStatus.cancelled) _alertVisible = false;
      return;
    }

    _trackedOfficialEventId = event.id;
    _officialPollStartedAt = DateTime.now();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      if (_officialPollingTimedOut()) {
        _stopOfficialStatusTracking();
        return;
      }
      notifyListeners();
    });
    _officialStatusTimer = Timer.periodic(_officialStatusPollInterval, (_) {
      if (_officialPollingTimedOut()) {
        _stopOfficialStatusTracking();
        return;
      }
      unawaited(_refreshOfficialEvent(event.id));
    });
  }

  bool _officialPollingTimedOut() {
    final startedAt = _officialPollStartedAt;
    return startedAt != null &&
        DateTime.now().difference(startedAt) >= _officialStatusPollTimeout;
  }

  Future<void> _refreshOfficialEvent(String eventId) async {
    final repository = _officialEventRepository;
    if (repository == null || _officialStatusRequestInFlight || _disposed) {
      return;
    }
    _officialStatusRequestInFlight = true;
    try {
      final official = await repository.getFallEventById(eventId);
      if (official == null || _disposed || eventId != _trackedOfficialEventId) {
        return;
      }
      final index = _events.indexWhere((event) => event.id == eventId);
      if (index >= 0) {
        _events[index] = official;
      } else {
        _events.insert(0, official);
      }
      _onOfficialEvent?.call(official);
      if (official.status != FallEventStatus.detected) {
        _stopOfficialStatusTracking();
        if (official.status == FallEventStatus.cancelled) {
          _alertVisible = false;
          _activeFallReceivedAt = null;
        }
      }
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Chưa thể refresh trạng thái fall event: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _officialStatusRequestInFlight = false;
    }
  }

  void _stopOfficialStatusTracking() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _officialStatusTimer?.cancel();
    _officialStatusTimer = null;
    _trackedOfficialEventId = null;
    _officialPollStartedAt = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _deviceWatchdogTimer?.cancel();
    _reconcileGeneration++;
    _stopOfficialStatusTracking();
    _subscription?.cancel();
    _dataSource.dispose();
    super.dispose();
  }
}
