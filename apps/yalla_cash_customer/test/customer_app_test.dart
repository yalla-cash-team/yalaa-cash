import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';

void main() {
  testWidgets('balance loading state does not display a false zero',
      (tester) async {
    final store = YallaCashStore.demo()..loginDemoCustomer();

    await tester.pumpWidget(
      MaterialApp(
        home: CustomerHomePage(
          cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
          state: const CustomerAppState(),
          customer: store.currentCustomer!,
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('customer app hides demo shortcut without injected store',
      (tester) async {
    final runtime = YallaCashRuntime.fromEnvironment();
    addTearDown(runtime.dispose);

    await tester.pumpWidget(YallaCashCustomerApp(runtime: runtime));

    expect(find.byType(CustomerAuthScreen), findsOneWidget);
    expect(find.byKey(const Key('demo-customer-login')), findsNothing);
  });

  testWidgets('customer can enter the injected demo experience',
      (tester) async {
    final store = YallaCashStore.demo();
    addTearDown(store.dispose);

    await tester.pumpWidget(YallaCashCustomerApp(store: store));

    expect(find.byType(CustomerAuthScreen), findsOneWidget);
    expect(find.byKey(const Key('demo-customer-login')), findsOneWidget);

    await tester.tap(find.byKey(const Key('demo-customer-login')));
    await tester.pumpAndSettle();

    // Idlib has cities, so step 2 (city) comes before the shell.
    expect(find.byType(CitySelectionScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('city-city-idlib')));
    await tester.pumpAndSettle();
    _expectOnlyNetworkImageFailures(tester);

    expect(find.byType(CustomerShell), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
  });
}

void _expectOnlyNetworkImageFailures(WidgetTester tester) {
  Object? exception = tester.takeException();
  while (exception != null) {
    expect(exception, isA<NetworkImageLoadException>());
    exception = tester.takeException();
  }
}
