/// Display-only whitespace trimming for store logos.
///
/// Many uploaded logos are a small mark in the middle of a large plain
/// canvas, so at card size the brand is almost invisible. This zooms the
/// *view* of the unchanged image so its content fills the plate. It never
/// edits, re-encodes or replaces the image, and it never cuts into content:
///
/// * Trimming happens only when all four corners share one background
///   colour (or are all transparent). Anything else is left exactly as is.
/// * A pixel counts as content when it differs from that background by more
///   than a small tolerance, so faint artwork is kept, not treated as margin.
/// * The detected box is padded by a safety buffer, and the zoom is limited
///   so the whole box stays inside the plate with breathing room.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Fractional content box of a logo (0–1 in each axis) and its aspect ratio.
@immutable
class LogoContentBounds {
  const LogoContentBounds({required this.content, required this.aspect});

  /// Content rectangle as fractions of the image. [full] means no trim.
  final Rect content;

  /// Image width / height.
  final double aspect;

  static const Rect full = Rect.fromLTWH(0, 0, 1, 1);

  bool get trims => content != full;
}

/// Finds the content box in an RGBA ([w] × [h], straight alpha) bitmap.
///
/// Returns null when there is nothing safe or worthwhile to trim: the corners
/// disagree (no uniform background), the image is blank, or the content
/// already covers most of the image.
Rect? logoContentRect(
  Uint8List rgba,
  int w,
  int h, {
  int tolerance = 14,
  double buffer = .06,
  double maxCoverage = .70,
}) {
  if (w < 3 || h < 3 || rgba.length < w * h * 4) return null;
  int at(int x, int y, int c) => rgba[(y * w + x) * 4 + c];
  bool transparent(int x, int y) => at(x, y, 3) < 24;

  final corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)];
  final (bx, by) = corners.first;
  final bgTransparent = transparent(bx, by);

  bool sameAsBackground(int x, int y) {
    if (bgTransparent) return transparent(x, y);
    if (transparent(x, y)) return false;
    for (var c = 0; c < 4; c++) {
      if ((at(x, y, c) - at(bx, by, c)).abs() > tolerance) return false;
    }
    return true;
  }

  // Uniform background: every corner must match the first one.
  for (final (x, y) in corners) {
    if (!sameAsBackground(x, y)) return null;
  }

  var top = -1, bottom = -1, left = w, right = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (sameAsBackground(x, y)) continue;
      if (top < 0) top = y;
      bottom = y;
      if (x < left) left = x;
      if (x > right) right = x;
    }
  }
  if (top < 0) return null; // blank image: nothing to zoom to

  final rect = Rect.fromLTRB(
    (left / w - buffer).clamp(0.0, 1.0),
    (top / h - buffer).clamp(0.0, 1.0),
    ((right + 1) / w + buffer).clamp(0.0, 1.0),
    ((bottom + 1) / h + buffer).clamp(0.0, 1.0),
  );
  if (rect.width * rect.height > maxCoverage) return null;
  return rect;
}

/// Measures [image] on a small thumbnail (cheap, and identical in proportion
/// on both axes).
Future<LogoContentBounds> measureLogo(ui.Image image) async {
  const n = 128;
  final aspect = image.width / image.height;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const Rect.fromLTWH(0, 0, n + 0.0, n + 0.0),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final thumb = await picture.toImage(n, n);
  picture.dispose();
  final data =
      await thumb.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  thumb.dispose();
  final rect =
      data == null ? null : logoContentRect(data.buffer.asUint8List(), n, n);
  return LogoContentBounds(
    content: rect ?? LogoContentBounds.full,
    aspect: aspect,
  );
}

/// The zoom (and translation) that makes [bounds]' content fill [fill] of a
/// [box] when the image is laid out with BoxFit.contain, or null for none.
Matrix4? logoZoomTransform(
  LogoContentBounds bounds,
  Size box, {
  double fill = .86,
  double maxZoom = 2.5,
}) {
  if (!bounds.trims || box.isEmpty) return null;
  final ar = bounds.aspect;
  final (dw, dh) = box.width / box.height > ar
      ? (box.height * ar, box.height)
      : (box.width, box.width / ar);
  final ox = (box.width - dw) / 2, oy = (box.height - dh) / 2;
  final r = bounds.content;
  final cw = r.width * dw, ch = r.height * dh;
  if (cw <= 0 || ch <= 0) return null;
  final zoom = [fill * box.width / cw, fill * box.height / ch, maxZoom]
      .reduce((a, b) => a < b ? a : b);
  if (zoom <= 1.02) return null;
  final cx = ox + r.center.dx * dw, cy = oy + r.center.dy * dh;
  return Matrix4.diagonal3Values(zoom, zoom, 1)
    ..setTranslationRaw(
        box.width / 2 - zoom * cx, box.height / 2 - zoom * cy, 0);
}

/// [Image.network] with display-only whitespace trimming (see library docs).
/// Until the image has been measured — or when it cannot be trimmed safely —
/// it shows exactly what a plain `Image.network(fit: BoxFit.contain)` shows.
class WhitespaceTrimmedLogo extends StatefulWidget {
  const WhitespaceTrimmedLogo({
    required this.url,
    super.key,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String url;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Measured bounds per URL, shared by every card showing the same logo.
  static final Map<String, LogoContentBounds> _cache = {};

  @visibleForTesting
  static void clearCache() => _cache.clear();

  @override
  State<WhitespaceTrimmedLogo> createState() => _WhitespaceTrimmedLogoState();
}

class _WhitespaceTrimmedLogoState extends State<WhitespaceTrimmedLogo> {
  LogoContentBounds? _bounds;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// URL whose measurement has been started (at most once per URL).
  String? _requested;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bounds = WhitespaceTrimmedLogo._cache[widget.url];
    if (_bounds == null && _requested != widget.url) _listen();
  }

  @override
  void didUpdateWidget(covariant WhitespaceTrimmedLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _stopListening();
      _bounds = WhitespaceTrimmedLogo._cache[widget.url];
      if (_bounds == null) _listen();
    }
  }

  void _listen() {
    _requested = widget.url;
    // Same provider as the Image below, so the image cache is shared and the
    // logo is downloaded once.
    final stream = NetworkImage(widget.url)
        .resolve(createLocalImageConfiguration(context));
    final url = widget.url;
    _listener = ImageStreamListener(
      (info, _) {
        _stopListening();
        measureLogo(info.image).then((bounds) {
          info.dispose();
          WhitespaceTrimmedLogo._cache[url] = bounds;
          if (mounted && widget.url == url) setState(() => _bounds = bounds);
        }, onError: (_) => info.dispose());
      },
      onError: (_, __) => _stopListening(),
    );
    _stream = stream..addListener(_listener!);
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _listener = null;
    _stream = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      widget.url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
    );
    final bounds = _bounds;
    if (bounds == null || !bounds.trims) return image;
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        final transform = box.isFinite ? logoZoomTransform(bounds, box) : null;
        if (transform == null) return image;
        return ClipRect(
          child: Transform(
            transform: transform,
            child: SizedBox.fromSize(size: box, child: image),
          ),
        );
      },
    );
  }
}
