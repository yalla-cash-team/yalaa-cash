import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/notifications_inbox.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';

/// Phase 7 QA: the premium customer UI across widths, text sizes, themes and
/// motion settings, with accessibility guidelines and RTL number checks.

void _viewport(WidgetTester tester, double width, double scale,
    {double height = 900}) {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget home, Brightness brightness) => MaterialApp(
      theme: customerLightTheme,
      darkTheme: customerDarkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      locale: customerLocale,
      supportedLocales: const [customerLocale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    );

Banner _banner(String id) => Banner(
      id: id,
      title: 'إعلان $id',
      imageUrl: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

final _t0 = DateTime(2026, 3, 9, 10);

/// Rich state with long Arabic names and very large figures.
CustomerAppState _state(YallaCashStore store) => CustomerAppState(
      customer: store.currentCustomer,
      qrToken: CustomerQrToken(
        token: 'qa',
        payload: 'yc:qa',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      ),
      points: const PointsSummary(
          pointsBalance: 987654321,
          heldPoints: 123456789,
          availablePoints: 864197532),
      stores: [
        for (var i = 0; i < 4; i++)
          PartnerStore(
            id: 's$i',
            name: 'مطعم ومقهى الأصالة الشامية للمأكولات الشرقية $i',
            category: 'مطاعم',
            commissionRate: 5,
            description: 'وصف',
            location: 'دمشق',
            iconSeed: 0,
            governorateId: 'g',
          ),
      ],
      banners: [_banner('a'), _banner('b'), _banner('c')],
      transactions: [
        LoyaltyTransaction(
          id: 't1',
          storeId: 's0',
          storeName: 'مطعم ومقهى الأصالة الشامية للمأكولات الشرقية',
          customerId: 'c',
          amountSyp: 987654321,
          commissionRateSnapshot: 5,
          commissionAmountSyp: 0,
          platformRevenueSyp: 0,
          customerShareSyp: 0,
          customerPointsEarned: 123456,
          createdAt: _t0,
        ),
      ],
      cashRequests: [
        CashRedemptionRequest(
          id: 'c1',
          customerId: 'c',
          pointsRequested: 123456789,
          cashValueSyp: 987654321,
          status: CashRequestStatus.pending,
          createdAt: _t0,
        ),
      ],
      products: store.products,
    );

Future<void> _pumpShell(
  WidgetTester tester,
  Brightness brightness,
) async {
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final repo = InMemoryYallaCashRepository(store);
  final cubit = CustomerAppCubit(repo);
  addTearDown(cubit.close);
  await tester.pumpWidget(_app(
    CustomerShell(
      cubit: cubit,
      state: _state(store),
      repository: repo,
      darkMode: brightness == Brightness.dark,
      onDarkModeChanged: (_) {},
    ),
    brightness,
  ));
  await _settle(tester);
}

void _noErrors(WidgetTester tester, String where) {
  Object? e = tester.takeException();
  while (e != null) {
    // Placeholder banner URLs never load in tests; nothing else may fail.
    expect(e, isA<NetworkImageLoadException>(), reason: where);
    e = tester.takeException();
  }
}

Future<void> _guidelines(WidgetTester tester, String where) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline),
      reason: '$where: 48dp touch targets');
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline),
      reason: '$where: every tap target is labelled');
}

