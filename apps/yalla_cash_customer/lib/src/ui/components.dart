/// Yalla Cash customer UI components.
///
/// Small, presentation-only building blocks on top of the customer design
/// tokens ([YcSpace], [YcRadius], [YcSurface], [YcType], [YcMotion]). They hold
/// no business logic: callers pass in text, tones and callbacks. All of them
/// are RTL-aware (directional padding and alignment), follow the active light
/// or dark theme, and scale with the user's text size.
library;

import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

// ---------------------------------------------------------------------------
// Tones
// ---------------------------------------------------------------------------

/// Semantic colour role for chips and icon badges.
enum YcTone { neutral, brand, success, warning, danger }

/// Foreground and tinted background for a [YcTone] in the active theme.
///
/// Text foregrounds are chosen to keep at least 4.5:1 contrast against their
/// tinted background on the card surface, in both light and dark mode.
@immutable
class YcToneColors {
  const YcToneColors({required this.foreground, required this.background});

  factory YcToneColors.of(BuildContext context, YcTone tone) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final Color foreground = switch (tone) {
      YcTone.neutral => scheme.onSurfaceVariant,
      YcTone.brand => dark ? scheme.primary : const Color(0xFF086892),
      YcTone.success =>
        dark ? const Color(0xFF6FD3A6) : const Color(0xFF14704B),
      YcTone.warning => dark ? YallaColors.gold : const Color(0xFF8A5A00),
      YcTone.danger => dark ? const Color(0xFFF59C95) : const Color(0xFFA8302C),
    };
    final Color base = switch (tone) {
      YcTone.neutral => scheme.onSurfaceVariant,
      YcTone.brand => scheme.primary,
      YcTone.success => YallaColors.success,
      YcTone.warning => YallaColors.gold,
      YcTone.danger => YallaColors.danger,
    };
    return YcToneColors(
      foreground: foreground,
      background: base.withValues(alpha: dark ? .18 : .12),
    );
  }

  final Color foreground;
  final Color background;
}

// ---------------------------------------------------------------------------
// YcCard
// ---------------------------------------------------------------------------

/// Minimal card surface: theme card colour, hairline border, one soft shadow
/// (light mode only, from [YcSurface]). Tappable when [onTap] is set; a
/// tappable card is announced as a single button.
class YcCard extends StatelessWidget {
  const YcCard({
    required this.child,
    super.key,
    this.onTap,
    this.padding = const EdgeInsets.all(YcSpace.md),
    this.radius = YcRadius.lg,
    this.raised = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Use the stronger [YcSurface.raisedShadow] (floating elements only).
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final surface = YcSurface.of(context);
    final borderRadius = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    final tap = onTap;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: raised ? surface.raisedShadow : surface.shadow,
      ),
      child: Material(
        color: surface.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(color: surface.hairline),
        ),
        child: tap == null
            ? content
            : MergeSemantics(
                child: Semantics(
                  button: true,
                  child: _YcInk(onTap: tap, child: content),
                ),
              ),
      ),
    );
  }
}

/// InkWell with the restrained brand-tinted ripple used across components.
class _YcInk extends StatelessWidget {
  const _YcInk({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      splashColor: primary.withValues(alpha: .08),
      highlightColor: primary.withValues(alpha: .04),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// YcSectionHeader
// ---------------------------------------------------------------------------

/// Section title with an optional subtitle and an optional text action at the
/// end (left in RTL). The title is exposed to screen readers as a header.
class YcSectionHeader extends StatelessWidget {
  const YcSectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;

  /// Shown only when [onAction] is also set.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final label = actionLabel;
    final action = onAction;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: YcType.section(context)),
              ),
              if (sub != null && sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub, style: YcType.meta(context)),
              ],
            ],
          ),
        ),
        if (label != null && action != null) ...[
          const SizedBox(width: YcSpace.xs),
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: YcSpace.sm),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            child: Text(label),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// YcEmptyState
// ---------------------------------------------------------------------------

/// Quiet, centred empty state: optional icon, a title, an optional
/// description and an optional outlined action.
class YcEmptyState extends StatelessWidget {
  const YcEmptyState({
    required this.title,
    super.key,
    this.icon,
    this.description,
    this.actionLabel,
    this.onAction,
    this.tone = YcTone.neutral,
  });

  final String title;
  final IconData? icon;
  final String? description;

