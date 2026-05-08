import 'dart:convert';

import '../../domain/models.dart';
import '../storage/kv_store.dart';
import 'ratings_repository.dart';

class MockRatingsRepository implements RatingsRepository {
  MockRatingsRepository(this._store);

  final KvStore _store;

  static const _kRatings = 'agapshift.ratings.items'; // list

  @override
  Future<List<Rating>> listForUser(String userId) async {
    final all = await _loadAll();
    return all.where((r) => r.ratedUserId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<Rating?> getForShift({
    required String gigId,
    required String raterUserId,
    required String ratedUserId,
  }) async {
    final all = await _loadAll();
    for (final r in all) {
      if (r.gigId == gigId && r.raterUserId == raterUserId && r.ratedUserId == ratedUserId) {
        return r;
      }
    }
    return null;
  }

  @override
  Future<Rating> create({
    required String gigId,
    required String raterUserId,
    required String ratedUserId,
    required int stars,
    String? feedback,
  }) async {
    if (stars < 1 || stars > 5) throw StateError('Stars must be 1-5');
    final existing = await getForShift(gigId: gigId, raterUserId: raterUserId, ratedUserId: ratedUserId);
    if (existing != null) throw StateError('Already rated for this shift');

    final now = DateTime.now().toUtc();
    final rating = Rating(
      id: 'rate_${now.microsecondsSinceEpoch}',
      gigId: gigId,
      raterUserId: raterUserId,
      ratedUserId: ratedUserId,
      stars: stars,
      createdAt: now,
      feedback: feedback?.trim().isEmpty ?? true ? null : feedback!.trim(),
    );
    final all = await _loadAll();
    await _saveAll([rating, ...all]);
    return rating;
  }

  @override
  Future<double> averageForUser(String userId) async {
    final items = await listForUser(userId);
    if (items.isEmpty) return 0;
    final sum = items.fold<int>(0, (acc, r) => acc + r.stars);
    return sum / items.length;
  }

  Future<List<Rating>> _loadAll() async {
    final raw = await _store.getString(_kRatings);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _saveAll(List<Rating> items) async {
    await _store.setString(_kRatings, jsonEncode(items.map(_toJson).toList()));
  }

  Map<String, dynamic> _toJson(Rating r) => {
        'id': r.id,
        'gigId': r.gigId,
        'raterUserId': r.raterUserId,
        'ratedUserId': r.ratedUserId,
        'stars': r.stars,
        'createdAt': r.createdAt.toIso8601String(),
        'feedback': r.feedback,
      };

  Rating _fromJson(Map<String, dynamic> j) => Rating(
        id: j['id'] as String,
        gigId: j['gigId'] as String,
        raterUserId: j['raterUserId'] as String,
        ratedUserId: j['ratedUserId'] as String,
        stars: j['stars'] as int,
        createdAt: DateTime.parse(j['createdAt'] as String),
        feedback: j['feedback'] as String?,
      );
}

