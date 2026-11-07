import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

StoreOffer _offer(String id, String storeId) =>
    StoreOffer(id: id, storeId: storeId, title: id);

/// Customer offer lists answered manually, so tests control the order in
/// which responses arrive.
class _ControlledRepository extends InMemoryYallaCashRepository {
  _ControlledRepository(super.store);

  final pending = <({String storeId, Completer<List<StoreOffer>> done})>[];

  @override
  Future<List<StoreOffer>> listStoreOffers(String storeId) {
    final done = Completer<List<StoreOffer>>();
    pending.add((storeId: storeId, done: done));
    return done.future;
  }
}

/// Counts admin preview downloads; can be told to fail.
class _ImageRepository extends InMemoryYallaCashRepository {
  _ImageRepository(super.store);

  var downloads = 0;
  var fail = false;

  @override
  Future<OfferImageData> fetchAdminOfferImage(
    String offerId, {
    int? imageVersion,
  }) async {
    downloads += 1;
    if (fail) {
      throw const YallaCashFailure(statusCode: 500, message: 'boom');
    }
    return OfferImageData(
      bytes: Uint8List.fromList([imageVersion ?? 0]),
      contentType: 'image/png',
    );
  }
}

/// Image upload always fails (to test partial success).
class _FailingImageUploadRepository extends InMemoryYallaCashRepository {
  _FailingImageUploadRepository(super.store);

  @override
  Future<StoreOffer> setOfferImage(String offerId, StoreLogoUpload image) =>
      Future.error(const YallaCashFailure(
        statusCode: 400,
        code: 'bad_request',
        message: 'bad image',
      ));
}

