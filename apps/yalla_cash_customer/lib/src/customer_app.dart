import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Banner;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yalla_cash_customer/src/push_notifications.dart';
import 'package:yalla_cash_customer/src/ui/customer_theme.dart';
import 'package:yalla_cash_customer/src/ui/logo_trim.dart';
import 'package:yalla_cash_customer/src/ui/notifications_inbox.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/shell.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CustomerAppState>(
      stream: customerCubit.stream,
      initialData: customerCubit.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? customerCubit.state;
        final restoring =
            restoringSession && state.customer == null && state.session == null;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'يلا كاش',
          scaffoldMessengerKey: _messengerKey,
          navigatorKey: _navigatorKey,
          theme: buildCustomerTheme(Brightness.light),
          darkTheme: buildCustomerTheme(Brightness.dark),
          themeMode: themeMode,
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
          home: restoring
              ? const Scaffold(body: Center(child: CircularProgressIndicator()))
              : state.customer == null
                  ? CustomerAuthScreen(
                      cubit: customerCubit,
                      state: state,
                      firebaseInitialization: widget.firebaseInitialization,
                      showDemoLogin: widget.store != null,
                      onDemoLogin: _loginDemoCustomer,
                    )
                  : CustomerGovernorateGate(
                      cubit: customerCubit,
                      state: state,
                      repository: repository,
                      darkMode: themeMode == ThemeMode.dark,
                      onDarkModeChanged: (enabled) => setState(
                        () => themeMode =
                            enabled ? ThemeMode.dark : ThemeMode.light,
                      ),
                    ),
        );
      },
    );
  }

  void _loginDemoCustomer() {
    widget.store?.loginDemoCustomer();
    unawaited(customerCubit.refresh());
  }
}

class CustomerAuthScreen extends StatefulWidget {
  const CustomerAuthScreen({
    required this.cubit,
    required this.state,
    this.firebaseInitialization,
    this.showDemoLogin = false,
    this.onDemoLogin,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final Future<void>? firebaseInitialization;
  final bool showDemoLogin;
  final VoidCallback? onDemoLogin;

  @override
  State<CustomerAuthScreen> createState() => _CustomerAuthScreenState();
}

class _CustomerAuthScreenState extends State<CustomerAuthScreen>
    with SingleTickerProviderStateMixin {
  static const governorates = [
    'دمشق',
    'ريف دمشق',
    'حلب',
    'حمص',
    'حماة',
    'اللاذقية',
    'طرطوس',
    'إدلب',
    'درعا',
    'السويداء',
    'القنيطرة',
    'دير الزور',
    'الرقة',
    'الحسكة',
  ];

  AuthMethod? method;
  _AuthStage stage = _AuthStage.options;
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  String? governorate;
  PhoneOtpChallenge? otpChallenge;
  String? _pendingOAuthIdToken;
  String? errorMessage;
  bool isLoading = false;
  Timer? resendTimer;
  int resendSeconds = 0;
  late final AnimationController entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  late final Animation<double> logoFade = CurvedAnimation(
    parent: entranceController,
    curve: const Interval(0, .52, curve: Curves.easeOutCubic),
  );
  late final Animation<double> logoScale =
      Tween<double>(begin: .65, end: 1).animate(logoFade);
  late final Animation<double> logoVerticalShift =
      Tween<double>(begin: 55, end: 0).animate(logoFade);
  late final Animation<double> titleEntrance = _buttonEntrance(.16, .45);
  bool entranceStarted = false;

  Animation<double> _buttonEntrance(double start, double end) =>
      CurvedAnimation(
        parent: entranceController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (entranceStarted) return;
    entranceStarted = true;
    if (MediaQuery.accessibleNavigationOf(context)) {
      entranceController.value = 1;
    } else {
      entranceController.forward();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    otpController.dispose();
    resendTimer?.cancel();
    entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedBuilder(
                    animation: logoVerticalShift,
                    child: const Center(child: YallaCashLogo(height: 120)),
                    builder: (context, logo) => Transform.translate(
                      offset: Offset(0, -30 + logoVerticalShift.value),
                      child: FadeTransition(
                        opacity: logoFade,
                        child: ScaleTransition(scale: logoScale, child: logo),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Entrance(
                    animation: titleEntrance,
                    distance: 25,
                    scaleBegin: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'يلا كاش',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: scheme.primary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          method == null
                              ? 'أنشئ حسابك وابدأ تجمع نقاطك'
                              : 'أكمل بياناتك',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (method == null) ...[
                    _Entrance(
                      animation: _buttonEntrance(.32, .59),
                      child: _AuthChoice(
                        icon: Icons.mail_outline_rounded,
                        label: 'المتابعة عبر جيميل',
                        onTap: () => unawaited(_signInWithGoogle()),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Entrance(
                      animation: _buttonEntrance(.46, .73),
                      child: _AuthChoice(
                        icon: Icons.phone_android_rounded,
                        label: 'المتابعة برقم الهاتف',
                        onTap: () => setState(() {
                          method = AuthMethod.phone;
                          stage = _AuthStage.phone;
                          errorMessage = null;
                        }),
                      ),
                    ),
                    if (widget.showDemoLogin && widget.onDemoLogin != null) ...[
                      const SizedBox(height: 22),
                      _Entrance(
                        animation: _buttonEntrance(.56, .82),
                        distance: 4,
                        scaleBegin: .98,
                        child: TextButton(
                          key: const Key('demo-customer-login'),
                          onPressed: widget.onDemoLogin,
                          child: const Text('دخول سريع للعرض التجريبي'),
                        ),
                      ),
                    ],
                  ] else if (stage == _AuthStage.phone) ...[
                    const Text(
                      'أدخل رقم هاتفك لإرسال رمز التحقق',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => errorMessage = null),
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        hintText: '09xxxxxxxx',
                        prefixIcon: Icon(Icons.phone_android_rounded),
                        prefixText: '+963  ',
                      ),
                    ),
                    if (errorMessage != null) _ErrorMessage(errorMessage!),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: isLoading ? null : _continueToOtp,
                      child: isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إرسال رمز التحقق'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: _backToOptions, child: const Text('رجوع')),
                  ] else if (stage == _AuthStage.otp) ...[
                    Text(
                      'تحقق من رقم ${phoneController.text.trim()}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'رمز التحقق',
                        hintText: '000000',
                        counterText: '',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    _InfoMessage(_otpHelpMessage),
                    if (errorMessage != null) _ErrorMessage(errorMessage!),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: isLoading ? null : _verifyOtp,
                      child: isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('تحقق ودخول'),
                    ),
                    TextButton(
                      onPressed:
                          resendSeconds == 0 && !isLoading ? _resendOtp : null,
                      child: Text(resendSeconds == 0
                          ? 'إعادة إرسال الرمز'
                          : 'إعادة الإرسال بعد $resendSeconds ث'),
                    ),
                    OutlinedButton(
                        onPressed: _backToPhone,
                        child: const Text('تغيير رقم الهاتف')),
                  ] else ...[
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: governorate,
                      decoration: const InputDecoration(
                        labelText: 'المحافظة',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      items: governorates
                          .map((item) =>
                              DropdownMenuItem(value: item, child: Text(item)))
                          .toList(),
                      onChanged: (value) => setState(() => governorate = value),
                    ),
                    if (errorMessage != null) _ErrorMessage(errorMessage!),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: isLoading || !_canSubmit ? null : _submit,
                      child: isLoading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('إنشاء الحساب'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _backToOptions,
                      child: const Text('رجوع'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _canSubmit {
    final hasProfile =
        nameController.text.trim().isNotEmpty && governorate != null;
    if (method == AuthMethod.phone) {
      return hasProfile &&
          phoneController.text.trim().length >= 8 &&
          otpChallenge != null &&
          otpController.text.trim().isNotEmpty;
    }
    return hasProfile && _pendingOAuthIdToken != null;
  }

  bool get _canContinuePhone => phoneController.text.trim().length >= 8;

  String get _otpHelpMessage => 'أدخل رمز التحقق المرسل إلى هاتفك.';

  Future<void> _signInWithGoogle() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      await (widget.firebaseInitialization ?? Firebase.initializeApp());
      if (Firebase.apps.isEmpty) {
        throw StateError('Firebase initialization is unavailable.');
      }
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // User cancelled the account picker — not an error.
        if (mounted) setState(() => isLoading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw fb_auth.FirebaseAuthException(
          code: 'missing-id-token',
          message: 'Firebase did not return an ID token.',
        );
      }
      if (!mounted) return;
      setState(() {
        method = AuthMethod.gmail;
        _pendingOAuthIdToken = idToken;
        if (nameController.text.trim().isEmpty &&
            (googleUser.displayName?.isNotEmpty ?? false)) {
          nameController.text = googleUser.displayName!;
        }
        stage = _AuthStage.details;
        isLoading = false;
        errorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint('GOOGLE_SIGN_IN_FAILED: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => isLoading = false);
      _showUnavailable('تعذر تسجيل الدخول عبر جوجل. حاول مرة أخرى.');
    }
  }

  Future<void> _continueToOtp() async {
    if (!_canContinuePhone) {
      setState(() =>
          errorMessage = 'أدخل رقم هاتف صحيحاً مكوناً من 8 أرقام على الأقل.');
      return;
    }
    setState(() {
      isLoading = true;
      errorMessage = null;
      otpController.clear();
    });
    final challenge =
        await widget.cubit.startPhoneOtp(phoneController.text.trim());
    if (!mounted) return;
    if (challenge == null) {
      setState(() {
        isLoading = false;
        errorMessage = _customerFailureMessage(widget.cubit.state.failure);
      });
      return;
    }
    setState(() {
      otpChallenge = challenge;
      stage = _AuthStage.otp;
      isLoading = false;
      errorMessage = null;
    });
  }

  Future<void> _verifyOtp() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    if (otpChallenge == null || otpController.text.trim().isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = 'أدخل رمز التحقق الصحيح.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      isLoading = false;
      stage = _AuthStage.details;
      errorMessage = null;
    });
  }

  Future<void> _resendOtp() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
      resendSeconds = 30;
    });
    final challenge =
        await widget.cubit.startPhoneOtp(phoneController.text.trim());
    if (!mounted) return;
    if (challenge == null) {
      setState(() {
        isLoading = false;
        resendSeconds = 0;
        errorMessage = _customerFailureMessage(widget.cubit.state.failure);
      });
      return;
    }
    setState(() {
      isLoading = false;
      otpChallenge = challenge;
    });
    resendTimer?.cancel();
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => resendSeconds = 0);
        return;
      }
      setState(() => resendSeconds--);
    });
  }

  void _showUnavailable(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _backToOptions() => setState(() {
        stage = _AuthStage.options;
        method = null;
        otpChallenge = null;
        _pendingOAuthIdToken = null;
        isLoading = false;
        errorMessage = null;
      });

  void _backToPhone() => setState(() {
        stage = _AuthStage.phone;
        otpChallenge = null;
        isLoading = false;
        errorMessage = null;
      });

  Future<void> _submit() async {
    if (method == AuthMethod.phone) {
      final challenge = otpChallenge;
      if (challenge == null) {
        setState(() => errorMessage = 'ابدأ التحقق من رقم الهاتف مرة أخرى.');
        return;
      }
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      await widget.cubit.verifyPhoneOtp(
        challengeId: challenge.challengeId,
        phone: phoneController.text.trim(),
        code: otpController.text.trim(),
        name: nameController.text.trim(),
        governorate: governorate!,
      );
    } else {
      final idToken = _pendingOAuthIdToken;
      if (idToken == null) {
        setState(() => errorMessage = 'ابدأ تسجيل الدخول مرة أخرى.');
        return;
      }
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
      await widget.cubit.signInWithOAuth(
        provider: method!,
        firebaseIdToken: idToken,
        name: nameController.text.trim(),
        governorate: governorate!,
      );
    }
    if (!mounted) return;
    if (widget.cubit.state.customer == null) {
      setState(() {
        isLoading = false;
        errorMessage = _customerFailureMessage(widget.cubit.state.failure);
      });
      return;
    }
    setState(() => isLoading = false);
  }
}

class _AuthChoice extends StatelessWidget {
  const _AuthChoice(
      {required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 21),
              const SizedBox(width: 10),
              Text(label, textDirection: TextDirection.rtl),
            ],
          ),
        ),
      );
}

class _Entrance extends StatelessWidget {
  const _Entrance(
      {required this.animation,
      required this.child,
      this.distance = 30,
      this.scaleBegin = .96});

