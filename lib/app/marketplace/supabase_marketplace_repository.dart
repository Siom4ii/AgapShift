import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../location/davao_del_sur_scope.dart';
import '../location/geo_distance.dart';
import 'marketplace_repository.dart';

/// Postgres-backed gigs + applications ([supabase/migrations/001_marketplace.sql]).
class SupabaseMarketplaceRepository implements MarketplaceRepository {
  SupabaseMarketplaceRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<Gig>> listGigs() async {
    final rows = await _client.from('gigs').select();
    final list = rows as List<dynamic>;
    return list
        .map((e) => _gigFromRow(Map<String, dynamic>.from(e as Map)))
        .where((g) => DavaoDelSurScope.contains(g.location))
        .toList();
  }

  @override
  Future<Gig> createGig({
    required String businessId,
    required String title,
    required String description,
    required GeoPoint location,
    required String addressLabel,
    required DateTime startAt,
    required DateTime endAt,
    required Money pay,
    required String category,
    int? workersNeeded,
    bool isUrgent = false,
    DateTime? boostedUntil,
  }) async {
    if (!DavaoDelSurScope.contains(location)) {
      throw ArgumentError(
        'Gig location must be inside ${DavaoDelSurScope.regionLabel}.',
      );
    }
    final payload = <String, dynamic>{
      'business_id': businessId,
      'title': title,
      'description': description,
      'lat': location.lat,
      'lng': location.lng,
      'address_label': addressLabel,
      'start_at': startAt.toUtc().toIso8601String(),
      'end_at': endAt.toUtc().toIso8601String(),
      'pay_amount': pay.amount,
      'pay_currency': pay.currency,
      'category': category,
      'status': GigStatus.open.name,
      'is_urgent': isUrgent,
    };
    if (workersNeeded != null) {
      payload['workers_needed'] = workersNeeded;
    }
    if (boostedUntil != null) {
      payload['boosted_until'] = boostedUntil.toUtc().toIso8601String();
    }
    final row = await _client.from('gigs').insert(payload).select().single();
    return _gigFromRow(Map<String, dynamic>.from(row));
  }

  @override
  Future<Gig?> getGig(String gigId) async {
    final row = await _client.from('gigs').select().eq('id', gigId).maybeSingle();
    if (row == null) return null;
    final gig = _gigFromRow(Map<String, dynamic>.from(row));
    if (!DavaoDelSurScope.contains(gig.location)) return null;
    return gig;
  }

  @override
  Future<List<Gig>> listNearbyGigs({
    required GeoPoint center,
    required int radiusMeters,
    int? minPayAmount,
    String? category,
  }) async {
    final gigs = await listGigs();
    final filtered = <_ScoredGig>[];
    final now = DateTime.now().toUtc();
    for (final g in gigs) {
      if (g.status != GigStatus.open) continue;
      // Worker rule: don't show expired listings.
      if (!g.endAt.toUtc().isAfter(now)) continue;
      if (!DavaoDelSurScope.contains(g.location)) continue;
      if (category != null && category.isNotEmpty && g.category != category) {
        continue;
      }
      if (minPayAmount != null && g.pay.amount < minPayAmount) continue;
      final d = geoDistanceMeters(center, g.location);
      if (d > radiusMeters) continue;
      filtered.add(_ScoredGig(gig: g, distanceMeters: d));
    }
    _sortFeedByBoostThenDistance(filtered);
    return filtered.map((e) => e.gig).toList();
  }

  @override
  Future<List<Gig>> listOpenJobsFeed({
    GeoPoint? sortCenter,
    int? minPayAmount,
    String? category,
  }) async {
    final gigs = await listGigs();
    final filtered = <_ScoredGig>[];
    final center = sortCenter ?? DavaoDelSurScope.defaultCenter;
    final now = DateTime.now().toUtc();
    for (final g in gigs) {
      if (g.status != GigStatus.open) continue;
      // Worker rule: don't show expired listings.
      if (!g.endAt.toUtc().isAfter(now)) continue;
      if (!DavaoDelSurScope.contains(g.location)) continue;
      if (category != null && category.isNotEmpty && g.category != category) {
        continue;
      }
      if (minPayAmount != null && g.pay.amount < minPayAmount) continue;
      final d = geoDistanceMeters(center, g.location);
      filtered.add(_ScoredGig(gig: g, distanceMeters: d));
    }
    _sortFeedByBoostThenDistance(filtered);
    return filtered.map((e) => e.gig).toList();
  }

