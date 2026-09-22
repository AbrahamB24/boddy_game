import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/building_art.dart';

// Shared icon renderer for BuildingDef (and the handful of non-building
// "source" rows that still use a literal emoji, e.g. resource_detail_screen
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
  ///
  /// Static, and taking the width as an argument instead of reading `this`,
  /// because a PRECACHE has to arrive at the same number (2026-09-21).
  /// Flutter's ImageCache keys on the ImageProvider, and `cacheWidth` /
  /// `memCacheWidth` resolve through a [ResizeImage] wrapper whose key
  /// INCLUDES that width — so precaching the bare provider files the picture
  /// under a key this widget never looks up: a full-resolution decode nobody
  /// reads, and then a second decode when the widget finally draws it. A
  /// caller that warms the cache goes through [providerFor].
  static int decodeWidthFor(BuildContext context, double logicalWidth) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final want = (logicalWidth * (dpr > 3 ? 3 : dpr) * 1.25).ceil();
    return want < 96 ? 96 : (want > 640 ? 640 : want);
  }

  /// Exactly the provider this widget resolves for [defId] at [logicalWidth]
  /// — the only thing a precache may hand to `precacheImage` and have the
  /// entry actually be hit later. Null when the id has no BUNDLED art: a
  /// network picture's BYTES are warmed through its cache manager instead,
  /// since decoding one ahead of time buys nothing and spends the whole
  /// texture budget doing it.
  static ImageProvider? providerFor(
    BuildContext context,
    String defId,
    double logicalWidth,
  ) {
    final asset = buildingAsset(defId);
    if (asset == null) return null;
    return ResizeImage.resizeIfNeeded(
      decodeWidthFor(context, logicalWidth),
      null,
      AssetImage(asset),
    );
  }

  int? _decodeWidth(BuildContext context) => decodeWidthFor(context, _w);

  /// How far a not-yet-finished building's picture is faded back.
  static const _kDimmed = AlwaysStoppedAnimation<double>(0.4);

  /// The fade for anything that is NOT a plain [Image] — the emoji/placeholder
  /// fallback, and the network path, since [CachedNetworkImage] has no
  /// `opacity` of its own. Here an [Opacity] is the only option; on an
  /// `Image` it is not, and that is the case that is on the map in bulk.
  Widget _dim(Widget child) =>
      dimmed ? Opacity(opacity: 0.4, child: child) : child;

  @override
  Widget build(BuildContext context) {
    // The bundled picture first: it is the one that cannot be stale, cannot
    // fail to download, and cannot disagree with the model it was rendered
    // from. errorBuilder still falls through to the emoji/placeholder, because
    // a missing asset must not leave a hole where a building is.
    final asset = buildingAsset(defId);
    if (asset != null) {
      final cw = _decodeWidth(context);
      // THROUGH THE IMAGE, not an Opacity around it (2026-09-21). [Opacity]
      // pushes an offscreen layer and composites it back — and `dimmed` is
      // what every building still UNDER CONSTRUCTION uses, so an early town
      // paid a saveLayer per site, every frame it was on screen. `Image`'s
      // own `opacity` folds the alpha into the draw call instead, and looks
      // the same because there is exactly one thing being faded.
      final image = anchorBottomOverflowTop
          ? Image.asset(
              asset,
              width: _w,
              cacheWidth: cw,
              fit: BoxFit.fitWidth,
              alignment: Alignment.bottomCenter,
              filterQuality: FilterQuality.medium,
              opacity: dimmed ? _kDimmed : null,
              errorBuilder: (_, _, _) => _dim(_fallback()),
            )
          : Image.asset(
              asset,
              width: _w,
              height: _h,
              cacheWidth: cw,
              fit: fit,
              filterQuality: FilterQuality.medium,
              opacity: dimmed ? _kDimmed : null,
              errorBuilder: (_, _, _) => _dim(_fallback()),
            );
      return image;
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      // Same cap as the bundled path above (user 2026-09-06: "performance
      // deutlich verbessern") — this one had none at all, so every one of
      // the 69 buildings still on an uploaded (not bundled) picture decoded
      // at its FULL NATIVE resolution, uncapped, every time it's drawn. The
      // bundled path exists only for 20 of 89 buildings; this is the common
      // case, not the edge case.
      final cw = _decodeWidth(context);
      if (anchorBottomOverflowTop) {
        final image = CachedNetworkImage(
          imageUrl: imageUrl!,
          width: _w,
          memCacheWidth: cw,
          fit: BoxFit.fitWidth,
          alignment: Alignment.bottomCenter,
          placeholder: (context, url) => _fallback(),
          errorWidget: (context, url, error) => _fallback(),
        );
        return _dim(image);
      }
      final image = CachedNetworkImage(
        imageUrl: imageUrl!,
        width: _w,
        height: _h,
        memCacheWidth: cw,
        fit: fit,
        placeholder: (context, url) => _fallback(),
        errorWidget: (context, url, error) => _fallback(),
      );
      return _dim(image);
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

/// One picture's cast shadow, ready to paint: an alpha mask laid out in the
/// picture's own pixel grid (same top-left), [srcW] x [srcH] being the picture
/// itself — the mask reaches past its right and bottom edges, where the shadow
/// falls.
class _Cast {
  final ui.Image mask;

  /// The picture's size in the measured pixels, and its height / width.
  final int srcW;
  final int srcH;
  const _Cast(this.mask, this.srcW, this.srcH);
  double get aspect => srcH / srcW;
}

/// The result of [castShadowMask]: one alpha byte per pixel.
class ShadowMask {
  final Uint8List alpha;
  final int width;
  final int height;
  const ShadowMask(this.alpha, this.width, this.height);
}

/// The shadow of every standing thing in a picture, laid on the ground.
///
/// [rgba] is the picture's pixels ([w] x [h], 4 bytes each). Each COLUMN is cut
/// into vertical runs of solid pixels; a run is one thing standing, and its
/// BOTTOM is where it touches the ground. Every pixel of the run is thrown from
/// that foot: [shear] to the right and [squash] down per pixel of height above
/// it — the ground's 2:1 diagonal, away from a sun at the top left.
///
/// PER RUN, not one hinge for the whole picture (user 2026-09-22: "der Schatten
/// ist unterhalb des Gebäudes und nicht am richtigen Ort"): a house with a
/// fence round its yard has its lowest pixel on the fence's front corner, and a
/// shadow hinged THERE lay a whole yard's depth below the walls that cast it.
/// Each thing now casts from its own foot — the walls from the wall's base, a
/// post from the post's — and a taller thing throws a longer shadow with no
/// per-object numbers.
///
/// Overlapping shadows do not darken each other (one alpha byte, set not added).
ShadowMask castShadowMask(
  Uint8List rgba,
  int w,
  int h, {
  double shear = BuildingGroundShadow._shear,
  double squash = BuildingGroundShadow._squash,
  int solid = BuildingGroundShadow._solid,
  int gapTolerance = 3,

  /// True (buildings): each vertical run of solid pixels is thrown from its OWN
  /// foot. False (a single standing thing — a tree, a stone): the whole picture
  /// is thrown from ONE foot, its lowest solid pixel. Per run would treat a
  /// tree's overhanging tiers as things standing on the ground: their undersides
  /// would cast a second, higher shadow beside the trunk's (user 2026-09-22: "es
  /// scheint als gäbe es 2 Schatten, einer gegen Osten und einer gegen Nordosten").
  bool perRun = true,
}) {
  final mw = w + (shear * h).ceil() + 2;
  final mh = h + (squash * h).ceil() + 2;
  final alpha = Uint8List(mw * mh);

  void throwRun(int x, int y0, int y1) {
    // y1 is the run's lowest solid row: the foot, so the shadow starts on the
    // row BELOW it.
    for (var y = y0; y <= y1; y++) {
      final d = y1 - y;
      final tx = (x + d * shear).round();
      final ty = (y1 + 1 + d * squash).round();
      if (tx >= 0 && tx < mw && ty >= 0 && ty < mh) alpha[ty * mw + tx] = 255;
    }
  }

  if (!perRun) {
    // One foot for the whole picture: its lowest solid pixel.
    var foot = -1;
    for (var y = h - 1; y >= 0 && foot < 0; y--) {
      for (var x = 0; x < w; x++) {
        if (rgba[(y * w + x) * 4 + 3] >= solid) {
          foot = y;
          break;
        }
      }
    }
    if (foot < 0) return ShadowMask(alpha, mw, mh);
    for (var x = 0; x < w; x++) {
      for (var y = 0; y <= foot; y++) {
        if (rgba[(y * w + x) * 4 + 3] < solid) continue;
        final d = foot - y;
        final tx = (x + d * shear).round();
        final ty = (foot + 1 + d * squash).round();
        if (tx >= 0 && tx < mw && ty >= 0 && ty < mh) alpha[ty * mw + tx] = 255;
      }
    }
    return ShadowMask(alpha, mw, mh);
  }

  for (var x = 0; x < w; x++) {
    var start = -1;
    var last = -1;
    for (var y = 0; y < h; y++) {
      if (rgba[(y * w + x) * 4 + 3] >= solid) {
        if (start < 0) start = y;
        // A hole of a pixel or two inside a thing (an antialiased edge, a thin
        // window frame) does not split it in two.
        last = y;
      } else if (start >= 0 && y - last > gapTolerance) {
        throwRun(x, start, last);
        start = -1;
      }
    }
    if (start >= 0) throwRun(x, start, last);
  }
  return ShadowMask(alpha, mw, mh);
}

/// The cast shadow of an already decoded picture, as a ready-to-paint image in
/// the picture's own pixel grid (same top-left; it reaches past the right and
/// bottom edges). Used for the rest of the map — trees, stones — so they throw
/// the SAME shadow the buildings do: one sun, one length, one direction (user
/// 2026-09-22: "den Schatten jetzt auch auf den Rest der Map umsetzen").
///
/// The colour is baked in at [alpha] (of 255), so thousands of them are drawn
/// with a plain paint — no colour filter per draw. Null for a picture that casts
/// nothing (fully transparent) or cannot be read.
Future<ui.Image?> castShadowImage(
  ui.Image image, {
  int alpha = 61,

  /// A tree or a stone is ONE standing thing: thrown from one foot, so its
  /// canopy does not cast a second shadow from its own underside.
  bool perRun = false,
}) async {
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final mask = castShadowMask(
      data.buffer.asUint8List(),
      image.width,
      image.height,
      perRun: perRun,
    );
    if (!mask.alpha.any((a) => a != 0)) return null;
    final rgba = Uint8List(mask.width * mask.height * 4);
    for (var i = 0; i < mask.alpha.length; i++) {
      if (mask.alpha[i] == 0) continue;
      rgba[i * 4] = 0x06;
      rgba[i * 4 + 1] = 0x17;
      rgba[i * 4 + 2] = 0x0F;
      rgba[i * 4 + 3] = alpha;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      mask.width,
      mask.height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return await done.future;
  } catch (_) {
    return null;
  }
}

/// A building's SHADOW ON THE GROUND, for the settlement map (user 2026-09-18:
/// "kannst du die Gebäude auf der Karte einen Schatten werfen lassen, damit sie
/// Kontext bekommen?" — "Variante 2", the isometric one; then "die Sonne kommt
/// von oben links und die Schatten sollen nicht zu lange sein und direkt an den
/// Objekten"; then "wenn eine Lampe steht, dann ist der Schatten 'im' Bild und
/// nicht unterhalb"; and 2026-09-22 "der Schatten ist unterhalb des Gebäudes und
/// nicht am richtigen Ort").
///
/// The object's own silhouette, laid down on the ground plane and pushed
/// down-right along the ground's 2:1 diagonal, away from a sun at the top left —
/// each standing thing from ITS OWN foot (see [castShadowMask]), so the shadow
/// starts at the walls and posts that cast it, however much yard, fence or air
/// the picture has below them. A taller object throws a longer shadow, and the
/// length is one number ([_shear]) for all of them.
///
/// Down-right also means FORWARD: the map paints back to front, so a building
/// standing in front of this one is painted AFTER its shadow and covers it, and
/// the shadow can never fall over something it should be behind. Roads are
/// painted earlier still, so it lies on them like on any other ground.
///
/// Place it exactly where the object's own art goes (same left/width/bottom) and
/// paint it FIRST.
class BuildingGroundShadow extends StatefulWidget {
  final String? imageUrl;
  final String? defId;
  final double width;
  final bool dimmed;

  const BuildingGroundShadow({
    super.key,
    required this.imageUrl,
    required this.width,
    this.defId,
    this.dimmed = false,
  });

  /// How far the top of the silhouette slides right, per unit of its height. The
  /// shadow's length: 0.34 puts the tip of a 200 px object 68 px to its right.
  static const double _shear = 0.34;

  /// How far it drops below the foot for the same unit. The shadow's DIRECTION is
  /// the ratio of the two: it was half the shear (the ground's own 2:1 diagonal,
  /// 27° below the horizontal); "jetzt soll der Schatten etwas mehr östlich sein"
  /// (user 2026-09-22) turned it towards the east — about 17° — and "noch mehr
  /// nach osten/rechts" turned it on to about 10°, the length growing only a little.
  static const double _squash = 0.06;

  /// The map's ground is busy (trees, stones, flowers), so the shadow stays
  /// light, close to the build menu's own 22 %.
  static const double _opacity = 0.24;

  /// Pixels fainter than this (of 255) are not "the object": a soft baked-in
  /// shadow or an antialiased fringe must not count as part of it.
  static const int _solid = 80;

  /// The width a picture is measured at. Small — the shadow is soft and low, and
  /// ninety of them have to stay cheap — and scaled up when painted.
  static const int _measureWidth = 128;

  /// One shadow per picture, for the life of the app.
  static final Map<String, _Cast?> _done = {};
  static final Map<String, Future<_Cast?>> _pending = {};

  @override
  State<BuildingGroundShadow> createState() => _BuildingGroundShadowState();

  static ImageProvider? _providerFor(String? defId, String? imageUrl) {
    final asset = buildingAsset(defId);
    if (asset != null) return AssetImage(asset);
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CachedNetworkImageProvider(imageUrl);
    }
    return null;
  }

  static Future<_Cast?> _measure(String key, ImageProvider provider) =>
      _pending.putIfAbsent(key, () {
        final done = Completer<_Cast?>();
        final stream = ResizeImage(
          provider,
          width: _measureWidth,
        ).resolve(ImageConfiguration.empty);
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) async {
            stream.removeListener(listener);
            try {
              final image = info.image;
              final data = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              if (data == null) {
                done.complete(null);
                return;
              }
              final w = image.width, h = image.height;
              final mask = castShadowMask(data.buffer.asUint8List(), w, h);
              // An empty mask (a fully transparent picture) casts nothing.
              if (!mask.alpha.any((a) => a != 0)) {
                done.complete(null);
                return;
              }
              // Black + the mask's alpha; the paint's own colour sets the tint.
              final rgba = Uint8List(mask.width * mask.height * 4);
              for (var i = 0; i < mask.alpha.length; i++) {
                rgba[i * 4 + 3] = mask.alpha[i];
              }
              final pixels = Completer<ui.Image>();
              ui.decodeImageFromPixels(
                rgba,
                mask.width,
                mask.height,
                ui.PixelFormat.rgba8888,
                pixels.complete,
              );
              done.complete(_Cast(await pixels.future, w, h));
            } catch (_) {
              done.complete(null);
            }
          },
          onError: (_, _) {
            stream.removeListener(listener);
            done.complete(null);
          },
        );
        stream.addListener(listener);
        return done.future.then((cast) => _done[key] = cast);
      });
}