  /// Shown only when [onAction] is also set.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Tone of the icon badge.
  final YcTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconData = icon;
    final desc = description;
    final label = actionLabel;
    final action = onAction;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: YcSpace.xl,
        vertical: YcSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconData != null) ...[
            YcIconBadge(iconData, tone: tone, size: 56, circle: true),
            const SizedBox(height: YcSpace.md),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: YcType.meta(context)?.copyWith(height: 1.5),
            ),
          ],
          if (label != null && action != null) ...[
            const SizedBox(height: YcSpace.md),
            OutlinedButton(onPressed: action, child: Text(label)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcListRow
// ---------------------------------------------------------------------------

/// List row: leading visual, title, optional subtitle and trailing widget.
///
/// Pass [leading] for a custom visual, or [icon] (+ [iconTone]) for a
/// standard [YcIconBadge]. When [onTap] is set the row is announced as one
/// button. Rows keep a 56px minimum height for comfortable touch targets and
/// grow with text scaling. Place rows inside a [YcCard] (or any [Material])
/// so the ripple has a surface.
class YcListRow extends StatelessWidget {
  const YcListRow({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.icon,
    this.iconTone = YcTone.brand,
    this.trailing,
    this.onTap,
    this.titleMaxLines = 1,
    this.titleColor,
    this.padding = const EdgeInsetsDirectional.symmetric(
      horizontal: YcSpace.md,
      vertical: YcSpace.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final IconData? icon;
  final YcTone iconTone;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int titleMaxLines;

  /// Overrides the title colour (e.g. a destructive action).
  final Color? titleColor;
  final EdgeInsetsGeometry padding;

  static const double _maxTrailingFraction = 0.45;

  @override
  Widget build(BuildContext context) {
    final iconData = icon;
    final lead = leading ??
        (iconData == null ? null : YcIconBadge(iconData, tone: iconTone));
    final sub = subtitle;
    final trail = trailing;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: padding,
        // The trailing widget may take at most [_maxTrailingFraction] of the
        // row, so a long status label shrinks (chips ellipsize) instead of
        // pushing the title off-screen on narrow phones or large text.
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: YcSpace.sm)],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                            color: titleColor,
                          ),
                    ),
                    if (sub != null && sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: YcType.meta(context),
                      ),
                    ],
                  ],
                ),
              ),
              if (trail != null) ...[
                const SizedBox(width: YcSpace.sm),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * _maxTrailingFraction,
                  ),
                  child: trail,
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final tap = onTap;
    if (tap == null) return row;
    return MergeSemantics(
      child: Semantics(button: true, child: _YcInk(onTap: tap, child: row)),
    );
  }
}

// ---------------------------------------------------------------------------
// YcStatusChip
// ---------------------------------------------------------------------------

/// Compact status pill. Colour is never the only signal: each preset also
/// carries an icon, and the label is always text.
///
/// The label is supplied by the caller so status wording stays with the
/// screen that owns the business meaning.
class YcStatusChip extends StatelessWidget {
  const YcStatusChip({
    required this.label,
    super.key,
    this.tone = YcTone.neutral,
    this.icon,
  });

  /// Waiting for review (warning tone, hourglass).
  const YcStatusChip.pending(this.label, {super.key})
      : tone = YcTone.warning,
        icon = Icons.hourglass_top_rounded;

  /// Done successfully (success tone, check).
  const YcStatusChip.completed(this.label, {super.key})
      : tone = YcTone.success,
        icon = Icons.check_circle_outline_rounded;

  /// Declined (danger tone, cross).
  const YcStatusChip.rejected(this.label, {super.key})
      : tone = YcTone.danger,
        icon = Icons.cancel_outlined;

  final String label;
  final YcTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = YcToneColors.of(context, tone);
    final iconData = icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(YcRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconData != null) ...[
              Icon(iconData, size: 14, color: colors.foreground),
              const SizedBox(width: YcSpace.xxs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.foreground,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcIconBadge
// ---------------------------------------------------------------------------

/// Icon on a soft tinted tile (rounded square, or a circle with [circle]).
/// Decorative by default, so screen readers skip it; pass [semanticLabel]
/// when the icon carries meaning on its own.
class YcIconBadge extends StatelessWidget {
  const YcIconBadge(
    this.icon, {
    super.key,
    this.tone = YcTone.brand,
    this.size = 40,
    this.circle = false,
    this.semanticLabel,
  });

  final IconData icon;
  final YcTone tone;
  final double size;
  final bool circle;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = YcToneColors.of(context, tone);
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.background,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: colors.foreground),
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: badge)
        : Semantics(
            label: label, image: true, child: ExcludeSemantics(child: badge));
  }
}

// ---------------------------------------------------------------------------
// YcFadeSlideIn
// ---------------------------------------------------------------------------

