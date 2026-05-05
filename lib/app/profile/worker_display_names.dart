import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/business_identity.dart';
import '../../domain/worker_identity.dart';
import '../supabase/supabase_config.dart';

/// Resolves worker display names from [profiles.identity_snapshot].
///
/// Prefer RPC [worker_display_names_for_ids] (migration `010`) when RLS blocks
/// direct `profiles` reads. Falls back to `.select()` for any missing ids.
Future<Map<String, String>> fetchWorkerDisplayNamesById(
  Set<String> workerIds,
) async {
  final out = <String, String>{};
  if (!SupabaseConfig.isConfigured || workerIds.isEmpty) return out;
  final ids = workerIds.toList();

  try {
    final rows = await Supabase.instance.client.rpc(
      'worker_display_names_for_ids',
      params: {'p_ids': ids},
    );
    if (rows is List<dynamic>) {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final id = m['id']?.toString();
        final name = m['full_name']?.toString().trim();
        if (id != null && name != null && name.isNotEmpty) out[id] = name;
      }
    }
  } catch (_) {}

  if (out.length >= workerIds.length) return out;

  try {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('id, identity_snapshot')
        .inFilter('id', ids);
    final list = response as List<dynamic>;
    for (final raw in list) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final id = row['id']?.toString();
      if (id == null || out.containsKey(id)) continue;
      final snap = row['identity_snapshot'];
      String? n = workerIdentityFromProfileIdentitySnapshot(snap)
          ?.displayName
          .trim();
      if (n == null || n.isEmpty) {
        n = businessIdentityFromProfileIdentitySnapshot(snap)
            ?.displayName
            .trim();
      }
      if (n != null && n.isNotEmpty) out[id] = n;
    }
  } catch (_) {}

  return out;
}

String applicantDisplayNameFallback(String workerId) {
  final id = workerId.trim();
  if (id.length <= 10) return 'Worker $id';
  return 'Worker …${id.substring(id.length - 6)}';
}

String initialsFromWorkerId(String id) {
  final t = id.trim();
  if (t.isEmpty) return '?';
  final alnum = t.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (alnum.length >= 2) {
    return alnum.substring(0, 2).toUpperCase();
  }
  return t.substring(0, t.length >= 2 ? 2 : 1).toUpperCase();
}

String applicantInitialsFromName(String name, String workerId) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty && parts.first.length >= 2) {
    return parts.first.substring(0, 2).toUpperCase();
  }
  return initialsFromWorkerId(workerId);
}
