import 'telemetry.dart';

class RecentStateEntry {
  const RecentStateEntry({required this.state, required this.receivedAt});

  final FallState state;
  final DateTime receivedAt;
}
