import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final _t0 = DateTime(2026, 3, 9);

LoyaltyTransaction _tx(String id, String store, int amount, int points) =>
    LoyaltyTransaction(
      id: id,
      storeId: 's$id',
      storeName: store,
      customerId: 'c',
      amountSyp: amount,
      commissionRateSnapshot: 5,
      commissionAmountSyp: 0,
      platformRevenueSyp: 0,
      customerShareSyp: 0,
      customerPointsEarned: points,
      createdAt: _t0,
    );

ProductRedemption _red(String id, RedemptionStatus status,
        {String? name = 'بطاقة شحن',
        String? phone,
        int cost = 300,
        String productId = 'p1'}) =>
    ProductRedemption(
      id: id,
      customerId: 'c',
      productId: productId,
      productName: name,
      pointsCostSnapshot: cost,
      phoneNumber: phone,
      status: status,
      createdAt: _t0,
    );

DigitalProduct _product(String id, int cost,
        {String name = 'منتج',
        bool active = true,
        bool phone = false,
        String? image}) =>
    DigitalProduct(
      id: id,
      name: name,
      costInPoints: cost,
      iconSeed: 0,
      isActive: active,
      requiresPhoneNumber: phone,
      imageUrl: image,
    );

PointsSummary _points(int balance, {int held = 0}) => PointsSummary(
      pointsBalance: balance,
      heldPoints: held,
      availablePoints: balance - held,
    );

/// Records submissions while keeping the in-memory behaviour.
class _RecordingRepo extends InMemoryYallaCashRepository {
  _RecordingRepo(super.store);

  final cash = <int>[];
  final redeemed = <String>[];

  /// When set, requests wait on it (a slow network) before completing.
  Completer<void>? gate;

  @override
  Future<CashRedemptionRequest> requestCashRedemption(int points) async {
    cash.add(points);
    await gate?.future;
    return super.requestCashRedemption(points);
  }

  @override
  Future<void> redeemDigitalProduct({
    required DigitalProduct product,
    String? phoneNumber,
  }) async {
    redeemed.add(product.id);
    await gate?.future;
  }
}

void _viewport(WidgetTester tester, {double width = 412, double scale = 1}) {
  tester.view.physicalSize = Size(width * 2, 2400 * 2);
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

Widget _app(Widget body, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      darkTheme: buildCustomerTheme(Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: body),
    );

void _onlyImageFailures(WidgetTester tester) {
  Object? e = tester.takeException();
  while (e != null) {
    expect(e, isA<NetworkImageLoadException>());
    e = tester.takeException();
  }
}

// Rewards host: lets a test swap the state without remounting the page.
class _RewardsHost extends StatefulWidget {
  const _RewardsHost({required this.cubit, required this.state});
  final CustomerAppCubit cubit;
  final CustomerAppState state;
  @override
  State<_RewardsHost> createState() => _RewardsHostState();
}

class _RewardsHostState extends State<_RewardsHost> {
  late CustomerAppState state = widget.state;
  void update(CustomerAppState next) => setState(() => state = next);
  @override
  Widget build(BuildContext context) =>
      CustomerRewardsPage(cubit: widget.cubit, state: state);
}

Future<({YallaCashStore store, _RecordingRepo repo})> _pumpRewards(
  WidgetTester tester, {
  PointsSummary? points,
  List<DigitalProduct> products = const [],
  List<ProductRedemption> redemptions = const [],
  List<CashRedemptionRequest> cashRequests = const [],
  LoadStatus status = LoadStatus.success,
  Brightness brightness = Brightness.light,
  double width = 412,
  double scale = 1,
}) async {
  _viewport(tester, width: width, scale: scale);
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final repo = _RecordingRepo(store);
  await tester.pumpWidget(_app(
    _RewardsHost(
      cubit: CustomerAppCubit(repo),
      state: CustomerAppState(
        status: status,
        customer: store.currentCustomer,
        points: points,
        products: products,
        productRedemptions: redemptions,
        cashRequests: cashRequests,
      ),
    ),
    brightness: brightness,
  ));
  await tester.pump();
  return (store: store, repo: repo);
}

final _submit = find.widgetWithText(FilledButton, 'إرسال طلب الاستبدال');
bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

String? _errorText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).decoration?.errorText;

YcProgressBar _barFor(WidgetTester tester, String productName) {
  final card = find.ancestor(
    of: find.text(productName),
    matching: find
        .byWidgetPredicate((w) => w.runtimeType.toString() == '_ProductCard'),
  );
  return tester.widget<YcProgressBar>(
      find.descendant(of: card, matching: find.byType(YcProgressBar)));
}

