/// Yalla Cash customer design tokens.
///
/// The single source for spacing, radii, surfaces, typography roles and
/// motion in the customer app. Brand colours come from the shared
/// [YallaColors]; nothing here redefines them. These tokens are customer-only:
/// the admin and merchant apps keep using the shared core theme unchanged.
library;

import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

/// Spacing scale on a 4pt grid. Prefer these over ad-hoc numbers.
abstract final class YcSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  /// Horizontal page gutter used by the existing customer screens.
  static const double gutter = 18;
}

/// Corner radii. Cards use [lg]; nested tiles step down one size.
abstract final class YcRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius circular(double radius) => BorderRadius.circular(radius);
}

/// Motion tokens. Keep animations short and calm; every duration collapses to
/// zero when the system asks for reduced motion (see [resolve]).
abstract final class YcMotion {
  /// Taps, toggles, small state changes.
  static const Duration fast = Duration(milliseconds: 150);

  /// Most component transitions (expand, fade, swap).
  static const Duration medium = Duration(milliseconds: 250);

  /// Content entrance (fade and rise).
  static const Duration slow = Duration(milliseconds: 420);

  /// Page push (Android Fade Forwards). The SDK default is 450ms.
  static const Duration pageEnter = Duration(milliseconds: 400);

  /// Page pop: slightly quicker so going back feels responsive.
  static const Duration pageExit = Duration(milliseconds: 350);

  /// Default curve for elements entering or settling.
  static const Curve standard = Curves.easeOutCubic;

  /// Curve for larger, expressive moves (e.g. shared-element growth).
  static const Curve emphasized = Curves.easeInOutCubicEmphasized;

  /// Curve for elements leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Whether the user asked the system to reduce or remove animations.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or [Duration.zero] under reduced motion.
  static Duration resolve(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Typography roles mapped onto the theme's [TextTheme] (Almarai). Use these
/// roles instead of hand-picked sizes so hierarchy stays consistent:
///
/// * [hero]     – the balance figure and other single key numbers.
/// * [title]    – page and details-page titles.
/// * [section]  – section headings ("المحلات الحصرية بمدينتك").
/// * [item]     – primary text in cards and list rows.
/// * [body]     – paragraphs and descriptions.
/// * [meta]     – secondary lines: category, dates, statuses.
///
/// All roles scale with the user's text-size setting.
abstract final class YcType {
  static TextStyle? hero(BuildContext context) => Theme.of(context)
      .textTheme
      .headlineMedium
      ?.copyWith(fontWeight: FontWeight.w900, height: 1.15);

  static TextStyle? title(BuildContext context) => Theme.of(context)
      .textTheme
      .headlineSmall
      ?.copyWith(fontWeight: FontWeight.w900, height: 1.25);

  static TextStyle? section(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium
      ?.copyWith(fontWeight: FontWeight.w900);

  static TextStyle? item(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium
      ?.copyWith(fontWeight: FontWeight.w800, height: 1.3);

  static TextStyle? body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6);

  static TextStyle? meta(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.3,
    );
  }
}

/// Surface tokens (card colour, hairline border, shadows) for the active
/// brightness. Registered on the customer theme, read with [YcSurface.of].
@immutable
class YcSurface extends ThemeExtension<YcSurface> {
  const YcSurface({
    required this.card,
    required this.hairline,
    required this.shadow,
    required this.raisedShadow,
  });

  /// Matches the shared core theme's card colours exactly.
  factory YcSurface.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return YcSurface(
      card: dark ? const Color(0xFF123040) : Colors.white,
      hairline: dark
          ? Colors.white.withValues(alpha: .08)
          : YallaColors.navy.withValues(alpha: .07),
      // Light mode: one soft shadow. Dark mode: shadows barely read, so
      // depth comes from the hairline border instead.
      shadow: dark
          ? const []
          : [
              BoxShadow(
                color: YallaColors.navy.withValues(alpha: .05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
      raisedShadow: [
        BoxShadow(
          color: (dark ? Colors.black : YallaColors.navy)
              .withValues(alpha: dark ? .38 : .12),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// Card / sheet background.
  final Color card;

  /// 1px border that separates a surface from the page.
  final Color hairline;

  /// Resting elevation for cards.
  final List<BoxShadow> shadow;

  /// Elevation for floating or emphasised elements (logos on headers, sheets).
  final List<BoxShadow> raisedShadow;

  /// Surface tokens for [context], falling back to the theme's brightness if
  /// the extension is missing (e.g. a widget test without the customer theme).
  static YcSurface of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<YcSurface>() ??
        YcSurface.forBrightness(theme.brightness);
  }

  /// Standard card decoration built from these tokens.
  BoxDecoration decoration(
          {double radius = YcRadius.lg, bool raised = false}) =>
      BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: hairline),
        boxShadow: raised ? raisedShadow : shadow,
      );

  @override
  YcSurface copyWith({
    Color? card,
    Color? hairline,
    List<BoxShadow>? shadow,
    List<BoxShadow>? raisedShadow,
  }) =>
      YcSurface(
        card: card ?? this.card,
        hairline: hairline ?? this.hairline,
        shadow: shadow ?? this.shadow,
        raisedShadow: raisedShadow ?? this.raisedShadow,
      );

  @override
  YcSurface lerp(covariant YcSurface? other, double t) {
    if (other == null) return this;
    return YcSurface(
      card: Color.lerp(card, other.card, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? const [],
      raisedShadow:
          BoxShadow.lerpList(raisedShadow, other.raisedShadow, t) ?? const [],
    );
  }
}
