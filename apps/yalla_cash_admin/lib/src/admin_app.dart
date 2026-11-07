import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' hide Banner;
import 'package:yalla_cash_admin/src/store_offers_admin.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart' as core show Banner;

const _adminPointAdjustmentNote = 'Admin adjustment';

class YallaCashAdminApp extends StatefulWidget {
  const YallaCashAdminApp(
      {super.key, this.store, this.runtime, this.skipLogin = false});

  final YallaCashStore? store;
  final YallaCashRuntime? runtime;
  final bool skipLogin;

  @override
  State<YallaCashAdminApp> createState() => _YallaCashAdminAppState();
}

class _YallaCashAdminAppState extends State<YallaCashAdminApp> {
  late final YallaCashRuntime? runtime = widget.runtime ??
      (widget.store == null ? YallaCashRuntime.fromEnvironment() : null);
  late final YallaCashStore? store = widget.store ?? runtime?.demoStore;
  late final YallaCashRepository repository =
      runtime?.repository ?? InMemoryYallaCashRepository(store!);
  late final AdminAppCubit adminCubit = AdminAppCubit(repository);
  late bool authenticated = widget.skipLogin;
  var darkMode = false;

  @override
  void initState() {
    super.initState();
    if (widget.skipLogin) unawaited(adminCubit.refresh());
  }

  @override
  void dispose() {
    adminCubit.close();
    if (widget.store == null && widget.runtime == null) {
      runtime?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AdminAppState>(
        stream: adminCubit.stream,
        initialData: adminCubit.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? adminCubit.state;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'لوحة تحكم يلا كاش',
            theme: buildYallaTheme(Brightness.light),
            darkTheme: buildYallaTheme(Brightness.dark),
            themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
            home: authenticated
                ? AdminShell(
                    cubit: adminCubit,
                    state: state,
                    repository: repository,
                    darkMode: darkMode,
                    onDarkModeChanged: (value) =>
                        setState(() => darkMode = value),
                    onLogout: _logout,
                  )
                : AdminLoginScreen(
                    cubit: adminCubit,
                    state: state,
                    onAuthenticated: () =>
                        setState(() => authenticated = true)),
          );
        },
      );

  Future<void> _logout() async {
    await adminCubit.logout();
    if (mounted) setState(() => authenticated = false);
  }
}

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({
    required this.cubit,
    required this.state,
    required this.onAuthenticated,
    super.key,
  });

  final AdminAppCubit cubit;
  final AdminAppState state;
  final VoidCallback onAuthenticated;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final emailController = TextEditingController(text: 'admin@yallacash.app');
  final passwordController = TextEditingController(text: '123456');
  String? error;
  bool submitting = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loading = submitting || widget.state.status == LoadStatus.loading;
    final failure = error ?? widget.state.failure?.message;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: YallaCashLogo(height: 112)),
                    const SizedBox(height: 18),
                    Text('لوحة تحكم يلا كاش',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text('دخول الإدارة', textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(
                      key: const Key('admin-email'),
                      controller: emailController,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: Icon(Icons.mail_outline_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('admin-password'),
                      controller: passwordController,
                      obscureText: true,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline_rounded)),
                    ),
                    if (failure != null) ...[
                      const SizedBox(height: 10),
                      Text(failure,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                        key: const Key('admin-login'),
                        onPressed: loading ? null : _login,
                        child: const Text('تسجيل الدخول')),
                    const SizedBox(height: 10),
                    Text('بيانات العرض مدخلة مسبقاً',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      error = null;
      submitting = true;
    });
    await widget.cubit.signIn(
      email: emailController.text.trim(),
      password: passwordController.text,
    );
    if (!mounted) return;
    if (widget.cubit.state.isAuthenticated) {
      widget.onAuthenticated();
    } else {
      submitting = false;
      final failure = widget.cubit.state.failure;

      setState(() {
        error = failure == null
            ? 'فشل تسجيل الدخول.'
            : '${failure.message} (${failure.code})';
      });
    }
  }
}

enum AdminSection {
  overview('نظرة عامة', Icons.dashboard_outlined),
  cashRequests('طلبات الكاش', Icons.payments_outlined),
  productRedemptions('طلبات استبدال المنتجات', Icons.card_giftcard_outlined),
  customers('المستخدمون', Icons.people_outline_rounded),
  stores('المحلات', Icons.storefront_outlined),
  governorates('المحافظات', Icons.location_on_outlined),
  banners('الإعلانات', Icons.campaign_outlined),
  products('المنتجات الرقمية', Icons.redeem_outlined),
  merchantAccounts('حسابات المحلات', Icons.badge_outlined),
  settlements('التحاسب الشهري', Icons.account_balance_outlined),
  notifications('الإشعارات', Icons.notifications_outlined),
  settings('الإعدادات', Icons.settings_outlined);

  const AdminSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class AdminShell extends StatefulWidget {
  const AdminShell(
      {required this.cubit,
      required this.state,
      required this.repository,
      required this.darkMode,
      required this.onDarkModeChanged,
      required this.onLogout,
      super.key});

  final AdminAppCubit cubit;
  final AdminAppState state;
  final YallaCashRepository repository;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onLogout;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  var section = AdminSection.overview;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final content = _AdminContent(
      section: section,
      cubit: widget.cubit,
      state: widget.state,
      repository: widget.repository,
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !wide,
        title: Text(section.label,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: widget.darkMode ? 'الوضع الفاتح' : 'الوضع الداكن',
            onPressed: () => widget.onDarkModeChanged(!widget.darkMode),
            icon: Icon(widget.darkMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined),
          ),
          IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide
          ? null
          : Builder(
              builder: (drawerContext) => Drawer(
                child: SafeArea(
                  child: _AdminNavigation(
                    selected: section,
                    onSelected: (value) {
                      _select(value);
                      Navigator.pop(drawerContext);
                    },
                  ),
                ),
              ),
            ),
      body: wide
          ? Row(
              children: [
                SizedBox(
                    width: 250,
                    child: _AdminNavigation(
                        selected: section, onSelected: _select)),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }

  void _select(AdminSection value) {
    setState(() => section = value);
  }
}

class _AdminNavigation extends StatelessWidget {
  const _AdminNavigation({required this.selected, required this.onSelected});

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelected;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 14, 12, 22),
              child: Row(
                children: [
                  YallaCashLogo(height: 42, markOnly: true),
                  SizedBox(width: 10),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('يلا كاش',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 18)),
                        Text('لوحة التحكم', style: TextStyle(fontSize: 11))
                      ]),
                ],
              ),
            ),
            for (final item in AdminSection.values)
              ListTile(
                selected: selected == item,
                selectedTileColor:
                    Theme.of(context).colorScheme.primaryContainer,
                leading: Icon(item.icon),
                title: Text(item.label),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onTap: () => onSelected(item),
              ),
          ],
        ),
      );
}

class _AdminContent extends StatelessWidget {
  const _AdminContent({
    required this.section,
    required this.cubit,
    required this.state,
    required this.repository,
  });

  final AdminSection section;
  final AdminAppCubit cubit;
  final AdminAppState state;
  final YallaCashRepository repository;

  @override
  Widget build(BuildContext context) => switch (section) {
        AdminSection.overview => AdminOverview(state: state),
        AdminSection.cashRequests => CashRequestsAdmin(
            cubit: cubit,
            requests: state.cashRequests,
            customers: state.customers,
          ),
        AdminSection.productRedemptions => ProductRedemptionsAdmin(
            cubit: cubit,
            redemptions: state.productRedemptions,
          ),
        AdminSection.customers => CustomersAdmin(
            cubit: cubit,
            customers: state.customers,
          ),
        AdminSection.stores => StoresAdmin(
            cubit: cubit,
            stores: state.stores,
            repository: repository,
          ),
        AdminSection.governorates => GovernoratesAdmin(repository: repository),
        AdminSection.banners => BannersAdmin(repository: repository),
        AdminSection.products => ProductsAdmin(
            cubit: cubit,
            products: state.products,
          ),
        AdminSection.merchantAccounts => MerchantAccountsAdmin(
            cubit: cubit,
            stores: state.stores,
            accounts: state.merchantAccounts,
          ),
        AdminSection.settlements => SettlementsAdmin(
            cubit: cubit,
            settlements: state.settlements,
          ),
        AdminSection.notifications => NotificationsAdmin(cubit: cubit),
        AdminSection.settings => SettingsAdmin(
            cubit: cubit,
            pointValueSyp: state.pointValueSyp,
            minCashWithdrawalSyp: state.minCashWithdrawalSyp,
            shareRewardPoints: state.shareRewardPoints,
          ),
      };
}

class AdminOverview extends StatelessWidget {
  const AdminOverview({required this.state, super.key});

  final AdminAppState state;

