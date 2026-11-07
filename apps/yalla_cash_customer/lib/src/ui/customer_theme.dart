/// Customer-only theme overlay.
///
/// Builds on the shared [buildYallaTheme] from `yalla_cash_core` without
/// changing it, so the admin and merchant apps are unaffected. Phase 1 keeps
/// the current look: it only adds the design-token extension and the page
/// transitions. Screen-level styling comes in later phases.
library;

// In this Flutter SDK the Cupertino page transition lives in the cupertino
// library rather than material.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/tokens.dart';

/// The customer app's theme for [brightness].
ThemeData buildCustomerTheme(Brightness brightness) {
  final base = buildYallaTheme(brightness);
  return base.copyWith(
    pageTransitionsTheme: _pageTransitions(base.scaffoldBackgroundColor),
    extensions: [
      ...base.extensions.values,
      YcSurface.forBrightness(brightness),
    ],
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
