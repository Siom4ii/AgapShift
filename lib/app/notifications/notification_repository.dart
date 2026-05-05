import '../../domain/models.dart';

abstract interface class NotificationRepository {
  Future<List<AppNotification>> listForUser(String userId);

  Future<void> add({
    required String userId,
    required String title,
    required String body,
    Map<String, String>? data,
  });

  Future<void> markRead({required String notificationId});
}