  @override
  Widget build(BuildContext context) {
    final overview = state.overview;
    if (overview == null) {
      return _AdminPage(
        key: const ValueKey('admin-overview'),
        children: const [LinearProgressIndicator()],
      );
    }
    return _AdminPage(
      key: const ValueKey('admin-overview'),
      children: [
        const _PageTitle(
            title: 'نظرة عامة', subtitle: 'ملخص أداء منصة يلا كاش'),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050
                ? 4
                : constraints.maxWidth >= 600
                    ? 2
                    : 1;
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: columns == 1 ? 3.4 : 2.0,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _KpiCard(
                    label: 'المستخدمون',
                    value: formatNumber(overview.customers),
                    icon: Icons.people_outline_rounded,
                    color: YallaColors.primaryStrong),
                _KpiCard(
                    label: 'المبيعات المسجلة',
                    value: '${formatNumber(overview.totalSalesSyp)} ل.س',
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFF0E8C79)),
                _KpiCard(
                    label: 'دخل المنصة',
                    value: '${formatNumber(overview.platformRevenueSyp)} ل.س',
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF7C6CF0)),
                _KpiCard(
                    label: 'طلبات كاش معلقة',
                    value: formatNumber(overview.pendingCashRequests),
                    icon: Icons.notifications_active_outlined,
                    color: YallaColors.gold),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text('آخر العمليات',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        _TableCard(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('المحل')),
              DataColumn(label: Text('الفاتورة')),
              DataColumn(label: Text('النقاط')),
              DataColumn(label: Text('التاريخ'))
            ],
            // Wired to real data: latest loyalty transactions loaded by
            // AdminAppCubit.refresh() (previously a hardcoded empty list).
            rows: state.recentTransactions.isEmpty
                ? const [
                    DataRow(cells: [
                      DataCell(Text('لا توجد عمليات بعد')),
                      DataCell(Text('')),
                      DataCell(Text('')),
                      DataCell(Text('')),
                    ])
                  ]
                : state.recentTransactions
                    .map((item) => DataRow(cells: [
                          DataCell(Text(item.storeName)),
                          DataCell(Text('${formatNumber(item.amountSyp)} ل.س')),
                          DataCell(Text(
                              '+${formatNumber(item.customerPointsEarned)}')),
                          DataCell(Text(formatDate(item.createdAt))),
                        ]))
                    .toList(),
          ),
        ),
      ],
    );
  }
}

