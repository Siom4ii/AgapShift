import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Loads [assets/supabase.env] so you can connect without passing long
/// `--dart-define` flags. Optional: still overridden by `--dart-define`.
Future<void> loadSupabaseDotEnv() async {
  try {
    await dotenv.load(fileName: 'assets/supabase.env');
  } catch (_) {
    // Missing asset (e.g. some tests) — rely on dart-define / mocks only.
  }
}
