import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// Background and closed-app messages are displayed by the platform from the
/// FCM "notification" payload, so this handler only needs to be registered.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {}

/// Requests notification permission, registers the device token, keeps it
/// fresh, and forwards foreground messages to the app.
class CustomerPushNotifications {
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialMessageHandled = false;

  Future<void> start({
    required Future<void> Function(String token) register,
    required void Function(RemoteMessage message) onForegroundMessage,
    void Function(RemoteMessage message)? onOpenedMessage,
  }) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) await register(token);
      _tokenSubscription ??= messaging.onTokenRefresh.listen(register);
      _messageSubscription ??=
          FirebaseMessaging.onMessage.listen(onForegroundMessage);
      if (onOpenedMessage != null) {
        // A notification tapped while the app was in the background...
        _openedSubscription ??=
            FirebaseMessaging.onMessageOpenedApp.listen(onOpenedMessage);
        // ...or the one that launched the app from a closed state (once).
        if (!_initialMessageHandled) {
          _initialMessageHandled = true;
          final initial = await messaging.getInitialMessage();
          if (initial != null) onOpenedMessage(initial);
        }
      }
    } on Object {
      // Push is an enhancement: the app keeps working without it.
    }
  }

  Future<void> stop() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
    _tokenSubscription = null;
    _messageSubscription = null;
    _openedSubscription = null;
  }

  /// Sign-out: stops listeners and deletes the local FCM token, so this device
  /// stops receiving pushes for the account that just signed out. Best-effort;
  /// the backend also drops tokens FCM rejects.
  Future<void> signOut() async {
    await stop();
    try {
      await FirebaseMessaging.instance.deleteToken();
    } on Object {
      // Firebase may be unavailable; sign-out must still complete.
    }
  }
}
