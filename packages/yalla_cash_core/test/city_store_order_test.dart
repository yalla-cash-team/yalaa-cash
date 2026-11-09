import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

PartnerStore _newStore(
  String id,
  String category, {
  String city = 'city-idlib',
  String gov = 'gov-idlib',
  int order = 0,
  bool active = true,
}) =>
    PartnerStore(
      id: id,
      name: id,
      category: category,
      commissionRate: 5,
      description: '',
      location: '',
      iconSeed: 0,
      governorateId: gov,
      cityId: city,
      displayOrder: order,
      isActive: active,
    );

Future<List<String>> _order(InMemoryYallaCashRepository repo, String city,
        {String gov = 'gov-idlib'}) async =>
    (await repo.listActiveStores(governorateId: gov, cityId: city))
        .map((s) => '${s.id}:${s.displayOrder}')
        .toList();

void main() {
  group('insertAtPosition / validateDisplayOrder', () {
    test('insert, clamp and default to last', () {
      expect(insertAtPosition(['a', 'b', 'c'], 'x', 2), ['a', 'x', 'b', 'c']);
      expect(insertAtPosition(['a', 'b'], 'x'), ['a', 'b', 'x']);
      expect(insertAtPosition(['a', 'b'], 'x', 99), ['a', 'b', 'x']);
      expect(insertAtPosition(['a', 'b'], 'x', 0), ['a', 'b', 'x']);
      expect(insertAtPosition(['a', 'x', 'b'], 'x', 3), ['a', 'b', 'x']);
    });

    test('client validation: empty ok, 1..10000 only', () {
      expect(validateDisplayOrder(''), isNull);
      expect(validateDisplayOrder(' 3 '), isNull);
      expect(validateDisplayOrder('0'), isNotNull);
      expect(validateDisplayOrder('-2'), isNotNull);
      expect(validateDisplayOrder('abc'), isNotNull);
      expect(validateDisplayOrder('2.5'), isNotNull);
      expect(validateDisplayOrder('10001'), isNotNull);
    });
  });

  group('customer city selection', () {
    test('demo data: Idlib has several cities; Damascus has its own', () async {
      final repo = InMemoryYallaCashRepository(YallaCashStore.demo());
      final idlib = await repo.listActiveCities(governorateId: 'gov-idlib');
      expect(idlib.map((c) => c.nameAr),
          ['إدلب', 'أريحا', 'سلقين', 'سراقب']);
      final damascus =
          await repo.listActiveCities(governorateId: 'gov-damascus');
      expect(damascus.map((c) => c.nameAr), ['دمشق']);
    });

    test('a city of another governorate is rejected', () async {
      final store = YallaCashStore.demo()..loginDemoCustomer();
      final repo = InMemoryYallaCashRepository(store);
      await repo.updateCustomerGovernorate('gov-idlib');
      expect(() => repo.updateCustomerCity('city-damascus'),
          throwsA(isA<StateError>()));
      final saved = await repo.updateCustomerCity('city-ariha');
      expect(saved.cityId, 'city-ariha');
    });

    test('changing governorate clears the saved city', () async {
      final store = YallaCashStore.demo()..loginDemoCustomer();
      final repo = InMemoryYallaCashRepository(store);
      await repo.updateCustomerGovernorate('gov-idlib');
      await repo.updateCustomerCity('city-ariha');
      final moved = await repo.updateCustomerGovernorate('gov-damascus');
      expect(moved.cityId, isNull);
    });

    test('the cubit loads only the chosen city\'s stores', () async {
      final store = YallaCashStore.demo()..loginDemoCustomer();
      final repo = InMemoryYallaCashRepository(store);
      final cubit = CustomerAppCubit(repo);
      addTearDown(cubit.close);
      await repo.updateCustomerGovernorate('gov-idlib');
      await cubit.refresh();
      expect(cubit.state.stores.map((s) => s.id),
          containsAll(['store-004', 'store-005']));

      // A second Idlib city never mixes in the first city's stores.
      await cubit.updateCity('city-ariha');
      expect(cubit.state.customer?.cityId, 'city-ariha');
      expect(cubit.state.stores, isEmpty);

      await cubit.updateCity('city-idlib');
      expect(cubit.state.stores.map((s) => s.id), ['store-004', 'store-005']);
    });
  });

  group('store ordering', () {
    late InMemoryYallaCashRepository repo;
    setUp(() {
      repo = InMemoryYallaCashRepository(YallaCashStore.demo());
    });

    test('demo stores come back in display order', () async {
      expect(await _order(repo, 'city-idlib'), ['store-004:1', 'store-005:2']);
    });

    test('a new store without a number goes last', () async {
      await repo.createStore(_newStore('n1', 'مكتبات'));
      expect(await _order(repo, 'city-idlib'),
          ['store-004:1', 'store-005:2', 'n1:3']);
    });

    test('inserting into an occupied position shifts the rest', () async {
      await repo.createStore(_newStore('n1', 'مكتبات', order: 1));
      expect(await _order(repo, 'city-idlib'),
          ['n1:1', 'store-004:2', 'store-005:3']);
    });

    test('moving earlier/later keeps positions contiguous', () async {
      await repo.createStore(_newStore('n1', 'مكتبات'));
      final all = await repo.listAdminStores();
      final n1 = all.firstWhere((s) => s.id == 'n1');
      await repo.updateStore(n1.copyWith(displayOrder: 1));
      expect(await _order(repo, 'city-idlib'),
          ['n1:1', 'store-004:2', 'store-005:3']);
      final moved = (await repo.listAdminStores())
          .firstWhere((s) => s.id == 'store-004');
      await repo.updateStore(moved.copyWith(displayOrder: 3));
      expect(await _order(repo, 'city-idlib'),
          ['n1:1', 'store-005:2', 'store-004:3']);
    });

    test('changing city closes the old gap and inserts in the new city',
        () async {
      final target = _newStore('t1', 'مطاعم', city: 'city-ariha');
      await repo.createStore(target);
      final s4 = (await repo.listAdminStores())
          .firstWhere((s) => s.id == 'store-004');
      await repo.updateStore(s4.copyWith(cityId: 'city-ariha', displayOrder: 1));
      expect(await _order(repo, 'city-idlib'), ['store-005:1']);
      expect(await _order(repo, 'city-ariha'), ['store-004:1', 't1:2']);
    });

    test('deactivating closes the gap; the store holds position 0', () async {
      await repo.deleteStore('store-004');
      expect(await _order(repo, 'city-idlib'), ['store-005:1']);
      final s4 = (await repo.listAdminStores())
          .firstWhere((s) => s.id == 'store-004');
      expect(s4.isActive, isFalse);
      expect(s4.displayOrder, 0);
      // Reactivation puts it last, not on a stale number.
      await repo.updateStore(s4.copyWith(isActive: true));
      expect(await _order(repo, 'city-idlib'), ['store-005:1', 'store-004:2']);
    });

    test('exclusivity: one active store per city and category', () async {
      // store-004 is the only 'صالونات' store in Idlib city.
      expect(() => repo.createStore(_newStore('dup', 'صالونات')),
          throwsA(isA<StateError>()));
      // Same category in another city is fine.
      await repo.createStore(_newStore('ok', 'صالونات', city: 'city-ariha'));
    });

    test('a city outside the store\'s governorate is rejected', () async {
      expect(
          () => repo.createStore(_newStore('bad', 'x', city: 'city-damascus')),
          throwsA(isA<StateError>()));
    });

    test('editing a store keeps its identity, logo and image data', () async {
      final s5 = (await repo.listAdminStores())
          .firstWhere((s) => s.id == 'store-005');
      final saved = await repo.updateStore(s5.copyWith(name: 'اسم جديد'));
      expect(saved.displayOrder, s5.displayOrder);
      expect(saved.logoUrl, s5.logoUrl);
      expect(saved.cityId, s5.cityId);
      expect(saved.category, s5.category);
    });
  });
}
