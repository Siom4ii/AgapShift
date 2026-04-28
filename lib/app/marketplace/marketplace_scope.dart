import 'package:flutter/material.dart';

import '../notifications/mock_notification_repository.dart';
import '../payments/mock_payments_repository.dart';
import '../ratings/mock_ratings_repository.dart';
import '../session/session_controller.dart';
import '../shift/mock_shift_repository.dart';
import '../storage/kv_store.dart';
import 'mock_marketplace_repository.dart';

class MarketplaceScope extends InheritedWidget {
  const MarketplaceScope({
    super.key,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.ratings,
    required this.shift,
    required this.session,
    required super.child,
  });

  final MockMarketplaceRepository repo;
  final MockNotificationRepository notifications;
  final MockPaymentsRepository payments;
  final MockRatingsRepository ratings;
  final MockShiftRepository shift;
  final SessionController session;

  static MarketplaceScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MarketplaceScope>();
    assert(scope != null, 'MarketplaceScope not found');
    return scope!;
  }

  static MarketplaceScope fromStore({
    required KvStore store,
    required SessionController session,
    required Widget child,
  }) {
    return MarketplaceScope(
      repo: MockMarketplaceRepository(store),
      notifications: MockNotificationRepository(store),
      payments: MockPaymentsRepository(store),
      ratings: MockRatingsRepository(store),
      shift: MockShiftRepository(store),
      session: session,
      child: child,
    );
  }

  @override
  bool updateShouldNotify(MarketplaceScope oldWidget) {
    return repo != oldWidget.repo ||
        notifications != oldWidget.notifications ||
        payments != oldWidget.payments ||
        ratings != oldWidget.ratings ||
        shift != oldWidget.shift ||
        session != oldWidget.session;
  }
}