class CashRequestsAdmin extends StatefulWidget {
  const CashRequestsAdmin({
    required this.cubit,
    required this.requests,
    required this.customers,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<CashRedemptionRequest> requests;
  final List<Customer> customers;

  @override
  State<CashRequestsAdmin> createState() => _CashRequestsAdminState();
}

class _CashRequestsAdminState extends State<CashRequestsAdmin> {
  final Set<String> _resolvingIds = {};

  Future<void> _resolve(CashRedemptionRequest request, bool approve) async {
    setState(() => _resolvingIds.add(request.id));
    try {
      await widget.cubit.resolveCashRequest(request, approve);
    } finally {
      if (mounted) setState(() => _resolvingIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminPage(children: [
      const _PageTitle(
          title: 'طلبات استبدال النقاط بكاش',
          subtitle: 'راجع الطلب ثم أكد التسليم النقدي أو ارفضه'),
      const SizedBox(height: 18),
      if (widget.requests.isEmpty)
        const _EmptyAdmin(
            icon: Icons.check_circle_outline_rounded,
            text: 'لا توجد طلبات معلقة')
      else
        ...widget.requests.map((request) {
          final customer = _customerForRequest(request, widget.customers);
          final resolving = _resolvingIds.contains(request.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const CircleAvatar(child: Icon(Icons.payments_outlined)),
                  SizedBox(
                      width: 220,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(customer.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            Text(
                                '${formatNumber(request.pointsRequested)} نقطة · ${formatNumber(request.cashValueSyp)} ل.س')
                          ])),
                  SizedBox(
                    width: 140,
                    child: FilledButton.tonalIcon(
                      onPressed:
                          resolving ? null : () => _resolve(request, true),
                      icon: resolving
                          ? const SizedBox.square(
                              dimension: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: const Text('حل الطلب'),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: OutlinedButton.icon(
                      onPressed:
                          resolving ? null : () => _resolve(request, false),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('رفض الطلب'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    ]);
  }
}

class ProductRedemptionsAdmin extends StatefulWidget {
  const ProductRedemptionsAdmin({
    required this.cubit,
    required this.redemptions,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<ProductRedemption> redemptions;

  @override
  State<ProductRedemptionsAdmin> createState() =>
      _ProductRedemptionsAdminState();
}

class _ProductRedemptionsAdminState extends State<ProductRedemptionsAdmin> {
  final Set<String> _resolvingIds = {};

  Future<void> _resolve(ProductRedemption redemption, bool approve) async {
    setState(() => _resolvingIds.add(redemption.id));
    try {
      await widget.cubit.resolveProductRedemption(redemption, approve);
    } finally {
      if (mounted) setState(() => _resolvingIds.remove(redemption.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminPage(children: [
      const _PageTitle(
          title: 'طلبات استبدال المنتجات الرقمية',
          subtitle: 'راجع الطلب ثم أكد التسليم أو ارفضه'),
      const SizedBox(height: 18),
      if (widget.redemptions.isEmpty)
        const _EmptyAdmin(
            icon: Icons.check_circle_outline_rounded,
            text: 'لا توجد طلبات معلقة')
      else
        ...widget.redemptions.map((redemption) {
          final resolving = _resolvingIds.contains(redemption.id);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const CircleAvatar(child: Icon(Icons.card_giftcard_outlined)),
                  SizedBox(
                      width: 240,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(redemption.customerName ?? redemption.customerId,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            if ((redemption.customerPhone ?? '').isNotEmpty)
                              Text(redemption.customerPhone!,
                                  textDirection: TextDirection.ltr),
                            Text(
                                '${redemption.productName ?? redemption.productId} · ${formatNumber(redemption.pointsCostSnapshot)} نقطة'),
                            if ((redemption.phoneNumber ?? '').isNotEmpty)
                              Text('رقم الاستلام: ${redemption.phoneNumber}',
                                  textDirection: TextDirection.ltr),
                            Text(
                                '${_redemptionStatusLabel(redemption.status)} · ${formatDate(redemption.createdAt)}'),
                          ])),
                  SizedBox(
                    width: 140,
                    child: FilledButton.tonalIcon(
                      onPressed:
                          resolving ? null : () => _resolve(redemption, true),
                      icon: resolving
                          ? const SizedBox.square(
                              dimension: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: const Text('حل الطلب'),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: OutlinedButton.icon(
                      onPressed: resolving
                          ? null
                          : () => _resolve(redemption, false),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('رفض الطلب'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    ]);
  }
}

String _redemptionStatusLabel(RedemptionStatus status) => switch (status) {
      RedemptionStatus.pending => 'قيد المعالجة',
      RedemptionStatus.fulfilled => 'تم التسليم',
      RedemptionStatus.rejected => 'مرفوض',
    };

class NotificationsAdmin extends StatefulWidget {
  const NotificationsAdmin({required this.cubit, super.key});

  final AdminAppCubit cubit;

  @override
  State<NotificationsAdmin> createState() => _NotificationsAdminState();
}

class _NotificationsAdminState extends State<NotificationsAdmin> {
  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  late Future<List<NotificationBroadcast>> _history;
  bool sending = false;
  String? resultMessage;
  bool resultIsError = false;

  // One key per composed message. Retrying the same message after a failure
  // reuses it, so the server returns the original broadcast instead of
  // notifying customers twice. Editing the message starts a new key.
  String? _pendingKey;

  @override
  void initState() {
    super.initState();
    _history = widget.cubit.listNotificationBroadcasts();
    titleController.addListener(_composeChanged);
    bodyController.addListener(_composeChanged);
  }

  @override
  void dispose() {
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }

  void _composeChanged() => _pendingKey = null;

  bool get _canSend =>
      titleController.text.trim().isNotEmpty &&
      bodyController.text.trim().isNotEmpty &&
      !sending;

  String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<bool> _confirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد إرسال الإشعار'),
        content: Text(
            'سيصل هذا الإشعار إلى جميع الزبائن: "${titleController.text.trim()}". لا يمكن التراجع عنه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إرسال')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _send() async {
    if (!_canSend || !await _confirm() || !mounted) return;
    final key = _pendingKey ??= _newKey();
    setState(() {
      sending = true;
      resultMessage = null;
    });
    final broadcast = await widget.cubit.sendGeneralNotification(
      title: titleController.text.trim(),
      body: bodyController.text.trim(),
      idempotencyKey: key,
    );
    if (!mounted) return;
    setState(() {
      sending = false;
      resultIsError = broadcast == null || broadcast.status == 'FAILED';
      resultMessage = _resultText(broadcast);
      if (broadcast != null) {
        _pendingKey = null;
        titleController.clear();
        bodyController.clear();
      }
      _history = widget.cubit.listNotificationBroadcasts();
    });
  }

  String _resultText(NotificationBroadcast? broadcast) => switch (broadcast?.status) {
        'SENT' => 'تم إرسال الإشعار إلى ${broadcast!.sentCount} جهاز.',
        'PARTIAL' =>
          'أُرسل إلى ${broadcast!.sentCount} جهاز، وفشل ${broadcast.failedCount}.',
        'FAILED' => 'فشل إرسال الإشعار. أعد المحاولة بالرسالة نفسها.',
        'PENDING' => 'الإشعار قيد الإرسال.',
        _ => 'تعذر إرسال الإشعار. حاول مرة أخرى.',
      };

  String _statusLabel(String status) => switch (status) {
        'SENT' => 'تم الإرسال',
        'PARTIAL' => 'أُرسل جزئياً',
        'FAILED' => 'فشل',
        'PENDING' => 'قيد الإرسال',
        _ => status,
      };

  Widget _historyList() => FutureBuilder<List<NotificationBroadcast>>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          final items = snapshot.data ?? const <NotificationBroadcast>[];
          if (items.isEmpty) return const Text('لا توجد إشعارات سابقة.');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items.take(20))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${_statusLabel(item.status)} · ${item.sentCount} من ${item.recipientCount} جهاز'),
                ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return _AdminPage(children: [
      const _PageTitle(
          title: 'إرسال إشعار عام',
          subtitle: 'يصل الإشعار إلى جميع الزبائن عبر الإشعارات الفورية'),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: bodyController,
                onChanged: (_) => setState(() {}),
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'نص الإشعار'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _canSend ? _send : null,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('إرسال إلى جميع الزبائن'),
              ),
              if (resultMessage != null) ...[
                const SizedBox(height: 12),
                Text(resultMessage!,
                    style: TextStyle(
                        color: resultIsError
                            ? Theme.of(context).colorScheme.error
                            : YallaColors.success)),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('سجل الإشعارات',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _historyList(),
            ],
          ),
        ),
      ),
    ]);
  }
}

class CustomersAdmin extends StatelessWidget {
  const CustomersAdmin({
    required this.cubit,
    required this.customers,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<Customer> customers;

  @override
  Widget build(BuildContext context) => _AdminPage(children: [
        const _PageTitle(
            title: 'المستخدمون', subtitle: 'إدارة أرصدة الزبائن وحساباتهم'),
        const SizedBox(height: 18),
        _TableCard(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('المحافظة')),
              DataColumn(label: Text('الرصيد')),
              DataColumn(label: Text('تاريخ الانضمام')),
              DataColumn(label: Text('إجراءات'))
            ],
            rows: customers
                .map((customer) => DataRow(cells: [
                      DataCell(Text(customer.name,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                      DataCell(Text(customer.governorate)),
                      DataCell(
                          Text('${formatNumber(customer.pointsBalance)} نقطة')),
                      DataCell(Text(formatDate(customer.createdAt))),
                      DataCell(Wrap(spacing: 6, children: [
                        IconButton(
                            tooltip: 'منح نقاط',
                            onPressed: () =>
                                _pointsDialog(context, customer, true),
                            icon: const Icon(Icons.add_circle_outline_rounded)),
                        IconButton(
                            tooltip: 'خصم نقاط',
                            onPressed: () =>
                                _pointsDialog(context, customer, false),
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded)),
                        IconButton(
                            tooltip: 'حذف',
                            onPressed: () => _deleteCustomer(context, customer),
                            icon: Icon(Icons.delete_outline_rounded,
                                color: Theme.of(context).colorScheme.error)),
                      ])),
                    ]))
                .toList(),
          ),
        ),
      ]);

  Future<void> _pointsDialog(
      BuildContext context, Customer customer, bool grant) async {
    // The dialog widget owns its TextEditingController (disposed in its
    // State.dispose), so popping the dialog can never leave the exit
    // animation referencing a disposed controller.
    final points = await showDialog<int>(
      context: context,
      builder: (_) => _PointsInputDialog(
        title: grant
            ? 'منح نقاط إلى ${customer.name}'
            : 'خصم نقاط من ${customer.name}',
      ),
    );
    if (points == null || points <= 0) return;
    if (grant) {
      await cubit.grantPoints(customer, points, _adminPointAdjustmentNote);
    } else {
      await cubit.deductPoints(customer, points, _adminPointAdjustmentNote);
    }
  }

  Future<void> _deleteCustomer(BuildContext context, Customer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المستخدم'),
        content:
            Text('هل تريد حذف حساب ${customer.name} وسجلات العرض المرتبطة به؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) await cubit.deleteCustomer(customer);
  }
}

/// Points add/deduct prompt. Owns its TextEditingController lifecycle.
class _PointsInputDialog extends StatefulWidget {
  const _PointsInputDialog({required this.title});

  final String title;

  @override
  State<_PointsInputDialog> createState() => _PointsInputDialogState();
}

class _PointsInputDialogState extends State<_PointsInputDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'عدد النقاط'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('تأكيد'),
          ),
        ],
      );
}

class GovernoratesAdmin extends StatefulWidget {
  const GovernoratesAdmin({required this.repository, super.key});

  final YallaCashRepository repository;

  @override
  State<GovernoratesAdmin> createState() => _GovernoratesAdminState();
}

class _GovernoratesAdminState extends State<GovernoratesAdmin> {
  List<Governorate> items = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final loaded = await widget.repository.listAdminGovernorates();
      if (!mounted) return;
      setState(() {
        items = loaded
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        loading = false;
        error = null;
      });
    } on YallaCashFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            failure.message.isEmpty ? 'تعذر تحميل المحافظات.' : failure.message;
      });
    } on Object catch (error_, stackTrace) {
      debugPrint('GOVERNORATES LOAD ERROR: $error_');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر تحميل المحافظات.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
        children: [
          _PageTitle(
            title: 'إدارة المحافظات',
            subtitle: 'تحكم بالمحافظات المتاحة وترتيب ظهورها للعملاء',
            action: FilledButton.icon(
              onPressed: () => _editGovernorate(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة محافظة'),
            ),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            Center(child: Text(error!))
          else if (items.isEmpty)
            const Center(child: Text('لا توجد محافظات بعد.'))
          else
            Card(
              child: Column(
                children: [
                  const ListTile(
                    title: Text('اسم المحافظة',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('الحالة · ترتيب الظهور'),
                    trailing: Text('تعديل',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const Divider(height: 1),
                  ...items.map(
                    (item) => ListTile(
                      leading:
                          CircleAvatar(child: Text('${item.displayOrder}')),
                      title: Text(item.nameAr,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(item.isActive
                          ? 'نشطة · الترتيب ${item.displayOrder}'
                          : 'غير نشطة · الترتيب ${item.displayOrder}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                              value: item.isActive,
                              onChanged: (value) => _toggle(item, value)),
                          IconButton(
                              tooltip: 'تعديل',
                              onPressed: () => _editGovernorate(context, item),
                              icon: const Icon(Icons.edit_outlined)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Future<void> _toggle(Governorate item, bool isActive) async {
    try {
      await widget.repository
          .updateGovernorate(item.copyWith(isActive: isActive));
      await _refresh();
    } on YallaCashFailure catch (failure) {
      if (!mounted) return;
      setState(() => error = failure.message.isEmpty
          ? 'تعذر تحديث حالة المحافظة.'
          : failure.message);
    } on Object catch (error_, stackTrace) {
      debugPrint('GOVERNORATE TOGGLE ERROR: $error_');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => error = 'تعذر تحديث حالة المحافظة.');
    }
  }

  Future<void> _editGovernorate(BuildContext context,
      [Governorate? item]) async {
    // The editor dialog owns its TextEditingControllers; it returns a plain
    // result object so the caller never touches a controller after pop.
    final result = await showDialog<_GovernorateEditorResult>(
      context: context,
      builder: (_) => _GovernorateEditorDialog(
        item: item,
        nextDisplayOrder: items.length + 1,
      ),
    );
    if (result == null || result.nameAr.isEmpty) return;
    final next = Governorate(
      id: item?.id ?? 'gov-${DateTime.now().microsecondsSinceEpoch}',
      nameAr: result.nameAr,
      isActive: result.isActive,
      displayOrder: result.displayOrder,
      createdAt: item?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    try {
      if (item == null) {
        await widget.repository.createGovernorate(next);
      } else {
        await widget.repository.updateGovernorate(next);
      }
      await _refresh();
    } on YallaCashFailure catch (failure) {
      if (!mounted) return;
      setState(() => error =
          failure.message.isEmpty ? 'تعذر حفظ المحافظة.' : failure.message);
    } on Object catch (error_, stackTrace) {
      debugPrint('GOVERNORATE SAVE ERROR: $error_');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() => error = 'تعذر حفظ المحافظة.');
    }
  }
}

class _GovernorateEditorResult {
  const _GovernorateEditorResult({
    required this.nameAr,
    required this.displayOrder,
    required this.isActive,
  });

  final String nameAr;
  final int displayOrder;
  final bool isActive;
}

/// Add/edit governorate prompt. Owns its TextEditingController lifecycle.
class _GovernorateEditorDialog extends StatefulWidget {
  const _GovernorateEditorDialog({
    required this.item,
    required this.nextDisplayOrder,
  });

  final Governorate? item;
  final int nextDisplayOrder;

  @override
  State<_GovernorateEditorDialog> createState() =>
      _GovernorateEditorDialogState();
}

class _GovernorateEditorDialogState extends State<_GovernorateEditorDialog> {
  late final name = TextEditingController(text: widget.item?.nameAr ?? '');
  late final order = TextEditingController(
      text: '${widget.item?.displayOrder ?? widget.nextDisplayOrder}');
  late var active = widget.item?.isActive ?? false;
  String? errorMessage;

  @override
  void dispose() {
    name.dispose();
    order.dispose();
    super.dispose();
  }

  void _save() {
    final nameValue = name.text.trim();
    if (nameValue.isEmpty) {
      setState(() => errorMessage = 'أدخل اسم المحافظة.');
      return;
    }
    Navigator.pop(
      context,
      _GovernorateEditorResult(
        nameAr: nameValue,
        displayOrder: int.tryParse(order.text) ?? widget.nextDisplayOrder,
        isActive: active,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item == null ? 'إضافة محافظة' : 'تعديل المحافظة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: name,
                autofocus: widget.item == null,
                decoration: const InputDecoration(labelText: 'اسم المحافظة')),
            const SizedBox(height: 12),
            TextField(
                controller: order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ترتيب الظهور')),
            SwitchListTile(
                value: active,
                onChanged: (value) => setState(() => active = value),
                title: const Text('نشطة')),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}

class BannersAdmin extends StatefulWidget {
  const BannersAdmin({required this.repository, super.key});

  final YallaCashRepository repository;

  @override
  State<BannersAdmin> createState() => _BannersAdminState();
}

class _BannersAdminState extends State<BannersAdmin> {
  static const allGovernoratesValue = '__all_governorates__';

  List<core.Banner> items = const [];
  List<Governorate> governorates = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final loadedGovernorates =
          await widget.repository.listAdminGovernorates();
      final loadedBanners = await widget.repository.listAdminBanners();
      if (!mounted) return;
      setState(() {
        governorates = loadedGovernorates.toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        items = loadedBanners.toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
        loading = false;
        error = null;
      });
    } on YallaCashFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            failure.message.isEmpty ? 'تعذر تحميل الإعلانات.' : failure.message;
      });
    } on Object catch (error_, stackTrace) {
      debugPrint('BANNERS LOAD ERROR: $error_');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذر تحميل الإعلانات.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => _AdminPage(
        children: [
          _PageTitle(
            title: 'إعلانات الصفحة الرئيسية',
            subtitle:
                'إدارة الشرائح الترويجية حسب المحافظة والحالة وجدولة الظهور',
            action: FilledButton.icon(
              onPressed: loading ? null : () => _editBanner(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة إعلان'),
            ),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            _BannerAdminMessage(message: error!, onRetry: _refresh)
          else if (items.isEmpty)
            const _EmptyAdmin(
                icon: Icons.campaign_outlined, text: 'لا توجد إعلانات بعد.')
          else
            ...items.map(
              (item) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: _BannerImageThumb(url: item.imageUrl),
                  title: Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_bannerSummary(item)),
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Switch(
                          value: item.isActive,
                          onChanged: (value) => _toggle(item, value)),
                      IconButton(
                        tooltip: 'تعديل',
                        onPressed: () => _editBanner(context, item),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        onPressed: () => _deleteBanner(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );

  String _bannerSummary(core.Banner item) {
    final status = item.isActive ? 'نشط' : 'متوقف';
    final governorate = item.governorateId == null
        ? 'كل المحافظات'
        : _governorateName(item.governorateId!);
    final schedule = _scheduleLabel(item);
    return [
      if (item.subtitle?.trim().isNotEmpty ?? false) item.subtitle!.trim(),
      '$status · $governorate · الترتيب ${item.displayOrder}',
      if (schedule != null) schedule,
    ].join('\n');
  }

  String _governorateName(String id) {
    for (final governorate in governorates) {
      if (governorate.id == id) return governorate.nameAr;
    }
    return 'محافظة محددة';
  }

  String? _scheduleLabel(core.Banner item) {
    final start = item.startsAt == null ? null : _formatDate(item.startsAt!);
    final end = item.endsAt == null ? null : _formatDate(item.endsAt!);
    if (start == null && end == null) return null;
    if (start != null && end != null) return 'من $start إلى $end';
    if (start != null) return 'يبدأ $start';
    return 'ينتهي $end';
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _deleteBanner(core.Banner item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الإعلان'),
        content: Text('هل تريد حذف "${item.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.deleteBanner(item.id);
      await _refresh();
    } on YallaCashFailure catch (failure) {
      _showBannerSnack(
          failure.message.isEmpty ? 'تعذر حذف الإعلان.' : failure.message);
    } on Object catch (error_, stackTrace) {
      debugPrint('BANNER DELETE ERROR: $error_');
      debugPrint('$stackTrace');
      _showBannerSnack('تعذر حذف الإعلان.');
    }
  }

  Future<void> _toggle(core.Banner item, bool isActive) async {
    try {
      await widget.repository.updateBanner(item.copyWith(isActive: isActive));
      await _refresh();
    } on YallaCashFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message.isEmpty
              ? 'تعذر تحديث حالة الإعلان.'
              : failure.message)));
    } on Object catch (error_, stackTrace) {
      debugPrint('BANNER TOGGLE ERROR: $error_');
      debugPrint('$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تحديث حالة الإعلان.')));
    }
  }

  Future<void> _editBanner(BuildContext context, [core.Banner? item]) async {
    // The editor dialog owns its seven TextEditingControllers; it returns a
    // plain result object so the caller never reads a controller after pop.
    final result = await showDialog<_BannerEditorResult>(
      context: context,
      builder: (_) => _BannerEditorDialog(
        item: item,
        nextDisplayOrder: items.length + 1,
        governorates: governorates,
        allGovernoratesValue: allGovernoratesValue,
      ),
    );
    if (result == null) return;

    final startsAtValue = _parseOptionalDate(result.startsAtText);
    final endsAtValue = _parseOptionalDate(result.endsAtText);
    final startsAtInvalid =
        result.startsAtText.trim().isNotEmpty && startsAtValue == null;
    final endsAtInvalid =
        result.endsAtText.trim().isNotEmpty && endsAtValue == null;

    if (result.title.isEmpty || result.imageUrl.isEmpty) {
      _showBannerSnack('أدخل عنوان الإعلان ورابط الصورة.');
      return;
    }
    if (!_isWebImageUrl(result.imageUrl)) {
      _showBannerSnack('رابط الصورة يجب أن يبدأ بـ http أو https.');
      return;
    }
    // targetUrl is optional (empty is allowed — the banner just won't be
    // tappable), but if the admin enters a value it must be a real external
    // http/https link — never an internal route like /stores or
    // stores?category=... — since Customer only ever opens it externally.
    if (result.targetUrl.isNotEmpty && !_isWebImageUrl(result.targetUrl)) {
      _showBannerSnack('أدخل رابطاً صحيحاً يبدأ بـ http:// أو https://');
      return;
    }
    if (startsAtInvalid || endsAtInvalid) {
      _showBannerSnack('صيغة التاريخ يجب أن تكون ISO صالحة.');
      return;
    }
    if (startsAtValue != null &&
        endsAtValue != null &&
        endsAtValue.isBefore(startsAtValue)) {
      _showBannerSnack('وقت النهاية يجب أن يكون بعد وقت البداية.');
      return;
    }

    final next = core.Banner(
      id: item?.id ?? 'banner-${DateTime.now().microsecondsSinceEpoch}',
      title: result.title,
      subtitle: result.subtitle.isEmpty ? null : result.subtitle,
      imageUrl: result.imageUrl,
      targetUrl: result.targetUrl.isEmpty ? null : result.targetUrl,
      placement: item?.placement ?? 'home',
      style: item?.style ?? 'promo',
      isActive: result.isActive,
      displayOrder: result.displayOrder,
      governorateId: result.governorateId == allGovernoratesValue
          ? null
          : result.governorateId,
      startsAt: startsAtValue,
      endsAt: endsAtValue,
      createdAt: item?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      final saved = item == null
          ? await widget.repository.createBanner(next)
          : await widget.repository.updateBanner(next);
      final image = result.image;
      if (image != null) {
        await widget.repository.setBannerImage(saved.id, image);
      } else if (result.removeImage) {
        await widget.repository.removeBannerImage(saved.id);
      }
      await _refresh();
    } on YallaCashFailure catch (failure) {
      _showBannerSnack(
          failure.message.isEmpty ? 'تعذر حفظ الإعلان.' : failure.message);
    } on Object catch (error_, stackTrace) {
      debugPrint('BANNER SAVE ERROR: $error_');
      debugPrint('$stackTrace');
      _showBannerSnack('تعذر حفظ الإعلان.');
    }
  }

  DateTime? _parseOptionalDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed);
  }

  bool _isWebImageUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  void _showBannerSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Opens the file picker for a banner or product image. Returns the image, or
/// an error message when the file is too large or not a supported type.
Future<({StoreLogoUpload? image, String? error})> _pickImageFile() async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
    withData: true,
  );
  final file = (picked?.files ?? const <PlatformFile>[]).firstOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return (image: null, error: null);
  if (bytes.length > _maxStoreLogoBytes) {
    return (image: null, error: 'حجم الصورة يجب ألا يتجاوز 300 KB.');
  }
  final extension = (file.extension ?? '').toLowerCase();
  return (
    image: StoreLogoUpload(
      bytes: bytes,
      contentType: switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      },
    ),
    error: null,
  );
}

class _BannerEditorResult {
  const _BannerEditorResult({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.targetUrl,
    required this.displayOrder,
    required this.startsAtText,
    required this.endsAtText,
    required this.isActive,
    required this.governorateId,
    this.image,
    this.removeImage = false,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final String targetUrl;
  final int displayOrder;
  final String startsAtText;
  final String endsAtText;
  final bool isActive;
  final String governorateId;
  final StoreLogoUpload? image;
  final bool removeImage;
}

/// Add/edit banner prompt. Owns its TextEditingController lifecycle.
class _BannerEditorDialog extends StatefulWidget {
  const _BannerEditorDialog({
    required this.item,
    required this.nextDisplayOrder,
    required this.governorates,
    required this.allGovernoratesValue,
  });

  final core.Banner? item;
  final int nextDisplayOrder;
  final List<Governorate> governorates;
  final String allGovernoratesValue;

  @override
  State<_BannerEditorDialog> createState() => _BannerEditorDialogState();
}

class _BannerEditorDialogState extends State<_BannerEditorDialog> {
  late final title = TextEditingController(text: widget.item?.title ?? '');
  late final subtitle =
      TextEditingController(text: widget.item?.subtitle ?? '');
  late final imageUrl =
      TextEditingController(text: widget.item?.imageUrl ?? '');
  StoreLogoUpload? pendingImage;
  String? imageError;
  bool removeImage = false;

  Future<void> _pickImage() async {
    final result = await _pickImageFile();
    if (!mounted) return;
    setState(() {
      imageError = result.error;
      if (result.image != null) {
        pendingImage = result.image;
        removeImage = false;
      }
    });
  }
  late final targetUrl =
      TextEditingController(text: widget.item?.targetUrl ?? '');
  late final order = TextEditingController(
      text: '${widget.item?.displayOrder ?? widget.nextDisplayOrder}');
  late final startsAt = TextEditingController(
      text: widget.item?.startsAt?.toIso8601String() ?? '');
  late final endsAt =
      TextEditingController(text: widget.item?.endsAt?.toIso8601String() ?? '');
  late var active = widget.item?.isActive ?? true;
  late var governorateChoice =
      widget.item?.governorateId ?? widget.allGovernoratesValue;

  @override
  void dispose() {
    title.dispose();
    subtitle.dispose();
    imageUrl.dispose();
    targetUrl.dispose();
    order.dispose();
    startsAt.dispose();
    endsAt.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.pop(
      context,
      _BannerEditorResult(
        title: title.text.trim(),
        subtitle: subtitle.text.trim(),
        imageUrl: imageUrl.text.trim(),
        image: pendingImage,
        removeImage: removeImage,
        targetUrl: targetUrl.text.trim(),
        displayOrder: int.tryParse(order.text) ?? widget.nextDisplayOrder,
        startsAtText: startsAt.text,
        endsAtText: endsAt.text,
        isActive: active,
        governorateId: governorateChoice,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item == null ? 'إضافة إعلان' : 'تعديل الإعلان'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'العنوان')),
                const SizedBox(height: 10),
                TextField(
                    controller: subtitle,
                    decoration:
                        const InputDecoration(labelText: 'العنوان الفرعي')),
                const SizedBox(height: 10),
                Row(children: [
                  if (pendingImage != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 96,
                        height: 54,
                        child: Image.memory(
                            Uint8List.fromList(pendingImage!.bytes),
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.image_outlined),
                          label: const Text('رفع صورة')),
                      if (pendingImage != null || widget.item != null)
                        TextButton(
                            onPressed: () => setState(() {
                                  pendingImage = null;
                                  removeImage = true;
                                }),
                            child: const Text('إزالة الصورة المرفوعة')),
                    ]),
                  ),
                ]),
                if (imageError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(imageError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: imageUrl,
                  decoration: const InputDecoration(labelText: 'رابط الصورة'),
                  onChanged: (_) => setState(() {}),
                ),
                if (imageUrl.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _BannerImagePreview(url: imageUrl.text.trim()),
                ],
                const SizedBox(height: 10),
                TextField(
                    controller: targetUrl,
                    decoration: const InputDecoration(labelText: 'رابط الهدف')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: governorateChoice,
                  decoration: const InputDecoration(labelText: 'المحافظة'),
                  items: [
                    DropdownMenuItem(
                        value: widget.allGovernoratesValue,
                        child: const Text('كل المحافظات')),
                    ...widget.governorates.map(
                      (governorate) => DropdownMenuItem(
                          value: governorate.id,
                          child: Text(governorate.nameAr)),
                    ),
                  ],
                  onChanged: (value) => setState(() =>
                      governorateChoice = value ?? widget.allGovernoratesValue),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: order,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'ترتيب الظهور')),
                const SizedBox(height: 10),
                TextField(
                    controller: startsAt,
                    decoration: const InputDecoration(
                        labelText: 'وقت البداية اختياري ISO')),
                const SizedBox(height: 10),
                TextField(
                    controller: endsAt,
                    decoration: const InputDecoration(
                        labelText: 'وقت النهاية اختياري ISO')),
                SwitchListTile(
                  value: active,
                  onChanged: (value) => setState(() => active = value),
                  title: const Text('نشط'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}

class _BannerImageThumb extends StatelessWidget {
  const _BannerImageThumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 84,
          height: 72,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
      );
}

class _BannerImagePreview extends StatelessWidget {
  const _BannerImagePreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 6,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child:
                  const Center(child: Icon(Icons.image_not_supported_outlined)),
            ),
          ),
        ),
      );
}

class _BannerAdminMessage extends StatelessWidget {
  const _BannerAdminMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
              TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

class StoresAdmin extends StatelessWidget {
  const StoresAdmin({
    required this.cubit,
    required this.stores,
    required this.repository,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<PartnerStore> stores;
  final YallaCashRepository repository;

  @override
  Widget build(BuildContext context) {
    // Store management shows the active roster only — a soft-deleted
    // (isActive: false) store disappears from here immediately, matching
    // "Delete", while it remains fully intact in the backend and still
    // shows up in Settlements/history (which lists every store regardless
    // of isActive) for audit purposes.
    final activeStores = stores.where((store) => store.isActive).toList();
    return _AdminPage(children: [
      _PageTitle(
          title: 'إدارة المحلات',
          subtitle: 'المحل الحصري ونسبة العمولة ومعلومات الظهور',
          action: FilledButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة محل'))),
      const SizedBox(height: 18),
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth >= 560
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: activeStores
              .map((partner) => SizedBox(
                  width: width,
                  child: _StoreAdminCard(
                      cubit: cubit, partner: partner, repository: repository)))
              .toList(),
        );
      }),
    ]);
  }

  Future<void> _create(BuildContext context) async {
    final created = await _showStoreEditor(context, repository: repository);
    if (created != null) {
      await cubit.createStore(created.store, logo: created.logo);
    }
  }
}

class _StoreAdminCard extends StatefulWidget {
  const _StoreAdminCard({
    required this.cubit,
    required this.partner,
    required this.repository,
  });

  final AdminAppCubit cubit;
  final PartnerStore partner;
  final YallaCashRepository repository;

  @override
  State<_StoreAdminCard> createState() => _StoreAdminCardState();
}

class _StoreAdminCardState extends State<_StoreAdminCard> {
  // Guards against a double tap firing two delete requests while the first
  // is still in flight.
  bool _deleting = false;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(child: Icon(AdminSection.stores.icon)),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(widget.partner.name,
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                Chip(label: Text('${widget.partner.commissionRate}%'))
              ]),
              const SizedBox(height: 10),
              Text(widget.partner.category,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  widget.partner.description.isEmpty
                      ? 'لا يوجد وصف'
                      : widget.partner.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text(widget.partner.location,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                    onPressed: _deleting ? null : () => _openOffers(context),
                    icon: const Icon(Icons.local_offer_outlined),
                    label: const Text('العروض')),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _deleting ? null : () => _edit(context),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('تعديل'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _deleting ? null : _delete,
                        icon: _deleting
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(context).colorScheme.error))
                            : Icon(Icons.delete_outline_rounded,
                                color: Theme.of(context).colorScheme.error),
                        label: Text('حذف',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)))),
              ]),
            ],
          ),
        ),
      );

  void _openOffers(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StoreOffersAdminPage(
            cubit: widget.cubit,
            repository: widget.repository,
            store: widget.partner,
          ),
        ),
      );

  Future<void> _edit(BuildContext context) async {
    final updated = await _showStoreEditor(context,
        partner: widget.partner, repository: widget.repository);
    if (updated != null) {
      await widget.cubit.updateStore(
        updated.store,
        logo: updated.logo,
        removeLogo: updated.removeLogo,
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المتجر'),
        content: const Text(
            'هل أنت متأكد من حذف هذا المتجر؟ سيختفي من التطبيق ولن يتم حذف السجلات والعمليات السابقة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف المتجر')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // No optimistic removal: the card stays exactly as-is until the backend
    // confirms success and the cubit's refresh() re-fetches the real store
    // list — only then does the (now-filtered) list stop showing it.
    setState(() => _deleting = true);
    final success = await widget.cubit.deleteStore(widget.partner);
    if (!mounted) return;
    setState(() => _deleting = false);

    if (!success) {
      final message = widget.cubit.state.failure?.message;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message == null || message.isEmpty
              ? 'تعذر حذف المتجر.'
              : message)));
    }
  }
}

/// Largest logo the editor accepts; the backend enforces the same limit.
const int _maxStoreLogoBytes = 300 * 1024;

/// Result of the store editor: the store fields plus any logo change.
class _StoreEditorResult {
  const _StoreEditorResult({
    required this.store,
    this.logo,
    this.removeLogo = false,
  });

  final PartnerStore store;
  final StoreLogoUpload? logo;
  final bool removeLogo;
}

Future<_StoreEditorResult?> _showStoreEditor(
  BuildContext context, {
  required YallaCashRepository repository,
  PartnerStore? partner,
}) async {
  // Governorate selection is required for every store, so the current
  // governorate list is fetched fresh each time the editor opens — the same
  // approach BannersAdmin already uses for its own governorate dropdown.
  List<Governorate> governorates;
  try {
    governorates = (await repository.listAdminGovernorates()).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  } on Object {
    governorates = const [];
  }
  if (!context.mounted) return null;
  if (governorates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر تحميل قائمة المحافظات. حاول مرة أخرى.')));
    return null;
  }
  // The editor dialog owns its TextEditingControllers and builds the
  // resulting PartnerStore itself; no controller outlives the dialog route.
  return showDialog<_StoreEditorResult>(
    context: context,
    builder: (_) =>
        _StoreEditorDialog(partner: partner, governorates: governorates),
  );
}

/// Create/edit store prompt. Owns its TextEditingController lifecycle.
class _StoreEditorDialog extends StatefulWidget {
  const _StoreEditorDialog({required this.governorates, this.partner});

  final PartnerStore? partner;
  final List<Governorate> governorates;

  @override
  State<_StoreEditorDialog> createState() => _StoreEditorDialogState();
}

class _StoreEditorDialogState extends State<_StoreEditorDialog> {
  late final name = TextEditingController(text: widget.partner?.name);
  late final category = TextEditingController(text: widget.partner?.category);
  late final rate =
      TextEditingController(text: widget.partner?.commissionRate.toString());
  late final location = TextEditingController(text: widget.partner?.location);
  late final description =
      TextEditingController(text: widget.partner?.description);
  // Pre-selects the store's current governorate when editing (existing
  // stores show إدلب after the migration backfill); null only for a brand
  // new store, which the admin must explicitly choose before saving.
  String? governorateChoice;
  String? governorateError;
  StoreLogoUpload? pendingLogo;
  String? logoError;
  bool removeLogo = false;

  bool get _hasLogo =>
      pendingLogo != null ||
      (!removeLogo && widget.partner?.logoUrl != null);

  Future<void> _pickLogo() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final file = (picked?.files ?? const <PlatformFile>[]).firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (bytes.length > _maxStoreLogoBytes) {
      setState(() => logoError = 'حجم الشعار يجب ألا يتجاوز 300 KB.');
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    setState(() {
      pendingLogo = StoreLogoUpload(
        bytes: bytes,
        contentType: switch (extension) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        },
      );
      removeLogo = false;
      logoError = null;
    });
  }

  Widget _logoPreview() {
    final pending = pendingLogo;
    final url = removeLogo ? null : widget.partner?.logoUrl;
    final fallback = Icon(AdminSection.stores.icon);
    final Widget image = pending != null
        ? Image.memory(Uint8List.fromList(pending.bytes), fit: BoxFit.cover)
        : url != null
            ? Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
            : fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(width: 72, height: 72, child: image),
    );
  }

  @override
  void initState() {
    super.initState();
    final currentId = widget.partner?.governorateId;
    governorateChoice = widget.governorates
        .any((governorate) => governorate.id == currentId)
        ? currentId
        : null;
  }

  @override
  void dispose() {
    name.dispose();
    category.dispose();
    rate.dispose();
    location.dispose();
    description.dispose();
    super.dispose();
  }

  void _save() {
    final selectedGovernorateId = governorateChoice;
    if (selectedGovernorateId == null) {
      setState(() => governorateError = 'اختر المحافظة قبل الحفظ.');
      return;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    Navigator.pop(
      context,
      _StoreEditorResult(
        store: PartnerStore(
          id: widget.partner?.id ?? 'store-$now',
          name: name.text.trim(),
          category: category.text.trim(),
          commissionRate:
              double.tryParse(rate.text) ?? widget.partner?.commissionRate ?? 0,
          description: description.text.trim(),
          location: location.text.trim(),
          iconSeed: widget.partner?.iconSeed ?? now.remainder(100000),
          governorateId: selectedGovernorateId,
          isActive: widget.partner?.isActive ?? true,
        ),
        logo: pendingLogo,
        removeLogo: removeLogo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.partner == null ? 'إضافة محل' : 'تعديل المحل'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(children: [
              Row(children: [
                _logoPreview(),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('اختيار شعار')),
                    if (_hasLogo)
                      TextButton(
                          onPressed: () => setState(() {
                                pendingLogo = null;
                                removeLogo = true;
                              }),
                          child: const Text('إزالة الشعار')),
                  ]),
                ),
              ]),
              if (logoError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(logoError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              const SizedBox(height: 14),
              TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'اسم المحل')),
              const SizedBox(height: 10),
              TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: 'الفئة')),
              const SizedBox(height: 10),
              TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'نسبة العمولة %')),
              const SizedBox(height: 10),
              TextField(
                  controller: location,
                  decoration: const InputDecoration(labelText: 'الموقع')),
              const SizedBox(height: 10),
              TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'الوصف')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: governorateChoice,
                decoration: InputDecoration(
                  labelText: 'المحافظة',
                  errorText: governorateError,
                ),
                items: widget.governorates
                    .map((governorate) => DropdownMenuItem(
                        value: governorate.id,
                        child: Text(governorate.nameAr)))
                    .toList(),
                onChanged: (value) => setState(() {
                  governorateChoice = value;
                  governorateError = null;
                }),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}

