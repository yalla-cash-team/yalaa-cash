import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';

void _ignoreImageFailures(WidgetTester tester) {
  Object? e = tester.takeException();
  while (e != null) {
    expect(e, isA<NetworkImageLoadException>());
    e = tester.takeException();
  }
}

/// Hosts the real [CustomerGovernorateGate] for a signed-in demo customer.
Future<
    ({
      YallaCashStore store,
      InMemoryYallaCashRepository repo,
      CustomerAppCubit cubit
    })> _pumpGate(
  WidgetTester tester, {
  String governorateId = 'gov-idlib',
  String? cityId,
  Brightness brightness = Brightness.light,
  Size size = const Size(412, 1000),
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(size.width * 2, size.height * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final repo = InMemoryYallaCashRepository(store);
  await repo.updateCustomerGovernorate(governorateId);
  if (cityId != null) await repo.updateCustomerCity(cityId);
  final cubit = CustomerAppCubit(repo);
  addTearDown(cubit.close);
  await cubit.refresh(); // loads the profile
  await cubit.refresh(); // now scoped by the profile's governorate/city
  await tester.pumpWidget(MaterialApp(
    theme: buildCustomerTheme(Brightness.light),
    darkTheme: buildCustomerTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: StreamBuilder<CustomerAppState>(
      stream: cubit.stream,
      initialData: cubit.state,
      builder: (context, snapshot) => CustomerGovernorateGate(
        cubit: cubit,
        state: snapshot.data!,
        repository: repo,
        darkMode: brightness == Brightness.dark,
        onDarkModeChanged: (_) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (store: store, repo: repo, cubit: cubit);
}

void main() {
  testWidgets('no saved city: step 2 lists only that governorate\'s cities',
      (tester) async {
    await _pumpGate(tester);
    expect(find.byType(CitySelectionScreen), findsOneWidget);
    expect(find.text('الخطوة 2 من 2'), findsOneWidget);
    for (final city in ['إدلب', 'أريحا', 'سلقين', 'سراقب']) {
      expect(find.text(city), findsOneWidget, reason: city);
    }
    expect(find.text('دمشق'), findsNothing);
    expect(find.byType(CustomerShell), findsNothing);
  });

  testWidgets(
      'choosing a city saves it and Home shows only that city\'s '
      'stores in display order', (tester) async {
    final h = await _pumpGate(tester);
    await tester.tap(find.byKey(const Key('city-city-idlib')));
    await tester.pumpAndSettle();
    _ignoreImageFailures(tester);

    expect(h.cubit.state.customer?.cityId, 'city-idlib');
    expect(find.byType(CustomerShell), findsOneWidget);
    final first = tester.getTopLeft(find.text('صالون لمسة')).dy;
    final second = tester.getTopLeft(find.text('صيدلية الشفاء')).dy;
    expect(first, lessThan(second));
    // Another governorate's stores never appear.
    expect(find.text('مطعم الوسيم'), findsNothing);
  });

  testWidgets('a saved city is restored: no picker, shell shown at once',
      (tester) async {
    await _pumpGate(tester, cityId: 'city-idlib');
    _ignoreImageFailures(tester);
    expect(find.byType(CitySelectionScreen), findsNothing);
    expect(find.byType(CustomerShell), findsOneWidget);
  });

  testWidgets(
      'a city without stores shows the friendly empty state, not '
      'another city\'s stores', (tester) async {
    await _pumpGate(tester, cityId: 'city-ariha');
    _ignoreImageFailures(tester);
    expect(find.text('لا توجد محلات في مدينتك حالياً'), findsOneWidget);
    expect(find.text('صالون لمسة'), findsNothing);
    expect(find.text('صيدلية الشفاء'), findsNothing);
  });

  testWidgets('a governorate with no cities keeps the governorate-wide list',
      (tester) async {
    final store = YallaCashStore.demo()..loginDemoCustomer();
    addTearDown(store.dispose);
    store.addGovernorate(Governorate(
      id: 'gov-empty',
      nameAr: 'محافظة بلا مدن',
      isActive: true,
      displayOrder: 9,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ));
    final repo = InMemoryYallaCashRepository(store);
    await repo.updateCustomerGovernorate('gov-empty');
    final cubit = CustomerAppCubit(repo);
    addTearDown(cubit.close);
    await cubit.refresh();
    await cubit.refresh();
    await tester.pumpWidget(MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: StreamBuilder<CustomerAppState>(
        stream: cubit.stream,
        initialData: cubit.state,
        builder: (context, snapshot) => CustomerGovernorateGate(
          cubit: cubit,
          state: snapshot.data!,
          repository: repo,
          darkMode: false,
          onDarkModeChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    _ignoreImageFailures(tester);
    expect(find.byType(CitySelectionScreen), findsNothing);
    expect(find.byType(CustomerShell), findsOneWidget);
  });

  testWidgets(
      'changing governorate from step 2 shows step 1, then the new '
      'governorate\'s cities', (tester) async {
    await _pumpGate(tester);
    await tester.tap(find.byKey(const Key('change-governorate')));
    await tester.pumpAndSettle();
    expect(find.text('الخطوة 1 من 2'), findsOneWidget);

    await tester.tap(find.text('دمشق'));
    await tester.pumpAndSettle();
    expect(find.byType(CitySelectionScreen), findsOneWidget);
    expect(find.text('المدن المتاحة في دمشق'), findsOneWidget);
    expect(find.text('أريحا'), findsNothing);
  });

  testWidgets('going back from step 1 keeps the current governorate',
      (tester) async {
    await _pumpGate(tester);
    await tester.tap(find.byKey(const Key('change-governorate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('location-back')));
    await tester.pumpAndSettle();
    expect(find.byType(CitySelectionScreen), findsOneWidget);
    expect(find.text('المدن المتاحة في إدلب'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final (size, scale) in [
      (const Size(320, 640), 1.0),
      (const Size(320, 640), 2.0),
      (const Size(412, 900), 1.0),
    ]) {
      testWidgets(
          'step 2 renders RTL without overflow (dark=$dark ${size.width}dp '
          'x$scale)', (tester) async {
        await _pumpGate(tester,
            brightness: dark ? Brightness.dark : Brightness.light,
            size: size,
            scale: scale);
        expect(tester.takeException(), isNull);
        expect(find.text('اختر مدينتك'), findsOneWidget);
        // The chevron sits at the leading-left of the city name in RTL.
        final card = find.byKey(const Key('city-city-idlib'));
        final chevron = find.descendant(
            of: card, matching: find.byIcon(Icons.chevron_left_rounded));
        final icon = find.descendant(
            of: card, matching: find.byIcon(Icons.location_city_outlined));
        expect(tester.getCenter(icon).dx,
            greaterThan(tester.getCenter(chevron).dx));
      });
    }
  }
}
