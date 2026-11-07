import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

PointsSummary _points(int balance, {int held = 0}) => PointsSummary(
      pointsBalance: balance,
      heldPoints: held,
      availablePoints: balance - held,
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

final _storeCard =
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StoreCard');
final _balanceCard = find.ancestor(
  of: find.text('رصيد النقاط'),
  matching: find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).gradient != null,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  PointsSummary? points,
  List<Banner> banners = const [],
  List<PartnerStore>? stores,
  Brightness brightness = Brightness.light,
  double width = 412,
  double height = 1600,
  double scale = 1,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      darkTheme: buildCustomerTheme(Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: _Host(
          store: store,
          points: points,
          banners: banners,
          stores: stores ?? _stores(2),
        ),
      ),
    ),
  );
  if (settle) await tester.pump(const Duration(milliseconds: 600));
}

/// Lets a test change the state fed to the home page without remounting it.
class _Host extends StatefulWidget {
  const _Host({
    required this.store,
    required this.points,
    required this.banners,
    required this.stores,
  });

  final YallaCashStore store;
  final PointsSummary? points;
  final List<Banner> banners;
  final List<PartnerStore> stores;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late PointsSummary? points = widget.points;
  late List<PartnerStore> stores = widget.stores;

  void update({PointsSummary? points, List<PartnerStore>? stores}) =>
      setState(() {
        this.points = points ?? this.points;
        this.stores = stores ?? this.stores;
      });

