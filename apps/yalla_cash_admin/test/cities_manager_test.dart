import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_admin/src/admin_app.dart';
import 'package:yalla_cash_admin/src/cities_admin.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' hide Banner;

void main() {
  late YallaCashStore store;
  late InMemoryYallaCashRepository repository;

  setUp(() {
    store = YallaCashStore.demo();
    repository = InMemoryYallaCashRepository(store);
  });

  Future<void> openManager(WidgetTester tester,
      {Size size = const Size(1200, 1000), bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildYallaTheme(dark ? Brightness.dark : Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: GovernoratesAdmin(repository: repository)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-cities-gov-idlib')));
    await tester.pumpAndSettle();
  }

  Future<void> addCity(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('city-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-city-name')), name);
    await tester.tap(find.byKey(const Key('city-name-confirm')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the governorate\'s cities with active-store counts',
      (tester) async {
    await openManager(tester);
    expect(find.text('مدن إدلب'), findsOneWidget);
    for (final c in ['إدلب', 'أريحا', 'سلقين', 'سراقب']) {
      expect(
          find.descendant(
              of: find.byType(CitiesManagerDialog), matching: find.text(c)),
          findsOneWidget,
          reason: c);
    }
    expect(find.text('نشطة · 2 محل نشط'), findsOneWidget); // إدلب
    expect(
        find.descendant(
            of: find.byType(CitiesManagerDialog), matching: find.text('دمشق')),
        findsNothing); // other governorate
  });

  testWidgets('an explicit add creates the city; a variant is refused',
      (tester) async {
    await openManager(tester);
    await addCity(tester, '  معرة   النعمان ');
    expect(find.text('معرة النعمان'), findsOneWidget);

    await addCity(tester, 'اريحا');
    expect(find.byKey(const Key('cities-message')), findsOneWidget);
    expect(find.textContaining('أريحا'), findsWidgets);
    expect(
        (await repository.listAdminCities(governorateId: 'gov-idlib'))
            .where((c) => cityNameKey(c.nameAr) == cityNameKey('أريحا')),
        hasLength(1));
  });

  testWidgets('renaming keeps the same city id; a clashing name is refused',
      (tester) async {
    await openManager(tester);
    await tester.tap(find.byKey(const Key('city-rename-city-ariha')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-city-name')), 'ادلب');
    await tester.tap(find.byKey(const Key('city-name-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cities-message')), findsOneWidget);
    expect(
        (await repository.listAdminCities(governorateId: 'gov-idlib'))
            .firstWhere((c) => c.id == 'city-ariha')
            .nameAr,
        'أريحا');

    await tester.tap(find.byKey(const Key('city-rename-city-ariha')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-city-name')), 'أريحا الجديدة');
    await tester.tap(find.byKey(const Key('city-name-confirm')));
    await tester.pumpAndSettle();
    final renamed =
        (await repository.listAdminCities(governorateId: 'gov-idlib'))
            .firstWhere((c) => c.id == 'city-ariha');
    expect(renamed.nameAr, 'أريحا الجديدة');
  });

  testWidgets(
      'a city with active stores cannot be deactivated; an empty one can',
      (tester) async {
    await openManager(tester);
    await tester.tap(find.byKey(const Key('city-active-city-idlib')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cities-message')), findsOneWidget);
    expect(
        (await repository.listAdminCities(governorateId: 'gov-idlib'))
            .firstWhere((c) => c.id == 'city-idlib')
            .isActive,
        isTrue);

    await tester.tap(find.byKey(const Key('city-active-city-salqin')));
    await tester.pumpAndSettle();
    expect(
        (await repository.listAdminCities(governorateId: 'gov-idlib'))
            .firstWhere((c) => c.id == 'city-salqin')
            .isActive,
        isFalse);
  });

  for (final dark in [false, true]) {
    testWidgets('manager fits a small phone in RTL (dark=$dark)',
        (tester) async {
      await openManager(tester, size: const Size(360, 640), dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('city-add')), findsOneWidget);
    });
  }

  testWidgets('a store without a city is flagged on its card', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final orphan = store.stores.first.copyWith(isActive: true);
    final noCity = PartnerStore(
      id: orphan.id,
      name: orphan.name,
      category: orphan.category,
      commissionRate: orphan.commissionRate,
      description: orphan.description,
      location: orphan.location,
      iconSeed: orphan.iconSeed,
      governorateId: orphan.governorateId,
    );
    final cubit = AdminAppCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      theme: buildYallaTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body:
            StoresAdmin(cubit: cubit, stores: [noCity], repository: repository),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('store-needs-city')), findsOneWidget);
  });
}
