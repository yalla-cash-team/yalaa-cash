import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

class YallaCashMerchantApp extends StatefulWidget {
  const YallaCashMerchantApp({
    super.key,
    this.runtime,
    this.cubit,
    this.store,
  });

  final YallaCashRuntime? runtime;
  final MerchantAppCubit? cubit;

  /// Test/example injection only. The production Merchant entrypoint uses the
  /// remote repository runtime and does not construct a demo store.
  final YallaCashStore? store;

  @override
  State<YallaCashMerchantApp> createState() => _YallaCashMerchantAppState();
}

class _YallaCashMerchantAppState extends State<YallaCashMerchantApp> {
  YallaCashRuntime? _runtime;
  MerchantAppCubit? _ownedCubit;
  var _ownsRuntime = false;

  MerchantAppCubit get _cubit => widget.cubit ?? _ownedCubit!;

  @override
  void initState() {
    super.initState();
    if (widget.cubit == null) {
      if (widget.store case final store?) {
        _ownedCubit = MerchantAppCubit(InMemoryYallaCashRepository(store));
      } else {
        _runtime = widget.runtime ?? _merchantProductionRuntime();
        _ownsRuntime = widget.runtime == null;
        _ownedCubit = _runtime!.merchantCubit();
      }
    }
    if (widget.store == null) unawaited(_cubit.restoreSession());
  }

  @override
  void dispose() {
    _ownedCubit?.close();
    if (_ownsRuntime) _runtime?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<MerchantAppState>(
        stream: _cubit.stream,
        initialData: _cubit.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? _cubit.state;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'يلا كاش للمحلات',
            theme: buildYallaTheme(Brightness.light),
            darkTheme: buildYallaTheme(Brightness.dark),
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: _homeForState(state),
          );
        },
      );

  Widget _homeForState(MerchantAppState state) {
    if (state.workspace != null) {
      return MerchantWorkspace(cubit: _cubit, state: state);
    }
    if (state.status == LoadStatus.loading && state.failure == null) {
      return const MerchantSplashScreen();
    }
    return MerchantLoginScreen(cubit: _cubit, state: state);
  }
}

YallaCashRuntime _merchantProductionRuntime() {
  // Uses the SHARED environment resolver so this app always targets the same
  // backend as admin/customer in the same runtime environment
  // (--dart-define=YALLA_CASH_API_BASE_URL for production; platform-aware
  // localhost / Android-emulator defaults locally). No app-specific URL.
  return YallaCashRuntime.fromEnvironment(
    environment: YallaCashEnvironment.fromEnvironment(useRemoteBackend: true),
  );
}

class MerchantSplashScreen extends StatelessWidget {
  const MerchantSplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const YallaCashLogo(height: 110),
                const SizedBox(height: 22),
                CircularProgressIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      );
}

class MerchantLoginScreen extends StatefulWidget {
  const MerchantLoginScreen({
    required this.cubit,
    required this.state,
    super.key,
  });

  final MerchantAppCubit cubit;
  final MerchantAppState state;

  @override
  State<MerchantLoginScreen> createState() => _MerchantLoginScreenState();
}

class _MerchantLoginScreenState extends State<MerchantLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.state.status == LoadStatus.loading;
    final error = widget.state.failure == null
        ? null
        : merchantFailureMessage(widget.state.failure!);

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
                  const Center(child: YallaCashLogo(height: 120)),
                  const SizedBox(height: 18),
                  Text(
                    'يلا كاش للمحلات',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'سجل الدخول ببيانات الحساب الصادرة من الإدارة',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    key: const Key('merchant-email'),
                    controller: emailController,
                    enabled: !isLoading,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('merchant-password'),
                    controller: passwordController,
                    enabled: !isLoading,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    key: const Key('merchant-login'),
                    onPressed: isLoading ? null : _login,
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('تسجيل الدخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _login() {
    FocusScope.of(context).unfocus();
    unawaited(
      widget.cubit.signIn(
        email: emailController.text,
        password: passwordController.text,
      ),
    );
  }
}

enum MerchantView { dashboard, scan, invoice, success }

class MerchantWorkspace extends StatefulWidget {
  const MerchantWorkspace({
    required this.cubit,
    required this.state,
    super.key,
  });

