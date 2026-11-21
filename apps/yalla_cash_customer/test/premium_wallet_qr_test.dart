import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

final _t0 = DateTime(2026, 3, 9, 10);

void _viewport(WidgetTester tester, double width, double height,
    {double scale = 1}) {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Widget _app(Widget body, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: customerLightTheme,
      darkTheme: customerDarkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: body),
    );

LoyaltyTransaction _tx(int i) => LoyaltyTransaction(
      id: 't$i',
      storeId: 's',
      storeName: 'متجر $i',
      customerId: 'c',
      amountSyp: 1000 + i,
      commissionRateSnapshot: 5,
      commissionAmountSyp: 0,
      platformRevenueSyp: 0,
      customerShareSyp: 0,
      customerPointsEarned: i + 1,
      createdAt: _t0,
    );

CashRedemptionRequest _cash(int i) => CashRedemptionRequest(
      id: 'c$i',
      customerId: 'c',
      pointsRequested: 100 + i,
      cashValueSyp: 500 + i,
      status: CashRequestStatus.pending,
      createdAt: _t0,
    );

final _customer = Customer(
  id: 'c',
  name: 'أحمد',
  governorate: 'نينوى',
  pointsBalance: 0,
  createdAt: _t0,
);

Future<void> _pumpWallet(
  WidgetTester tester, {
  PointsSummary? points,
  int transactions = 30,
  int cash = 3,
  double width = 412,
  double height = 760,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  _viewport(tester, width, height, scale: scale);
  await tester.pumpWidget(_app(
    CustomerWalletPage(
      transactions: [for (var i = 0; i < transactions; i++) _tx(i)],
      customer: _customer,
      cashRequests: [for (var i = 0; i < cash; i++) _cash(i)],
      points: points,
    ),
    brightness: brightness,
  ));
  await tester.pump();
}

int _segment(WidgetTester tester) =>
    tester.widget<YcSegmentedTabs>(find.byType(YcSegmentedTabs)).selectedIndex;

void main() {
  group('wallet sections', () {
    testWidgets('segments in RTL order; the first is selected', (tester) async {
      await _pumpWallet(tester);
      final xs = [
        for (final s in CustomerWalletPage.sectionLabels)
          tester.getCenter(find.text(s)).dx,
      ];
      expect(xs[0], greaterThan(xs[1]));
      expect(xs[1], greaterThan(xs[2]));
      expect(_segment(tester), 0);
    });

    testWidgets('a segment jumps to its section, even past lazy entries',
        (tester) async {
      await _pumpWallet(tester, cash: 15);
      // The cash section is far below 30 transactions: not built yet.
      expect(find.text('طلبات سحب الكاش'), findsNothing);
      await tester.tap(find.text('سحب الكاش'));
      await tester.pumpAndSettle();
      expect(_segment(tester), 1);
      final list = tester.getRect(find.byType(CustomScrollView));
      final heading = tester.getRect(find.text('طلبات سحب الكاش'));
      // The heading is now at the top of the list.
      expect(heading.top - list.top, inInclusiveRange(0, YcSpace.xl + 2));
      // Every entry is still in one list: the products section follows.
      await tester.tap(find.text('المنتجات'));
      await tester.pumpAndSettle();
      expect(_segment(tester), 2);
      expect(find.text('طلبات استبدال المنتجات'), findsOneWidget);
      await tester.tap(find.text('العمليات'));
      await tester.pumpAndSettle();
      expect(_segment(tester), 0);
      expect(find.text('متجر 0'), findsOneWidget);
    });

    testWidgets('the selected segment follows manual scrolling',
        (tester) async {
      await _pumpWallet(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(_segment(tester), 2);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 6000));
      await tester.pumpAndSettle();
      expect(_segment(tester), 0);
    });

    testWidgets('balance header shows the real summary when known',
        (tester) async {
      await _pumpWallet(
        tester,
        points: const PointsSummary(
            pointsBalance: 1500, heldPoints: 300, availablePoints: 1200),
      );
      expect(find.byType(YcBalanceHero), findsOneWidget);
      expect(find.text('1,500'), findsOneWidget);
      expect(find.text('1,200'), findsOneWidget);
      // Without a summary there is no header (and never a false zero).
      await _pumpWallet(tester);
      expect(find.byType(YcBalanceHero), findsNothing);
    });

    for (final b in Brightness.values) {
      testWidgets('$b 320dp x2: header, segments and list fit', (tester) async {
        await _pumpWallet(
          tester,
          width: 320,
          scale: 2,
          brightness: b,
          points: const PointsSummary(
              pointsBalance: 987654321,
              heldPoints: 1,
              availablePoints: 987654320),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('المنتجات'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('rewards', () {
    testWidgets('only the cash card listens to typing', (tester) async {
      _viewport(tester, 412, 1600);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      await tester.pumpWidget(_app(CustomerRewardsPage(
        cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
        state: CustomerAppState(
          customer: store.currentCustomer,
          points: const PointsSummary(
              pointsBalance: 900, heldPoints: 0, availablePoints: 900),
          products: store.products,
        ),
      )));
      final listener = find.byWidgetPredicate(
          (w) => w is ValueListenableBuilder<TextEditingValue>);
      expect(find.ancestor(of: find.byType(TextField), matching: listener),
          findsOneWidget);
      // The product cards are outside the listener's subtree.
      final products = find
          .byWidgetPredicate((w) => w.runtimeType.toString() == '_ProductCard');
      expect(products, findsWidgets);
      expect(find.descendant(of: listener, matching: products), findsNothing);
      // The summary is the compact premium hero with the real figure.
      expect(find.byType(YcBalanceHero), findsOneWidget);
      expect(find.text('900 نقطة'), findsOneWidget);
    });
  });

  group('QR presentation', () {
    testWidgets('white QR plate on the hero surface, payload untouched',
        (tester) async {
      _viewport(tester, 412, 1600);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      final token = CustomerQrToken(
        token: 't',
        payload: 'yc:qr:test',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      );
      await tester.pumpWidget(_app(CustomerQrPage(
        cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
        state:
            CustomerAppState(customer: store.currentCustomer, qrToken: token),
        customer: store.currentCustomer!,
      )));
      await tester.pump();
      expect(find.byType(QrImageView), findsOneWidget);
      final ctx = tester.element(find.byType(QrImageView));
      final colors = YcColors.of(ctx);
      final hero = find.ancestor(
        of: find.byType(QrImageView),
        matching: find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).gradient as LinearGradient?)
                    ?.colors
                    .first ==
                colors.heroStart),
      );
      expect(hero, findsOneWidget);
      // Name and expiry are white on the hero surface.
      final name = tester.widget<Text>(find.text(store.currentCustomer!.name));
      expect(name.style?.color, colors.onHero);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
