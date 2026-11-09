import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yalla_cash_admin/src/startup.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

void main() {
  // Errors outside the widget tree are logged, never silently dropped; the
  // startup screen below shows initialization failures to the user.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Release builds talk to the production API unless
    // --dart-define=YALLA_CASH_API_BASE_URL=... pins another backend.
    // Debug/local runs fall back to the platform-aware default
    // (localhost:3000, or 10.0.2.2:3000 inside an Android emulator).
    final baseUrl = resolveAdminApiBaseUrl(
      configured: const String.fromEnvironment(
        YallaCashEnvironment.baseUrlEnvKey,
      ),
      releaseMode: kReleaseMode,
    );
    runApp(AdminStartup(
      initialize: () async => createAdminRuntime(baseUrl),
    ));
  }, (error, stackTrace) {
    debugPrint('ADMIN UNCAUGHT ERROR: $error\n$stackTrace');
  });
}
