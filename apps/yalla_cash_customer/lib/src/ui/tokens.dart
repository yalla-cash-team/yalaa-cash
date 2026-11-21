/// Yalla Cash customer design tokens.
///
/// The single source for spacing, radii, surfaces, typography roles and
/// motion in the customer app. Brand colours come from the shared
/// [YallaColors]; nothing here redefines them. These tokens are customer-only:
/// the admin and merchant apps keep using the shared core theme unchanged.
library;

import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';

/// The customer font family (declared in the customer pubspec only).
const String customerFontFamily = 'Almarai';

/// Page background: a cool off-white, or a deep neutral navy in dark mode.
Color customerPageColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFF08141C)
        : const Color(0xFFF5F8FA);

/// Card / sheet surface.
Color customerCardColor(Brightness brightness) =>
    brightness == Brightness.dark ? const Color(0xFF0F2230) : Colors.white;

/// Raised surface in dark mode (inputs, nested panels).
Color customerRaisedColor(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFF142C3C)
        : YallaColors.surfaceAlt;

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

/// Typography roles mapped onto the theme's [TextTheme] (the customer's
/// complete Almarai family: Light 300, Regular 400, Bold 700, ExtraBold 800).
/// Use these roles instead of hand-picked sizes so hierarchy stays consistent:
///
/// * [hero]     – the balance figure and other single key numbers (w800).
/// * [title]    – page and details-page titles (w700).
/// * [section]  – section headings ("المحلات الحصرية بمدينتك") (w700).
/// * [item]     – primary text in cards and list rows (w700).
/// * [body]     – paragraphs and descriptions (w400, generous Arabic leading).
/// * [meta]     – secondary lines: category, dates, statuses (w400, muted).
/// * [amount]   – figures in lists and summaries (w800, tabular digits).
///
/// Weights stay on the four shipped faces so nothing is synthesised. All roles
/// scale with the user's text-size setting.
abstract final class YcType {
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static TextStyle? hero(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.15,
            fontFeatures: tabular,
          );

  static TextStyle? title(BuildContext context) => Theme.of(context)
      .textTheme
      .headlineSmall
      ?.copyWith(fontWeight: FontWeight.w700, height: 1.3);

