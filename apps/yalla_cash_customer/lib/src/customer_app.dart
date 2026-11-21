import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollDirection;
import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yalla_cash_customer/src/push_notifications.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/logo_plate.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';
import 'package:yalla_cash_customer/src/ui/notifications_inbox.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/shell.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

// The customer app is one library split into feature files (`part`s), so
// private widgets and helpers stay shared exactly as before.
part 'features/auth/customer_auth_screen.dart';
part 'features/location/location_screens.dart';
part 'features/shell/customer_shell.dart';
part 'features/home/home_page.dart';
part 'features/store/store_details_page.dart';
part 'features/qr/qr_page.dart';
part 'features/wallet/wallet_page.dart';
part 'features/rewards/rewards_page.dart';

class YallaCashCustomerApp extends StatefulWidget {
  const YallaCashCustomerApp({
    super.key,
    this.store,
    this.runtime,
    this.firebaseInitialization,
  });

  final YallaCashStore? store;
  final YallaCashRuntime? runtime;
  final Future<void>? firebaseInitialization;

  @override
  State<YallaCashCustomerApp> createState() => _YallaCashCustomerAppState();
}

class _YallaCashCustomerAppState extends State<YallaCashCustomerApp>
    with WidgetsBindingObserver {
  late final YallaCashRuntime? runtime = widget.runtime ??
      (widget.store == null ? YallaCashRuntime.fromEnvironment() : null);
  late final YallaCashRepository repository = widget.store == null
      ? runtime!.repository
      : InMemoryYallaCashRepository(widget.store!);
  late final CustomerAppCubit customerCubit = widget.store == null
      ? runtime!.customerCubit()
      : CustomerAppCubit(repository);
  ThemeMode themeMode = ThemeMode.light;
  bool restoringSession = false;
  final CustomerPushNotifications _push = CustomerPushNotifications();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<CustomerAppState>? _customerSubscription;
  bool _pushActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _customerSubscription = customerCubit.stream.listen(_syncPush);
    _syncPush(customerCubit.state);
    if (widget.store == null && runtime?.demoStore == null) {
      restoringSession = true;
      unawaited(_restoreSession());
    }
  }

  Future<void> _restoreSession() async {
    try {
      await customerCubit.restoreSession();
    } finally {
      if (mounted) {
        setState(() => restoringSession = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        customerCubit.state.customer != null) {
      unawaited(customerCubit.refresh());
    }
  }

  /// Push starts once a customer is signed in and stops on sign-out, so the
  /// device token is registered only for the account that is using the app.
  void _syncPush(CustomerAppState state) {
    final signedIn = state.customer != null;
    if (signedIn && !_pushActive) {
      _pushActive = true;
      unawaited(_push.start(
        register: customerCubit.registerDeviceToken,
        onForegroundMessage: _showForegroundMessage,
        onOpenedMessage: _openFromPush,
      ));
    } else if (!signedIn && _pushActive) {
      _pushActive = false;
      unawaited(_push.signOut());
    }
  }

  // Android does not display notifications while the app is open, so they
  // are shown here as a snackbar.
  void _showForegroundMessage(RemoteMessage message) {
    // A new admin broadcast is already in the inbox: refresh the bell.
    if (broadcastIdFromPushData(message.data) != null) {
      unawaited(customerCubit.loadNotifications());
    }
    final text = [message.notification?.title, message.notification?.body]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join('\n');
    if (text.isEmpty) return;
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// A push the customer tapped on the phone: open its content and mark that
  /// inbox entry read, so the in-app inbox stays in sync.
  Future<void> _openFromPush(RemoteMessage message) async {
    final broadcastId = broadcastIdFromPushData(message.data);
    if (broadcastId == null) return;
    final notification =
        await customerCubit.openNotificationFromPush(broadcastId);
    if (notification == null || !mounted) return;
    await _navigatorKey.currentState?.push(MaterialPageRoute<void>(
      builder: (_) =>
          CustomerNotificationDetailPage(notification: notification),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _customerSubscription?.cancel();
    unawaited(_push.stop());
    customerCubit.close();
    if (widget.store == null && widget.runtime == null) {
      runtime?.dispose();
    }
    super.dispose();
  }

  /// The app shell (themes, locale, navigator) is built once per local change
  /// (theme mode, session restore); customer state changes rebuild only the
  /// home content below it. The cached themes are never re-created.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'يلا كاش',
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: _navigatorKey,
      theme: customerLightTheme,
      darkTheme: customerDarkTheme,
      themeMode: themeMode,
      locale: customerLocale,
      supportedLocales: const [customerLocale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: StreamBuilder<CustomerAppState>(
        stream: customerCubit.stream,
        initialData: customerCubit.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? customerCubit.state;
          final restoring = restoringSession &&
              state.customer == null &&
              state.session == null;
          if (restoring) return const CustomerSessionRestoreScreen();
          if (state.customer == null) {
            return CustomerAuthScreen(
              cubit: customerCubit,
              state: state,
              firebaseInitialization: widget.firebaseInitialization,
              showDemoLogin: widget.store != null,
              onDemoLogin: _loginDemoCustomer,
            );
          }
          return CustomerGovernorateGate(
            cubit: customerCubit,
            state: state,
            repository: repository,
            darkMode: themeMode == ThemeMode.dark,
            onDarkModeChanged: (enabled) => setState(
              () => themeMode = enabled ? ThemeMode.dark : ThemeMode.light,
            ),
          );
        },
      ),
    );
  }

  void _loginDemoCustomer() {
    widget.store?.loginDemoCustomer();
    unawaited(customerCubit.refresh());
  }
}

/// [value] is a UTC instant (parsed from the backend's ISO-8601 `Z`
/// timestamp). Converting to local time here — only at the point of display —
/// ensures the shown expiry time matches the phone's own clock/timezone,
/// including under daylight saving, without affecting the underlying UTC
/// instant used everywhere else (expiry comparisons, JWT validation).
String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _customerFailureMessage(YallaCashFailure? failure) {
  if (failure == null) return 'تعذر إكمال العملية. حاول مرة أخرى.';
  if (failure.statusCode == 401 || failure.code == 'unauthorized') {
    return 'انتهت الجلسة. سجّل الدخول مرة أخرى.';
  }
  if (failure.code == 'network_error') {
    return 'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مجدداً.';
  }
  final message = failure.message.trim();
  if (message.isEmpty) return 'تعذر إكمال العملية. حاول مرة أخرى.';
  return message;
}
