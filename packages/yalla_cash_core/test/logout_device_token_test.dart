import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

class _RecordingRepository extends InMemoryYallaCashRepository {
  _RecordingRepository(YallaCashStore store, {this.failUnregister = false})
      : super(store);

  final bool failUnregister;
  final List<String> unregistered = [];

  @override
  Future<void> unregisterDeviceToken(String token) async {
    if (failUnregister) throw StateError('offline');
    unregistered.add(token);
  }
}

void main() {
  test('logout removes the registered device token before clearing the session',
      () async {
    final repository = _RecordingRepository(YallaCashStore.demo());
    final cubit = CustomerAppCubit(repository);

    await cubit.registerDeviceToken('token-1');
    await cubit.logout();

    expect(repository.unregistered, ['token-1']);
    expect(cubit.state.customer, isNull);
  });

  test('logout still completes when the token removal fails', () async {
    final repository = _RecordingRepository(
      YallaCashStore.demo(),
      failUnregister: true,
    );
    final cubit = CustomerAppCubit(repository);

    await cubit.registerDeviceToken('token-2');
    await cubit.logout();

    expect(repository.unregistered, isEmpty);
    expect(cubit.state.customer, isNull);
  });

  test('logout without a registered token skips the removal call', () async {
    final repository = _RecordingRepository(YallaCashStore.demo());
    final cubit = CustomerAppCubit(repository);

    await cubit.logout();

    expect(repository.unregistered, isEmpty);
    expect(cubit.state.customer, isNull);
  });
}
