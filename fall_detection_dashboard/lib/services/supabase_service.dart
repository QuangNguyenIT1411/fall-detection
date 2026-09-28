import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/device.dart';
import '../models/fall_event.dart';
import 'fall_event_repository.dart';

class DatabaseReadException implements Exception {
  const DatabaseReadException(this.message, this.cause);

  final String message;
  final Object cause;

  @override
  String toString() => message;
}

class SupabaseService implements FallEventRepository {
  const SupabaseService(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Device>> getDevices() async {
    try {
      final rows = await _client.from('devices').select().order('created_at');
      return rows.map(Device.fromJson).toList();
    } catch (error) {
      throw DatabaseReadException('Không thể tải danh sách thiết bị.', error);
    }
  }

  @override
  Future<Device?> getDeviceByCode(String code) async {
    try {
      final row = await _client
          .from('devices')
          .select()
          .eq('device_code', code)
          .maybeSingle();
      return row == null ? null : Device.fromJson(row);
    } catch (error) {
      throw DatabaseReadException('Không thể tải thông tin thiết bị.', error);
    }
  }

  @override
  Future<List<FallEvent>> getFallEvents() async {
    try {
      final rows = await _client
          .from('fall_events')
          .select('*, devices(*)')
          .order('detected_at', ascending: false)
          .limit(100);
      return rows.map(FallEvent.fromJson).toList();
    } catch (error) {
      throw DatabaseReadException('Không thể tải lịch sử té ngã.', error);
    }
  }

  @override
  Future<FallEvent?> getFallEventById(String id) async {
    try {
      final row = await _client
          .from('fall_events')
          .select('*, devices(*)')
          .eq('id', id)
          .maybeSingle();
      return row == null ? null : FallEvent.fromJson(row);
    } catch (error) {
      throw DatabaseReadException('Không thể tải chi tiết sự kiện.', error);
    }
  }

  @override
  Future<FallEvent?> getLatestFallEventForDevice(
    String deviceCode, {
    required DateTime detectedAfter,
  }) async {
    try {
      final row = await _client
          .from('fall_events')
          .select('*, devices!inner(*)')
          .eq('devices.device_code', deviceCode)
          .gte('detected_at', detectedAfter.toUtc().toIso8601String())
          .order('detected_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : FallEvent.fromJson(row);
    } catch (error) {
      throw DatabaseReadException(
        'Không thể đối chiếu sự kiện té ngã mới nhất.',
        error,
      );
    }
  }
}
