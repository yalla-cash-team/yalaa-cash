/// Yalla Cash customer premium components.
///
/// Presentation-only building blocks for the premium customer UI, built on
/// the design tokens ([YcSpace], [YcRadius], [YcType], [YcColors],
/// [YcSurface], [YcMotion]) and the base components in `components.dart`.
/// None of them computes, rounds or fetches anything: callers pass in the
/// real values and callbacks. All are RTL-aware, follow light and dark mode,
/// scale with the user's text size and honour reduced motion.
library;

import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/components.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

// ---------------------------------------------------------------------------
// YcAmount
// ---------------------------------------------------------------------------

/// Unicode left-to-right isolate / pop directional isolate.
const String _lri = '\u2066';
const String _pdi = '\u2069';

/// Size steps for [YcAmount].
enum YcAmountSize { small, medium, large }

/// A figure with an optional unit ("نقطة", "ل.س"), formatted with the shared
/// [formatNumber] and shown with tabular digits.
///
/// The value is displayed exactly as given: no arithmetic, rounding or
/// conversion happens here. A [signed] figure ("+120") is wrapped in a
/// left-to-right isolate so the sign stays in front of the digits inside
/// right-to-left text (plain RTL text would show "120+"). Unsigned figures
/// need no isolation and are left as plain text.
class YcAmount extends StatelessWidget {
  const YcAmount(
    this.value, {
    super.key,
    this.unit,
    this.signed = false,
    this.size = YcAmountSize.small,
    this.color,
    this.unitColor,
    this.scaleDown = false,
    this.textAlign,
  });

  final int value;

  /// Unit after the figure, or null for the bare figure.
  final String? unit;

  /// Prefix the figure with "+" (credits).
  final bool signed;
  final YcAmountSize size;

  /// Figure colour (defaults to the theme's text colour).
  final Color? color;

  /// Unit colour (defaults to [color]).
  final Color? unitColor;

  /// Scale down instead of ellipsizing when space is short.
  final bool scaleDown;
  final TextAlign? textAlign;

  /// The figure as displayed: "+1,200" isolated when [signed].
  static String figure(int value, {bool signed = false}) {
    final number = formatNumber(value);
    return signed ? '$_lri+$number$_pdi' : number;
  }

  /// The complete display text (figure and unit), e.g. "1,200 نقطة".
  static String format(int value, {String? unit, bool signed = false}) {
    final text = figure(value, signed: signed);
    return unit == null ? text : '$text $unit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = switch (size) {
      YcAmountSize.small => theme.textTheme.titleSmall,
      YcAmountSize.medium => theme.textTheme.titleMedium,
      YcAmountSize.large => theme.textTheme.headlineSmall,
    };
    final style = base?.copyWith(
      color: color,
      fontWeight: FontWeight.w800,
      height: 1.25,
      fontFeatures: YcType.tabular,
    );
    final unitText = unit;
    final Widget text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: figure(value, signed: signed)),
          if (unitText != null)
            TextSpan(
              text: ' $unitText',
              style: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: (style?.fontSize ?? 14) * .78,
                color: unitColor,
              ),
            ),
        ],
      ),
      style: style,
      maxLines: 1,
      softWrap: false,
      overflow: scaleDown ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    if (!scaleDown) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: text,
    );
  }
}

// ---------------------------------------------------------------------------
// YcBalanceHero
// ---------------------------------------------------------------------------

/// One labelled figure in the [YcBalanceHero] breakdown panel.
@immutable
class YcHeroStat {
  const YcHeroStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;
}

/// Premium balance card: a deep navy → brand blue gradient with one quiet
/// highlight, a gold accent, the key figure and an optional breakdown panel.
///
/// Shows the [value] it is given and nothing else: while [value] is null it
/// shows an indeterminate bar (never a false zero), and when [failed] it shows
/// a retry instead. Height follows content and never jumps between states
/// beyond the figure line.
class YcBalanceHero extends StatelessWidget {
  const YcBalanceHero({
    required this.label,
    required this.value,
    super.key,
    this.unit,
    this.stats = const [],
    this.trailing,
    this.compact = false,
    this.failed = false,
    this.onRetry,
    this.inlineUnit = false,
  });

  /// Caption over the figure, e.g. "رصيد النقاط".
  final String label;

  /// The figure, or null while loading.
  final int? value;

  /// Unit shown beside the figure in a lighter weight.
  final String? unit;