  final Animation<double> animation;
  final Widget child;
  final double distance;
  final double scaleBegin;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, distance / 52),
            end: Offset.zero,
          ).animate(animation),
          child: ScaleTransition(
            scale: Tween<double>(begin: scaleBegin, end: 1).animate(animation),
            child: child,
          ),
        ),
      );
}

enum _AuthStage { options, phone, otp, details }

class _InfoMessage extends StatelessWidget {
  const _InfoMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12),
        ),
      );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Theme.of(context).colorScheme.error, fontSize: 12),
        ),
      );
}

class CustomerGovernorateGate extends StatefulWidget {
  const CustomerGovernorateGate({
    required this.cubit,
    required this.state,
    required this.repository,
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final YallaCashRepository repository;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<CustomerGovernorateGate> createState() =>
      _CustomerGovernorateGateState();
}

class _CustomerGovernorateGateState extends State<CustomerGovernorateGate> {
  List<Governorate> governorates = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    try {
      final items = await widget.repository.listActiveGovernorates();
      final selectedId = widget.state.customer?.governorateId;
      if (!mounted) return;
      setState(() {
        governorates = items.where((item) => item.isActive).toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        loading = false;
        error = null;
      });
      if (kDebugMode) {
        debugPrint(
          'CUSTOMER_STARTUP governorate_validation_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      if (selectedId != null &&
          governorates.any((item) => item.id == selectedId)) {
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر تحميل المحافظات المتاحة. حاول مرة أخرى.';
      });
    }
  }

  Future<void> _select(Governorate governorate) async {
    setState(() => loading = true);
    try {
      await widget.cubit.updateGovernorate(governorate.id);
      if (!mounted) return;
      if (widget.cubit.state.failure != null) {
        setState(() {
          loading = false;
          error = _customerFailureMessage(widget.cubit.state.failure);
        });
        return;
      }
      setState(() => loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر حفظ المحافظة المختارة. حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.state.customer?.governorateId;
    final hasProfileGovernorate = selectedId != null && selectedId.isNotEmpty;
    final validSelection =
        selectedId != null && governorates.any((item) => item.id == selectedId);
    if (validSelection || (loading && hasProfileGovernorate)) {
      return CustomerShell(
        cubit: widget.cubit,
        state: widget.state,
        repository: widget.repository,
        darkMode: widget.darkMode,
        onDarkModeChanged: widget.onDarkModeChanged,
      );
    }
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return GovernorateSelectionScreen(
      governorates: governorates,
      error: error,
      onRetry: _load,
      onSelected: _select,
    );
  }
}

class GovernorateSelectionScreen extends StatelessWidget {
  const GovernorateSelectionScreen({
    required this.governorates,
    required this.onSelected,
    this.error,
    this.onRetry,
    super.key,
  });

  final List<Governorate> governorates;
  final String? error;
  final Future<void> Function(Governorate) onSelected;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المحافظة')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 24),
                  Text('اختر محافظتك',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('اختر محافظتك وابدأ بجمع نقاطك',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  if (error != null) ...[
                    Text(error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 12),
                    OutlinedButton(
                        onPressed: onRetry,
                        child: const Text('إعادة المحاولة')),
                    const SizedBox(height: 12),
                  ],
                  if (governorates.isEmpty && error == null)
                    const Text('لا توجد محافظات متاحة حالياً.',
                        textAlign: TextAlign.center)
                  else
                    ...governorates.map(
                      (governorate) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => onSelected(governorate),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 18),
                              child: Row(
                                children: [
                                  Icon(Icons.location_on_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(governorate.nameAr,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800))),
                                  const Icon(Icons.chevron_left_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({
    required this.cubit,
    required this.state,
    required this.repository,
    required this.darkMode,
    required this.onDarkModeChanged,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final YallaCashRepository repository;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final customer = widget.state.customer!;
    final pages = [
      CustomerHomePage(
          cubit: widget.cubit, state: widget.state, customer: customer),
      CustomerQrPage(
          cubit: widget.cubit, state: widget.state, customer: customer),
      // Wallet and store fade in on their first visit only (never on return).
      YcRevealOnFirstShow(
        active: selectedIndex == 2,
        child: CustomerWalletPage(
          transactions: widget.state.transactions,
          customer: customer,
          productRedemptions: widget.state.productRedemptions,
          cashRequests: widget.state.cashRequests,
          // Wallet data arrives in one batch with the points summary.
          loading: widget.state.points == null &&
              widget.state.status != LoadStatus.failure,
          failed: widget.state.points == null &&
              widget.state.status == LoadStatus.failure,
          onRetry: widget.cubit.refresh,
        ),
      ),
      YcRevealOnFirstShow(
        active: selectedIndex == 3,
        child: CustomerRewardsPage(cubit: widget.cubit, state: widget.state),
      ),
    ];

    return Scaffold(
      appBar: CustomerAppBar(
        firstName: customer.name.split(' ').first,
        // The greeting row belongs to the Home tab only.
        showGreeting: selectedIndex == 0,
        unreadNotifications: widget.state.unreadNotificationCount,
        onOpenNotifications: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CustomerNotificationsPage(cubit: widget.cubit),
          ),
        ),
      ),
      drawer: CustomerDrawer(
        governorateName: customer.governorate,
        darkMode: widget.darkMode,
        onDarkModeChanged: widget.onDarkModeChanged,
        onChangeGovernorate: _changeGovernorate,
        onContact: _contactUsOnWhatsApp,
        onRate: _rateAppOnGooglePlay,
        onInvite: () {
          Navigator.pop(context);
          _showShareSheet(context);
        },
        onLogout: widget.cubit.logout,
      ),
      body: SafeArea(
        // Pull-to-refresh re-syncs every section (profile, points, stores,
        // transactions, products, cash requests AND banners) from the server.
        child: RefreshIndicator(
          onRefresh: () => widget.cubit.refresh(),
          child: IndexedStack(index: selectedIndex, children: pages),
        ),
      ),
      bottomNavigationBar: CustomerNavBar(
        selectedIndex: selectedIndex,
        onSelected: (index) {
          final changed = index != selectedIndex;
          setState(() => selectedIndex = index);
          // Re-sync authoritative data when switching sections so Home /
          // Wallet / Rewards never remain stale after admin-side changes.
          if (changed) unawaited(widget.cubit.refresh());
        },
      ),
    );
  }

  Future<void> _changeGovernorate() async {
    final governorates = await widget.repository.listActiveGovernorates();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => GovernorateSelectionScreen(
          governorates: governorates,
          onSelected: (governorate) async {
            try {
              await widget.cubit.updateGovernorate(governorate.id);
              if (!context.mounted) return;
              if (widget.cubit.state.failure == null) {
                Navigator.of(context).pop();
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        _customerFailureMessage(widget.cubit.state.failure))),
              );
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تعذر حفظ المحافظة المختارة.')));
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _contactUsOnWhatsApp() async {
    final uri = Uri.parse('https://wa.me/963998111295');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showShareSheet(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => _ShareAppSheet(cubit: widget.cubit),
      );

  Future<void> _rateAppOnGooglePlay() async {
    const marketUri = 'market://details?id=com.yallacash.app';
    const webUri =
        'https://play.google.com/store/apps/details?id=com.yallacash.app';
    if (await canLaunchUrl(Uri.parse(marketUri))) {
      await launchUrl(Uri.parse(marketUri),
          mode: LaunchMode.externalApplication);
      return;
    }
    await launchUrl(Uri.parse(webUri), mode: LaunchMode.externalApplication);
  }
}

/// Invitation text and official Play Store link (same app id as "rate us").
const _shareAppMessage = 'حمّل تطبيق يلا كاش واستبدل نقاطك بكاش! '
    'https://play.google.com/store/apps/details?id=com.yallacash.app';

/// Share sheet opened from the drawer. It shares the app and asks the server
/// for the one-time share reward.
class _ShareAppSheet extends StatefulWidget {
  const _ShareAppSheet({required this.cubit});

  final CustomerAppCubit cubit;

  @override
  State<_ShareAppSheet> createState() => _ShareAppSheetState();
}

class _ShareAppSheetState extends State<_ShareAppSheet> {
  // Blocks a second tap while the share sheet or claim request is running.
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final shared = await Share.share(
        _shareAppMessage,
        subject: 'تطبيق يلا كاش',
      );
      // Delivery cannot be verified (Android and web usually report
      // "unavailable"), so any action other than a dismissed sheet counts.
      // The server still grants the reward only once per account.
      if (shared.status == ShareResultStatus.dismissed) {
        messenger.showSnackBar(
            const SnackBar(content: Text('لم تكتمل عملية المشاركة.')));
        return;
      }
      final reward = await widget.cubit.claimShareReward();
      messenger.showSnackBar(SnackBar(content: Text(_rewardMessage(reward))));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _rewardMessage(ShareRewardResult? reward) => switch (reward?.status) {
        'granted' =>
          'شكراً لمشاركتك! أضفنا ${reward!.pointsAwarded} نقطة إلى رصيدك.',
        'already_claimed' => 'حصلت على مكافأة المشاركة من قبل.',
        'disabled' => 'مكافأة المشاركة غير متاحة حالياً.',
        _ => 'تعذر تسجيل المكافأة الآن. حاول لاحقاً.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.card_giftcard_rounded,
                  size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'ادعُ أصدقاءك واربح نقاط',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'شارك تطبيق يلا كاش مع أصدقائك. تحصل على نقاط مكافأة عند مشاركتك الأولى، وتُمنح المكافأة مرة واحدة لكل حساب.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.share_rounded),
              label: Text(_sharing ? 'جارٍ المشاركة...' : 'شارك الآن'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Home page renders everything from [CustomerAppState] — including banners,
/// which are owned by [CustomerAppCubit] so every refresh() reflects the
/// latest admin-managed content (previously banners were fetched once into
/// local widget state and never refreshed).
class CustomerHomePage extends StatelessWidget {
  const CustomerHomePage({
    required this.cubit,
    required this.state,
    required this.customer,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final points = state.points;
    final stores =
        state.stores.where((store) => store.isActive).toList(growable: false);
    final banners = state.banners;
    // One gentle entrance for the page, played when Home is first built. It
    // wraps the list itself (not its lazily built children) and the page stays
    // mounted across tab switches and rebuilds, so it does not replay on tab
    // return, refresh, or scrolling. Skipped under reduced motion.
    return YcFadeSlideIn(
      offset: 10,
      child: ListView(
        key: const PageStorageKey('customer-home'),
        padding: const EdgeInsets.fromLTRB(
          YcSpace.gutter,
          YcSpace.sm,
          YcSpace.gutter,
          YcSpace.xl,
        ),
        children: [
          _BalanceCard(points: points),
          if (banners.isNotEmpty) ...[
            const SizedBox(height: YcSpace.md),
            _HomeBannerCarousel(banners: banners),
          ],
          const SizedBox(height: YcSpace.xl),
          const YcSectionHeader('المحلات الحصرية بمدينتك'),
          const SizedBox(height: YcSpace.sm),
          if (stores.isEmpty)
            const YcEmptyState(
              icon: Icons.storefront_outlined,
              title: 'لا توجد محلات متاحة حالياً',
            )
          else
            ...stores.map((partner) => Padding(
                  padding: const EdgeInsets.only(bottom: YcSpace.sm),
                  child: _StoreCard(store: partner, cubit: cubit),
                )),
        ],
      ),
    );
  }
}

/// Banner artwork is designed at 1200 x 500 px (2.4 : 1). The carousel keeps
/// that ratio at every screen width, so the height scales with the width.
const double _bannerAspectRatio = 1200 / 500;

/// Advertising banner carousel with automatic rotation every 2 seconds.
/// Manual swipe keeps working (PageView's normal gesture handling); the
/// timer just advances the SAME controller, and onPageChanged keeps the
/// tracked page in sync so auto-rotation continues from wherever the user
/// last swiped to, rather than resetting.
class _HomeBannerCarousel extends StatefulWidget {
  const _HomeBannerCarousel({required this.banners});

  final List<Banner> banners;

  @override
  State<_HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<_HomeBannerCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant _HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The banner list can change (e.g. after a governorate switch) to a
    // different length or different banners at the same length. Either way,
    // reset to the first page so we never try to animate to an index that
    // no longer exists in the new list, then restart the rotation timer to
    // match the new list.
    final changed = oldWidget.banners.length != widget.banners.length ||
        !_sameBannerIds(oldWidget.banners, widget.banners);
    if (changed) {
      _page = 0;
      if (_controller.hasClients && widget.banners.isNotEmpty) {
        _controller.jumpToPage(0);
      }
      _restartTimer();
    }
  }

  bool _sameBannerIds(List<Banner> a, List<Banner> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.banners.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_controller.hasClients) return;
      final next = (_page + 1) % widget.banners.length;
      // Reduced motion: change ad at the same cadence, without the slide.
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.jumpToPage(next);
        return;
      }
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Returns the trimmed URL when [targetUrl] is a valid external http(s)
  /// link, or null otherwise (missing, blank, malformed, or any non-http/
  /// https scheme — e.g. an internal route like `/stores?category=...`).
  /// Banners are never routed internally; a null result just means the
  /// banner isn't tappable.
  String? _validExternalBannerUrl(String? targetUrl) {
    if (targetUrl == null) return null;
    final trimmed = targetUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return trimmed;
  }

  Future<void> _openBannerUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      // Opening the link is best-effort only — never crash or surface an
      // error just because no app could handle it.
    }
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: _bannerAspectRatio,
        // One rounded clip wraps the WHOLE carousel viewport rather than each
        // page. Clipping per page left the viewport's own square edge exposed
        // while two ads were mid-slide, so the incoming image briefly showed
        // sharp corners. Here every frame (outgoing and incoming ads, loading
        // and error placeholders) is cut to the same rounded rectangle.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: PageView.builder(
              controller: _controller,
              // The ClipRRect above is the single clip; skip PageView's own.
              clipBehavior: Clip.none,
              itemCount: widget.banners.length,
              onPageChanged: (index) => _page = index,
              itemBuilder: (context, index) {
                final banner = widget.banners[index];
                final externalUrl = _validExternalBannerUrl(banner.targetUrl);
                return GestureDetector(
                  // A null onTap makes this a no-op tap target without
                  // affecting PageView's own horizontal swipe gesture — swipe
                  // and this tap detector coexist normally in Flutter's
                  // gesture arena, no special handling needed.
                  onTap: externalUrl == null
                      ? null
                      : () => _openBannerUrl(externalUrl),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // BoxFit.contain shows the whole ad; the neutral
                      // background fills any leftover space when the image
                      // ratio differs from 2.4 : 1.
                      ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: banner.imageUrl.isEmpty
                            ? const Center(child: Icon(Icons.image_outlined))
                            : Image.network(
                                banner.imageUrl,
                                fit: BoxFit.contain,
                                // A failed image (404, network hiccup, stale
                                // URL) must never crash or blank out just
                                // this one banner — the carousel keeps
                                // auto-rotating through the rest regardless,
                                // since each page's Image error is scoped to
                                // that page only.
                                errorBuilder: (context, error, stackTrace) =>
                                    ColoredBox(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Center(
                                      child: Icon(
                                          Icons.image_not_supported_outlined)),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
}

/// Points balance card.
///
/// The hero figure is the customer's real total balance. Beneath it, a
/// compact breakdown always shows the real available points and the real
/// pending (processing) points — including a pending figure of 0. All numbers
/// come straight from [PointsSummary]; this widget does no arithmetic,
/// rounding or loading logic of its own.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.points});

  final PointsSummary? points;

  /// Bright brand sky blue → the brand's medium blue. White hero figures stay
  /// above 3:1 (large-text) contrast on both stops.
  static final Color _gradientStart =
      Color.lerp(YallaColors.primary, YallaColors.primaryStrong, .25)!;
  static const Color _gradientEnd = YallaColors.primaryStrong;

  /// Inset behind the breakdown: deep enough for small white text to keep at
  /// least 4.5:1 contrast anywhere on the gradient.
  static final Color _panel = YallaColors.navy.withValues(alpha: .30);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final summary = points;
    final radius = BorderRadius.circular(YcRadius.xl);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        // Lighter at the logo corner, deeper behind the figures.
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [_gradientStart, _gradientEnd],
        ),
        border: dark
            ? Border.all(color: Colors.white.withValues(alpha: .12))
            : null,
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: YallaColors.primaryStrong.withValues(alpha: .28),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // One soft highlight at the logo corner, away from the figures.
            PositionedDirectional(
              top: -64,
              end: -56,
              child: ExcludeSemantics(
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .06),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                YcSpace.lg,
                14,
                YcSpace.lg,
                YcSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'رصيد النقاط',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const _BalanceLogo(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (summary == null)
                    // Loading: an indeterminate bar, never a false zero. The
                    // box matches the figure's height so the card does not
                    // jump.
                    SizedBox(
                      height: 38,
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: 112,
                          child: LinearProgressIndicator(
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    // Scales down (never wraps or overflows) for very large
                    // balances or large text sizes.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        formatNumber(summary.pointsBalance),
                        maxLines: 1,
                        style: YcType.hero(context)?.copyWith(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.1,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BalanceSplit(
                      available: summary.availablePoints,
                      pending: summary.heldPoints,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Official mark on the brand gold disc, at the card's end corner.
class _BalanceLogo extends StatelessWidget {
  const _BalanceLogo();

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: YallaColors.gold,
          shape: BoxShape.circle,
        ),
        child: const YallaCashLogo(
          height: 20,
          markOnly: true,
          color: YallaColors.navy,
        ),
      );
}

/// "Available" and "processing" side by side on a deeper inset panel.
class _BalanceSplit extends StatelessWidget {
  const _BalanceSplit({required this.available, required this.pending});

  final int available;
  final int pending;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: _BalanceCard._panel,
          borderRadius: BorderRadius.circular(YcRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YcSpace.md,
            vertical: YcSpace.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: _SplitCell(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'المتاح',
                  value: available,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: YcSpace.sm),
                color: Colors.white.withValues(alpha: .25),
              ),
              Expanded(
                child: _SplitCell(
                  icon: Icons.schedule_rounded,
                  label: 'قيد المعالجة',
                  value: pending,
                ),
              ),
            ],
          ),
        ),
      );
}

/// A small label over its figure. The figure scales down rather than
/// overflowing for very large values or text sizes.
class _SplitCell extends StatelessWidget {
  const _SplitCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The full label always shows: it scales down rather than being
          // cut on narrow screens or at large text sizes.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatNumber(value),
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared premium surface for store UI: a soft tint gradient over the theme's
/// card colour, a hairline border and a gentle shadow. Everything is derived
/// from the active theme, so light and dark mode both stay on-brand.
BoxDecoration _storeSurface(BuildContext context, {double radius = 24}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final base = theme.cardTheme.color ?? scheme.surface;
  final tint = Color.alphaBlend(
    scheme.primary.withValues(alpha: dark ? .10 : .07),
    base,
  );
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: AlignmentDirectional.topStart,
      end: AlignmentDirectional.bottomEnd,
      colors: [base, tint],
    ),
    border: Border.all(
      color: dark
          ? Colors.white.withValues(alpha: .10)
          : YallaColors.navy.withValues(alpha: .08),
    ),
    boxShadow: [
      BoxShadow(
        color: (dark ? Colors.black : YallaColors.navy)
            .withValues(alpha: dark ? .30 : .08),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

/// Store card on the home list. Tapping it opens [StoreDetailsPage].
class _StoreCard extends StatefulWidget {
  const _StoreCard({required this.store, required this.cubit});

  final PartnerStore store;
  final CustomerAppCubit cubit;

  @override
  State<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<_StoreCard> {
  bool _pressed = false;

  /// Below this text width (in unscaled units) the card stacks its layout.
  static const double _minTextWidth = 130;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Logo plate: 76 (68 on narrow phones). The card shows only the store's
    // identity — logo, name and partner badge; category and location live on
    // the store details page. Height follows content (no fixed height).
    final logoSize = MediaQuery.sizeOf(context).width < 360 ? 68.0 : 76.0;
    final radius = BorderRadius.circular(20);
    // Reduced motion: no press scale at all, not just an instant jump.
    final reduced = YcMotion.reduced(context);
    return AnimatedScale(
      scale: !reduced && _pressed ? .98 : 1,
      duration: YcMotion.resolve(context, YcMotion.fast),
      curve: Curves.easeOut,
      // Soft sky-blue-to-white surface with a hairline border and one gentle
      // shadow — the same tokens as the store details page. No large shapes.
      child: DecoratedBox(
        decoration: _storeSurface(context, radius: 20),
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: radius),
          // MergeSemantics must wrap the whole interactive subtree (not sit
          // inside it) for its button flag and the descendant text to be
          // combined into one node.
          child: MergeSemantics(
            child: Semantics(
              button: true,
              child: InkWell(
                splashColor: scheme.primary.withValues(alpha: .08),
                highlightColor: scheme.primary.withValues(alpha: .04),
                onTapDown: (_) => _setPressed(true),
                onTapCancel: () => _setPressed(false),
                onTap: () {
                  _setPressed(false);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          StoreDetailsPage(store: store, cubit: widget.cubit),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      // Width the text column would get beside the logo, in
                      // unscaled units. Too little (narrow phone + large text)
                      // and the card stacks instead of truncating words.
                      final besideWidth =
                          constraints.maxWidth - logoSize - 12 - 10 - 28;
                      final stacked = besideWidth / scale < _minTextWidth;
                      final logo = _StoreLogo(
                        url: store.logoUrl,
                        size: stacked ? 60 : logoSize,
                        heroTag: 'store-logo-${store.id}',
                        raised: false,
                      );
                      // Name and badge as one group, vertically centred
                      // against the logo.
                      final details = Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            store.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // The exact wording is always shown in full: on
                          // narrow screens or large text the pill scales
                          // down slightly instead of being cut.
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: _StoreCardPartnerBadge(),
                          ),
                        ],
                      );
                      if (stacked) {
                        // Logo and arrow on top; the text gets the full width.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                logo,
                                const Spacer(),
                                const _StoreCardArrow(),
                              ],
                            ),
                            const SizedBox(height: 10),
                            details,
                          ],
                        );
                      }
                      // RTL: logo on the right, the arrow on the far left.
                      return Row(
                        children: [
                          logo,
                          const SizedBox(width: 12),
                          Expanded(child: details),
                          const SizedBox(width: 10),
                          const _StoreCardArrow(),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold "exclusive partner" badge with the exact approved copy: a discreet
/// tint, a hairline gold border and a premium medal icon.
class _StoreCardPartnerBadge extends StatelessWidget {
  const _StoreCardPartnerBadge();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? YallaColors.gold : const Color(0xFF7A4F00);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: YallaColors.gold.withValues(alpha: dark ? .14 : .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: YallaColors.gold.withValues(alpha: .50)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Material Icons has no literal crown glyph; this premium medal
            // is the same mark used by the details-page exclusive badge.
            Icon(Icons.workspace_premium_rounded, size: 15, color: ink),
            const SizedBox(width: 5),
            Text(
              'شريك حصري لدى يلا كاش',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.2,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular "forward" arrow at the card's far (left) end.
class _StoreCardArrow extends StatelessWidget {
  const _StoreCardArrow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.primary.withValues(alpha: dark ? .16 : .10),
        ),
        // Left-pointing chevron = "forward" in RTL.
        child:
            Icon(Icons.chevron_left_rounded, size: 18, color: scheme.primary),
      ),
    );
  }
}

/// Dedicated store page: gradient header with an overlapping logo, the
/// existing store information, and the store's real, view-only exclusive
/// offers (loaded through [CustomerAppCubit.loadStoreOffers]).
class StoreDetailsPage extends StatelessWidget {
  const StoreDetailsPage({required this.store, required this.cubit, super.key});

  final PartnerStore store;
  final CustomerAppCubit cubit;

  static const double _logoSize = 132;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = store.description.trim();
    final location = store.location.trim();
    final headerHeight =
        MediaQuery.paddingOf(context).top + kToolbarHeight + 88;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: headerHeight + _logoSize / 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  bottom: _logoSize / 2,
                  child: const _StoreHeaderBackdrop(),
                ),
                Positioned(
                  top: headerHeight - _logoSize / 2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _StoreLogo(
                      url: store.logoUrl,
                      size: _logoSize,
                      heroTag: 'store-logo-${store.id}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
            child: _FadeSlideIn(
              child: Column(
                children: [
                  Text(
                    store.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const _ExclusiveBadge(),
                      _CategoryPill(store.category),
                    ],
                  ),
                  if (description.isNotEmpty || location.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _StoreInfoCard(
                      description: description,
                      location: location,
                    ),
                  ],
                  const SizedBox(height: 30),
                  const _OffersHeader(),
                  const SizedBox(height: 12),
                  _StoreOffersSection(cubit: cubit, storeId: store.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand gradient behind the details-page logo, with two soft decorative
/// circles. Uses a deeper navy-blue blend in dark mode.
class _StoreHeaderBackdrop extends StatelessWidget {
  const _StoreHeaderBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget circle(double size, double alpha) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: alpha),
          ),
          child: SizedBox(width: size, height: size),
        );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [Color(0xFF0B5F86), Color(0xFF123040)]
                : const [YallaColors.primary, YallaColors.primaryStrong],
          ),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -48,
              start: -36,
              child: circle(170, .09),
            ),
            PositionedDirectional(
              bottom: -60,
              end: -28,
              child: circle(190, .07),
            ),
          ],
        ),
      ),
    );
  }
}

/// Store description and location on the details page.
class _StoreInfoCard extends StatelessWidget {
  const _StoreInfoCard({required this.description, required this.location});

  final String description;
  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _storeSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              // Flexible: wraps instead of overflowing on 320dp + large text.
              Flexible(
                child: Text(
                  'عن المحل',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.7,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (description.isNotEmpty && location.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 16),
          ],
          if (location.isNotEmpty)
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: .12),
                ),
                child: Icon(Icons.location_on_rounded,
                    size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  location,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

/// "العروض الحصرية" section heading with a gold accent bar.
class _OffersHeader extends StatelessWidget {
  const _OffersHeader();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 5,
        height: 26,
        decoration: BoxDecoration(
          color: YallaColors.gold,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          'العروض الحصرية',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    ]);
  }
}

/// The store's offers section: loading, empty, error/retry or the offer
/// cards. It listens only to this store's offers in the Cubit, so the rest of
/// the page (header, logo Hero, store information) never rebuilds for it and
/// another store's offers can never appear here.
class _StoreOffersSection extends StatefulWidget {
  const _StoreOffersSection({required this.cubit, required this.storeId});

  final CustomerAppCubit cubit;
  final String storeId;

  @override
  State<_StoreOffersSection> createState() => _StoreOffersSectionState();
}

class _StoreOffersSectionState extends State<_StoreOffersSection> {
  Timer? _expiryTimer;
  DateTime? _expiryAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _load() => unawaited(widget.cubit.loadStoreOffers(widget.storeId));

  /// Rebuilds when the next shown offer reaches its exclusive endsBefore, so
  /// an offer disappears on time even while the page stays open.
  void _scheduleExpiryCheck(List<StoreOffer> shown, DateTime now) {
    DateTime? next;
    for (final offer in shown) {
      final end = offer.endsBefore;
      if (end != null && end.isAfter(now) && (next == null || end.isBefore(next))) {
        next = end;
      }
    }
    if (next == _expiryAt) return;
    _expiryTimer?.cancel();
    _expiryAt = next;
    if (next == null) return;
    // Capped so a distant boundary stays within timer limits (web); the
    // check simply runs again.
    var wait = next.difference(now) + const Duration(milliseconds: 50);
    if (wait > const Duration(hours: 6)) wait = const Duration(hours: 6);
    _expiryTimer = Timer(wait, () {
      if (mounted) setState(() => _expiryAt = null);
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<CustomerAppState>(
        stream: widget.cubit.stream,
        initialData: widget.cubit.state,
        builder: (context, snapshot) {
          final offers =
              (snapshot.data ?? widget.cubit.state).offersFor(widget.storeId);
          final now = DateTime.now();
          // The server already returns only available offers of an active
          // store; this re-check keeps the backend rule (startsAt <= now <
          // endsBefore, exclusive end) while the page is open, and only ever
          // shows offers that belong to this store.
          final shown = [
            for (final offer in offers.offers)
              if (offer.storeId == widget.storeId && offer.isAvailableAt(now))
                offer,
          ];
          _scheduleExpiryCheck(shown, now);

          final Widget child;
          if (shown.isNotEmpty) {
            child = Column(
              key: const ValueKey('store-offers-list'),
              children: [
                if (offers.status == LoadStatus.failure)
                  _StoreOffersInlineRetry(onRetry: _load),
                for (final offer in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _StoreOfferCard(key: ValueKey(offer.id), offer: offer),
                  ),
              ],
            );
          } else {
            child = switch (offers.status) {
              LoadStatus.initial ||
              LoadStatus.loading =>
                const _StoreOffersLoading(key: ValueKey('store-offers-loading')),
              // 404: the store is missing or inactive, so it has no offers.
              LoadStatus.failure when offers.failure?.statusCode != 404 =>
                _StoreOffersError(
                  key: const ValueKey('store-offers-error'),
                  message: _customerFailureMessage(offers.failure),
                  onRetry: _load,
                ),
              _ => const _StoreOffersEmptyState(
                  key: ValueKey('store-offers-empty')),
            };
          }
          return AnimatedSwitcher(
            duration: YcMotion.resolve(context, YcMotion.medium),
            child: child,
          );
        },
      );
}

/// Levantine month names, as used in Syria.
const _offerMonths = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

/// The offer's last day (inclusive Damascus calendar day, as the admin
/// entered it), never shifted through the device time zone.
String _offerExpiryText(StoreOffer offer) {
  final end = offer.endDate;
  if (end == null) return 'عرض مستمر';
  return 'ساري حتى ${end.day} ${_offerMonths[end.month - 1]} ${end.year}';
}

/// Public offer images only (the customer endpoint's versioned URL).
String? _publicOfferImageUrl(StoreOffer offer) {
  final url = offer.imageUrl;
  if (url == null || offer.imageAccess != OfferImageAccess.public) return null;
  final scheme = Uri.tryParse(url)?.scheme;
  return scheme == 'https' || scheme == 'http' ? url : null;
}

/// One view-only offer: image, discount label, title, description, expiry
/// and how to use it. No coupon, QR, points or purchase action.
class _StoreOfferCard extends StatelessWidget {
  const _StoreOfferCard({required this.offer, super.key});

  final StoreOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final imageUrl = _publicOfferImageUrl(offer);
    final label = offer.discountLabel?.trim() ?? '';
    final description = offer.description.trim();
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: _storeSurface(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null) _StoreOfferImage(url: imageUrl, title: offer.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.isNotEmpty) ...[
                  _OfferDiscountPill(label),
                  const SizedBox(height: 10),
                ],
                Text(
                  offer.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.4,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.7,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.event_available_rounded,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _offerExpiryText(offer),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            color: scheme.primary.withValues(
                alpha: theme.brightness == Brightness.dark ? .16 : .07),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phone_iphone_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'أبرز تطبيق يلا كاش عند المحاسبة للاستفادة من العرض',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole offer image, never cropped: its height follows the image's
/// own aspect ratio (letterboxed only beyond a maximum height). Hidden if it
/// fails to load.
class _StoreOfferImage extends StatelessWidget {
  const _StoreOfferImage({required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'صورة العرض: $title',
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
              frame == null && !wasSynchronouslyLoaded
                  ? AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Icon(Icons.image_outlined,
                          size: 34,
                          color: scheme.onSurfaceVariant.withValues(alpha: .5)),
                    )
                  : child,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Free-text discount label (display only; never calculated).
class _OfferDiscountPill extends StatelessWidget {
  const _OfferDiscountPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? YallaColors.gold : const Color(0xFF8A5A0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: YallaColors.gold.withValues(alpha: dark ? .18 : .16),
        borderRadius: BorderRadius.circular(YcRadius.pill),
        border: Border.all(color: YallaColors.gold.withValues(alpha: .5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_offer_rounded, size: 16, color: ink),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: ink,
                ),
          ),
        ),
      ]),
    );
  }
}

/// Static placeholder card while offers load (no shimmer, so it is calm
/// with reduced motion too).
class _StoreOffersLoading extends StatelessWidget {
  const _StoreOffersLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context)
        .colorScheme
        .onSurfaceVariant
        .withValues(alpha: .10);
    Widget bar(double? width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(8),
          ),
        );
    return Semantics(
      container: true,
      label: 'جارٍ تحميل العروض',
      child: ExcludeSemantics(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: _storeSurface(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              bar(double.infinity, 120),
              const SizedBox(height: 16),
              bar(96, 14),
              const SizedBox(height: 10),
              bar(double.infinity, 12),
              const SizedBox(height: 8),
              bar(160, 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreOffersError extends StatelessWidget {
  const _StoreOffersError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: _storeSurface(context),
        child: YcEmptyState(
          icon: Icons.wifi_off_rounded,
          tone: YcTone.danger,
          title: 'تعذر تحميل العروض',
          description: message,
          actionLabel: 'إعادة المحاولة',
          onAction: onRetry,
        ),
      );
}

/// Shown above existing offers when a reload failed.
class _StoreOffersInlineRetry extends StatelessWidget {
  const _StoreOffersInlineRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 18, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text('تعذر تحديث العروض.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ]),
    );
  }
}

/// Shown when the store has no offers available right now.
class _StoreOffersEmptyState extends StatelessWidget {
  const _StoreOffersEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: _storeSurface(context),
      child: Column(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary.withValues(alpha: .20),
                        YallaColors.gold.withValues(alpha: .20),
                      ],
                    ),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: .18),
                    ),
                  ),
                  child: const SizedBox(width: 84, height: 84),
                ),
                Icon(Icons.local_offer_rounded,
                    size: 38, color: scheme.primary),
                const PositionedDirectional(
                  top: 2,
                  end: 4,
                  child: Icon(Icons.auto_awesome_rounded,
                      size: 20, color: YallaColors.gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'لا توجد عروض متاحة حالياً',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ستظهر العروض الحصرية لهذا المحل هنا فور إضافتها.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Category label as a soft tinted pill.
class _CategoryPill extends StatelessWidget {
  const _CategoryPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Gold "حصري" (exclusive) pill shown on store cards and the details page.
class _ExclusiveBadge extends StatelessWidget {
  const _ExclusiveBadge();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? YallaColors.gold : const Color(0xFF8A5A00);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: YallaColors.gold.withValues(alpha: dark ? .16 : .20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: YallaColors.gold.withValues(alpha: .55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.workspace_premium_rounded, size: 13, color: ink),
            const SizedBox(width: 4),
            Text(
              'حصري',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle one-shot fade and rise for the details content. Skipped when the
/// system asks for reduced motion.
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Product image on a neutral plate. BoxFit.contain keeps the whole image
/// visible, never cropped or stretched. Falls back to a branded placeholder
/// when the product has no image or the image fails to load.
class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url, this.size = 64});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageUrl = url;
    Widget icon(Color color) => Center(
          child: Icon(Icons.redeem_rounded, size: size * .42, color: color),
        );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: imageUrl == null ? scheme.primaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(YcRadius.md),
        border: Border.all(color: YcSurface.of(context).hairline),
      ),
      child: imageUrl == null
          ? icon(scheme.primary)
          : Padding(
              padding: EdgeInsets.all(size * .08),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : icon(scheme.primary.withValues(alpha: .25)),
                errorBuilder: (_, __, ___) => icon(scheme.primary),
              ),
            ),
    );
  }
}

/// Store logo tile. Always shows the whole logo (BoxFit.contain, never cropped
/// or stretched) on a clean white plate so any artwork stays crisp in both
/// themes. Falls back to a branded storefront tile when the store has no logo
/// or the logo fails to load.
class _StoreLogo extends StatelessWidget {
  const _StoreLogo({
    required this.url,
    this.size = 56,
    this.heroTag,
    this.raised = true,
  });

  final String? url;
  final double size;

  /// Optional hero tag so the logo glides into the store details screen.
  final String? heroTag;

  /// Raised plates (details page) get a soft shadow. Flat plates (list cards)
  /// use a hairline border only, so the card stays calm.
  final bool raised;

  /// The plate sizes itself from its incoming constraints, so during a Hero
  /// flight it scales smoothly between the card and the details page.
  Widget _plate(BuildContext context, double s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final logoUrl = url;
    final storefront = s * 0.42;
    final loading = Center(
      child: Icon(
        Icons.storefront_rounded,
        size: storefront,
        color: YallaColors.primary.withValues(alpha: .25),
      ),
    );
    final failed = Center(
      child: Icon(
        Icons.storefront_rounded,
        size: storefront,
        color: YallaColors.primaryStrong,
      ),
    );
    return Container(
      width: s,
      height: s,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(s * 0.26),
        border: Border.all(
          color: YallaColors.navy.withValues(alpha: dark ? 0 : .07),
        ),
        boxShadow: raised
            ? [
                BoxShadow(
                  color: (dark ? Colors.black : YallaColors.navy)
                      .withValues(alpha: dark ? .38 : .14),
                  blurRadius: s * 0.22,
                  offset: Offset(0, s * 0.08),
                ),
              ]
            : null,
      ),
      child: logoUrl == null
          ? DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [YallaColors.primary, YallaColors.primaryStrong],
                ),
              ),
              child: Center(
                child: Icon(Icons.storefront_rounded,
                    size: storefront, color: Colors.white),
              ),
            )
          : raised
              // Details page: unchanged.
              ? Padding(
                  padding: EdgeInsets.all(s * 0.10),
                  child: Image.network(
                    logoUrl,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : loading,
                    errorBuilder: (_, __, ___) => failed,
                  ),
                )
              // List cards: a slim inset, and plain background margins inside
              // the image are trimmed from the *view* so marks with lots of
              // built-in whitespace stay visible (see WhitespaceTrimmedLogo).
              : Padding(
                  padding: EdgeInsets.all(s * 0.05),
                  child: WhitespaceTrimmedLogo(
                    url: logoUrl,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : loading,
                    errorBuilder: (_, __, ___) => failed,
                  ),
                ),
    );
  }

  /// Cross-fades from the card plate to the details plate (and back) during
  /// the Hero flight, since the card view may be whitespace-trimmed. The card
  /// plate stays opaque underneath, so the white plate never turns see-through.
  static Widget _shuttle(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final fromChild = (fromContext.widget as Hero).child;
    final toChild = (toContext.widget as Hero).child;
    // `animation` reads 0 at the list card and 1 at the details page in both
    // directions.
    final push = direction == HeroFlightDirection.push;
    final card = push ? fromChild : toChild;
    final details = push ? toChild : fromChild;
    return Stack(
      fit: StackFit.expand,
      children: [
        card,
        FadeTransition(opacity: animation, child: details),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = SizedBox(
      width: size,
      height: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return _plate(context, side.isFinite ? side : size);
        },
      ),
    );
    final tag = heroTag;
    if (tag == null) return tile;
    return Hero(
      tag: tag,
      // Straight-line flight (the default is an arc), which reads calmer.
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: _shuttle,
      child: tile,
    );
  }
}

class CustomerQrPage extends StatefulWidget {
  const CustomerQrPage({
    required this.cubit,
    required this.state,
    required this.customer,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final Customer customer;

  @override
  State<CustomerQrPage> createState() => _CustomerQrPageState();
}

class _CustomerQrPageState extends State<CustomerQrPage> {
  bool requesting = false;

  /// Periodically re-checks the current token while this page stays mounted
  /// (e.g. the user leaves it open past the 120s TTL) so an idle screen
  /// self-heals instead of continuing to display an expired QR. This does
  /// NOT force a new token every tick — it just re-runs the same
  /// [_ensureQrToken] check, which only issues a new token when the current
  /// one is missing or within its existing 10-second safety margin.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _ensureQrToken();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _ensureQrToken(),
    );
  }

  @override
  void didUpdateWidget(covariant CustomerQrPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.id != widget.customer.id ||
        oldWidget.state.qrToken != widget.state.qrToken) {
      _ensureQrToken();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _ensureQrToken() {
    final token = widget.state.qrToken;
    final validUntil = DateTime.now().add(const Duration(seconds: 10));
    if (requesting || (token != null && token.expiresAt.isAfter(validUntil))) {
      return;
    }
    requesting = true;
    widget.cubit.issueQrToken().whenComplete(() {
      if (mounted) setState(() => requesting = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.state.qrToken;
    final failure = widget.state.failure;
    final danger = YcToneColors.of(context, YcTone.danger).foreground;
    // No stretch/glow overscroll on this page: the stretch effect would
    // scale the QR while the list is pulled. Pull-to-refresh still works.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          YcSpace.gutter,
          YcSpace.sm,
          YcSpace.gutter,
          YcSpace.xl,
        ),
        children: [
          const YcSectionHeader('كودك الشخصي'),
          const SizedBox(height: YcSpace.sm),
          YcCard(
            padding: const EdgeInsets.fromLTRB(
              YcSpace.lg,
              YcSpace.xl,
              YcSpace.lg,
              YcSpace.lg,
            ),
            child: Column(
              children: [
                _QrPlate(token: token),
                const SizedBox(height: YcSpace.lg),
                Text(
                  widget.customer.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: YcType.item(context),
                ),
                const SizedBox(height: 2),
                // A short reference instead of the full technical id. Merchants
                // identify customers only by scanning the QR token.
                Text(
                  _shortCustomerRef(widget.customer.id),
                  textDirection: TextDirection.ltr,
                  style: YcType.meta(context),
                ),
                if (token != null) ...[
                  const SizedBox(height: YcSpace.sm),
                  _QrExpiry(text: 'ينتهي في ${_formatTime(token.expiresAt)}'),
                ],
              ],
            ),
          ),
          const SizedBox(height: YcSpace.md),
          const _QrInstructionCard(),
          if (failure != null && token == null) ...[
            const SizedBox(height: YcSpace.md),
            YcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: danger),
                      const SizedBox(width: YcSpace.xs),
                      Expanded(
                        child: Text(
                          _customerFailureMessage(failure),
                          style: YcType.body(context)?.copyWith(color: danger),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: YcSpace.sm),
                  OutlinedButton.icon(
                    onPressed: _ensureQrToken,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "How do you earn points?" instruction card beneath the QR. A small,
/// restrained icon sits at the card's start side (the right, in RTL) with
/// the title and description as one aligned text block beside it. Both are
/// top-aligned against the icon, so a 1-line or 3-line description never
/// shifts the icon off-centre.
class _QrInstructionCard extends StatelessWidget {
  const _QrInstructionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return YcCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const YcIconBadge(Icons.qr_code_scanner_rounded),
          const SizedBox(width: YcSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كيف تجمع نقاطك؟',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'أبرز الكود للكاشير عند الدفع. ستُضاف نقاطك تلقائياً بعد '
                  'تسجيل الفاتورة.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "#…" plus the last six characters of [id]; short ids are shown in full.
String _shortCustomerRef(String id) =>
    id.length <= 8 ? '#$id' : '#…${id.substring(id.length - 6)}';

/// White QR plate. The QR is never animated, tinted or distorted: the same
/// payload and styling as before (navy modules on pure white), at 210px with
/// the plate's 18px padding plus the QR's own padding as quiet zone. The plate
/// ignores text scaling and only shrinks, staying square, on very narrow
/// screens.
class _QrPlate extends StatelessWidget {
  const _QrPlate({required this.token});

  final CustomerQrToken? token;

  static const double _plate = 246;
  static const double _padding = 18;

  @override
  Widget build(BuildContext context) {
    final t = token;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side =
            constraints.maxWidth < _plate ? constraints.maxWidth : _plate;
        return Center(
          child: Container(
            width: side,
            height: side,
            padding: const EdgeInsets.all(_padding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            // The hairline is painted on top, not laid out: a layout border
            // would shrink the QR below its exact 210px.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: YallaColors.navy.withValues(alpha: .08),
              ),
            ),
            child: t == null
                ? const Center(child: CircularProgressIndicator())
                : Semantics(
                    label: 'كود QR الشخصي',
                    image: true,
                    child: ExcludeSemantics(
                      child: QrImageView(
                        data: t.payload,
                        version: QrVersions.auto,
                        size: side - _padding * 2,
                        eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: YallaColors.navy),
                        dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: YallaColors.navy),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

/// Expiry time on a soft pill. Only this text cross-fades when the token
/// is refreshed; the QR itself never animates.
class _QrExpiry extends StatelessWidget {
  const _QrExpiry({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = YcToneColors.of(context, YcTone.brand);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(YcRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YcSpace.sm,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: brand.foreground),
            const SizedBox(width: 6),
            Flexible(
              child: AnimatedSwitcher(
                duration: YcMotion.resolve(context, YcMotion.medium),
                child: Text(
                  text,
                  key: ValueKey(text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: brand.foreground,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerWalletPage extends StatelessWidget {
  const CustomerWalletPage({
    required this.transactions,
    required this.customer,
    this.productRedemptions = const [],
    this.cashRequests = const [],
    this.loading = false,
    this.failed = false,
    this.onRetry,
    super.key,
  });

  final List<LoyaltyTransaction> transactions;
  final Customer customer;

  /// Persistent history of the customer's own digital-product redemption
  /// requests. Every request — PENDING, FULFILLED, or REJECTED — stays
  /// visible here permanently; a FULFILLED entry is only visually dimmed,
  /// never removed.
  final List<ProductRedemption> productRedemptions;

  /// The customer's cash withdrawal requests, in the order they arrive.
  final List<CashRedemptionRequest> cashRequests;

  /// The wallet data has not arrived yet. Lists show quiet placeholders
  /// instead of a false "nothing here yet" message.
  final bool loading;

  /// Loading the wallet data failed; shows a retry state.
  final bool failed;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        YcSpace.gutter,
        YcSpace.sm,
        YcSpace.gutter,
        YcSpace.xl,
      ),
      children: [
        if (failed)
          YcEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'تعذر تحميل السجل',
            description: 'تحقق من اتصالك ثم حاول مرة أخرى.',
            actionLabel: retry == null ? null : 'إعادة المحاولة',
            onAction: retry,
          )
        else ...[
          const YcSectionHeader('سجل العمليات'),
          const SizedBox(height: YcSpace.sm),
          if (loading)
            const YcSkeleton()
          else if (transactions.isEmpty)
            const YcEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'لا توجد عمليات حتى الآن',
            )
          else
            ...transactions.map((transaction) => Padding(
                  padding: const EdgeInsets.only(bottom: YcSpace.xs),
                  child: _TransactionTile(transaction: transaction),
                )),
          const SizedBox(height: YcSpace.xl),
          const YcSectionHeader('طلبات سحب الكاش'),
          const SizedBox(height: YcSpace.sm),
          if (loading)
            const YcSkeleton(rows: 2)
          else if (cashRequests.isEmpty)
            const YcEmptyState(
              icon: Icons.payments_outlined,
              title: 'لا توجد طلبات سحب بعد',
            )
          else
            ...cashRequests.map((request) => Padding(
                  padding: const EdgeInsets.only(bottom: YcSpace.xs),
                  child: _CashRequestTile(request: request),
                )),
          const SizedBox(height: YcSpace.xl),
          const YcSectionHeader('طلبات استبدال المنتجات'),
          const SizedBox(height: YcSpace.sm),
          if (loading)
            const YcSkeleton(rows: 2)
          else if (productRedemptions.isEmpty)
            const YcEmptyState(
              icon: Icons.redeem_outlined,
              title: 'لا توجد طلبات استبدال بعد',
            )
          else
            ...productRedemptions.map((redemption) => Padding(
                  padding: const EdgeInsets.only(bottom: YcSpace.xs),
                  child: _RedemptionTile(redemption: redemption),
                )),
        ],
      ],
    );
  }
}

/// An earned-points entry: store, date, invoice amount and the points
/// earned. Transactions carry no other status, so each one is a credit,
/// marked with the success tone and a "+" amount.
class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final LoyaltyTransaction transaction;

  @override
  Widget build(BuildContext context) => YcCard(
        padding: EdgeInsets.zero,
        child: YcListRow(
          icon: Icons.receipt_long_rounded,
          iconTone: YcTone.success,
          title: transaction.storeName,
          subtitle: '${formatDate(transaction.createdAt)} · فاتورة '
              '${formatNumber(transaction.amountSyp)} ل.س',
          // Value and unit on one line, matching the redemption tile below.
          trailing: _PointsAmount(
            '+${formatNumber(transaction.customerPointsEarned)} نقطة',
            color: YcToneColors.of(context, YcTone.success).foreground,
            unit: false,
          ),
        ),
      );
}

/// A cash withdrawal request: the cash amount, its date and points, and the
/// real status from the data (pending, settled or rejected).
class _CashRequestTile extends StatelessWidget {
  const _CashRequestTile({required this.request});

  final CashRedemptionRequest request;

  @override
  Widget build(BuildContext context) => YcCard(
        padding: EdgeInsets.zero,
        child: YcListRow(
          icon: Icons.payments_outlined,
          title: '${formatNumber(request.cashValueSyp)} ل.س',
          subtitle: '${formatDate(request.createdAt)} · '
              '${formatNumber(request.pointsRequested)} نقطة',
          trailing: _cashRequestStatusChip(request.status),
        ),
      );
}

YcStatusChip _cashRequestStatusChip(CashRequestStatus status) {
  switch (status) {
    case CashRequestStatus.pending:
      return const YcStatusChip.pending('قيد المعالجة');
    case CashRequestStatus.settled:
      return const YcStatusChip.completed('تم الصرف');
    case CashRequestStatus.rejected:
      return const YcStatusChip.rejected('تم رفض الطلب');
  }
}

/// A digital-product redemption request with its status chip.
class _RedemptionTile extends StatelessWidget {
  const _RedemptionTile({required this.redemption});

  final ProductRedemption redemption;

  @override
  Widget build(BuildContext context) {
    final phone = redemption.phoneNumber;
    final tile = YcCard(
      padding: EdgeInsets.zero,
      child: YcListRow(
        icon: Icons.redeem_rounded,
        title: redemption.productName ?? 'منتج رقمي',
        subtitle: [
          formatDate(redemption.createdAt),
          if (phone != null && phone.isNotEmpty) phone,
        ].join(' · '),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _PointsAmount(
              '${formatNumber(redemption.pointsCostSnapshot)} نقطة',
              unit: false,
            ),
            const SizedBox(height: YcSpace.xxs),
            _redemptionStatusChip(redemption.status),
          ],
        ),
      ),
    );
    // Only the completed (FULFILLED) history entry is dimmed — the
    // request is kept permanently, never removed, just visually
    // muted. PENDING/REJECTED entries render at full opacity.
    return redemption.status == RedemptionStatus.fulfilled
        ? Opacity(opacity: 0.55, child: tile)
        : tile;
  }
}

/// Points figure for list trailing slots. With [unit], a quiet "نقطة"
/// line sits under the figure.
class _PointsAmount extends StatelessWidget {
  const _PointsAmount(this.text, {this.color, this.unit = true});

  final String text;
  final Color? color;
  final bool unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (unit) Text('نقطة', style: YcType.meta(context)),
      ],
    );
  }
}

YcStatusChip _redemptionStatusChip(RedemptionStatus status) {
  final label = _productRedemptionStatusLabel(status);
  switch (status) {
    case RedemptionStatus.pending:
      return YcStatusChip.pending(label);
    case RedemptionStatus.fulfilled:
      return YcStatusChip.completed(label);
    case RedemptionStatus.rejected:
      return YcStatusChip.rejected(label);
  }
}

String _productRedemptionStatusLabel(RedemptionStatus status) {
  switch (status) {
    case RedemptionStatus.pending:
      return 'طلبك قيد المراجعة';
    case RedemptionStatus.fulfilled:
      return 'تم الاستبدال';
    case RedemptionStatus.rejected:
      return 'تم رفض الطلب';
  }
}

/// Visual progress toward a product: the customer's available points over
/// the product's cost, clamped to 0–1. A product that costs nothing counts
/// as fully reachable.
double _progressTowards(int availablePoints, int costInPoints) {
  if (costInPoints <= 0) return 1;
  return (availablePoints / costInPoints).clamp(0.0, 1.0);
}

/// Motivational copy for a product's progress bar, from the exact same
/// [progress] value the bar renders (0–1). Carries no point numbers or
/// percentages. Thresholds are inclusive at the lower bound.
String _motivationFor(double progress) {
  if (progress >= 1) return 'مبروك! مكافأتك جاهزة للاستبدال';
  if (progress >= .75) return 'باقيلك شوي، مكافأتك صارت قريبة!';
  if (progress >= .5) return 'قطعت شوط حلو نحو مكافأتك!';
  if (progress >= .25) return 'بداية حلوة، كمّل تجميع!';
  if (progress > 0) return 'كل نقطة بتقرّبك من مكافأتك!';
  return 'رحلتك للمكافأة بتبدأ من هون!';
}

class CustomerRewardsPage extends StatefulWidget {
  const CustomerRewardsPage(
      {required this.cubit, required this.state, super.key});

  final CustomerAppCubit cubit;
  final CustomerAppState state;

  @override
  State<CustomerRewardsPage> createState() => _CustomerRewardsPageState();
}

class _CustomerRewardsPageState extends State<CustomerRewardsPage> {
  final cashPointsController = TextEditingController();

  /// In-flight guards so a double tap cannot send the same request twice.
  /// They only disable buttons; the submission code itself is unchanged.
  bool _submittingCash = false;
  String? _redeemingProductId;

  @override
  void dispose() {
    cashPointsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.state.customer!;
    final requested = int.tryParse(cashPointsController.text) ?? 0;
    final pointValue = _pointValueSyp(widget.state.cashRequests);
    // Points, products and requests arrive in one batch with the points
    // summary, so a null summary means that data has not loaded yet.
    final summary = widget.state.points;
    final failed = summary == null && widget.state.status == LoadStatus.failure;
    final loading = summary == null && !failed;
    // The real available points, or null while unknown. There is no
    // fallback to the total balance: redemption waits until this is loaded.
    final available = summary?.availablePoints;
    // Submission rule: unchanged once available points are known.
    final canSubmitCash =
        available != null && requested > 0 && requested <= available;
    // Feedback mirrors that rule exactly: an error shows only when something
    // was typed and the rule rejects it (never while the balance is unknown).
    final String? cashError = available == null ||
            cashPointsController.text.trim().isEmpty ||
            canSubmitCash
        ? null
        : requested <= 0
            ? 'أدخل عدداً صحيحاً أكبر من صفر'
            : 'العدد أكبر من رصيدك المتاح';
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        YcSpace.gutter,
        YcSpace.sm,
        YcSpace.gutter,
        YcSpace.xl,
      ),
      children: [
        _AvailablePointsCard(
          summary: summary,
          failed: failed,
          onRetry: widget.cubit.refresh,
        ),
        const SizedBox(height: YcSpace.xl),
        const YcSectionHeader('استبدال نقاط بكاش'),
        const SizedBox(height: YcSpace.sm),
        YcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: cashPointsController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'عدد النقاط',
                  prefixIcon: const Icon(Icons.savings_outlined),
                  suffixText: 'نقطة',
                  errorText: cashError,
                  helperText: available == null
                      ? 'يتاح الإرسال بعد تحميل رصيدك المتاح'
                      : cashError == null
                          ? 'الحد الأقصى ${formatNumber(available)} نقطة'
                          : null,
                ),
              ),
              const SizedBox(height: YcSpace.sm),
              _ConversionRow(valueSyp: (requested * pointValue).round()),
              const SizedBox(height: YcSpace.md),
              FilledButton(
                onPressed: canSubmitCash && !_submittingCash
                    ? () => _submitCash(customer, requested)
                    : null,
                child: _submittingCash
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Text('إرسال طلب الاستبدال'),
              ),
            ],
          ),
        ),
        const SizedBox(height: YcSpace.xl),
        const YcSectionHeader('منتجات رقمية'),
        const SizedBox(height: YcSpace.sm),
        if (failed)
          YcEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'تعذر تحميل المنتجات',
            actionLabel: 'إعادة المحاولة',
            onAction: widget.cubit.refresh,
          )
        else if (loading)
          const YcSkeleton(rows: 2)
        else if (widget.state.products.isEmpty)
          const YcEmptyState(
            icon: Icons.redeem_outlined,
            title: 'لا توجد منتجات متاحة حالياً',
          )
        else
          ...widget.state.products.map((product) {
            // Only an ACTIVE PENDING request for this exact product blocks
            // a new one — a past FULFILLED/REJECTED request never does, so
            // the same digital product can be redeemed again over time.
            final hasPendingRequest = widget.state.productRedemptions.any(
              (redemption) =>
                  redemption.productId == product.id &&
                  redemption.status == RedemptionStatus.pending,
            );
            // Progress is shown for every active product without a pending
            // request, from the real available points (never the total).
            final progress =
                available != null && product.isActive && !hasPendingRequest
                    ? _progressTowards(available, product.costInPoints)
                    : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: YcSpace.sm),
              child: _ProductCard(
                product: product,
                hasPendingRequest: hasPendingRequest,
                // Unchanged redemption rule once available points are
                // known, plus the in-flight guard.
                canRedeem: available != null &&
                    available >= product.costInPoints &&
                    _redeemingProductId == null,
                busy: _redeemingProductId == product.id,
                progress: progress,
                onRedeem: () => _startRedeem(customer, product),
              ),
            );
          }),
      ],
    );
  }

  Future<void> _submitCash(Customer customer, int points) async {
    // A second tap in the same frame still reaches the enabled button.
    if (_submittingCash) return;
    setState(() => _submittingCash = true);
    try {
      await _requestCash(customer, points);
    } finally {
      if (mounted) setState(() => _submittingCash = false);
    }
  }

  Future<void> _startRedeem(Customer customer, DigitalProduct product) async {
    if (_redeemingProductId != null) return;
    setState(() => _redeemingProductId = product.id);
    try {
      await _redeemProduct(customer, product);
    } finally {
      if (mounted) setState(() => _redeemingProductId = null);
    }
  }

  Future<void> _requestCash(Customer customer, int points) async {
    await widget.cubit.requestCashRedemption(points);
    if (!mounted) return;
    if (widget.cubit.state.failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_customerFailureMessage(widget.cubit.state.failure))),
      );
      return;
    }
    cashPointsController.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال الطلب، وبانتظار محاسبة الإدارة.')),
    );
  }

  Future<void> _redeemProduct(Customer customer, DigitalProduct product) async {
    String? phone;
    if (product.requiresPhoneNumber) {
      // The dialog widget owns its TextEditingController and disposes it in
      // State.dispose(), so the exit animation can never touch a disposed
      // controller.
      phone = await showDialog<String>(
        context: context,
        builder: (_) => const _PhoneNumberDialog(),
      );
      if (phone == null || phone.trim().length < 8) return;
    }
    await widget.cubit.redeemDigitalProduct(product, phoneNumber: phone);
    if (!mounted) return;
    if (widget.cubit.state.failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_customerFailureMessage(widget.cubit.state.failure))),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم طلب «${product.name}» بنجاح.')));
  }

