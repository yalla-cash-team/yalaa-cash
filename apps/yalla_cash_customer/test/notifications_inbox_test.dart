import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/notifications_inbox.dart';

/// In-memory backend with controllable inbox loading and read marking.
class _Repo extends InMemoryYallaCashRepository {
  _Repo(super.store);

  final marked = <String>[];
  Completer<void>? holdList;
  var failListOnce = false;

  @override
  Future<CustomerNotificationInbox> listCustomerNotifications({
    bool unreadOnly = true,
  }) async {
    await holdList?.future;
    if (failListOnce) {
      failListOnce = false;
      throw const YallaCashFailure(message: 'تعذر الاتصال بالخادم.');
    }
    return super.listCustomerNotifications(unreadOnly: unreadOnly);
  }

  @override
  Future<CustomerNotificationReadResult> markCustomerNotificationRead(
    String notificationId,
  ) {
    marked.add(notificationId);
    return super.markCustomerNotificationRead(notificationId);
  }
}

void main() {
  late YallaCashStore store;
  late _Repo repository;

  setUp(() async {
    store = YallaCashStore.demo()..loginDemoCustomer();
    repository = _Repo(store);
    // Two real admin broadcasts through the (in-memory) send path.
    await repository.sendGeneralNotification(
        title: 'عرض قديم', body: 'تفاصيل العرض القديم', idempotencyKey: 'k1');
    await repository.sendGeneralNotification(
        title: 'خبر جديد', body: 'تفاصيل الخبر الجديد', idempotencyKey: 'k2');
  });

  void viewport(WidgetTester tester, double width, double scale) {
    tester.view.physicalSize = Size(width * 2, 1800 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  /// The real shell (header + bell + nav) bound to the Cubit like the app.
  Future<CustomerAppCubit> pumpShell(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    final cubit = CustomerAppCubit(repository);
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      darkTheme: buildCustomerTheme(Brightness.dark),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: StreamBuilder<CustomerAppState>(
        stream: cubit.stream,
        initialData: cubit.state,
        builder: (context, snapshot) => CustomerShell(
          cubit: cubit,
          state: (snapshot.data ?? cubit.state)
              .copyWith(customer: store.currentCustomer),
          repository: repository,
          darkMode: brightness == Brightness.dark,
          onDarkModeChanged: (_) {},
        ),
      ),
    ));
    await cubit.loadNotifications();
    await settle(tester);
    return cubit;
  }

  Finder dot() => find.byKey(const Key('notifications-unread-dot'));

  testWidgets('bell dot reflects real unread; inbox lists newest first',
      (tester) async {
    await pumpShell(tester);
    expect(dot(), findsOneWidget);
    expect(find.byTooltip('الإشعارات، 2 غير مقروءة'), findsOneWidget);

    await tester.tap(find.byTooltip('الإشعارات، 2 غير مقروءة'));
    await settle(tester);

    final newest = tester.getTopLeft(find.text('خبر جديد')).dy;
    final older = tester.getTopLeft(find.text('عرض قديم')).dy;
    expect(newest, lessThan(older));
    // Opening the screen marks nothing as read.
    expect(repository.marked, isEmpty);
  });

  testWidgets(
      'tapping one opens it, removes only it immediately, marks only it read',
      (tester) async {
    final cubit = await pumpShell(tester);
    await tester.tap(find.byTooltip('الإشعارات، 2 غير مقروءة'));
    await settle(tester);

    await tester.tap(find.text('عرض قديم'));
    await settle(tester);

    // Its content is open.
    expect(find.byType(CustomerNotificationDetailPage), findsOneWidget);
    expect(find.text('تفاصيل العرض القديم'), findsOneWidget);
    final opened = cubit.state.notifications.map((n) => n.title);
    expect(opened, ['خبر جديد']);
    expect(repository.marked, hasLength(1));
    expect(cubit.state.unreadNotificationCount, 1);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('عرض قديم'), findsNothing);
    expect(find.text('خبر جديد'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);
    expect(find.byTooltip('الإشعارات، 1 غير مقروءة'), findsOneWidget);
  });

  testWidgets('dot disappears when the last unread is opened', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('الإشعارات، 2 غير مقروءة'));
    await settle(tester);
    for (final title in ['خبر جديد', 'عرض قديم']) {
      await tester.tap(find.text(title));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
    }
    expect(find.text('لا توجد إشعارات جديدة'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(dot(), findsNothing);
    expect(find.byTooltip('الإشعارات'), findsOneWidget);
  });

  testWidgets('read notifications stay read after a restart', (tester) async {
    final first = CustomerAppCubit(repository);
    await first.loadNotifications();
    await first.openNotification(first.state.notifications.first);
    await first.close();

    // A fresh app session over the same backend.
    await pumpShell(tester);
    expect(find.byTooltip('الإشعارات، 1 غير مقروءة'), findsOneWidget);
  });

  testWidgets('push tap opens content and syncs the inbox', (tester) async {
    final cubit = await pumpShell(tester);
    final opened = await cubit.openNotificationFromPush('k2');
    expect(opened?.title, 'خبر جديد');
    expect(broadcastIdFromPushData({'type': 'broadcast', 'broadcastId': 'k2'}),
        'k2');
    expect(broadcastIdFromPushData({'type': 'other', 'broadcastId': 'k2'}),
        isNull);
    await settle(tester);
    expect(find.byTooltip('الإشعارات، 1 غير مقروءة'), findsOneWidget);
    await tester.tap(find.byTooltip('الإشعارات، 1 غير مقروءة'));
    await settle(tester);
    expect(find.text('خبر جديد'), findsNothing);
    expect(find.text('عرض قديم'), findsOneWidget);
  });

  testWidgets('loading, then error with retry', (tester) async {
    final semantics = tester.ensureSemantics();
    final cubit = CustomerAppCubit(repository);
    addTearDown(cubit.close);
    repository
      ..holdList = Completer<void>()
      ..failListOnce = true;
    await tester.pumpWidget(MaterialApp(
      theme: buildCustomerTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: CustomerNotificationsPage(cubit: cubit),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('inbox-loading')), findsOneWidget);
    expect(find.bySemanticsLabel('جارٍ تحميل الإشعارات'), findsOneWidget);

    final hold = repository.holdList!;
    repository.holdList = null;
    hold.complete();
    await settle(tester);
    expect(find.text('تعذر تحميل الإشعارات'), findsOneWidget);

    await tester.tap(find.text('إعادة المحاولة'));
    await settle(tester);
    expect(find.text('خبر جديد'), findsOneWidget);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('RTL 320dp x2 ${brightness.name}: inbox and detail fit',
        (tester) async {
      viewport(tester, 320, 2);
      await pumpShell(tester, brightness: brightness);
      await tester.tap(find.byTooltip('الإشعارات، 2 غير مقروءة'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // RTL: each tile's icon is at the start (right), before its title.
      final icon =
          tester.getTopRight(find.byIcon(Icons.notifications_active_outlined).first);
      final title = tester.getTopRight(find.text('خبر جديد'));
      expect(icon.dx, greaterThan(title.dx));
      await tester.tap(find.text('خبر جديد'));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}

/// Pumps a second of frames (the shell keeps some indeterminate loaders).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
