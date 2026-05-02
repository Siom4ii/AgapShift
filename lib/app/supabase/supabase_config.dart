import 'package:flutter_dotenv/flutter_dotenv.dart';

String? _dotenvGet(String key) {
  try {
    return dotenv.env[key];
  } catch (_) {
    return null;
  }
}

/// Supabase URL and anon key (Dashboard → Settings → API).
///
/// **Priority:** values in `assets/supabase.env`, then `--dart-define` /
/// `--dart-define-from-file` at build time.
///
/// Edit `assets/supabase.env` in this project to connect the app without CLI flags.
abstract final class SupabaseConfig {
  static String get url {
    final fromFile = _dotenvGet('SUPABASE_URL')?.trim();
    final raw = (fromFile != null && fromFile.isNotEmpty)
        ? fromFile
        : const String.fromEnvironment(
            'SUPABASE_URL',
            defaultValue: '',
          );
    return _normalizeSupabaseProjectUrl(raw);
  }

  /// Keeps only scheme + host (+ port). Drops `/rest/v1`, `/auth/v1`, etc.
  /// The SDK appends those paths; a configured URL that already contains
  /// `/rest/v1` yields broken requests like `/rest/v1//auth/v1/token`.
  static String _normalizeSupabaseProjectUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return trimmed;
    final scheme = uri.scheme.isEmpty ? 'https' : uri.scheme;
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  static String get anonKey {
    final fromFile = _dotenvGet('SUPABASE_ANON_KEY')?.trim();
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    return const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );
  }

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// Call before initializing to catch a half-set config.
  static void assertConsistent() {
    final hasUrl = url.isNotEmpty;
    final hasKey = anonKey.isNotEmpty;
    if (hasUrl != hasKey) {
      throw StateError(
        'Set both SUPABASE_URL and SUPABASE_ANON_KEY in assets/supabase.env '
        'or via --dart-define, or leave both unset.',
      );
    }
  }
}
