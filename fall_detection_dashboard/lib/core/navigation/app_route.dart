class AppRoute {
  const AppRoute(this.path, this.pageIndex, {this.eventId});

  final String path;
  final int pageIndex;
  final String? eventId;

  static AppRoute fromPath(String? path) {
    final uri = Uri.tryParse(path ?? '/');
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.isEmpty || segments.singleOrNull == 'overview') {
      return const AppRoute('/', 0);
    }
    if (segments.singleOrNull == 'realtime') {
      return const AppRoute('/realtime', 1);
    }
    if (segments.singleOrNull == 'history') {
      return const AppRoute('/history', 2);
    }
    if (segments.length == 2 && segments.first == 'events' &&
        segments.last.isNotEmpty) {
      return AppRoute('/events/${Uri.encodeComponent(segments.last)}', 3,
          eventId: segments.last);
    }
    return const AppRoute('/', 0);
  }

  static String pathForPage(int index) => switch (index) {
    1 => '/realtime',
    2 => '/history',
    _ => '/',
  };

  static String pathForEvent(String id) => '/events/${Uri.encodeComponent(id)}';
}
