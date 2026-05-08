import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models.dart';
import '../supabase/supabase_config.dart';
import 'ratings_repository.dart';

class SupabaseRatingsRepository implements RatingsRepository {
  SupabaseRatingsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<List<Rating>> listForUser(String userId) async {
    if (!SupabaseConfig.isConfigured) return const [];
    try {
      final rows = await _client
          .from('ratings')
          .select()
          .eq('rated_user_id', userId)
          .order('created_at', ascending: false);
      final list = rows as List<dynamic>;
      return list
          .map((e) => _fromRow(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on PostgrestException catch (e) {
      // If migration hasn't been applied yet, don't break the UI.
      if (e.code == 'PGRST205') return const [];
      rethrow;
    }
  }

  @override
  Future<Rating?> getForShift({
    required String gigId,
    required String raterUserId,
    required String ratedUserId,
  }) async {
    if (!SupabaseConfig.isConfigured) return null;
    try {
      final row = await _client
          .from('ratings')
          .select()
          .eq('gig_id', gigId)
          .eq('rater_user_id', raterUserId)
          .eq('rated_user_id', ratedUserId)
          .maybeSingle();
      if (row == null) return null;
      return _fromRow(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') return null;
      rethrow;
    }
  }

  @override
  Future<Rating> create({
    required String gigId,
    required String raterUserId,
    required String ratedUserId,
    required int stars,
    String? feedback,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError('Supabase not configured');
    }
    if (stars < 1 || stars > 5) throw StateError('Stars must be 1-5');
    final cleaned = feedback?.trim();
    try {
      final row = await _client.from('ratings').insert({
        'gig_id': gigId,
        'rater_user_id': raterUserId,
        'rated_user_id': ratedUserId,
        'stars': stars,
        'feedback': (cleaned == null || cleaned.isEmpty) ? null : cleaned,
      }).select().single();
      return _fromRow(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') {
        throw StateError('Ratings are not available yet. Please update the server.');
      }
      rethrow;
    }
  }

  @override
  Future<double> averageForUser(String userId) async {
    if (!SupabaseConfig.isConfigured) return 0;
    try {
      final rows = await _client
          .from('ratings')
          .select('stars')
          .eq('rated_user_id', userId);
      final list = rows as List<dynamic>;
      if (list.isEmpty) return 0;
      var sum = 0;
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final s = m['stars'];
        sum += s is int ? s : int.tryParse('$s') ?? 0;
      }
      return sum / list.length;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205') return 0;
      rethrow;
    }
  }

  Rating _fromRow(Map<String, dynamic> row) {
    final created = row['created_at'] ?? row['createdAt'];
    final createdAt = created is String ? DateTime.parse(created) : DateTime.now().toUtc();
    return Rating(
      id: row['id'] as String,
      gigId: row['gig_id'] as String,
      raterUserId: row['rater_user_id'] as String,
      ratedUserId: row['rated_user_id'] as String,
      stars: row['stars'] as int,
      createdAt: createdAt,
      feedback: row['feedback'] as String?,
    );
  }
}