  /// Breakdown under the figure (e.g. available / processing).
  final List<YcHeroStat> stats;

  /// Mark at the card's end corner (e.g. the official logo on a gold disc).
  final Widget? trailing;

  /// Smaller figure and padding for secondary pages.
  final bool compact;
  final bool failed;
  final VoidCallback? onRetry;

  /// Show figure and unit as one text ("600 نقطة", see [YcAmount.format]),
  /// the unit in a lighter, smaller weight.
  final bool inlineUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YcColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(compact ? YcRadius.lg : YcRadius.xl);
    final figureSize = compact ? 26.0 : 34.0;
    final v = value;
    final mark = trailing;

    final Widget figureLine;
    if (v != null && inlineUnit) {
      figureLine = YcAmount(
        v,
        unit: unit,
        size: YcAmountSize.large,
        color: colors.onHero,
        unitColor: colors.onHeroMuted,
        scaleDown: true,
      );
    } else if (v != null) {
      figureLine = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              formatNumber(v),
              maxLines: 1,
              style: YcType.hero(context)?.copyWith(
                color: colors.onHero,
                fontSize: figureSize,
                height: 1.1,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 6),
              Text(
                unit!,
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onHeroMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ],
        ),
      );
    } else if (failed) {
      figureLine = Row(
        children: [
          Flexible(
            child: Text(
              'تعذر تحميل الرصيد',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: colors.onHero),
              child: const Text('إعادة المحاولة'),
            ),
        ],
      );
    } else {
      // Loading: an indeterminate bar, never a false zero. The box matches
      // the figure's height so the card does not jump.
      figureLine = SizedBox(
        height: figureSize + 4,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 112,
            child: LinearProgressIndicator(
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: colors.onHero,
              backgroundColor: colors.onHero.withValues(alpha: .18),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
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
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // One soft highlight at the mark corner, away from the figures.
            PositionedDirectional(
              top: -70,
              end: -60,
              child: ExcludeSemantics(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .06),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                YcSpace.lg,
                compact ? YcSpace.sm : 14,
                YcSpace.lg,
                compact ? YcSpace.sm : YcSpace.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Subtle gold accent before the caption.
                      ExcludeSemantics(
                        child: Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: colors.gold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(width: YcSpace.xs),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onHeroMuted,
                          ),
                        ),
                      ),
                      if (mark != null) mark,
                    ],
                  ),
                  const SizedBox(height: 2),
                  figureLine,
                  if (v != null && stats.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _HeroStatsPanel(stats: stats),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The breakdown on a deeper inset panel, stats side by side with hairline
/// dividers. Small white text keeps at least 4.5:1 on the panel anywhere on
/// the gradient.
class _HeroStatsPanel extends StatelessWidget {
  const _HeroStatsPanel({required this.stats});

  final List<YcHeroStat> stats;

  /// Navy wash that deepens the gradient behind small text.
  static final Color panel = const Color(0xFF06141D).withValues(alpha: .35);

  @override
  Widget build(BuildContext context) {
    final colors = YcColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(YcRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YcSpace.md,
          vertical: YcSpace.xs,
        ),
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: YcSpace.sm),
                  color: colors.onHero.withValues(alpha: .22),
                ),
              Expanded(child: _HeroStatCell(stat: stats[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroStatCell extends StatelessWidget {
  const _HeroStatCell({required this.stat});

  final YcHeroStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YcColors.of(context);
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The full label always shows: it scales down rather than being
          // cut on narrow screens or at large text sizes.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(stat.icon, size: 13, color: colors.onHeroMuted),
                const SizedBox(width: 4),
                Text(
                  stat.label,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onHero,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatNumber(stat.value),
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onHero,
                fontWeight: FontWeight.w800,
                height: 1.2,
                fontFeatures: YcType.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcNetworkImage
// ---------------------------------------------------------------------------

/// Network image that decodes at the size it is shown (not the file's full
/// resolution), fades in once loaded (instant under reduced motion), and
/// shows quiet placeholder and error states instead of throwing layout.
///
/// The decode width comes from the incoming width constraint times the
/// device pixel ratio; with an unbounded width the image decodes at full size.
class YcNetworkImage extends StatelessWidget {
  const YcNetworkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.placeholder,
    this.error,
    this.semanticLabel,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = false,
    this.resize = true,
    this.cacheWidth,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Shown until the first frame arrives (defaults to nothing).
  final Widget? placeholder;

  /// Shown when the image fails to load (defaults to nothing).
  final Widget? error;
  final String? semanticLabel;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;

  /// Decode at the displayed size (the default). A resized image has its own
  /// image-cache key, so it is downloaded and decoded separately from the
  /// plain `NetworkImage(url)`. Pass false where the *same* image is already
  /// on screen as a plain `NetworkImage` and must be reused from the cache
  /// (e.g. a store logo flying from the Home card to the details page).
  final bool resize;

  /// Decode width in physical pixels, overriding the one measured from the
  /// layout. Lets a caller that precaches the image (see [provider]) use the
  /// very same width, so the precached image is found in the image cache.
  final int? cacheWidth;

  /// The provider [YcNetworkImage] uses for [url] at [cacheWidth] (the same
  /// one `Image.network(cacheWidth: ...)` builds). Precaching this provider
  /// makes the matching [YcNetworkImage] paint on its first frame.
  static ImageProvider provider(String url, {int? cacheWidth}) =>
      ResizeImage.resizeIfNeeded(cacheWidth, null, NetworkImage(url));

  /// Decode width in physical pixels for [logicalWidth], or null when the
  /// width is unknown.
  static int? decodeWidth(BuildContext context, double logicalWidth) {
    if (!logicalWidth.isFinite || logicalWidth <= 0) return null;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return (logicalWidth * dpr).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = YcMotion.reduced(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final given = width;
        final w =
            given != null && given.isFinite ? given : constraints.maxWidth;
        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          filterQuality: filterQuality,
          gaplessPlayback: gaplessPlayback,
          semanticLabel: semanticLabel,
          cacheWidth: cacheWidth ?? (resize ? decodeWidth(context, w) : null),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            if (frame == null) return placeholder ?? const SizedBox.shrink();
            if (reduced) return child;
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: YcMotion.medium,
              curve: YcMotion.standard,
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: child,
            );
          },
          errorBuilder: (context, _, __) => error ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// YcErrorState / YcInlineBanner
// ---------------------------------------------------------------------------

/// Full error state with a retry: the quiet [YcEmptyState] layout in the
/// danger tone, announced to screen readers as it appears.
class YcErrorState extends StatelessWidget {
  const YcErrorState({
    required this.title,
    super.key,
    this.description = 'تحقق من اتصالك ثم حاول مرة أخرى.',
    this.icon = Icons.cloud_off_rounded,
    this.onRetry,
    this.retryLabel = 'إعادة المحاولة',
  });

  final String title;
  final String? description;
  final IconData icon;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: YcEmptyState(
          icon: icon,
          tone: YcTone.danger,
          title: title,
          description: description,
          actionLabel: onRetry == null ? null : retryLabel,
          onAction: onRetry,
        ),
      );
}

/// Slim tinted message row: icon, text and an optional text action. For
/// inline information, warnings and "couldn't refresh" notes above content
/// that is still shown.
class YcInlineBanner extends StatelessWidget {
  const YcInlineBanner({
    required this.message,
    super.key,
    this.tone = YcTone.brand,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final YcTone tone;
  final IconData? icon;

  /// Shown only when [onAction] is also set.
  final String? actionLabel;
  final VoidCallback? onAction;

  IconData get _icon =>
      icon ??
      switch (tone) {
        YcTone.danger => Icons.error_outline_rounded,
        YcTone.warning => Icons.warning_amber_rounded,
        YcTone.success => Icons.check_circle_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final colors = YcToneColors.of(context, tone);
    final label = actionLabel;
    final action = onAction;
    return Semantics(
      liveRegion: tone == YcTone.danger,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(YcRadius.md),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            YcSpace.sm,
            YcSpace.xs,
            label != null && action != null ? YcSpace.xxs : YcSpace.sm,
            YcSpace.xs,
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final text = Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
            );
            final button = label == null || action == null
                ? null
                : TextButton(
                    onPressed: action,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.foreground,
                      padding:
                          const EdgeInsets.symmetric(horizontal: YcSpace.sm),
                    ),
                    child: Text(label, maxLines: 1),
                  );
            // Narrow screens or large text: the action moves under the
            // message instead of squeezing it.
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final stack = button != null && constraints.maxWidth / scale < 300;
            return Row(
              crossAxisAlignment:
                  stack ? CrossAxisAlignment.start : CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: stack ? 2 : 0),
                  child: ExcludeSemantics(
                    child: Icon(_icon, size: 20, color: colors.foreground),
                  ),
                ),
                const SizedBox(width: YcSpace.xs),
                Expanded(
                  child: stack
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            text,
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: button,
                            ),
                          ],
                        )
                      : text,
                ),
                if (!stack && button != null) button,
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcChip
// ---------------------------------------------------------------------------

/// Rounded label pill for categories, partner badges and discounts. Tinted
/// with a [YcTone]; colour is never the only signal (the label is always
/// text). The gold [YcChip.discount] is reserved for offers.
class YcChip extends StatelessWidget {
  const YcChip({
    required this.label,
    super.key,
    this.tone = YcTone.brand,
    this.icon,
    this.outlined = false,
    this.large = false,
    this.maxLines = 1,
  });

  /// Gold discount pill (offers only). The free-text label wraps (up to
  /// three lines) rather than being cut.
  const YcChip.discount(this.label, {super.key})
      : tone = YcTone.warning,
        icon = Icons.local_offer_rounded,
        outlined = true,
        large = true,
        maxLines = 3;

  final String label;
  final YcTone tone;
  final IconData? icon;

  /// Adds a soft border in the tone's colour.
  final bool outlined;

  /// Larger text and padding (headline pills).
  final bool large;

  /// Label lines before ellipsizing.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = YcToneColors.of(context, tone);
    final palette = YcColors.of(context);
    final gold = tone == YcTone.warning;
    final foreground = gold ? palette.goldInk : colors.foreground;
    final background = gold ? palette.goldTint : colors.background;
    final iconData = icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(YcRadius.pill),
        border: outlined
            ? Border.all(
                color:
                    (gold ? palette.gold : foreground).withValues(alpha: .45),
              )
            : null,
      ),
      child: Padding(
        padding: large
            ? const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6)
            : const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              ExcludeSemantics(
                child: Icon(iconData, size: large ? 16 : 14, color: foreground),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: (large
                        ? theme.textTheme.labelLarge
                        : theme.textTheme.labelMedium)
                    ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcPageDots
// ---------------------------------------------------------------------------

/// Page indicator: small dots with the current page drawn as a short pill.
/// The pill's growth animates (instant under reduced motion). Read by screen
/// readers as "n من total".
class YcPageDots extends StatelessWidget {
  const YcPageDots({
    required this.count,
    required this.index,
    super.key,
    this.activeColor,
    this.inactiveColor,
  });

  final int count;
  final int index;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final active = activeColor ?? scheme.primary;
    final inactive = inactiveColor ?? active.withValues(alpha: .30);
    final duration = YcMotion.resolve(context, YcMotion.medium);
    return Semantics(
      label: '${index + 1} من $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: duration,
                curve: YcMotion.standard,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == index ? active : inactive,
                  borderRadius: BorderRadius.circular(YcRadius.pill),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcSegmentedTabs
// ---------------------------------------------------------------------------

/// Calm segmented control: equal segments on a tinted track, the selected one
/// raised on the card surface. Each segment is a 48dp+ button announced as
/// selected or not; labels scale down rather than wrap.
class YcSegmentedTabs extends StatelessWidget {
  const YcSegmentedTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = YcSurface.of(context);
    final colors = YcColors.of(context);
    final duration = YcMotion.resolve(context, YcMotion.fast);
    final media = MediaQuery.of(context);
    // Short labels follow the text size up to 1.3x so all segments stay one
    // even size (each still scales down to fit on the narrowest phones).
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.3),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark
              ? Colors.white.withValues(alpha: .06)
              : YallaColors.navy.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(YcRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selectedIndex,
                    inMutuallyExclusiveGroup: true,
                    child: AnimatedContainer(
                      duration: duration,
                      curve: YcMotion.standard,
                      constraints: const BoxConstraints(minHeight: 48),
                      decoration: BoxDecoration(
                        color: i == selectedIndex
                            ? surface.card
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(YcRadius.sm),
                        boxShadow: i == selectedIndex && !dark
                            ? [
                                BoxShadow(
                                  color:
                                      YallaColors.navy.withValues(alpha: .08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(YcRadius.sm),
                          onTap: i == selectedIndex ? null : () => onChanged(i),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: YcSpace.xs,
                                vertical: YcSpace.xs,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labels[i],
                                  maxLines: 1,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: i == selectedIndex
                                        ? colors.ink
                                        : colors.inkMuted,
                                    fontWeight: i == selectedIndex
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
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
    );
  }
}