class _BuildingGroundShadowState extends State<BuildingGroundShadow> {
  String? get _key {
    final asset = buildingAsset(widget.defId);
    if (asset != null) return asset;
    final url = widget.imageUrl;
    return url != null && url.isNotEmpty ? url : null;
  }

  Future<_Cast?>? _future;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(BuildingGroundShadow old) {
    super.didUpdateWidget(old);
    if (old.defId != widget.defId || old.imageUrl != widget.imageUrl) _start();
  }

  void _start() {
    final key = _key;
    final provider = BuildingGroundShadow._providerFor(
      widget.defId,
      widget.imageUrl,
    );
    if (key == null ||
        provider == null ||
        BuildingGroundShadow._done.containsKey(key)) {
      _future = null;
      return;
    }
    _future = BuildingGroundShadow._measure(key, provider);
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    if (key == null) return const SizedBox.shrink();
    if (BuildingGroundShadow._done.containsKey(key)) {
      return _shadow(BuildingGroundShadow._done[key]);
    }
    return FutureBuilder<_Cast?>(
      future: _future,
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? _shadow(snap.data)
          : const SizedBox.shrink(),
    );
  }

  Widget _shadow(_Cast? cast) {
    // Nothing measurable (a fully transparent or unreadable picture): no shadow
    // rather than a wrong one.
    if (cast == null) return const SizedBox.shrink();
    // The box the picture itself occupies; the shadow is painted past its right
    // and bottom edges (CustomPaint does not clip).
    return IgnorePointer(
      child: SizedBox(
        width: widget.width,
        height: widget.width * cast.aspect,
        child: CustomPaint(painter: _ShadowPainter(cast)),
      ),
    );
  }
}

class _ShadowPainter extends CustomPainter {
  final _Cast cast;
  const _ShadowPainter(this.cast);

  @override
  void paint(Canvas canvas, Size size) {
    // One measured pixel, in the size the picture is drawn at.
    final unit = size.width / cast.srcW;
    final mask = cast.mask;
    canvas.drawImageRect(
      mask,
      Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
      Rect.fromLTWH(0, 0, mask.width * unit, mask.height * unit),
      Paint()
        ..filterQuality = FilterQuality.medium
        // An opaque tint = a true silhouette; its alpha sets how dark it lands.
        ..colorFilter = ColorFilter.mode(
          const Color(
            0xFF06170F,
          ).withValues(alpha: BuildingGroundShadow._opacity),
          BlendMode.srcIn,
        ),
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => old.cast != cast;
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
    // Lighter and closer than before (user 2026-08-27: "das Gebäude ist
    // anscheinend etwas durchsichtig") — at the card's small size the old
    // 0.32/offset(4,7) read less like a shadow grounding the building and
    // more like a second, fainter copy of it peeking out past the edges.
    return Opacity(
      opacity: 0.22,
      child: Transform.translate(
        offset: const Offset(3, 5),
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