  final MerchantAppCubit cubit;
  final MerchantAppState state;

  @override
  State<MerchantWorkspace> createState() => _MerchantWorkspaceState();
}

class _MerchantWorkspaceState extends State<MerchantWorkspace> {
  MerchantView view = MerchantView.dashboard;
  String? scannedPayload;
  String? invoiceIdempotencyKey;
  final amountController = TextEditingController();

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.state.workspace!;
    final isLoading = widget.state.status == LoadStatus.loading;

    return Scaffold(
      appBar: AppBar(
        leading: view == MerchantView.dashboard
            ? null
            : IconButton(
                onPressed: isLoading ? null : _goHome,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const YallaCashLogo(height: 34, markOnly: true),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'يلا كاش للمحلات',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(snapshot.store.name,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed:
                isLoading ? null : () => unawaited(widget.cubit.logout()),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (view) {
            MerchantView.dashboard => MerchantDashboard(
                snapshot: snapshot,
                isRefreshing: isLoading,
                errorMessage: widget.state.failure == null
                    ? null
                    : merchantFailureMessage(widget.state.failure!),
                onScan: () => setState(() => view = MerchantView.scan),
                onRefresh: () => unawaited(widget.cubit.refresh()),
              ),
            MerchantView.scan => MerchantScanner(
                isResolving: isLoading,
                errorMessage: widget.state.failure == null
                    ? null
                    : merchantFailureMessage(widget.state.failure!),
                onPayload: _handlePayload,
              ),
            MerchantView.invoice => MerchantInvoiceForm(
                customer: widget.state.scannedCustomer!,
                amountController: amountController,
                isSubmitting: isLoading,
                errorMessage: widget.state.failure == null
                    ? null
                    : merchantFailureMessage(widget.state.failure!),
                onConfirm: _confirmInvoice,
              ),
            MerchantView.success => MerchantSuccess(
                transaction: widget.state.lastTransaction!,
                onNewSale: _startNewSale,
                onHome: _goHome,
              ),
          },
        ),
      ),
    );
  }

  Future<bool> _handlePayload(String payload) async {
    scannedPayload = payload;
    invoiceIdempotencyKey = _newUuidV4();
    await widget.cubit.resolveQr(payload);
    if (!mounted) return false;

    final customer = widget.cubit.state.scannedCustomer;
    if (customer == null) {
      _showSnack(merchantFailureMessage(widget.cubit.state.failure));
      return false;
    }

    setState(() => view = MerchantView.invoice);
    return true;
  }

  Future<void> _confirmInvoice() async {
    final payload = scannedPayload;
    if (payload == null) return;

    final amount = int.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
    if (amount <= 0) return;

    await widget.cubit.registerInvoice(
      customerQrPayload: payload,
      amountSyp: amount,
      idempotencyKey: invoiceIdempotencyKey ??= _newUuidV4(),
    );
    if (!mounted) return;

    if (widget.cubit.state.lastTransaction == null) {
      _showSnack(merchantFailureMessage(widget.cubit.state.failure));
      return;
    }

    setState(() => view = MerchantView.success);
  }

  void _startNewSale() {
    amountController.clear();
    scannedPayload = null;
    invoiceIdempotencyKey = null;
    widget.cubit.resetSaleFlow();
    setState(() => view = MerchantView.scan);
  }

