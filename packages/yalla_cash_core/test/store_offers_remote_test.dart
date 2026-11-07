import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

const _base = 'https://api.example.com/v1';
const _storeId = '11111111-1111-4111-8111-111111111111';
const _offerId = '22222222-2222-4222-8222-222222222222';

Map<String, Object?> _adminOffer({Object? imageUrl, int imageVersion = 0}) => {
      'id': _offerId,
      'storeId': _storeId,
      'title': 'عرض',
      'description': '',
      'discountLabel': null,
      'hasImage': imageUrl != null,
      'imageVersion': imageVersion,
      'imageUrl': imageUrl,
      'startDate': null,
      'endDate': null,
      'startsAt': null,
      'endsBefore': null,
      'isActive': false,
      'displayOrder': 0,
      'status': 'inactive',
      'createdAt': '2026-11-01T10:00:00.000Z',
      'updatedAt': '2026-11-01T10:00:00.000Z',
    };

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// A repository over a mocked HTTP client, signed in as [accessToken].
class _Harness {
  _Harness(this.handler, {String? accessToken = 'admin-access'})
      : _initialToken = accessToken;

  final Future<http.Response> Function(http.Request request) handler;
  final String? _initialToken;
  final requests = <http.Request>[];
  final tokenStore = _MemoryTokenStore();

  late final client = YallaCashApiClient(
    environment: YallaCashEnvironment(
      apiBaseUrl: Uri.parse(_base),
      useRemoteBackend: true,
    ),
    tokenStore: tokenStore,
    httpClient: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
  );
  late final repository = RemoteYallaCashRepository(client);

  Future<RemoteYallaCashRepository> ready() async {
    if (_initialToken != null) {
      await client.saveTokens(AuthTokens(
        accessToken: _initialToken,
        refreshToken: 'admin-refresh',
        expiresAt: DateTime.utc(2030),
      ));
    }
    return repository;
  }
}