void main() {
  group('CustomerAppCubit.loadStoreOffers', () {
    late YallaCashStore store;

    setUp(() => store = YallaCashStore.demo()..loginDemoCustomer());

    test('loads one store without touching global status or other data',
        () async {
      final repository = InMemoryYallaCashRepository(store);
      await repository.createOffer(
          'store-001', const StoreOfferDraft(title: 'عرض'));
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);
      await cubit.refresh();
      final before = cubit.state;
      expect(before.status, LoadStatus.success);

      final states = <CustomerAppState>[];
      final sub = cubit.stream.listen(states.add);
      await cubit.loadStoreOffers('store-001');
      await sub.cancel();

      expect(states.first.offersFor('store-001').status, LoadStatus.loading);
      for (final state in states) {
        expect(state.status, LoadStatus.success);
        expect(state.stores, before.stores);
        expect(state.banners, before.banners);
        expect(state.points, before.points);
        expect(state.customer, before.customer);
        expect(state.failure, isNull);
      }
      final offers = cubit.state.offersFor('store-001');
      expect(offers.status, LoadStatus.success);
      expect(offers.offers.single.title, 'عرض');
      expect(cubit.state.offersFor('store-002').status, LoadStatus.initial);
    });

    test('a store without offers is empty, not a failure', () async {
      final cubit = CustomerAppCubit(InMemoryYallaCashRepository(store));
      addTearDown(cubit.close);

      await cubit.loadStoreOffers('store-003');

      expect(cubit.state.offersFor('store-003').status, LoadStatus.empty);
      expect(cubit.state.status, LoadStatus.initial);
    });

    test('a failure stays on that store and keeps the global state clean',
        () async {
      store.deleteStore('store-004'); // inactive store: 404
      final cubit = CustomerAppCubit(InMemoryYallaCashRepository(store));
      addTearDown(cubit.close);

      await cubit.loadStoreOffers('store-004');

      final offers = cubit.state.offersFor('store-004');
      expect(offers.status, LoadStatus.failure);
      expect(offers.failure?.statusCode, 404);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.status, LoadStatus.initial);
    });

    test('stores load independently and responses land on their own store',
        () async {
      final repository = _ControlledRepository(store);
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);

      final a = cubit.loadStoreOffers('store-001');
      final b = cubit.loadStoreOffers('store-002');
      expect(cubit.state.offersFor('store-001').isLoading, isTrue);
      expect(cubit.state.offersFor('store-002').isLoading, isTrue);

      // B answers first; A is still loading.
      repository.pending[1].done.complete([_offer('b1', 'store-002')]);
      await b;
      expect(cubit.state.offersFor('store-002').offers.single.id, 'b1');
      expect(cubit.state.offersFor('store-001').isLoading, isTrue);

      repository.pending[0].done.complete([_offer('a1', 'store-001')]);
      await a;
      expect(cubit.state.offersFor('store-001').offers.single.id, 'a1');
      expect(cubit.state.offersFor('store-002').offers.single.id, 'b1');
    });

    test('a late, older response for the same store is dropped', () async {
      final repository = _ControlledRepository(store);
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);

      final first = cubit.loadStoreOffers('store-001');
      final second = cubit.loadStoreOffers('store-001');

      repository.pending[1].done.complete([_offer('new', 'store-001')]);
      await second;
      repository.pending[0].done.complete([_offer('old', 'store-001')]);
      await first;

      final offers = cubit.state.offersFor('store-001');
      expect(offers.status, LoadStatus.success);
      expect(offers.offers.single.id, 'new');
    });

    test('offers of another store are never shown under this store',
        () async {
      final repository = _ControlledRepository(store);
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);

      final load = cubit.loadStoreOffers('store-001');
      repository.pending.single.done.complete([
        _offer('mine', 'store-001'),
        _offer('foreign', 'store-002'),
      ]);
      await load;

      expect(cubit.state.offersFor('store-001').offers.map((o) => o.id),
          ['mine']);
      expect(cubit.state.storeOffers.containsKey('store-002'), isFalse);
    });

    test('a failed reload keeps the last loaded offers', () async {
      final repository = _ControlledRepository(store);
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);

      final ok = cubit.loadStoreOffers('store-001');
      repository.pending[0].done.complete([_offer('a1', 'store-001')]);
      await ok;
      final failed = cubit.loadStoreOffers('store-001');
      expect(cubit.state.offersFor('store-001').offers.single.id, 'a1');
      repository.pending[1].done
          .completeError(const YallaCashFailure(message: 'offline'));
      await failed;

      final offers = cubit.state.offersFor('store-001');
      expect(offers.status, LoadStatus.failure);
      expect(offers.offers.single.id, 'a1');
    });

    test('logout clears offers and drops in-flight responses', () async {
      final repository = _ControlledRepository(store);
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);

      final load = cubit.loadStoreOffers('store-001');
      await cubit.logout();
      repository.pending.single.done.complete([_offer('a1', 'store-001')]);
      await load;

      expect(cubit.state.storeOffers, isEmpty);
    });

    test('refresh() keeps loaded offers (offers are independent)', () async {
      final repository = InMemoryYallaCashRepository(store);
      await repository.createOffer(
          'store-001', const StoreOfferDraft(title: 'عرض'));
      final cubit = CustomerAppCubit(repository);
      addTearDown(cubit.close);

      await cubit.loadStoreOffers('store-001');
      await cubit.refresh();

      expect(cubit.state.offersFor('store-001').offers, hasLength(1));
    });
  });

  group('AdminAppCubit offers', () {
    late YallaCashStore store;

    setUp(() => store = YallaCashStore.demo());

    test('CRUD runs with its own operation status, never the global one',
        () async {
      final cubit = AdminAppCubit(InMemoryYallaCashRepository(store));
      addTearDown(cubit.close);
      final globalStatuses = <LoadStatus>{};
      final sub =
          cubit.stream.listen((state) => globalStatuses.add(state.status));

      expect(
        await cubit.createOffer('store-001',
            const StoreOfferDraft(title: 'first', isActive: false),
            image: const StoreLogoUpload(
                bytes: [1], contentType: 'image/png')),
        isTrue,
      );
      var offers = cubit.state.offersFor('store-001');
      expect(offers.operationStatus, LoadStatus.success);
      final created = offers.offers.single;
      expect(created.serverStatus, OfferStatus.inactive);
      expect(created.imageVersion, 1);

      expect(
        await cubit.updateOffer(created, const StoreOfferUpdate(isActive: true),
            removeImage: true),
        isTrue,
      );
      offers = cubit.state.offersFor('store-001');
      expect(offers.offers.single.serverStatus, OfferStatus.active);
      expect(offers.offers.single.hasImage, isFalse);
      expect(offers.offers.single.imageVersion, 2);

      expect(await cubit.deleteOffer(offers.offers.single), isTrue);
      expect(cubit.state.offersFor('store-001').status, LoadStatus.empty);

      await sub.cancel();
      expect(globalStatuses, {LoadStatus.initial});
      expect(cubit.state.failure, isNull);
    });

    test('a failed operation reports on that store only', () async {
      final cubit = AdminAppCubit(InMemoryYallaCashRepository(store));
      addTearDown(cubit.close);

      final ok = await cubit.createOffer(
          'store-001', const StoreOfferDraft(title: 'x')); // too short

      expect(ok, isFalse);
      final offers = cubit.state.offersFor('store-001');
      expect(offers.operationStatus, LoadStatus.failure);
      expect(offers.operationFailure?.statusCode, 400);
      expect(cubit.state.failure, isNull);
      expect(cubit.state.status, LoadStatus.initial);
    });

    test('partial success (offer created, image failed) is reloaded',
        () async {
      final cubit = AdminAppCubit(_FailingImageUploadRepository(store));
      addTearDown(cubit.close);

      final ok = await cubit.createOffer(
        'store-001',
        const StoreOfferDraft(title: 'created'),
        image: const StoreLogoUpload(bytes: [1], contentType: 'image/png'),
      );

      expect(ok, isFalse);
      final offers = cubit.state.offersFor('store-001');
      expect(offers.operationStatus, LoadStatus.failure);
      expect(offers.offers.single.title, 'created');
    });

    test('an empty update with no image change sends nothing', () async {
      final repository = InMemoryYallaCashRepository(store);
      final cubit = AdminAppCubit(repository);
      addTearDown(cubit.close);
      await cubit.createOffer('store-001', const StoreOfferDraft(title: 'same'));
      final offer = cubit.state.offersFor('store-001').offers.single;

      expect(await cubit.updateOffer(offer, const StoreOfferUpdate()), isTrue);
      expect(cubit.state.offersFor('store-001').offers.single.updatedAt,
          offer.updatedAt);
    });

    test('preview images: cached per version, refetched after a new upload',
        () async {
      final repository = _ImageRepository(store);
      final cubit = AdminAppCubit(repository);
      addTearDown(cubit.close);

      const noImage = StoreOffer(id: 'o', storeId: 's', title: 't');
      expect(await cubit.loadOfferImage(noImage), isNull);
      expect(repository.downloads, 0);

      const v1 = StoreOffer(
          id: 'o', storeId: 's', title: 't', hasImage: true, imageVersion: 1);
      final results = await Future.wait(
          [cubit.loadOfferImage(v1), cubit.loadOfferImage(v1)]);
      expect(repository.downloads, 1); // one shared download
      expect(results.first!.bytes, [1]);
      await cubit.loadOfferImage(v1);
      expect(repository.downloads, 1);

      const v2 = StoreOffer(
          id: 'o', storeId: 's', title: 't', hasImage: true, imageVersion: 2);
      expect((await cubit.loadOfferImage(v2))!.bytes, [2]);
      expect(repository.downloads, 2);
    });

    test('a failed preview download is not cached', () async {
      final repository = _ImageRepository(store)..fail = true;
      final cubit = AdminAppCubit(repository);
      addTearDown(cubit.close);
      const offer = StoreOffer(
          id: 'o', storeId: 's', title: 't', hasImage: true, imageVersion: 1);

      await expectLater(
          cubit.loadOfferImage(offer), throwsA(isA<YallaCashFailure>()));
      repository.fail = false;
      expect(await cubit.loadOfferImage(offer), isNotNull);
      expect(repository.downloads, 2);
    });

    test('logout clears offers and cached preview images', () async {
      final repository = _ImageRepository(store);
      final cubit = AdminAppCubit(repository);
      addTearDown(cubit.close);
      await cubit.createOffer('store-001', const StoreOfferDraft(title: 'ab'));
      const offer = StoreOffer(
          id: 'o', storeId: 's', title: 't', hasImage: true, imageVersion: 1);
      await cubit.loadOfferImage(offer);

      await cubit.logout();

      expect(cubit.state.storeOffers, isEmpty);
      await cubit.loadOfferImage(offer);
      expect(repository.downloads, 2);
    });
  });

  test('existing state constructors and copyWith keep working', () {
    const customer = CustomerAppState();
    expect(customer.storeOffers, isEmpty);
    expect(customer.copyWith(status: LoadStatus.loading).storeOffers, isEmpty);
    expect(customer, const CustomerAppState());
    const admin = AdminAppState();
    expect(admin.offersFor('any').status, LoadStatus.initial);
    expect(admin.copyWith(stores: const []), admin);
  });
}
