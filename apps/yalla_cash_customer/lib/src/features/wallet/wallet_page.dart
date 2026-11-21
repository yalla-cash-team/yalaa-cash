part of '../../customer_app.dart';

/// The wallet: an optional balance header, a segmented section navigator
/// (العمليات / سحب الكاش / المنتجات) and the three history sections in one
/// continuous, lazily built list.
///
/// The segments jump to their section and follow the scroll position, so
/// every entry stays reachable in one place exactly as before; nothing is
/// filtered or hidden.
class CustomerWalletPage extends StatefulWidget {
  const CustomerWalletPage({
    required this.transactions,
    required this.customer,
    this.productRedemptions = const [],
    this.cashRequests = const [],
    this.loading = false,
    this.failed = false,
    this.onRetry,
    this.points,
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

  /// The real points summary for the balance header, shown when known.
  final PointsSummary? points;

  /// Segment labels, in section order.
  static const sectionLabels = ['العمليات', 'سحب الكاش', 'المنتجات'];

  @override
  State<CustomerWalletPage> createState() => _CustomerWalletPageState();
}

class _CustomerWalletPageState extends State<CustomerWalletPage> {
  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _sectionKeys = List.generate(3, (_) => GlobalKey());
  int _section = 0;

  /// True while a segment tap is scrolling, so the scroll-follow does not
  /// flicker through the sections in between.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_followScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Scroll offset at which section [index]'s heading reaches the top.
  double? _sectionOffset(int index) {
    final box = _sectionKeys[index].currentContext?.findRenderObject();
    if (box == null || !box.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  void _followScroll() {
    if (_jumping || !_controller.hasClients) return;
    final position = _controller.position;
    var current = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final start = _sectionOffset(i);
      if (start != null && start <= position.pixels + YcSpace.xl) current = i;
    }
    // At the very end of a scrollable list the last section is the one in
    // view, even when it is too short to reach the top.
    if (position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1) {
      current = _sectionKeys.length - 1;
    }
    if (current != _section) setState(() => _section = current);
  }

  Future<void> _goToSection(int index) async {
    setState(() => _section = index);
    if (!_controller.hasClients) return;
    final duration = YcMotion.resolve(context, YcMotion.medium);
    Future<void> scrollTo(double offset) {
      final position = _controller.position;
      final target = offset.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      return duration == Duration.zero
          ? Future.sync(() => _controller.jumpTo(target))
          : _controller.animateTo(
              target,
              duration: duration,
              curve: YcMotion.standard,
            );
    }

    _jumping = true;
    try {
      final first = index == 0 ? 0.0 : _sectionOffset(index);
      if (first == null) return;
      await scrollTo(first);
      // Lazily built lists before the section are estimated until laid
      // out; settle on the exact heading position once they are.
      final exact = index == 0 ? 0.0 : _sectionOffset(index);
      if (mounted && exact != null && (exact - _controller.offset).abs() > 1) {
        _controller.jumpTo(exact.clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        ));
      }
    } finally {
      _jumping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final retry = widget.onRetry;
    if (widget.failed) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          YcSpace.gutter,
          YcSpace.sm,
          YcSpace.gutter,
          YcSpace.xl,
        ),
        children: [
          YcErrorState(
            title: 'تعذر تحميل السجل',
            description: 'تحقق من اتصالك ثم حاول مرة أخرى.',
            onRetry: retry,
          ),
        ],
      );
    }
    final points = widget.points;
    final loading = widget.loading;
    const gutter = EdgeInsets.symmetric(horizontal: YcSpace.gutter);

    // One section: its heading (the scroll anchor) and then its entries,
    // built lazily, or a placeholder / empty message.
    List<Widget> section<T>({
      required int index,
      required String title,
      required List<T> items,
      required int skeletonRows,
      required YcEmptyState empty,
      required Widget Function(T item) tile,
    }) =>
        [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              YcSpace.gutter,
              index == 0 ? YcSpace.sm : YcSpace.xl,
              YcSpace.gutter,
              YcSpace.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _sectionKeys[index],
                child: YcSectionHeader(title),
              ),
            ),
          ),
          SliverPadding(
            padding: gutter,
            sliver: loading
                ? SliverToBoxAdapter(child: YcSkeleton(rows: skeletonRows))
                : items.isEmpty
                    ? SliverToBoxAdapter(child: empty)
                    : SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: YcSpace.xs),
                          child: tile(items[i]),
                        ),
                      ),
          ),
        ];

    return Column(
      children: [
        if (points != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              YcSpace.gutter,
              YcSpace.sm,
              YcSpace.gutter,
              0,
            ),
            child: YcBalanceHero(
              label: 'رصيد النقاط',
              value: points.pointsBalance,
              unit: 'نقطة',
              compact: true,
              stats: [
                YcHeroStat(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'المتاح',
                  value: points.availablePoints,
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            YcSpace.gutter,
            YcSpace.sm,
            YcSpace.gutter,
            YcSpace.xxs,
          ),
          child: YcSegmentedTabs(
            labels: CustomerWalletPage.sectionLabels,
            selectedIndex: _section,
            onChanged: (index) => unawaited(_goToSection(index)),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ...section<LoyaltyTransaction>(
                index: 0,
                title: 'سجل العمليات',
                items: widget.transactions,
                skeletonRows: 3,
                empty: const YcEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'لا توجد عمليات حتى الآن',
                ),
                tile: (t) => _TransactionTile(transaction: t),
              ),
              ...section<CashRedemptionRequest>(
                index: 1,
                title: 'طلبات سحب الكاش',
                items: widget.cashRequests,
                skeletonRows: 2,
                empty: const YcEmptyState(
                  icon: Icons.payments_outlined,
                  title: 'لا توجد طلبات سحب بعد',
                ),
                tile: (r) => _CashRequestTile(request: r),
              ),
              ...section<ProductRedemption>(
                index: 2,
                title: 'طلبات استبدال المنتجات',
                items: widget.productRedemptions,
                skeletonRows: 2,
                empty: const YcEmptyState(
                  icon: Icons.redeem_outlined,
                  title: 'لا توجد طلبات استبدال بعد',
                ),
                tile: (r) => _RedemptionTile(redemption: r),
              ),
              const SliverPadding(
                padding: EdgeInsets.only(bottom: YcSpace.xl),
              ),
            ],
          ),
        ),
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
          // Value and unit on one line; the "+" stays before the digits in
          // right-to-left text.
          trailing: YcAmount(
            transaction.customerPointsEarned,
            unit: 'نقطة',
            signed: true,
            color: YcToneColors.of(context, YcTone.success).foreground,
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
          title: YcAmount.format(request.cashValueSyp, unit: 'ل.س'),
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
            YcAmount(redemption.pointsCostSnapshot, unit: 'نقطة'),
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