class ProductsAdmin extends StatelessWidget {
  const ProductsAdmin({
    required this.cubit,
    required this.products,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<DigitalProduct> products;

  @override
  Widget build(BuildContext context) => _AdminPage(children: [
        _PageTitle(
            title: 'المنتجات الرقمية',
            subtitle: 'إدارة خيارات استبدال النقاط',
            action: FilledButton.icon(
                onPressed: () => _createProduct(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('إضافة منتج'))),
        const SizedBox(height: 18),
        _TableCard(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('المنتج')),
              DataColumn(label: Text('التكلفة')),
              DataColumn(label: Text('رقم هاتف')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text(''))
            ],
            rows: products
                .map((product) => DataRow(cells: [
                      DataCell(Text(product.name,
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                      DataCell(
                          Text('${formatNumber(product.costInPoints)} نقطة')),
                      DataCell(Icon(product.requiresPhoneNumber
                          ? Icons.check_circle_rounded
                          : Icons.remove_rounded)),
                      DataCell(Chip(
                          label: Text(product.isActive ? 'نشط' : 'متوقف'))),
                      DataCell(IconButton(
                          onPressed: () => _editProduct(context, product),
                          icon: const Icon(Icons.edit_outlined))),
                    ]))
                .toList(),
          ),
        ),
      ]);

  Future<void> _editProduct(
      BuildContext context, DigitalProduct product) async {
    final updated = await showDialog<_ProductEditorResult>(
      context: context,
      builder: (_) => _ProductEditorDialog(product: product),
    );
    if (updated != null) {
      await cubit.updateProduct(
        updated.product,
        image: updated.image,
        removeImage: updated.removeImage,
      );
    }
  }

  Future<void> _createProduct(BuildContext context) async {
    final created = await _showProductEditor(context);
    if (created != null) {
      await cubit.createProduct(created.product, image: created.image);
    }
  }
}

/// Result of the product editor: the product fields plus any image change.
class _ProductEditorResult {
  const _ProductEditorResult({
    required this.product,
    this.image,
    this.removeImage = false,
  });

  final DigitalProduct product;
  final StoreLogoUpload? image;
  final bool removeImage;
}

Future<_ProductEditorResult?> _showProductEditor(
  BuildContext context, [
  DigitalProduct? product,
]) {
  return showDialog<_ProductEditorResult>(
    context: context,
    builder: (_) => _ProductEditorDialog(product: product),
  );
}

/// Create/edit product prompt. Owns its TextEditingController lifecycle.
class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({this.product});

  final DigitalProduct? product;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final name = TextEditingController(text: widget.product?.name);
  late final cost =
      TextEditingController(text: widget.product?.costInPoints.toString());
  late var needsPhone = widget.product?.requiresPhoneNumber ?? false;
  late var active = widget.product?.isActive ?? true;
  StoreLogoUpload? pendingImage;
  String? imageError;
  bool removeImage = false;

  @override
  void dispose() {
    name.dispose();
    cost.dispose();
    super.dispose();
  }

  bool get _hasImage =>
      pendingImage != null ||
      (!removeImage && widget.product?.imageUrl != null);

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final file = (picked?.files ?? const <PlatformFile>[]).firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (bytes.length > _maxStoreLogoBytes) {
      setState(() => imageError = 'حجم الصورة يجب ألا يتجاوز 300 KB.');
      return;
    }
    final extension = (file.extension ?? '').toLowerCase();
    setState(() {
      pendingImage = StoreLogoUpload(
        bytes: bytes,
        contentType: switch (extension) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        },
      );
      removeImage = false;
      imageError = null;
    });
  }

  Widget _imagePreview() {
    final pending = pendingImage;
    final url = removeImage ? null : widget.product?.imageUrl;
    final fallback = Icon(Icons.redeem_rounded, color: Colors.grey.shade600);
    final Widget image = pending != null
        ? Image.memory(Uint8List.fromList(pending.bytes), fit: BoxFit.cover)
        : url != null
            ? Image.network(url,
                fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
            : fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Colors.grey.shade200,
        child: SizedBox(width: 72, height: 72, child: Center(child: image)),
      ),
    );
  }

  void _save() {
    final now = DateTime.now().microsecondsSinceEpoch;
    Navigator.pop(
      context,
      _ProductEditorResult(
        product: DigitalProduct(
          id: widget.product?.id ?? 'product-$now',
          name: name.text.trim(),
          costInPoints:
              int.tryParse(cost.text) ?? widget.product?.costInPoints ?? 0,
          iconSeed: widget.product?.iconSeed ?? now.remainder(100000),
          requiresPhoneNumber: needsPhone,
          isActive: active,
        ),
        image: pendingImage,
        removeImage: removeImage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product == null ? 'إضافة منتج' : 'تعديل المنتج'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              _imagePreview(),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('اختيار صورة')),
                  if (_hasImage)
                    TextButton(
                        onPressed: () => setState(() {
                              pendingImage = null;
                              removeImage = true;
                            }),
                        child: const Text('إزالة الصورة')),
                ]),
              ),
            ]),
            if (imageError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(imageError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 12),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم المنتج')),
            const SizedBox(height: 10),
            TextField(
                controller: cost,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'التكلفة بالنقاط')),
            SwitchListTile(
                value: needsPhone,
                onChanged: (value) => setState(() => needsPhone = value),
                title: const Text('يتطلب رقم هاتف')),
            SwitchListTile(
                value: active,
                onChanged: (value) => setState(() => active = value),
                title: const Text('المنتج نشط')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      );
}

