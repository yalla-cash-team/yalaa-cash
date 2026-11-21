import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/notifications_inbox.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

/// Inbox whose first load fails with a raw (technical, English) message.
class _FailingRepo extends InMemoryYallaCashRepository {
  _FailingRepo(super.store);

  @override
  Future<CustomerNotificationInbox> listCustomerNotifications({
    bool unreadOnly = true,
  }) async =>
      throw const YallaCashFailure(message: 'Internal Server Error (pg)');
}

Widget _app(Widget home, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: customerLightTheme,
      darkTheme: customerDarkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: home,
    );

void _viewport(WidgetTester tester, double width, double scale) {
  tester.view.physicalSize = Size(width * 2, 1800 * 2);
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _partner = PartnerStore(
  id: 'p1',
  name: 'مقهى الياسمين',
  category: 'مقاهي',
  commissionRate: 5,
  description: 'قهوة مختصة وحلويات شرقية',
  location: 'دمشق - المزة',
  iconSeed: 0,
  governorateId: 'g',
);

void main() {
  group('notification day headings', () {
    final now = DateTime(2026, 11, 21, 15);

    test('today, yesterday, then the Levantine date', () {
      expect(
          notificationDayLabel(DateTime(2026, 11, 21, 9), now: now), 'اليوم');
      expect(notificationDayLabel(DateTime(2026, 11, 20, 23, 59), now: now),
          'أمس');
      expect(notificationDayLabel(DateTime(2026, 11, 12, 8), now: now),
          '12 تشرين الثاني 2026');
      expect(notificationDayLabel(DateTime(2025, 1, 3), now: now),
          '3 كانون الثاني 2025');
    });

    test('failure copy is friendly Arabic, never the raw server text', () {
      const raw = YallaCashFailure(message: 'Internal Server Error (pg)');
      expect(inboxFailureMessage(raw), isNot(contains('Internal')));
      expect(inboxFailureMessage(null), 'تحقق من اتصالك ثم حاول مجدداً.');
      expect(
        inboxFailureMessage(
            const YallaCashFailure(message: 'x', code: 'network_error')),
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مجدداً.',
      );
      expect(
        inboxFailureMessage(
            const YallaCashFailure(message: 'x', statusCode: 401)),
        'انتهت الجلسة. سجّل الدخول مرة أخرى.',
      );
    });
  });

  group('notification inbox', () {
    testWidgets('groups by day; unread styling follows the real read state',
        (tester) async {
      _viewport(tester, 412, 1);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      final repo = InMemoryYallaCashRepository(store);
      await repo.sendGeneralNotification(
          title: 'خبر أول', body: 'نص', idempotencyKey: 'a');
      await repo.sendGeneralNotification(
          title: 'خبر ثان', body: 'نص', idempotencyKey: 'b');
      final cubit = CustomerAppCubit(repo);
      addTearDown(cubit.close);
      await tester.pumpWidget(_app(CustomerNotificationsPage(cubit: cubit)));
      await _settle(tester);
      // Both were sent just now: one "today" heading above them.
      expect(find.text('اليوم'), findsOneWidget);
      expect(tester.getRect(find.text('اليوم')).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('خبر ثان')).top));
      // Every listed notification is genuinely unread, so each has a dot.
      final unread = cubit.state.notifications.where((n) => !n.isRead).length;
      expect(unread, 2);
      expect(find.byKey(const Key('notification-unread-dot')),
          findsNWidgets(unread));
    });

    testWidgets('load failure shows friendly Arabic copy with a retry',
        (tester) async {
      _viewport(tester, 412, 1);
      final store = YallaCashStore.demo()..loginDemoCustomer();
      addTearDown(store.dispose);
      final cubit = CustomerAppCubit(_FailingRepo(store));
      addTearDown(cubit.close);
      await tester.pumpWidget(_app(CustomerNotificationsPage(cubit: cubit)));
      await _settle(tester);
      expect(find.text('تعذر تحميل الإشعارات'), findsOneWidget);
      expect(find.byType(YcErrorState), findsOneWidget);
      expect(find.textContaining('Internal'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('store details', () {
    for (final b in Brightness.values) {
      testWidgets('$b: unified chips and the navy hero header', (tester) async {
        _viewport(tester, 412, 1);
        final store = YallaCashStore.demo()..loginDemoCustomer();
        addTearDown(store.dispose);
        final cubit = CustomerAppCubit(InMemoryYallaCashRepository(store));
        addTearDown(cubit.close);
        await tester.pumpWidget(_app(
          StoreDetailsPage(store: _partner, cubit: cubit),
          brightness: b,
        ));
        await _settle(tester);
        expect(find.widgetWithText(YcChip, 'حصري'), findsOneWidget);
        expect(find.widgetWithText(YcChip, 'مقاهي'), findsOneWidget);
        final ctx = tester.element(find.text('مقهى الياسمين'));
        final colors = YcColors.of(ctx);
        final header = find.byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).gradient as LinearGradient?)
                    ?.colors
                    .first ==
                colors.heroStart);
        expect(header, findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    for (final b in Brightness.values) {
      testWidgets('$b 320dp x2: details page fits', (tester) async {
        _viewport(tester, 320, 2);
        final store = YallaCashStore.demo()..loginDemoCustomer();
        addTearDown(store.dispose);
        final cubit = CustomerAppCubit(InMemoryYallaCashRepository(store));
        addTearDown(cubit.close);
        await tester.pumpWidget(_app(
          StoreDetailsPage(store: _partner, cubit: cubit),
          brightness: b,
        ));
        await _settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('inline retry banner', () {
    testWidgets('320dp x2: the action moves under the message', (tester) async {
      _viewport(tester, 320, 2);
      await tester.pumpWidget(_app(Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(YcSpace.gutter),
          child: YcInlineBanner(
            message: 'تعذر تحديث العروض.',
            tone: YcTone.danger,
            actionLabel: 'إعادة المحاولة',
            onAction: () {},
          ),
        ),
      )));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('إعادة المحاولة')).top,
          greaterThan(tester.getRect(find.text('تعذر تحديث العروض.')).top));
    });
  });
}
