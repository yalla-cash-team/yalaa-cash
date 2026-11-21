part of '../../customer_app.dart';

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
                    child: YcLogoPlate(
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
            child: YcFadeSlideIn(
              offset: 18,
              child: Column(
                children: [
                  Text(
                    store.name,
                    textAlign: TextAlign.center,
                    style: YcType.title(context),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Gold "حصري" (exclusive) pill.
                      const YcChip(
                        label: 'حصري',
                        tone: YcTone.warning,
                        icon: Icons.workspace_premium_rounded,
                        outlined: true,
                      ),
                      YcChip(label: store.category),
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

/// The premium hero gradient (deep navy → brand blue) behind the details-page
/// logo, with two quiet decorative circles.
class _StoreHeaderBackdrop extends StatelessWidget {
  const _StoreHeaderBackdrop();

  @override
  Widget build(BuildContext context) {
    final colors = YcColors.of(context);
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
            colors: [colors.heroStart, colors.heroEnd],
          ),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -48,
              start: -36,
              child: circle(170, .06),
            ),
            PositionedDirectional(
              bottom: -60,
              end: -28,
              child: circle(190, .05),
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
      decoration: YcSurface.of(context).decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              // Flexible: wraps instead of overflowing on 320dp + large text.
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text('عن المحل', style: theme.textTheme.titleSmall),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
              description,
              style: YcType.body(context)?.copyWith(
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
        child: Semantics(
          header: true,
          child: Text(
            'العروض الحصرية',
            style: Theme.of(context).textTheme.titleLarge,
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
      if (end != null &&
          end.isAfter(now) &&
          (next == null || end.isBefore(next))) {
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
                    child:
                        _StoreOfferCard(key: ValueKey(offer.id), offer: offer),
                  ),
              ],
            );
          } else {
            child = switch (offers.status) {
              LoadStatus.initial ||
              LoadStatus.loading =>
                const YcSkeleton.offer(
                  key: ValueKey('store-offers-loading'),
                  label: 'جارٍ تحميل العروض',
                ),
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
    final colors = YcColors.of(context);
    final imageUrl = _publicOfferImageUrl(offer);
    final label = offer.discountLabel?.trim() ?? '';
    final description = offer.description.trim();
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: YcSurface.of(context).decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null)
            _StoreOfferImage(url: imageUrl, title: offer.title),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Free-text discount label (display only; never calculated).
                if (label.isNotEmpty) ...[
                  YcChip.discount(label),
                  const SizedBox(height: 10),
                ],
                Text(
                  offer.title,
                  style: YcType.item(context)?.copyWith(height: 1.4),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: YcType.body(context)?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.7,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.event_available_rounded,
                      size: 18, color: colors.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _offerExpiryText(offer),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          // How to use the offer: a quiet brand-tinted strip.
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.brandTint,
              border: Border(
                top: BorderSide(color: YcSurface.of(context).hairline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.phone_iphone_rounded,
                      size: 18, color: colors.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'أبرز تطبيق يلا كاش عند المحاسبة للاستفادة من العرض',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                        color: colors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole offer image, never cropped: its height follows the image's
/// own aspect ratio (letterboxed only beyond a maximum height). Decoded at
/// the card's width, faded in once loaded, hidden if it fails to load.
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
        child: YcNetworkImage(
          url,
          width: double.infinity,
          semanticLabel: 'صورة العرض: $title',
          placeholder: AspectRatio(
            aspectRatio: 16 / 9,
            child: Icon(Icons.image_outlined,
                size: 34, color: scheme.onSurfaceVariant.withValues(alpha: .5)),
          ),
        ),
      ),
    );
  }
}

/// Offers could not be loaded and none are cached: the shared error state.
class _StoreOffersError extends StatelessWidget {
  const _StoreOffersError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => YcCard(
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          child: YcErrorState(
            icon: Icons.wifi_off_rounded,
            title: 'تعذر تحميل العروض',
            description: message,
            onRetry: onRetry,
          ),
        ),
      );
}

/// Shown above existing offers when a reload failed.
class _StoreOffersInlineRetry extends StatelessWidget {
  const _StoreOffersInlineRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: YcInlineBanner(
          message: 'تعذر تحديث العروض.',
          tone: YcTone.danger,
          actionLabel: 'إعادة المحاولة',
          onAction: onRetry,
        ),
      );
}

/// Shown when the store has no offers available right now.
class _StoreOffersEmptyState extends StatelessWidget {
  const _StoreOffersEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YcColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: YcSurface.of(context).decoration(),
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
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: [colors.brandTint, colors.goldTint],
                    ),
                    border: Border.all(
                      color: colors.brand.withValues(alpha: .18),
                    ),
                  ),
                  child: const SizedBox(width: 84, height: 84),
                ),
                Icon(Icons.local_offer_rounded, size: 38, color: colors.brand),
                PositionedDirectional(
                  top: 2,
                  end: 4,
                  child: Icon(Icons.auto_awesome_rounded,
                      size: 20, color: colors.gold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'لا توجد عروض متاحة حالياً',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'ستظهر العروض الحصرية لهذا المحل هنا فور إضافتها.',
            textAlign: TextAlign.center,
            style: YcType.meta(context)?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }
}
