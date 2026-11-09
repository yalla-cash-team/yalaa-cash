import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_cash_admin/src/admin_app.dart';
import 'package:yalla_cash_admin/src/startup.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

YallaCashRuntime _demoRuntime() => YallaCashRuntime.fromEnvironment(
      environment: YallaCashEnvironment(
        apiBaseUrl: Uri.parse('http://localhost:3000'),
      ),
    );

void main() {
  group('resolveAdminApiBaseUrl', () {
    test('release without a define uses the production API (no crash)', () {
      expect(
        resolveAdminApiBaseUrl(configured: '', releaseMode: true),
        'https://yalla-cash-api.onrender.com',
      );
      expect(
        resolveAdminApiBaseUrl(configured: '   ', releaseMode: true),
        productionApiBaseUrl,
      );
    });

    test('an explicit define always wins', () {
      expect(
        resolveAdminApiBaseUrl(
            configured: ' https://staging.example.com ', releaseMode: true),
        'https://staging.example.com',
      );
      expect(
        resolveAdminApiBaseUrl(
            configured: 'http://10.0.2.2:3000', releaseMode: false),
        'http://10.0.2.2:3000',
      );
    });

    test('debug without a define keeps the local default', () {
      expect(resolveAdminApiBaseUrl(configured: '', releaseMode: false), '');
    });
  });

  test('the runtime talks to the pinned remote API', () {
    final runtime = createAdminRuntime(productionApiBaseUrl);
    addTearDown(runtime.dispose);
    expect(runtime.environment.apiBaseUrl.toString(), productionApiBaseUrl);
    expect(runtime.environment.useRemoteBackend, isTrue);
    expect(runtime.demoStore, isNull); // real repository, not the demo
  });

  testWidgets('initialization failure shows an error with retry, not a '
      'blank screen', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(AdminStartup(initialize: () async {
      attempts++;
      if (attempts == 1) throw StateError('boom on first start');
      return _demoRuntime();
    }));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('startup-error')), findsOneWidget);
    expect(find.text('تعذر تشغيل لوحة التحكم'), findsOneWidget);
    expect(find.textContaining('boom on first start'), findsOneWidget);
    expect(find.byType(AdminLoginScreen), findsNothing);

    await tester.tap(find.byKey(const Key('startup-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byKey(const Key('startup-error')), findsNothing);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('shows progress while starting, then the admin login',
      (tester) async {
    await tester.pumpWidget(AdminStartup(initialize: () async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _demoRuntime();
    }));
    expect(find.byKey(const Key('startup-loading')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('the error screen fits a small phone in RTL', (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AdminStartup(
        initialize: () async => throw Exception('network unreachable')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('startup-retry')), findsOneWidget);
  });
}
