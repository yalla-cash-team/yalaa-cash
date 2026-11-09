import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

/// Customer sign-up no longer sends a governorate: the customer picks one of
/// the governorates activated in Admin after sign-in.

class _Memory implements AuthTokenStore {
  AuthTokens? tokens;
  @override
  Future<void> clear() async => tokens = null;
  @override
  Future<AuthTokens?> read() async => tokens;
  @override
  Future<void> write(AuthTokens tokens) async => this.tokens = tokens;
}

void main() {
  final bodies = <Map<String, Object?>>[];
  late RemoteYallaCashRepository repository;

  setUp(() {
    bodies.clear();
    final client = YallaCashApiClient(
      environment: YallaCashEnvironment(
        apiBaseUrl: Uri.parse('https://api.example.com/v1'),
        useRemoteBackend: true,
      ),
      tokenStore: _Memory(),
      httpClient: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, Object?>);
        // Only the request body matters here.
        return http.Response('{"message":"stop"}', 400,
            headers: {'content-type': 'application/json'});
      }),
    );
    repository = RemoteYallaCashRepository(client);
  });

  Future<void> ignoreFailure(Future<void> call) async {
    try {
      await call;
    } catch (_) {}
  }

  test('phone sign-up without a governorate omits the field', () async {
    await ignoreFailure(repository.verifyCustomerPhoneOtp(
      challengeId: 'c1',
      phone: '0933000000',
      code: '123456',
      name: 'Customer',
    ));
    expect(bodies.single.containsKey('governorate'), isFalse);
    expect(bodies.single['name'], 'Customer');
    expect(bodies.single['code'], '123456');
  });

  test('OAuth sign-up without a governorate omits the field', () async {
    await ignoreFailure(repository.signInCustomerWithOAuth(
      provider: AuthMethod.gmail,
      firebaseIdToken: 'token',
      name: 'Customer',
    ));
    expect(bodies.single.containsKey('governorate'), isFalse);
    expect(bodies.single['provider'], 'GOOGLE');
  });

  test('a governorate passed explicitly is still sent', () async {
    await ignoreFailure(repository.verifyCustomerPhoneOtp(
      challengeId: 'c1',
      phone: '0933000000',
      code: '123456',
      name: 'Customer',
      governorate: 'إدلب',
    ));
    expect(bodies.single['governorate'], 'إدلب');
  });

  test('in-memory sign-up without governorate leaves no governorate chosen',
      () async {
    final store = YallaCashStore.demo();
    addTearDown(store.dispose);
    final repo = InMemoryYallaCashRepository(store);
    final session = await repo.verifyCustomerPhoneOtp(
      challengeId: 'demo-otp',
      phone: '0933000000',
      code: '000000',
      name: 'Customer',
    );
    expect(session.customer?.governorate, '');
    expect(session.customer?.governorateId, isNull);
    expect(session.customer?.cityId, isNull);
  });
}
