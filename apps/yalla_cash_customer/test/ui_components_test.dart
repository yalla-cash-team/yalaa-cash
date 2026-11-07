import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
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

const _longText =
    'نص طويل جداً لاختبار التفاف النص والقص في الشاشات الصغيرة مع تكبير الخط';

Widget _gallery() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        YcSectionHeader(_longText,
            subtitle: _longText, actionLabel: 'عرض الكل', onAction: () {}),
        const SizedBox(height: YcSpace.sm),
        YcCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            YcListRow(
              icon: Icons.receipt_long_rounded,
              title: _longText,
              subtitle: _longText,
              trailing: const YcStatusChip.pending('طلبك قيد المراجعة'),
              onTap: () {},
            ),
            const YcListRow(
              icon: Icons.check_rounded,
              iconTone: YcTone.success,
              title: 'تم الاستبدال',
              trailing: YcStatusChip.completed('تم الاستبدال'),
            ),
            const YcListRow(
              title: 'تم رفض الطلب',
              trailing: YcStatusChip.rejected('تم رفض الطلب'),
            ),
          ]),
        ),
        const SizedBox(height: YcSpace.sm),
        YcCard(
          onTap: () {},
          child: YcEmptyState(
            icon: Icons.local_offer_outlined,
            title: _longText,
            description: _longText,
            actionLabel: 'تحديث',
            onAction: () {},
          ),
        ),
        const SizedBox(height: YcSpace.sm),
        const Wrap(spacing: 8, children: [
          YcIconBadge(Icons.star_rounded),
          YcIconBadge(Icons.warning_amber_rounded,
              tone: YcTone.warning, circle: true),
          YcIconBadge(Icons.close_rounded, tone: YcTone.danger, size: 56),
        ]),
        const YcFadeSlideIn(child: Text('ENTERED')),
      ],
    );

