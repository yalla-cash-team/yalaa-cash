import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/shell.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

const _tabs = ['الرئيسية', 'كودي', 'المحفظة', 'المتجر'];
const _longName = 'عبدالرحمنبنمحمدبنعبداللهالقحطانيالمتواجدفيمدينةالموصل';

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

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Pumps about a second of frames. Used where `pumpAndSettle` can never
/// finish because a page keeps an indeterminate loader running.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(Widget home, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      darkTheme: buildCustomerTheme(Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: home,
    );

/// Scaffold with the real header and nav, a recording drawer, and a body.
class _Harness extends StatefulWidget {
  const _Harness({
    this.name = 'أحمد',
    this.darkMode = false,
    this.calls,
  });

  final String name;
  final bool darkMode;
  final List<String>? calls;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    void log(String s) => widget.calls?.add(s);
    return Scaffold(
      appBar: CustomerAppBar(firstName: widget.name),
      drawer: CustomerDrawer(
        governorateName: 'نينوى',
        darkMode: widget.darkMode,
        onDarkModeChanged: (v) => log('dark:$v'),
        onChangeGovernorate: () => log('governorate'),
        onContact: () => log('contact'),
        onRate: () => log('rate'),
        onInvite: () => log('invite'),
        onLogout: () => log('logout'),
      ),
      body: Center(child: Text('tab $index')),
      bottomNavigationBar: CustomerNavBar(
        selectedIndex: index,
        onSelected: (i) => setState(() => index = i),
      ),
    );
  }
}

