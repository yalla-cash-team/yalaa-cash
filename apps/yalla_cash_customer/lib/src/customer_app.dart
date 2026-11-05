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
      ));
    } else if (!signedIn && _pushActive) {
      _pushActive = false;
      unawaited(_push.signOut());
    }
  }

  // Android does not display notifications while the app is open, so they
  // are shown here as a snackbar.
  void _showForegroundMessage(RemoteMessage message) {
    final text = [message.notification?.title, message.notification?.body]
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join('\n');
    if (text.isEmpty) return;
    _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(text)));
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
          theme: buildYallaTheme(Brightness.light),
          darkTheme: buildYallaTheme(Brightness.dark),
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
      CustomerWalletPage(
          transactions: widget.state.transactions,
          customer: customer,
          productRedemptions: widget.state.productRedemptions),
      CustomerRewardsPage(cubit: widget.cubit, state: widget.state),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const YallaCashLogo(height: 34, markOnly: true),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('يلا كاش',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w900)),
                Text(
                  'مرحباً ${customer.name.split(' ').first}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(
                leading:
                    CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                title: Text('إعدادات الحساب',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('اللغة، المظهر والتواصل'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('تغيير المحافظة'),
                subtitle: Text(customer.governorate),
                onTap: _changeGovernorate,
              ),
              SwitchListTile(
                value: widget.darkMode,
                onChanged: widget.onDarkModeChanged,
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('الوضع الداكن'),
              ),
              const ListTile(
                  leading: Icon(Icons.language_rounded),
                  title: Text('اللغة'),
                  trailing: Text('العربية')),
              ListTile(
                  leading: const Icon(Icons.message_outlined),
                  title: const Text('تواصل معنا'),
                  onTap: _contactUsOnWhatsApp),
              ListTile(
                  leading: const Icon(Icons.star_outline_rounded),
                  title: const Text('قيّم التطبيق'),
                  onTap: _rateAppOnGooglePlay),
              ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded),
                  title: const Text('ادعُ أصدقاءك واربح نقاط'),
                  onTap: () {
                    Navigator.pop(context);
                    _showShareSheet(context);
                  }),
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: Text('تسجيل الخروج',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: widget.cubit.logout,
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        // Pull-to-refresh re-syncs every section (profile, points, stores,
        // transactions, products, cash requests AND banners) from the server.
        child: RefreshIndicator(
          onRefresh: () => widget.cubit.refresh(),
          child: IndexedStack(index: selectedIndex, children: pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          final changed = index != selectedIndex;
          setState(() => selectedIndex = index);
          // Re-sync authoritative data when switching sections so Home /
          // Wallet / Rewards never remain stale after admin-side changes.
          if (changed) unawaited(widget.cubit.refresh());
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'الرئيسية'),
          NavigationDestination(
              icon: Icon(Icons.qr_code_2_rounded), label: 'كودي'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: 'المحفظة'),
          NavigationDestination(
              icon: Icon(Icons.redeem_outlined), label: 'المتجر'),
        ],
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
const _shareAppMessage =
    'حمّل تطبيق يلا كاش واستبدل نقاطك بكاش! '
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
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
    return ListView(
      key: const PageStorageKey('customer-home'),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        _BalanceCard(points: points),
        const SizedBox(height: 18),
        if (banners.isNotEmpty)
          _HomeBannerCarousel(banners: banners),
        const SizedBox(height: 22),
        const _SectionTitle('المحلات الحصرية بمدينتك'),
        const SizedBox(height: 10),
        if (stores.isEmpty)
          const _EmptyState(
              icon: Icons.storefront_outlined,
              text: 'لا توجد محلات متاحة حالياً')
        else
          ...stores.map((partner) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StoreCard(store: partner),
              )),
      ],
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
        child: PageView.builder(
          controller: _controller,
          itemCount: widget.banners.length,
          onPageChanged: (index) => _page = index,
          itemBuilder: (context, index) {
            final banner = widget.banners[index];
            final externalUrl = _validExternalBannerUrl(banner.targetUrl);
            return GestureDetector(
              // A null onTap makes this a no-op tap target without
              // affecting PageView's own horizontal swipe gesture — swipe
              // and this tap detector coexist normally in Flutter's gesture
              // arena, no special handling needed.
              onTap: externalUrl == null
                  ? null
                  : () => _openBannerUrl(externalUrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
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
                        // A failed image (404, network hiccup, stale URL) must
                        // never crash or blank out just this one banner — the
                        // carousel keeps auto-rotating through the rest
                        // regardless, since each page's Image error is scoped
                        // to that page only.
                        errorBuilder: (context, error, stackTrace) =>
                            ColoredBox(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Center(
                              child: Icon(Icons.image_not_supported_outlined)),
                        ),
                      ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.points});

  final PointsSummary? points;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [YallaColors.primaryStrong, YallaColors.primary],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: YallaColors.primary.withValues(alpha: .24),
                blurRadius: 24,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                    color: YallaColors.gold, shape: BoxShape.circle),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: YallaCashLogo(
                    height: 27,
                    markOnly: true,
                    color: YallaColors.navy,
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رصيد النقاط',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                if (points == null)
                  const SizedBox(
                    width: 112,
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                    ),
                  )
                else
                  Text(
                    formatNumber(points!.pointsBalance),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900),
                  ),
                if (points != null && points!.heldPoints > 0)
                  Text(
                      'منها ${formatNumber(points!.heldPoints)} نقطة قيد المعالجة',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ],
        ),
      );
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.store});

  final PartnerStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        tilePadding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: _StoreLogo(url: store.logoUrl),
        title: Text(
          store.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Flexible(
              child: Text(
                store.category,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  'حصري',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ]),
        ),
        children: [
          Text(
            store.description,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.location_on_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(store.location)),
          ]),
        ],
      ),
    );
  }
}

