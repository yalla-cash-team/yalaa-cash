import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Banner;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/logo_trim.dart';

import 'support/fake_image_http.dart';

/// Regression: a store logo that loads fine on the Home card must stay
/// visible on StoreDetailsPage (after the Hero flight) and again on the card
/// after coming back. Uses real, served image bytes: a store without a logo
/// URL (as in the older Hero test) never exercises this path.

const _url = 'https://cdn.example/stores/logo.png';

/// Serves the logo and counts how many times it was requested from the
/// "network". A logo already on screen must come from the image cache.
class _CountingClient extends FakeImageHttpClient {
  _CountingClient(super.images);

  int requests = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests++;
    return super.getUrl(url);
  }
}

PartnerStore _store() => const PartnerStore(
      id: 's1',
      name: 'مطعم الأصالة',
      category: 'مطاعم',
      commissionRate: 5,
      description: 'وصف المحل',
      location: 'الموصل',
      iconSeed: 0,
      governorateId: 'g1',
      logoUrl: _url,
    );

/// A small mark in the middle of a large white canvas, so the Home card's
/// whitespace trimming really applies.
Future<Uint8List> _logoBytes(WidgetTester tester) async =>
    (await tester.runAsync(() => drawPng(600, 600, (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = Colors.white);
          c.drawRect(const Rect.fromLTWH(240, 240, 120, 120),
              Paint()..color = const Color(0xFF1B4965));
        })))!;

/// Lets image futures (real async) and animation frames both advance.
Future<void> _advance(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpHome(WidgetTester tester, {double width = 412}) async {
  tester.view.physicalSize = Size(width * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final store = YallaCashStore.demo()..loginDemoCustomer();
  addTearDown(store.dispose);
  final cubit = CustomerAppCubit(InMemoryYallaCashRepository(store));
  addTearDown(cubit.close);
  await tester.pumpWidget(MaterialApp(
    theme: customerLightTheme,
    darkTheme: customerDarkTheme,
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(
      body: CustomerHomePage(
        cubit: cubit,
        state: CustomerAppState(
          customer: store.currentCustomer,
          stores: [_store()],
        ),
        customer: store.currentCustomer!,
      ),
    ),
  ));
  await _advance(tester);
}

final _card =
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_StoreCard');

/// The decoded logo pixels shown inside the Hero under [scope], plus every
/// opacity that dims them. Fails the test when the logo is not painted.
void _expectLogoVisible(WidgetTester tester, Finder scope, String where) {
  final hero = find.descendant(of: scope, matching: find.byType(Hero));
  expect(hero, findsOneWidget, reason: '$where: logo Hero present');
  final raw = find.descendant(of: hero, matching: find.byType(RawImage));
  expect(raw, findsOneWidget, reason: '$where: the logo image is mounted');
  expect(tester.widget<RawImage>(raw).image, isNotNull,
      reason: '$where: the logo image is decoded and painted');
  expect(tester.getSize(raw).shortestSide, greaterThan(8),
      reason: '$where: the logo has a real size');
  // Nothing above the image may leave it faded out.
  for (final o in find
      .ancestor(of: raw, matching: find.byType(Opacity))
      .evaluate()
      .map((e) => e.widget as Opacity)) {
    expect(o.opacity, 1, reason: '$where: logo fully opaque');
  }
  // And it must not have fallen back to the storefront placeholder icon.
  expect(
      find.descendant(
          of: hero, matching: find.byIcon(Icons.storefront_rounded)),
      findsNothing,
      reason: '$where: no placeholder in place of the logo');
}

/// Advances animation frames only: no real time passes, so nothing that is
/// not already decoded in the image cache can finish loading.
Future<void> _framesOnly(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  tearDown(WhitespaceTrimmedLogo.clearCache);

  for (final width in [412.0, 320.0]) {
    testWidgets(
        '${width}dp: the logo stays visible on the card, on the details page '
        'and on the card after returning, from the image cache',
        (tester) async {
      WhitespaceTrimmedLogo.clearCache();
      // The image cache is process-wide: start every run cold.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      final bytes = await _logoBytes(tester);
      final client = _CountingClient({_url: bytes});
      painting.debugNetworkImageHttpClientProvider = () => client;
      try {
        await _pumpHome(tester, width: width);
        _expectLogoVisible(tester, _card, 'home card before opening');
        final loaded = client.requests;
        expect(loaded, 1, reason: 'the card downloads the logo once');

        await tester.tap(find.text('مطعم الأصالة'));
        await tester.pump();
        // The whole Hero flight and settle, without letting any new image
        // load finish: the logo is already cached, so it must simply be there.
        await _framesOnly(tester, frames: 12);
        expect(find.byType(StoreDetailsPage), findsOneWidget);
        _expectLogoVisible(tester, find.byType(StoreDetailsPage),
            'details page right after the flight');

        await tester.pageBack();
        await tester.pump();
        await _framesOnly(tester, frames: 12);
        expect(find.byType(StoreDetailsPage), findsNothing);
        _expectLogoVisible(tester, _card, 'home card right after returning');

        // Let anything still pending finish, then check again.
        await _advance(tester);
        _expectLogoVisible(tester, _card, 'home card once settled');
        expect(client.requests, loaded,
            reason: 'opening the details page must not download or decode '
                'the same logo again under a different cache key');
      } finally {
        painting.debugNetworkImageHttpClientProvider = null;
      }
    });
  }
}
