import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

Map<String, Object?> _json(String id, {String? broadcastId, String? readAt}) => {
      'id': id,
      'broadcastId': broadcastId ?? 'b-$id',
      'title': 'عنوان $id',
      'body': 'نص $id',
      'createdAt': '2026-11-07T10:00:00.000Z',
      'readAt': readAt,
    };

class _Tokens implements AuthTokenStore {
  AuthTokens? t;
  @override
  Future<void> clear() async => t = null;
  @override
  Future<AuthTokens?> read() async => t;
  @override
  Future<void> write(AuthTokens tokens) async => t = tokens;
}

/// In-memory repository whose mark-read can be held or failed.
class _Repo extends InMemoryYallaCashRepository {
  _Repo(super.store);

  var markCalls = <String>[];
  var listCalls = 0;
  var failMark = false;
  var failList = false;
  Completer<void>? holdMark;

  @override
  Future<CustomerNotificationInbox> listCustomerNotifications({
    bool unreadOnly = true,
  }) {
    listCalls++;
    if (failList) {
      return Future.error(const YallaCashFailure(message: 'offline'));
    }
    return super.listCustomerNotifications(unreadOnly: unreadOnly);
  }

  @override
  Future<CustomerNotificationReadResult> markCustomerNotificationRead(
    String notificationId,
  ) async {
    markCalls.add(notificationId);
    await holdMark?.future;
    if (failMark) throw const YallaCashFailure(message: 'offline');
    return super.markCustomerNotificationRead(notificationId);
  }
}