/// Product image, or a placeholder tile when the product has no image.
class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Icon(Icons.redeem_rounded, size: 28, color: scheme.primary);
    final imageUrl = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 64,
        height: 64,
        child: ColoredBox(
          color: scheme.primaryContainer,
          child: imageUrl == null
              ? Center(child: placeholder)
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(child: placeholder),
                ),
        ),
      ),
    );
  }
}

/// Store logo tile. Falls back to the default storefront icon when the store
/// has no logo or the logo fails to load.
class _StoreLogo extends StatelessWidget {
  const _StoreLogo({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final logoUrl = url;
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(logoUrl == null ? 0 : 6),
      decoration: BoxDecoration(
        color: logoUrl == null ? YallaColors.primaryStrong : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: logoUrl == null
          ? const Icon(Icons.storefront_rounded, size: 26, color: Colors.white)
          : Image.network(
              logoUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.storefront_rounded,
                size: 26,
                color: YallaColors.primaryStrong,
              ),
            ),
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
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const _SectionTitle('كودك الشخصي'),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              children: [
                Container(
                  width: 246,
                  height: 246,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22)),
                  child: token == null
                      ? const Center(child: CircularProgressIndicator())
                      : QrImageView(
                          data: token.payload,
                          version: QrVersions.auto,
                          size: 210,
                          eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: YallaColors.navy),
                          dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: YallaColors.navy),
                        ),
                ),
                const SizedBox(height: 16),
                Text(widget.customer.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
                Text('#${widget.customer.id}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (token != null)
                  Text('ينتهي في ${_formatTime(token.expiresAt)}',
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'اعرض هذا الكود على الكاشير عند الدفع، وستضاف نقاطك تلقائياً بعد تسجيل الفاتورة.',
          textAlign: TextAlign.center,
        ),
        if (failure != null && token == null) ...[
          const SizedBox(height: 12),
          Text(
            _customerFailureMessage(failure),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _ensureQrToken,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ],
    );
  }
}

class CustomerWalletPage extends StatelessWidget {
  const CustomerWalletPage({
    required this.transactions,
    required this.customer,
    this.productRedemptions = const [],
    super.key,
  });

  final List<LoyaltyTransaction> transactions;
  final Customer customer;

