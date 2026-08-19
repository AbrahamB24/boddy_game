import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/building_art.dart';

// Shared icon renderer for BuildingDef (and the handful of non-building
// "source" rows that still use a literal emoji, e.g. resource_breakdown_sheet
// .dart's synthetic population-upkeep row, and EraDef rows in
// dev_mode_screen.dart which never got PNGs). Buildings themselves have no
// emoji anymore — see BuildingDef.imageUrl — so `imageUrl` is the primary
// path and `emoji` only matters for those non-building callers.
class BuildingIcon extends StatelessWidget {
  final String? imageUrl;

  /// The BuildingDef's id, so the icon can use the picture that SHIPS with the
  /// app instead of a downloaded one — see data/building_art.dart. A bundled
  /// asset wins over [imageUrl]; when nothing is bundled for this id (the
  /// ordinary case — twenty of eighty-nine buildings are modelled so far)
  /// nothing changes at all.
  ///
  /// Optional, because the handful of non-building "source" rows that reuse
  /// this widget have no def and no art.
  final String? defId;
  final String emoji;
  // `size` sets both width and height (the common square-icon case — build
  // menu tiles, dialog headers, list rows). Pass `width`/`height` instead
  // when a building's actual (possibly non-square) grid footprint needs to
  // be matched exactly, e.g. the map tile — see widgets/settlement_map.dart's
  // _BuildingTile, sized from the footprint's diamond (spriteWidth in
  // iso_grid.dart).
  final double? size;
  final double? width;
  final double? height;
  final bool dimmed;
  // When true: the image is scaled to exactly match `width`/`size` (its
  // natural aspect ratio determines the resulting height) and anchored to
  // the bottom, so a sprite taller than its tile's footprint overflows
  // upward past it instead of being squeezed to fit — the usual "sprite
  // standing on its tile" look for isometric/city-builder art. `height` is
  // ignored for the image itself in this mode. The immediate parent Stack
  // must set `clipBehavior: Clip.none` for the overflow to actually show
  // instead of being cut off. See widgets/settlement_map.dart's _BuildingTile.
  final bool anchorBottomOverflowTop;

  // How the image fills its box (ignored in anchorBottomOverflowTop mode).
  // Default `contain` letterboxes non-square art — pass `cover`/`fill` for
  // tiles that must be filled edge-to-edge, e.g. road cells on the map.
  final BoxFit fit;

  const BuildingIcon({
    super.key,
    this.imageUrl,
    this.defId,
    this.emoji = '',
    this.size,
    this.width,
    this.height,
    this.dimmed = false,
    this.anchorBottomOverflowTop = false,
    this.fit = BoxFit.contain,
  }) : assert(size != null || width != null, 'Pass width or size'),
       assert(
         anchorBottomOverflowTop || size != null || height != null,
         'Pass either size, or both width and height',
       );

  double get _w => width ?? size!;
  double get _h => height ?? size ?? _w;

  /// How wide to DECODE the bundled picture, in device pixels.
  ///
  /// ── The map ran CanvasKit out of memory (user 2026-08-12) ──
  /// The renders are 1024-1372 px across and the map draws a building about
  /// 200 logical px wide. Decoded at source resolution the twenty bundled
  /// assets need 80 MB of RGBA — with a 32 MB map background on top of that,
  /// against Flutter's default 100 MB image cache. The cache starts evicting
  /// and re-decoding on every pan, and on the web that surfaces as
  /// "memory access out of bounds" inside canvaskit.wasm, then "Cannot
  /// dispose picture" as the heap comes apart. It is not a Dart error at all;
  /// it is the texture budget.
  ///
  /// Device pixels plus a quarter, and never more than the asset HAS —
  /// cacheWidth above the natural width upsamples, which costs memory and
  /// buys nothing. The cap is tool/pack_art.py's APP_MAX_WIDTH.
  ///
  /// The ratio is against device pixels rather than logical ones because that
  /// is what the GPU actually samples; a factor on top of that is headroom for
  /// zooming in, and every multiple of it is paid for in the image cache.
  int? _decodeWidth(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final want = (_w * (dpr > 3 ? 3 : dpr) * 1.25).ceil();
    return want < 96 ? 96 : (want > 640 ? 640 : want);
  }

