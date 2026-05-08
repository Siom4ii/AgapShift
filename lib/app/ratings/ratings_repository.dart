import '../../domain/models.dart';

abstract class RatingsRepository {
  Future<List<Rating>> listForUser(String userId);

  Future<Rating?> getForShift({
    required String gigId,
    required String raterUserId,
    required String ratedUserId,
  });

  Future<Rating> create({
    required String gigId,
    required String raterUserId,
    required String ratedUserId,
    required int stars,
    String? feedback,
  });

  Future<double> averageForUser(String userId);
}

