// Landing-page screenshot harness.
//
// Renders the REAL Customer app shell (CustomerShell, real theme, real
// Almarai family from the app's pubspec) and exports the Home and Wallet tabs
// as PNGs. Only the data is seeded: the app's built-in demo stores
// (YallaCashStore.demo) plus a few loyalty transactions, so nothing about the
// UI itself is mocked or drawn by hand.
//
// It is NOT part of the app. Copy it temporarily into the customer app's test
// folder under a git-ignored name, run it, then delete the copy:
//
//   cp docs/landing-page/tools/landing_shots_test.dart \
//      apps/yalla_cash_customer/test/_tmp_landing_shots_test.dart
//   cd apps/yalla_cash_customer
//   flutter test test/_tmp_landing_shots_test.dart --dart-define=OUT=<abs dir>
//   rm test/_tmp_landing_shots_test.dart
//
// Skipped unless OUT is defined.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Banner;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';

const _out = String.fromEnvironment('OUT');

// ---- fake HTTP, only to serve the banner image to Image.network -------------
class _Client implements HttpClient {
  _Client(this.images);
  final Map<String, Uint8List> images;
  @override
  bool autoUncompress = true;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(images[url.toString()]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Request implements HttpClientRequest {
  _Request(this.bytes);
  final Uint8List? bytes;
  @override
  HttpHeaders get headers => _Headers();
  @override
  Future<HttpClientResponse> close() async => _Response(bytes);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Headers implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes);
  final Uint8List? bytes;
  @override
  int get statusCode => bytes == null ? 404 : 200;
  @override
  int get contentLength => bytes?.length ?? 0;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.fromIterable(bytes == null ? const [] : [bytes!])
          .listen(onData,
              onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A plain brand banner: the app's navy→blue gradient with the real mark.
Future<Uint8List> _bannerPng() async {
  const w = 1200, h = 500;
  final mark = await ui.instantiateImageCodec(File(
          '../../packages/yalla_cash_core/assets/images/yalla_cash_mark.png')
      .readAsBytesSync());
  final markImage = (await mark.getNextFrame()).image;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const size = Size(w * 1.0, h * 1.0);
  c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [Color(0xFF0E2A3B), Color(0xFF0B7EB0), Color(0xFF1EA7E0)],
        ).createShader(Offset.zero & size));
  const mh = 330.0;
  final mw = mh * markImage.width / markImage.height;
  c.drawImageRect(
      markImage,
      Rect.fromLTWH(
          0, 0, markImage.width.toDouble(), markImage.height.toDouble()),
      Rect.fromLTWH(w * 0.12, (h - mh) / 2, mw, mh),
      Paint()..filterQuality = FilterQuality.high);
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _icons() async {
  // flutter test does not auto-load the app's pubspec fonts, so load the real
  // four-weight Almarai family explicitly (otherwise text renders as boxes).
  final almarai = FontLoader('Almarai');
  for (final w in ['Light', 'Regular', 'Bold', 'ExtraBold']) {
    almarai.addFont(Future.value(ByteData.sublistView(
        File('assets/fonts/Almarai-$w.ttf').readAsBytesSync())));
  }
  await almarai.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File(
            'C:/src/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
        .readAsBytesSync())));
  await icons.load();
}

final _key = GlobalKey();

LoyaltyTransaction _tx(String id, String storeId, String name, int amount,
        int points, DateTime at) =>
    LoyaltyTransaction(
      id: id,
      storeId: storeId,
      storeName: name,
      customerId: 'c1',
      amountSyp: amount,
      commissionRateSnapshot: 5,
      commissionAmountSyp: 0,
      platformRevenueSyp: 0,
      customerShareSyp: 0,
      customerPointsEarned: points,
      createdAt: at,
    );

Future<void> _shot(WidgetTester tester, String name,
    {Future<void> Function(WidgetTester)? then}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final banner = await tester.runAsync(_bannerPng);
  painting.debugNetworkImageHttpClientProvider =
      () => _Client({'https://banner.test/b.png': banner!});
  await tester.runAsync(_icons);

  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final repo = InMemoryYallaCashRepository(store);
  const points = PointsSummary(
      pointsBalance: 1250, heldPoints: 0, availablePoints: 1250);
  final customer = Customer(
    id: 'c1',
    name: 'أحمد',
    governorate: 'دمشق',
    pointsBalance: points.pointsBalance,
    createdAt: DateTime(2026),
  );
  final now = DateTime(2026, 11, 18, 18, 30);
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildCustomerTheme(Brightness.light),
      themeMode: ThemeMode.light,
      builder: (c, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: CustomerShell(
        cubit: CustomerAppCubit(repo),
        state: CustomerAppState(
          status: LoadStatus.success,
          customer: customer,
          points: points,
          banners: [
            Banner(
              id: 'b1',
              title: 'يلا كاش',
              imageUrl: 'https://banner.test/b.png',
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
          // The app's own demo partner stores (no logos: real fallback).
          stores: store.stores.where((s) => s.governorateId == 'gov-damascus').toList(),
          transactions: [
            _tx('t1', 'store-001', 'مطعم الوسيم', 85000, 210,
                now.subtract(const Duration(days: 1))),
            _tx('t2', 'store-002', 'ماركت البركة', 140000, 320,
                now.subtract(const Duration(days: 3))),
            _tx('t3', 'store-003', 'كافيه الزاوية', 36000, 120,
                now.subtract(const Duration(days: 5))),
            _tx('t4', 'store-001', 'مطعم الوسيم', 62000, 150,
                now.subtract(const Duration(days: 9))),
            _tx('t5', 'store-002', 'ماركت البركة', 98000, 450,
                now.subtract(const Duration(days: 12))),
          ],
        ),
        repository: repo,
        darkMode: false,
        onDarkModeChanged: (_) {},
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 600));
  if (then != null) {
    await then(tester);
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
  final boundary =
      tester.renderObject(find.byKey(_key)) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  painting.debugNetworkImageHttpClientProvider = null;
}

void main() {
  group('landing screenshots', () {
    testWidgets('home', (t) => _shot(t, 'home'));
    testWidgets(
        'wallet',
        (t) => _shot(t, 'wallet',
            then: (t) async => t.tap(find.text('المحفظة'))));
  }, skip: _out.isEmpty ? 'pass --dart-define=OUT=<abs dir>' : false);
}
