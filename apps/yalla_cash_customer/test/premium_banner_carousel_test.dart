import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Banner;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';

import 'support/fake_image_http.dart';

/// Regression tests for the Home banner carousel: rotation must never show a
/// blank, faded-in or half-loaded frame. The next banner is precached while
/// the current one stays on screen, then crossfades in over 250ms; slow
/// downloads are waited for and failed ones are skipped.

const _a = 'https://cdn.example/banners/a.png';
const _b = 'https://cdn.example/banners/b.png';
const _c = 'https://cdn.example/banners/c.png';

/// Serves banner images, counting requests, and can hold a URL's response
/// until [release]d (a slow connection). A URL without bytes answers 404.
class _Server extends FakeImageHttpClient {
  _Server(super.images);

  final requests = <String, int>{};
  final _gates = <String, Completer<void>>{};

  void hold(String url) => _gates[url] = Completer<void>();
  void release(String url) => _gates[url]?.complete();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final key = url.toString();
    requests[key] = (requests[key] ?? 0) + 1;
    await _gates[key]?.future;
    return super.getUrl(url);
  }
}

Banner _banner(String id, String url, {String? target}) => Banner(
      id: id,
      title: 'ad $id',
      imageUrl: url,
      targetUrl: target,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Future<Uint8List> _png(WidgetTester tester, Color color) async =>
    (await tester.runAsync(() => drawPng(1200, 500, (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = color);
        })))!;

/// Real time for image I/O and decoding, interleaved with frames.
Future<void> _load(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final _pageView = find.byType(PageView);
final _crossfade = find.byKey(const Key('banner-crossfade'));

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
        find.descendant(of: _pageView, matching: find.byType(Scrollable)))
    .position;

/// Which page is showing: the page index at rest.
int _shownPage(WidgetTester tester) {
  final p = _position(tester);
  return (p.pixels / p.viewportDimension).round();
}

/// The page's picture is really painted: its image is decoded, mounted, and
/// not faded out by anything above it. A blank or half-loaded page fails
/// here (placeholder, nothing mounted, or an opacity below 1).
void _expectPagePainted(WidgetTester tester, String when) {
  final raw = find.descendant(of: _pageView, matching: find.byType(RawImage));
  expect(raw, findsOneWidget, reason: '$when: the shown page has its image');
  expect(tester.widget<RawImage>(raw).image, isNotNull,
      reason: '$when: the image is decoded');
  for (final o in find
      .ancestor(of: raw, matching: find.byType(Opacity))
      .evaluate()
      .map((e) => e.widget as Opacity)) {
    expect(o.opacity, 1, reason: '$when: the page is not faded');
  }
}

int _dotsIndex(WidgetTester tester) =>
    tester.widget<YcPageDots>(find.byType(YcPageDots)).index;

Future<_Server> _pumpHome(
  WidgetTester tester,
  List<Banner> banners, {
  Map<String, Color> images = const {},
  Set<String> held = const {},
  double width = 412,
  Brightness brightness = Brightness.light,
}) async {
  PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();
  final bytes = <String, Uint8List>{
    for (final e in images.entries) e.key: await _png(tester, e.value),
  };
  final server = _Server(bytes);
  for (final url in held) {
    server.hold(url);
  }
  painting.debugNetworkImageHttpClientProvider = () => server;
  tester.view.physicalSize = Size(width * 2, 1800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final cubit = CustomerAppCubit(InMemoryYallaCashRepository(store));
  addTearDown(cubit.close);
  await tester.pumpWidget(MaterialApp(
    theme: customerLightTheme,
    darkTheme: customerDarkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(
      body: CustomerHomePage(
        cubit: cubit,
        state: CustomerAppState(
          customer: store.currentCustomer,
          points: const PointsSummary(
              pointsBalance: 1, heldPoints: 0, availablePoints: 1),
          banners: banners,
        ),
        customer: store.currentCustomer!,
      ),
    ),
  ));
  // The first banner loads and finishes its own fade-in (about 0.8s).
  await _load(tester);
  return server;
}

/// Runs the 5s rotation tick (the carousel started about 0.8s ago).
Future<void> _tick(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 4300));
}

