import 'dart:convert';
import 'dart:math' as math;

import '../../domain/enums.dart';
import '../../domain/models.dart';
import '../storage/kv_store.dart';
import 'marketplace_repository.dart';

class MockMarketplaceRepository implements MarketplaceRepository {
  MockMarketplaceRepository(this._store);

  final KvStore _store;

  static const _kGigs = 'agapshift.marketplace.gigs';
  static const _kApplications = 'agapshift.marketplace.applications';
  static const _kHires = 'agapshift.marketplace.hires'; // gigId -> workerId

  Future<List<Gig>> listGigs() async {
    final raw = await _store.getString(_kGigs);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _gigFromJson(e as Map<String, dynamic>)).toList();
  }

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
    final gigs = await listGigs();
    final id = 'gig_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().toUtc();
    final gig = Gig(
      id: id,
      businessId: businessId,
      title: title,
      description: description,
      location: location,
      addressLabel: addressLabel,
      startAt: startAt.toUtc(),
      endAt: endAt.toUtc(),
      pay: pay,
      category: category,
      status: GigStatus.open,
      createdAt: now,
    );
    await _saveGigs([...gigs, gig]);
    return gig;
  }

  Future<Gig?> getGig(String gigId) async {
    final gigs = await listGigs();
    for (final g in gigs) {
      if (g.id == gigId) return g;
    }
    return null;
  }

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
      if (category != null && category.isNotEmpty && g.category != category) continue;
      if (minPayAmount != null && g.pay.amount < minPayAmount) continue;
      final d = _distanceMeters(center, g.location);
      if (d > radiusMeters) continue;
      filtered.add(_ScoredGig(gig: g, distanceMeters: d));
    }
    filtered.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return filtered.map((e) => e.gig).toList();
  }

  Future<List<GigApplication>> listApplications() async {
    final raw = await _store.getString(_kApplications);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _appFromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<GigApplication>> listApplicants(String gigId) async {
    final apps = await listApplications();
    return apps.where((a) => a.gigId == gigId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<GigApplication> applyToGig({
    required String gigId,
    required String workerId,
  }) async {
    final gig = await getGig(gigId);
    if (gig == null) throw StateError('Gig not found');
    if (gig.status != GigStatus.open) throw StateError('Gig is not open');

    final apps = await listApplications();
    final already = apps.any((a) => a.gigId == gigId && a.workerId == workerId);
    if (already) throw StateError('Already applied');

    final id = 'app_${DateTime.now().microsecondsSinceEpoch}';
    final app = GigApplication(
      id: id,
      gigId: gigId,
      workerId: workerId,
      status: ApplicationStatus.applied,
      createdAt: DateTime.now().toUtc(),
    );
    await _saveApps([...apps, app]);
    return app;
  }

  Future<HireResult> hireApplicant({
    required String gigId,
    required String applicationId,
    required String businessId,
  }) async {
    final gigs = await listGigs();
    final idx = gigs.indexWhere((g) => g.id == gigId);
    if (idx < 0) throw StateError('Gig not found');
    final gig = gigs[idx];
    if (gig.businessId != businessId) throw StateError('Not gig owner');
    if (gig.status != GigStatus.open) throw StateError('Gig is not open');

    final apps = await listApplications();
    final appIdx = apps.indexWhere((a) => a.id == applicationId && a.gigId == gigId);
    if (appIdx < 0) throw StateError('Application not found');
    final selected = apps[appIdx];

    // Update all applications for that gig.
    final updatedApps = apps.map((a) {
      if (a.gigId != gigId) return a;
      if (a.id == selected.id) {
        return GigApplication(
          id: a.id,
          gigId: a.gigId,
          workerId: a.workerId,
          status: ApplicationStatus.hired,
          createdAt: a.createdAt,
        );
      }
      if (a.status == ApplicationStatus.applied) {
        return GigApplication(
          id: a.id,
          gigId: a.gigId,
          workerId: a.workerId,
          status: ApplicationStatus.rejected,
          createdAt: a.createdAt,
        );
      }
      return a;
    }).toList();
    await _saveApps(updatedApps);

    // Update gig status to filled.
    final updatedGig = Gig(
      id: gig.id,
      businessId: gig.businessId,
      title: gig.title,
      description: gig.description,
      location: gig.location,
      addressLabel: gig.addressLabel,
      startAt: gig.startAt,
      endAt: gig.endAt,
      pay: gig.pay,
      category: gig.category,
      status: GigStatus.filled,
      createdAt: gig.createdAt,
    );
    final updatedGigs = [...gigs]..[idx] = updatedGig;
    await _saveGigs(updatedGigs);

    // Save hire mapping for convenience.
    final hiresRaw = await _store.getString(_kHires);
    final hires = (hiresRaw == null || hiresRaw.isEmpty)
        ? <String, String>{}
        : Map<String, String>.from(jsonDecode(hiresRaw) as Map);
    hires[gigId] = selected.workerId;
    await _store.setString(_kHires, jsonEncode(hires));

    final rejected = updatedApps
        .where((a) => a.gigId == gigId && a.status == ApplicationStatus.rejected)
        .map((a) => a.workerId)
        .toSet()
        .toList();
    return HireResult(selectedWorkerId: selected.workerId, rejectedWorkerIds: rejected);
  }

  Future<void> cancelGig({required String gigId, required String businessId}) async {
    final gigs = await listGigs();
    final idx = gigs.indexWhere((g) => g.id == gigId);
    if (idx < 0) throw StateError('Gig not found');
    final gig = gigs[idx];
    if (gig.businessId != businessId) throw StateError('Not gig owner');
    if (gig.status == GigStatus.completed) throw StateError('Cannot cancel completed gig');

    final updated = Gig(
      id: gig.id,
      businessId: gig.businessId,
      title: gig.title,
      description: gig.description,
      location: gig.location,
      addressLabel: gig.addressLabel,
      startAt: gig.startAt,
      endAt: gig.endAt,
      pay: gig.pay,
      category: gig.category,
      status: GigStatus.cancelled,
      createdAt: gig.createdAt,
    );
    final updatedGigs = [...gigs]..[idx] = updated;
    await _saveGigs(updatedGigs);
  }

  Future<String?> getHiredWorkerId(String gigId) async {
    final hiresRaw = await _store.getString(_kHires);
    if (hiresRaw == null || hiresRaw.isEmpty) return null;
    final hires = Map<String, String>.from(jsonDecode(hiresRaw) as Map);
    return hires[gigId];
  }

  Future<void> _saveGigs(List<Gig> gigs) async {
    final encoded = gigs.map(_gigToJson).toList();
    await _store.setString(_kGigs, jsonEncode(encoded));
  }

  Future<void> _saveApps(List<GigApplication> apps) async {
    final encoded = apps.map(_appToJson).toList();
    await _store.setString(_kApplications, jsonEncode(encoded));
  }

  Map<String, dynamic> _gigToJson(Gig g) => {
        'id': g.id,
        'businessId': g.businessId,
        'title': g.title,
        'description': g.description,
        'location': {'lat': g.location.lat, 'lng': g.location.lng},
        'addressLabel': g.addressLabel,
        'startAt': g.startAt.toIso8601String(),
        'endAt': g.endAt.toIso8601String(),
        'pay': {'amount': g.pay.amount, 'currency': g.pay.currency},
        'category': g.category,
        'status': g.status.name,
        'createdAt': g.createdAt.toIso8601String(),
      };

  Gig _gigFromJson(Map<String, dynamic> j) => Gig(
        id: j['id'] as String,
        businessId: j['businessId'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        location: GeoPoint(
          lat: (j['location']['lat'] as num).toDouble(),
          lng: (j['location']['lng'] as num).toDouble(),
        ),
        addressLabel: j['addressLabel'] as String,
        startAt: DateTime.parse(j['startAt'] as String),
        endAt: DateTime.parse(j['endAt'] as String),
        pay: Money(
          amount: j['pay']['amount'] as int,
          currency: j['pay']['currency'] as String,
        ),
        category: j['category'] as String,
        status: GigStatus.values.firstWhere((e) => e.name == (j['status'] as String)),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  Map<String, dynamic> _appToJson(GigApplication a) => {
        'id': a.id,
        'gigId': a.gigId,
        'workerId': a.workerId,
        'status': a.status.name,
        'createdAt': a.createdAt.toIso8601String(),
      };

  GigApplication _appFromJson(Map<String, dynamic> j) => GigApplication(
        id: j['id'] as String,
        gigId: j['gigId'] as String,
        workerId: j['workerId'] as String,
        status: ApplicationStatus.values.firstWhere((e) => e.name == (j['status'] as String)),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  int _distanceMeters(GeoPoint a, GeoPoint b) {
    // MVP approximation: treat 1 degree ~= 111km and use Euclidean distance.
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

