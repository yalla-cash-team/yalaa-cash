part of '../../customer_app.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({
    required this.cubit,
    required this.state,
    required this.repository,
    required this.darkMode,
    required this.onDarkModeChanged,
    this.cityName,
    super.key,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final YallaCashRepository repository;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;

  /// The saved city's name, shown next to the governorate in the drawer.
  final String? cityName;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  var selectedIndex = 0;

  /// One memo per tab: a tab's page widget is rebuilt only when the state
  /// it actually reads changes. An unrelated update (e.g. the notification
  /// count, a QR token, another tab's data) reuses the same widget instance,
  /// so Flutter skips that whole subtree.
  final _homeMemo = _PageMemo();
  final _qrMemo = _PageMemo();
  final _walletMemo = _PageMemo();
  final _rewardsMemo = _PageMemo();

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final customer = state.customer!;
    final pages = [
      _homeMemo.of(
        [widget.cubit, customer, state.points, state.stores, state.banners],
        () => CustomerHomePage(
          cubit: widget.cubit,
          state: state,
          customer: customer,
          // Quick actions switch tabs exactly like the bottom navigation.
          onNavigate: _selectTab,
        ),
      ),
      _qrMemo.of(
        [widget.cubit, customer, state.qrToken, state.failure],
        () => CustomerQrPage(
            cubit: widget.cubit, state: state, customer: customer),
      ),
      // Wallet and store fade in on their first visit only (never on return).
      _walletMemo.of(
        [
          widget.cubit,
          selectedIndex == 2,
          customer,
          state.transactions,
          state.productRedemptions,
          state.cashRequests,
          state.points,
          state.status,
        ],
        () => YcRevealOnFirstShow(
          active: selectedIndex == 2,
          child: CustomerWalletPage(
            transactions: state.transactions,
            customer: customer,
            productRedemptions: state.productRedemptions,
            cashRequests: state.cashRequests,
            // Wallet data arrives in one batch with the points summary.
            loading: state.points == null && state.status != LoadStatus.failure,
            failed: state.points == null && state.status == LoadStatus.failure,
            onRetry: widget.cubit.refresh,
            points: state.points,
          ),
        ),
      ),
      _rewardsMemo.of(
        [
          widget.cubit,
          selectedIndex == 3,
          customer,
          state.points,
          state.status,
          state.products,
          state.productRedemptions,
          state.cashRequests,
        ],
        () => YcRevealOnFirstShow(
          active: selectedIndex == 3,
          child: CustomerRewardsPage(cubit: widget.cubit, state: state),
        ),
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
        governorateName: widget.cityName == null
            ? customer.governorate
            : '${customer.governorate} · ${widget.cityName}',
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
        onSelected: _selectTab,
      ),
    );
  }

  /// Shows tab [index]; shared by the bottom navigation and Home's quick
  /// actions, so both behave identically. The pages themselves rebuild only
  /// when their own memo dependencies change.
  void _selectTab(int index) {
    final changed = index != selectedIndex;
    setState(() => selectedIndex = index);
    // Re-sync authoritative data when switching sections so Home /
    // Wallet / Rewards never remain stale after admin-side changes.
    if (changed) unawaited(widget.cubit.refresh());
  }

  /// Two-step location change: governorate, then (when it has cities) city.
  Future<void> _changeGovernorate() async {
    final governorates = await widget.repository.listActiveGovernorates();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (context) => GovernorateSelectionScreen(
          governorates: governorates,
          step: 1,
          onSelected: (governorate) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final current = widget.cubit.state.customer?.governorateId;
              if (governorate.id != current) {
                await widget.cubit.updateGovernorate(governorate.id);
                if (widget.cubit.state.failure != null) {
                  messenger.showSnackBar(SnackBar(
                      content: Text(_customerFailureMessage(
                          widget.cubit.state.failure))));
                  return;
                }
              }
              final cities = await widget.repository
                  .listActiveCities(governorateId: governorate.id);
              if (!context.mounted) return;
              if (cities.isEmpty) {
                Navigator.of(context).pop();
                return;
              }
              final chosen = await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (cityContext) => CitySelectionScreen(
                    governorateName: governorate.nameAr,
                    cities: cities,
                    onBack: () => Navigator.of(cityContext).pop(false),
                    onSelected: (city) async {
                      final cityMessenger = ScaffoldMessenger.of(cityContext);
                      try {
                        await widget.cubit.updateCity(city.id);
                        if (!cityContext.mounted) return;
                        if (widget.cubit.state.failure == null) {
                          Navigator.of(cityContext).pop(true);
                          return;
                        }
                        cityMessenger.showSnackBar(SnackBar(
                            content: Text(_customerFailureMessage(
                                widget.cubit.state.failure))));
                      } catch (_) {
                        if (cityContext.mounted) {
                          cityMessenger.showSnackBar(const SnackBar(
                              content: Text('تعذر حفظ المدينة المختارة.')));
                        }
                      }
                    },
                  ),
                ),
              );
              if (chosen == true && context.mounted) {
                Navigator.of(context).pop();
              }
            } catch (_) {
              if (context.mounted) {
                messenger.showSnackBar(const SnackBar(
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
                  ?.copyWith(fontWeight: FontWeight.w700),
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

/// Caches one tab page widget against the state it reads. [of] returns the
/// same widget instance while every dependency is unchanged (identical or
/// equal), so Flutter skips rebuilding that tab's subtree; any change builds
/// a fresh widget. Purely a rebuild optimisation: no state is held here.
class _PageMemo {
  List<Object?>? _dependencies;
  Widget? _widget;

  Widget of(List<Object?> dependencies, Widget Function() builder) {
    final previous = _dependencies;
    final cached = _widget;
    if (cached != null &&
        previous != null &&
        previous.length == dependencies.length) {
      var same = true;
      for (var i = 0; i < dependencies.length; i++) {
        final a = previous[i];
        final b = dependencies[i];
        if (!identical(a, b) && a != b) {
          same = false;
          break;
        }
      }
      if (same) return cached;
    }
    _dependencies = List<Object?>.of(dependencies, growable: false);
    return _widget = builder();
  }
}
