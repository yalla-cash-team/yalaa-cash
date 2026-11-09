import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_admin/src/admin_app.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' hide Banner;

void main() {
  late YallaCashStore store;
  late InMemoryYallaCashRepository repository;

  setUp(() {
    store = YallaCashStore.demo();
    repository = InMemoryYallaCashRepository(store);
  });

  Future<void> openEditor(WidgetTester tester,
      {bool dark = false, Size size = const Size(1400, 1100)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = AdminAppCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      theme: buildYallaTheme(dark ? Brightness.dark : Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: StoresAdmin(
            cubit: cubit, stores: store.stores, repository: repository),
      ),
    ));
    await tester.tap(find.text('إضافة محل').first);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(DropdownButtonFormField<String>, label);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  Future<void> pickCityOptions(WidgetTester tester) async {
    final field =
        find.widgetWithText(DropdownButtonFormField<String>, 'المدينة');
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
  }

  testWidgets('city list depends on the chosen governorate and resets',
      (tester) async {
    await openEditor(tester);
    // No governorate yet: the city field is disabled with a hint.
    expect(find.text('اختر المحافظة أولاً'), findsOneWidget);

    await pick(tester, 'المحافظة', 'إدلب');
    await pickCityOptions(tester);
    for (final city in ['إدلب', 'أريحا', 'سلقين', 'سراقب']) {
      expect(find.text(city), findsWidgets, reason: city);
    }
    expect(find.text('دمشق'), findsNothing);
    await tester.tap(find.text('أريحا').last);
    await tester.pumpAndSettle();

    // Switching governorate clears the old city and shows the new one's.
    await pick(tester, 'المحافظة', 'دمشق');
    await pickCityOptions(tester);
    expect(find.text('أريحا'), findsNothing);
    expect(find.text('دمشق'), findsWidgets);
  });

  testWidgets('saving needs a city and a valid display order', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.widgetWithText(TextField, 'اسم المحل'), 'جديد');
    await pick(tester, 'المحافظة', 'إدلب');

    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('اختر المدينة قبل الحفظ.'), findsOneWidget);

    await pick(tester, 'المدينة', 'سراقب');
    // Letters can't be typed (digits only); zero is rejected.
    await tester.enterText(find.byKey(const Key('store-display-order')), 'ab');
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('store-display-order')))
            .controller!
            .text,
        isEmpty);
    await tester.enterText(find.byKey(const Key('store-display-order')), '0');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();
    expect(find.text('أدخل رقماً صحيحاً من 1 إلى 10000'), findsOneWidget);
    expect(store.stores.where((s) => s.name == 'جديد'), isEmpty);
  });

  testWidgets('a valid store is created in the chosen city at position 1',
      (tester) async {
    await openEditor(tester);
    await tester.enterText(
        find.widgetWithText(TextField, 'اسم المحل'), 'مكتبة');
    await tester.enterText(find.widgetWithText(TextField, 'الفئة'), 'مكتبات');
    await pick(tester, 'المحافظة', 'إدلب');
    await pick(tester, 'المدينة', 'إدلب');
    await tester.enterText(find.byKey(const Key('store-display-order')), '1');
    await tester.tap(find.text('حفظ'));
    await tester.pumpAndSettle();

    final ids = (await repository.listActiveStores(
            governorateId: 'gov-idlib', cityId: 'city-idlib'))
        .map((s) => s.name)
        .toList();
    expect(ids, ['مكتبة', 'صالون لمسة', 'صيدلية الشفاء']);
  });

  for (final dark in [false, true]) {
    testWidgets('editor fits a small phone in RTL (dark=$dark)',
        (tester) async {
      await openEditor(tester, dark: dark, size: const Size(360, 640));
      await pick(tester, 'المحافظة', 'إدلب');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('add-city')), findsOneWidget);
      expect(find.byKey(const Key('store-display-order')), findsOneWidget);
    });
  }

  testWidgets('a city can be added inline and is selected', (tester) async {
    await openEditor(tester);
    await pick(tester, 'المحافظة', 'إدلب');
    await tester.tap(find.byKey(const Key('add-city')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('new-city-name')), 'معرة النعمان');
    await tester.tap(find.byKey(const Key('city-name-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('معرة النعمان'), findsWidgets);
    expect(
        (await repository.listActiveCities(governorateId: 'gov-idlib'))
            .any((c) => c.nameAr == 'معرة النعمان'),
        isTrue);
  });
}