  static TextStyle? section(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium
      ?.copyWith(fontWeight: FontWeight.w700, height: 1.35);

  static TextStyle? item(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium
      ?.copyWith(fontWeight: FontWeight.w700, height: 1.3);

  static TextStyle? body(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium
      ?.copyWith(fontWeight: FontWeight.w400, height: 1.65);

  static TextStyle? meta(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w400,
      height: 1.3,
    );
  }

  static TextStyle? amount(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontFeatures: tabular,
          );
}

/// Customer brand palette for the active brightness: navy for hierarchy and
/// hero surfaces, blue for actions, gold reserved for points, rewards and
/// discounts. Registered on the customer theme, read with [YcColors.of].
///
/// Built only from the shared [YallaColors] plus customer-only neutrals, so
/// the admin and merchant apps are unaffected. Every text colour here keeps
/// at least 4.5:1 contrast on the surface it is meant for.
@immutable
class YcColors extends ThemeExtension<YcColors> {
  const YcColors({
    required this.ink,
    required this.inkMuted,
    required this.brand,
    required this.brandBright,
    required this.brandTint,
    required this.heroStart,
    required this.heroEnd,
    required this.onHero,
    required this.onHeroMuted,
    required this.heroPanel,
    required this.gold,
    required this.goldInk,
    required this.goldTint,
  });

  factory YcColors.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return YcColors(
      ink: dark ? const Color(0xFFEAF2F7) : YallaColors.navy,
      inkMuted: dark ? const Color(0xFF9DB2C0) : const Color(0xFF4E6878),
      brand: dark ? const Color(0xFF3FC1F0) : YallaColors.primaryStrong,
      brandBright: YallaColors.primary,
      brandTint: dark
          ? YallaColors.primary.withValues(alpha: .14)
          : YallaColors.surfaceAlt,
      heroStart: dark ? const Color(0xFF0A1E2B) : YallaColors.navy,
      heroEnd: dark ? const Color(0xFF0B5F86) : YallaColors.primaryStrong,
      onHero: Colors.white,
      // Solid white: the brand-blue end of the hero gradient leaves no
      // contrast headroom (white is 4.54:1 there), so secondary hero text is
      // set apart by weight and size, never by transparency.
      onHeroMuted: Colors.white,
      heroPanel: Colors.white.withValues(alpha: .10),
      gold: YallaColors.gold,
      goldInk: dark ? YallaColors.gold : const Color(0xFF8A5A00),
      goldTint: YallaColors.gold.withValues(alpha: dark ? .18 : .16),
    );
  }

  /// Primary text.
  final Color ink;

  /// Secondary text (meta lines, captions).
  final Color inkMuted;

  /// Primary actions and links.
  final Color brand;

  /// The bright brand sky blue, for small accents only.
  final Color brandBright;

  /// Soft brand-tinted fill (panels, selected states).
  final Color brandTint;

  /// Hero gradient (balance card, QR backdrop, store header): deep navy into
  /// the brand blue. White text keeps at least 4.5:1 on both stops.
  final Color heroStart;
  final Color heroEnd;

  /// Text and icons on the hero gradient.
  final Color onHero;
  final Color onHeroMuted;

  /// Inset panel on the hero gradient.
  final Color heroPanel;

  /// Gold: points, rewards and discounts only.
  final Color gold;

  /// Text on a [goldTint] fill.
  final Color goldInk;
  final Color goldTint;

  /// The hero gradient, lighter at the start corner (top-end in RTL).
  LinearGradient get heroGradient => LinearGradient(
        begin: AlignmentDirectional.bottomStart,
        end: AlignmentDirectional.topEnd,
        colors: [heroStart, heroEnd],
      );

  /// Palette for [context], falling back to the theme's brightness if the
  /// extension is missing (e.g. a widget test without the customer theme).
  static YcColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<YcColors>() ??
        YcColors.forBrightness(theme.brightness);
  }

  @override
  YcColors copyWith({
    Color? ink,
    Color? inkMuted,
    Color? brand,
    Color? brandBright,
    Color? brandTint,
    Color? heroStart,
    Color? heroEnd,
    Color? onHero,
    Color? onHeroMuted,
    Color? heroPanel,
    Color? gold,
    Color? goldInk,
    Color? goldTint,
  }) =>
      YcColors(
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        brand: brand ?? this.brand,
        brandBright: brandBright ?? this.brandBright,
        brandTint: brandTint ?? this.brandTint,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
        onHero: onHero ?? this.onHero,
        onHeroMuted: onHeroMuted ?? this.onHeroMuted,
        heroPanel: heroPanel ?? this.heroPanel,
        gold: gold ?? this.gold,
        goldInk: goldInk ?? this.goldInk,
        goldTint: goldTint ?? this.goldTint,
      );

  @override
  YcColors lerp(covariant YcColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return YcColors(
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      brand: l(brand, other.brand),
      brandBright: l(brandBright, other.brandBright),
      brandTint: l(brandTint, other.brandTint),
      heroStart: l(heroStart, other.heroStart),
      heroEnd: l(heroEnd, other.heroEnd),
      onHero: l(onHero, other.onHero),
      onHeroMuted: l(onHeroMuted, other.onHeroMuted),
      heroPanel: l(heroPanel, other.heroPanel),
      gold: l(gold, other.gold),
      goldInk: l(goldInk, other.goldInk),
      goldTint: l(goldTint, other.goldTint),
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

  /// Matches the customer theme's card colours ([customerCardColor]).
  factory YcSurface.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return YcSurface(
      card: customerCardColor(brightness),
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