void main() {
  group('layout matrix (RTL)', () {
    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp text x$scale renders without overflow',
              (tester) async {
            await _pump(tester, _gallery(),
                brightness: b, width: w, textScale: scale);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('ENTERED'), findsOneWidget);
          });
        }
      }
    }
  });

  group('YcCard', () {
    for (final b in Brightness.values) {
      testWidgets('$b uses YcSurface tokens', (tester) async {
        await _pump(tester, const YcCard(child: Text('x')), brightness: b);
        final surface = YcSurface.forBrightness(b);
        final material = tester.widget<Material>(find
            .descendant(
                of: find.byType(YcCard), matching: find.byType(Material))
            .first);
        expect(material.color, surface.card);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, surface.hairline);
        final box = tester.widget<DecoratedBox>(find
            .descendant(
                of: find.byType(YcCard), matching: find.byType(DecoratedBox))
            .first);
        final shadows = (box.decoration as BoxDecoration).boxShadow ?? const [];
        // Light: one soft shadow. Dark: border only.
        expect(shadows.length, b == Brightness.light ? 1 : 0);
      });
    }

    testWidgets('tappable card fires and reads as one button', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        YcCard(
          onTap: () => taps++,
          child: const Column(children: [Text('عنوان'), Text('تفاصيل')]),
        ),
      );
      await tester.tap(find.text('عنوان'));
      expect(taps, 1);
      final node = tester.getSemantics(find.text('عنوان'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, contains('عنوان'));
      expect(node.label, contains('تفاصيل'));
      handle.dispose();
    });

    testWidgets('static card is not a button', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const YcCard(child: Text('عنوان')));
      expect(tester.getSemantics(find.text('عنوان')).flagsCollection.isButton,
          isFalse);
      handle.dispose();
    });
  });

  group('YcSectionHeader', () {
    testWidgets('header semantics, action fires, RTL order', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        YcSectionHeader('المحلات',
            actionLabel: 'عرض الكل', onAction: () => taps++),
      );
      expect(tester.getSemantics(find.text('المحلات')).flagsCollection.isHeader,
          isTrue);
      await tester.tap(find.text('عرض الكل'));
      expect(taps, 1);
      // RTL: title starts on the right, action sits on the left.
      expect(tester.getCenter(find.text('المحلات')).dx,
          greaterThan(tester.getCenter(find.text('عرض الكل')).dx));
      // Action keeps a 48px touch target.
      expect(tester.getSize(find.byType(TextButton)).height,
          greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('action hidden without a callback', (tester) async {
      await _pump(
          tester, const YcSectionHeader('المحلات', actionLabel: 'عرض الكل'));
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('YcEmptyState', () {
    testWidgets('full variant renders and action fires', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        YcEmptyState(
          icon: Icons.inbox_outlined,
          title: 'لا توجد عروض',
          description: 'ستظهر هنا',
          actionLabel: 'تحديث',
          onAction: () => taps++,
        ),
      );
      expect(find.byType(YcIconBadge), findsOneWidget);
      expect(find.text('ستظهر هنا'), findsOneWidget);
      await tester.tap(find.text('تحديث'));
      expect(taps, 1);
    });

    testWidgets('minimal variant has title only', (tester) async {
      await _pump(tester, const YcEmptyState(title: 'لا توجد عروض'));
      expect(find.byType(YcIconBadge), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text('لا توجد عروض'), findsOneWidget);
    });
  });

  group('YcListRow', () {
    testWidgets('tap, RTL order, min height, merged semantics', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        YcCard(
          padding: EdgeInsets.zero,
          child: YcListRow(
            icon: Icons.receipt_long_rounded,
            title: 'شراء',
            subtitle: 'اليوم',
            trailing: const Text('+50'),
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('شراء'));
      expect(taps, 1);
      expect(tester.getSize(find.byType(YcListRow)).height,
          greaterThanOrEqualTo(56));
      final lead = tester.getCenter(find.byType(YcIconBadge)).dx;
      final title = tester.getCenter(find.text('شراء')).dx;
      final trail = tester.getCenter(find.text('+50')).dx;
      expect(lead, greaterThan(title));
      expect(title, greaterThan(trail));
      final node = tester.getSemantics(find.text('شراء'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label,
          allOf(contains('شراء'), contains('اليوم'), contains('+50')));
      handle.dispose();
    });

    testWidgets('title truncates to titleMaxLines', (tester) async {
      await _pump(tester, const YcListRow(title: _longText + _longText),
          width: 320);
      final text = tester.widget<Text>(find.text(_longText + _longText));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  });

  group('YcStatusChip', () {
    testWidgets('presets carry tone and icon', (tester) async {
      await _pump(
        tester,
        const Column(children: [
          YcStatusChip.pending('p'),
          YcStatusChip.completed('c'),
          YcStatusChip.rejected('r'),
        ]),
      );
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
      expect(const YcStatusChip.pending('p').tone, YcTone.warning);
      expect(const YcStatusChip.completed('c').tone, YcTone.success);
      expect(const YcStatusChip.rejected('r').tone, YcTone.danger);
    });

    for (final b in Brightness.values) {
      testWidgets('$b: every tone keeps >= 4.5:1 text contrast',
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
        final card = YcSurface.of(ctx).card;
        for (final tone in YcTone.values) {
          final colors = YcToneColors.of(ctx, tone);
          final bg = Color.alphaBlend(colors.background, card);
          final ratio = _contrast(colors.foreground, bg);
          expect(ratio, greaterThanOrEqualTo(4.5),
              reason: '$b $tone contrast ${ratio.toStringAsFixed(2)}');
        }
      });
    }
  });

  group('YcIconBadge', () {
    testWidgets('decorative by default, labelled when asked', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const Row(children: [
          YcIconBadge(Icons.star_rounded, size: 48),
          YcIconBadge(Icons.wallet_rounded, semanticLabel: 'محفظة'),
        ]),
      );
      expect(find.bySemanticsLabel('محفظة'), findsOneWidget);
      final sizes = tester
          .renderObjectList<RenderBox>(find.byType(YcIconBadge))
          .map((r) => r.size)
          .toList();
      expect(sizes.first, const Size(48, 48));
      expect(sizes.last, const Size(40, 40));
      // The unlabelled badge sits inside an active ExcludeSemantics.
      expect(
        find.ancestor(
          of: find.byIcon(Icons.star_rounded),
          matching: find.byWidgetPredicate(
            (w) => w is ExcludeSemantics && w.excluding,
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('YcFadeSlideIn', () {
    double opacityOf(WidgetTester tester) => tester
        .widget<Opacity>(
            find.ancestor(of: find.text('IN'), matching: find.byType(Opacity)))
        .opacity;

    testWidgets('animates in once and does not replay on rebuild',
        (tester) async {
      await _pump(tester, const YcFadeSlideIn(child: Text('IN')));
      expect(opacityOf(tester), 0);
      await tester.pump(YcMotion.slow ~/ 2);
      final mid = opacityOf(tester);
      expect(mid, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacityOf(tester), 1);
      // Rebuild with identical settings: stays fully visible.
      await _pump(tester, const YcFadeSlideIn(child: Text('IN')));
      await tester.pump();
      expect(opacityOf(tester), 1);
    });

    testWidgets('delay holds the start without timers', (tester) async {
      await _pump(
        tester,
        const YcFadeSlideIn(
          delay: Duration(milliseconds: 200),
          child: Text('IN'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 180));
      expect(opacityOf(tester), 0);
      await tester.pumpAndSettle();
      expect(opacityOf(tester), 1);
    });

    testWidgets('reduced motion: child shown immediately, no animation',
        (tester) async {
      _reduceMotion(tester);
      await _pump(tester, const YcFadeSlideIn(child: Text('IN')));
      expect(find.text('IN'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('IN'), matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });
  });
}
