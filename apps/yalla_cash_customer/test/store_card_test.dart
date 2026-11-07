import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';

/// The exact approved badge copy. Written out in full (not built from
/// pieces) so a regression in the literal string is caught verbatim.
const _badgeText = 'شريك حصري لدى يلا كاش';

PartnerStore _store({
  String id = 's1',
  String? logoUrl,
  String name = 'مطعم الأصالة',
  String category = 'مطاعم',
  String location = 'الموصل',
}) =>
    PartnerStore(
      id: id,
      name: name,
      category: category,
      commissionRate: 5,
      description: 'وصف المحل',
      location: location,
      iconSeed: 0,
      governorateId: 'g1',
      logoUrl: logoUrl,
    );

final _storeCard =
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StoreCard');
final _arrow = find
    .byWidgetPredicate((w) => w.runtimeType.toString() == '_StoreCardArrow');
final _accent = find
    .byWidgetPredicate((w) => w.runtimeType.toString() == '_StoreCardAccent');

void _onlyImageFailures(WidgetTester tester) {
  Object? e = tester.takeException();
  while (e != null) {
    expect(e, isA<NetworkImageLoadException>());
    e = tester.takeException();
  }
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Hosts the real [CustomerHomePage] with the given stores, exactly as the
/// app renders the card list — not a card built in isolation.
Future<void> _pumpHome(
  WidgetTester tester, {
  required List<PartnerStore> stores,
  Brightness brightness = Brightness.light,
  double width = 412,
  double height = 1600,
  double scale = 1,
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
  await tester.pumpWidget(MaterialApp(
    theme: buildCustomerTheme(Brightness.light),
    darkTheme: buildCustomerTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(
      body: CustomerHomePage(
        cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
        state:
            CustomerAppState(customer: store.currentCustomer, stores: stores),
        customer: store.currentCustomer!,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('layout and copy', () {
    testWidgets(
        'shows only the real store name and the exact partner badge — '
        'never sample data', (tester) async {
      await _pumpHome(tester, stores: [
        _store(
          name: 'صيدلية الشفاء',
          category: 'صيدليات',
          location: 'الدواسة، الموصل',
        ),
      ]);
      expect(find.text('صيدلية الشفاء'), findsOneWidget);
      expect(find.text(_badgeText), findsOneWidget);
      // Never any mockup placeholder text.
      for (final mock in ['متجر تجريبي', 'اسم المحل', 'Store Name']) {
        expect(find.text(mock), findsNothing);
      }
    });

    testWidgets(
        'category, city, neighbourhood and location icons are absent '
        'from Home cards', (tester) async {
      await _pumpHome(tester, stores: [
        _store(
          name: 'صيدلية الشفاء',
          category: 'صيدليات ومستلزمات طبية',
          location: 'الموصل - حي الزهور قرب دوار الساعة',
        ),
      ]);
      expect(find.textContaining('صيدليات ومستلزمات'), findsNothing);
      expect(find.textContaining('الموصل'), findsNothing);
      expect(find.textContaining('دوار الساعة'), findsNothing);
      expect(
          find.descendant(
              of: _storeCard,
              matching: find.byIcon(Icons.location_on_outlined)),
          findsNothing);
      expect(
          find.descendant(
              of: _storeCard, matching: find.byIcon(Icons.sell_outlined)),
          findsNothing);
      // Exactly two texts on the card: the name and the badge.
      final texts = tester
          .widgetList<Text>(
              find.descendant(of: _storeCard, matching: find.byType(Text)))
          .map((w) => w.data)
          .toList();
      expect(texts, ['صيدلية الشفاء', _badgeText]);
    });

    testWidgets('the removed information is still on StoreDetailsPage',
        (tester) async {
      await _pumpHome(tester, stores: [
        _store(
          name: 'صيدلية الشفاء',
          category: 'صيدليات ومستلزمات طبية',
          location: 'الموصل - حي الزهور قرب دوار الساعة',
        ),
      ]);
      await tester.tap(find.text('صيدلية الشفاء'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      _onlyImageFailures(tester);
      expect(find.byType(StoreDetailsPage), findsOneWidget);
      expect(find.text('صيدليات ومستلزمات طبية'), findsOneWidget);
      expect(find.text('الموصل - حي الزهور قرب دوار الساعة'), findsOneWidget);
    });

    testWidgets('badge, logo and arrow all present on every card',
        (tester) async {
      await _pumpHome(tester, stores: [_store(id: 'a'), _store(id: 'b')]);
      expect(find.text(_badgeText), findsNWidgets(2));
      expect(_arrow, findsNWidgets(2));
    });

    testWidgets('no oversized decorative shapes: the large circle is gone',
        (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      expect(_accent, findsNothing);
      // Only small circles remain (the 28dp arrow).
      final circles = tester.widgetList<Container>(find.descendant(
          of: _storeCard,
          matching: find.byWidgetPredicate((w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle)));
      for (final c in circles) {
        expect(c.constraints?.maxWidth ?? 0, lessThanOrEqualTo(30));
      }
    });

    testWidgets('compact: about the logo plate plus padding (~100px)',
        (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      final h = tester.getSize(_storeCard).height;
      // ignore: avoid_print
      print('store card height: $h');
      expect(h, lessThanOrEqualTo(104));
    });

    testWidgets(
        'name and badge form one group, vertically centred on the '
        'logo', (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      final logo = tester.getRect(
          find.descendant(of: _storeCard, matching: find.byType(Hero)));
      final name = tester.getRect(find.text('مطعم الأصالة'));
      final badge = tester.getRect(find.text(_badgeText));
      final groupCentre = (name.top + badge.bottom) / 2;
      expect(groupCentre, closeTo(logo.center.dy, 4));
      expect(badge.top, greaterThan(name.bottom));
    });

    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
              '$b ${w}dp x$scale: a long name and the badge fit without '
              'overflow', (tester) async {
            await _pumpHome(
              tester,
              brightness: b,
              width: w,
              scale: scale,
              stores: [
                _store(
                  name: 'اسم محل طويل جداً جداً لاختبار التفاف الاسم على سطرين',
                  category: 'فئة طويلة من المنتجات والخدمات المتنوعة',
                  location: 'عنوان طويل جداً في أحد أحياء المدينة البعيدة',
                ),
              ],
            );
            expect(tester.takeException(), isNull);
            expect(find.text(_badgeText), findsOneWidget);
          });
        }
      }
    }
  });

  group('real store logos', () {
    testWidgets(
        'an uploaded logo uses BoxFit.contain, never cropped or '
        'stretched', (tester) async {
      await _pumpHome(tester, stores: [
        _store(logoUrl: 'https://cdn.example/stores/real-logo.png'),
      ]);
      _onlyImageFailures(tester);
      final image = tester.widget<Image>(find.descendant(
        of: _storeCard,
        matching: find.byType(Image),
      ));
      expect(image.fit, BoxFit.contain);
      // The exact URL is passed straight through — never replaced.
      expect((image.image as NetworkImage).url,
          'https://cdn.example/stores/real-logo.png');
    });

    testWidgets(
        'a store with no logo falls back to the branded tile, '
        'never a sample image', (tester) async {
      await _pumpHome(tester, stores: [_store(logoUrl: null)]);
      expect(find.descendant(of: _storeCard, matching: find.byType(Image)),
          findsNothing);
      expect(
          find.descendant(
              of: _storeCard, matching: find.byIcon(Icons.storefront_rounded)),
          findsOneWidget);
    });

    testWidgets('a failed logo load falls back gracefully', (tester) async {
      await _pumpHome(tester, stores: [
        _store(logoUrl: 'https://invalid.example/missing.png'),
      ]);
      _onlyImageFailures(tester);
      expect(
          find.descendant(
              of: _storeCard, matching: find.byIcon(Icons.storefront_rounded)),
          findsOneWidget);
    });
  });

  group('RTL layout', () {
    testWidgets(
        'logo on the right, badge/text block centre, arrow on the '
        'far left', (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      final logo = tester.getCenter(
          find.descendant(of: _storeCard, matching: find.byType(Hero)));
      final name = tester.getCenter(find.text('مطعم الأصالة'));
      final arrow = tester.getCenter(_arrow);
      expect(logo.dx, greaterThan(name.dx));
      expect(name.dx, greaterThan(arrow.dx));
    });

    testWidgets('name and badge sit between the logo and the arrow',
        (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      final logo = tester.getRect(
          find.descendant(of: _storeCard, matching: find.byType(Hero)));
      final arrow = tester.getRect(_arrow);
      for (final s in ['مطعم الأصالة', _badgeText]) {
        final r = tester.getRect(find.text(s));
        expect(r.right, lessThanOrEqualTo(logo.left), reason: s);
        expect(r.left, greaterThanOrEqualTo(arrow.right), reason: s);
      }
      // RTL: name and badge start from the same right-hand edge (the badge
      // text sits inside its pill padding and icon).
      final nameRight = tester.getRect(find.text('مطعم الأصالة')).right;
      final pillRight = tester
          .getRect(find
              .ancestor(
                  of: find.text(_badgeText),
                  matching: find.byType(DecoratedBox))
              .first)
          .right;
      expect(pillRight, closeTo(nameRight, 1));
    });
  });

  group('navigation and Hero', () {
    testWidgets(
        'tapping anywhere on the card opens StoreDetailsPage for '
        'the correct store', (tester) async {
      await _pumpHome(tester, stores: [
        _store(id: 'x', name: 'أول'),
        _store(id: 'y', name: 'ثاني'),
      ]);
      await tester.tap(find.text('ثاني'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      _onlyImageFailures(tester);
      final details =
          tester.widget<StoreDetailsPage>(find.byType(StoreDetailsPage));
      expect(details.store.id, 'y');
      expect(find.text('ثاني'), findsOneWidget);
    });

    testWidgets(
        'the store-logo Hero flies from the card to the details '
        'page and back', (tester) async {
      await _pumpHome(tester, stores: [_store()], width: 412, height: 1800);
      final heroTag = tester
          .widgetList<Hero>(
              find.descendant(of: _storeCard, matching: find.byType(Hero)))
          .single
          .tag;
      expect(heroTag, 'store-logo-s1');
      await tester.tap(find.text('مطعم الأصالة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // mid-flight
      expect(find.byType(Hero), findsWidgets);
      await tester.pump(const Duration(milliseconds: 900));
      _onlyImageFailures(tester);
      expect(find.byType(StoreDetailsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      _onlyImageFailures(tester);
      expect(find.byType(StoreDetailsPage), findsNothing);
      expect(find.text('مطعم الأصالة'), findsOneWidget);
    });
  });

  group('accessibility', () {
    testWidgets('the card reads as one tappable item with its real data',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpHome(tester, stores: [_store()]);
      final node = tester.getSemantics(find.text('مطعم الأصالة'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, contains('مطعم الأصالة'));
      handle.dispose();
    });

    testWidgets('the decorative arrow is structurally excluded from semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpHome(tester, stores: [_store()]);
      expect(
        find.descendant(of: _arrow, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      handle.dispose();
    });
  });

  group('press animation', () {
    testWidgets('a press scales the card down slightly; release restores it',
        (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      AnimatedScale scaleOf() => tester.widget<AnimatedScale>(find.descendant(
          of: _storeCard, matching: find.byType(AnimatedScale)));
      expect(scaleOf().scale, 1);
      final gesture = await tester
          .startGesture(tester.getCenter(find.text('مطعم الأصالة')));
      await tester.pump(const Duration(milliseconds: 150));
      final pressedScale = scaleOf().scale;
      expect(pressedScale, lessThan(1));
      // Subtle, not an exaggerated squash.
      expect(pressedScale, greaterThan(0.9));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf().scale, 1);
    });

    testWidgets('a cancelled press (drag away) restores the scale',
        (tester) async {
      await _pumpHome(tester, stores: [_store()]);
      AnimatedScale scaleOf() => tester.widget<AnimatedScale>(find.descendant(
          of: _storeCard, matching: find.byType(AnimatedScale)));
      final gesture = await tester
          .startGesture(tester.getCenter(find.text('مطعم الأصالة')));
      await tester.pump(const Duration(milliseconds: 150));
      expect(scaleOf().scale, lessThan(1));
      await gesture.moveBy(const Offset(0, 400));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(scaleOf().scale, 1);
    });

    testWidgets('reduced motion: the card never scales on press',
        (tester) async {
      _reduceMotion(tester);
      await _pumpHome(tester, stores: [_store()]);
      final gesture = await tester
          .startGesture(tester.getCenter(find.text('مطعم الأصالة')));
      await tester.pump(const Duration(milliseconds: 150));
      final scale = tester
          .widget<AnimatedScale>(find.descendant(
              of: _storeCard, matching: find.byType(AnimatedScale)))
          .scale;
      expect(scale, 1);
      expect(
        find.descendant(
            of: _storeCard,
            matching: find.byType(TweenAnimationBuilder<double>)),
        findsNothing,
      );
      await gesture.up();
      await tester.pump();
    });
  });

  group('loading behaviour is unchanged', () {
    testWidgets('empty stores still show the existing empty state',
        (tester) async {
      await _pumpHome(tester, stores: const []);
      expect(_storeCard, findsNothing);
      expect(find.text('لا توجد محلات متاحة حالياً'), findsOneWidget);
    });

    testWidgets(
        'inactive stores are still filtered out before reaching '
        'the card list', (tester) async {
      await _pumpHome(tester, stores: [
        _store(id: 'active').copyWith(isActive: true),
        _store(id: 'hidden').copyWith(isActive: false),
      ]);
      expect(_storeCard, findsOneWidget);
    });
  });

  group('realistic long Arabic values', () {
    const longName = 'مطعم ومشويات بيت الشام الأصيل للمأكولات الشرقية';
    const longCategory = 'مطاعم ومأكولات شرقية ومشاوي على الفحم';
    const longLocation = 'الموصل - الجانب الأيسر - حي الزهور قرب دوار الساعة';
    final realistic = _store(
      name: longName,
      category: longCategory,
      location: longLocation,
      logoUrl: null,
    );

    Rect rectOf(WidgetTester tester, String text) =>
        tester.getRect(find.text(text));

    void expectNoCollisions(WidgetTester tester) {
      final rects = [
        rectOf(tester, longName),
        rectOf(tester, _badgeText),
      ];
      // Top-to-bottom order, no vertical overlap between lines.
      for (var i = 0; i < rects.length - 1; i++) {
        expect(rects[i].bottom, lessThanOrEqualTo(rects[i + 1].top + .5),
            reason: 'line $i collides with line ${i + 1}');
      }
      // Everything stays inside the card.
      final card = tester.getRect(_storeCard);
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(card.left));
        expect(r.right, lessThanOrEqualTo(card.right));
      }
    }

    for (final b in Brightness.values) {
      for (final (w, scale) in [(320.0, 2.0), (320.0, 1.3), (360.0, 1.0)]) {
        testWidgets('$b ${w}dp x$scale: no overflow and no colliding lines',
            (tester) async {
          await _pumpHome(tester,
              stores: [realistic], brightness: b, width: w, scale: scale);
          expect(tester.takeException(), isNull);
          expectNoCollisions(tester);
        });
      }
    }

    testWidgets('long category and location never appear on the card',
        (tester) async {
      await _pumpHome(tester, stores: [realistic], width: 320, scale: 2);
      expect(find.text(longCategory), findsNothing);
      expect(find.text(longLocation), findsNothing);
      expect(find.text(longName), findsOneWidget);
    });

    testWidgets('360dp x1: side-by-side — logo right of the text',
        (tester) async {
      await _pumpHome(tester, stores: [realistic], width: 360);
      final logo = tester.getRect(
          find.descendant(of: _storeCard, matching: find.byType(Hero)));
      final name = rectOf(tester, longName);
      expect(logo.left, greaterThanOrEqualTo(name.right));
      expect(name.top, lessThan(logo.bottom));
    });

    testWidgets('320dp x2: stacks — logo and arrow on top, text full width',
        (tester) async {
      await _pumpHome(tester, stores: [realistic], width: 320, scale: 2);
      final logo = tester.getRect(
          find.descendant(of: _storeCard, matching: find.byType(Hero)));
      final arrow = tester.getRect(_arrow);
      final name = rectOf(tester, longName);
      expect(name.top, greaterThanOrEqualTo(logo.bottom));
      expect(logo.center.dx, greaterThan(arrow.center.dx)); // RTL
      // The name now uses most of the card's width.
      final card = tester.getRect(_storeCard);
      expect(rectOf(tester, longName).width, greaterThan(card.width * .5));
    });
  });

  group('badge legibility', () {
    testWidgets('exact wording, never truncated, readable size and weight',
        (tester) async {
      await _pumpHome(tester, stores: [_store()], width: 320, scale: 2);
      final text = tester.widget<Text>(find.text(_badgeText));
      expect(text.data, 'شريك حصري لدى يلا كاش');
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.style?.fontSize, greaterThanOrEqualTo(12));
      expect(text.style?.fontWeight, FontWeight.w800);
      expect(
          find.descendant(
              of: _storeCard,
              matching: find.byIcon(Icons.workspace_premium_rounded)),
          findsOneWidget);
      // Fully inside the card even at 320dp with 2x text.
      final card = tester.getRect(_storeCard);
      final badge = tester.getRect(find.text(_badgeText));
      expect(badge.left, greaterThanOrEqualTo(card.left));
      expect(badge.right, lessThanOrEqualTo(card.right));
    });

    for (final b in Brightness.values) {
      testWidgets('$b: gold ink keeps >= 4.5:1 on the badge', (tester) async {
        await _pumpHome(tester, stores: [_store()], brightness: b);
        final ink = tester.widget<Text>(find.text(_badgeText)).style!.color!;
        final pill = (tester
                .widget<DecoratedBox>(find
                    .ancestor(
                        of: find.text(_badgeText),
                        matching: find.byType(DecoratedBox))
                    .first)
                .decoration as BoxDecoration)
            .color!;
        final ctx = tester.element(find.text(_badgeText));
        final surface = Theme.of(ctx).cardTheme.color!;
        final bg = Color.alphaBlend(pill, surface);
        final la = ink.computeLuminance(), lb = bg.computeLuminance();
        final ratio = ((la > lb ? la : lb) + .05) / ((la > lb ? lb : la) + .05);
        // ignore: avoid_print
        print('$b badge contrast ${ratio.toStringAsFixed(2)}');
        expect(ratio, greaterThanOrEqualTo(4.5));
      });
    }
  });
}
