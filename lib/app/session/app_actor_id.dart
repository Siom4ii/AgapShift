import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import 'session_controller.dart';

/// Stable id for linking data to the signed-in user: Supabase Auth user id when
/// configured, otherwise the demo email stored in session.
String appActorId(SessionController session, {required String mockFallback}) {
  if (SupabaseConfig.isConfigured) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) return uid;
  }
  final email = session.state.email;
  if (email != null && email.isNotEmpty) return email;
  return mockFallback;
}