  double _pointValueSyp(List<CashRedemptionRequest> requests) {
    for (final request in requests) {
      if (request.pointsRequested > 0) {
        return request.cashValueSyp / request.pointsRequested;
      }
    }
    return 5;
  }
}

/// Available-points summary at the top of the store tab. Shows the real
/// available points once loaded, a quiet placeholder while loading, and a
/// retry when loading failed (never the total balance in their place).
class _AvailablePointsCard extends StatelessWidget {
  const _AvailablePointsCard({
    required this.summary,
    required this.failed,
    required this.onRetry,
  });

  final PointsSummary? summary;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final Widget value;
    if (s != null) {
      value = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          '${formatNumber(s.availablePoints)} نقطة',
          maxLines: 1,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    } else if (failed) {
      value = Row(
        children: [
          Flexible(
            child: Text(
              'تعذر تحميل الرصيد',
              style: YcType.meta(context)?.copyWith(
                color: YcToneColors.of(context, YcTone.danger).foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      );
    } else {
      value = Semantics(
        label: 'جارٍ التحميل',
        child: Container(
          width: 120,
          height: 22,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(
                alpha: theme.brightness == Brightness.dark ? .10 : .07),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      );
    }
    return YcCard(
      child: Row(
        children: [
          const YcIconBadge(Icons.account_balance_wallet_rounded, size: 48),
          const SizedBox(width: YcSpace.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رصيدك المتاح', style: YcType.meta(context)),
                const SizedBox(height: 2),
                value,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live cash value of the typed points ("القيمة"), on a soft tinted panel.
class _ConversionRow extends StatelessWidget {
  const _ConversionRow({required this.valueSyp});

  final int valueSyp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return MergeSemantics(
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: dark ? .14 : .07),
            borderRadius: BorderRadius.circular(YcRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: YcSpace.md,
              vertical: YcSpace.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.payments_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: YcSpace.xs),
                Text(
                  'القيمة',
                  style: YcType.meta(context)
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: YcSpace.sm),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      '${formatNumber(valueSyp)} ل.س',
                      maxLines: 1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Digital product card: uncropped image, name and cost, then a bottom row
/// with the progress bar (eligible products only) and the action.
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.hasPendingRequest,
    required this.canRedeem,
    required this.busy,
    required this.progress,
    required this.onRedeem,
  });

  final DigitalProduct product;
  final bool hasPendingRequest;
  final bool canRedeem;
  final bool busy;

  /// Null hides the bar (inactive product or a pending request).
  final double? progress;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final Widget action = hasPendingRequest
        ? const YcStatusChip.pending('قيد المراجعة')
        : FilledButton.tonal(
            onPressed: canRedeem && !busy ? onRedeem : null,
            // The shared theme makes filled buttons full width; this one
            // sits in a row, so it gets a compact size.
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 40),
              padding: const EdgeInsets.symmetric(horizontal: YcSpace.md),
            ),
            // While busy the button is only disabled: the flow may be showing
            // the phone dialog, so no spinner runs behind it.
            child: const Text(
              'استبدال',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
    return YcCard(
      padding: const EdgeInsets.symmetric(
        horizontal: YcSpace.md,
        vertical: YcSpace.sm,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ProductImage(url: product.imageUrl, size: 64),
              const SizedBox(width: YcSpace.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatNumber(product.costInPoints)} نقطة',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            YcToneColors.of(context, YcTone.brand).foreground,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: YcSpace.xs),
          // The action may take at most 60% of the row, so a long status
          // shrinks (chips ellipsize) instead of overflowing at large text.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: p == null
                      ? const SizedBox.shrink()
                      : YcProgressBar(
                          value: p,
                          semanticLabel: 'التقدم نحو ${product.name}',
                        ),
                ),
                const SizedBox(width: YcSpace.md),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth * .6),
                  child: action,
                ),
              ],
            ),
          ),
          // Directly beneath the bar, spanning the full card width. Only for
          // an eligible product: the real progress is known (balance loaded)
          // and there is no pending request — the same condition the bar
          // itself uses, so the two never disagree.
          if (p != null) ...[
            const SizedBox(height: YcSpace.xxs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _ProductMotivation(progress: p),
            ),
          ],
        ],
      ),
    );
  }
}