/// Steps frames until [done] or 60 frames, checking the no-blank-frame
/// invariant on every frame of the change.
Future<List<double>> _watchChange(
  WidgetTester tester, {
  required int toPage,
}) async {
  final opacities = <double>[];
  var switched = false;
  for (var i = 0; i < 60; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 16));
    final nowOn = _shownPage(tester);
    if (!switched && nowOn == toPage) {
      switched = true;
      // The very frame the page changes: the new image is already painted,
      // and the outgoing ad is on top of it (so nothing is ever blank).
      expect(_crossfade, findsOneWidget,
          reason: 'the outgoing banner fades out on top');
    }
    if (switched) {
      _expectPagePainted(tester, 'frame $i during the change');
      if (_crossfade.evaluate().isNotEmpty) {
        opacities.add(tester.widget<FadeTransition>(_crossfade).opacity.value);
      } else {
        return opacities;
      }
    } else {
      expect(nowOn, isNot(toPage));
      _expectPagePainted(tester, 'frame $i before the change');
    }
  }
  fail('the banner never changed to page $toPage');
}

/// A widget test that always restores the global image HTTP client before
/// the test body ends (the framework checks this before `tearDown` runs).
void _testBanner(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        painting.debugNetworkImageHttpClientProvider = null;
      }
    });

