import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/ratings/mock_ratings_repository.dart';
import 'package:nexora/app/storage/memory_kv_store.dart';

void main() {
  test('Prevents duplicate rating per shift per rater->rated', () async {
    final store = MemoryKvStore();
    final repo = MockRatingsRepository(store);

    await repo.create(
      gigId: 'gig1',
      raterUserId: 'u1',
      ratedUserId: 'u2',
      stars: 5,
      feedback: 'Great',
    );

    expect(
      () => repo.create(
        gigId: 'gig1',
        raterUserId: 'u1',
        ratedUserId: 'u2',
        stars: 4,
      ),
      throwsA(isA<StateError>()),
    );
  });
}

