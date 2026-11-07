import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

/// Exactly what presentAdminOffer returns (backend/nestjs/src/offers).
Map<String, Object?> adminJson({
  String id = 'offer-1',
  Object? imageUrl = '/admin/offers/offer-1/image?v=2',
  Object? startDate = '2026-11-01',
  Object? endDate = '2026-11-30',
  Object? startsAt = '2026-10-31T21:00:00.000Z',
  Object? endsBefore = '2026-11-30T21:00:00.000Z',
}) =>
    {
      'id': id,
      'storeId': 'store-1',
      'title': 'خصم الشتاء',
      'description': 'على كل المعاطف',
      'discountLabel': 'خصم 20%',
      'hasImage': imageUrl != null,
      'imageVersion': 2,
      'imageUrl': imageUrl,
      'startDate': startDate,
      'endDate': endDate,
      'startsAt': startsAt,
      'endsBefore': endsBefore,
      'isActive': true,
      'displayOrder': 3,
      'status': 'scheduled',
      'createdAt': '2026-10-20T08:00:00.000Z',
      'updatedAt': '2026-10-21T09:30:00.000Z',
    };

/// Exactly what presentPublicOffer returns.
Map<String, Object?> publicJson() => {
      'id': 'offer-9',
      'storeId': 'store-1',
      'title': 'عرض',
      'description': '',
      'discountLabel': null,
      'imageUrl': '/offers/offer-9/image?v=4',
      'startDate': null,
      'endDate': null,
      'startsAt': null,
      'endsBefore': null,
    };

