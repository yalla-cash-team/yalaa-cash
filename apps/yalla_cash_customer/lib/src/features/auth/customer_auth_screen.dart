part of '../../customer_app.dart';

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
  AuthMethod? method;
  _AuthStage stage = _AuthStage.options;
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
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
                                fontWeight: FontWeight.w800,
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
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'الاسم الكامل',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
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
    // The governorate is chosen after sign-in (CustomerGovernorateGate) from
    // the governorates activated in Admin, so sign-up only needs a name.
    final hasProfile = nameController.text.trim().isNotEmpty;
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