void main() {
  group('model and remote repository', () {
    test('parses an inbox entry; read state optional', () {
      final unread = CustomerNotification.fromJson(_json('n1'));
      expect(unread.isRead, isFalse);
      expect(unread.createdAt, DateTime.utc(2026, 11, 7, 10));
      final read = CustomerNotification.fromJson(
          _json('n2', readAt: '2026-11-07T11:00:00.000Z'));
      expect(read.isRead, isTrue);
      expect(() => CustomerNotification.fromJson({'id': 'x'}),
          throwsA(isA<YallaCashFailure>()));
    });

    test('lists unread with the token and marks one read by id', () async {
      final requests = <http.Request>[];
      final client = YallaCashApiClient(
        environment: YallaCashEnvironment(
            apiBaseUrl: Uri.parse('https://api.test'), useRemoteBackend: true),
        tokenStore: _Tokens(),
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = request.method == 'GET'
              ? {
                  'items': [_json('n2'), _json('n1')],
                  'unreadCount': 2,
                }
              : {
                  ..._json('n1', readAt: '2026-11-07T12:00:00.000Z'),
                  'unreadCount': 1,
                };
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      await client.saveTokens(AuthTokens(
          accessToken: 'customer-access',
          refreshToken: 'r',
          expiresAt: DateTime.utc(2030)));
      final repository = RemoteYallaCashRepository(client);

      final inbox = await repository.listCustomerNotifications();
      final read = await repository.markCustomerNotificationRead('n1');

      expect(requests[0].url.toString(),
          'https://api.test/customer/notifications?unread=true');
      expect(requests[0].headers['authorization'], 'Bearer customer-access');
      expect(inbox.items.map((n) => n.id), ['n2', 'n1']);
      expect(inbox.unreadCount, 2);
      expect(requests[1].method, 'POST');
      expect(requests[1].url.path, '/customer/notifications/n1/read');
      expect(read.notification.isRead, isTrue);
      expect(read.unreadCount, 1);
    });
  });

  group('in-memory delivery and isolation', () {
    test('a broadcast reaches every customer once; retries add nothing',
        () async {
      final store = YallaCashStore.demo()..loginDemoCustomer();
      final repository = InMemoryYallaCashRepository(store);
      await repository.sendGeneralNotification(
          title: 'عرض', body: 'نص', idempotencyKey: 'k1');
      await repository.sendGeneralNotification(
          title: 'عرض', body: 'نص', idempotencyKey: 'k1');

      final inbox = await repository.listCustomerNotifications();
      expect(inbox.items, hasLength(1));
      expect(inbox.unreadCount, 1);
      expect(inbox.items.single.broadcastId, 'k1');
    });

    test('a customer cannot mark another customer\'s notification', () async {
      final store = YallaCashStore.demo()..loginDemoCustomer();
      final repository = InMemoryYallaCashRepository(store);
      final first = store.currentCustomer!;
      await repository.sendGeneralNotification(
          title: 'ت', body: 'ن', idempotencyKey: 'k2');
      final firstsId = (await repository.listCustomerNotifications())
          .items
          .single
          .id;
      store.registerCustomer(
          name: 'ب', governorate: 'إدلب', authMethod: AuthMethod.phone,
          phone: '+963900000002');
      expect(store.currentCustomer!.id, isNot(first.id));

      await expectLater(repository.markCustomerNotificationRead(firstsId),
          throwsA(isA<YallaCashFailure>()
              .having((f) => f.statusCode, 'status', 404)));
    });
  });

  group('CustomerAppCubit inbox', () {
    late YallaCashStore store;
    late _Repo repository;
    late CustomerAppCubit cubit;

    Future<void> broadcast(String key, String title) =>
        repository.sendGeneralNotification(
            title: title, body: 'نص $title', idempotencyKey: key);

    setUp(() async {
      store = YallaCashStore.demo()..loginDemoCustomer();
      repository = _Repo(store);
      cubit = CustomerAppCubit(repository);
      await broadcast('k-old', 'الأقدم');
      await broadcast('k-new', 'الأحدث');
    });
    tearDown(() => cubit.close());

    test('loads unread newest first with the count; global status untouched',
        () async {
      await cubit.loadNotifications();
      expect(cubit.state.notifications.map((n) => n.title),
          ['الأحدث', 'الأقدم']);
      expect(cubit.state.unreadNotificationCount, 2);
      expect(cubit.state.notificationsStatus, LoadStatus.success);
      expect(cubit.state.status, LoadStatus.initial);
    });

    test('loading the inbox never marks anything read', () async {
      await cubit.loadNotifications();
      await cubit.loadNotifications();
      expect(repository.markCalls, isEmpty);
      expect(cubit.state.unreadNotificationCount, 2);
    });

    test('opening one removes it immediately and marks only that one',
        () async {
      await cubit.loadNotifications();
      final target = cubit.state.notifications.last;
      repository.holdMark = Completer<void>();

      final opening = cubit.openNotification(target);

      // Immediate: before the backend answers.
      expect(cubit.state.notifications.map((n) => n.id),
          isNot(contains(target.id)));
      expect(cubit.state.unreadNotificationCount, 1);
      repository.holdMark!.complete();
      expect(await opening, isTrue);
      expect(repository.markCalls, [target.id]);
      expect(cubit.state.unreadNotificationCount, 1);
      expect(cubit.state.notifications, hasLength(1));
    });

    test('a reload while marking does not bring the item back', () async {
      await cubit.loadNotifications();
      final target = cubit.state.notifications.first;
      repository.holdMark = Completer<void>();
      final opening = cubit.openNotification(target);
      await cubit.loadNotifications();
      expect(cubit.state.notifications.map((n) => n.id),
          isNot(contains(target.id)));
      expect(cubit.state.unreadNotificationCount, 1);
      repository.holdMark!.complete();
      await opening;
    });

    test('if the backend refuses, the item comes back (no fake read)',
        () async {
      await cubit.loadNotifications();
      final target = cubit.state.notifications.first;
      repository.failMark = true;
      expect(await cubit.openNotification(target), isFalse);
      expect(cubit.state.notifications.map((n) => n.id), contains(target.id));
      expect(cubit.state.unreadNotificationCount, 2);
    });

    test('read state persists across an app restart (new Cubit)', () async {
      await cubit.loadNotifications();
      await cubit.openNotification(cubit.state.notifications.first);

      final restarted = CustomerAppCubit(repository);
      addTearDown(restarted.close);
      await restarted.loadNotifications();

      expect(restarted.state.notifications.map((n) => n.title), ['الأقدم']);
      expect(restarted.state.unreadNotificationCount, 1);
    });

    test('push tap: finds by broadcast id, loads if needed, marks it read',
        () async {
      final opened = await cubit.openNotificationFromPush('k-old');
      expect(opened?.title, 'الأقدم');
      expect(repository.markCalls, [opened!.id]);
      expect(cubit.state.notifications.map((n) => n.title), ['الأحدث']);
      expect(cubit.state.unreadNotificationCount, 1);

      // Tapping the same push again: already read, returned, not re-marked.
      final again = await cubit.openNotificationFromPush('k-old');
      expect(again?.isRead, isTrue);
      expect(repository.markCalls, hasLength(1));
      expect(await cubit.openNotificationFromPush('unknown'), isNull);
    });

    test('failure state is independent and retry recovers', () async {
      repository.failList = true;
      await cubit.loadNotifications();
      expect(cubit.state.notificationsStatus, LoadStatus.failure);
      expect(cubit.state.notificationsFailure?.message, 'offline');
      expect(cubit.state.failure, isNull);
      repository.failList = false;
      await cubit.loadNotifications();
      expect(cubit.state.notificationsStatus, LoadStatus.success);
    });

    test('empty inbox is empty, not failure', () async {
      final fresh = YallaCashStore.demo()..loginDemoCustomer();
      final empty = CustomerAppCubit(InMemoryYallaCashRepository(fresh));
      addTearDown(empty.close);
      await empty.loadNotifications();
      expect(empty.state.notificationsStatus, LoadStatus.empty);
      expect(empty.state.unreadNotificationCount, 0);
    });

    test('logout clears the inbox and drops late responses', () async {
      final pending = Completer<void>();
      repository.holdMark = pending;
      await cubit.loadNotifications();
      final opening = cubit.openNotification(cubit.state.notifications.first);
      await cubit.logout();
      repository.failMark = true;
      pending.complete();
      await opening;
      expect(cubit.state.notifications, isEmpty);
      expect(cubit.state.unreadNotificationCount, 0);
    });
  });
}
