import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

const _base = 'https://api.example.com/v1';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Memory implements AuthTokenStore {
  AuthTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<AuthTokens?> read() async => tokens;
  @override
  Future<void> write(AuthTokens tokens) async => this.tokens = tokens;
}

Map<String, Object?> _storeJson({String? cityId, int order = 0}) => {
      'id': 's1',
      'name': 'متجر',
      'category': 'مطاعم',
      'city': 'إدلب',
      'commissionRate': 5,
      'description': '',
      'location': 'إدلب - الشارع',
      'logoUrl': null,
      'iconSeed': 0,
      'isActive': true,
      'governorateId': 'g1',
      'cityId': cityId,
      'displayOrder': order,
      'createdAt': '2026-11-01T10:00:00.000Z',
    };

void main() {
  final requests = <http.Request>[];
  late RemoteYallaCashRepository repository;
  late Future<http.Response> Function(http.Request) handler;

  setUp(() async {
    requests.clear();
    handler = (_) async => _json({'items': []});
    final client = YallaCashApiClient(
      environment: YallaCashEnvironment(
        apiBaseUrl: Uri.parse(_base),
        useRemoteBackend: true,
      ),
      tokenStore: _Memory(),
      httpClient: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
    );
    await client.saveTokens(AuthTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.utc(2030),
    ));
    repository = RemoteYallaCashRepository(client);
  });

  group('GET /stores contract', () {
    test('old call (governorate only) sends no cityId', () async {
      await repository.listActiveStores(governorateId: 'g1');
      final q = requests.single.url.queryParameters;
      expect(q['governorateId'], 'g1');
      expect(q.containsKey('cityId'), isFalse);
    });

    test('new call filters by governorate AND city', () async {
      await repository.listActiveStores(governorateId: 'g1', cityId: 'c1');
      final q = requests.single.url.queryParameters;
      expect(q['governorateId'], 'g1');
      expect(q['cityId'], 'c1');
    });

    test('older responses without cityId/displayOrder still parse', () async {
      handler = (_) async => _json({
            'items': [
              (_storeJson()..remove('cityId')..remove('displayOrder'))
            ]
          });
      final stores = await repository.listActiveStores(governorateId: 'g1');
      expect(stores.single.cityId, isNull);
      expect(stores.single.displayOrder, 0);
    });
  });

  group('admin store write contract', () {
    PartnerStore store({String? cityId, int order = 0}) => PartnerStore(
          id: 's1',
          name: 'متجر',
          category: 'مطاعم',
          commissionRate: 5,
          description: '',
          location: 'إدلب - الشارع',
          iconSeed: 0,
          governorateId: 'g1',
          cityId: cityId,
          displayOrder: order,
        );

    test('with a city: sends cityId (never the free-text city)', () async {
      handler = (_) async => _json(_storeJson(cityId: 'c1', order: 2));
      final saved =
          await repository.createStore(store(cityId: 'c1', order: 2));
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body['cityId'], 'c1');
      expect(body['displayOrder'], 2);
      expect(body.containsKey('city'), isFalse);
      expect(saved.cityId, 'c1');
      expect(saved.displayOrder, 2);
    });

    test('no position typed: displayOrder is omitted so it goes last',
        () async {
      handler = (_) async => _json(_storeJson(cityId: 'c1', order: 5));
      await repository.createStore(store(cityId: 'c1'));
      final body = jsonDecode(requests.single.body) as Map<String, Object?>;
      expect(body.containsKey('displayOrder'), isFalse);
    });
  });

  group('city admin contract', () {
    test('create/rename/deactivate use the explicit city endpoints', () async {
      handler = (r) async => _json({
            'id': 'c1',
            'governorateId': 'g1',
            'nameAr': 'أريحا',
            'isActive': true,
            'displayOrder': 1,
          });
      await repository.createCity(const City(
          id: '', governorateId: 'g1', nameAr: 'أريحا', displayOrder: 1));
      await repository.updateCity(const City(
          id: 'c1', governorateId: 'g1', nameAr: 'أريحا 2', isActive: false));
      expect(requests[0].method, 'POST');
      expect(requests[0].url.path, '/v1/admin/cities');
      expect(requests[1].method, 'PATCH');
      expect(requests[1].url.path, '/v1/admin/cities/c1');
      final body = jsonDecode(requests[1].body) as Map<String, Object?>;
      expect(body, {'nameAr': 'أريحا 2', 'isActive': false, 'displayOrder': 0});
      expect(body.containsKey('governorateId'), isFalse);
    });

    test('a 409 from the server surfaces as a failure, not a new city',
        () async {
      handler = (_) async => _json(
          {'statusCode': 409, 'error': 'Conflict', 'message': 'similar city'},
          409);
      await expectLater(
        repository.createCity(
            const City(id: '', governorateId: 'g1', nameAr: 'اريحا')),
        throwsA(isA<YallaCashFailure>()),
      );
    });
  });

  group('city name keys', () {
    test('match spelling variants but not different cities', () {
      expect(cityNameKey('أريحا'), cityNameKey(' اريحا '));
      expect(cityNameKey('حماة'), cityNameKey('حماه'));
      expect(cityNameKey('سراقِب'), cityNameKey('سراقب'));
      expect(cityNameKey('إدلب'), isNot(cityNameKey('أريحا')));
      expect(normalizeCityName('  معرة   النعمان '), 'معرة النعمان');
    });
  });

  group('in-memory rules mirror the backend', () {
    late InMemoryYallaCashRepository repo;
    setUp(() => repo = InMemoryYallaCashRepository(YallaCashStore.demo()));

    test('a variant of an existing city is refused; other governorates ok',
        () async {
      expect(
          () => repo.createCity(const City(
              id: '', governorateId: 'gov-idlib', nameAr: 'اريحا')),
          throwsA(isA<StateError>()));
      final other = await repo.createCity(const City(
          id: '', governorateId: 'gov-damascus', nameAr: 'أريحا'));
      expect(other.governorateId, 'gov-damascus');
    });

    test('renaming to a sibling\'s name is refused, own spelling allowed',
        () async {
      final cities = await repo.listAdminCities(governorateId: 'gov-idlib');
      final ariha = cities.firstWhere((c) => c.id == 'city-ariha');
      expect(() => repo.updateCity(ariha.copyWith(nameAr: 'ادلب')),
          throwsA(isA<StateError>()));
      final renamed = await repo.updateCity(ariha.copyWith(nameAr: 'اريحا'));
      expect(renamed.nameAr, 'اريحا');
    });

    test('a city with active stores cannot be deactivated', () async {
      final idlib = (await repo.listAdminCities(governorateId: 'gov-idlib'))
          .firstWhere((c) => c.id == 'city-idlib');
      expect(() => repo.updateCity(idlib.copyWith(isActive: false)),
          throwsA(isA<StateError>()));
      // An empty city can be.
      final salqin = (await repo.listAdminCities(governorateId: 'gov-idlib'))
          .firstWhere((c) => c.id == 'city-salqin');
      expect((await repo.updateCity(salqin.copyWith(isActive: false))).isActive,
          isFalse);
      expect(
          (await repo.listActiveCities(governorateId: 'gov-idlib'))
              .map((c) => c.id),
          isNot(contains('city-salqin')));
    });

    test('a store cannot be saved into an inactive city', () async {
      final salqin = (await repo.listAdminCities(governorateId: 'gov-idlib'))
          .firstWhere((c) => c.id == 'city-salqin');
      await repo.updateCity(salqin.copyWith(isActive: false));
      expect(
          () => repo.createStore(const PartnerStore(
                id: 'x',
                name: 'x',
                category: 'k',
                commissionRate: 1,
                description: '',
                location: '',
                iconSeed: 0,
                governorateId: 'gov-idlib',
                cityId: 'city-salqin',
              )),
          throwsA(isA<StateError>()));
    });
  });
}
