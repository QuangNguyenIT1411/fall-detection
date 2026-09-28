import '../models/realtime_update.dart';

abstract interface class TelemetryDataSource {
  TelemetrySource get source;
  String get deviceCode;
  Stream<RealtimeUpdate> get updates;
  bool get supportsSimulation;
  bool get isSimulating;

  Future<void> start();
  Future<void> simulateFall();
  void resetSimulation();
  Future<void> disconnect();
  void dispose();
}