  /// Persistent history of the customer's own digital-product redemption
  /// requests. Every request — PENDING, FULFILLED, or REJECTED — stays
  /// visible here permanently; a FULFILLED entry is only visually dimmed,
  /// never removed.
  final List<ProductRedemption> productRedemptions;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const _SectionTitle('سجل العمليات'),
        const SizedBox(height: 10),
        if (transactions.isEmpty)
          const _EmptyState(
              icon: Icons.receipt_long_outlined,
              text: 'لا توجد عمليات حتى الآن')
        else
          ...transactions.map((transaction) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.receipt_long_outlined)),
                  title: Text(transaction.storeName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${formatDate(transaction.createdAt)} · فاتورة ${formatNumber(transaction.amountSyp)} ل.س'),
                  trailing: Text(
                    '+${formatNumber(transaction.customerPointsEarned)}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w900),
                  ),
                ),
              )),
        const SizedBox(height: 22),
        const _SectionTitle('طلبات استبدال المنتجات'),
        const SizedBox(height: 10),
        if (productRedemptions.isEmpty)
          const _EmptyState(
              icon: Icons.redeem_outlined, text: 'لا توجد طلبات استبدال بعد')
        else
          ...productRedemptions.map((redemption) {
            final card = Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                    child:
                        Icon(_productRedemptionStatusIcon(redemption.status))),
                title: Text(redemption.productName ?? 'منتج رقمي',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(
                  [
                    formatDate(redemption.createdAt),
                    if (redemption.phoneNumber != null &&
                        redemption.phoneNumber!.isNotEmpty)
                      redemption.phoneNumber!,
                  ].join(' · '),
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${formatNumber(redemption.pointsCostSnapshot)} نقطة',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      _productRedemptionStatusLabel(redemption.status),
                      style: TextStyle(
                        fontSize: 12,
                        color: _productRedemptionStatusColor(
                            context, redemption.status),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            );
            // Only the completed (FULFILLED) history entry is dimmed — the
            // request is kept permanently, never removed, just visually
            // muted. PENDING/REJECTED entries render at full opacity.
            return redemption.status == RedemptionStatus.fulfilled
                ? Opacity(opacity: 0.55, child: card)
                : card;
          }),
      ],
    );
  }
}

IconData _productRedemptionStatusIcon(RedemptionStatus status) {
  switch (status) {
    case RedemptionStatus.fulfilled:
      return Icons.check_circle_outline_rounded;
    case RedemptionStatus.rejected:
      return Icons.cancel_outlined;
    case RedemptionStatus.pending:
      return Icons.hourglass_top_rounded;
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

Color _productRedemptionStatusColor(
    BuildContext context, RedemptionStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case RedemptionStatus.fulfilled:
      return scheme.primary;
    case RedemptionStatus.rejected:
      return scheme.error;
    case RedemptionStatus.pending:
      return scheme.onSurfaceVariant;
  }
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

  @override
  void dispose() {
    cashPointsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.state.customer!;
    final available =
        widget.state.points?.availablePoints ?? customer.pointsBalance;
    final requested = int.tryParse(cashPointsController.text) ?? 0;
    final pointValue = _pointValueSyp(widget.state.cashRequests);
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('رصيدك المتاح'),
              Text('${formatNumber(available)} نقطة',
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('استبدال نقاط بكاش'),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: cashPointsController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'عدد النقاط',
                      prefixIcon: Icon(Icons.savings_outlined)),
                ),
                const SizedBox(height: 10),
                Text(
                    'القيمة: ${formatNumber((requested * pointValue).round())} ل.س'),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: requested > 0 && requested <= available
                      ? () => _requestCash(customer, requested)
                      : null,
                  child: const Text('إرسال طلب الاستبدال'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const _SectionTitle('منتجات رقمية'),
        const SizedBox(height: 10),
        if (widget.state.products.isEmpty)
          const _EmptyState(
              icon: Icons.redeem_outlined, text: 'لا توجد منتجات متاحة حالياً')
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
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  _ProductImage(url: product.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          '${formatNumber(product.costInPoints)} نقطة',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  hasPendingRequest
                      ? const OutlinedButton(
                          onPressed: null,
                          child: Text('قيد المراجعة'),
                        )
                      : OutlinedButton(
                          onPressed: available >= product.costInPoints
                              ? () => _redeemProduct(customer, product)
                              : null,
                          child: const Text('استبدال'),
                        ),
                ]),
              ),
            );
          }),
      ],
    );
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
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
