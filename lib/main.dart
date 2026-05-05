import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app/auth/mock_auth_service.dart';
import 'app/database/app_database.dart';
import 'app/database/sqflite_platform.dart';
import 'app/supabase/supabase_bootstrap.dart';
import 'app/supabase/supabase_env.dart';
import 'app/marketplace/marketplace_scope.dart';
import 'app/session/session_controller.dart';
import 'app/storage/shared_prefs_kv_store.dart';
import 'app/ui/session_gate.dart';
import 'app/ui/theme/agap_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSupabaseDotEnv();
  configureSqfliteForPlatform();
  await initializeSupabaseIfConfigured();
  runApp(const AgapShiftBootstrap());
}

class AgapShiftBootstrap extends StatefulWidget {
  const AgapShiftBootstrap({super.key});

  @override
  State<AgapShiftBootstrap> createState() => _AgapShiftBootstrapState();
}

class _AgapShiftBootstrapState extends State<AgapShiftBootstrap> {
  SessionController? _session;
  SharedPrefsKvStore? _store;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store = await SharedPrefsKvStore.create();
    final session = SessionController(store: store, auth: MockAuthService());
    session.bindSupabaseAuthSync();
    await session.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _session = session;
    });
    // Local SQLite is not used on Flutter Web (no dart:io / sqflite path).
    if (!kIsWeb) {
      unawaited(AppDatabase.instance.database);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final store = _store;
    final ready = session != null && store != null;
    return MaterialApp(
      title: 'AgapShift',
      debugShowCheckedModeBanner: false,
      theme: AgapTheme.light(),
      // Scope must wrap the [Navigator], not only [home], so pushed routes
      // (Messages inbox/thread, modals, etc.) still see [MarketplaceScope].
      builder: ready
          ? (context, child) => MarketplaceScope.fromStore(
                store: store,
                session: session,
                child: child ?? const SizedBox.shrink(),
              )
          : null,
      home: ready
          ? SessionGate(session: session)
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
