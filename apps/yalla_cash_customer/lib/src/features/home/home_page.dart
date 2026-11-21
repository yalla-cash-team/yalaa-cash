part of '../../customer_app.dart';

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
    this.onNavigate,
  });

  final CustomerAppCubit cubit;
  final CustomerAppState state;
  final Customer customer;

  /// Switches the shell to an existing tab (1 كودي, 2 المحفظة, 3 المتجر).
  /// The quick actions show only when the page is hosted by a shell that
  /// provides it.
  final ValueChanged<int>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final points = state.points;
    final stores =
        state.stores.where((store) => store.isActive).toList(growable: false);
    final banners = state.banners;
    final navigate = onNavigate;
    // Everything above the store list is a handful of fixed widgets; the
    // store cards themselves are built lazily as they scroll into view.
    final head = <Widget>[
      _BalanceCard(points: points),
      if (navigate != null) ...[
        const SizedBox(height: YcSpace.md),
        _HomeQuickActions(onNavigate: navigate),
      ],
      if (banners.isNotEmpty) ...[
        const SizedBox(height: YcSpace.md),
        _HomeBannerCarousel(banners: banners),
      ],
      const SizedBox(height: YcSpace.xl),
      const YcSectionHeader('المحلات الحصرية بمدينتك'),
      const SizedBox(height: YcSpace.sm),
      if (stores.isEmpty)
        customer.cityId != null
            ? const YcEmptyState(
                icon: Icons.storefront_outlined,
                title: 'لا توجد محلات في مدينتك حالياً',
                description:
                    'نعمل على إضافة شركاء جدد قريباً. يمكنك تغيير المدينة من القائمة الجانبية.',
              )
            : const YcEmptyState(
                icon: Icons.storefront_outlined,
                title: 'لا توجد محلات متاحة حالياً',
              ),
    ];
    // One gentle entrance for the page, played when Home is first built. It
    // wraps the list itself (not its lazily built children) and the page stays
    // mounted across tab switches and rebuilds, so it does not replay on tab
    // return, refresh, or scrolling. Skipped under reduced motion.
    return YcFadeSlideIn(
      offset: 10,
      child: ListView.builder(
        key: const PageStorageKey('customer-home'),
        padding: const EdgeInsets.fromLTRB(
          YcSpace.gutter,
          YcSpace.sm,
          YcSpace.gutter,
          YcSpace.xl,
        ),
        itemCount: head.length + stores.length,
        itemBuilder: (context, index) {
          if (index < head.length) return head[index];
          final partner = stores[index - head.length];
          return Padding(
            key: ValueKey('store-${partner.id}'),
            padding: const EdgeInsets.only(bottom: YcSpace.sm),
            child: _StoreCard(store: partner, cubit: cubit),
          );
        },
      ),
    );
  }
}

/// Three shortcuts under the balance card. Each one only switches the shell
/// to an existing tab, exactly like tapping that tab: كودي → my QR code,
/// استبدال → the rewards store, السجل → the wallet history.
class _HomeQuickActions extends StatelessWidget {
  const _HomeQuickActions({required this.onNavigate});

  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _QuickAction(
              key: const Key('quick-action-qr'),
              icon: Icons.qr_code_scanner_rounded,
              label: 'كودي',
              emphasised: true,
              onTap: () => onNavigate(1),
            ),
          ),
          const SizedBox(width: YcSpace.sm),
          Expanded(
            child: _QuickAction(
              key: const Key('quick-action-redeem'),
              icon: Icons.card_giftcard_rounded,
              label: 'استبدال',
              onTap: () => onNavigate(3),
            ),
          ),
          const SizedBox(width: YcSpace.sm),
          Expanded(
            child: _QuickAction(
              key: const Key('quick-action-history'),
              icon: Icons.receipt_long_rounded,
              label: 'السجل',
              onTap: () => onNavigate(2),
            ),
          ),
        ],
      );
}