void main() {
  group('customer (public) offers', () {
    test('GET /stores/:id/offers without a token; public image URLs', () async {
      final harness = _Harness((_) async => _json([
            {
              'id': _offerId,
              'storeId': _storeId,
              'title': 'عرض',
              'description': 'وصف',
              'discountLabel': 'خصم 10%',
              'imageUrl': '/offers/$_offerId/image?v=3',
              'startDate': '2026-11-01',
              'endDate': '2026-11-30',
              'startsAt': '2026-10-31T21:00:00.000Z',
              'endsBefore': '2026-11-30T21:00:00.000Z',
            },
          ]));
      final repository = await harness.ready();

      final offers = await repository.listStoreOffers(_storeId);

      final request = harness.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), '$_base/stores/$_storeId/offers');
      expect(request.headers.containsKey('authorization'), isFalse);

      final offer = offers.single;
      expect(offer.imageAccess, OfferImageAccess.public);
      // Absolute, public endpoint, cache-busting version preserved.
      expect(offer.imageUrl, '$_base/offers/$_offerId/image?v=3');
      expect(offer.startDate, OfferCalendarDate(2026, 11, 1));
      expect(offer.endsBefore, DateTime.utc(2026, 11, 30, 21));
    });

    test('an active store without offers gives an empty list', () async {
      final harness = _Harness((_) async => _json([]));
      expect(await (await harness.ready()).listStoreOffers(_storeId), isEmpty);
    });

    test('a missing or inactive store surfaces the API 404', () async {
      final harness = _Harness((_) async => _json(
          {'code': 'not_found', 'message': 'Store was not found.'}, 404));
      final repository = await harness.ready();

      await expectLater(
        repository.listStoreOffers(_storeId),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)
            .having((f) => f.code, 'code', 'not_found')),
      );
    });
  });

  group('admin offers', () {
    test('lists every offer with the bearer token; admin image URLs',
        () async {
      final harness = _Harness((_) async => _json([
            _adminOffer(
              imageUrl: '/admin/offers/$_offerId/image?v=2',
              imageVersion: 2,
            ),
          ]));
      final repository = await harness.ready();

      final offer = (await repository.listAdminStoreOffers(_storeId)).single;

      final request = harness.requests.single;
      expect(request.url.toString(), '$_base/admin/stores/$_storeId/offers');
      expect(request.headers['authorization'], 'Bearer admin-access');
      expect(offer.imageAccess, OfferImageAccess.adminPreview);
      expect(offer.imageUrl, '$_base/admin/offers/$_offerId/image?v=2');
      expect(offer.imageVersion, 2);
      expect(offer.serverStatus, OfferStatus.inactive);
    });

    test('create posts the exact contract body', () async {
      final harness = _Harness((_) async => _json(_adminOffer(), 201));
      final repository = await harness.ready();

      final offer = await repository.createOffer(
        _storeId,
        StoreOfferDraft(
          title: 'عرض',
          discountLabel: 'خصم 20%',
          startDate: OfferCalendarDate(2026, 11, 1),
          endDate: OfferCalendarDate(2026, 11, 1),
          isActive: false,
          displayOrder: 5,
        ),
      );

      final request = harness.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/admin/stores/$_storeId/offers');
      expect(jsonDecode(request.body), {
        'title': 'عرض',
        'description': '',
        'discountLabel': 'خصم 20%',
        'startDate': '2026-11-01',
        'endDate': '2026-11-01',
        'isActive': false,
        'displayOrder': 5,
      });
      expect(offer.id, _offerId);
      expect(offer.imageAccess, OfferImageAccess.adminPreview);
    });

    test('update patches only the given fields; clear sends null', () async {
      final harness = _Harness((_) async => _json(_adminOffer()));
      final repository = await harness.ready();

      await repository.updateOffer(
        _offerId,
        const StoreOfferUpdate(
          endDate: OfferFieldUpdate.clear(),
          displayOrder: 2,
        ),
      );

      final request = harness.requests.single;
      expect(request.method, 'PATCH');
      expect(request.url.path, '/v1/admin/offers/$_offerId');
      expect(jsonDecode(request.body), {'endDate': null, 'displayOrder': 2});
    });

    test('delete addresses exactly one offer', () async {
      final harness = _Harness((_) async =>
          _json({'id': _offerId, 'storeId': _storeId, 'deleted': true}));
      final repository = await harness.ready();

      await repository.deleteOffer(_offerId);

      final request = harness.requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/v1/admin/offers/$_offerId');
    });

    test('image upload POSTs base64 JSON; the new version comes back',
        () async {
      final harness = _Harness((_) async => _json(_adminOffer(
            imageUrl: '/admin/offers/$_offerId/image?v=1',
            imageVersion: 1,
          )));
      final repository = await harness.ready();

      final offer = await repository.setOfferImage(
        _offerId,
        const StoreLogoUpload(bytes: [1, 2, 3], contentType: 'image/png'),
      );

      final request = harness.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/admin/offers/$_offerId/image');
      expect(jsonDecode(request.body), {
        'contentType': 'image/png',
        'dataBase64': base64Encode([1, 2, 3]),
      });
      expect(offer.imageVersion, 1);
      expect(offer.imageUrl, endsWith('/image?v=1'));
    });

    test('image removal DELETEs the image and bumps the version', () async {
      final harness =
          _Harness((_) async => _json(_adminOffer(imageVersion: 2)));
      final repository = await harness.ready();

      final offer = await repository.removeOfferImage(_offerId);

      final request = harness.requests.single;
      expect(request.method, 'DELETE');
      expect(request.url.path, '/v1/admin/offers/$_offerId/image');
      expect(offer.hasImage, isFalse);
      expect(offer.imageUrl, isNull);
      expect(offer.imageVersion, 2);
    });

    test('validation errors keep the API code, message and status', () async {
      final harness = _Harness((_) async => _json({
            'code': 'bad_request',
            'message': 'endDate must not be before startDate.',
          }, 400));
      final repository = await harness.ready();

      await expectLater(
        repository.createOffer(_storeId, const StoreOfferDraft(title: 'xx')),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 400)
            .having((f) => f.code, 'code', 'bad_request')),
      );
    });

    test('403 for a non-admin role is surfaced as a failure', () async {
      final harness = _Harness(
          (_) async => _json({'code': 'forbidden', 'message': 'Forbidden'}, 403));
      final repository = await harness.ready();

      await expectLater(
        repository.listAdminStoreOffers(_storeId),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 403)),
      );
    });
  });

  group('authenticated admin image preview', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2]);

    test('sends the token only in the header; version in the query',
        () async {
      final harness = _Harness((_) async => http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          ));
      final repository = await harness.ready();

      final image =
          await repository.fetchAdminOfferImage(_offerId, imageVersion: 7);

      final request = harness.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/admin/offers/$_offerId/image');
      expect(request.url.queryParameters, {'v': '7'});
      expect(request.headers['authorization'], 'Bearer admin-access');
      expect(request.url.toString(), isNot(contains('admin-access')));
      expect(image.bytes, png);
      expect(image.contentType, 'image/png');
    });

    test('omits the version query when none is given', () async {
      final harness = _Harness((_) async => http.Response.bytes(png, 200,
          headers: {'content-type': 'image/webp'}));
      final repository = await harness.ready();

      await repository.fetchAdminOfferImage(_offerId);

      expect(harness.requests.single.url.hasQuery, isFalse);
    });

    test('refreshes an expired token once and retries the download',
        () async {
      final harness = _Harness((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': 'rotated-access',
            'refreshToken': 'rotated-refresh',
            'expiresInSeconds': 900,
          });
        }
        if (request.headers['authorization'] == 'Bearer admin-access') {
          return _json({'code': 'unauthorized', 'message': 'expired'}, 401);
        }
        return http.Response.bytes(png, 200,
            headers: {'content-type': 'image/jpeg'});
      });
      final repository = await harness.ready();

      final image = await repository.fetchAdminOfferImage(_offerId);

      expect(harness.requests.map((r) => r.url.path), [
        '/v1/admin/offers/$_offerId/image',
        '/v1/auth/refresh',
        '/v1/admin/offers/$_offerId/image',
      ]);
      expect(harness.requests.last.headers['authorization'],
          'Bearer rotated-access');
      expect(image.contentType, 'image/jpeg');
    });

    test('401 without a usable session fails as unauthorized', () async {
      final harness = _Harness(
        (_) async => _json({'code': 'unauthorized', 'message': 'no'}, 401),
        accessToken: null,
      );
      final repository = await harness.ready();

      await expectLater(
        repository.fetchAdminOfferImage(_offerId),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.isUnauthorized, 'isUnauthorized', isTrue)),
      );
      expect(harness.requests.single.headers.containsKey('authorization'),
          isFalse);
    });

    test('a 404 (no image) maps the JSON error', () async {
      final harness = _Harness((_) async => _json(
          {'code': 'not_found', 'message': 'Offer image was not found.'},
          404));
      final repository = await harness.ready();

      await expectLater(
        repository.fetchAdminOfferImage(_offerId),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 404)
            .having((f) => f.code, 'code', 'not_found')),
      );
    });

    test('a non-JSON error body still becomes a YallaCashFailure', () async {
      final harness =
          _Harness((_) async => http.Response('<html>bad gateway</html>', 502));
      final repository = await harness.ready();

      await expectLater(
        repository.fetchAdminOfferImage(_offerId),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.statusCode, 'statusCode', 502)),
      );
    });

    test('rejects a response that is not an offer image type', () async {
      final harness = _Harness((_) async =>
          http.Response('{}', 200, headers: {'content-type': 'text/html'}));
      final repository = await harness.ready();

      await expectLater(
        repository.fetchAdminOfferImage(_offerId),
        throwsA(isA<YallaCashFailure>()
            .having((f) => f.code, 'code', 'invalid_response')),
      );
    });
  });

  test('existing JSON requests are unchanged by the binary support', () async {
    final harness = _Harness((_) async => _json({'items': []}));
    final repository = await harness.ready();

    expect(await repository.listAdminStores(), isEmpty);

    final request = harness.requests.single;
    expect(request.headers['accept'], 'application/json');
    expect(request.headers['content-type'], startsWith('application/json'));
    expect(request.headers['authorization'], 'Bearer admin-access');
  });
}

class _MemoryTokenStore implements AuthTokenStore {
  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens tokens) async => this.tokens = tokens;
}
