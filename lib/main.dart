import 'package:flutter/material.dart';

import 'app/auth/mock_auth_service.dart';
import 'app/marketplace/marketplace_scope.dart';
import 'app/session/session_controller.dart';
import 'app/storage/shared_prefs_kv_store.dart';
import 'app/ui/session_gate.dart';
import 'app/ui/theme/agap_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    await session.load();
    if (!mounted) return;
    setState(() {
      _store = store;
      _session = session;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final store = _store;
    return MaterialApp(
      title: 'AgapShift',
      theme: AgapTheme.light(),
      home: session == null || store == null
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : MarketplaceScope.fromStore(
              store: store,
              session: session,
              child: SessionGate(session: session),
            ),
    );
  }
}