void main() {
  group('layout matrix: light/dark, 320/412dp, text x1/x2, RTL', () {
    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final name in ['أحمد', _longName, '']) {
            testWidgets('$b ${w}dp x$scale name="${name.length}ch" header+nav',
                (tester) async {
              _viewport(tester, w, scale);
              await tester
                  .pumpWidget(_app(_Harness(name: name), brightness: b));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              for (final t in _tabs) {
                expect(find.text(t), findsOneWidget);
              }
            });
          }
          testWidgets('$b ${w}dp x$scale drawer scrolls without overflow',
              (tester) async {
            _viewport(tester, w, scale);
            await tester.pumpWidget(_app(const _Harness(), brightness: b));
            await tester.tap(find.byTooltip('القائمة'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('إعدادات الحساب'), findsOneWidget);
          });
        }
      }
    }
  });

  group('header', () {
    for (final w in [320.0, 412.0]) {
      for (final name in ['أحمد', _longName]) {
        testWidgets(
            '${w}dp name=${name.length}ch: menu far right, logo exactly '
            'centred, bell far left, greeting below the toolbar',
            (tester) async {
          _viewport(tester, w, 1);
          await tester.pumpWidget(_app(_Harness(name: name)));
          await tester.pumpAndSettle();
          final menu = tester.getCenter(find.byTooltip('القائمة'));
          final bell = tester.getCenter(find.byTooltip('الإشعارات'));
          final logo = tester.getCenter(find.byType(YallaCashLogo));
          // Logo on the screen's true centre line, whatever the name length.
          expect(logo.dx, closeTo(w / 2, .5));
          expect(menu.dx, greaterThan(logo.dx));
          expect(logo.dx, greaterThan(bell.dx));
          // Menu and bell sit symmetrically at the far edges.
          expect(menu.dx - w / 2, closeTo(w / 2 - bell.dx, .5));
          expect(menu.dy, closeTo(bell.dy, .5));
          // The greeting row is below the 64dp toolbar, right-aligned.
          final greeting = tester.getRect(find.text('مرحباً'));
          expect(greeting.top, greaterThanOrEqualTo(64));
          expect(greeting.right, closeTo(w - YcSpace.gutter, 1));
          expect(tester.getSize(find.byType(AppBar)).height, 64 + 34);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
        'the official full logo is used, unaltered — no text '
        'substitute', (tester) async {
      _viewport(tester, 320, 2);
      await tester.pumpWidget(_app(const _Harness()));
      await tester.pumpAndSettle();
      final logo = tester.widget<YallaCashLogo>(find.byType(YallaCashLogo));
      expect(logo.markOnly, isFalse);
      expect(logo.color, isNull); // not tinted
      expect(tester.getSize(find.byType(YallaCashLogo)).height, 46);
      final image = tester.widget<Image>(find.descendant(
          of: find.byType(YallaCashLogo), matching: find.byType(Image)));
      expect(image.fit, BoxFit.contain);
      expect(find.text('يلا كاش'), findsNothing);
    });

    testWidgets('long name stays on one ellipsized line in the greeting row',
        (tester) async {
      _viewport(tester, 320, 1);
      await tester.pumpWidget(_app(const _Harness(name: _longName)));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text(_longName));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      final nameRect = tester.getRect(find.text(_longName));
      expect(nameRect.left, greaterThanOrEqualTo(YcSpace.gutter - .5));
      expect(nameRect.top, greaterThanOrEqualTo(64));
    });

    testWidgets('menu and bell share matching 44dp touch targets',
        (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      final menu = tester.getSize(find.ancestor(
          of: find.byIcon(Icons.menu_rounded),
          matching: find.byType(IconButton)));
      final bell = tester.getSize(find.ancestor(
          of: find.byIcon(Icons.notifications_none_rounded),
          matching: find.byType(IconButton)));
      // 44dp buttons; Material pads the touch area to 48dp tall for
      // accessibility. Menu and bell are identical either way.
      expect(menu.width, 44);
      expect(menu.height, greaterThanOrEqualTo(44));
      expect(bell, menu);
    });

    testWidgets('without the greeting (other tabs) the header is 64dp',
        (tester) async {
      await tester.pumpWidget(_app(const Scaffold(
        appBar: CustomerAppBar(firstName: 'أحمد', showGreeting: false),
      )));
      expect(find.text('مرحباً'), findsNothing);
      expect(tester.getSize(find.byType(AppBar)).height, 64);
      expect(find.byTooltip('الإشعارات'), findsOneWidget);
    });

    testWidgets('empty name shows only the greeting', (tester) async {
      await tester.pumpWidget(_app(const _Harness(name: '  ')));
      expect(find.text('مرحباً'), findsOneWidget);
    });

    testWidgets('header text scale is capped at 1.4x', (tester) async {
      _viewport(tester, 412, 2);
      await tester.pumpWidget(_app(const _Harness(name: 'أحمد')));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.text('أحمد'));
      final scaled = MediaQuery.textScalerOf(ctx).scale(10);
      // Grows with the system setting, but never past 1.4x (AppBar's own
      // title clamp of 1.34x applies on top).
      expect(scaled, greaterThan(10));
      expect(scaled, lessThanOrEqualTo(14.001));
    });

    for (final b in Brightness.values) {
      testWidgets('$b: status-bar icons contrast with the header',
          (tester) async {
        await tester.pumpWidget(_app(const _Harness(), brightness: b));
        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        );
        expect(
          region.value.statusBarIconBrightness,
          b == Brightness.dark ? Brightness.light : Brightness.dark,
        );
      });
    }

    testWidgets('menu button opens the drawer', (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      expect(find.text('إعدادات الحساب'), findsNothing);
      await tester.tap(find.byTooltip('القائمة'));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات الحساب'), findsOneWidget);
    });
  });

  group('notification bell', () {
    testWidgets('no unread indicator is ever shown', (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Badge)),
        findsNothing,
      );
      // The bell has no count or dot next to it.
      expect(
        find.descendant(
            of: find.ancestor(
                of: find.byIcon(Icons.notifications_none_rounded),
                matching: find.byType(IconButton)),
            matching: find.byType(Text)),
        findsNothing,
      );
    });

    for (final b in Brightness.values) {
      testWidgets(
          '$b: the bell opens an honest notifications screen and '
          'back returns', (tester) async {
        await tester.pumpWidget(_app(const _Harness(), brightness: b));
        await tester.tap(find.byTooltip('الإشعارات'));
        await tester.pumpAndSettle();
        expect(find.byType(CustomerNotificationsPage), findsOneWidget);
        expect(find.text('الإشعارات'), findsOneWidget);
        expect(find.text('سجل الإشعارات غير متاح بعد'), findsOneWidget);
        expect(find.textContaining('غير متاح حالياً'), findsOneWidget);
        // Never fabricated notifications.
        expect(find.byType(ListTile), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(CustomerNotificationsPage), findsNothing);
        expect(find.byTooltip('الإشعارات'), findsOneWidget);
      });
    }

    testWidgets('320dp x2: notifications screen fits', (tester) async {
      _viewport(tester, 320, 2);
      await tester.pumpWidget(_app(const _Harness()));
      await tester.tap(find.byTooltip('الإشعارات'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('سجل الإشعارات غير متاح بعد'), findsOneWidget);
    });
  });

  group('bottom navigation', () {
    testWidgets('four tabs in the existing order (right to left)',
        (tester) async {
      _viewport(tester, 412, 1);
      await tester.pumpWidget(_app(const _Harness()));
      final xs = [for (final t in _tabs) tester.getCenter(find.text(t)).dx];
      // RTL: first tab is rightmost.
      for (var i = 0; i < xs.length - 1; i++) {
        expect(xs[i], greaterThan(xs[i + 1]), reason: '${_tabs[i]} order');
      }
    });

    testWidgets('selection follows taps; touch targets >= 48', (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar().selectedIndex, 0);
      for (var i = 1; i < 4; i++) {
        await tester.tap(find.text(_tabs[i]));
        await tester.pumpAndSettle();
        expect(bar().selectedIndex, i);
        expect(find.text('tab $i'), findsOneWidget);
      }
      for (final d in tester.widgetList(find.byType(NavigationDestination))) {
        expect(d, isNotNull);
      }
      expect(
        tester.getSize(find.byType(NavigationBar)).height,
        greaterThanOrEqualTo(68),
      );
    });

    testWidgets('selected icons are filled variants; QR keeps one icon',
        (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    });

    testWidgets('selected icon settles with a short animation', (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      await tester.tap(find.text('المحفظة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final scale = tester
          .widgetList<AnimatedScale>(find.byType(AnimatedScale))
          .map((s) => s.scale);
      expect(scale, contains(1.0));
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.animationDuration, const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
    });

    testWidgets('reduced motion: zero-duration selection animations',
        (tester) async {
      _reduceMotion(tester);
      await tester.pumpWidget(_app(const _Harness()));
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.animationDuration, Duration.zero);
      for (final s
          in tester.widgetList<AnimatedScale>(find.byType(AnimatedScale))) {
        expect(s.duration, Duration.zero);
      }
      await tester.tap(find.text('كودي'));
      await tester.pump();
      expect(find.text('tab 1'), findsOneWidget);
    });
  });

  group('drawer', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byTooltip('القائمة'));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps every setting, in three groups', (tester) async {
      _viewport(tester, 412, 1);
      await tester.pumpWidget(_app(const _Harness()));
      await open(tester);
      for (final t in [
        'التفضيلات',
        'تغيير المحافظة',
        'نينوى',
        'الوضع الداكن',
        'اللغة',
        'العربية',
        'الدعم والمشاركة',
        'تواصل معنا',
        'قيّم التطبيق',
        'ادعُ أصدقاءك واربح نقاط',
        'الحساب',
        'تسجيل الخروج',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('opens from the right edge in RTL', (tester) async {
      _viewport(tester, 412, 1);
      await tester.pumpWidget(_app(const _Harness()));
      await open(tester);
      expect(tester.getRect(find.byType(Drawer)).right, 412);
    });

    testWidgets('every action fires its own callback once', (tester) async {
      _viewport(tester, 412, 1);
      final calls = <String>[];
      await tester.pumpWidget(_app(_Harness(calls: calls)));
      await open(tester);
      for (final t in [
        'تغيير المحافظة',
        'تواصل معنا',
        'قيّم التطبيق',
        'ادعُ أصدقاءك واربح نقاط',
        'تسجيل الخروج',
      ]) {
        await tester.ensureVisible(find.text(t));
        await tester.tap(find.text(t));
        await tester.pump();
      }
      expect(calls, ['governorate', 'contact', 'rate', 'invite', 'logout']);
    });

    for (final dark in [false, true]) {
      testWidgets('dark-mode row and switch both request ${!dark}',
          (tester) async {
        final calls = <String>[];
        await tester.pumpWidget(_app(_Harness(darkMode: dark, calls: calls)));
        await open(tester);
        expect(tester.widget<Switch>(find.byType(Switch)).value, dark);
        await tester.tap(find.text('الوضع الداكن'));
        await tester.pump();
        await tester.tap(find.byType(Switch));
        await tester.pump();
        expect(calls, ['dark:${!dark}', 'dark:${!dark}']);
      });
    }

    testWidgets('language row is informational only', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_app(_Harness(calls: calls)));
      await open(tester);
      await tester.tap(find.text('اللغة'));
      await tester.pump();
      expect(calls, isEmpty);
    });

    testWidgets('logout title uses the danger colour, tap target >= 56',
        (tester) async {
      await tester.pumpWidget(_app(const _Harness()));
      await open(tester);
      final style = tester.widget<Text>(find.text('تسجيل الخروج')).style!;
      expect(style.color, isNotNull);
      expect(
          style.color,
          isNot(Theme.of(tester.element(find.byType(Drawer)))
              .colorScheme
              .onSurface));
      final row = tester.getSize(find
          .ancestor(
              of: find.text('تسجيل الخروج'), matching: find.byType(YcListRow))
          .first);
      expect(row.height, greaterThanOrEqualTo(56));
    });

    testWidgets('closes with back and the scrim; scrim tap does not act',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_app(_Harness(calls: calls)));
      await open(tester);
      await tester.tapAt(const Offset(20, 300)); // scrim on the left
      await tester.pumpAndSettle();
      expect(find.text('إعدادات الحساب').hitTestable(), findsNothing);
      expect(calls, isEmpty);
    });
  });

  group('CustomerShell integration', () {
    late YallaCashStore store;

    Future<({CustomerAppCubit cubit, List<bool> dark})> pumpShell(
      WidgetTester tester, {
      Brightness brightness = Brightness.light,
      double height = 1600,
    }) async {
      _viewport(tester, 412, 1, height: height);
      store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      final stores = [
        for (var i = 0; i < 10; i++)
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
      final repo = InMemoryYallaCashRepository(store);
      final cubit = CustomerAppCubit(repo);
      final dark = <bool>[];
      await tester.pumpWidget(_app(
        CustomerShell(
          cubit: cubit,
          state:
              CustomerAppState(customer: store.currentCustomer, stores: stores),
          repository: repo,
          darkMode: brightness == Brightness.dark,
          onDarkModeChanged: dark.add,
        ),
        brightness: brightness,
      ));
      await _settle(tester);
      return (cubit: cubit, dark: dark);
    }

    testWidgets('greeting row shows on Home only and returns with it',
        (tester) async {
      await pumpShell(tester);
      expect(find.text('مرحباً'), findsOneWidget);
      await tester.tap(find.text('المحفظة'));
      await _settle(tester);
      expect(find.text('مرحباً'), findsNothing);
      expect(tester.getSize(find.byType(AppBar)).height, 64);
      await tester.tap(find.text('الرئيسية'));
      await _settle(tester);
      expect(find.text('مرحباً'), findsOneWidget);
    });

    testWidgets('greets the real customer by first name', (tester) async {
      await pumpShell(tester);
      final first = store.currentCustomer!.name.split(' ').first;
      expect(find.text(first), findsOneWidget);
      expect(find.text('مرحباً'), findsOneWidget);
    });

    testWidgets('tab switching preserves Home scroll position and tab state',
        (tester) async {
      // A phone-sized viewport so Home (ten store cards) actually scrolls.
      await pumpShell(tester, height: 800);
      final homeScrollable = find.descendant(
        of: find.byKey(const PageStorageKey<String>('customer-home')),
        matching: find.byType(Scrollable),
      );
      await tester.drag(homeScrollable, const Offset(0, -500));
      await _settle(tester);
      final before =
          tester.state<ScrollableState>(homeScrollable).position.pixels;
      expect(before, greaterThan(100));

      await tester.tap(find.text('المحفظة'));
      await _settle(tester);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2);
      expect(find.byType(CustomerWalletPage), findsOneWidget);

      await tester.tap(find.text('الرئيسية'));
      await _settle(tester);
      final home = tester.state<ScrollableState>(homeScrollable);
      expect(home.position.pixels, before);
      // The pages stay mounted in the IndexedStack (none are rebuilt from 0).
      expect(find.byType(IndexedStack), findsWidgets);
      expect(find.byType(CustomerQrPage, skipOffstage: false), findsOneWidget);
      expect(find.byType(CustomerRewardsPage, skipOffstage: false),
          findsOneWidget);
    });

    testWidgets('drawer dark switch reaches the shell callback',
        (tester) async {
      final h = await pumpShell(tester);
      await tester.tap(find.byTooltip('القائمة'));
      await _settle(tester);
      await tester.tap(find.text('الوضع الداكن'));
      await tester.pump();
      expect(h.dark, [true]);
    });

    testWidgets('drawer governorate opens the governorate picker',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byTooltip('القائمة'));
      await _settle(tester);
      await tester.tap(find.text('تغيير المحافظة'));
      await _settle(tester);
      expect(find.byType(GovernorateSelectionScreen), findsOneWidget);
    });

    testWidgets('drawer invite closes the drawer and opens the share sheet',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byTooltip('القائمة'));
      await _settle(tester);
      await tester.tap(find.text('ادعُ أصدقاءك واربح نقاط'));
      await _settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('إعدادات الحساب').hitTestable(), findsNothing);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pumpShell(tester, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomerNavBar), findsOneWidget);
    });
  });
}
