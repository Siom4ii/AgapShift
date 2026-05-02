import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums.dart';
import '../../domain/models.dart';
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
    return list.map((e) => _gigFromRow(Map<String, dynamic>.from(e as Map))).toList();
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
  }) async {
    final row = await _client.from('gigs').insert({
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
    }).select().single();
    return _gigFromRow(Map<String, dynamic>.from(row));
  }

  @override
  Future<Gig?> getGig(String gigId) async {
    final row = await _client.from('gigs').select().eq('id', gigId).maybeSingle();
    if (row == null) return null;
    return _gigFromRow(Map<String, dynamic>.from(row));
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
    for (final g in gigs) {
      if (g.status != GigStatus.open) continue;
      if (category != null && category.isNotEmpty && g.category != category) {
        continue;
      }
      if (minPayAmount != null && g.pay.amount < minPayAmount) continue;
      final d = _distanceMeters(center, g.location);
      if (d > radiusMeters) continue;
      filtered.add(_ScoredGig(gig: g, distanceMeters: d));
    }
    filtered.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
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

  int _distanceMeters(GeoPoint a, GeoPoint b) {
    final dx = (a.lat - b.lat) * 111000.0;
    final dy = (a.lng - b.lng) * 111000.0;
    return math.sqrt(dx * dx + dy * dy).round();
  }
}

class _ScoredGig {
  _ScoredGig({required this.gig, required this.distanceMeters});
  final Gig gig;
  final int distanceMeters;
}
