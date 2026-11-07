import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

/// A controllable clock for deterministic availability checks.
class _Clock {
  _Clock(this.now);
  DateTime now;
  DateTime call() => now;
}

void main() {
  late YallaCashStore store;
  late _Clock clock;
  late InMemoryYallaCashRepository repository;

  // Damascus is UTC+3: Nov 1 starts at Oct 31 21:00Z and the day after
  // Nov 30 starts at Nov 30 21:00Z.
  final novStart = DateTime.utc(2026, 10, 31, 21);
  final novEndsBefore = DateTime.utc(2026, 11, 30, 21);
  const micro = Duration(microseconds: 1);

  setUp(() {
    store = YallaCashStore.demo();
    clock = _Clock(DateTime.utc(2026, 11, 15, 12));
    repository = InMemoryYallaCashRepository(store, clock: clock.call);
  });

  Future<StoreOffer> create(
    String title, {
    String storeId = 'store-001',
    OfferCalendarDate? start,
    OfferCalendarDate? end,
    bool isActive = true,
    int displayOrder = 0,
  }) =>
      repository.createOffer(
        storeId,
        StoreOfferDraft(
          title: title,
          startDate: start,
          endDate: end,
          isActive: isActive,
          displayOrder: displayOrder,
        ),
      );

  test('starts empty: no demo offers are fabricated', () async {
    for (final s in store.stores) {
      expect(await repository.listAdminStoreOffers(s.id), isEmpty);
    }
  });

  test('create returns the admin shape with both date forms', () async {
    final offer = await create(
      'عرض نوفمبر',
      start: OfferCalendarDate(2026, 11, 1),
      end: OfferCalendarDate(2026, 11, 30),
    );

    expect(offer.storeId, 'store-001');
    expect(offer.startDate.toString(), '2026-11-01');
    expect(offer.endDate.toString(), '2026-11-30');
    expect(offer.startsAt, novStart);
    expect(offer.endsBefore, novEndsBefore);
    expect(offer.serverStatus, OfferStatus.active);
    expect(offer.imageAccess, OfferImageAccess.adminPreview);
    expect(offer.hasImage, isFalse);
    expect(offer.imageVersion, 0);
  });

  test('customers see only active offers; admins see every status',
      () async {
    await create('active-open');
    await create('active-window',
        start: OfferCalendarDate(2026, 11, 1),
        end: OfferCalendarDate(2026, 11, 30));
    await create('scheduled', start: OfferCalendarDate(2026, 12, 1));
    await create('expired', end: OfferCalendarDate(2026, 10, 31));
    await create('inactive', isActive: false);

    final public = await repository.listStoreOffers('store-001');
    expect(public.map((o) => o.title).toSet(), {'active-open', 'active-window'});
    expect(public.every((o) => o.imageAccess == OfferImageAccess.public),
        isTrue);
    // Public offers carry no admin-only fields, like the API.
    expect(public.every((o) => o.serverStatus == null), isTrue);
    expect(public.every((o) => o.displayOrder == null), isTrue);

    final admin = await repository.listAdminStoreOffers('store-001');
    expect(
      {for (final o in admin) o.title: o.serverStatus},
      {
        'active-open': OfferStatus.active,
        'active-window': OfferStatus.active,
        'scheduled': OfferStatus.scheduled,
        'expired': OfferStatus.expired,
        'inactive': OfferStatus.inactive,
      },
    );
  });

  test('UTC boundaries: startsAt inclusive, endsBefore exclusive', () async {
    await create('window',
        start: OfferCalendarDate(2026, 11, 1),
        end: OfferCalendarDate(2026, 11, 30));

    Future<int> visibleAt(DateTime now) async {
      clock.now = now;
      return (await repository.listStoreOffers('store-001')).length;
    }

    expect(await visibleAt(novStart.subtract(micro)), 0);
    expect(await visibleAt(novStart), 1);
    expect(await visibleAt(novEndsBefore.subtract(micro)), 1);
    expect(await visibleAt(novEndsBefore), 0);
  });

  test('a one-day offer is visible for exactly that Damascus day', () async {
    final offer = await create('one day',
        start: OfferCalendarDate(2026, 11, 20),
        end: OfferCalendarDate(2026, 11, 20));
    expect(offer.endsBefore!.difference(offer.startsAt!),
        const Duration(days: 1));
  });

  test('ordering: displayOrder ascending, then newest first', () async {
    await create('order1-first', displayOrder: 1);
    await create('order0', displayOrder: 0);
    clock.now = clock.now.add(const Duration(minutes: 1));
    await create('order1-newer', displayOrder: 1);
    await create('order1-newest-same-time', displayOrder: 1);

    final titles = (await repository.listAdminStoreOffers('store-001'))
        .map((o) => o.title);
    expect(titles, [
      'order0',
      'order1-newest-same-time',
      'order1-newer',
      'order1-first',
    ]);
    expect((await repository.listStoreOffers('store-001')).map((o) => o.title),
        titles);
  });

  test('offers stay with their own store', () async {
    await create('AA', storeId: 'store-001');
    await create('BB', storeId: 'store-002');

    expect((await repository.listStoreOffers('store-001')).single.title, 'AA');
    expect((await repository.listStoreOffers('store-002')).single.title, 'BB');
    expect(await repository.listStoreOffers('store-003'), isEmpty);
  });

  test('update changes only the targeted offer and only given fields',
      () async {
    final target = await create('target',
        start: OfferCalendarDate(2026, 11, 1),
        end: OfferCalendarDate(2026, 11, 30));
    final other = await create('other');
    clock.now = clock.now.add(const Duration(hours: 1));

    final updated = await repository.updateOffer(
      target.id,
      const StoreOfferUpdate(
        description: OfferFieldUpdate.set('جديد'),
        discountLabel: OfferFieldUpdate.set('  خصم 5%  '),
        endDate: OfferFieldUpdate.clear(),
      ),
    );

    expect(updated.title, 'target');
    expect(updated.description, 'جديد');
    expect(updated.discountLabel, 'خصم 5%');
    expect(updated.startDate, OfferCalendarDate(2026, 11, 1));
    expect(updated.endDate, isNull);
    expect(updated.endsBefore, isNull);
    expect(updated.updatedAt, clock.now);
    expect(updated.createdAt, target.createdAt);

    final admin = await repository.listAdminStoreOffers('store-001');
    expect(admin.firstWhere((o) => o.id == other.id), other);
  });

  test('clearing description gives "" and a blank label gives null',
      () async {
    final offer = await create('x1');
    await repository.updateOffer(
        offer.id,
        const StoreOfferUpdate(
            description: OfferFieldUpdate.set('d'),
            discountLabel: OfferFieldUpdate.set('L')));
    final cleared = await repository.updateOffer(
      offer.id,
      const StoreOfferUpdate(
        description: OfferFieldUpdate.clear(),
        discountLabel: OfferFieldUpdate.set('   '),
      ),
    );
    expect(cleared.description, '');
    expect(cleared.discountLabel, isNull);
  });

  test('an empty update returns the offer unchanged', () async {
    final offer = await create('same');
    clock.now = clock.now.add(const Duration(days: 1));
    final result =
        await repository.updateOffer(offer.id, const StoreOfferUpdate());
    expect(result.updatedAt, offer.updatedAt);
    expect(result.title, offer.title);
  });

  test('the combined window is validated and a rejected update changes nothing',
      () async {
    final offer = await create('ww',
        start: OfferCalendarDate(2026, 11, 10),
        end: OfferCalendarDate(2026, 11, 20));

    await expectLater(
      repository.updateOffer(
        offer.id,
        StoreOfferUpdate(
          title: 'changed',
          endDate: OfferFieldUpdate.set(OfferCalendarDate(2026, 11, 9)),
        ),
      ),
      throwsA(isA<YallaCashFailure>()
          .having((f) => f.statusCode, 'statusCode', 400)),
    );
    final stored =
        (await repository.listAdminStoreOffers('store-001')).single;
    expect(stored.title, 'ww');
    expect(stored.endDate, OfferCalendarDate(2026, 11, 20));
  });

  test('create validates like the backend', () async {
    Future<void> rejects(StoreOfferDraft draft) => expectLater(
          repository.createOffer('store-001', draft),
          throwsA(isA<YallaCashFailure>()
              .having((f) => f.statusCode, 'statusCode', 400)),
        );

    await rejects(const StoreOfferDraft(title: ' a '));
    await rejects(StoreOfferDraft(title: 'x' * 121));
    await rejects(StoreOfferDraft(title: 'ok', description: 'd' * 1001));
    await rejects(StoreOfferDraft(title: 'ok', discountLabel: 'l' * 61));
    await rejects(const StoreOfferDraft(title: 'ok', displayOrder: -1));
    await rejects(const StoreOfferDraft(title: 'ok', displayOrder: 10000));
    await rejects(StoreOfferDraft(
      title: 'ok',
      startDate: OfferCalendarDate(2026, 11, 2),
      endDate: OfferCalendarDate(2026, 11, 1),
    ));
    await rejects(
        StoreOfferDraft(title: 'ok', startDate: OfferCalendarDate(1999, 1, 1)));
    expect(await repository.listAdminStoreOffers('store-001'), isEmpty);
  });

  test('delete removes exactly one offer', () async {
    final a = await create('aa');
    final b = await create('bb');

    await repository.deleteOffer(a.id);

    final remaining = await repository.listAdminStoreOffers('store-001');
    expect(remaining.map((o) => o.id), [b.id]);
    await expectLater(repository.deleteOffer(a.id),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)));
  });

  test('images: upload and removal bump the version; URLs are versioned',
      () async {
    final offer = await create('img');

    final uploaded = await repository.setOfferImage(offer.id,
        const StoreLogoUpload(bytes: [1, 2, 3], contentType: 'image/webp'));
    expect(uploaded.imageVersion, 1);
    expect(uploaded.imageUrl, '/admin/offers/${offer.id}/image?v=1');

    final replaced = await repository.setOfferImage(offer.id,
        const StoreLogoUpload(bytes: [4, 5], contentType: 'image/png'));
    expect(replaced.imageVersion, 2);
    expect(
        (await repository.listStoreOffers('store-001')).single.imageUrl,
        '/offers/${offer.id}/image?v=2');

    final preview = await repository.fetchAdminOfferImage(offer.id);
    expect(preview.bytes, [4, 5]);
    expect(preview.contentType, 'image/png');

    final removed = await repository.removeOfferImage(offer.id);
    expect(removed.imageVersion, 3);
    expect(removed.hasImage, isFalse);
    expect(removed.imageUrl, isNull);
    await expectLater(repository.fetchAdminOfferImage(offer.id),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)));
  });

  test('the admin preview works for inactive offers too', () async {
    final offer = await create('hidden', isActive: false);
    await repository.setOfferImage(offer.id,
        const StoreLogoUpload(bytes: [9], contentType: 'image/jpeg'));

    expect(await repository.listStoreOffers('store-001'), isEmpty);
    expect((await repository.fetchAdminOfferImage(offer.id)).bytes, [9]);
  });

  test('invalid images are rejected before the offer changes', () async {
    final offer = await create('img');
    for (final upload in [
      const StoreLogoUpload(bytes: [1], contentType: 'image/gif'),
      const StoreLogoUpload(bytes: [], contentType: 'image/png'),
      StoreLogoUpload(bytes: List.filled(300 * 1024 + 1, 0),
          contentType: 'image/png'),
    ]) {
      await expectLater(repository.setOfferImage(offer.id, upload),
          throwsA(isA<YallaCashFailure>()));
    }
    expect(
        (await repository.listAdminStoreOffers('store-001')).single.imageVersion,
        0);
  });

  test('store rules: inactive store hidden from customers, kept for admins',
      () async {
    await create('kept', storeId: 'store-002');
    store.deleteStore('store-002'); // soft delete: isActive = false

    await expectLater(repository.listStoreOffers('store-002'),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)));
    expect(await repository.listAdminStoreOffers('store-002'), hasLength(1));

    await expectLater(repository.listAdminStoreOffers('missing'),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)));
    await expectLater(create('x1', storeId: 'missing'),
        throwsA(isA<YallaCashFailure>()));
  });

  test('offer operations leave existing demo data unchanged', () async {
    final storesBefore = store.stores.toList();
    final bannersBefore = store.banners.toList();
    final productsBefore = store.products.toList();

    final offer = await create('x1');
    await repository.updateOffer(
        offer.id, const StoreOfferUpdate(isActive: false));
    await repository.deleteOffer(offer.id);

    expect(store.stores.toList(), storesBefore);
    expect(store.banners.toList(), bannersBefore);
    expect(store.products.toList(), productsBefore);
  });
}