  @override
  Widget build(BuildContext context) {
    // The bundled picture first: it is the one that cannot be stale, cannot
    // fail to download, and cannot disagree with the model it was rendered
    // from. errorBuilder still falls through to the emoji/placeholder, because
    // a missing asset must not leave a hole where a building is.
    final asset = buildingAsset(defId);
    if (asset != null) {
      final cw = _decodeWidth(context);
      final image = anchorBottomOverflowTop
          ? Image.asset(
              asset,
              width: _w,
              cacheWidth: cw,
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : Image.asset(
              asset,
              width: _w,
              height: _h,
              cacheWidth: cw,
              fit: fit,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _fallback(),
            );
      return dimmed ? Opacity(opacity: 0.4, child: image) : image;
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (anchorBottomOverflowTop) {
        final image = CachedNetworkImage(
          imageUrl: imageUrl!,
          width: _w,
          fit: BoxFit.fitWidth,
          alignment: Alignment.bottomCenter,
          placeholder: (context, url) => _fallback(),
          errorWidget: (context, url, error) => _fallback(),
        );
        return dimmed ? Opacity(opacity: 0.4, child: image) : image;
      }
      final image = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: _w,
        height: _h,
        fit: fit,
        placeholder: (context, url) => _fallback(),
        errorWidget: (context, url, error) => _fallback(),
      );
      return dimmed ? Opacity(opacity: 0.4, child: image) : image;
    }
    return _fallback();
  }

  Widget _fallback() {
    // Fallback content (emoji/placeholder icon) always renders as a single
    // square glyph — sized off the smaller dimension so it never overflows a
    // non-square footprint.
    final glyphSize = _w < _h ? _w : _h;
    if (emoji.isNotEmpty) {
      return SizedBox(
        width: _w,
        height: _h,
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(
              fontSize: glyphSize,
              color: dimmed ? Colors.white30 : null,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: _w,
      height: _h,
      child: Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          size: glyphSize,
          color: Colors.white24,
        ),
      ),
    );
  }
}

/// A building [BuildingIcon] standing on its own cast SHADOW — the monsters'
/// look (battle_screen._spriteWithShadow): a SHARP, un-blurred silhouette of
/// the art itself, nudged down-right and slightly smaller, so it reads as cast
/// on the ground rather than as a soft drop shadow.
///
/// One definition for both places a building's art stands out of a tile — the
/// build-menu card and the detail dialog — so the two can never drift apart.
/// Bottom-anchored, so it belongs in a Stack whose `alignment` is
/// `Alignment.bottomCenter`; the caller reserves the headroom for the overflow.
class ShadowedBuildingIcon extends StatelessWidget {
  final String? imageUrl;

  /// Passed straight through to [BuildingIcon] — see its `defId`.
  final String? defId;
  final double width;

  /// Dims the art (not the shadow) — the build menu greys an unaffordable card.
  final bool dimmed;

  const ShadowedBuildingIcon({
    super.key,
    required this.imageUrl,
    required this.width,
    this.defId,
    this.dimmed = false,
  });

  Widget _icon({required bool asShadow}) {
    final image = BuildingIcon(
      imageUrl: imageUrl,
      defId: defId,
      width: width,
      anchorBottomOverflowTop: true,
      dimmed: dimmed && !asShadow,
    );
    if (!asShadow) return image;
    return Opacity(
      opacity: 0.32,
      child: Transform.translate(
        offset: const Offset(4, 7),
        child: Transform.scale(
          scale: 0.92,
          alignment: Alignment.bottomCenter,
          child: ColorFiltered(
            // Opaque tint = a true silhouette; the Opacity above sets how dark
            // it lands.
            colorFilter: const ColorFilter.mode(
              Color(0xFF06170F),
              BlendMode.srcATop,
            ),
            child: image,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.bottomCenter,
    children: [_icon(asShadow: true), _icon(asShadow: false)],
  );
}