/// Short motivational line beneath an eligible product's progress bar.
/// Carries no point numbers or percentages — only the fixed copy for each
/// real progress threshold. Cross-fades when the message changes; the swap
/// is instant under reduced motion rather than skipped, so the new message
/// is still shown.
class _ProductMotivation extends StatelessWidget {
  const _ProductMotivation({required this.progress});

  /// Same 0–1 value the progress bar renders.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final complete = progress >= 1;
    final tone = complete ? YcTone.success : YcTone.brand;
    final color = YcToneColors.of(context, tone).foreground;
    final message = _motivationFor(progress);
    return AnimatedSwitcher(
      duration: YcMotion.resolve(context, YcMotion.medium),
      child: Row(
        key: ValueKey(message),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            complete ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _captionStyle(context, color),
            ),
          ),
        ],
      ),
    );
  }

  /// Restrained, brand-coloured caption style.
  TextStyle? _captionStyle(BuildContext context, Color color) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          );
}

/// Phone-number prompt for digital product redemption. Owns its own
/// TextEditingController lifecycle.
class _PhoneNumberDialog extends StatefulWidget {
  const _PhoneNumberDialog();

  @override
  State<_PhoneNumberDialog> createState() => _PhoneNumberDialogState();
}

class _PhoneNumberDialogState extends State<_PhoneNumberDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('رقم الهاتف'),
        content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: '09xxxxxxxx')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('تأكيد')),
        ],
      );
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
