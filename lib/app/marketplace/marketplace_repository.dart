import '../../domain/models.dart';

/// Result of hiring one applicant for a gig.
class HireResult {
  HireResult({required this.selectedWorkerId, required this.rejectedWorkerIds});
  final String selectedWorkerId;
  final List<String> rejectedWorkerIds;
}

/// Marketplace persistence — mock KV or Supabase.
abstract class MarketplaceRepository {
  Future<List<Gig>> listGigs();

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
  });

  Future<Gig?> getGig(String gigId);

  Future<List<Gig>> listNearbyGigs({
    required GeoPoint center,
    required int radiusMeters,
    int? minPayAmount,
    String? category,
  });

  /// Every [GigStatus.open] job in product scope (e.g. region). No distance cap.
  /// When [sortCenter] is set, results are ordered nearest-first.
  Future<List<Gig>> listOpenJobsFeed({
    GeoPoint? sortCenter,
    int? minPayAmount,
    String? category,
  });

  Future<List<GigApplication>> listApplications();

  Future<List<GigApplication>> listApplicants(String gigId);

  Future<GigApplication> applyToGig({
    required String gigId,
    required String workerId,
  });

  Future<HireResult> hireApplicant({
    required String gigId,
    required String applicationId,
    required String businessId,
  });

  Future<void> cancelGig({required String gigId, required String businessId});

  Future<String?> getHiredWorkerId(String gigId);
}