  void _goHome() {
    amountController.clear();
    scannedPayload = null;
    invoiceIdempotencyKey = null;
    widget.cubit.resetSaleFlow();
    setState(() => view = MerchantView.dashboard);
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class MerchantDashboard extends StatelessWidget {
  const MerchantDashboard({
    required this.snapshot,
    required this.onScan,
    required this.onRefresh,
    required this.isRefreshing,
    this.errorMessage,
    super.key,
  });

  final MerchantWorkspaceSnapshot snapshot;
  final VoidCallback onScan;
  final VoidCallback onRefresh;
  final bool isRefreshing;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final transactions = snapshot.recentTransactions;
    final summary = snapshot.summary;

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        key: const ValueKey('merchant-dashboard'),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 96),
        children: [
          if (errorMessage != null) ...[
            _InlineError(message: errorMessage!),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.receipt_long_outlined,
                  value: '${summary.transactionCount}',
                  label: 'عدد المبيعات',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  icon: Icons.payments_outlined,
                  value: formatNumber(summary.totalSalesSyp),
                  label: 'قيمة المبيعات',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatCard(
            icon: Icons.account_balance_wallet_outlined,
            value: '${formatNumber(summary.commissionDueSyp)} ل.س',
            label:
                'العمولة المستحقة · النسبة ${snapshot.store.commissionRate}%',
            highlighted: true,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'آخر العمليات',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'تحديث',
                onPressed: isRefreshing ? null : onRefresh,
                icon: isRefreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (transactions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('لا توجد عمليات بعد')),
              ),
            )
          else
            ...transactions.map(
              (transaction) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(
                    '${formatNumber(transaction.amountSyp)} ل.س',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                      '${formatDate(transaction.createdAt)} · ${transaction.customerName?.isNotEmpty ?? false ? transaction.customerName! : transaction.customerId}'),
                  trailing: Text(
                    '${formatNumber(transaction.commissionAmountSyp)} ل.س',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('بدء عملية جديدة'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: highlighted
              ? const LinearGradient(
                  colors: [YallaColors.primaryStrong, YallaColors.primary])
              : null,
          color: highlighted ? null : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: highlighted
              ? null
              : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: highlighted
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: highlighted ? 24 : 20,
                fontWeight: FontWeight.w900,
                color: highlighted ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: highlighted
                    ? Colors.white70
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

class MerchantScanner extends StatefulWidget {
  const MerchantScanner({
    required this.onPayload,
    required this.isResolving,
    this.errorMessage,
    super.key,
  });

  final Future<bool> Function(String) onPayload;
  final bool isResolving;
  final String? errorMessage;

  @override
  State<MerchantScanner> createState() => _MerchantScannerState();
}

class _MerchantScannerState extends State<MerchantScanner> {
  final controller =
      MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
        key: const ValueKey('merchant-scan'),
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'مسح كود الزبون',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: controller,
                    errorBuilder: (context, error) =>
                        _ScannerError(message: scannerErrorMessage(error)),
                    placeholderBuilder: (context) => const ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                    onDetect: (capture) {
                      if (handled ||
                          widget.isResolving ||
                          capture.barcodes.isEmpty) {
                        return;
                      }
                      final payload = capture.barcodes.first.rawValue;
                      if (payload == null) {
                        return;
                      }
                      handled = true;
                      unawaited(_resolve(payload));
                    },
                  ),
                  Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: YallaColors.primary, width: 3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                  if (widget.isResolving)
                    const ColoredBox(
                      color: Color(0x66000000),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'وجّه الكاميرا نحو QR الظاهر في تطبيق الزبون.',
            textAlign: TextAlign.center,
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 14),
            _InlineError(message: widget.errorMessage!),
          ],
        ],
      );

  Future<void> _resolve(String payload) async {
    final accepted = await widget.onPayload(payload);
    if (!accepted && mounted) setState(() => handled = false);
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded,
                    color: Colors.white, size: 42),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      );
}

class MerchantInvoiceForm extends StatefulWidget {
  const MerchantInvoiceForm({
    required this.customer,
    required this.amountController,
    required this.onConfirm,
    required this.isSubmitting,
    this.errorMessage,
    super.key,
  });

  final Customer customer;
  final TextEditingController amountController;
  final VoidCallback onConfirm;
  final bool isSubmitting;
  final String? errorMessage;

