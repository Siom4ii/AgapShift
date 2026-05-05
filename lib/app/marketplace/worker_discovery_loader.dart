import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../../domain/worker_identity.dart';
import '../location/davao_del_sur_scope.dart';
import '../location/geo_distance.dart';
import '../location/user_geo_point.dart';
import '../profile/worker_display_names.dart';
import '../ratings/mock_ratings_repository.dart';
import '../session/app_actor_id.dart';
import '../session/session_controller.dart';
import '../shift/shift_repository.dart';
import '../supabase/supabase_config.dart';
import 'marketplace_repository.dart';

/// Row for business “Find Workers” — built from profiles + marketplace data.
class DiscoverableWorker {
  const DiscoverableWorker({
    required this.workerId,
    required this.initials,
    required this.displayName,
    required this.verified,
    required this.availability,
    required this.availabilityHighlight,
    required this.rating,
    required this.shiftsCompleted,
    required this.skillTags,
    required this.distanceKm,
    required this.rateLabel,
    required this.hiredByMe,
    this.bio,
    this.ageYears,
    this.phone,
  });

  final String workerId;
  final String initials;
  final String displayName;
  final bool verified;
  final String availability;
  final bool availabilityHighlight;
  final double rating;
  final int shiftsCompleted;
  final List<String> skillTags;
  final double distanceKm;
  final String rateLabel;
  final bool hiredByMe;
  final String? bio;
  final int? ageYears;
  final String? phone;
}

int? _ageYearsFromBirthDate(DateTime? bd) {
  if (bd == null) return null;
  final today = DateTime.now();
  var y = today.year - bd.year;
  final hadBirthday = today.month > bd.month ||
      (today.month == bd.month && today.day >= bd.day);
  if (!hadBirthday) y--;
  return y.clamp(0, 120);
}

Future<List<DiscoverableWorker>> loadDiscoverableWorkers({
  required MarketplaceRepository repo,
  required SessionController session,
  required MockRatingsRepository ratings,
  required ShiftRepository shiftRepo,
}) async {
  final businessId = appActorId(session, mockFallback: '');
  final refCenter = await _resolveRefCenter();
  final gigs = await repo.listGigs();
  final apps = await repo.listApplications();
  final myGigIds =
      gigs.where((g) => g.businessId == businessId).map((g) => g.id).toSet();

  final hiredPairs = apps
      .where(
        (a) =>
            myGigIds.contains(a.gigId) &&
            a.status == ApplicationStatus.hired,
      )
      .map((a) => a.workerId)
      .toSet();

  final shiftSessions = await shiftRepo.listShiftSessions();

  Map<String, WorkerIdentityDisplay?> identities = {};
  Map<String, bool> verifiedById = {};

  if (SupabaseConfig.isConfigured) {
    final fetched = await _fetchWorkerIdentitiesFromSupabase(
      excludeUserId: Supabase.instance.client.auth.currentUser?.id,
    );
    identities = fetched.identities;
    verifiedById = fetched.verified;
  }

  final fromApps = _workerIdentitiesFromApplications(
    apps: apps,
    gigs: gigs,
    businessGigIds: myGigIds,
  );
  for (final e in fromApps.entries) {
    identities.putIfAbsent(e.key, () => e.value);
  }

  if (SupabaseConfig.isConfigured) {
    final needsName = identities.entries
        .where((e) {
          final v = e.value;
          return v == null || v.displayName.trim().isEmpty;
        })
        .map((e) => e.key)
        .toSet();
    if (needsName.isNotEmpty) {
      final names = await fetchWorkerDisplayNamesById(needsName);
      for (final id in needsName) {
        final name = names[id]?.trim();
        if (name == null || name.isEmpty) continue;
        final old = identities[id];
        identities[id] = WorkerIdentityDisplay(
          displayName: name,
          tagline: old?.tagline,
          bio: old?.bio,
          skills: (old != null && old.skills.isNotEmpty)
              ? old.skills
              : _fallbackSkills(id),
          phone: old?.phone,
          addressLine: old?.addressLine,
          birthDate: old?.birthDate,
        );
      }
    }
  }

  final ids = identities.keys.toList();
  if (ids.isEmpty) {
    return [];
  }

  final completedByWorker =
      await _completedShiftCountsByWorker(ids, shiftSessions);

  final out = <DiscoverableWorker>[];
  for (final id in ids) {
    final snap = identities[id];
    final displayName = snap?.displayName.trim().isNotEmpty == true
        ? snap!.displayName.trim()
        : applicantDisplayNameFallback(id);
    final tags = snap?.skills.isNotEmpty == true
        ? snap!.skills.take(4).toList()
        : _fallbackSkills(id);

    final avg = await ratings.averageForUser(id);
    final shifts = completedByWorker[id] ?? 0;

    final recentApp = apps
        .where((a) => a.workerId == id)
        .fold<DateTime?>(
          null,
          (prev, a) =>
              prev == null || a.createdAt.isAfter(prev) ? a.createdAt : prev,
        );
    final avail = _availabilityLabel(recentApp);

    final rateLabel =
        _rateLabelFromGigs(gigs, apps.where((a) => a.workerId == id).map((a) => a.gigId).toSet());

    final km = _distanceKmForWorker(id, refCenter);

    final workerVerified = verifiedById[id] ??
        (avg > 0 || hiredPairs.contains(id));

    final bio = snap?.bio?.trim();
    final phone = snap?.phone?.trim();
    final ageYears = _ageYearsFromBirthDate(snap?.birthDate);

    out.add(
      DiscoverableWorker(
        workerId: id,
        initials: _initials(displayName, id),
        displayName: displayName,
        verified: workerVerified,
        availability: avail.$1,
        availabilityHighlight: avail.$2,
        rating: avg,
        shiftsCompleted: shifts,
        skillTags: tags,
        distanceKm: km,
        rateLabel: rateLabel,
        hiredByMe: hiredPairs.contains(id),
        bio: bio != null && bio.isNotEmpty ? bio : null,
        ageYears: ageYears,
        phone: phone != null && phone.isNotEmpty ? phone : null,
      ),
    );
  }

  out.sort((a, b) {
    final ac = a.availabilityHighlight ? 0 : 1;
    final bc = b.availabilityHighlight ? 0 : 1;
    if (ac != bc) return ac.compareTo(bc);
    return b.rating.compareTo(a.rating);
  });

  return out;
}