void main() {
  const widths = [320.0, 360.0, 412.0];
  const scales = [1.0, 2.0];

  for (final b in Brightness.values) {
    for (final w in widths) {
      for (final s in scales) {
        testWidgets('${b.name} ${w}dp x$s: every tab and the drawer',
            (tester) async {
          final handle = tester.ensureSemantics();
          _viewport(tester, w, s);
          await _pumpShell(tester, b);
          _noErrors(tester, 'home');
          await _guidelines(tester, 'home');
          for (final tab in ['كودي', 'المحفظة', 'المتجر', 'الرئيسية']) {
            await tester.tap(find.descendant(
                of: find.byType(NavigationBar), matching: find.text(tab)));
            await _settle(tester);
            _noErrors(tester, tab);
            await _guidelines(tester, tab);
          }
          await tester.tap(find.byTooltip('القائمة'));
          await _settle(tester);
          _noErrors(tester, 'drawer');
          await _guidelines(tester, 'drawer');
          await tester.pumpWidget(const SizedBox());
          handle.dispose();
        });

        testWidgets('${b.name} ${w}dp x$s: store details and notifications',
            (tester) async {
          final handle = tester.ensureSemantics();
          _viewport(tester, w, s);
          final store = YallaCashStore.demo()..loginDemoCustomer();
          addTearDown(store.dispose);
          final repo = InMemoryYallaCashRepository(store);
          await repo.sendGeneralNotification(
              title: 'عرض خاص لعملاء يلا كاش في جميع المحلات المشاركة',
              body: 'تفاصيل طويلة للعرض الخاص بعملاء يلا كاش',
              idempotencyKey: 'qa');
          final cubit = CustomerAppCubit(repo);
          addTearDown(cubit.close);
          final partner = store.stores.first;
          await tester.pumpWidget(
              _app(StoreDetailsPage(store: partner, cubit: cubit), b));
          await _settle(tester);
          _noErrors(tester, 'store details');
          await _guidelines(tester, 'store details');
          await tester
              .pumpWidget(_app(CustomerNotificationsPage(cubit: cubit), b));
          await _settle(tester);
          _noErrors(tester, 'notifications');
          await _guidelines(tester, 'notifications');
          await tester.pumpWidget(const SizedBox());
          handle.dispose();
        });
      }
    }
  }

  for (final b in Brightness.values) {
    testWidgets('${b.name}: text contrast >= 4.5:1 on every tab',
        (tester) async {
      final handle = tester.ensureSemantics();
      _viewport(tester, 412, 1);
      await _pumpShell(tester, b);
      for (final tab in ['الرئيسية', 'كودي', 'المحفظة', 'المتجر']) {
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar), matching: find.text(tab)));
        await _settle(tester);
        await tester.pump(const Duration(seconds: 1));
        _noErrors(tester, tab);
        await expectLater(tester, meetsGuideline(textContrastGuideline),
            reason: tab);
      }
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    });
  }

  testWidgets('reduced motion: the shell settles with no running animation',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    _viewport(tester, 412, 1);
    await _pumpShell(tester, Brightness.light);
    for (final tab in ['كودي', 'المحفظة', 'المتجر', 'الرئيسية']) {
      await tester.tap(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(tab)));
      await tester.pump();
      // The page itself switches at once (zero-duration navigation, reveal
      // and transitions). Only Material's brief touch ripple may still run;
      // once it ends nothing is left animating, so no frame is scheduled.
      // (The reveal wrapper keeps a zero-duration tween in place by design,
      // so the page is never remounted.)
      expect(
        tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .animationDuration,
        Duration.zero,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse, reason: tab);
    }
    _noErrors(tester, 'reduced motion');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('RTL: tab order, right-hand drawer, signed amounts',
      (tester) async {
    _viewport(tester, 412, 1);
    await _pumpShell(tester, Brightness.light);
    final xs = [
      for (final t in ['الرئيسية', 'كودي', 'المحفظة', 'المتجر'])
        tester
            .getCenter(find.descendant(
                of: find.byType(NavigationBar), matching: find.text(t)))
            .dx,
    ];
    for (var i = 0; i < 3; i++) {
      expect(xs[i], greaterThan(xs[i + 1]));
    }
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('المحفظة')));
    await _settle(tester);
    // "+123,456 نقطة" with the sign isolated so it renders before the digits.
    final signed = YcAmount.format(123456, unit: 'نقطة', signed: true);
    expect(find.text(signed), findsOneWidget);
    expect(signed, contains('\u2066+123,456\u2069'));
    // Unsigned currency keeps its plain, correctly ordered text.
    expect(find.text('987,654,321 ل.س'), findsOneWidget);
    await tester.tap(find.byTooltip('القائمة'));
    await _settle(tester);
    expect(tester.getRect(find.byType(Drawer)).right, 412);
    _noErrors(tester, 'rtl');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Arabic Material localizations are active', (tester) async {
    _viewport(tester, 412, 1);
    await tester.pumpWidget(_app(
        Builder(
          builder: (context) => Text(
              MaterialLocalizations.of(context).backButtonTooltip,
              textDirection: Directionality.of(context)),
        ),
        Brightness.light));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, isNot('Back'));
    expect(text.textDirection, TextDirection.rtl);
  });
}