void main() {
  group('precache provider', () {
    test('is exactly the provider Image.network(cacheWidth) builds', () async {
      const config = ImageConfiguration(devicePixelRatio: 2);
      final precached =
          await YcNetworkImage.provider(_a, cacheWidth: 824).obtainKey(config);
      final shown =
          await Image.network(_a, cacheWidth: 824).image.obtainKey(config);
      // Same cache key: a precached image is the very one the page paints.
      expect(precached, shown);
    });
  });

  group('slow connection', () {
    _testBanner(
        'the current banner stays until the next is fully decoded, then '
        'crossfades in with no blank frame', (tester) async {
      final server = await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b), _banner('c', _c)],
        images: {
          _a: const Color(0xFF1B4965),
          _b: const Color(0xFFBF4342),
          _c: const Color(0xFF2A9D8F),
        },
        held: {_b},
      );
      _expectPagePainted(tester, 'first banner');
      expect(server.requests[_a], 1);

      await _tick(tester);
      await tester.pump();
      // The next banner is being fetched (held) while the current stays.
      expect(server.requests[_b], 1, reason: 'next banner precached once');
      expect(_shownPage(tester), 0);
      expect(_crossfade, findsNothing);
      _expectPagePainted(tester, 'while the next image is still loading');

      // Two more ticks pass on the slow connection: still waiting, never a
      // second request, the current banner never goes blank.
      await tester.pump(const Duration(seconds: 12));
      expect(server.requests[_b], 1,
          reason: 'a slow image is not re-requested');
      expect(_shownPage(tester), 0);
      expect(_dotsIndex(tester), 0);
      _expectPagePainted(tester, 'after 12s on a slow connection');

      // The connection delivers the image: crossfade, frame by frame.
      server.release(_b);
      final opacities = await _watchChange(tester, toPage: 1);
      expect(_dotsIndex(tester), 1);
      expect(opacities, isNotEmpty);
      expect(opacities.first, closeTo(1, .01),
          reason: 'the outgoing banner starts fully visible');
      for (var i = 1; i < opacities.length; i++) {
        expect(opacities[i], lessThanOrEqualTo(opacities[i - 1]),
            reason: 'the crossfade only fades out');
      }
      expect(_crossfade, findsNothing, reason: 'the fade overlay is removed');
      _expectPagePainted(tester, 'after the crossfade');
    });

    _testBanner('the crossfade takes 250ms', (tester) async {
      await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b)],
        images: {_a: const Color(0xFF1B4965), _b: const Color(0xFFBF4342)},
      );
      await _tick(tester);
      // Let the precache finish and the change start.
      var started = false;
      for (var i = 0; i < 40 && !started; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        started = _crossfade.evaluate().isNotEmpty;
      }
      expect(started, isTrue);
      await tester.pump(const Duration(milliseconds: 240));
      expect(_crossfade, findsOneWidget, reason: 'still fading at 240ms');
      await tester.pump(const Duration(milliseconds: 20));
      expect(_crossfade, findsNothing, reason: 'done by 260ms');
    });

    _testBanner('rotation keeps its 5-second interval', (tester) async {
      await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b)],
        images: {_a: const Color(0xFF1B4965), _b: const Color(0xFFBF4342)},
      );
      await tester.pump(const Duration(milliseconds: 4000)); // 4.8s in
      expect(_shownPage(tester), 0);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 400)); // past 5s
      await _load(tester, rounds: 4);
      expect(_shownPage(tester), 1);
    });
  });

  group('failed downloads', () {
    _testBanner(
        'a banner that fails to load is skipped and not hammered; the '
        'rotation goes on without a blank frame', (tester) async {
      // b is not served (404).
      final server = await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b), _banner('c', _c)],
        images: {_a: const Color(0xFF1B4965), _c: const Color(0xFF2A9D8F)},
      );
      await _tick(tester);
      // b fails, so the rotation skips straight to c, with a crossfade.
      await _watchChange(tester, toPage: 2);
      expect(server.requests[_b], 1);
      expect(_dotsIndex(tester), 2);

      // Next tick: c -> a (b is not next). Then a -> c: b is skipped again,
      // without asking the network a second time.
      await tester.pump(const Duration(seconds: 5));
      await _watchChange(tester, toPage: 0);
      await tester.pump(const Duration(seconds: 5));
      await _watchChange(tester, toPage: 2);
      expect(server.requests[_b], 1,
          reason: 'a recently failed banner is not requested every tick');
    });

    _testBanner('when no other banner can load, the current one stays',
        (tester) async {
      // Only a is served; b and c fail.
      final server = await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b), _banner('c', _c)],
        images: {_a: const Color(0xFF1B4965)},
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 5));
        await _load(tester, rounds: 3);
        expect(_shownPage(tester), 0);
        expect(_crossfade, findsNothing);
        _expectPagePainted(tester, 'tick $i with nothing else to show');
      }
      expect(server.requests[_b], 1);
      expect(server.requests[_c], 1);
      expect(tester.takeException(), isNull,
          reason: 'failed precaches are handled, never thrown');
    });

    _testBanner('a failed banner is still reachable by swiping, with its icon',
        (tester) async {
      await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b)],
        images: {_a: const Color(0xFF1B4965)},
      );
      // RTL: the next ad is reached by swiping to the right.
      await tester.drag(_pageView, const Offset(300, 0));
      await _load(tester, rounds: 6);
      expect(_shownPage(tester), 1);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      // The image failure itself is reported by the page's own image.
      Object? e = tester.takeException();
      while (e != null) {
        expect(e, isA<NetworkImageLoadException>());
        e = tester.takeException();
      }
    });
  });

  group('manual swiping, reduced motion, links', () {
    _testBanner('swiping works, also in the middle of a crossfade',
        (tester) async {
      await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b), _banner('c', _c)],
        images: {
          _a: const Color(0xFF1B4965),
          _b: const Color(0xFFBF4342),
          _c: const Color(0xFF2A9D8F),
        },
      );
      await _tick(tester);
      var started = false;
      for (var i = 0; i < 40 && !started; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        started = _crossfade.evaluate().isNotEmpty;
      }
      expect(started, isTrue);
      expect(_shownPage(tester), 1);
      // Grab and swipe while the outgoing copy is still fading.
      await tester.drag(_pageView, const Offset(300, 0));
      await _load(tester, rounds: 4);
      expect(_crossfade, findsNothing,
          reason: 'a swipe takes over: no overlay over the dragged page');
      expect(_shownPage(tester), 2);
      expect(_dotsIndex(tester), 2);
    });

    _testBanner('reduced motion: the ad changes at once, without a fade',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b)],
        images: {_a: const Color(0xFF1B4965), _b: const Color(0xFFBF4342)},
      );
      await _tick(tester);
      var switched = false;
      for (var i = 0; i < 40 && !switched; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 16));
        // Never a fade overlay, never a half-way state.
        expect(_crossfade, findsNothing);
        switched = _shownPage(tester) == 1;
      }
      expect(switched, isTrue);
      _expectPagePainted(tester, 'right after the instant change');
      expect(_position(tester).pixels,
          closeTo(_position(tester).viewportDimension, 1));
    });

    _testBanner('keeps the 2.4:1 ratio and the rounded clip', (tester) async {
      await _pumpHome(
        tester,
        [_banner('a', _a), _banner('b', _b)],
        images: {_a: const Color(0xFF1B4965), _b: const Color(0xFFBF4342)},
        width: 320,
      );
      final box = tester.getSize(find
          .ancestor(of: _pageView, matching: find.byType(AspectRatio))
          .first);
      expect(box.width / box.height, closeTo(1200 / 500, .01));
      final clip =
          find.ancestor(of: _pageView, matching: find.byType(ClipRRect));
      expect(clip, findsOneWidget);
      expect(tester.widget<ClipRRect>(clip).borderRadius,
          BorderRadius.circular(22));
    });
  });
}
