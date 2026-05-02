import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Initializes the Supabase client when [SupabaseConfig] has URL and anon key.
/// If both are empty (e.g. tests, local runs without defines), initialization is skipped.
Future<void> initializeSupabaseIfConfigured() async {
  SupabaseConfig.assertConsistent();
  if (!SupabaseConfig.isConfigured) {
    if (kDebugMode) {
      debugPrint(
        'Supabase: not configured. Use --dart-define=SUPABASE_URL=... '
        '--dart-define=SUPABASE_ANON_KEY=...',
      );
    }
    return;
  }

  if (kDebugMode) {
    debugPrint('Supabase init: URL=${SupabaseConfig.url}');
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}