Future<Map<String, int>> _completedShiftCountsByWorker(
  List<String> workerIds,
  List<ShiftSession> shiftSessions,
) async {
  if (workerIds.isEmpty) return {};
  if (!SupabaseConfig.isConfigured) {
    final m = <String, int>{};
    for (final s in shiftSessions) {
      if (s.checkOutAt == null) continue;
      m[s.workerId] = (m[s.workerId] ?? 0) + 1;
    }
    return m;
  }
  try {
    final raw = await Supabase.instance.client
        .rpc('worker_completed_shift_counts', params: {'p_ids': workerIds});
    if (raw is! List<dynamic>) return {};
    final out = <String, int>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final wid = row['worker_id']?.toString();
      final c = row['completed_count'];
      if (wid == null) continue;
      final n = c is int ? c : (c is num) ? c.toInt() : 0;
      out[wid] = n;
    }
    return out;
  } catch (_) {
    final m = <String, int>{};
    for (final s in shiftSessions) {
      if (s.checkOutAt == null) continue;
      m[s.workerId] = (m[s.workerId] ?? 0) + 1;
    }
    return m;
  }
}

Future<GeoPoint> _resolveRefCenter() async {
  final g = await tryGetCurrentUserGeoPoint();
  if (g != null && DavaoDelSurScope.contains(g)) {
    return g;
  }
  return DavaoDelSurScope.defaultCenter;
}

Future<({Map<String, WorkerIdentityDisplay?> identities, Map<String, bool> verified})>
    _fetchWorkerIdentitiesFromSupabase({
  String? excludeUserId,
}) async {
  final out = <String, WorkerIdentityDisplay?>{};
  final verified = <String, bool>{};

  void ingestRow(Map<String, dynamic> m) {
    final id = (m['profile_id'] ?? m['id'])?.toString();
    if (id == null || id.isEmpty) return;
    if (excludeUserId != null && id == excludeUserId) return;
    final snap = m['identity_snapshot'];
    out[id] = workerIdentityFromProfileIdentitySnapshot(snap);
    verified[id] = (m['account_status'] as String?) == 'verified';
  }

  try {
    final rpc = await Supabase.instance.client
        .rpc('worker_profiles_for_business_directory');
    if (rpc is List<dynamic> && rpc.isNotEmpty) {
      for (final raw in rpc) {
        if (raw is Map) ingestRow(Map<String, dynamic>.from(raw));
      }
      return (identities: out, verified: verified);
    }
  } catch (_) {}

  try {
    final rows = await Supabase.instance.client
        .from('profiles')
        .select('id, identity_snapshot, account_status')
        .eq('role', 'worker');

    final list = rows as List<dynamic>;
    for (final raw in list) {
      if (raw is Map) ingestRow(Map<String, dynamic>.from(raw));
    }
  } catch (_) {
    return (
      identities: <String, WorkerIdentityDisplay?>{},
      verified: <String, bool>{},
    );
  }
  return (identities: out, verified: verified);
}

