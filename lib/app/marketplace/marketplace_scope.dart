import 'package:flutter/material.dart';

import '../messaging/messaging_repository.dart';
import '../messaging/mock_messaging_repository.dart';
import '../messaging/supabase_messaging_repository.dart';
import '../notifications/mock_notification_repository.dart';
import '../notifications/notification_repository.dart';
import '../notifications/supabase_notification_repository.dart';
import '../payments/mock_payments_repository.dart';
import '../payments/payments_repository.dart';
import '../payments/stub_payments_repository.dart';
import '../ratings/mock_ratings_repository.dart';
import '../session/session_controller.dart';
import '../shift/mock_shift_repository.dart';
import '../shift/shift_repository.dart';
import '../shift/supabase_shift_repository.dart';
import '../storage/kv_store.dart';
import '../supabase/supabase_config.dart';
import 'marketplace_repository.dart';
import 'mock_marketplace_repository.dart';
import 'supabase_marketplace_repository.dart';

class MarketplaceScope extends InheritedWidget {
  const MarketplaceScope({
    super.key,
    required this.repo,
    required this.notifications,
    required this.payments,
    required this.ratings,
    required this.shift,
    required this.messaging,
    required this.session,
    required super.child,
  });

  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final PaymentsRepository payments;
  final MockRatingsRepository ratings;
  final ShiftRepository shift;
  final MessagingRepository messaging;
  final SessionController session;

  static MarketplaceScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MarketplaceScope>();
    assert(scope != null, 'MarketplaceScope not found');
    return scope!;
  }

  static MarketplaceScope? tryOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<MarketplaceScope>();
  }

  static MarketplaceScope fromStore({
    required KvStore store,
    required SessionController session,
    required Widget child,
  }) {
    return MarketplaceScope(
      repo: SupabaseConfig.isConfigured
          ? SupabaseMarketplaceRepository()
          : MockMarketplaceRepository(store),
      notifications: SupabaseConfig.isConfigured
          ? SupabaseNotificationRepository()
          : MockNotificationRepository(store),
      payments: SupabaseConfig.isConfigured
          ? StubPaymentsRepository()
          : MockPaymentsRepository(store),
      ratings: MockRatingsRepository(store),
      shift: SupabaseConfig.isConfigured
          ? SupabaseShiftRepository()
          : MockShiftRepository(store),
      messaging: SupabaseConfig.isConfigured
          ? SupabaseMessagingRepository()
          : MockMessagingRepository(store, session),
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
        messaging != oldWidget.messaging ||
        session != oldWidget.session;
  }
}