class MerchantAccountsAdmin extends StatelessWidget {
  const MerchantAccountsAdmin({
    required this.cubit,
    required this.stores,
    required this.accounts,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<PartnerStore> stores;
  final List<MerchantAccount> accounts;

  @override
  Widget build(BuildContext context) => _AdminPage(
        children: [
          const _PageTitle(
            title: 'حسابات دخول المحلات',
            subtitle: 'كل محل يمكن أن يمتلك أكثر من حساب أو جهاز',
          ),
          const SizedBox(height: 18),
          ...stores.map((partner) {
            final storeAccounts =
                accounts.where((item) => item.storeId == partner.id).toList();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 150,
                      height: 44,
                      child: FilledButton.tonalIcon(
                        onPressed: () => _addAccount(context, partner),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('توليد حساب'),
                      ),
                    ),
                    if (storeAccounts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text('لا توجد حسابات لهذا المحل'),
                      ),
                    for (final account in storeAccounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          child: Icon(Icons.badge_outlined),
                        ),
                        title: Text(
                          account.email,
                          textDirection: TextDirection.ltr,
                        ),
                        subtitle: const Text(
                          'كلمة المرور تظهر مرة واحدة عند الإنشاء.',
                        ),
                        trailing: Text('${account.deviceCount} جهاز'),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      );

  Future<void> _addAccount(BuildContext context, PartnerStore partner) async {
    final issued = await _showMerchantAccountEditor(context, cubit, partner);
    if (issued == null) return;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم إنشاء الحساب'),
        content: SelectableText(
            'البريد: ${issued.account.email}\nكلمة المرور المؤقتة: ${issued.temporaryPassword}',
            textDirection: TextDirection.ltr),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('تم'))
        ],
      ),
    );
  }
}

