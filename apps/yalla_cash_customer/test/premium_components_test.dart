import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/logo_plate.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

/// Hosts [child] the way the customer app does: customer theme + RTL.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 412,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      darkTheme: buildCustomerTheme(Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(YcSpace.gutter),
          children: [child],
        ),
      ),
    ),
  );
}

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Left-to-right box of the code unit at [index] in a laid-out paragraph.
double _glyphLeft(String text, int index) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 10)),
    textDirection: TextDirection.rtl,
  )..layout();
  final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + 1));
  painter.dispose();
  return boxes.first.left;
}

Widget _gallery() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const YcBalanceHero(
          label: 'رصيد النقاط',
          value: 987654321,
          unit: 'نقطة',
          stats: [
            YcHeroStat(
                icon: Icons.check_circle_outline_rounded,
                label: 'المتاح',
                value: 864197532),
            YcHeroStat(
                icon: Icons.schedule_rounded,
                label: 'قيد المعالجة',
                value: 123456789),
          ],
        ),
        const SizedBox(height: 8),
        const YcBalanceHero(
            label: 'رصيدك المتاح', value: 1200, unit: 'نقطة', compact: true),
        const SizedBox(height: 8),
        const Row(children: [
          Expanded(child: Text('عملية')),
          Flexible(child: YcAmount(1234567, unit: 'نقطة', signed: true)),
        ]),
        const YcAmount(987654321, unit: 'ل.س', scaleDown: true),
        const Wrap(spacing: 8, runSpacing: 8, children: [
          YcChip(label: 'مطاعم ومقاهي ومأكولات شرقية وغربية'),
          YcChip.discount('خصم 50% على كل المشروبات الساخنة والباردة'),
        ]),
        const YcInlineBanner(
          message: 'تعذر تحديث العروض. نعرض آخر نسخة محفوظة لديك الآن.',
          tone: YcTone.danger,
          actionLabel: 'إعادة المحاولة',
          onAction: _noop,
        ),
        YcSegmentedTabs(
          labels: const ['العمليات', 'سحب الكاش', 'المنتجات'],
          selectedIndex: 1,
          onChanged: (_) {},
        ),
        const YcErrorState(title: 'تعذر تحميل السجل', onRetry: _noop),
        const YcSkeleton.offer(),
        const YcSkeleton.card(rows: 2),
        const Center(child: YcPageDots(count: 4, index: 2)),
        const Center(child: YcLogoPlate(url: null, size: 72)),
      ],
    );

void _noop() {}

