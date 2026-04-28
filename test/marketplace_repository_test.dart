import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/marketplace/mock_marketplace_repository.dart';
import 'package:nexora/app/storage/memory_kv_store.dart';
import 'package:nexora/domain/models.dart';

void main() {
  test('Create gig, apply, hire updates statuses', () async {
    final store = MemoryKvStore();
    final repo = MockMarketplaceRepository(store);

    final gig = await repo.createGig(
      businessId: 'biz1',
      title: 'Kitchen Helper',
      description: 'Assist kitchen staff',
      location: const GeoPoint(lat: 14.6, lng: 121.0),
      addressLabel: 'QC',
      startAt: DateTime.utc(2026, 5, 1, 9),
      endAt: DateTime.utc(2026, 5, 1, 17),
      pay: const Money(amount: 80000),
      category: 'Food Service',
    );

    await repo.applyToGig(gigId: gig.id, workerId: 'w1');
    await repo.applyToGig(gigId: gig.id, workerId: 'w2');

    final appsBefore = await repo.listApplicants(gig.id);
    expect(appsBefore.length, 2);

    await repo.hireApplicant(gigId: gig.id, applicationId: appsBefore.first.id, businessId: 'biz1');

    final updated = await repo.getGig(gig.id);
    expect(updated!.status.name, 'filled');

    final appsAfter = await repo.listApplicants(gig.id);
    expect(appsAfter.where((a) => a.status.name == 'hired').length, 1);
    expect(appsAfter.where((a) => a.status.name == 'rejected').length, 1);
  });
}