Finder _barIn(String productName) => find.descendant(
      of: find.ancestor(
        of: find.text(productName),
        matching: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ProductCard'),
      ),
      matching: find.byType(YcProgressBar),
    );

void main() {
  // -------------------------------------------------------------------------
  group('wallet', () {
    Future<void> pumpWallet(
      WidgetTester tester, {
      List<LoyaltyTransaction> transactions = const [],
      List<ProductRedemption> redemptions = const [],
      List<CashRedemptionRequest> cashRequests = const [],
      bool loading = false,
      bool failed = false,
      VoidCallback? onRetry,
      Brightness brightness = Brightness.light,
      double width = 412,
      double scale = 1,
    }) async {
      _viewport(tester, width: width, scale: scale);
      final customer = Customer(
        id: 'c',
        name: 'أحمد',
        governorate: 'نينوى',
        pointsBalance: 0,
        createdAt: _t0,
      );
      await tester.pumpWidget(_app(
        CustomerWalletPage(
          transactions: transactions,
          customer: customer,
          productRedemptions: redemptions,
          cashRequests: cashRequests,
          loading: loading,
          failed: failed,
          onRetry: onRetry,
        ),
        brightness: brightness,
      ));
    }

    testWidgets('every transaction keeps its data and order', (tester) async {
      await pumpWallet(tester, transactions: [
        _tx('1', 'مطعم البيت', 25000, 120),
        _tx('2', 'صيدلية', 8000, 40),
        _tx('3', 'مقهى', 1500, 7),
      ]);
      // Value and unit on one line.
      expect(find.text('+120 نقطة'), findsOneWidget);
      expect(find.text('+40 نقطة'), findsOneWidget);
      expect(find.text('+7 نقطة'), findsOneWidget);
      expect(find.text('09/03/2026 · فاتورة 25,000 ل.س'), findsOneWidget);
      final ys = [
        for (final s in ['مطعم البيت', 'صيدلية', 'مقهى'])
          tester.getCenter(find.text(s)).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
    });

    testWidgets('earned points use the success tone', (tester) async {
      await pumpWallet(tester, transactions: [_tx('1', 'مطعم', 100, 5)]);
      final ctx = tester.element(find.text('+5 نقطة'));
      expect(tester.widget<Text>(find.text('+5 نقطة')).style?.color,
          YcToneColors.of(ctx, YcTone.success).foreground);
    });

    testWidgets(
        'redemptions: existing labels as status chips; fulfilled '
        'dimmed only', (tester) async {
      await pumpWallet(tester, redemptions: [
        _red('a', RedemptionStatus.pending, phone: '0991234567'),
        _red('b', RedemptionStatus.fulfilled, name: 'باقة إنترنت'),
        _red('c', RedemptionStatus.rejected, name: null),
      ]);
      YcStatusChip chip(String label) => tester.widget<YcStatusChip>(find
          .ancestor(of: find.text(label), matching: find.byType(YcStatusChip)));
      expect(chip('طلبك قيد المراجعة').tone, YcTone.warning);
      expect(chip('تم الاستبدال').tone, YcTone.success);
      expect(chip('تم رفض الطلب').tone, YcTone.danger);
      expect(find.text('منتج رقمي'), findsOneWidget); // name fallback
      expect(find.text('09/03/2026 · 0991234567'), findsOneWidget);
      expect(find.text('300 نقطة'), findsNWidgets(3));
      double opacityOf(String label) {
        final o =
            find.ancestor(of: find.text(label), matching: find.byType(Opacity));
        return o.evaluate().isEmpty
            ? 1
            : tester.widget<Opacity>(o.first).opacity;
      }

      expect(opacityOf('تم الاستبدال'), 0.55);
      expect(opacityOf('طلبك قيد المراجعة'), 1);
      expect(opacityOf('تم رفض الطلب'), 1);
    });

    testWidgets('cash requests: real amount, date, points and status',
        (tester) async {
      CashRedemptionRequest req(
              String id, int pts, int syp, CashRequestStatus s) =>
          CashRedemptionRequest(
            id: id,
            customerId: 'c',
            pointsRequested: pts,
            cashValueSyp: syp,
            status: s,
            createdAt: _t0,
          );
      await pumpWallet(tester, cashRequests: [
        req('1', 100, 500, CashRequestStatus.pending),
        req('2', 2000, 10000, CashRequestStatus.settled),
        req('3', 40, 200, CashRequestStatus.rejected),
      ]);
      expect(find.text('طلبات سحب الكاش'), findsOneWidget);
      expect(find.text('500 ل.س'), findsOneWidget);
      expect(find.text('10,000 ل.س'), findsOneWidget);
      expect(find.text('200 ل.س'), findsOneWidget);
      expect(find.text('09/03/2026 · 100 نقطة'), findsOneWidget);
      expect(find.text('09/03/2026 · 2,000 نقطة'), findsOneWidget);
      YcStatusChip chip(String label) => tester.widget<YcStatusChip>(find
          .ancestor(of: find.text(label), matching: find.byType(YcStatusChip)));
      expect(chip('قيد المعالجة').tone, YcTone.warning);
      expect(chip('تم الصرف').tone, YcTone.success);
      expect(chip('تم رفض الطلب').tone, YcTone.danger);
      // Order preserved as delivered.
      final ys = [
        for (final s in ['500 ل.س', '10,000 ل.س', '200 ل.س'])
          tester.getCenter(find.text(s)).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
    });

    testWidgets('sections in order: transactions, cash, products',
        (tester) async {
      await pumpWallet(tester);
      final y = [
        for (final s in [
          'سجل العمليات',
          'طلبات سحب الكاش',
          'طلبات استبدال المنتجات'
        ])
          tester.getCenter(find.text(s)).dy,
      ];
      expect(y[0], lessThan(y[1]));
      expect(y[1], lessThan(y[2]));
    });

    testWidgets('empty lists show the existing empty messages', (tester) async {
      await pumpWallet(tester);
      // Three sections: transactions, cash requests, product requests.
      expect(find.byType(YcEmptyState), findsNWidgets(3));
      expect(find.text('لا توجد عمليات حتى الآن'), findsOneWidget);
      expect(find.text('لا توجد طلبات سحب بعد'), findsOneWidget);
      expect(find.text('لا توجد طلبات استبدال بعد'), findsOneWidget);
    });

    testWidgets('loading shows placeholders, never a false empty message',
        (tester) async {
      await pumpWallet(tester, loading: true);
      expect(find.byType(YcSkeleton), findsNWidgets(3));
      expect(find.text('لا توجد عمليات حتى الآن'), findsNothing);
      expect(find.text('لا توجد طلبات سحب بعد'), findsNothing);
    });

    testWidgets('failure shows a retry state that calls back', (tester) async {
      var retries = 0;
      await pumpWallet(tester, failed: true, onRetry: () => retries++);
      expect(find.text('تعذر تحميل السجل'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      expect(retries, 1);
    });

    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp x$scale: long text and big numbers fit',
              (tester) async {
            await pumpWallet(
              tester,
              brightness: b,
              width: w,
              scale: scale,
              transactions: [
                _tx('1', 'اسم متجر طويل جداً جداً لاختبار القص والتفاف النص',
                    987654321, 123456789),
              ],
              cashRequests: [
                CashRedemptionRequest(
                  id: 'x',
                  customerId: 'c',
                  pointsRequested: 123456789,
                  cashValueSyp: 987654321,
                  status: CashRequestStatus.settled,
                  createdAt: _t0,
                ),
              ],
              redemptions: [
                _red('a', RedemptionStatus.pending,
                    name: 'اسم منتج رقمي طويل جداً لاختبار القص',
                    phone: '0991234567',
                    cost: 99999999),
                _red('b', RedemptionStatus.rejected),
              ],
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  group('rewards: available points and cash form', () {
    testWidgets('summary shows AVAILABLE points, not the total balance',
        (tester) async {
      await _pumpRewards(tester, points: _points(1000, held: 400));
      expect(find.text('600 نقطة'), findsOneWidget);
      expect(find.text('1,000 نقطة'), findsNothing);
    });

    testWidgets('summary never shows the total while loading', (tester) async {
      final r = await _pumpRewards(tester, points: null);
      final total = formatNumber(r.store.currentCustomer!.pointsBalance);
      expect(find.text('$total نقطة'), findsNothing);
      expect(find.byType(YcSkeleton), findsOneWidget); // products placeholder
    });

    testWidgets('load failure: retry in summary and products', (tester) async {
      await _pumpRewards(tester, points: null, status: LoadStatus.failure);
      expect(find.text('تعذر تحميل الرصيد'), findsOneWidget);
      expect(find.text('تعذر تحميل المنتجات'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNWidgets(2));
    });

    testWidgets('conversion uses the existing rate and rounding',
        (tester) async {
      // Default rate when there is no history: 5 SYP per point.
      await _pumpRewards(tester, points: _points(1000));
      await tester.enterText(find.byType(TextField), '100');
      await tester.pump();
      expect(find.text('500 ل.س'), findsOneWidget);
    });

    testWidgets('conversion rate comes from the first request, rounded',
        (tester) async {
      await _pumpRewards(tester, points: _points(1000), cashRequests: [
        CashRedemptionRequest(
          id: 'r',
          customerId: 'c',
          pointsRequested: 10,
          cashValueSyp: 73,
          status: CashRequestStatus.settled,
          createdAt: _t0,
        ),
      ]);
      await tester.enterText(find.byType(TextField), '3');
      await tester.pump();
      expect(find.text('22 ل.س'), findsOneWidget); // 3 × 7.3 = 21.9 → 22
    });

    testWidgets('validation feedback mirrors the unchanged submit rule',
        (tester) async {
      await _pumpRewards(tester, points: _points(1000, held: 400));
      // (input, enabled, error)
      const cases = [
        ('', false, null),
        ('abc', false, 'أدخل عدداً صحيحاً أكبر من صفر'),
        ('0', false, 'أدخل عدداً صحيحاً أكبر من صفر'),
        ('-5', false, 'أدخل عدداً صحيحاً أكبر من صفر'),
        ('601', false, 'العدد أكبر من رصيدك المتاح'),
        ('600', true, null),
        ('1', true, null),
      ];
      for (final (input, enabled, error) in cases) {
        await tester.enterText(find.byType(TextField), input);
        await tester.pump();
        expect(_enabled(tester, _submit), enabled, reason: 'input "$input"');
        expect(_errorText(tester), error, reason: 'input "$input"');
      }
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('الحد الأقصى 600 نقطة'), findsOneWidget);
    });

    testWidgets('submit sends exactly one request with the typed points',
        (tester) async {
      final r = await _pumpRewards(tester, points: _points(1000));
      final available = r.store.availablePoints(r.store.currentCustomer!.id);
      final amount = available >= 50 ? 50 : 1;
      await tester.enterText(find.byType(TextField), '$amount');
      await tester.pump();
      r.repo.gate = Completer<void>(); // keep the request in flight
      final button = find.byType(FilledButton);
      // A second tap in the same frame, then another after a rebuild.
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      await tester.tap(button, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.repo.cash, [amount]);
      // In flight: disabled, with a small spinner in the button.
      expect(_enabled(tester, button), isFalse);
      expect(
          find.descendant(
              of: button, matching: find.byType(CircularProgressIndicator)),
          findsOneWidget);
      r.repo.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.repo.cash, [amount]);
      expect(find.text('إرسال طلب الاستبدال'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // snackbar timers
    });

    testWidgets(
        'cash redemption is disabled until available points load; '
        'the total balance is never used instead', (tester) async {
      final r = await _pumpRewards(tester, points: null);
      final total = r.store.currentCustomer!.pointsBalance;
      expect(total, greaterThan(0), reason: 'demo customer has a balance');
      // A valid amount within the TOTAL balance must still be refused.
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      expect(_enabled(tester, _submit), isFalse);
      expect(_errorText(tester), isNull, reason: 'no error while unknown');
      expect(find.text('يتاح الإرسال بعد تحميل رصيدك المتاح'), findsOneWidget);
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pump();
      expect(r.repo.cash, isEmpty);

      // Once the real available points arrive, the same input is valid.
      final host = tester.state<_RewardsHostState>(find.byType(_RewardsHost));
      host.update(CustomerAppState(
        customer: host.state.customer,
        points: _points(total, held: total - 1),
      ));
      await tester.pump();
      expect(_enabled(tester, _submit), isTrue);
      expect(find.text('الحد الأقصى 1 نقطة'), findsOneWidget);
      // ...and the cap is the AVAILABLE amount, not the total.
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      expect(_enabled(tester, _submit), isFalse);
      expect(_errorText(tester), 'العدد أكبر من رصيدك المتاح');
    });

    testWidgets('load failure keeps cash redemption disabled', (tester) async {
      final r =
          await _pumpRewards(tester, points: null, status: LoadStatus.failure);
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      expect(_enabled(tester, _submit), isFalse);
      await tester.tap(_submit, warnIfMissed: false);
      await tester.pump();
      expect(r.repo.cash, isEmpty);
    });

    testWidgets('valid submissions are unchanged once loaded', (tester) async {
      final r = await _pumpRewards(tester, points: _points(1000, held: 400));
      await tester.enterText(find.byType(TextField), '600');
      await tester.pump();
      expect(_enabled(tester, _submit), isTrue);
      await tester.tap(_submit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.repo.cash, [600]);
      await tester.pump(const Duration(seconds: 5)); // snackbar timers
    });
  });

  // -------------------------------------------------------------------------
  group('digital products and progress bar', () {
    testWidgets('progress = available / cost, clamped; uses AVAILABLE points',
        (tester) async {
      await _pumpRewards(tester, points: _points(1000, held: 600), products: [
        _product('a', 1600, name: 'ربع'),
        _product('b', 800, name: 'نصف'),
        _product('c', 100, name: 'مكتمل'),
        _product('d', 0, name: 'مجاني'),
      ]);
      expect(_barFor(tester, 'ربع').value, closeTo(.25, 1e-9));
      // 400 / 800 — the total (1000) would wrongly give 1.0.
      expect(_barFor(tester, 'نصف').value, closeTo(.5, 1e-9));
      expect(_barFor(tester, 'مكتمل').value, 1);
      expect(_barFor(tester, 'مجاني').value, 1);
    });

    testWidgets('zero available points: empty bar', (tester) async {
      await _pumpRewards(tester,
          points: _points(0), products: [_product('a', 500, name: 'منتج')]);
      expect(_barFor(tester, 'منتج').value, 0);
    });

    testWidgets('no bar for pending-request or inactive products',
        (tester) async {
      await _pumpRewards(
        tester,
        points: _points(1000),
        products: [
          _product('p1', 100, name: 'قيد الطلب'),
          _product('p2', 100, name: 'غير نشط', active: false),
          _product('p3', 100, name: 'مؤهل'),
        ],
        redemptions: [_red('r', RedemptionStatus.pending, productId: 'p1')],
      );
      expect(_barIn('قيد الطلب'), findsNothing);
      expect(_barIn('غير نشط'), findsNothing);
      expect(_barIn('مؤهل'), findsOneWidget);
      // Pending product: status chip instead of the action.
      final pendingCard = find.ancestor(
          of: find.text('قيد الطلب'),
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_ProductCard'));
      expect(
          find.descendant(of: pendingCard, matching: find.byType(YcStatusChip)),
          findsOneWidget);
      expect(find.descendant(of: pendingCard, matching: find.text('استبدال')),
          findsNothing);
    });

    testWidgets('a fulfilled or rejected past request does not block',
        (tester) async {
      await _pumpRewards(
        tester,
        points: _points(1000),
        products: [_product('p1', 100, name: 'منتج')],
        redemptions: [
          _red('a', RedemptionStatus.fulfilled, productId: 'p1'),
          _red('b', RedemptionStatus.rejected, productId: 'p1'),
        ],
      );
      expect(_barIn('منتج'), findsOneWidget);
      expect(find.text('استبدال'), findsOneWidget);
    });

    testWidgets('redeem button rule is unchanged: available >= cost',
        (tester) async {
      await _pumpRewards(tester, points: _points(1000, held: 600), products: [
        _product('a', 400, name: 'يكفي'),
        _product('b', 401, name: 'لا يكفي'),
      ]);
      Finder btn(String name) => find.descendant(
          of: find.ancestor(
              of: find.text(name),
              matching: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_ProductCard')),
          matching: find.byType(FilledButton));
      expect(_enabled(tester, btn('يكفي')), isTrue);
      expect(_enabled(tester, btn('لا يكفي')), isFalse);
    });

    testWidgets(
        'no numbers or percentages inside the bar; value for screen '
        'readers only', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpRewards(tester,
          points: _points(250), products: [_product('a', 1000, name: 'منتج')]);
      expect(
        find.descendant(of: _barIn('منتج'), matching: find.byType(Text)),
        findsNothing,
      );
      expect(find.textContaining('%'), findsNothing);
      final node = tester.getSemantics(_barIn('منتج'));
      expect(node.value, '25%');
      handle.dispose();
    });

    group('motivational message', () {
      Finder cardFor(String name) => find.ancestor(
          of: find.text(name),
          matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_ProductCard'));

      testWidgets('exact copy at every real progress threshold',
          (tester) async {
        // (available points against a 100-point product, expected message)
        const cases = [
          (0, 'رحلتك للمكافأة بتبدأ من هون!'), // 0%
          (1, 'كل نقطة بتقرّبك من مكافأتك!'), // just above 0%
          (24, 'كل نقطة بتقرّبك من مكافأتك!'), // just below 25%
          (25, 'بداية حلوة، كمّل تجميع!'), // 25%
          (49, 'بداية حلوة، كمّل تجميع!'), // just below 50%
          (50, 'قطعت شوط حلو نحو مكافأتك!'), // 50%
          (74, 'قطعت شوط حلو نحو مكافأتك!'), // just below 75%
          (75, 'باقيلك شوي، مكافأتك صارت قريبة!'), // 75%
          (99, 'باقيلك شوي، مكافأتك صارت قريبة!'), // just below 100%
          (100, 'مبروك! مكافأتك جاهزة للاستبدال'), // 100%
          (150, 'مبروك! مكافأتك جاهزة للاستبدال'), // clamped above 100%
        ];
        for (final (available, message) in cases) {
          await _pumpRewards(tester,
              points: _points(available),
              products: [_product('a', 100, name: 'منتج')]);
          expect(
            find.descendant(of: cardFor('منتج'), matching: find.text(message)),
            findsOneWidget,
            reason: 'available=$available',
          );
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('message never contains a digit or a percent sign',
          (tester) async {
        for (final available in [0, 1, 24, 25, 49, 50, 74, 75, 99, 100]) {
          await _pumpRewards(tester,
              points: _points(available),
              products: [_product('a', 100, name: 'منتج')]);
          // Only the motivational message itself — the card also shows the
          // product's real cost ("100 نقطة"), which legitimately has a digit.
          final motivation = find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_ProductMotivation');
          final message = tester
              .widgetList<Text>(
                  find.descendant(of: motivation, matching: find.byType(Text)))
              .map((t) => t.data ?? '')
              .join(' ');
          expect(message, isNot(contains('%')));
          expect(RegExp(r'[0-9٠-٩]').hasMatch(message), isFalse,
              reason: 'available=$available: "$message"');
          await tester.pumpWidget(const SizedBox());
        }
      });

      testWidgets('hidden while the available balance is still loading',
          (tester) async {
        await _pumpRewards(tester,
            points: null, products: [_product('a', 100, name: 'منتج')]);
        expect(_barIn('منتج'), findsNothing);
        for (final m in [
          'رحلتك للمكافأة بتبدأ من هون!',
          'كل نقطة بتقرّبك من مكافأتك!',
          'مبروك! مكافأتك جاهزة للاستبدال',
        ]) {
          expect(find.text(m), findsNothing);
        }
      });

      testWidgets('hidden for a product with a pending request',
          (tester) async {
        await _pumpRewards(
          tester,
          points: _points(100),
          products: [_product('a', 100, name: 'منتج')],
          redemptions: [_red('r', RedemptionStatus.pending, productId: 'a')],
        );
        expect(_barIn('منتج'), findsNothing);
        expect(find.text('مبروك! مكافأتك جاهزة للاستبدال'), findsNothing);
        expect(find.byType(YcStatusChip), findsOneWidget);
      });

      testWidgets('hidden for an inactive product', (tester) async {
        await _pumpRewards(tester,
            points: _points(100),
            products: [_product('a', 100, name: 'منتج', active: false)]);
        expect(_barIn('منتج'), findsNothing);
        expect(find.text('مبروك! مكافأتك جاهزة للاستبدال'), findsNothing);
      });

      testWidgets(
          'crossfades when the message changes; instant under '
          'reduced motion', (tester) async {
        await _pumpRewards(tester,
            points: _points(10), products: [_product('a', 100, name: 'منتج')]);
        final switcher = tester.widget<AnimatedSwitcher>(find.descendant(
            of: cardFor('منتج'), matching: find.byType(AnimatedSwitcher)));
        expect(switcher.duration, const Duration(milliseconds: 250));
        expect(find.text('كل نقطة بتقرّبك من مكافأتك!'), findsOneWidget);

        final host = tester.state<_RewardsHostState>(find.byType(_RewardsHost));
        host.update(CustomerAppState(
          customer: host.state.customer,
          points: _points(100),
          products: host.state.products,
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 260));
        expect(find.text('مبروك! مكافأتك جاهزة للاستبدال'), findsOneWidget);
        expect(find.text('كل نقطة بتقرّبك من مكافأتك!'), findsNothing);
      });

      testWidgets(
          'reduced motion: new message still appears, with no '
          'animated transition', (tester) async {
        _reduceMotion(tester);
        await _pumpRewards(tester,
            points: _points(10), products: [_product('a', 100, name: 'منتج')]);
        final switcher = tester.widget<AnimatedSwitcher>(find.descendant(
            of: cardFor('منتج'), matching: find.byType(AnimatedSwitcher)));
        expect(switcher.duration, Duration.zero);

        final host = tester.state<_RewardsHostState>(find.byType(_RewardsHost));
        host.update(CustomerAppState(
          customer: host.state.customer,
          points: _points(100),
          products: host.state.products,
        ));
        await tester.pump();
        expect(find.text('مبروك! مكافأتك جاهزة للاستبدال'), findsOneWidget);
      });

      testWidgets('RTL: the message sits at the bar\'s start (right) edge',
          (tester) async {
        await _pumpRewards(tester,
            points: _points(10), products: [_product('a', 100, name: 'منتج')]);
        final cardRight = tester.getRect(cardFor('منتج')).right;
        // The group's own right edge (icon is first in the Row, so in RTL it
        // paints rightmost, ahead of the text) — not just the inner Text.
        final motivation = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_ProductMotivation');
        final messageRight = tester.getRect(motivation).right;
        // Starts near the card's own right edge (inside its padding), not
        // centred and not pinned to the left.
        expect(messageRight, closeTo(cardRight - YcSpace.md, 6));
      });

      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('${w}dp x$scale: product card fits with the message',
              (tester) async {
            await _pumpRewards(
              tester,
              points: _points(10),
              width: w,
              scale: scale,
              products: [
                _product('a', 100,
                    name:
                        'اسم منتج رقمي طويل جداً جداً لاختبار القص والتفاف النص'),
              ],
            );
            expect(tester.takeException(), isNull);
          });
        }
      }

      for (final b in Brightness.values) {
        testWidgets('$b: product card with the message renders cleanly',
            (tester) async {
          await _pumpRewards(tester,
              points: _points(10),
              brightness: b,
              products: [_product('a', 100, name: 'منتج')]);
          expect(tester.takeException(), isNull);
          expect(find.text('كل نقطة بتقرّبك من مكافأتك!'), findsOneWidget);
        });
      }
    });

    testWidgets('RTL: the bar fills from the right', (tester) async {
      await _pumpRewards(tester,
          points: _points(250), products: [_product('a', 1000, name: 'منتج')]);
      final track = tester.getRect(find.descendant(
          of: _barIn('منتج'), matching: find.byType(ClipRRect)));
      final fill = tester.getRect(find.descendant(
          of: _barIn('منتج'), matching: find.byType(FractionallySizedBox)));
      expect(fill.right, closeTo(track.right, .5));
      expect(fill.width, closeTo(track.width * .25, .5));
    });

    testWidgets(
        'first build shows the real value (no replayed fill); a '
        'change animates smoothly', (tester) async {
      await _pumpRewards(tester,
          points: _points(250), products: [_product('a', 1000, name: 'منتج')]);
      double fillFraction() {
        final track = tester.getRect(find.descendant(
            of: _barIn('منتج'), matching: find.byType(ClipRRect)));
        final fill = tester.getRect(find.descendant(
            of: _barIn('منتج'), matching: find.byType(FractionallySizedBox)));
        return fill.width / track.width;
      }

      expect(fillFraction(), closeTo(.25, .01));
      final host = tester.state<_RewardsHostState>(find.byType(_RewardsHost));
      host.update(CustomerAppState(
        customer: host.state.customer,
        points: _points(750),
        products: host.state.products,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = fillFraction();
      expect(mid, inExclusiveRange(.26, .74));
      await tester.pump(const Duration(milliseconds: 500));
      expect(fillFraction(), closeTo(.75, .01));
    });

    testWidgets('reduced motion: value changes apply at once', (tester) async {
      _reduceMotion(tester);
      await _pumpRewards(tester,
          points: _points(250), products: [_product('a', 1000, name: 'منتج')]);
      expect(
        find.descendant(
            of: _barIn('منتج'),
            matching: find.byType(TweenAnimationBuilder<double>)),
        findsNothing,
      );
      final host = tester.state<_RewardsHostState>(find.byType(_RewardsHost));
      host.update(CustomerAppState(
        customer: host.state.customer,
        points: _points(750),
        products: host.state.products,
      ));
      await tester.pump();
      expect(_barFor(tester, 'منتج').value, .75);
    });

    testWidgets('product image is uncropped (BoxFit.contain)', (tester) async {
      await _pumpRewards(tester, points: _points(10), products: [
        _product('a', 100,
            name: 'منتج', image: 'https://invalid.example/p.png'),
      ]);
      _onlyImageFailures(tester);
      final image = tester.widget<Image>(find.byType(Image).first);
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('redeem sends one request; double tap is ignored',
        (tester) async {
      final r = await _pumpRewards(tester,
          points: _points(1000), products: [_product('a', 100, name: 'منتج')]);
      r.repo.gate = Completer<void>(); // keep the request in flight
      final button = find.widgetWithText(FilledButton, 'استبدال');
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(_enabled(tester, button), isFalse);
      await tester.tap(button, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.repo.redeemed, ['a']);
      r.repo.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(r.repo.redeemed, ['a']);
      expect(_enabled(tester, button), isTrue);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('phone products still ask for a number; cancel sends nothing',
        (tester) async {
      final r = await _pumpRewards(tester,
          points: _points(1000),
          products: [_product('a', 100, name: 'رصيد', phone: true)]);
      await tester.tap(find.text('استبدال'));
      await tester.pumpAndSettle();
      expect(find.text('رقم الهاتف'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(r.repo.redeemed, isEmpty);
      // The button is usable again after cancelling.
      expect(_enabled(tester, find.widgetWithText(FilledButton, 'استبدال')),
          isTrue);
    });

    for (final b in Brightness.values) {
      for (final w in [320.0, 412.0]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets('$b ${w}dp x$scale: rewards page fits', (tester) async {
            await _pumpRewards(
              tester,
              points: _points(987654321, held: 1),
              brightness: b,
              width: w,
              scale: scale,
              products: [
                _product('a', 99999999,
                    name: 'اسم منتج رقمي طويل جداً لاختبار القص والتفاف النص'),
                _product('b', 100, name: 'منتج'),
              ],
              redemptions: [
                _red('r', RedemptionStatus.pending, productId: 'b')
              ],
            );
            await tester.enterText(find.byType(TextField), '999999999999');
            await tester.pump();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  // -------------------------------------------------------------------------
  group('shell integration', () {
    Future<void> pumpShell(WidgetTester tester, CustomerAppState state) async {
      _viewport(tester);
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
            status: state.status,
            customer: store.currentCustomer,
            points: state.points,
            transactions: state.transactions,
          ),
          repository: repo,
          darkMode: false,
          onDarkModeChanged: (_) {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
    }

    double revealOpacity(WidgetTester tester, Type page) => tester
        .widget<Opacity>(find
            .ancestor(
              of: find.byType(page, skipOffstage: false),
              matching: find.byType(Opacity, skipOffstage: false),
            )
            .first)
        .opacity;

    testWidgets('wallet shows placeholders until data arrives', (tester) async {
      await pumpShell(tester, const CustomerAppState());
      await tester.tap(find.text('المحفظة'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(YcSkeleton), findsNWidgets(3));
      expect(find.text('لا توجد عمليات حتى الآن'), findsNothing);
    });

    testWidgets('shell passes the cash requests to the wallet', (tester) async {
      _viewport(tester);
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
            points: _points(10),
            cashRequests: [
              CashRedemptionRequest(
                id: 'r',
                customerId: 'c',
                pointsRequested: 70,
                cashValueSyp: 350,
                status: CashRequestStatus.pending,
                createdAt: _t0,
              ),
            ],
          ),
          repository: repo,
          darkMode: false,
          onDarkModeChanged: (_) {},
        ),
      ));
      await tester.tap(find.text('المحفظة'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('350 ل.س'), findsOneWidget);
      expect(find.text('قيد المعالجة'), findsOneWidget);
    });

    testWidgets('wallet shows the retry state when loading failed',
        (tester) async {
      await pumpShell(
          tester, const CustomerAppState(status: LoadStatus.failure));
      await tester.tap(find.text('المحفظة'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('تعذر تحميل السجل'), findsOneWidget);
    });

    testWidgets('wallet reveals on first visit only, never on return',
        (tester) async {
      await pumpShell(tester, CustomerAppState(points: _points(10)));
      expect(revealOpacity(tester, CustomerWalletPage), 0);
      await tester.tap(find.text('المحفظة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(revealOpacity(tester, CustomerWalletPage), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 500));
      expect(revealOpacity(tester, CustomerWalletPage), 1);
      await tester.tap(find.text('الرئيسية'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('المحفظة'));
      await tester.pump();
      expect(revealOpacity(tester, CustomerWalletPage), 1);
    });

    testWidgets('reduced motion: wallet appears at once', (tester) async {
      _reduceMotion(tester);
      await pumpShell(tester, CustomerAppState(points: _points(10)));
      await tester.tap(find.text('المحفظة'));
      await tester.pump();
      expect(revealOpacity(tester, CustomerWalletPage), 1);
    });

    testWidgets('store tab keeps typed text across tab switches',
        (tester) async {
      await pumpShell(tester, CustomerAppState(points: _points(1000)));
      await tester.tap(find.text('المتجر'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), '42');
      await tester.tap(find.text('الرئيسية'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('المتجر'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('42'), findsOneWidget);
    });
  });
}
