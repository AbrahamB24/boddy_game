import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    alignment: alignment,
    width: width,
    height: height,
    filterQuality: FilterQuality.none,
    fadeInDuration: Duration.zero,
    fadeOutDuration: Duration.zero,
    placeholder: (_, __) => const SizedBox.shrink(),
    errorWidget: (_, __, ___) => fallback,
  );
}
