import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Banner;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';

/// Regression tests for the home banner carousel's rounded clipping.
///
/// Bug: each page was rounded on its own, so while the carousel slid between
/// ads, the page pieces meeting the viewport edge showed square corners.
/// The whole carousel viewport must stay clipped to one rounded rectangle on
/// every frame.

Banner _banner(String id, String url) => Banner(
      id: id,
      title: 'ad $id',
      imageUrl: url,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpHome(
  WidgetTester tester,
  List<Banner> banners, {
  Brightness brightness = Brightness.light,
}) async {
  _viewport(tester);
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
        body: CustomerHomePage(
          cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
          state: CustomerAppState(
            customer: store.currentCustomer,
            points: const PointsSummary(
              pointsBalance: 10,
              heldPoints: 0,
              availablePoints: 10,
            ),
            banners: banners,
          ),
          customer: store.currentCustomer!,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

final _pageView = find.byType(PageView);

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: _pageView, matching: find.byType(Scrollable)),
    )
    .position;

/// Image of the nearest repaint boundary ABOVE the carousel box, i.e. the
/// carousel exactly as it is painted, clip included. Pixels outside the
/// clip stay transparent.
Future<({ui.Image image, ByteData bytes})> _captureCarousel(
  WidgetTester tester,
) async {
  final box = find.ancestor(of: _pageView, matching: find.byType(AspectRatio));
  RenderObject? node = tester.renderObject(box.first);
  while (node != null && node is! RenderRepaintBoundary) {
    node = node.parent;
  }
  final boundary = node! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(() => image.toByteData()))!;
  return (image: image, bytes: bytes);
}

int _alpha(({ui.Image image, ByteData bytes}) c, int x, int y) =>
    c.bytes.getUint8((y * c.image.width + x) * 4 + 3);

/// Pixels just inside each corner of the carousel box that lie OUTSIDE a
/// 22px rounded rectangle, so they must be transparent.
void _expectRoundedCorners(({ui.Image image, ByteData bytes}) c, String when) {
  final w = c.image.width;
  final h = c.image.height;
  for (final (x, y) in [
    (3, 1),
    (w - 4, 1),
    (3, h - 2),
    (w - 4, h - 2),
  ]) {
    expect(_alpha(c, x, y), 0, reason: '$when: corner ($x,$y) must be clipped');
  }
  expect(_alpha(c, w ~/ 2, h ~/ 2), 255, reason: '$when: centre is painted');
}

void main() {
  for (final b in Brightness.values) {
    for (final (label, url) in [
      ('no image', ''),
      ('failed image', 'https://invalid.example/ad.png'),
    ]) {
      testWidgets('$b / $label: corners stay rounded at rest and mid-slide',
          (tester) async {
        await _pumpHome(
          tester,
          [_banner('a', url), _banner('b', url), _banner('c', url)],
          brightness: b,
        );
        // Failed network images throw in tests; nothing else may.
        Object? e = tester.takeException();
        while (e != null) {
          expect(e, isA<NetworkImageLoadException>());
          e = tester.takeException();
        }

        _expectRoundedCorners(await _captureCarousel(tester), 'at rest');

        // Rotation fires at 2s; mid-transition is ~175ms into the 350ms slide.
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 175));
        final pixels = _position(tester).pixels;
        final width = _position(tester).viewportDimension;
        expect(pixels, inExclusiveRange(width * .15, width * .85),
            reason: 'must be genuinely mid-slide');
        _expectRoundedCorners(await _captureCarousel(tester), 'mid-slide');

        // Sample several frames across the whole transition.
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 30));
          _expectRoundedCorners(
              await _captureCarousel(tester), 'frame ${i + 1}');
        }

        await tester.pumpAndSettle(const Duration(milliseconds: 50));
        _expectRoundedCorners(await _captureCarousel(tester), 'settled');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('one rounded clip wraps the whole PageView, none per page',
      (tester) async {
    await _pumpHome(tester, [_banner('a', ''), _banner('b', '')]);
    final outer =
        find.ancestor(of: _pageView, matching: find.byType(ClipRRect));
    expect(outer, findsOneWidget);
    expect(
      tester.widget<ClipRRect>(outer).borderRadius,
      BorderRadius.circular(22),
    );
    expect(tester.widget<ClipRRect>(outer).clipBehavior, Clip.antiAlias);
    expect(
      find.descendant(of: _pageView, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'rotation timing is unchanged: still at rest at 1.9s, moves at 2s',
      (tester) async {
    await _pumpHome(tester, [_banner('a', ''), _banner('b', '')]);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(_position(tester).pixels, 0);
    await tester.pump(const Duration(milliseconds: 150)); // timer at 2s + frame
    await tester.pump(const Duration(milliseconds: 100));
    expect(_position(tester).pixels, greaterThan(0));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(
      _position(tester).pixels,
      closeTo(_position(tester).viewportDimension, 1),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual swipe still changes the page', (tester) async {
    await _pumpHome(tester, [_banner('a', ''), _banner('b', '')]);
    // RTL: the next ad is reached by swiping to the right.
    await tester.drag(_pageView, const Offset(300, 0));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(_position(tester).pixels, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion: ad changes instantly, no sliding frames',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpHome(tester, [_banner('a', ''), _banner('b', '')]);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 16));
    final width = _position(tester).viewportDimension;
    // Exactly one full page, never an in-between offset.
    expect(_position(tester).pixels, closeTo(width, 1));
    _expectRoundedCorners(await _captureCarousel(tester), 'after jump');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320dp: rounded at rest and mid-slide', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = YallaCashStore.demo()..loginDemoCustomer();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildCustomerTheme(Brightness.light),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(
          body: CustomerHomePage(
            cubit: CustomerAppCubit(InMemoryYallaCashRepository(store)),
            state: CustomerAppState(
              customer: store.currentCustomer,
              points: const PointsSummary(
                  pointsBalance: 1, heldPoints: 0, availablePoints: 1),
              banners: [_banner('a', ''), _banner('b', '')],
            ),
            customer: store.currentCustomer!,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 175));
    _expectRoundedCorners(await _captureCarousel(tester), '320dp mid-slide');
    await tester.pumpWidget(const SizedBox());
  });
}