class SettlementsAdmin extends StatelessWidget {
  const SettlementsAdmin({
    required this.cubit,
    required this.settlements,
    super.key,
  });

  final AdminAppCubit cubit;
  final List<MerchantSettlementSummary> settlements;

  @override
  Widget build(BuildContext context) => _AdminPage(children: [
        const _PageTitle(
            title: 'التحاسب الشهري',
            subtitle: 'إجمالي المبيعات والعمولة المستحقة لكل محل'),
        MonthlySettlementCard(cubit: cubit),
        const SizedBox(height: 18),
        _TableCard(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('المحل')),
              DataColumn(label: Text('العمليات')),
              DataColumn(label: Text('المبيعات')),
              DataColumn(label: Text('العمولة')),
              DataColumn(label: Text('الحالة'))
            ],
            rows: settlements.map((settlement) {
              final transactions = settlement.transactionCount;
              final sales = settlement.totalSalesSyp;
              final commission = settlement.commissionDueSyp;
              final settled = settlement.status == 'settled';
              return DataRow(cells: [
                DataCell(Text(settlement.storeName,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
                DataCell(Text('$transactions')),
                DataCell(Text('${formatNumber(sales)} ل.س')),
                DataCell(Text('${formatNumber(commission)} ل.س')),
                DataCell(FilledButton.tonalIcon(
                    onPressed:
                        settled ? null : () => cubit.settleStore(settlement),
                    icon: Icon(settled
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded),
                    label: Text(settled ? 'تم التسديد' : 'تحديد كمسدد'))),
              ]);
            }).toList(),
          ),
        ),
      ]);
}

