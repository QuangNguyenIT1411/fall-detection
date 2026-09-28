import 'package:flutter/foundation.dart';

import '../models/fall_event.dart';
import '../services/fall_event_repository.dart';

enum FallEventLoadStatus { initial, loading, success, error }

class FallEventProvider extends ChangeNotifier {
  FallEventProvider(this._repository);

  final FallEventRepository _repository;
  FallEventLoadStatus _status = FallEventLoadStatus.initial;
  List<FallEvent> _events = const [];
  String? _errorMessage;
  int _loadGeneration = 0;
  int _upsertVersion = 0;
  final Map<String, int> _eventUpsertVersions = {};
  bool _disposed = false;

  FallEventLoadStatus get status => _status;
  List<FallEvent> get events => List.unmodifiable(_events);
  String? get errorMessage => _errorMessage;

  Future<void> loadEvents() async {
    final loadGeneration = ++_loadGeneration;
    final upsertVersionAtStart = _upsertVersion;
    _status = FallEventLoadStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched = await _repository.getFallEvents();
      if (_disposed || loadGeneration != _loadGeneration) return;
      final byId = <String, FallEvent>{
        for (final event in fetched) event.id: event,
      };
      for (final event in _events) {
        if ((_eventUpsertVersions[event.id] ?? 0) > upsertVersionAtStart) {
          byId[event.id] = _preferTerminal(byId[event.id], event);
        }
      }
      _events = _newestFirst(byId.values);
      _status = FallEventLoadStatus.success;
    } catch (error, stackTrace) {
      if (_disposed || loadGeneration != _loadGeneration) return;
      debugPrint('Không thể tải lịch sử Supabase: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (_upsertVersion > upsertVersionAtStart && _events.isNotEmpty) {
        _status = FallEventLoadStatus.success;
      } else {
        _errorMessage = error is StateError
            ? error.message
            : 'Không thể tải dữ liệu từ máy chủ.';
        _status = FallEventLoadStatus.error;
      }
    }
    notifyListeners();
  }

  Future<void> refresh() => loadEvents();

  Future<FallEvent?> loadEventById(String id) async {
    final event = await _repository.getFallEventById(id);
    if (event != null && !_disposed) upsertOfficialEvent(event);
    return event;
  }

  void upsertOfficialEvent(FallEvent event) {
    if (_disposed) return;
    final existing = _events.where((item) => item.id == event.id).firstOrNull;
    final latest = _preferTerminal(existing, event);
    _eventUpsertVersions[event.id] = ++_upsertVersion;
    _events = _newestFirst([
      ..._events.where((item) => item.id != event.id),
      latest,
    ]);
    _status = FallEventLoadStatus.success;
    _errorMessage = null;
    notifyListeners();
  }

  static List<FallEvent> _newestFirst(Iterable<FallEvent> events) {
    final sorted = events.toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return sorted;
  }

  static FallEvent _preferTerminal(FallEvent? existing, FallEvent incoming) {
    if (existing == null) return incoming;
    if (existing.acknowledgedAt != null && incoming.acknowledgedAt == null) {
      return existing;
    }
    if (existing.status != FallEventStatus.detected &&
        incoming.status == FallEventStatus.detected) {
      return existing;
    }
    return incoming;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    super.dispose();
  }
}