  @override
  Widget build(BuildContext context) => CustomerHomePage(
        cubit: CustomerAppCubit(InMemoryYallaCashRepository(widget.store)),
        state: CustomerAppState(
          customer: widget.store.currentCustomer,
          points: points,
          stores: stores,
          banners: widget.banners,
        ),
        customer: widget.store.currentCustomer!,
      );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

double _entranceOpacity(WidgetTester tester) => tester
    .widget<Opacity>(find
        .ancestor(of: find.byType(ListView), matching: find.byType(Opacity))
        .first)
    .opacity;

void main() {
  group('balance card: real values, accurate separation', () {
    testWidgets('shows the total balance and the available/pending split',
        (tester) async {
      await _pump(tester, points: _points(1500, held: 300));
      expect(find.text('1,500'), findsOneWidget);
      expect(find.text('المتاح'), findsOneWidget);
      expect(find.text('1,200'), findsOneWidget);
      expect(find.text('قيد المعالجة'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      // RTL: available (first) sits to the right of pending.
      expect(tester.getCenter(find.text('المتاح')).dx,
          greaterThan(tester.getCenter(find.text('قيد المعالجة')).dx));
    });

    testWidgets('no pending points: the breakdown still shows, with a real 0',
        (tester) async {
      await _pump(tester, points: _points(1500));
      // Total and available are both 1,500; pending is shown as 0.
      expect(find.text('1,500'), findsNWidgets(2));
      expect(find.text('المتاح'), findsOneWidget);
      expect(find.text('قيد المعالجة'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('a real zero balance is shown as 0', (tester) async {
      await _pump(tester, points: _points(0));
      // Total, available and pending are all a real 0.
      expect(find.text('0'), findsNWidgets(3));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('loading never shows the breakdown with placeholder numbers',
        (tester) async {
      await _pump(tester, points: null, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('المتاح'), findsNothing);
      expect(find.text('قيد المعالجة'), findsNothing);
    });

    testWidgets('loading shows a progress bar and never a false zero',
        (tester) async {
      await _pump(tester, points: null, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('رصيد النقاط'), findsOneWidget);
    });

    testWidgets('numbers use the existing thousands formatting',
        (tester) async {
      await _pump(tester, points: _points(12345678, held: 1000000));
      expect(find.text(formatNumber(12345678)), findsOneWidget);
      expect(find.text('12,345,678'), findsOneWidget);
      expect(find.text('11,345,678'), findsOneWidget);
      expect(find.text('1,000,000'), findsOneWidget);
    });

    testWidgets('values update in place when the balance changes',
        (tester) async {
      await _pump(tester, points: _points(100, held: 20));
      tester
          .state<_HostState>(find.byType(_Host))
          .update(points: _points(250, held: 50));
      await tester.pump();
      // Real values straight away: no count-up through intermediate numbers.
      expect(find.text('250'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('official mark is kept, undistorted', (tester) async {
      await _pump(tester, points: _points(10));
      final logo = find.descendant(
          of: _balanceCard.first, matching: find.byType(YallaCashLogo));
      expect(logo, findsOneWidget);
      expect(tester.widget<YallaCashLogo>(logo).markOnly, isTrue);
      expect(tester.getSize(logo).height, 20);
    });
  });

  group('balance card: readability and proportions', () {
    for (final b in Brightness.values) {
      testWidgets(
          '$b: hero figures >= 3:1 (large text) on both stops; breakdown '
          'text >= 4.5:1 on its inset panel', (tester) async {
        await _pump(tester, points: _points(1500, held: 300), brightness: b);
        final deco = tester.widget<DecoratedBox>(_balanceCard.first).decoration
            as BoxDecoration;
        final gradient = deco.gradient! as LinearGradient;
        expect(gradient.colors.length, 2);
        final panel = (tester
                .widget<DecoratedBox>(find
                    .ancestor(
                      of: find.text('المتاح'),
                      matching: find.byWidgetPredicate((w) =>
                          w is DecoratedBox &&
                          w.decoration is BoxDecoration &&
                          (w.decoration as BoxDecoration).color != null),
                    )
                    .first)
                .decoration as BoxDecoration)
            .color!;
        for (final stop in gradient.colors) {
          final hero = _contrast(Colors.white, stop);
          final small = _contrast(Colors.white, Color.alphaBlend(panel, stop));
          // ignore: avoid_print
          print('$b stop $stop: hero ${hero.toStringAsFixed(2)}, '
              'panel ${small.toStringAsFixed(2)}');
          expect(hero, greaterThanOrEqualTo(3.0), reason: 'hero on $stop');
          expect(small, greaterThanOrEqualTo(4.5), reason: 'panel on $stop');
        }
      });
    }

    testWidgets('gradient is the bright brand sky-blue → medium-blue range',
        (tester) async {
      await _pump(tester, points: _points(1));
      final gradient = (tester
              .widget<DecoratedBox>(_balanceCard.first)
              .decoration as BoxDecoration)
          .gradient! as LinearGradient;
      for (final c in gradient.colors) {
        // Between the brand sky blue (primary) and primaryStrong.
        expect(c.b, greaterThan(c.r));
        expect(c.computeLuminance(),
            lessThanOrEqualTo(YallaColors.primary.computeLuminance()));
        expect(c.computeLuminance(),
            greaterThanOrEqualTo(YallaColors.primaryStrong.computeLuminance()));
      }
      // Noticeably brighter than the previous navy-deepened card.
      final previousStart =
          Color.lerp(YallaColors.primaryStrong, YallaColors.navy, .15)!;
      expect(gradient.colors.first.computeLuminance(),
          greaterThan(previousStart.computeLuminance() * 1.5));
    });

    testWidgets(
        'proportions: the breakdown is always present, so the card is the '
        'same height with or without pending points', (tester) async {
      await _pump(tester, points: _points(1500));
      final plain = tester.getSize(_balanceCard.first).height;
      // Unmount so the second pump builds fresh state with pending points.
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, points: _points(1500, held: 300));
      expect(find.text('قيد المعالجة'), findsOneWidget);
      final withSplit = tester.getSize(_balanceCard.first).height;
      // ignore: avoid_print
      print('balance card height: plain=$plain withPending=$withSplit');
      expect(plain, withSplit);
      // Grows only for the breakdown (previously 139px with pending points).
      expect(withSplit, lessThanOrEqualTo(165));
    });

    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp x$scale: huge numbers never overflow',
              (tester) async {
            await _pump(
              tester,
              points: _points(987654321, held: 123456789),
              banners: [_banner('a'), _banner('b')],
              brightness: b,
              width: w,
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            expect(find.text('987,654,321'), findsOneWidget);
            // The figure stays inside the card.
            final card = tester.getRect(_balanceCard.first);
            final fig = tester.getRect(find.text('987,654,321'));
            expect(fig.right, lessThanOrEqualTo(card.right + 0.5));
            expect(fig.left, greaterThanOrEqualTo(card.left - 0.5));
            await tester.pumpWidget(const SizedBox());
          });
        }
      }
    }
  });

  group('home composition: rhythm and margins', () {
    testWidgets('consistent horizontal margins for card, carousel, stores',
        (tester) async {
      await _pump(tester,
          points: _points(10), banners: [_banner('a'), _banner('b')]);
      const w = 412.0;
      final card = tester.getRect(_balanceCard.first);
      expect(card.left, YcSpace.gutter);
      expect(card.right, w - YcSpace.gutter);
      final carousel = tester.getRect(find
          .ancestor(
              of: find.byType(PageView), matching: find.byType(AspectRatio))
          .first);
      expect(carousel.left, YcSpace.gutter);
      expect(carousel.right, w - YcSpace.gutter);
      for (final r in tester
          .widgetList(_storeCard)
          .map((w) => tester.getRect(find.byWidget(w)))) {
        expect(r.left, YcSpace.gutter);
        expect(r.right, w - YcSpace.gutter);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'vertical rhythm: 16 card→carousel, 24 carousel→section, '
        '12 header→stores, 12 between stores', (tester) async {
      await _pump(tester,
          points: _points(10), banners: [_banner('a'), _banner('b')]);
      final card = tester.getRect(_balanceCard.first);
      final carousel = tester.getRect(find
          .ancestor(
              of: find.byType(PageView), matching: find.byType(AspectRatio))
          .first);
      final header = tester.getRect(find.byType(YcSectionHeader));
      final cards = tester
          .widgetList(_storeCard)
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList();
      expect(carousel.top - card.bottom, YcSpace.md);
      expect(header.top - carousel.bottom, YcSpace.xl);
      // closeTo: store cards can land on fractional pixel positions.
      expect(cards.first.top - header.bottom, closeTo(YcSpace.sm, .01));
      expect(cards[1].top - cards[0].bottom, closeTo(YcSpace.sm, .01));
      expect(card.top, YcSpace.sm, reason: 'top inset under the app header');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('without banners there is a single 24px gap, not two',
        (tester) async {
      await _pump(tester, points: _points(10));
      final card = tester.getRect(_balanceCard.first);
      final header = tester.getRect(find.byType(YcSectionHeader));
      expect(header.top - card.bottom, YcSpace.xl);
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('stores keep the premium-minimal card and section title',
        (tester) async {
      await _pump(tester, points: _points(10), stores: _stores(3));
      expect(find.text('المحلات الحصرية بمدينتك'), findsOneWidget);
      expect(_storeCard, findsNWidgets(3));
      // Premium-minimal card: no badge or pill added to it.
      expect(find.text('حصري'), findsNothing);
    });

    testWidgets('empty stores shows the restrained empty state',
        (tester) async {
      await _pump(tester, points: _points(10), stores: const []);
      expect(find.byType(YcEmptyState), findsOneWidget);
      expect(find.text('لا توجد محلات متاحة حالياً'), findsOneWidget);
    });
  });

  group('entrance animation', () {
    testWidgets('fades and rises in once, then rests at full opacity',
        (tester) async {
      await _pump(tester, points: _points(10), settle: false);
      await tester.pump(const Duration(milliseconds: 60));
      final early = _entranceOpacity(tester);
      expect(early, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(_entranceOpacity(tester), 1);
    });

    testWidgets('real values are visible from the first frame (no count-up)',
        (tester) async {
      await _pump(tester, points: _points(1500, held: 300), settle: false);
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.text('1,500'), findsOneWidget);
      expect(find.text('1,200'), findsOneWidget);
    });

    testWidgets('does not replay on rebuild or unrelated state updates',
        (tester) async {
      await _pump(tester, points: _points(10));
      expect(_entranceOpacity(tester), 1);
      tester
          .state<_HostState>(find.byType(_Host))
          .update(stores: _stores(4), points: _points(99, held: 9));
      await tester.pump();
      expect(_entranceOpacity(tester), 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(_entranceOpacity(tester), 1);
    });

    testWidgets('does not replay when scrolling away and back', (tester) async {
      await _pump(tester,
          points: _points(10), stores: _stores(12), height: 700);
      final scrollable = find.descendant(
          of: find.byType(ListView), matching: find.byType(Scrollable));
      await tester.drag(scrollable, const Offset(0, -1500));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.drag(scrollable, const Offset(0, 1500));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_entranceOpacity(tester), 1);
    });

    testWidgets('tab return keeps the page mounted and fully visible',
        (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      final repo = InMemoryYallaCashRepository(store);
      await tester.pumpWidget(MaterialApp(
        theme: buildCustomerTheme(Brightness.light),
        builder: (c, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: CustomerShell(
          cubit: CustomerAppCubit(repo),
          state: CustomerAppState(
            customer: store.currentCustomer,
            points: _points(500),
            stores: _stores(2),
          ),
          repository: repo,
          darkMode: false,
          onDarkModeChanged: (_) {},
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_entranceOpacity(tester), 1);
      await tester.tap(find.text('المحفظة'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('الرئيسية'));
      await tester.pump();
      // Straight back at full opacity: no fade-in on return.
      expect(_entranceOpacity(tester), 1);
      // Total and available (nothing pending) both read 500.
      expect(find.text('500'), findsNWidgets(2));
    });

    testWidgets('reduced motion: no animation layers at all', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester, points: _points(1500, held: 300), settle: false);
      expect(
        find.ancestor(
            of: find.byType(ListView), matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(find.text('1,500'), findsOneWidget);
    });
  });

  group('regression guards', () {
    testWidgets('light and dark both render the whole home screen',
        (tester) async {
      for (final b in Brightness.values) {
        await _pump(tester,
            points: _points(1500, held: 300),
            banners: [_banner('a'), _banner('b')],
            brightness: b);
        expect(tester.takeException(), isNull);
        expect(_balanceCard, findsWidgets);
        expect(find.byType(PageView), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('carousel keeps its single rounded clip around the PageView',
        (tester) async {
      await _pump(tester,
          points: _points(10), banners: [_banner('a'), _banner('b')]);
      final clip = find.ancestor(
          of: find.byType(PageView), matching: find.byType(ClipRRect));
      expect(clip, findsOneWidget);
      expect(tester.widget<ClipRRect>(clip).borderRadius,
          BorderRadius.circular(22));
      expect(
        find.descendant(
            of: find.byType(PageView), matching: find.byType(ClipRRect)),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
