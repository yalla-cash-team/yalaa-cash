import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';

const _payload = 'yallacash://customer/abc?v=1&token=signed-token-value';
const _longId = '3f2b9c1e-8a4d-4f6b-9c2e-7d1a5b0c9e42';

/// Counts token requests while keeping the in-memory behaviour.
class _CountingRepo extends InMemoryYallaCashRepository {
  _CountingRepo(super.store);
  int issued = 0;

  @override
  Future<CustomerQrToken> issueCustomerQrToken() {
    issued++;
    return super.issueCustomerQrToken();
  }
}

Customer _customer({String id = _longId, String name = 'أحمد الحسن'}) =>
    Customer(
      id: id,
      name: name,
      governorate: 'نينوى',
      pointsBalance: 0,
      createdAt: DateTime(2026),
    );

CustomerQrToken _token({Duration ttl = const Duration(minutes: 2)}) =>
    CustomerQrToken(
      token: 't',
      payload: _payload,
      expiresAt: DateTime.now().add(ttl),
    );

Future<_CountingRepo> _pump(
  WidgetTester tester, {
  CustomerQrToken? token,
  YallaCashFailure? failure,
  Customer? customer,
  Brightness brightness = Brightness.light,
  double width = 412,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final repo = _CountingRepo(store);
  await tester.pumpWidget(MaterialApp(
    theme: buildCustomerTheme(Brightness.light),
    darkTheme: buildCustomerTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (c, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(
      body: CustomerQrPage(
        cubit: CustomerAppCubit(repo),
        state: CustomerAppState(qrToken: token, failure: failure),
        customer: customer ?? _customer(),
      ),
    ),
  ));
  await tester.pump();
  return repo;
}

/// Unmount so the page's periodic refresh timer is cancelled.
Future<void> _dispose(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox());

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _hhmm(DateTime v) {
  final l = v.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:'
      '${l.minute.toString().padLeft(2, '0')}';
}

void main() {
  group('QR image is unchanged and never animated', () {
    testWidgets('exact payload and styling, 210px on a white plate',
        (tester) async {
      final token = _token();
      await _pump(tester, token: token);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.version, QrVersions.auto);
      expect(qr.size, 210);
      expect(qr.eyeStyle.eyeShape, QrEyeShape.square);
      expect(qr.eyeStyle.color, YallaColors.navy);
      expect(qr.dataModuleStyle.dataModuleShape, QrDataModuleShape.square);
      expect(qr.dataModuleStyle.color, YallaColors.navy);
      expect(tester.getSize(find.byType(QrImageView)), const Size(210, 210));

      // White plate with an 18px quiet margin around the QR.
      final plate = tester.widget<Container>(find
          .ancestor(
              of: find.byType(QrImageView), matching: find.byType(Container))
          .first);
      expect((plate.decoration! as BoxDecoration).color, Colors.white);
      expect(plate.padding, const EdgeInsets.all(18));
      expect(_contrast(YallaColors.navy, Colors.white), greaterThan(12));
      await _dispose(tester);
    });

    testWidgets('the painted QR encodes exactly the token payload',
        (tester) async {
      await _pump(tester, token: _token());
      final shown = tester
          .renderObject<RenderCustomPaint>(find
              .descendant(
                  of: find.byType(QrImageView),
                  matching: find.byType(CustomPaint))
              .first)
          .painter! as QrPainter;
      QrPainter reference(String data) => QrPainter(
            data: data,
            version: QrVersions.auto,
            gapless: true, // QrImageView's default
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: YallaColors.navy),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: YallaColors.navy),
          );
      Future<List<int>> png(QrPainter p) async =>
          (await tester.runAsync(() => p.toImageData(210)))!
              .buffer
              .asUint8List();
      final actual = await png(shown);
      expect(actual, await png(reference(_payload)));
      // Sensitivity check: a different payload paints differently.
      expect(actual, isNot(await png(reference('$_payload-x'))));
      await _dispose(tester);
    });

    testWidgets('no animation or transform wraps the QR', (tester) async {
      await _pump(tester, token: _token());
      for (final type in [
        Opacity,
        FadeTransition,
        ScaleTransition,
        SlideTransition,
        AnimatedSwitcher,
        Transform,
        FittedBox,
      ]) {
        // Route transitions animate the whole page; only widgets inside the
        // QR page itself matter here.
        expect(
          find.ancestor(
            of: find.byType(QrImageView),
            matching: find.descendant(
              of: find.byType(CustomerQrPage),
              matching: find.byType(type),
            ),
          ),
          findsNothing,
          reason: '$type must not wrap the QR',
        );
      }
      await _dispose(tester);
    });

    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp x$scale: fits, QR stays square',
              (tester) async {
            await _pump(tester,
                token: _token(),
                customer: _customer(
                    name:
                        'اسم عميل طويل جداً جداً لاختبار التفاف النص في الشاشة'),
                brightness: b,
                width: w,
                scale: scale);
            expect(tester.takeException(), isNull);
            final s = tester.getSize(find.byType(QrImageView));
            expect(s.width, s.height);
            // Text size never shrinks or grows the QR; only a narrow screen
            // can reduce it.
            if (w >= 412) expect(s.width, 210);
            await _dispose(tester);
          });
        }
      }
    }
  });

  testWidgets('pull-to-refresh still fires on the QR page', (tester) async {
    tester.view.physicalSize = const Size(412 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = YallaCashStore.demo()..loginDemoCustomer();
    addTearDown(store.dispose);
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: RefreshIndicator(
          onRefresh: () async => refreshes++,
          child: CustomerQrPage(
            cubit: CustomerAppCubit(_CountingRepo(store)),
            state: CustomerAppState(qrToken: _token()),
            customer: _customer(),
          ),
        ),
      ),
    ));
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(refreshes, 1);
    await _dispose(tester);
  });

  group('information', () {
    testWidgets('name, expiry time and the instruction are shown',
        (tester) async {
      final token = _token();
      await _pump(tester, token: token);
      expect(find.text('أحمد الحسن'), findsOneWidget);
      expect(find.text('ينتهي في ${_hhmm(token.expiresAt)}'), findsOneWidget);
      expect(find.text('كيف تجمع نقاطك؟'), findsOneWidget);
      expect(
        find.text(
            'أبرز الكود للكاشير عند الدفع. ستُضاف نقاطك تلقائياً بعد تسجيل الفاتورة.'),
        findsOneWidget,
      );
      await _dispose(tester);
    });

    testWidgets('a short reference replaces the full technical id',
        (tester) async {
      await _pump(tester, token: _token());
      expect(find.textContaining(_longId), findsNothing);
      expect(find.text('#…5b0c9e42'.replaceFirst('5b', '')), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('short ids are shown in full', (tester) async {
      await _pump(tester, token: _token(), customer: _customer(id: 'c-17'));
      expect(find.text('#c-17'), findsOneWidget);
      await _dispose(tester);
    });

    testWidgets('loading: spinner on the plate, no expiry', (tester) async {
      await _pump(tester);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('ينتهي في'), findsNothing);
      await _dispose(tester);
    });

    testWidgets('failure: message and a retry that requests a token',
        (tester) async {
      final repo = await _pump(
        tester,
        failure:
            const YallaCashFailure(code: 'network_error', message: 'offline'),
      );
      expect(find.text('تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مجدداً.'),
          findsOneWidget);
      final before = repo.issued;
      await tester.pump(); // let the initial request settle
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();
      expect(repo.issued, greaterThanOrEqualTo(before));
      await _dispose(tester);
    });
  });

  group('token refresh rules are unchanged', () {
    testWidgets('a valid token is not re-issued on the 5s checks',
        (tester) async {
      final repo = await _pump(tester, token: _token());
      await tester.pump(const Duration(seconds: 16)); // three timer ticks
      expect(repo.issued, 0);
      await _dispose(tester);
    });

    testWidgets('a token within the 10s safety margin is renewed',
        (tester) async {
      final repo =
          await _pump(tester, token: _token(ttl: const Duration(seconds: 5)));
      expect(repo.issued, 1);
      await _dispose(tester);
    });

    testWidgets('no token: one is requested immediately', (tester) async {
      final repo = await _pump(tester);
      expect(repo.issued, 1);
      await _dispose(tester);
    });
  });

  group('motion', () {
    testWidgets(
        'only the expiry text cross-fades; instant under reduced '
        'motion', (tester) async {
      await _pump(tester, token: _token());
      final switcher =
          tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, const Duration(milliseconds: 250));
      await _dispose(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await _pump(tester, token: _token());
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
      await _dispose(tester);
    });
  });

  group('instruction card', () {
    final icon = find.byIcon(Icons.qr_code_scanner_rounded);
    final card = find.ancestor(
      of: find.text('كيف تجمع نقاطك؟'),
      matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_QrInstructionCard'),
    );

    testWidgets('shows the exact approved title and description',
        (tester) async {
      await _pump(tester, token: _token());
      expect(find.text('كيف تجمع نقاطك؟'), findsOneWidget);
      expect(
        find.text(
            'أبرز الكود للكاشير عند الدفع. ستُضاف نقاطك تلقائياً بعد تسجيل الفاتورة.'),
        findsOneWidget,
      );
      expect(icon, findsOneWidget);
      await _dispose(tester);
    });

    testWidgets(
        'icon is top-aligned beside the title, not vertically '
        'centred against a tall description', (tester) async {
      await _pump(tester, token: _token());
      // The badge container, not the glyph itself (which sits centred
      // inside the badge), is what visually top-aligns with the title.
      final badgeTop = tester.getTopLeft(find.byType(YcIconBadge)).dy;
      final titleTop = tester.getTopLeft(find.text('كيف تجمع نقاطك؟')).dy;
      expect(badgeTop, closeTo(titleTop, 6));
      await _dispose(tester);
    });

    testWidgets(
        'RTL: icon sits on the right, title/description start there '
        'too', (tester) async {
      await _pump(tester, token: _token());
      final iconCenter = tester.getCenter(icon).dx;
      final titleLeft = tester.getTopLeft(find.text('كيف تجمع نقاطك؟')).dx;
      // The icon is to the right of the text block's own start edge.
      expect(iconCenter, greaterThan(titleLeft));
      final cardRight = tester.getRect(card).right;
      final iconRight = tester.getRect(icon).right;
      expect(cardRight - iconRight, lessThan(40));
      await _dispose(tester);
    });

    testWidgets(
        'title is smaller/lighter than the balance card\'s hero '
        'figure and heavier than the description', (tester) async {
      await _pump(tester, token: _token());
      final title = tester.widget<Text>(find.text('كيف تجمع نقاطك؟')).style!;
      final description = tester
          .widget<Text>(find.text(
              'أبرز الكود للكاشير عند الدفع. ستُضاف نقاطك تلقائياً بعد تسجيل الفاتورة.'))
          .style!;
      expect(title.fontSize, lessThanOrEqualTo(16));
      expect((title.fontWeight?.value ?? 0),
          greaterThan(description.fontWeight?.value ?? 0));
      expect(description.fontSize, lessThan(title.fontSize!));
      await _dispose(tester);
    });

    testWidgets('does not alter the QR plate, payload or expiry',
        (tester) async {
      final token = _token();
      await _pump(tester, token: token);
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.size, 210);
      expect(find.text('ينتهي في ${_hhmm(token.expiresAt)}'), findsOneWidget);
      await _dispose(tester);
    });

    for (final b in Brightness.values) {
      testWidgets('$b: renders cleanly', (tester) async {
        await _pump(tester, token: _token(), brightness: b);
        expect(tester.takeException(), isNull);
        expect(find.text('كيف تجمع نقاطك؟'), findsOneWidget);
        await _dispose(tester);
      });
    }

    for (final w in [320.0, 412.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${w}dp x$scale: no overflow', (tester) async {
          await _pump(tester, token: _token(), width: w, scale: scale);
          expect(tester.takeException(), isNull);
          expect(find.text('كيف تجمع نقاطك؟'), findsOneWidget);
          await _dispose(tester);
        });
      }
    }
  });
}
