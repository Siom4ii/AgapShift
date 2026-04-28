import 'package:flutter/foundation.dart';

import '../../domain/models.dart';
import '../session/session_controller.dart';
import 'mock_marketplace_repository.dart';

class MarketplaceController extends ChangeNotifier {
  MarketplaceController({
    required this.repo,
    required this.session,
  });

  final MockMarketplaceRepository repo;
  final SessionController session;

  List<Gig> _nearby = const [];
  List<Gig> get nearby => _nearby;

  List<Gig> _businessGigs = const [];
  List<Gig> get businessGigs => _businessGigs;

  Future<void> refreshNearby({
    required GeoPoint center,
    required int radiusMeters,
    int? minPayAmount,
    String? category,
  }) async {
    _nearby = await repo.listNearbyGigs(
      center: center,
      radiusMeters: radiusMeters,
      minPayAmount: minPayAmount,
      category: category,
    );
    notifyListeners();
  }

  Future<void> refreshBusinessGigs() async {
    final businessId = session.state.email ?? 'business';
    final all = await repo.listGigs();
    _businessGigs = all.where((g) => g.businessId == businessId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }
}

