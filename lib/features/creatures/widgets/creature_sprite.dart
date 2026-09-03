import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// How wide to DECODE a creature sprite, in device pixels — the monster art
/// equivalent of settlement/widgets/building_icon.dart's own _decodeWidth
/// (same reasoning duplicated rather than shared across features on purpose;
/// see that file for the full story). Without this, every sprite — network
/// art at whatever resolution it was uploaded at — decodes at its FULL
/// native size regardless of how small it is actually drawn, which is what
/// made monster art the slow, memory-heavy load (user 2026-08-29: "die
/// Monsterassets werden sehr langsam geladen").
///
/// Device pixels plus a quarter of headroom for zooming in, floored so a
/// tiny icon still decodes cleanly. [displayWidth] is whichever of the
/// widget's own width/height is known — for BoxFit.contain art the two are
/// close enough that either bounds the decode sensibly.
int decodeWidthFor(BuildContext context, double displayWidth) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  final want = (displayWidth * (dpr > 3 ? 3 : dpr) * 1.25).ceil();
  return want < 96 ? 96 : want;
}

/// Shared renderer for a creature's PNG sprite (user 2026-07-25). Backed by
/// [CachedNetworkImage] so sprites are cached to DISK — the raw `Image.network`
/// this replaces only lived in the in-memory cache, so every eviction / cold
/// start re-downloaded them, which hurt in the scrolling collection + team
/// pickers where the same handful of sprites render over and over.
///
/// Pixel-art defaults: [FilterQuality.none] (crisp, no smoothing) and no fade.
/// Only used when [url] is non-empty; callers keep their own no-url branch.
class CreatureSprite extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;

  /// Shown on load error (and while loading, so there's no flash — pass a
  /// transparent box for the "nothing until it pops in" look).
  final Widget fallback;

  const CreatureSprite({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    // Whichever dimension is known bounds the decode — for BoxFit.contain
    // art the two are close enough that either is a sensible cap, and most
    // callers here only ever pass one of the two anyway.
    final knownWidth = width ?? height;
    final memWidth =
        knownWidth == null ? null : decodeWidthFor(context, knownWidth);
    // FLUTTER WEB (user 2026-09-02): cached_network_image/flutter_cache_manager
    // is built around a real on-disk cache, which the browser doesn't have —
    // in practice this made creature art fail to load intermittently on
    // Chrome (reproduced with the starter picker: untouched cards randomly
    // came back as the error widget, only recovering on a retry), while a
    // plain Image.network — which just goes through the browser's own
    // fetch/img loading — didn't. That's the standard workaround for this
    // package's well-documented web unreliability, so web skips
    // CachedNetworkImage entirely rather than routing through a cache layer
    // that doesn't actually have anywhere durable to write to there.
    if (kIsWeb) {
      return Image.network(
        url,
        fit: fit,
        alignment: alignment,
        width: width,
        height: height,
        cacheWidth: memWidth,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth: memWidth,
      filterQuality: FilterQuality.none,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
