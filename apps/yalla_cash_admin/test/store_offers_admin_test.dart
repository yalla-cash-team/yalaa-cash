import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_admin/src/admin_app.dart';
import 'package:yalla_cash_admin/src/store_offers_admin.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' hide Banner;

/// A valid 1x1 PNG.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
const _pngUpload = StoreLogoUpload(bytes: _png, contentType: 'image/png');

/// In-memory repository with hooks for failures, delays and call counts.
class _TestRepository extends InMemoryYallaCashRepository {
  _TestRepository(super.store, {super.clock});

  var createCalls = 0;
  var imageDownloads = 0;
  var failImageUpload = false;
  Completer<void>? holdCreate;
  final listFailures = <YallaCashFailure>[];
  Completer<void>? holdList;

  @override
  Future<StoreOffer> createOffer(String storeId, StoreOfferDraft draft) async {
    createCalls += 1;
    await holdCreate?.future;
    return super.createOffer(storeId, draft);
  }

  @override
  Future<StoreOffer> setOfferImage(String offerId, StoreLogoUpload image) {
    if (failImageUpload) {
      return Future.error(const YallaCashFailure(
          statusCode: 400, code: 'bad_request', message: 'توقيع الصورة غير صالح'));
    }
    return super.setOfferImage(offerId, image);
  }

  @override
  Future<List<StoreOffer>> listAdminStoreOffers(String storeId) async {
    await holdList?.future;
    if (listFailures.isNotEmpty) throw listFailures.removeAt(0);
    return super.listAdminStoreOffers(storeId);
  }

  @override
  Future<OfferImageData> fetchAdminOfferImage(String offerId,
      {int? imageVersion}) {
    imageDownloads += 1;
    return super.fetchAdminOfferImage(offerId, imageVersion: imageVersion);
  }
}