/// Monthly settlement for ALL merchants of one completed calendar month. The
/// admin sees the count and totals first, confirms, then reads the result.
class MonthlySettlementCard extends StatefulWidget {
  const MonthlySettlementCard({required this.cubit, super.key});

  final AdminAppCubit cubit;

  @override
  State<MonthlySettlementCard> createState() => _MonthlySettlementCardState();
}

class _MonthlySettlementCardState extends State<MonthlySettlementCard> {
  late final List<String> _months = _completedMonths(DateTime.now());
  late String _selected = _months.first;
  late Future<List<MonthlySettlementRecord>> _history =
      widget.cubit.listMonthlySettlementHistory();
  bool _busy = false;

  /// The 12 most recent calendar months that are already over (YYYY-MM).
  static List<String> _completedMonths(DateTime now) => [
        for (var i = 1; i <= 12; i++)
          () {
            final date = DateTime.utc(now.year, now.month - i, 1);
            return '${date.year}-${date.month.toString().padLeft(2, '0')}';
          }(),
      ];

  String _label(String month) {
    final parts = month.split('-');
    return '${parts[1]}/${parts[0]}';
  }

  Future<void> _settle() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final preview = await widget.cubit.previewMonthlySettlement(_selected);
      if (!mounted) return;
      if (preview == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('تعذر تحميل معاينة التسوية الشهرية.')));
        return;
      }
      if (preview.openMerchantCount == 0) {
        messenger.showSnackBar(SnackBar(
            content: Text('لا توجد فواتير غير مسددة لشهر ${_label(_selected)}.')));
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تأكيد التسوية الشهرية'),
          content: Text(
              'شهر ${_label(_selected)}\n'
              'عدد التجار: ${preview.openMerchantCount}\n'
              'إجمالي المبيعات: ${formatNumber(preview.totalSalesSyp)} ل.س\n'
              'إجمالي العمولة المستحقة: ${formatNumber(preview.totalCommissionSyp)} ل.س\n\n'
              'تُسوّى الفواتير غير المسددة فقط. لا يمكن التراجع عن التسوية.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('تأكيد التسوية')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await widget.cubit.runMonthlySettlement(_selected);
      if (!mounted) return;
      if (result == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('تعذر إتمام التسوية الشهرية. حاول مرة أخرى.')));
        return;
      }
      final failed = result.merchants
          .where((merchant) => merchant.status == 'failed')
          .map((merchant) => merchant.storeName)
          .join('، ');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('نتيجة التسوية الشهرية'),
          content: Text(
              'تمت تسوية ${result.settledCount} تاجراً بإجمالي عمولة '
              '${formatNumber(result.totalCommissionSyp)} ل.س.\n'
              'تم تخطي ${result.skippedCount} (مسددة سابقاً).\n'
              'فشل ${result.failedCount}${failed.isEmpty ? '' : ': $failed'}.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('حسناً')),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _history = widget.cubit.listMonthlySettlementHistory());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _TableCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('التسوية الشهرية لكل التجار',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('تسوّي الفواتير غير المسددة لشهر مكتمل دفعة واحدة.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'الشهر'),
                  items: [
                    for (final month in _months)
                      DropdownMenuItem(value: month, child: Text(_label(month))),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _selected = value ?? _selected),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _settle,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('تسوية كل التجار'),
              ),
            ]),
            const SizedBox(height: 16),
            Text('سجل التسويات الشهرية',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            FutureBuilder<List<MonthlySettlementRecord>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator();
                }
                final items = snapshot.data ?? const <MonthlySettlementRecord>[];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('لا توجد تسويات شهرية بعد.'),
                  );
                }
                return Column(
                  children: [
                    for (final item in items.take(12))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${item.storeName} · ${_label(item.month)}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${formatNumber(item.commissionDueSyp)} ل.س عمولة · '
                            '${item.transactionCount} عملية'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsAdmin extends StatefulWidget {
  const SettingsAdmin({
    required this.cubit,
    required this.pointValueSyp,
    this.minCashWithdrawalSyp,
    this.shareRewardPoints,
    super.key,
  });

  final AdminAppCubit cubit;
  final double? pointValueSyp;
  final int? minCashWithdrawalSyp;
  final int? shareRewardPoints;

  @override
  State<SettingsAdmin> createState() => _SettingsAdminState();
}

/// Shows whole values without a trailing ".0" (e.g. 5 not 5.0).
String _formatPointValue(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

class _SettingsAdminState extends State<SettingsAdmin> {
  late final controller = TextEditingController(
      text: _formatPointValue(widget.pointValueSyp ?? 1));
  late final minCashController = TextEditingController(
      text: (widget.minCashWithdrawalSyp ?? 0).toString());
  late final shareRewardController = TextEditingController(
      text: (widget.shareRewardPoints ?? 0).toString());

  @override
  void didUpdateWidget(covariant SettingsAdmin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pointValueSyp != widget.pointValueSyp &&
        widget.pointValueSyp != null) {
      controller.text = _formatPointValue(widget.pointValueSyp!);
    }
    if (oldWidget.minCashWithdrawalSyp != widget.minCashWithdrawalSyp &&
        widget.minCashWithdrawalSyp != null) {
      minCashController.text = widget.minCashWithdrawalSyp.toString();
    }
    if (oldWidget.shareRewardPoints != widget.shareRewardPoints &&
        widget.shareRewardPoints != null) {
      shareRewardController.text = widget.shareRewardPoints.toString();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    minCashController.dispose();
    shareRewardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AdminPage(children: [
        const _PageTitle(
            title: 'الإعدادات العامة',
            subtitle: 'قيم مالية تؤثر في حسابات المنصة'),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'قيمة النقطة نقداً', suffixText: 'ل.س')),
                    const SizedBox(height: 10),
                    Text(
                        'تُستخدم هذه القيمة لحساب نقاط الفاتورة وقيمة طلب الاستبدال.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: _save, child: const Text('حفظ الإعدادات')),
                  ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: minCashController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'الحد الأدنى لسحب الكاش',
                            suffixText: 'ل.س')),
                    const SizedBox(height: 10),
                    Text(
                        'صفر يعني بلا حد أدنى. لا يُطبَّق على طلبات الاستبدال الحالية.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: _saveMinCashWithdrawal,
                        child: const Text('حفظ الحد الأدنى')),
                  ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                        controller: shareRewardController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'مكافأة مشاركة التطبيق',
                            suffixText: 'نقطة')),
                    const SizedBox(height: 10),
                    Text(
                        'تُمنح مرة واحدة لكل حساب زبون. صفر يعني إيقاف المكافأة.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: _saveShareReward,
                        child: const Text('حفظ مكافأة المشاركة')),
                  ]),
            ),
          ),
        ),
      ]);

  Future<void> _saveShareReward() async {
    final value = int.tryParse(shareRewardController.text.trim());
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أدخل عدد نقاط صحيحاً (صفر لإيقاف المكافأة).')));
      return;
    }
    final saved = await widget.cubit.updateShareRewardPoints(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? 'تم حفظ مكافأة المشاركة.'
            : 'تعذر حفظ مكافأة المشاركة. حاول مرة أخرى.'),
      ),
    );
  }

  Future<void> _saveMinCashWithdrawal() async {
    final value = int.tryParse(minCashController.text.trim());
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أدخل مبلغاً صحيحاً بالليرة السورية.')));
      return;
    }
    final saved = await widget.cubit.updateMinCashWithdrawal(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? 'تم حفظ الحد الأدنى لسحب الكاش.'
            : 'تعذر حفظ الحد الأدنى. حاول مرة أخرى.'),
      ),
    );
  }

  Future<void> _save() async {
    final value =
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    if (value <= 0) return;
    // Only report success when the backend update actually succeeded
    // (AdminAppCubit.updatePointValue returns false on any failure).
    final saved = await widget.cubit.updatePointValue(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? 'تم حفظ قيمة النقطة.'
            : 'تعذر حفظ قيمة النقطة. حاول مرة أخرى.'),
      ),
    );
  }
}

