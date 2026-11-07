import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_customer/src/ui/logo_trim.dart';

import 'support/fake_image_http.dart';

/// Builds an RGBA bitmap filled with [bg], then lets [paint] set pixels.
Uint8List _bitmap(int w, int h, List<int> bg,
    [void Function(void Function(int x, int y, List<int> c) set)? paint]) {
  final data = Uint8List(w * h * 4);
  void set(int x, int y, List<int> c) {
    final i = (y * w + x) * 4;
    for (var k = 0; k < 4; k++) {
      data[i + k] = c[k];
    }
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      set(x, y, bg);
    }
  }
  paint?.call(set);
  return data;
}

const _white = [255, 255, 255, 255];
const _clear = [0, 0, 0, 0];
const _red = [214, 40, 40, 255];

void main() {
  group('logoContentRect (pure detection)', () {
    test('small mark on a white canvas: returns its padded box', () {
      final rgba = _bitmap(100, 100, _white, (set) {
        for (var y = 40; y < 60; y++) {
          for (var x = 30; x < 70; x++) {
            set(x, y, _red);
          }
        }
      });
      final r = logoContentRect(rgba, 100, 100)!;
      // Content 30..70 × 40..60, plus the 6% safety buffer on every side.
      expect(r.left, closeTo(.24, .001));
      expect(r.right, closeTo(.76, .001));
      expect(r.top, closeTo(.34, .001));
      expect(r.bottom, closeTo(.66, .001));
    });

    test('transparent background is trimmed the same way', () {
      final rgba = _bitmap(100, 100, _clear, (set) {
        for (var y = 45; y < 55; y++) {
          for (var x = 45; x < 55; x++) {
            set(x, y, _red);
          }
        }
      });
      expect(logoContentRect(rgba, 100, 100), isNotNull);
    });

    test('a logo that already fills its frame is left alone', () {
      final rgba = _bitmap(100, 100, _white, (set) {
        for (var y = 5; y < 95; y++) {
          for (var x = 5; x < 95; x++) {
            set(x, y, _red);
          }
        }
      });
      expect(logoContentRect(rgba, 100, 100), isNull);
    });

    test('non-uniform corners (no single background): never trimmed', () {
      final rgba = _bitmap(100, 100, _white, (set) {
        set(99, 99, [0, 0, 0, 255]); // one dark corner
        for (var y = 45; y < 55; y++) {
          for (var x = 45; x < 55; x++) {
            set(x, y, _red);
          }
        }
      });
      expect(logoContentRect(rgba, 100, 100), isNull);
    });

    test('faint artwork counts as content, so it is never cut off', () {
      final rgba = _bitmap(100, 100, _white, (set) {
        // Main mark in the centre…
        for (var y = 45; y < 55; y++) {
          for (var x = 45; x < 55; x++) {
            set(x, y, _red);
          }
        }
        // …and a pale tagline far below it (20 levels off white).
        for (var x = 40; x < 60; x++) {
          set(x, 85, [235, 235, 235, 255]);
        }
      });
      final r = logoContentRect(rgba, 100, 100)!;
      expect(r.bottom, greaterThanOrEqualTo(.86));
    });

    test('a blank image is left alone', () {
      expect(logoContentRect(_bitmap(50, 50, _white), 50, 50), isNull);
    });
  });

  group('logoZoomTransform', () {
    const box = Size(100, 100);

    test('no transform when there is nothing to trim', () {
      expect(
        logoZoomTransform(
          const LogoContentBounds(content: LogoContentBounds.full, aspect: 1),
          box,
        ),
        isNull,
      );
    });

    test('zoom keeps the whole content box inside the plate', () {
      const bounds = LogoContentBounds(
        content: Rect.fromLTRB(.3, .4, .7, .6),
        aspect: 1,
      );
      final m = logoZoomTransform(bounds, box)!;
      final topLeft = MatrixUtils.transformPoint(m, const Offset(30, 40));
      final bottomRight = MatrixUtils.transformPoint(m, const Offset(70, 60));
      expect(topLeft.dx, greaterThanOrEqualTo(0));
      expect(topLeft.dy, greaterThanOrEqualTo(0));
      expect(bottomRight.dx, lessThanOrEqualTo(100));
      expect(bottomRight.dy, lessThanOrEqualTo(100));
      // Centred.
      final centre = MatrixUtils.transformPoint(m, const Offset(50, 50));
      expect(centre.dx, closeTo(50, .01));
      expect(centre.dy, closeTo(50, .01));
    });

    test('zoom is capped at 2.5x for tiny marks', () {
      const bounds = LogoContentBounds(
        content: Rect.fromLTRB(.48, .48, .52, .52),
        aspect: 1,
      );
      final m = logoZoomTransform(bounds, box)!;
      expect(m.getMaxScaleOnAxis(), closeTo(2.5, .001));
    });
  });

  group('WhitespaceTrimmedLogo (real decode)', () {
    late Map<String, Uint8List> images;

    setUp(WhitespaceTrimmedLogo.clearCache);

    Future<void> pump(WidgetTester tester, String url) async {
      images = (await tester.runAsync(() async => {
            'https://logo.test/whitespace.png': await drawPng(400, 400, (c, s) {
              c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
              c.drawRect(
                  Rect.fromCenter(
                      center: s.center(Offset.zero), width: 110, height: 50),
                  Paint()..color = const Color(0xFFD62828));
            }),
            'https://logo.test/full.png': await drawPng(400, 400, (c, s) {
              c.drawRect(
                  Offset.zero & s, Paint()..color = const Color(0xFF1B4965));
            }),
          }))!;
      painting.debugNetworkImageHttpClientProvider =
          () => FakeImageHttpClient(images);
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 80,
            child: WhitespaceTrimmedLogo(url: url),
          ),
        ),
      ));
      // Let the image download, decode and be measured for real.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      painting.debugNetworkImageHttpClientProvider = null;
    }

    testWidgets('a whitespace-heavy logo is zoomed to its content',
        (tester) async {
      await pump(tester, 'https://logo.test/whitespace.png');
      final transform = find.descendant(
          of: find.byType(WhitespaceTrimmedLogo),
          matching: find.byType(Transform));
      expect(transform, findsOneWidget);
      final scale =
          tester.widget<Transform>(transform).transform.getMaxScaleOnAxis();
      expect(scale, greaterThan(1.5));
      // The image itself is untouched: same URL, BoxFit.contain.
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url,
          'https://logo.test/whitespace.png');
      expect(image.fit, BoxFit.contain);
      await done(tester);
    });

    testWidgets('a logo that fills its frame is shown exactly as before',
        (tester) async {
      await pump(tester, 'https://logo.test/full.png');
      expect(
        find.descendant(
            of: find.byType(WhitespaceTrimmedLogo),
            matching: find.byType(Transform)),
        findsNothing,
      );
      await done(tester);
    });

    testWidgets('a failed download falls back to the error builder',
        (tester) async {
      images = {};
      painting.debugNetworkImageHttpClientProvider =
          () => FakeImageHttpClient(images);
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 80,
            child: WhitespaceTrimmedLogo(
              url: 'https://logo.test/missing.png',
              errorBuilder: (_, __, ___) => const Text('fallback'),
            ),
          ),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
      expect(find.text('fallback'), findsOneWidget);
      await done(tester);
    });
  });
}