/// One quick-action tile: an icon disc over its label, announced as a
/// single button. The QR action's disc carries the hero gradient.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YcColors.of(context);
    final disc = emphasised
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: colors.heroGradient,
            ),
            child: SizedBox.square(
              dimension: 40,
              child: Icon(icon, size: 21, color: colors.onHero),
            ),
          )
        : YcIconBadge(icon, size: 40, circle: true);
    return YcCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: YcSpace.xs,
        vertical: YcSpace.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(child: disc),
          const SizedBox(height: YcSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelLarge?.copyWith(color: colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner artwork is designed at 1200 x 500 px (2.4 : 1). The carousel keeps
/// that ratio at every screen width, so the height scales with the width.
const double _bannerAspectRatio = 1200 / 500;

/// How long each ad stays on screen before the carousel advances.
const Duration _bannerInterval = Duration(seconds: 5);

/// How long a banner whose image failed to load is left out of the automatic
/// rotation before it is tried again.
const Duration _bannerRetryAfter = Duration(seconds: 60);

/// Advertising banner carousel with automatic rotation every 5 seconds and a
/// page indicator. Manual swipe keeps working (PageView's normal gesture
/// handling), and auto-rotation continues from wherever the user last swiped
/// to, rather than resetting.
///
/// Automatic rotation never shows an unready banner:
///
/// * The next banner's image is **precached** (decoded into the image cache,
///   with the exact provider the page uses) before anything changes. Until it
///   is ready the current banner simply stays on screen, however slow the
///   connection is.
/// * A banner whose image **fails** to load is skipped (and retried after
///   [_bannerRetryAfter]); if none of the others can be shown, the current one
///   stays. A failed banner is still reachable by swiping, where it shows its
///   quiet error icon.
/// * The change is a **250ms crossfade**: the page switches underneath while a
///   copy of the outgoing banner fades out on top, so there is no blank or
///   half-loaded frame at any point. With reduced motion the ad changes at
///   once, at the same cadence, with no fade.
///
/// Rotation pauses while the Home tab is hidden (another tab is showing) and
/// while the app is in the background, and resumes when it is visible again.
class _HomeBannerCarousel extends StatefulWidget {
  const _HomeBannerCarousel({required this.banners});

  final List<Banner> banners;

  @override
  State<_HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<_HomeBannerCarousel>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final PageController _controller = PageController();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: YcMotion.medium,
  )..addStatusListener(_onFadeStatus);
  late final Animation<double> _fadeOpacity = Tween<double>(begin: 1, end: 0)
      .animate(CurvedAnimation(parent: _fade, curve: YcMotion.standard));
  Timer? _timer;
  int _page = 0;
  bool _visible = true;
  bool _foreground = true;

  /// Index of the outgoing banner while it fades out on top, else null.
  int? _fadeFrom;

  /// Decode width (physical px) the pages use, measured from the layout.
  /// Precaching uses the same value so the cache key matches the page's.
  int? _cacheWidth;

  /// Bumped whenever a pending advance must be abandoned (rotation paused,
  /// banner list replaced, disposed).
  int _epoch = 0;
  bool _advancing = false;

  /// When each banner's image last failed to load (by banner id).
  final Map<String, DateTime> _failedAt = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // False while the IndexedStack shows another tab.
    final visible = Visibility.of(context);
    if (visible != _visible || _timer == null) {
      _visible = visible;
      _restartTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground) {
      _foreground = foreground;
      if (_fadeFrom != null) setState(_cancelFade);
      _restartTimer();
    }
  }

  @override
  void didUpdateWidget(covariant _HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The banner list can change (e.g. after a governorate switch) to a
    // different length or different banners at the same length. Either way,
    // reset to the first page so we never try to show an index that no longer
    // exists in the new list, then restart the rotation timer to match the
    // new list.
    final changed = oldWidget.banners.length != widget.banners.length ||
        !_sameBannerIds(oldWidget.banners, widget.banners);
    if (changed) {
      _page = 0;
      _cancelFade();
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
    _timer = null;
    // Abandon any advance still waiting for an image: it belongs to the old
    // timer / banner list / visibility.
    _epoch++;
    _advancing = false;
    _cancelFade();
    if (widget.banners.length < 2 || !_visible || !_foreground) return;
    _timer = Timer.periodic(_bannerInterval, (_) {
      if (!mounted || !_controller.hasClients || _advancing) return;
      unawaited(_advance());
    });
  }

  /// Moves to the next banner that is ready to show, or stays on the current
  /// one. Starts at the tick and runs until an image is ready; the next tick
  /// does nothing while it is still waiting (a slow image is awaited once,
  /// never requested again).
  Future<void> _advance() async {
    final count = widget.banners.length;
    if (count < 2) return;
    final epoch = _epoch;
    final from = _page;
    _advancing = true;
    try {
      for (var step = 1; step < count; step++) {
        final index = (from + step) % count;
        final ready = await _ready(widget.banners[index]);
        // The rotation was paused or replaced, or the user swiped elsewhere
        // while waiting: do not move anything.
        if (!mounted || epoch != _epoch || _page != from) return;
        if (!ready) continue;
        _show(index, from);
        return;
      }
    } finally {
      if (epoch == _epoch) _advancing = false;
    }
  }

  /// Whether [banner] can be shown without a blank frame: its image is
  /// decoded in the image cache (waiting for it if the connection is slow),
  /// or it has no image at all. False when the image fails to load.
  Future<bool> _ready(Banner banner) async {
    final url = banner.imageUrl;
    if (url.isEmpty) return true; // nothing to load: shows its quiet icon
    final failedAt = _failedAt[banner.id];
    if (failedAt != null &&
        DateTime.now().difference(failedAt) < _bannerRetryAfter) {
      return false;
    }
    var failed = false;
    await precacheImage(
      YcNetworkImage.provider(url, cacheWidth: _cacheWidth),
      context,
      onError: (_, __) => failed = true,
    );
    if (failed) {
      _failedAt[banner.id] = DateTime.now();
      return false;
    }
    _failedAt.remove(banner.id);
    return true;
  }

  /// Shows [index] (whose image is ready) in place of [from].
  void _show(int index, int from) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      // Reduced motion: change ad at the same cadence, without any fade.
      _controller.jumpToPage(index);
      return;
    }
    // The page switches underneath in the same frame the outgoing copy
    // appears on top, so there is never a frame with neither image painted.
    setState(() => _fadeFrom = from);
    _controller.jumpToPage(index);
    _fade.forward(from: 0);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _fadeFrom = null);
    }
  }

  /// Ends any crossfade at once. Does not rebuild by itself: call it from a
  /// path that is already rebuilding, or inside setState.
  void _cancelFade() {
    _fade.stop();
    _fadeFrom = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _epoch++;
    _timer?.cancel();
    _fade.dispose();
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

  /// One banner's picture on the neutral background: BoxFit.contain shows the
  /// whole ad, and the background fills any leftover space when the image
  /// ratio differs from 2.4 : 1. A failed image (404, network hiccup, stale
  /// URL) shows a quiet icon on just that banner.
  Widget _bannerPicture(Banner banner, Color fill) => ColoredBox(
        color: fill,
        child: banner.imageUrl.isEmpty
            ? const Center(child: Icon(Icons.image_outlined))
            : YcNetworkImage(
                banner.imageUrl,
                semanticLabel: banner.title,
                cacheWidth: _cacheWidth,
                error: const Center(
                  child: Icon(Icons.image_not_supported_outlined),
                ),
              ),
      );

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final count = widget.banners.length;
    final fadeFrom = _fadeFrom;
    // Its own repaint boundary: rotating ads never repaint the page around.
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: _bannerAspectRatio,
        // One rounded clip wraps the WHOLE carousel viewport rather than each
        // page. Clipping per page left the viewport's own square edge exposed
        // while two ads were mid-slide, so the incoming image briefly showed
        // sharp corners. Here every frame (outgoing and incoming ads, loading
        // and error placeholders, the page dots) is cut to the same rounded
        // rectangle.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Each page is exactly this wide: its decode width, shared
                // with precaching so the precached image is the one painted.
                _cacheWidth =
                    YcNetworkImage.decodeWidth(context, constraints.maxWidth);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    NotificationListener<UserScrollNotification>(
                      // A manual swipe takes over at once: drop the fade
                      // overlay so it never covers the page being dragged.
                      onNotification: (notification) {
                        if (notification.direction != ScrollDirection.idle &&
                            _fadeFrom != null) {
                          setState(_cancelFade);
                        }
                        return false;
                      },
                      child: PageView.builder(
                        controller: _controller,
                        // The ClipRRect above is the single clip; skip
                        // PageView's own.
                        clipBehavior: Clip.none,
                        itemCount: count,
                        onPageChanged: (index) => setState(() => _page = index),
                        itemBuilder: (context, index) {
                          final banner = widget.banners[index];
                          final externalUrl =
                              _validExternalBannerUrl(banner.targetUrl);
                          return GestureDetector(
                            // A null onTap makes this a no-op tap target
                            // without affecting PageView's own horizontal
                            // swipe gesture — swipe and this tap detector
                            // coexist normally in Flutter's gesture arena, no
                            // special handling needed.
                            onTap: externalUrl == null
                                ? null
                                : () => _openBannerUrl(externalUrl),
                            child: _bannerPicture(banner, fill),
                          );
                        },
                      ),
                    ),
                    // The outgoing banner, fading out over the new one. It is
                    // painted from the image cache (already loaded), is not
                    // interactive and is hidden from screen readers.
                    if (fadeFrom != null && fadeFrom < count)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: FadeTransition(
                              key: const Key('banner-crossfade'),
                              opacity: _fadeOpacity,
                              child: _bannerPicture(
                                widget.banners[fadeFrom],
                                fill,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (count > 1)
                      PositionedDirectional(
                        start: 0,
                        end: 0,
                        bottom: YcSpace.xs,
                        child: Center(
                          child: DecoratedBox(
                            // A soft scrim keeps the dots readable on any ad.
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .28),
                              borderRadius:
                                  BorderRadius.circular(YcRadius.pill),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 4,
                              ),
                              child: YcPageDots(
                                count: count,
                                index: _page.clamp(0, count - 1),
                                activeColor: Colors.white,
                                inactiveColor:
                                    Colors.white.withValues(alpha: .5),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Points balance card: the premium [YcBalanceHero] in its full size.
///
/// The hero figure is the customer's real total balance. Beneath it, a
/// compact breakdown always shows the real available points and the real
/// pending (processing) points — including a pending figure of 0. All numbers
/// come straight from [PointsSummary]; this widget does no arithmetic,
/// rounding or loading logic of its own.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.points});

  final PointsSummary? points;

  @override
  Widget build(BuildContext context) {
    final summary = points;
    return YcBalanceHero(
      label: 'رصيد النقاط',
      value: summary?.pointsBalance,
      unit: 'نقطة',
      trailing: const _BalanceLogo(),
      stats: summary == null
          ? const []
          : [
              YcHeroStat(
                icon: Icons.check_circle_outline_rounded,
                label: 'المتاح',
                value: summary.availablePoints,
              ),
              YcHeroStat(
                icon: Icons.schedule_rounded,
                label: 'قيد المعالجة',
                value: summary.heldPoints,
              ),
            ],
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
        decoration: YcSurface.of(context).decoration(radius: 20),
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
                      final logo = YcLogoPlate(
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
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // The exact wording is always shown in full: on
                          // narrow screens or large text the line scales
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

/// Plain secondary "exclusive partner" line under the store name: muted
/// blue-grey text only, no pill, border or icon.
class _StoreCardPartnerBadge extends StatelessWidget {
  const _StoreCardPartnerBadge();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      'شريك حصري لدى يلا كاش',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: dark ? const Color(0xFF9DB2C0) : const Color(0xFF5F7A8A),
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
