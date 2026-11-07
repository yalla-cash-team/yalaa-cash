import 'dart:async';

import 'package:flutter/material.dart' hide Banner;
import 'package:flutter/painting.dart' as painting;
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';

import 'support/fake_image_http.dart';

const _instruction = 'أبرز تطبيق يلا كاش عند المحاسبة للاستفادة من العرض';

/// Customer offers answered from per-store queues: a list, a failure or a
/// pending completer. Falls back to the in-memory behaviour.
class _OffersRepository extends InMemoryYallaCashRepository {
  _OffersRepository(super.store);

  final queues = <String, List<Object>>{};
  final calls = <String>[];

  void answer(String storeId, Object response) =>
      (queues[storeId] ??= []).add(response);

  @override
  Future<List<StoreOffer>> listStoreOffers(String storeId) async {
    calls.add(storeId);
    final queue = queues[storeId];
    if (queue == null || queue.isEmpty) return super.listStoreOffers(storeId);
    final next = queue.removeAt(0);
    if (next is Completer<List<StoreOffer>>) return next.future;
    if (next is YallaCashFailure) throw next;
    return next as List<StoreOffer>;
  }
}

StoreOffer _offer(
  String id, {
  required String storeId,
  String? title,
  String? label,
  String description = '',
  OfferCalendarDate? endDate,
  DateTime? startsAt,
  DateTime? endsBefore,
  String? imageUrl,
  OfferImageAccess access = OfferImageAccess.public,
}) =>
    StoreOffer(
      id: id,
      storeId: storeId,
      title: title ?? 'عرض $id',
      discountLabel: label,
      description: description,
      endDate: endDate,
      startsAt: startsAt,
      endsBefore: endsBefore,
      imageUrl: imageUrl,
      imageAccess: access,
    );