Customer _customerForRequest(
  CashRedemptionRequest request,
  List<Customer> customers,
) {
  for (final customer in customers) {
    if (customer.id == request.customerId) return customer;
  }
  return Customer(
    id: request.customerId,
    name: request.customerId,
    governorate: '',
    pointsBalance: 0,
    createdAt: request.createdAt,
  );
}

Future<IssuedMerchantAccount?> _showMerchantAccountEditor(
  BuildContext context,
  AdminAppCubit cubit,
  PartnerStore store,
) async {
  String email = '';
  String password = '';
  String label = store.name;

  final values = await showDialog<Map<String, String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('توليد حساب محل'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                ),
                onChanged: (value) => email = value,
              ),
              const SizedBox(height: 10),
              TextField(
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور اختيارية',
                ),
                onChanged: (value) => password = value,
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'اسم الجهاز',
                ),
                onChanged: (value) => label = value,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop({
            'email': email.trim(),
            'password': password.trim(),
            'label': label.trim(),
          }),
          child: const Text('إنشاء'),
        ),
      ],
    ),
  );

  if (values == null) return null;

  final accountEmail = values['email']?.trim() ?? '';
  if (accountEmail.isEmpty) return null;

  final accountPassword = values['password']?.trim() ?? '';
  final displayLabel = values['label']?.trim() ?? '';

  return cubit.createMerchantAccount(
    storeId: store.id,
    email: accountEmail,
    password: accountPassword.isEmpty ? null : accountPassword,
    displayLabel: displayLabel.isEmpty ? null : displayLabel,
  );
}

class _AdminPage extends StatelessWidget {
  const _AdminPage({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children)))
      ]);
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
              width: 520,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant))
                  ])),
          if (action != null) action!,
        ],
      );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: .14),
                foregroundColor: color,
                child: Icon(icon)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Text(value,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(label, style: Theme.of(context).textTheme.bodySmall)
                ]))
          ]),
        ),
      );
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
      child: SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: child));
}

class _EmptyAdmin extends StatelessWidget {
  const _EmptyAdmin({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(children: [
            Icon(icon, size: 54, color: YallaColors.success),
            const SizedBox(height: 12),
            Text(text)
          ])));
}
