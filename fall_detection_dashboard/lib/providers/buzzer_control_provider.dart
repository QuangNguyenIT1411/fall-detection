import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../services/buzzer_control_repository.dart';

class BuzzerControlProvider extends ChangeNotifier {
  BuzzerControlProvider(this._repository);
  final BuzzerControlRepository _repository;
  Device? _device;
  Device? get device => _device;
  bool _pending = false;
  bool get pending => _pending;
  String? _error;
  String? get error => _error;
  String? _message;
  String? get message => _message;
  bool _disposed = false;
  bool _refreshing = false;
  int _generation = 0;
  Timer? _timer;

  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(const Duration(seconds: 8), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_disposed || _pending || _refreshing) return;
    _refreshing = true;
    final generation = ++_generation;
    try {
      final device = await _repository.getDeviceByCode('device01');
      if (_disposed || generation != _generation) return;
      if (device == null) throw StateError('Device not found');
      _device = device;
      _error = null;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _error = 'Không thể đọc cấu hình còi. Hãy thử làm mới.';
    } finally {
      if (!_disposed && generation == _generation) {
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_disposed || _pending || _device == null) return;
    _pending = true;
    _error = null;
    _message = null;
    ++_generation; // Invalidate an older read that could undo this write.
    _refreshing = false;
    notifyListeners();
    try {
      final setting = await _repository.setBuzzerEnabled(enabled);
      if (_disposed) return;
      // This is the server's committed configuration, not a device ACK.
      _device = Device.fromJson({
        ..._device!.toJson(),
        'buzzer_enabled': setting.enabled,
        'buzzer_updated_at': setting.updatedAt.toUtc().toIso8601String(),
      });
      _message =
          'Đã lưu cấu hình còi. Thiết bị sẽ nhận qua heartbeat tiếp theo.';
      try {
        final latest = await _repository.getDeviceByCode('device01');
        if (_disposed) return;
        if (latest == null) throw StateError('Device not found');
        _device = latest;
      } catch (_) {
        if (_disposed) return;
        // Keep the authoritative Edge response if the follow-up read fails.
        _error = 'Đã lưu nhưng chưa thể làm mới cấu hình. Hãy thử làm mới.';
      }
    } catch (_) {
      if (_disposed) return;
      // No optimistic switch update: the previous value remains on failure.
      _error = 'Không thể lưu cấu hình còi. Vui lòng thử lại.';
    } finally {
      if (!_disposed) {
        _pending = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
