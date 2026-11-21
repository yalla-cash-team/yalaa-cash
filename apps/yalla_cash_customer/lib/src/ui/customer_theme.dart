/// Customer-only theme overlay.
///
/// Builds on the shared [buildYallaTheme] from `yalla_cash_core` without
/// changing it, so the admin and merchant apps are unaffected. The overlay
/// adds the customer's complete Almarai family, the premium palette
/// ([YcColors]), surface tokens ([YcSurface]) and page transitions.
library;

// In this Flutter SDK the Cupertino page transition lives in the cupertino
// library rather than material.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

/// The customer app's only locale: Arabic (Syria). Drives Material strings
/// (tooltips, text-selection toolbar), right-to-left layout and the engine's
/// locale-aware text shaping.
const Locale customerLocale = Locale('ar', 'SY');

/// The customer light theme, built once and reused on every app rebuild.
final ThemeData customerLightTheme = buildCustomerTheme(Brightness.light);

/// The customer dark theme, built once and reused on every app rebuild.
final ThemeData customerDarkTheme = buildCustomerTheme(Brightness.dark);

/// The customer app's theme for [brightness]. Prefer the cached
/// [customerLightTheme] / [customerDarkTheme] in the app itself.
ThemeData buildCustomerTheme(Brightness brightness) {
  final base = buildYallaTheme(brightness);
  final dark = brightness == Brightness.dark;
  final palette = YcColors.forBrightness(brightness);
  final page = customerPageColor(brightness);
  final card = customerCardColor(brightness);
  final scheme = base.colorScheme.copyWith(
    surface: card,
    onSurface: palette.ink,
    onSurfaceVariant: palette.inkMuted,
    surfaceContainerHighest:
        dark ? const Color(0xFF17303F) : const Color(0xFFE9EFF3),
    outlineVariant: dark
        ? Colors.white.withValues(alpha: .10)
        : YallaColors.navy.withValues(alpha: .10),
  );
  final textTheme = _customerTextTheme(base.textTheme, palette);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: page,
    canvasColor: page,
    textTheme: textTheme,
    primaryTextTheme:
        base.primaryTextTheme.apply(fontFamily: customerFontFamily),
    cardTheme: base.cardTheme.copyWith(color: card),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: customerRaisedColor(brightness),
      labelStyle: textTheme.bodyMedium?.copyWith(color: palette.inkMuted),
      helperStyle: textTheme.bodySmall?.copyWith(color: palette.inkMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YcRadius.sm + 2),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YcRadius.sm + 2),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF1B3A4D) : YallaColors.navy,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YcRadius.sm),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(YcRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YcRadius.xl),
      ),
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: page,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleLarge,
    ),
    pageTransitionsTheme: _pageTransitions(page),
    extensions: [
      ...base.extensions.values,
      YcSurface.forBrightness(brightness),
      palette,
    ],
  );
}

/// Material 3 sizes kept as they are (every screen was laid out and tested
/// against them); only the family, weights and colour change. Weights map to
/// the four shipped Almarai faces so nothing is synthesised: headlines w800,
/// titles and labels w700, body w400.
TextTheme _customerTextTheme(TextTheme base, YcColors palette) {
  TextStyle? w(TextStyle? style, FontWeight weight) =>
      style?.copyWith(fontWeight: weight);
  return base
      .copyWith(
        displayLarge: w(base.displayLarge, FontWeight.w800),
        displayMedium: w(base.displayMedium, FontWeight.w800),
        displaySmall: w(base.displaySmall, FontWeight.w800),
        headlineLarge: w(base.headlineLarge, FontWeight.w800),
        headlineMedium: w(base.headlineMedium, FontWeight.w800),
        headlineSmall: w(base.headlineSmall, FontWeight.w700),
        titleLarge: w(base.titleLarge, FontWeight.w700),
        titleMedium: w(base.titleMedium, FontWeight.w700),
        titleSmall: w(base.titleSmall, FontWeight.w700),
        bodyLarge: w(base.bodyLarge, FontWeight.w400),
        bodyMedium: w(base.bodyMedium, FontWeight.w400),
        bodySmall: w(base.bodySmall, FontWeight.w400),
        labelLarge: w(base.labelLarge, FontWeight.w700),
        labelMedium: w(base.labelMedium, FontWeight.w700),
        labelSmall: w(base.labelSmall, FontWeight.w700),
      )
      .apply(
        fontFamily: customerFontFamily,
        bodyColor: palette.ink,
        displayColor: palette.ink,
      );
}

/// Android and other platforms: Material's Fade Forwards transition at
/// [YcMotion.pageEnter] / [YcMotion.pageExit], using the page background so no
/// other colour flashes between pages. iOS and macOS keep the native Cupertino
/// slide, its timing and its interactive swipe-back gesture.
///
/// Hero flights run on the route's animation, so store-logo Heroes follow the
/// same duration under normal motion.
PageTransitionsTheme _pageTransitions(Color background) {
  final fadeForwards = ReducedMotionPageTransitionsBuilder(
    FadeForwardsPageTransitionsBuilder(backgroundColor: background),
    duration: YcMotion.pageEnter,
    reverseDuration: YcMotion.pageExit,
  );
  return PageTransitionsTheme(
    builders: {
      TargetPlatform.android: fadeForwards,
      TargetPlatform.fuchsia: fadeForwards,
      TargetPlatform.linux: fadeForwards,
      TargetPlatform.windows: fadeForwards,
      TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
    },
  );
}

/// Wraps a [PageTransitionsBuilder] to set its timing and honour reduced
/// motion.
///
/// * [duration] / [reverseDuration] replace the wrapped builder's timing.
///   [MaterialPageRoute] reads these from the theme's builder, and Fade
///   Forwards is defined purely by curves over the 0→1 route animation, so a
///   shorter duration plays the same motion faster.
/// * Under reduced motion the route runs at [Duration.zero]: the page appears
///   at once and Hero widgets land without a flight. The getters have no
///   [BuildContext], so they read the same platform flag that
///   [MediaQueryData.disableAnimations] is built from.
///
/// The wrapped builder's [delegatedTransition] (the animation applied to the
/// outgoing page) is forwarded and gated the same way. It is created once and
/// cached so routes always see the same function.
class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  ReducedMotionPageTransitionsBuilder(
    this.delegate, {
    Duration? duration,
    Duration? reverseDuration,
  })  : _duration = duration ?? delegate.transitionDuration,
        _reverseDuration =
            reverseDuration ?? delegate.reverseTransitionDuration,
        _delegatedTransition = _gate(delegate.delegatedTransition);

  final PageTransitionsBuilder delegate;
  final Duration _duration;
  final Duration _reverseDuration;
  final DelegatedTransitionBuilder? _delegatedTransition;

  static bool get _systemReducedMotion => WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  static DelegatedTransitionBuilder? _gate(DelegatedTransitionBuilder? inner) {
    if (inner == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) =>
        YcMotion.reduced(context)
            ? child
            : inner(
                context,
                animation,
                secondaryAnimation,
                allowSnapshotting,
                child,
              );
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _delegatedTransition;

  @override
  Duration get transitionDuration =>
      _systemReducedMotion ? Duration.zero : _duration;

  @override
  Duration get reverseTransitionDuration =>
      _systemReducedMotion ? Duration.zero : _reverseDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (YcMotion.reduced(context)) return child;
    return delegate.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