void main() {
  late YallaCashStore store;
  late PartnerStore partner;
  late PartnerStore other;

  setUp(() {
    store = YallaCashStore.demo();
    partner = store.stores[0];
    other = store.stores[1];
  });

  Future<CustomerAppCubit> pumpDetails(
    WidgetTester tester,
    YallaCashRepository repository, {
    CustomerAppCubit? cubit,
    PartnerStore? shown,
    Brightness brightness = Brightness.light,
    double width = 390,
    double textScale = 1,
    bool reduceMotion = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width * 2, 4400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final appCubit = cubit ?? CustomerAppCubit(repository);
    addTearDown(appCubit.close);
    await tester.pumpWidget(MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      darkTheme: buildCustomerTheme(Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: StoreDetailsPage(store: shown ?? partner, cubit: appCubit),
    ));
    if (settle) await tester.pumpAndSettle();
    return appCubit;
  }

  Finder networkImages() => find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is NetworkImage);

  testWidgets('shows a real offer card, view-only, with the instruction',
      (tester) async {
    final repository = _OffersRepository(store)
      ..answer(partner.id, [
        _offer('o1',
            storeId: partner.id,
            title: 'خصم الشتاء',
            label: 'خصم 20%',
            description: 'على جميع المعاطف',
            endDate: OfferCalendarDate(2099, 11, 30),
            endsBefore: DateTime.utc(2099, 11, 30, 21)),
      ]);

    await pumpDetails(tester, repository);

    expect(repository.calls, [partner.id]);
    expect(find.text('خصم الشتاء'), findsOneWidget);
    expect(find.text('خصم 20%'), findsOneWidget);
    expect(find.text('على جميع المعاطف'), findsOneWidget);
    expect(find.text('ساري حتى 30 تشرين الثاني 2099'), findsOneWidget);
    expect(find.text(_instruction), findsOneWidget);
    expect(find.text('لا توجد عروض متاحة حالياً'), findsNothing);
    // View-only: no buttons at all (no coupon, QR, points or purchase).
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('keeps the header, logo Hero and store information',
      (tester) async {
    await pumpDetails(tester, _OffersRepository(store));

    expect(find.text(partner.name), findsOneWidget);
    expect(find.text(partner.category), findsOneWidget);
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'store-logo-${partner.id}');
  });

  testWidgets('only currently valid offers are shown (exclusive endsBefore)',
      (tester) async {
    final now = DateTime.now().toUtc();
    final repository = _OffersRepository(store)
      ..answer(partner.id, [
        // The API always sends both forms: the inclusive day and the
        // exclusive instant.
        _offer('valid',
            storeId: partner.id,
            endDate: OfferCalendarDate(2099, 12, 31),
            endsBefore: now.add(const Duration(days: 1))),
        _offer('open', storeId: partner.id),
        // endsBefore is exclusive: at or after it the offer is over.
        _offer('expired', storeId: partner.id,
            endsBefore: now.subtract(const Duration(seconds: 1))),
        _offer('scheduled', storeId: partner.id,
            startsAt: now.add(const Duration(days: 1))),
      ]);

    await pumpDetails(tester, repository);

    expect(find.text('عرض valid'), findsOneWidget);
    expect(find.text('عرض open'), findsOneWidget);
    expect(find.text('عرض مستمر'), findsOneWidget);
    expect(find.text('عرض expired'), findsNothing);
    expect(find.text('عرض scheduled'), findsNothing);
  });

  testWidgets('an offer disappears at endsBefore while the page is open',
      (tester) async {
    final repository = _OffersRepository(store)
      ..answer(partner.id, [
        _offer('soon', storeId: partner.id,
            endsBefore:
                DateTime.now().toUtc().add(const Duration(milliseconds: 400))),
      ]);
    await pumpDetails(tester, repository);
    expect(find.text('عرض soon'), findsOneWidget);

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('عرض soon'), findsNothing);
    expect(find.text('لا توجد عروض متاحة حالياً'), findsOneWidget);
  });

  testWidgets('real in-memory flow: active shown; inactive and expired hidden',
      (tester) async {
    final repository = InMemoryYallaCashRepository(store);
    await repository.createOffer(
        partner.id, const StoreOfferDraft(title: 'عرض فعال'));
    await repository.createOffer(partner.id,
        const StoreOfferDraft(title: 'عرض متوقف', isActive: false));
    await repository.createOffer(
        partner.id,
        StoreOfferDraft(
            title: 'عرض منتهي', endDate: OfferCalendarDate(2020, 1, 1)));

    await pumpDetails(tester, repository);

    expect(find.text('عرض فعال'), findsOneWidget);
    expect(find.text('عرض متوقف'), findsNothing);
    expect(find.text('عرض منتهي'), findsNothing);
  });

  testWidgets('empty state when the store has no offers', (tester) async {
    await pumpDetails(tester, _OffersRepository(store));

    expect(find.text('لا توجد عروض متاحة حالياً'), findsOneWidget);
    expect(find.text(_instruction), findsNothing);
  });

  testWidgets('an inactive store (404) shows the empty state, not an error',
      (tester) async {
    store.deleteStore(partner.id);
    await pumpDetails(tester, InMemoryYallaCashRepository(store));

    expect(find.text('لا توجد عروض متاحة حالياً'), findsOneWidget);
    expect(find.text('تعذر تحميل العروض'), findsNothing);
  });

  testWidgets('loading, then error, then retry', (tester) async {
    final pending = Completer<List<StoreOffer>>();
    final repository = _OffersRepository(store)
      ..answer(partner.id, pending)
      ..answer(partner.id, [_offer('back', storeId: partner.id)]);

    final semantics = tester.ensureSemantics();
    await pumpDetails(tester, repository, settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // fade-in done
    expect(find.byKey(const ValueKey('store-offers-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('جارٍ تحميل العروض'), findsOneWidget);
    semantics.dispose();

    pending.completeError(const YallaCashFailure(
        code: 'network_unavailable', message: 'تعذر الاتصال بالخادم.'));
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل العروض'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(repository.calls, [partner.id, partner.id]);
    expect(find.text('عرض back'), findsOneWidget);
    expect(find.text('تعذر تحميل العروض'), findsNothing);
  });

  testWidgets("never shows another store's offers", (tester) async {
    final repository = _OffersRepository(store)
      ..answer(other.id, [_offer('b1', storeId: other.id)])
      ..answer(partner.id, [
        _offer('a1', storeId: partner.id),
        // Mis-associated item in this store's response: never shown.
        _offer('b2', storeId: other.id),
      ]);
    final cubit = CustomerAppCubit(repository);
    // The other store's offers are already in the Cubit.
    await cubit.loadStoreOffers(other.id);

    await pumpDetails(tester, repository, cubit: cubit);

    expect(find.text('عرض a1'), findsOneWidget);
    expect(find.text('عرض b1'), findsNothing);
    expect(find.text('عرض b2'), findsNothing);
  });

  testWidgets('a late response for another store does not change this page',
      (tester) async {
    final otherPending = Completer<List<StoreOffer>>();
    final repository = _OffersRepository(store)
      ..answer(other.id, otherPending)
      ..answer(partner.id, const <StoreOffer>[]);
    final cubit = CustomerAppCubit(repository);
    unawaited(cubit.loadStoreOffers(other.id)); // e.g. a page just left

    await pumpDetails(tester, repository, cubit: cubit);
    otherPending.complete([_offer('late', storeId: other.id)]);
    await tester.pumpAndSettle();

    expect(find.text('عرض late'), findsNothing);
    expect(find.text('لا توجد عروض متاحة حالياً'), findsOneWidget);
  });

  testWidgets('public image is shown whole (uncropped, aspect preserved)',
      (tester) async {
    const url = 'https://api.test/offers/o1/image?v=3';
    final bytes = (await tester.runAsync(() => drawPng(400, 200, (c, s) {
          c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF1B4965));
        })))!;
    painting.debugNetworkImageHttpClientProvider =
        () => FakeImageHttpClient({url: bytes});
    final repository = _OffersRepository(store)
      ..answer(partner.id, [
        _offer('o1', storeId: partner.id, title: 'عرض مصور', imageUrl: url),
      ]);

    await pumpDetails(tester, repository);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    final image = tester.widget<Image>(networkImages());
    expect((image.image as NetworkImage).url, url); // version kept
    expect(image.fit, BoxFit.contain);
    final size = tester.getSize(
        find.descendant(of: networkImages(), matching: find.byType(RawImage)));
    expect(size.width / size.height, closeTo(2, .02));

    await tester.pumpWidget(const SizedBox());
    painting.debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('admin-only or relative image URLs are never loaded',
      (tester) async {
    final repository = _OffersRepository(store)
      ..answer(partner.id, [
        _offer('admin', storeId: partner.id,
            imageUrl: 'https://api.test/admin/offers/admin/image?v=1',
            access: OfferImageAccess.adminPreview),
        _offer('relative', storeId: partner.id,
            imageUrl: '/offers/relative/image?v=1'),
      ]);

    await pumpDetails(tester, repository);

    expect(find.text('عرض admin'), findsOneWidget);
    expect(find.text('عرض relative'), findsOneWidget);
    expect(networkImages(), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('320dp, large text, ${brightness.name} mode: no overflow',
        (tester) async {
      final repository = _OffersRepository(store)
        ..answer(partner.id, [
          _offer('long',
              storeId: partner.id,
              title: 'عرض بعنوان طويل جداً لاختبار الالتفاف في الشاشات الصغيرة',
              label: 'خصم 25% على كل المشتريات',
              description: 'وصف طويل ' * 12,
              endDate: OfferCalendarDate(2099, 1, 31),
              endsBefore: DateTime.utc(2099, 1, 31, 21)),
        ]);

      await pumpDetails(tester, repository,
          width: 320, textScale: 2, brightness: brightness);

      expect(tester.takeException(), isNull);
      expect(find.text(_instruction), findsOneWidget);
    });
  }

  testWidgets('reduced motion: offers appear without running animations',
      (tester) async {
    final repository = _OffersRepository(store)
      ..answer(partner.id, [_offer('calm', storeId: partner.id)]);

    await pumpDetails(tester, repository, reduceMotion: true, settle: false);
    await tester.pump();
    await tester.pump();

    expect(find.text('عرض calm'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
