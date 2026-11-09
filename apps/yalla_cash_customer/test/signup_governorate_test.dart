import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';

/// The governorates a previous sign-up form hardcoded. None of them may
/// appear unless the backend (Admin) lists it as active.
const _formerHardcoded = [
  'ريف دمشق',
  'حلب',
  'حمص',
  'حماة',
  'اللاذقية',
  'طرطوس',
  'درعا',
  'السويداء',
  'القنيطرة',
  'دير الزور',
  'الرقة',
  'الحسكة',
];

void _ignoreImageFailures(WidgetTester tester) {
  Object? e = tester.takeException();
  while (e != null) {
    expect(e, isA<NetworkImageLoadException>());
    e = tester.takeException();
  }
}

/// Signs up through the real auth screen (phone + demo OTP) and stops on
/// the details step.
Future<YallaCashStore> _openSignupDetails(WidgetTester tester,
    {void Function(YallaCashStore store)? prepare}) async {
  tester.view.physicalSize = const Size(824, 2000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final store = YallaCashStore.demo();
  addTearDown(store.dispose);
  prepare?.call(store);
  await tester.pumpWidget(YallaCashCustomerApp(store: store));
  await tester.pumpAndSettle();

  await tester.tap(find.text('المتابعة برقم الهاتف'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '0933123456');
  await tester.tap(find.text('إرسال رمز التحقق'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '000000');
  await tester.tap(find.text('تحقق ودخول'));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('sign-up shows no governorate field or hardcoded governorates',
      (tester) async {
    await _openSignupDetails(tester);

    expect(find.text('الاسم الكامل'), findsOneWidget);
    expect(find.text('المحافظة'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    for (final name in [..._formerHardcoded, 'دمشق', 'إدلب']) {
      expect(find.text(name), findsNothing, reason: name);
    }
  });

  testWidgets(
      'sign-up works with only a name, then asks for a governorate '
      'from the active (Admin) list', (tester) async {
    final store = await _openSignupDetails(tester, prepare: (store) {
      store.addGovernorate(Governorate(
        id: 'gov-hidden',
        nameAr: 'حلب',
        isActive: false,
        displayOrder: 3,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
    });

    final submit = find.widgetWithText(FilledButton, 'إنشاء الحساب');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull,
        reason: 'a name is still required');
    await tester.enterText(find.byType(TextField), 'زبون جديد');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);

    await tester.tap(submit);
    await tester.pumpAndSettle();

    final customer = store.currentCustomer!;
    expect(customer.name, 'زبون جديد');
    expect(customer.governorate, '');
    expect(customer.governorateId, isNull);
    expect(customer.cityId, isNull);

    // Step 1 lists exactly the active governorates from the repository.
    expect(find.byType(GovernorateSelectionScreen), findsOneWidget);
    expect(find.text('إدلب'), findsOneWidget);
    expect(find.text('دمشق'), findsOneWidget);
    expect(find.text('حلب'), findsNothing, reason: 'inactive in Admin');
    for (final name in _formerHardcoded) {
      expect(find.text(name), findsNothing, reason: name);
    }

    // Picking a governorate moves on to that governorate's active cities.
    await tester.tap(find.text('إدلب'));
    await tester.pumpAndSettle();
    expect(store.currentCustomer!.governorateId, 'gov-idlib');
    expect(find.byType(CitySelectionScreen), findsOneWidget);
    for (final city in ['أريحا', 'سلقين', 'سراقب']) {
      expect(find.text(city), findsOneWidget, reason: city);
    }
    expect(find.byType(CustomerShell), findsNothing);
  });

  testWidgets('only active cities of the selected governorate are listed',
      (tester) async {
    final store = await _openSignupDetails(tester, prepare: (store) {
      store.addCity(City(
        id: 'city-closed',
        governorateId: 'gov-idlib',
        nameAr: 'مدينة مغلقة',
        isActive: false,
        displayOrder: 9,
      ));
    });
    await tester.enterText(find.byType(TextField), 'زبون');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'إنشاء الحساب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إدلب'));
    await tester.pumpAndSettle();

    expect(store.currentCustomer!.governorateId, 'gov-idlib');
    expect(find.text('مدينة مغلقة'), findsNothing);
    expect(find.byKey(const Key('city-city-damascus')), findsNothing);
    expect(find.byKey(const Key('city-city-ariha')), findsOneWidget);
  });

  testWidgets('changing governorate clears the previously chosen city',
      (tester) async {
    final store = YallaCashStore.demo()..loginDemoCustomer();
    addTearDown(store.dispose);
    final repo = InMemoryYallaCashRepository(store);
    await repo.updateCustomerGovernorate('gov-idlib');
    await repo.updateCustomerCity('city-ariha');
    final cubit = CustomerAppCubit(repo);
    addTearDown(cubit.close);
    await cubit.refresh();
    expect(cubit.state.customer?.cityId, 'city-ariha');

    await tester.pumpWidget(MaterialApp(
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
    expect(find.byType(CustomerShell), findsOneWidget);

    await cubit.updateGovernorate('gov-damascus');
    await tester.pumpAndSettle();
    _ignoreImageFailures(tester);

    expect(cubit.state.customer?.governorateId, 'gov-damascus');
    expect(cubit.state.customer?.cityId, isNull);
    // The old city is gone; the new governorate's cities are offered.
    expect(find.byType(CitySelectionScreen), findsOneWidget);
    expect(find.text('المدن المتاحة في دمشق'), findsOneWidget);
    expect(find.text('أريحا'), findsNothing);
  });
}