  @override
  State<MerchantInvoiceForm> createState() => _MerchantInvoiceFormState();
}

class _MerchantInvoiceFormState extends State<MerchantInvoiceForm> {
  @override
  Widget build(BuildContext context) {
    final amount =
        int.tryParse(widget.amountController.text.replaceAll(',', '')) ?? 0;
    return ListView(
      key: const ValueKey('merchant-invoice'),
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'إضافة الفاتورة',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        Card(
          child: ListTile(
            leading:
                const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
            title: Text(widget.customer.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle:
                Text('${widget.customer.governorate} · تم التحقق من الكود'),
            trailing:
                const Icon(Icons.verified_rounded, color: YallaColors.success),
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          key: const Key('invoice-amount'),
          controller: widget.amountController,
          enabled: !widget.isSubmitting,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'قيمة الفاتورة بالليرة السورية',
            suffixText: 'ل.س',
          ),
        ),
        if (widget.errorMessage != null) ...[
          const SizedBox(height: 14),
          _InlineError(message: widget.errorMessage!),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const Key('confirm-invoice'),
          onPressed:
              amount > 0 && !widget.isSubmitting ? widget.onConfirm : null,
          child: widget.isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تأكيد العملية'),
        ),
      ],
    );
  }
}

class MerchantSuccess extends StatelessWidget {
  const MerchantSuccess({
    required this.transaction,
    required this.onNewSale,
    required this.onHome,
    super.key,
  });

  final LoyaltyTransaction transaction;
  final VoidCallback onNewSale;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => ListView(
        key: const ValueKey('merchant-success'),
        padding: const EdgeInsets.all(22),
        children: [
          const SizedBox(height: 30),
          const CircleAvatar(
            radius: 38,
            backgroundColor: Color(0x221F9D6B),
            child:
                Icon(Icons.check_rounded, size: 42, color: YallaColors.success),
          ),
          const SizedBox(height: 16),
          Text(
            'تمت العملية بنجاح',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'فاتورة بقيمة ${formatNumber(transaction.amountSyp)} ل.س',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [YallaColors.primaryStrong, YallaColors.primary]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Text('العمولة المستحقة عليك',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Text(
                  '${formatNumber(transaction.commissionAmountSyp)} ل.س',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.stars_rounded),
                  title: const Text('النقاط المضافة للزبون'),
                  trailing: Text(
                    formatNumber(transaction.customerPointsEarned),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.confirmation_number_outlined),
                  title: const Text('رقم العملية'),
                  subtitle:
                      Text(transaction.id, textDirection: TextDirection.ltr),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'يتم التحاسب نقداً مطلع كل شهر بناءً على مجموع العمليات المسجلة.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onNewSale, child: const Text('عملية جديدة')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: onHome, child: const Text('العودة للرئيسية')),
        ],
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      );
}

String merchantFailureMessage(YallaCashFailure? failure) {
  if (failure == null) return 'تعذر إتمام الطلب. حاول مرة أخرى.';
  switch (failure.code) {
    case 'network_unavailable':
      return 'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى.';
    case 'request_timeout':
      return 'انتهت مهلة الاتصال بالخادم. حاول مرة أخرى.';
    case 'unauthorized':
      // The backend returns HTTP 401 with this same generic code for both a
      // real merchant session/login failure AND an expired/invalid scanned
      // Customer QR token (see MerchantService.customerIdFromQr) — the two
      // are distinguished here by the underlying message text so a QR
      // failure is never mistaken for the merchant's own session expiring.
      if (failure.message.contains('QR token')) {
        return 'انتهت صلاحية رمز QR. اطلب من الزبون عرض الرمز الجديد ثم أعد المسح.';
      }
      return 'انتهت الجلسة أو بيانات الدخول غير صحيحة.';
    case 'forbidden':
      return 'هذا الحساب لا يملك صلاحية الوصول إلى بيانات المحل.';
    case 'not_found':
      return 'لم يتم العثور على البيانات المطلوبة.';
    case 'conflict':
      return 'تم تسجيل هذه العملية سابقاً أو توجد حالة تمنع تكرارها.';
    case 'bad_request':
      return 'الطلب غير صالح. تحقق من البيانات وحاول مرة أخرى.';
    default:
      return failure.message.isEmpty
          ? 'تعذر إتمام الطلب. حاول مرة أخرى.'
          : failure.message;
  }
}

String scannerErrorMessage(MobileScannerException error) {
  final raw = error.errorCode.message.toLowerCase();
  if (raw.contains('permission') || raw.contains('denied')) {
    return 'لم يتم منح صلاحية الكاميرا.';
  }
  if (raw.contains('camera')) {
    return 'الكاميرا غير متاحة حالياً.';
  }
  return 'تعذر تشغيل ماسح الكود.';
}

String _newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