/// One-shot fade and rise for content entering the screen.
///
/// Uses an implicit [TweenAnimationBuilder] (no controller); [child] is built
/// once and reused on every frame. Rebuilding with the same settings does not
/// replay the animation. [delay] staggers items without timers by holding the
/// start of a longer animation. Under reduced motion the child is returned
/// as-is, with no animation at all.
class YcFadeSlideIn extends StatelessWidget {
  const YcFadeSlideIn({
    required this.child,
    super.key,
    this.duration = YcMotion.slow,
    this.delay = Duration.zero,
    this.offset = 12,
    this.curve = YcMotion.standard,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;

  /// Vertical distance in logical pixels the content rises from.
  final double offset;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    if (YcMotion.reduced(context)) return child;
    final total = delay + duration;
    final start = total == Duration.zero
        ? 0.0
        : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: curve),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * offset),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// YcProgressBar
// ---------------------------------------------------------------------------

/// Slim, rounded progress bar. Draws no numbers or percentages; the value is
/// exposed to screen readers only.
///
/// It fills from the start edge (right in RTL). Changes in [value] animate
/// with an implicit tween (no controller); the first build shows the value
/// directly, so a lazily rebuilt list never replays a fill. Brand blue while
/// in progress, success green when complete. Static under reduced motion.
class YcProgressBar extends StatelessWidget {
  const YcProgressBar({
    required this.value,
    super.key,
    this.height = 6,
    this.semanticLabel,
  });

  /// Progress from 0 to 1. Values outside that range are clamped.
  final double value;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final track = scheme.primary.withValues(alpha: dark ? .20 : .12);
    Widget bar(double t) => ClipRRect(
          borderRadius: BorderRadius.circular(YcRadius.pill),
          child: SizedBox(
            height: height,
            child: ColoredBox(
              color: track,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: t,
                  heightFactor: 1,
                  child: ColoredBox(
                    color: t >= 1 ? YallaColors.success : scheme.primary,
                  ),
                ),
              ),
            ),
          ),
        );
    return Semantics(
      label: semanticLabel,
      value: '${(target * 100).round()}%',
      child: ExcludeSemantics(
        child: YcMotion.reduced(context)
            ? bar(target)
            : TweenAnimationBuilder<double>(
                // No `begin`: starts at the current value, animates changes.
                tween: Tween<double>(end: target),
                duration: YcMotion.slow,
                curve: YcMotion.standard,
                builder: (context, t, _) => bar(t),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YcRevealOnFirstShow
// ---------------------------------------------------------------------------

/// Fades and lifts [child] in the first time [active] becomes true, then
/// never again. Built for tab pages kept alive in an [IndexedStack]: the
/// page animates on its first visit only, never on tab return or rebuilds,
/// and the child is never remounted, so its state is untouched. Shows the
/// child directly under reduced motion.
class YcRevealOnFirstShow extends StatefulWidget {
  const YcRevealOnFirstShow({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  State<YcRevealOnFirstShow> createState() => _YcRevealOnFirstShowState();
}

class _YcRevealOnFirstShowState extends State<YcRevealOnFirstShow> {
  late bool _revealed = widget.active;

  @override
  void didUpdateWidget(covariant YcRevealOnFirstShow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) _revealed = true;
  }

  @override
  Widget build(BuildContext context) {
    // Same widget shape in every state, so the child is never remounted.
    final reduced = YcMotion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _revealed || reduced ? 1 : 0),
      duration: reduced ? Duration.zero : YcMotion.slow,
      curve: YcMotion.standard,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: widget.child,
    );
  }
}

// ---------------------------------------------------------------------------
// YcSkeleton
// ---------------------------------------------------------------------------

/// Static loading placeholder: soft rounded bars inside a [YcCard]. No
/// perpetual animation, so it is calm and cheap. Announced once as loading.
class YcSkeleton extends StatelessWidget {
  const YcSkeleton({super.key, this.rows = 3, this.label = 'جارٍ التحميل'});

  final int rows;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill =
        theme.colorScheme.onSurface.withValues(alpha: dark ? .10 : .07);
    Widget block(double w, double h, {bool circle = false}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: fill,
            shape: circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: circle ? null : BorderRadius.circular(6),
          ),
        );
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: YcSpace.xs),
                child: YcCard(
                  child: Row(
                    children: [
                      block(40, 40, circle: true),
                      const SizedBox(width: YcSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FractionallySizedBox(
                              widthFactor: .6,
                              child: block(double.infinity, 12),
                            ),
                            const SizedBox(height: YcSpace.xs),
                            FractionallySizedBox(
                              widthFactor: .4,
                              child: block(double.infinity, 10),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: YcSpace.sm),
                      block(48, 14),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
