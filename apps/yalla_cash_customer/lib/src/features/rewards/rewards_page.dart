part of '../../customer_app.dart';

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
              // Decoded at the plate's size, not the file's full resolution.
              child: YcNetworkImage(
                imageUrl,
                placeholder: icon(scheme.primary.withValues(alpha: .25)),
                error: icon(scheme.primary),
              ),
            ),
    );
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
    final pointValue = _pointValueSyp(widget.state.cashRequests);
    // Points, products and requests arrive in one batch with the points
    // summary, so a null summary means that data has not loaded yet.
    final summary = widget.state.points;
    final failed = summary == null && widget.state.status == LoadStatus.failure;
    final loading = summary == null && !failed;
    // The real available points, or null while unknown. There is no
    // fallback to the total balance: redemption waits until this is loaded.
    final available = summary?.availablePoints;
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
        const YcSectionHeader(
          'استبدال نقاط بكاش',
          subtitle: 'حوّل نقاطك المتاحة إلى رصيد نقدي',
        ),
        const SizedBox(height: YcSpace.sm),
        // Only this card listens to the typed text, so typing never rebuilds
        // the summary or the product list below it.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: cashPointsController,
          builder: (context, value, _) {
            final requested = int.tryParse(cashPointsController.text) ?? 0;
            // Submission rule: unchanged once available points are known.
            final canSubmitCash =
                available != null && requested > 0 && requested <= available;
            // Feedback mirrors that rule exactly: an error shows only when
            // something was typed and the rule rejects it (never while the
            // balance is unknown).
            final String? cashError = available == null ||
                    cashPointsController.text.trim().isEmpty ||
                    canSubmitCash
                ? null
                : requested <= 0
                    ? 'أدخل عدداً صحيحاً أكبر من صفر'
                    : 'العدد أكبر من رصيدك المتاح';
            return YcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: cashPointsController,
                    keyboardType: TextInputType.number,
                    // A larger figure with tabular digits for amounts.
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: YcType.tabular,
                        ),
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
            );
          },
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

/// Available-points summary at the top of the store tab: the compact premium
/// hero. Shows the real available points once loaded, a quiet progress bar
/// while loading, and a retry when loading failed (never the total balance
/// in their place).
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
  Widget build(BuildContext context) => YcBalanceHero(
        label: 'رصيدك المتاح',
        value: summary?.availablePoints,
        unit: 'نقطة',
        inlineUnit: true,
        compact: true,
        failed: summary == null && failed,
        onRetry: onRetry,
      );
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
                    child: YcAmount(
                      valueSyp,
                      unit: 'ل.س',
                      size: YcAmountSize.medium,
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
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: YcSpace.xxs),
                    // The cost as a gold amount chip (gold marks points).
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: YcColors.of(context).goldTint,
                        borderRadius: BorderRadius.circular(YcRadius.pill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        child: YcAmount(
                          product.costInPoints,
                          unit: 'نقطة',
                          color: YcColors.of(context).goldInk,
                        ),
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
