import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/customer_app.dart';
import 'package:yalla_cash_customer/src/push_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupStopwatch = Stopwatch()..start();
  final firebaseInitialization = () async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP firebase_initialized_ms=${startupStopwatch.elapsedMilliseconds}',
        );
      }
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('CUSTOMER_STARTUP firebase_initialization_failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }();
  // Release builds must pin the SHARED backend explicitly via
  // --dart-define=YALLA_CASH_API_BASE_URL=... Debug/local runs fall back to
  // the platform-aware default from YallaCashEnvironment (localhost:3000,
  // or 10.0.2.2:3000 inside an Android emulator).
  const configuredBaseUrl =
      String.fromEnvironment(YallaCashEnvironment.baseUrlEnvKey);
  if (kReleaseMode && configuredBaseUrl.isEmpty) {
    throw StateError(
      'YALLA_CASH_API_BASE_URL must be provided for release builds.',
    );
  }
  final runtime = YallaCashRuntime.fromEnvironment(
    environment: YallaCashEnvironment.fromEnvironment(useRemoteBackend: true),
  );
  runApp(
    YallaCashCustomerApp(
      runtime: runtime,
      firebaseInitialization: firebaseInitialization,
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (kDebugMode) {
      debugPrint(
        'CUSTOMER_STARTUP first_flutter_frame_ms=${startupStopwatch.elapsedMilliseconds}',
      );
    }
  });
}
