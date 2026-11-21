/// Store logo plate shared by the store list and the store details page.
library;

import 'package:flutter/material.dart';
import 'package:yalla_cash_core/yalla_cash_core.dart';
import 'package:yalla_cash_customer/src/ui/logo_trim.dart';
import 'package:yalla_cash_customer/src/ui/premium.dart';

/// Store logo tile. Always shows the whole logo (BoxFit.contain, never cropped
/// or stretched) on a clean white plate so any artwork stays crisp in both
/// themes. Falls back to a branded storefront tile when the store has no logo
/// or the logo fails to load.
///
/// With [heroTag] the plate flies between the store card and the details
/// page; the flight cross-fades from the (possibly whitespace-trimmed) card
/// view to the details view.
class YcLogoPlate extends StatelessWidget {
  const YcLogoPlate({
    required this.url,
    super.key,
    this.size = 56,
    this.heroTag,
    this.raised = true,
  });

  final String? url;
  final double size;

  /// Optional hero tag so the logo glides into the store details screen.
  final String? heroTag;

  /// Raised plates (details page) get a soft shadow and show the image as
  /// uploaded. Flat plates (list cards) use a hairline border only and trim
  /// plain background margins from the *view* (see [WhitespaceTrimmedLogo]).
  final bool raised;

  /// The plate sizes itself from its incoming constraints, so during a Hero
  /// flight it scales smoothly between the card and the details page.
  Widget _plate(BuildContext context, double s) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final logoUrl = url;
    final storefront = s * 0.42;
    final loading = Center(
      child: Icon(
        Icons.storefront_rounded,
        size: storefront,
        color: YallaColors.primary.withValues(alpha: .25),
      ),
    );
    final failed = Center(
      child: Icon(
        Icons.storefront_rounded,
        size: storefront,
        color: YallaColors.primaryStrong,
      ),
    );
    return Container(
      width: s,
      height: s,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(s * 0.26),
        border: Border.all(
          color: YallaColors.navy.withValues(alpha: dark ? 0 : .07),
        ),
        boxShadow: raised
            ? [
                BoxShadow(
                  color: (dark ? Colors.black : YallaColors.navy)
                      .withValues(alpha: dark ? .38 : .14),
                  blurRadius: s * 0.22,
                  offset: Offset(0, s * 0.08),
                ),
              ]
            : null,
      ),
      child: logoUrl == null
          ? DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [YallaColors.primary, YallaColors.primaryStrong],
                ),
              ),
              child: Center(
                child: Icon(Icons.storefront_rounded,
                    size: storefront, color: Colors.white),
              ),
            )
          : raised
              // Details page: the logo as uploaded. It must NOT be decoded at
              // a custom size: the Home card already holds this logo under
              // the plain NetworkImage cache key, and a resized copy would
              // be a different key, so the details page would re-download
              // and re-decode it (showing the placeholder meanwhile) and
              // would restart that on every layout change of the Hero flight.
              ? Padding(
                  padding: EdgeInsets.all(s * 0.10),
                  child: YcNetworkImage(
                    logoUrl,
                    resize: false,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    placeholder: loading,
                    error: failed,
                  ),
                )
              // List cards: a slim inset, and plain background margins inside
              // the image are trimmed from the *view* so marks with lots of
              // built-in whitespace stay visible.
              : Padding(
                  padding: EdgeInsets.all(s * 0.05),
                  child: WhitespaceTrimmedLogo(
                    url: logoUrl,
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : loading,
                    errorBuilder: (_, __, ___) => failed,
                  ),
                ),
    );
  }

  /// Cross-fades from the card plate to the details plate (and back) during
  /// the Hero flight, since the card view may be whitespace-trimmed. The card
  /// plate stays opaque underneath, so the white plate never turns see-through.
  static Widget _shuttle(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final fromChild = (fromContext.widget as Hero).child;
    final toChild = (toContext.widget as Hero).child;
    // `animation` reads 0 at the list card and 1 at the details page in both
    // directions.
    final push = direction == HeroFlightDirection.push;
    final card = push ? fromChild : toChild;
    final details = push ? toChild : fromChild;
    return Stack(
      fit: StackFit.expand,
      children: [
        card,
        FadeTransition(opacity: animation, child: details),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = SizedBox(
      width: size,
      height: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return _plate(context, side.isFinite ? side : size);
        },
      ),
    );
    final tag = heroTag;
    if (tag == null) return tile;
    return Hero(
      tag: tag,
      // Straight-line flight (the default is an arc), which reads calmer.
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: _shuttle,
      child: tile,
    );
  }
}
