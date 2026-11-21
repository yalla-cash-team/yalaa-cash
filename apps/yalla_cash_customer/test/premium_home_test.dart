import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';
import 'package:yalla_cash_customer/src/ui/shell.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

void _viewport(WidgetTester tester, double width, double scale,
    {double height = 1600}) {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget home, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: customerLightTheme,
      darkTheme: customerDarkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: home,
    );

Banner _banner(String id) => Banner(
      id: id,
      title: 'ad $id',
      imageUrl: '',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

List<PartnerStore> _stores(int n) => [
      for (var i = 0; i < n; i++)
        PartnerStore(
          id: 's$i',
          name: 'محل $i',
          category: 'مطاعم',
          commissionRate: 5,
          description: 'وصف',
          location: 'الموصل',
          iconSeed: 0,
          governorateId: 'g',
        ),
    ];

/// Counts refresh() calls without changing any behaviour.
class _CountingCubit extends CustomerAppCubit {
  _CountingCubit(super.repository);

  int refreshes = 0;

  @override
  Future<void> refresh() {
    refreshes++;
    return super.refresh();
  }
}

Future<_CountingCubit> _pumpShell(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  double width = 412,
  double scale = 1,
  List<Banner> banners = const [],
  int stores = 3,
}) async {
  _viewport(tester, width, scale);
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final repo = InMemoryYallaCashRepository(store);
  final cubit = _CountingCubit(repo);
  await tester.pumpWidget(_app(
    CustomerShell(
      cubit: cubit,
      state: CustomerAppState(
        customer: store.currentCustomer,
        points: const PointsSummary(
            pointsBalance: 1500, heldPoints: 300, availablePoints: 1200),
        stores: _stores(stores),
        banners: banners,
      ),
      repository: repo,
      darkMode: brightness == Brightness.dark,
      onDarkModeChanged: (_) {},
    ),
    brightness: brightness,
  ));
  await _settle(tester);
  return cubit;
}