  @override
  Future<List<GigApplication>> listApplications() async {
    final rows = await _client.from('gig_applications').select();
    final list = rows as List<dynamic>;
    return list
        .map((e) => _appFromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<GigApplication>> listApplicants(String gigId) async {
    final rows =
        await _client.from('gig_applications').select().eq('gig_id', gigId);
    final list = rows as List<dynamic>;
    final apps =
        list.map((e) => _appFromRow(Map<String, dynamic>.from(e as Map))).toList();
    apps.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return apps;
  }

  @override
  Future<GigApplication> applyToGig({
    required String gigId,
    required String workerId,
  }) async {
    final gig = await getGig(gigId);
    if (gig == null) throw StateError('Gig not found');
    if (gig.status != GigStatus.open) throw StateError('Gig is not open');

    final apps = await listApplicants(gigId);
    final already = apps.any((a) => a.workerId == workerId);
    if (already) throw StateError('Already applied');

    final row = await _client.from('gig_applications').insert({
      'gig_id': gigId,
      'worker_id': workerId,
      'status': ApplicationStatus.applied.name,
    }).select().single();
    return _appFromRow(Map<String, dynamic>.from(row));
  }

  @override
  Future<HireResult> hireApplicant({
    required String gigId,
    required String applicationId,
    required String businessId,
  }) async {
    final gig = await getGig(gigId);
    if (gig == null) throw StateError('Gig not found');
    if (gig.businessId != businessId) throw StateError('Not gig owner');
    if (gig.status != GigStatus.open) throw StateError('Gig is not open');

    final apps = await listApplicants(gigId);
    final idx = apps.indexWhere((a) => a.id == applicationId);
    if (idx < 0) throw StateError('Application not found');
    final selected = apps[idx];

    for (final a in apps) {
      ApplicationStatus next;
      if (a.id == selected.id) {
        next = ApplicationStatus.hired;
      } else if (a.status == ApplicationStatus.applied) {
        next = ApplicationStatus.rejected;
      } else {
        next = a.status;
      }
      await _client.from('gig_applications').update({
        'status': next.name,
      }).eq('id', a.id);
    }

    await _client.from('gigs').update({
      'status': GigStatus.filled.name,
      'hired_worker_id': selected.workerId,
    }).eq('id', gigId);

    final rejectedWorkerIds = apps
        .where((a) => a.id != applicationId && a.status == ApplicationStatus.applied)
        .map((a) => a.workerId)
        .toList();

    return HireResult(
      selectedWorkerId: selected.workerId,
      rejectedWorkerIds: rejectedWorkerIds,
    );
  }

  @override
  Future<void> cancelGig({required String gigId, required String businessId}) async {
    final gig = await getGig(gigId);
    if (gig == null) throw StateError('Gig not found');
    if (gig.businessId != businessId) throw StateError('Not gig owner');
    if (gig.status == GigStatus.completed) {
      throw StateError('Cannot cancel completed gig');
    }
    await _client.from('gigs').update({
      'status': GigStatus.cancelled.name,
    }).eq('id', gigId);
  }

  @override
  Future<String?> getHiredWorkerId(String gigId) async {
    final row = await _client
        .from('gigs')
        .select('hired_worker_id')
        .eq('id', gigId)
        .maybeSingle();
    if (row == null) return null;
    final id = row['hired_worker_id'];
    if (id == null) return null;
    return id as String;
  }

  Gig _gigFromRow(Map<String, dynamic> row) {
    final wn = row['workers_needed'];
    final bu = row['boosted_until'];
    return Gig(
      id: row['id'] as String,
      businessId: row['business_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String,
      location: GeoPoint(
        lat: (row['lat'] as num).toDouble(),
        lng: (row['lng'] as num).toDouble(),
      ),
      addressLabel: row['address_label'] as String,
      startAt: DateTime.parse(row['start_at'] as String),
      endAt: DateTime.parse(row['end_at'] as String),
      pay: Money(
        amount: row['pay_amount'] as int,
        currency: row['pay_currency'] as String? ?? 'PHP',
      ),
      category: row['category'] as String,
      status: GigStatus.values.firstWhere((e) => e.name == row['status']),
      createdAt: DateTime.parse(row['created_at'] as String),
      workersNeeded: wn == null ? null : (wn as num).toInt(),
      isUrgent: row['is_urgent'] == true,
      boostedUntil: bu == null ? null : DateTime.parse(bu as String),
    );
  }

  GigApplication _appFromRow(Map<String, dynamic> row) {
    return GigApplication(
      id: row['id'] as String,
      gigId: row['gig_id'] as String,
      workerId: row['worker_id'] as String,
      status:
          ApplicationStatus.values.firstWhere((e) => e.name == row['status']),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

}

void _sortFeedByBoostThenDistance(List<_ScoredGig> filtered) {
  filtered.sort((a, b) {
    final ab = a.gig.isBoostedActive;
    final bb = b.gig.isBoostedActive;
    if (ab != bb) return ab ? -1 : 1;
    return a.distanceMeters.compareTo(b.distanceMeters);
  });
}

class _ScoredGig {
  _ScoredGig({required this.gig, required this.distanceMeters});
  final Gig gig;
  final int distanceMeters;
}