/// Derive worker ids from applications: anyone who applied to **this business's
/// gigs** (always), plus anyone who applied to gigs pinned inside Davao del Sur
/// (regional discovery). Without the business-gig branch, workers who applied
/// only to your jobs but whose gig pin falls outside the polygon—or who have
/// not yet got `profiles.role = 'worker'` synced—would disappear from Find Workers.
Map<String, WorkerIdentityDisplay?> _workerIdentitiesFromApplications({
  required List<GigApplication> apps,
  required List<Gig> gigs,
  required Set<String> businessGigIds,
}) {
  final gigById = {for (final g in gigs) g.id: g};
  final workerIds = <String>{};
  for (final a in apps) {
    final g = gigById[a.gigId];
    if (g == null) continue;
    final appliedToMyJob = businessGigIds.contains(a.gigId);
    final regionalGig = DavaoDelSurScope.contains(g.location);
    if (appliedToMyJob || regionalGig) {
      workerIds.add(a.workerId);
    }
  }

  final out = <String, WorkerIdentityDisplay?>{};
  for (final id in workerIds) {
    out[id] = null;
  }
  return out;
}

(String, bool) _availabilityLabel(DateTime? lastApplicationAt) {
  if (lastApplicationAt == null) {
    return ('Open to shifts', false);
  }
  final days = DateTime.now().difference(lastApplicationAt.toLocal()).inDays;
  if (days <= 3) {
    return ('Available Now', true);
  }
  if (days <= 14) {
    return ('Available Soon', true);
  }
  return ('Available Tomorrow', false);
}

String _rateLabelFromGigs(List<Gig> gigs, Set<String> gigIds) {
  if (gigIds.isEmpty) return '—';
  final relevant = gigs.where((g) => gigIds.contains(g.id)).toList();
  if (relevant.isEmpty) return '—';
  var sum = 0.0;
  var n = 0;
  for (final g in relevant) {
    final minutes = g.endAt.difference(g.startAt).inMinutes;
    final hours = math.max(0.25, minutes / 60.0);
    final hourly = (g.pay.amount / 100.0) / hours;
    sum += hourly;
    n++;
  }
  if (n == 0) return '—';
  return '₱${(sum / n).round()}/hr';
}

double _distanceKmForWorker(String workerId, GeoPoint ref) {
  final h = workerId.hashCode.abs();
  final latOff = (h % 1000) / 48000.0;
  final lngOff = ((h ~/ 1000) % 1000) / 48000.0;
  final p = GeoPoint(lat: ref.lat + latOff, lng: ref.lng + lngOff);
  return geoDistanceMetersApprox(ref, p) / 1000.0;
}

List<String> _fallbackSkills(String id) {
  const pools = [
    ['Warehouse', 'Delivery'],
    ['Food Service', 'Retail'],
    ['Events', 'Warehouse'],
    ['Retail'],
  ];
  return pools[id.hashCode.abs() % pools.length];
}

String _initials(String name, String id) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2) {
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.isNotEmpty && parts.first.length >= 2) {
    return parts.first.substring(0, 2).toUpperCase();
  }
  final t = id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  if (t.length >= 2) return t.substring(0, 2).toUpperCase();
  return 'W${id.hashCode.abs() % 9}';
}

bool _skillMatchesCategory(List<String> skills, String categoryKey) {
  if (categoryKey.isEmpty) return true;
  final needle = categoryKey.toLowerCase();
  for (final s in skills) {
    if (s.toLowerCase().contains(needle)) return true;
  }
  return false;
}

bool _matchesCategory(DiscoverableWorker w, String categoryKey) {
  if (categoryKey.isEmpty) return true;
  final map = {
    'warehouse': 'warehouse',
    'food': 'food',
    'retail': 'retail',
    'event': 'event',
  };
  final needle = map[categoryKey] ?? categoryKey;
  return _skillMatchesCategory(w.skillTags, needle);
}

bool matchesWorkerSearch(DiscoverableWorker w, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (w.displayName.toLowerCase().contains(q)) return true;
  for (final s in w.skillTags) {
    if (s.toLowerCase().contains(q)) return true;
  }
  return false;
}

/// Exported for the Find Workers screen filters.
bool categoryFilterPass(DiscoverableWorker w, String categoryKey) =>
    _matchesCategory(w, categoryKey);