int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  group('quick actions', () {
    testWidgets('three shortcuts under the balance card, in RTL order',
        (tester) async {
      await _pumpShell(tester);
      final qr = tester.getCenter(find.byKey(const Key('quick-action-qr')));
      final redeem =
          tester.getCenter(find.byKey(const Key('quick-action-redeem')));
      final history =
          tester.getCenter(find.byKey(const Key('quick-action-history')));
      expect(qr.dx, greaterThan(redeem.dx));
      expect(redeem.dx, greaterThan(history.dx));
      final hero = tester.getRect(find
          .ancestor(
              of: find.text('رصيد النقاط'),
              matching: find.byType(YcBalanceHero))
          .first);
      expect(
          tester.getRect(find.byKey(const Key('quick-action-qr'))).top -
              hero.bottom,
          YcSpace.md);
    });

    for (final (key, tab) in [
      ('quick-action-qr', 1),
      ('quick-action-redeem', 3),
      ('quick-action-history', 2),
    ]) {
      testWidgets('$key opens existing tab $tab exactly like the nav bar',
          (tester) async {
        final cubit = await _pumpShell(tester);
        final before = cubit.refreshes;
        await tester.tap(find.byKey(Key(key)));
        await _settle(tester);
        expect(_selectedTab(tester), tab);
        // Same tab-switch behaviour as the bottom navigation: one refresh.
        expect(cubit.refreshes, before + 1);
      });
    }

    testWidgets('each shortcut is one button with a 48dp+ target',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpShell(tester);
      for (final key in [
        'quick-action-qr',
        'quick-action-redeem',
        'quick-action-history',
      ]) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(find.bySemanticsLabel('كودي'), findsWidgets);
      handle.dispose();
    });

    testWidgets('hidden when Home is hosted without a shell', (tester) async {
      _viewport(tester, 412, 1);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      await tester.pumpWidget(_app(Scaffold(
        body: CustomerHomePage(
          cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
          state: CustomerAppState(customer: store.currentCustomer),
          customer: store.currentCustomer!,
        ),
      )));
      expect(find.byKey(const Key('quick-action-qr')), findsNothing);
    });
  });

  group('QR tab emphasis', () {
    testWidgets('one QR glyph on a gradient disc; gold ring when selected',
        (tester) async {
      await _pumpShell(tester);
      expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
      BoxDecoration disc() => tester
          .widget<AnimatedContainer>(find
              .ancestor(
                  of: find.byIcon(Icons.qr_code_2_rounded),
                  matching: find.byType(AnimatedContainer))
              .first)
          .decoration! as BoxDecoration;
      expect(disc().gradient, isNotNull);
      expect((disc().border! as Border).top.color, Colors.transparent);
      await tester.tap(find.text('كودي').last);
      await _settle(tester);
      expect(_selectedTab(tester), 1);
      expect((disc().border! as Border).top.color, YallaColors.gold);
      // The four tabs and their order are unchanged (right to left).
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
    });
  });

  group('rebuild isolation', () {
    testWidgets(
        'an unrelated update reuses the tab pages; a points change '
        'rebuilds Home', (tester) async {
      _viewport(tester, 412, 1);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      final repo = InMemoryYallaCashRepository(store);
      final cubit = CustomerAppCubit(repo);
      addTearDown(cubit.close);
      final initial = CustomerAppState(
        customer: store.currentCustomer,
        points: const PointsSummary(
            pointsBalance: 10, heldPoints: 0, availablePoints: 10),
        stores: _stores(2),
      );
      await tester.pumpWidget(_app(_ShellHost(
        cubit: cubit,
        repository: repo,
        initial: initial,
      )));
      await _settle(tester);
      final host = tester.state<_ShellHostState>(find.byType(_ShellHost));
      T page<T extends Widget>() =>
          tester.widget<T>(find.byType(T, skipOffstage: false));
      final home = page<CustomerHomePage>();
      final wallet = page<CustomerWalletPage>();
      final qr = page<CustomerQrPage>();

      // Only the notification count changes: every tab page is reused.
      host.update(initial.copyWith(unreadNotificationCount: 3));
      await tester.pump();
      expect(identical(page<CustomerHomePage>(), home), isTrue);
      expect(identical(page<CustomerWalletPage>(), wallet), isTrue);
      expect(identical(page<CustomerQrPage>(), qr), isTrue);
      expect(find.byKey(const Key('notifications-unread-dot')),
          findsOneWidget);

      // Points change: Home and Wallet rebuild with the real new figure.
      host.update(initial.copyWith(
        unreadNotificationCount: 3,
        points: const PointsSummary(
            pointsBalance: 25, heldPoints: 0, availablePoints: 25),
      ));
      await tester.pump();
      expect(identical(page<CustomerHomePage>(), home), isFalse);
      expect(identical(page<CustomerWalletPage>(), wallet), isFalse);
      expect(identical(page<CustomerQrPage>(), qr), isTrue);
      expect(find.text('25'), findsWidgets);
    });
  });

  group('banner carousel', () {
    testWidgets('shows page dots that follow the page', (tester) async {
      await _pumpShell(tester, banners: [_banner('a'), _banner('b')]);
      final dots = find.byType(YcPageDots);
      expect(dots, findsOneWidget);
      expect(tester.widget<YcPageDots>(dots).index, 0);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<YcPageDots>(dots).index, 1);
    });

    testWidgets('pauses while another tab is showing', (tester) async {
      await _pumpShell(tester, banners: [_banner('a'), _banner('b')]);
      ScrollPosition position() => tester
          .state<ScrollableState>(find.descendant(
              of: find.byType(PageView, skipOffstage: false),
              matching: find.byType(Scrollable, skipOffstage: false)))
          .position;
      await tester.tap(find.text('المحفظة').last);
      await _settle(tester);
      // Well past several intervals: the hidden carousel does not move.
      await tester.pump(const Duration(seconds: 12));
      await tester.pump(const Duration(milliseconds: 400));
      expect(position().pixels, 0);
      // Back on Home it resumes.
      await tester.tap(find.text('الرئيسية').last);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(position().pixels, greaterThan(0));
    });
  });

  group('session restore screen', () {
    testWidgets('official logo and a quiet progress bar', (tester) async {
      await tester.pumpWidget(_app(const CustomerSessionRestoreScreen()));
      expect(find.byType(YallaCashLogo), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('layout matrix', () {
    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp x$scale: home with quick actions fits',
              (tester) async {
            await _pumpShell(tester,
                brightness: b,
                width: w,
                scale: scale,
                banners: [_banner('a'), _banner('b')]);
            expect(tester.takeException(), isNull);
            expect(
                find.byKey(const Key('quick-action-history')), findsOneWidget);
          });
        }
      }
    }
  });
}

/// Hosts the real shell and lets a test replace the state it receives.
class _ShellHost extends StatefulWidget {
  const _ShellHost({
    required this.cubit,
    required this.repository,
    required this.initial,
  });

  final CustomerAppCubit cubit;
  final YallaCashRepository repository;
  final CustomerAppState initial;

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  late CustomerAppState state = widget.initial;

  void update(CustomerAppState next) => setState(() => state = next);

  @override
  Widget build(BuildContext context) => CustomerShell(
        cubit: widget.cubit,
        state: state,
        repository: widget.repository,
        darkMode: false,
        onDarkModeChanged: (_) {},
      );
}