void main() {
  group('OfferCalendarDate', () {
    test('parses strict YYYY-MM-DD and round-trips', () {
      final date = OfferCalendarDate.parse('2026-02-28');
      expect([date.year, date.month, date.day], [2026, 2, 28]);
      expect(date.toJson(), '2026-02-28');
      expect(OfferCalendarDate(2026, 1, 5).toString(), '2026-01-05');
    });

    test('rejects malformed and impossible days', () {
      for (final value in [
        '2026-02-30',
        '2026-13-01',
        '2026-00-10',
        '2026-1-05',
        '2026-01-05T00:00:00Z',
        '',
      ]) {
        expect(OfferCalendarDate.tryParse(value), isNull, reason: value);
      }
      expect(OfferCalendarDate.tryParse('2028-02-29'), isNotNull);
      expect(() => OfferCalendarDate(2026, 2, 29), throwsArgumentError);
      expect(() => OfferCalendarDate.parse('x'), throwsFormatException);
    });

    test('orders by calendar day', () {
      final days = [
        OfferCalendarDate(2026, 12, 1),
        OfferCalendarDate(2025, 12, 31),
        OfferCalendarDate(2026, 1, 15),
      ]..sort();
      expect(days.map((d) => '$d'), ['2025-12-31', '2026-01-15', '2026-12-01']);
    });
  });

  group('StoreOffer.fromJson', () {
    test('parses every admin field and resolves the versioned image URL', () {
      final offer = StoreOffer.fromJson(
        adminJson(),
        resolveUrl: (path) => 'https://api.example.com$path',
        imageAccess: OfferImageAccess.adminPreview,
      );

      expect(offer.id, 'offer-1');
      expect(offer.storeId, 'store-1');
      expect(offer.title, 'خصم الشتاء');
      expect(offer.description, 'على كل المعاطف');
      expect(offer.discountLabel, 'خصم 20%');
      expect(offer.imageUrl,
          'https://api.example.com/admin/offers/offer-1/image?v=2');
      expect(offer.imageVersion, 2);
      expect(offer.hasImage, isTrue);
      expect(offer.imageAccess, OfferImageAccess.adminPreview);
      expect(offer.startDate, OfferCalendarDate(2026, 11, 1));
      expect(offer.endDate, OfferCalendarDate(2026, 11, 30));
      expect(offer.startsAt, DateTime.utc(2026, 10, 31, 21));
      expect(offer.endsBefore, DateTime.utc(2026, 11, 30, 21));
      expect(offer.startsAt!.isUtc, isTrue);
      expect(offer.isActive, isTrue);
      expect(offer.displayOrder, 3);
      expect(offer.serverStatus, OfferStatus.scheduled);
      expect(offer.createdAt, DateTime.utc(2026, 10, 20, 8));
      expect(offer.updatedAt, DateTime.utc(2026, 10, 21, 9, 30));
    });

    test('parses a public offer: no admin fields, defaults to active', () {
      final offer = StoreOffer.fromJson(publicJson());

      expect(offer.imageUrl, '/offers/offer-9/image?v=4');
      expect(offer.imageAccess, OfferImageAccess.public);
      expect(offer.hasImage, isTrue);
      expect(offer.imageVersion, isNull);
      expect(offer.discountLabel, isNull);
      expect(offer.description, '');
      expect(offer.startDate, isNull);
      expect(offer.endDate, isNull);
      expect(offer.startsAt, isNull);
      expect(offer.endsBefore, isNull);
      expect(offer.isActive, isTrue);
      expect(offer.displayOrder, isNull);
      expect(offer.serverStatus, isNull);
      expect(offer.createdAt, isNull);
    });

    test('a null image URL means no image', () {
      final offer = StoreOffer.fromJson(adminJson(imageUrl: null));
      expect(offer.imageUrl, isNull);
      expect(offer.hasImage, isFalse);
    });

    test('keeps Damascus dates as entered; never shifts them via the device',
        () {
      // 21:00Z on Oct 31 is already Nov 1 in Damascus: the calendar date
      // comes from the API, not from converting the instant locally.
      final offer = StoreOffer.fromJson(adminJson());
      expect(offer.startDate.toString(), '2026-11-01');
      expect(offer.startsAt!.toUtc().day, 31);
    });

    test('fails clearly on a missing required field', () {
      final json = adminJson()..remove('title');
      expect(
        () => StoreOffer.fromJson(json),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.code, 'code', 'invalid_response')),
      );
    });

    test('toJson emits the API shape and round-trips', () {
      final offer = StoreOffer.fromJson(
        adminJson(),
        imageAccess: OfferImageAccess.adminPreview,
      );
      final json = offer.toJson();
      expect(json['startDate'], '2026-11-01');
      expect(json['endsBefore'], '2026-11-30T21:00:00.000Z');
      expect(json['status'], 'scheduled');
      expect(
        StoreOffer.fromJson(json, imageAccess: OfferImageAccess.adminPreview),
        offer,
      );
    });
  });

  group('storeOffersFromJson', () {
    test('parses the bare array the offer endpoints return', () {
      final offers = storeOffersFromJson([adminJson(), publicJson()]);
      expect(offers.map((o) => o.id), ['offer-1', 'offer-9']);
    });

    test('also accepts an {items: [...]} envelope', () {
      final offers = storeOffersFromJson({
        'items': [publicJson()],
      });
      expect(offers.single.id, 'offer-9');
    });

    test('rejects a non-list response', () {
      expect(() => storeOffersFromJson({'id': 'x'}),
          throwsA(isA<YallaCashFailure>()));
      expect(() => storeOffersFromJson(null), throwsA(isA<YallaCashFailure>()));
    });
  });

  group('offerStatusAt (backend rule on instants)', () {
    final startsAt = DateTime.utc(2026, 10, 31, 21);
    final endsBefore = DateTime.utc(2026, 11, 30, 21);
    OfferStatus at(DateTime now, {bool isActive = true}) => offerStatusAt(
          isActive: isActive,
          startsAt: startsAt,
          endsBefore: endsBefore,
          now: now,
        );
    const micro = Duration(microseconds: 1);

    test('startsAt is inclusive', () {
      expect(at(startsAt.subtract(micro)), OfferStatus.scheduled);
      expect(at(startsAt), OfferStatus.active);
    });

    test('endsBefore is exclusive', () {
      expect(at(endsBefore.subtract(micro)), OfferStatus.active);
      expect(at(endsBefore), OfferStatus.expired);
    });

    test('inactive overrides every window state', () {
      for (final now in [
        startsAt.subtract(micro),
        startsAt,
        endsBefore,
      ]) {
        expect(at(now, isActive: false), OfferStatus.inactive);
      }
    });

    test('null boundaries are unbounded', () {
      final now = DateTime.utc(2000);
      expect(
        offerStatusAt(
            isActive: true, startsAt: null, endsBefore: null, now: now),
        OfferStatus.active,
      );
      expect(
        offerStatusAt(
            isActive: true,
            startsAt: null,
            endsBefore: DateTime.utc(1999),
            now: now),
        OfferStatus.expired,
      );
      expect(
        offerStatusAt(
            isActive: true,
            startsAt: DateTime.utc(2001),
            endsBefore: null,
            now: now),
        OfferStatus.scheduled,
      );
    });

    test('a local DateTime is compared as the same instant', () {
      final local = startsAt.toLocal();
      expect(local.isUtc, isFalse);
      expect(at(local), OfferStatus.active);
      expect(at(local.subtract(micro)), OfferStatus.scheduled);
    });

    test('StoreOffer.statusAt / isAvailableAt use the same rule', () {
      final offer = StoreOffer.fromJson(adminJson());
      expect(offer.isAvailableAt(startsAt), isTrue);
      expect(offer.isAvailableAt(endsBefore), isFalse);
      expect(offer.statusAt(endsBefore), OfferStatus.expired);
    });
  });

  test('sortStoreOffers: displayOrder, newest first, missing values last', () {
    StoreOffer offer(String id, int? order, String? created) => StoreOffer(
          id: id,
          storeId: 's',
          title: id,
          displayOrder: order,
          createdAt: created == null ? null : DateTime.parse(created),
        );
    final sorted = sortStoreOffers([
      offer('no-order', null, '2026-01-09T00:00:00Z'),
      offer('b-old', 1, '2026-01-01T00:00:00Z'),
      offer('a', 0, '2026-01-01T00:00:00Z'),
      offer('b-new', 1, '2026-01-05T00:00:00Z'),
      offer('b-undated', 1, null),
    ]);
    expect(sorted.map((o) => o.id),
        ['a', 'b-new', 'b-old', 'b-undated', 'no-order']);
  });

  group('request bodies', () {
    test('StoreOfferDraft sends date-only values and explicit nulls', () {
      final json = StoreOfferDraft(
        title: 'عرض',
        startDate: OfferCalendarDate(2026, 11, 1),
      ).toJson();
      expect(json, {
        'title': 'عرض',
        'description': '',
        'discountLabel': null,
        'startDate': '2026-11-01',
        'endDate': null,
        'isActive': true,
        'displayOrder': 0,
      });
    });

    test('StoreOfferUpdate: absent = unchanged, clear = JSON null', () {
      expect(const StoreOfferUpdate().isEmpty, isTrue);
      final json = StoreOfferUpdate(
        title: 'جديد',
        discountLabel: const OfferFieldUpdate.clear(),
        endDate: OfferFieldUpdate.set(OfferCalendarDate(2026, 12, 31)),
        startDate: const OfferFieldUpdate.clear(),
        isActive: false,
      ).toJson();
      expect(json, {
        'title': 'جديد',
        'discountLabel': null,
        'startDate': null,
        'endDate': '2026-12-31',
        'isActive': false,
      });
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('displayOrder'), isFalse);
    });
  });
}