void main() {
  group('theme foundations', () {
    for (final b in Brightness.values) {
      testWidgets('$b: customer font family, real weights, palette',
          (tester) async {
        late BuildContext ctx;
        await _pump(
          tester,
          Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
          brightness: b,
        );
        final theme = Theme.of(ctx);
        final text = theme.textTheme;
        for (final style in [
          text.headlineMedium,
          text.titleMedium,
          text.bodyMedium,
          text.labelLarge,
        ]) {
          expect(style?.fontFamily, customerFontFamily);
          // Only the four shipped Almarai faces are requested.
          expect(
            [
              FontWeight.w300,
              FontWeight.w400,
              FontWeight.w700,
              FontWeight.w800,
            ],
            contains(style?.fontWeight),
          );
        }
        expect(YcType.hero(ctx)?.fontWeight, FontWeight.w800);
        expect(YcType.body(ctx)?.fontWeight, FontWeight.w400);
        expect(theme.extension<YcColors>(), isNotNull);
        expect(theme.extension<YcSurface>(), isNotNull);
        final colors = YcColors.of(ctx);
        final card = YcSurface.of(ctx).card;
        // Body and muted text keep >= 4.5:1 on cards and on the page.
        for (final bg in [card, theme.scaffoldBackgroundColor]) {
          expect(_contrast(colors.ink, bg), greaterThanOrEqualTo(4.5));
          expect(_contrast(colors.inkMuted, bg), greaterThanOrEqualTo(4.5));
        }
        // White hero text keeps >= 4.5:1 on both gradient stops.
        for (final stop in [colors.heroStart, colors.heroEnd]) {
          expect(_contrast(colors.onHero, stop), greaterThanOrEqualTo(4.5));
        }
      });
    }

    test('themes are cached, not rebuilt', () {
      expect(identical(customerLightTheme, customerLightTheme), isTrue);
      expect(customerLightTheme.brightness, Brightness.light);
      expect(customerDarkTheme.brightness, Brightness.dark);
    });
  });

  group('YcAmount', () {
    test('format: exact figure and unit, sign isolated left-to-right', () {
      expect(YcAmount.format(1500, unit: 'نقطة'), '1,500 نقطة');
      expect(YcAmount.format(500, unit: 'ل.س'), '500 ل.س');
      expect(YcAmount.format(12345678), '12,345,678');
      expect(YcAmount.format(120, unit: 'نقطة', signed: true),
          '\u2066+120\u2069 نقطة');
    });

    test('RTL: the plus sign stays in front of (left of) the digits', () {
      final isolated = YcAmount.format(120, unit: 'نقطة', signed: true);
      // index 1 is "+", index 2 is the first digit.
      expect(_glyphLeft(isolated, 1), lessThan(_glyphLeft(isolated, 2)));
      // Without isolation the sign lands on the wrong side ("120+").
      const plain = '+120 نقطة';
      expect(_glyphLeft(plain, 0), greaterThan(_glyphLeft(plain, 1)));
    });

    test('RTL: the unit reads after the number (number on the right)', () {
      final text = YcAmount.format(500, unit: 'ل.س');
      expect(_glyphLeft(text, 0), greaterThan(_glyphLeft(text, 4)));
    });

    testWidgets('one text widget, tabular figures, caller colour',
        (tester) async {
      await _pump(
        tester,
        const YcAmount(1200, unit: 'نقطة', color: Colors.green),
      );
      final text = tester.widget<Text>(find.text('1,200 نقطة'));
      expect(text.style?.color, Colors.green);
      expect(text.style?.fontFeatures, YcType.tabular);
      expect(text.style?.fontWeight, FontWeight.w800);
    });
  });

  group('YcBalanceHero', () {
    testWidgets('shows the real figure and stats, never a false zero',
        (tester) async {
      await _pump(
        tester,
        const YcBalanceHero(
          label: 'رصيد النقاط',
          value: 1500,
          stats: [
            YcHeroStat(icon: Icons.check, label: 'المتاح', value: 1200),
            YcHeroStat(icon: Icons.schedule, label: 'قيد المعالجة', value: 300),
          ],
        ),
      );
      expect(find.text('1,500'), findsOneWidget);
      expect(find.text('1,200'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
      // RTL: the first stat sits to the right of the second.
      expect(tester.getCenter(find.text('المتاح')).dx,
          greaterThan(tester.getCenter(find.text('قيد المعالجة')).dx));
    });

    testWidgets('loading: progress bar, no figure, no stats', (tester) async {
      await _pump(
        tester,
        const YcBalanceHero(
          label: 'رصيد النقاط',
          value: null,
          stats: [YcHeroStat(icon: Icons.check, label: 'المتاح', value: 0)],
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('المتاح'), findsNothing);
    });

    testWidgets('failed: retry instead of a figure', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        YcBalanceHero(
          label: 'رصيدك المتاح',
          value: null,
          failed: true,
          onRetry: () => retried++,
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retried, 1);
    });

    for (final b in Brightness.values) {
      testWidgets('$b: hero gradient is deep navy → brand blue',
          (tester) async {
        await _pump(tester, const YcBalanceHero(label: 'x', value: 1),
            brightness: b);
        final deco = tester
            .widget<DecoratedBox>(find
                .ancestor(
                  of: find.text('x'),
                  matching: find.byWidgetPredicate((w) =>
                      w is DecoratedBox &&
                      w.decoration is BoxDecoration &&
                      (w.decoration as BoxDecoration).gradient != null),
                )
                .first)
            .decoration as BoxDecoration;
        final stops = (deco.gradient! as LinearGradient).colors;
        expect(stops.first.computeLuminance(), lessThan(.05));
        expect(stops.last.b, greaterThan(stops.last.r));
      });
    }
  });

  group('YcNetworkImage', () {
    testWidgets('decodes at the laid-out width times the pixel ratio',
        (tester) async {
      await _pump(
        tester,
        const Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: YcNetworkImage('https://invalid.example/a.png'),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      expect((image.image as ResizeImage).width, 400);
      // Failed loads in tests are network errors only.
      tester.takeException();
    });

    testWidgets('resize: false keeps the plain NetworkImage cache key',
        (tester) async {
      await _pump(
        tester,
        const Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: YcNetworkImage(
              'https://invalid.example/a.png',
              resize: false,
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      // The same provider (and image-cache key) as a plain Image.network, so
      // an image already loaded elsewhere is reused, not downloaded again.
      expect(image.image, isA<NetworkImage>());
      expect(image.image, isNot(isA<ResizeImage>()));
      tester.takeException();
    });
  });

  group('YcSegmentedTabs', () {
    testWidgets('selects by tap, announces the selected segment',
        (tester) async {
      final handle = tester.ensureSemantics();
      var selected = 0;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => YcSegmentedTabs(
            labels: const ['العمليات', 'سحب الكاش', 'المنتجات'],
            selectedIndex: selected,
            onChanged: (i) => setState(() => selected = i),
          ),
        ),
      );
      // RTL: the first segment is the right-most.
      expect(tester.getCenter(find.text('العمليات')).dx,
          greaterThan(tester.getCenter(find.text('المنتجات')).dx));
      await tester.tap(find.text('المنتجات'));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(
        tester.getSemantics(find.text('المنتجات')),
        matchesSemantics(
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          label: 'المنتجات',
        ),
      );
      // Every segment is a comfortable touch target.
      expect(tester.getSize(find.byType(AnimatedContainer).first).height,
          greaterThanOrEqualTo(44));
      handle.dispose();
    });
  });

  group('YcPageDots', () {
    testWidgets('active dot is the wide one; hidden for a single page',
        (tester) async {
      await _pump(tester, const YcPageDots(count: 3, index: 1));
      await tester.pumpAndSettle();
      final widths = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((c) => tester.getSize(find.byWidget(c)).width)
          .toList();
      // Widths include the 2.5px margin on each side.
      expect(widths, [11, 23, 11]);
      await _pump(tester, const YcPageDots(count: 1, index: 0));
      expect(find.byType(AnimatedContainer), findsNothing);
    });
  });

  group('YcChip / YcInlineBanner / YcErrorState', () {
    for (final b in Brightness.values) {
      testWidgets('$b: text keeps >= 4.5:1 on its tint', (tester) async {
        await _pump(
          tester,
          const Column(children: [
            YcChip(label: 'مطاعم'),
            YcChip.discount('خصم'),
            YcInlineBanner(message: 'تنبيه', tone: YcTone.danger),
          ]),
          brightness: b,
        );
        final card = YcSurface.of(tester.element(find.text('مطاعم'))).card;
        for (final label in ['مطاعم', 'خصم', 'تنبيه']) {
          final text = tester.widget<Text>(find.text(label));
          final box = tester
              .widget<DecoratedBox>(find
                  .ancestor(
                      of: find.text(label), matching: find.byType(DecoratedBox))
                  .first)
              .decoration as BoxDecoration;
          final bg = Color.alphaBlend(box.color!, card);
          expect(_contrast(text.style!.color!, bg), greaterThanOrEqualTo(4.5),
              reason: '$b $label');
        }
      });
    }

    testWidgets('error state offers a retry', (tester) async {
      var retried = 0;
      await _pump(
        tester,
        YcErrorState(title: 'تعذر التحميل', onRetry: () => retried++),
      );
      expect(find.byType(YcEmptyState), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retried, 1);
    });
  });

  group('layout matrix (RTL)', () {
    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp text x$scale renders without overflow',
              (tester) async {
            await _pump(tester, _gallery(),
                brightness: b, width: w, textScale: scale);
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  testWidgets('reduced motion: no animation in dots or segments',
      (tester) async {
    _reduceMotion(tester);
    await _pump(tester, _gallery());
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    final dots =
        tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
    for (final d in dots) {
      expect(d.duration, Duration.zero);
    }
  });
}