void main() {
  late YallaCashStore store;
  late PartnerStore partner;

  setUp(() {
    store = YallaCashStore.demo();
    partner = store.stores.first;
  });

  void largeScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(Widget home) => MaterialApp(
        theme: buildYallaTheme(Brightness.light),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  Future<AdminAppCubit> pumpPage(
    WidgetTester tester,
    _TestRepository repository, {
    OfferImagePicker? pickImage,
    bool settle = true,
  }) async {
    largeScreen(tester);
    final cubit = AdminAppCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(app(StoreOffersAdminPage(
      cubit: cubit,
      repository: repository,
      store: partner,
      pickImage: pickImage ?? () async => (image: null, error: null),
    )));
    if (settle) await tester.pumpAndSettle();
    return cubit;
  }

  Finder imageWidgetsFromNetwork() => find.byWidgetPredicate(
      (widget) => widget is Image && widget.image is NetworkImage);

  testWidgets('store card has an العروض button that opens the store offers',
      (tester) async {
    largeScreen(tester);
    final repository = _TestRepository(store);
    final cubit = AdminAppCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(app(Scaffold(
      body: StoresAdmin(
          cubit: cubit, stores: store.stores, repository: repository),
    )));

    await tester.tap(find.text('العروض').first);
    await tester.pumpAndSettle();

    expect(find.text('عروض ${partner.name}'), findsOneWidget);
    expect(find.text('لا توجد عروض لهذا المحل بعد'), findsOneWidget);
  });

  testWidgets('shows real offers with Damascus dates and status chips',
      (tester) async {
    final repository =
        _TestRepository(store, clock: () => DateTime.utc(2026, 11, 15, 12));
    Future<void> add(String title,
            {OfferCalendarDate? start,
            OfferCalendarDate? end,
            bool active = true}) =>
        repository.createOffer(
            partner.id,
            StoreOfferDraft(
                title: title,
                startDate: start,
                endDate: end,
                isActive: active,
                discountLabel: title == 'عرض نوفمبر' ? 'خصم 20%' : null));
    await add('عرض نوفمبر',
        start: OfferCalendarDate(2026, 11, 1),
        end: OfferCalendarDate(2026, 11, 30));
    await add('عرض ديسمبر', start: OfferCalendarDate(2026, 12, 1));
    await add('عرض أكتوبر', end: OfferCalendarDate(2026, 10, 31));
    await add('عرض موقوف', active: false);

    await pumpPage(tester, repository);

    for (final label in ['نشط', 'مجدول', 'منتهي', 'متوقف']) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(find.text('$label 1'), findsOneWidget, reason: 'summary $label');
    }
    expect(find.text('4 عروض'), findsOneWidget);
    expect(find.text('من 2026-11-01 إلى 2026-11-30'), findsOneWidget);
    expect(find.text('من 2026-12-01'), findsOneWidget);
    expect(find.text('حتى 2026-10-31'), findsOneWidget);
    expect(find.text('بدون تاريخ محدد'), findsOneWidget);
    expect(find.text('خصم 20%'), findsOneWidget);
  });

  testWidgets('loading, error and retry states', (tester) async {
    final repository = _TestRepository(store)
      ..holdList = Completer<void>()
      ..listFailures.add(const YallaCashFailure(message: 'الخادم غير متاح'));

    await pumpPage(tester, repository, settle: false);
    await tester.pump();
    expect(find.byKey(const Key('offers-loading')), findsOneWidget);

    repository.holdList!.complete();
    await tester.pumpAndSettle();
    expect(find.text('تعذر تحميل العروض'), findsOneWidget);
    expect(find.text('الخادم غير متاح'), findsOneWidget);

    await repository.createOffer(
        partner.id, const StoreOfferDraft(title: 'بعد الإصلاح'));
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();

    expect(find.text('بعد الإصلاح'), findsOneWidget);
    expect(find.text('تعذر تحميل العروض'), findsNothing);
  });

  testWidgets('create: validation, image upload and inactive switch',
      (tester) async {
    final repository = _TestRepository(store);
    await pumpPage(tester, repository,
        pickImage: () async => (image: _pngUpload, error: null));

    await tester.tap(find.text('إضافة أول عرض'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();
    expect(find.text('العنوان يجب أن يكون بين 2 و120 حرفاً.'), findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.enterText(find.byKey(const Key('offer-title')), 'عرض الافتتاح');
    await tester.enterText(find.byKey(const Key('offer-label')), 'خصم 15%');
    await tester.enterText(find.byKey(const Key('offer-order')), '3');
    await tester.tap(find.byKey(const Key('offer-pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-active')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();

    expect(find.byType(OfferEditorDialog), findsNothing);
    expect(find.text('تمت إضافة العرض.'), findsOneWidget);
    final saved = (await repository.listAdminStoreOffers(partner.id)).single;
    expect(saved.title, 'عرض الافتتاح');
    expect(saved.discountLabel, 'خصم 15%');
    expect(saved.displayOrder, 3);
    expect(saved.isActive, isFalse);
    expect(saved.imageVersion, 1);
    expect(find.text('عرض الافتتاح'), findsOneWidget);
    expect(find.text('متوقف'), findsOneWidget);
  });

  testWidgets('a second tap while saving does not submit twice',
      (tester) async {
    final repository = _TestRepository(store)..holdCreate = Completer<void>();
    await pumpPage(tester, repository);

    await tester.tap(find.text('إضافة عرض'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('offer-title')), 'مرة واحدة');
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('offer-save')), warnIfMissed: false);
    await tester.pump();

    repository.holdCreate!.complete();
    await tester.pumpAndSettle();

    expect(repository.createCalls, 1);
    expect(await repository.listAdminStoreOffers(partner.id), hasLength(1));
  });

  testWidgets('partial failure: offer created, image retried without a duplicate',
      (tester) async {
    final repository = _TestRepository(store)..failImageUpload = true;
    await pumpPage(tester, repository,
        pickImage: () async => (image: _pngUpload, error: null));

    await tester.tap(find.text('إضافة عرض'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('offer-title')), 'عرض بصورة');
    await tester.tap(find.byKey(const Key('offer-pick-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();

    // The dialog stays open, explains the partial success and edits the
    // created offer from now on.
    expect(find.byType(OfferEditorDialog), findsOneWidget);
    expect(find.textContaining('تم إنشاء العرض، لكن تعذر رفع الصورة'),
        findsOneWidget);
    expect(find.text('تعديل العرض'), findsOneWidget);
    expect(await repository.listAdminStoreOffers(partner.id), hasLength(1));

    repository.failImageUpload = false;
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();

    expect(find.byType(OfferEditorDialog), findsNothing);
    expect(repository.createCalls, 1);
    final offers = await repository.listAdminStoreOffers(partner.id);
    expect(offers.single.imageVersion, 1);
    expect(offers.single.hasImage, isTrue);
  });

  testWidgets('activate and deactivate', (tester) async {
    final repository = _TestRepository(store);
    await repository.createOffer(
        partner.id, const StoreOfferDraft(title: 'عرض دائم'));
    await pumpPage(tester, repository);
    expect(find.text('نشط'), findsOneWidget);

    await tester.tap(find.text('إيقاف'));
    await tester.pumpAndSettle();
    expect(find.text('متوقف'), findsOneWidget);
    expect(
        (await repository.listAdminStoreOffers(partner.id)).single.isActive,
        isFalse);

    await tester.tap(find.text('تفعيل'));
    await tester.pumpAndSettle();
    expect(find.text('نشط'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation', (tester) async {
    final repository = _TestRepository(store);
    await repository.createOffer(
        partner.id, const StoreOfferDraft(title: 'عرض للحذف'));
    await pumpPage(tester, repository);

    await tester.tap(find.byTooltip('حذف العرض'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.text('عرض للحذف'), findsOneWidget);

    await tester.tap(find.byTooltip('حذف العرض'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'حذف العرض'));
    await tester.pumpAndSettle();

    expect(find.text('عرض للحذف'), findsNothing);
    expect(find.text('لا توجد عروض لهذا المحل بعد'), findsOneWidget);
    expect(await repository.listAdminStoreOffers(partner.id), isEmpty);
  });

  testWidgets(
      'images use the authenticated preview; edit can remove the image',
      (tester) async {
    final repository = _TestRepository(store);
    final offer = await repository.createOffer(
        partner.id, const StoreOfferDraft(title: 'عرض مصور'));
    await repository.setOfferImage(offer.id, _pngUpload);
    await pumpPage(tester, repository);

    expect(repository.imageDownloads, 1);
    expect(find.byType(AdminOfferImage), findsOneWidget);
    expect(imageWidgetsFromNetwork(), findsNothing);

    await tester.tap(find.text('تعديل'));
    await tester.pumpAndSettle();
    expect(imageWidgetsFromNetwork(), findsNothing);
    await tester.tap(find.byKey(const Key('offer-remove-image')));
    await tester.enterText(find.byKey(const Key('offer-title')), 'عرض معدل');
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();

    final saved = (await repository.listAdminStoreOffers(partner.id)).single;
    expect(saved.title, 'عرض معدل');
    expect(saved.hasImage, isFalse);
    expect(saved.imageVersion, 2);
    expect(find.text('تم حفظ التعديلات.'), findsOneWidget);
  });

  testWidgets('date-only picking; end before start is blocked',
      (tester) async {
    final repository = _TestRepository(store);
    await pumpPage(tester, repository);
    final now = DateTime.now();

    await tester.tap(find.text('إضافة عرض'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('offer-title')), 'عرض مؤقت');

    Future<void> pick(Key field, String day) async {
      await tester.tap(find.descendant(
          of: find.byKey(field), matching: find.text('بلا تاريخ')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(day));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await pick(const Key('offer-start-date'), '20');
    await pick(const Key('offer-end-date'), '10');
    expect(find.text('تاريخ النهاية يجب ألا يسبق تاريخ البداية.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 0);

    await tester.tap(find.descendant(
        of: find.byKey(const Key('offer-end-date')),
        matching: find.byTooltip('مسح التاريخ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offer-save')));
    await tester.pumpAndSettle();

    final saved = (await repository.listAdminStoreOffers(partner.id)).single;
    expect(saved.startDate, OfferCalendarDate(now.year, now.month, 20));
    expect(saved.endDate, isNull);
  });

  group('helpers', () {
    test('image validation: signature, type and size', () {
      expect(validateOfferImage(_png).image?.contentType, 'image/png');
      expect(offerImageTypeOf([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(
          offerImageTypeOf(
              [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]),
          'image/webp');
      expect(validateOfferImage('GIF89a'.codeUnits).error, isNotNull);
      expect(validateOfferImage(const []).error, isNotNull);
      expect(
          validateOfferImage([..._png, ...List.filled(300 * 1024, 0)]).error,
          'حجم الصورة يجب ألا يتجاوز 300 KB.');
    });

    test('date window and status labels', () {
      final a = OfferCalendarDate(2026, 11, 1);
      final b = OfferCalendarDate(2026, 11, 2);
      expect(offerWindowError(a, a), isNull);
      expect(offerWindowError(a, b), isNull);
      expect(offerWindowError(null, a), isNull);
      expect(offerWindowError(b, a), isNotNull);
      expect(OfferStatus.values.map(offerStatusLabel),
          ['متوقف', 'مجدول', 'نشط', 'منتهي']);
    });
  });
}
