part of '../../customer_app.dart';

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
          // Premium presentation: the white QR plate on the deep navy → blue
          // hero surface. The plate, payload and QR sizing are unchanged.
          _QrHeroCard(
            child: Column(
              children: [
                _QrPlate(token: token),
                const SizedBox(height: YcSpace.lg),
                Text(
                  widget.customer.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: YcType.item(context)?.copyWith(
                    color: YcColors.of(context).onHero,
                  ),
                ),
                const SizedBox(height: 2),
                // A short reference instead of the full technical id. Merchants
                // identify customers only by scanning the QR token.
                Text(
                  _shortCustomerRef(widget.customer.id),
                  textDirection: TextDirection.ltr,
                  style: YcType.meta(context)?.copyWith(
                    color: YcColors.of(context).onHeroMuted,
                  ),
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

/// The QR page's hero surface: the premium navy → brand blue gradient with a
/// quiet highlight, so the white QR plate reads as the focal point.
class _QrHeroCard extends StatelessWidget {
  const _QrHeroCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = YcColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YcRadius.xl),
        gradient: colors.heroGradient,
        border: dark
            ? Border.all(color: Colors.white.withValues(alpha: .10))
            : null,
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: YallaColors.navy.withValues(alpha: .22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          YcSpace.lg,
          YcSpace.xl,
          YcSpace.lg,
          YcSpace.lg,
        ),
        child: child,
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
                    fontWeight: FontWeight.w700,
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
    // Shown on the hero surface: white text on a soft white pill.
    final foreground = YcColors.of(context).onHero;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(YcRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YcSpace.sm,
          vertical: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 16, color: foreground),
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
                    color: foreground,
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
