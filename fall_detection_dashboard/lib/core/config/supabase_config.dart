import 'dart:convert';

abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;

  static bool get isProductionCompatible =>
      isConfigured &&
      url == 'https://nuwcsqdedelgfkjpmrsj.supabase.co' &&
      isPublicKey(anonKey);

  static bool isPublicKey(String key) {
    if (key.startsWith('sb_publishable_')) return true;
    try {
      final parts = key.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return payload is Map<String, dynamic> && payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  static String get missingConfigMessage =>
      'Chưa cấu hình Supabase. Hãy chạy ứng dụng với '
      '--dart-define=SUPABASE_URL=... và '
      '--dart-define=SUPABASE_ANON_KEY=...';
}
