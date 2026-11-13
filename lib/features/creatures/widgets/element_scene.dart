import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../settlement/widgets/building_icon.dart'
    show castShadowImage, kShadowTint, kShadowOpacity;
import '../models/creature_enums.dart';

/// A small scene for each creature TYPE, built from the MAP's own pictures
/// (user 2026-11-10: "kannst du nicht eine Szene machen in der Grafik der
/// Karte?"): the map's grass, sand and water swatches tiled as the ground, the
/// map's trees, stones, reeds, shells, campfire, menhirs and ruins standing on
/// it — the same sprites and the same cast shadows the settlement and the
/// battle arena use. Each type tints the ground and props its own way and adds
/// a little weather on top (embers, snow, rain and a bolt, mist, sparkles).
///
/// Only the PLACEMENT and the tints are this file's. The art loads once for
/// the life of the app; until it has, the card shows the type's plain colour.
class ElementScene extends StatefulWidget {
  final CreatureElement element;

  const ElementScene({super.key, required this.element});

  @override
  State<ElementScene> createState() => _ElementSceneState();
}

class _ElementSceneState extends State<ElementScene> {
  _SceneArt? _art = _SceneArt.cached;

  @override
  void initState() {
    super.initState();
    if (_art == null) {
      _SceneArt.load().then((art) {
        if (mounted && art != null) setState(() => _art = art);
      });
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _ScenePainter(widget.element, _art),
      child: const SizedBox.expand(),
    ),
  );
}

/// The map's pictures, decoded once.
class _SceneArt {
  final Map<String, ui.Image> tiles;
  final Map<String, ui.Image> props;
  final Map<String, ui.Image> shadows;

  const _SceneArt(this.tiles, this.props, this.shadows);

  static _SceneArt? cached;
  static Future<_SceneArt?>? _pending;

  /// key → (file, decode width, shadow depth or null for "casts none").
  static const _files = <String, (String, int, double?)>{
    'tree_b_m': ('prop_broadleaf_m', 200, 0.14),
    'tree_b_s': ('prop_broadleaf_s', 150, 0.14),
    'tree_c_m': ('prop_conifer_m', 200, 0.14),
    'tree_c_s': ('prop_conifer_s', 150, 0.14),
    'bush_a': ('prop_bush_a', 90, null),
    'bush_c': ('prop_bush_c', 90, null),
    'flowers_a': ('prop_flowers_a', 80, null),
    'flowers_b': ('prop_flowers_b', 80, null),
    'flowers_d': ('prop_flowers_d', 90, null),
    'fern': ('prop_fern', 50, null),
    'tuft': ('prop_tuft', 50, null),
    'stump': ('prop_stump', 40, 0.08),
    'log': ('prop_log_a', 80, 0.08),
    'stone_a': ('prop_stone_a', 100, 0.08),
    'stone_b': ('prop_stone_b', 100, 0.08),
    'stone_c': ('prop_stone_c', 120, 0.08),
    'stone_d': ('prop_stone_d', 100, 0.08),
    'stone_e': ('prop_stone_e', 100, 0.08),
    'stone_f': ('prop_stone_f', 100, 0.08),
    'reeds': ('prop_reeds', 100, null),
    'shell': ('prop_shell_a', 50, null),
    'driftwood': ('prop_driftwood_a', 100, 0.08),
    'campfire': ('life_campfire', 110, null),
    'menhirs': ('life_menhirs', 180, 0.1),
    'columns': ('life_ruin_columns', 180, 0.1),
    'tower': ('life_ruin_tower', 150, 0.1),
    'arch': ('life_ruin_arch', 170, 0.1),
    'well': ('life_well', 110, 0.08),
    'crow': ('life_crow_up_se', 60, null),
    'duck': ('life_duck_se', 60, null),
    'crab': ('life_crab', 50, null),
  };

  static Future<_SceneArt?> load() => _pending ??= _build();

  static Future<ui.Image> _decode(String asset, {int? width}) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<_SceneArt?> _build() async {
    try {
      final tiles = <String, ui.Image>{
        for (final t in const ['grass', 'sand', 'water'])
          t: await _decode('assets/images/terrain/${t}_tile.webp', width: 384),
      };
      final props = <String, ui.Image>{};
      final shadows = <String, ui.Image>{};
      for (final e in _files.entries) {
        final (file, width, depth) = e.value;
        final image = await _decode(
          'assets/images/terrain/$file.webp',
          width: width,
        );
        props[e.key] = image;
        if (depth != null) {
          final shadow = await castShadowImage(image, groundDepth: depth);
          if (shadow != null) shadows[e.key] = shadow;
        }
      }
      return cached = _SceneArt(tiles, props, shadows);
    } catch (_) {
      _pending = null;
      return null;
    }
  }
}

/// One placed picture: key, foot x / foot y as fractions of the box, width as a
/// fraction of the box's HEIGHT, mirrored, and whether the type's tint applies.
class _P {
  final String key;
  final double x, y, w;
  final bool flip;
  final bool tint;
  const _P(
    this.key,
    this.x,
    this.y,
    this.w, {
    this.flip = false,
    this.tint = true,
  });
}

class _Look {
  final String ground;
  final Color sky; // plain colour while the art loads
  final ColorFilter? groundFilter;
  final ColorFilter? propFilter;
  final List<_P> props;
  const _Look(
    this.ground,
    this.sky,
    this.groundFilter,
    this.propFilter,
    this.props,
  );
}

ColorFilter _mul(int argb) => ColorFilter.mode(Color(argb), BlendMode.modulate);
ColorFilter _screen(int argb) =>
    ColorFilter.mode(Color(argb), BlendMode.screen);
ColorFilter _over(int argb) => ColorFilter.mode(Color(argb), BlendMode.srcATop);

// Restrained on purpose (user 2026-11-10: "die Szenen sind etwas zu
// übertrieben"): two or three small pieces at the very edges, the type's tint
// only a hint, and the weather a few specks — the monster is the picture.
final Map<CreatureElement, _Look> _looks = {
  CreatureElement.plant: const _Look('grass', Color(0xFF3E8A4E), null, null, [
    _P('tree_b_s', 0.06, 0.58, 0.40),
    _P('bush_a', 0.94, 0.97, 0.16),
    _P('flowers_b', 0.07, 0.98, 0.13),
  ]),
  CreatureElement.water: const _Look('water', Color(0xFF1B7FA6), null, null, [
    _P('reeds', 0.06, 0.82, 0.22),
    _P('reeds', 0.95, 0.80, 0.20, flip: true),
    _P('shell', 0.90, 0.98, 0.07, tint: false),
  ]),
  CreatureElement.ice: _Look(
    'water',
    const Color(0xFF9ADCF4),
    _screen(0x66E4F6FF),
    _over(0x40F2FAFF),
    const [_P('tree_c_s', 0.06, 0.58, 0.40), _P('stone_b', 0.94, 0.98, 0.14)],
  ),
  CreatureElement.fire: _Look(
    'sand',
    const Color(0xFF8A2A10),
    _mul(0xFFF0A070),
    _mul(0xFFD8B09A),
    const [
      _P('campfire', 0.10, 0.90, 0.24, tint: false),
      _P('stone_d', 0.94, 0.97, 0.16),
    ],
  ),
  CreatureElement.stone: _Look(
    'sand',
    const Color(0xFF7A6A55),
    _mul(0xFFD0CCC4),
    _mul(0xFFE6E2DC),
    const [_P('menhirs', 0.12, 0.62, 0.38), _P('stone_c', 0.94, 0.98, 0.16)],
  ),
  CreatureElement.light: _Look(
    'grass',
    const Color(0xFFCDB45A),
    _screen(0x33FFF0A0),
    _screen(0x1AFFF0B0),
    const [_P('arch', 0.90, 0.64, 0.40), _P('flowers_a', 0.07, 0.98, 0.15)],
  ),
  CreatureElement.shadow: _Look(
    'grass',
    const Color(0xFF3A2D5C),
    _mul(0xFF9486B8),
    _mul(0xFFA090C0),
    const [
      _P('tower', 0.90, 0.64, 0.40, flip: true),
      _P('stump', 0.07, 0.97, 0.12),
    ],
  ),
  CreatureElement.lightning: _Look(
    'grass',
    const Color(0xFF3A3F8A),
    _mul(0xFFA0AADC),
    _mul(0xFFB8BEE4),
    const [_P('menhirs', 0.12, 0.62, 0.38), _P('stone_b', 0.94, 0.98, 0.14)],
  ),
  CreatureElement.neutral: const _Look('grass', Color(0xFF59647A), null, null, [
    _P('bush_a', 0.06, 0.97, 0.16),
    _P('stone_b', 0.94, 0.98, 0.14),
  ]),
};

class _ScenePainter extends CustomPainter {
  final CreatureElement element;
  final _SceneArt? art;
  const _ScenePainter(this.element, this.art);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final look = _looks[element]!;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    final a = art;
    if (a == null) {
      canvas.drawRect(rect, Paint()..color = look.sky);
      canvas.restore();
      return;
    }

    ImageShader tileShader(ui.Image tile) {
      // One swatch is about 96 px across, whatever it was decoded at.
      final k = 96 / tile.width;
      return ImageShader(
        tile,
        TileMode.mirror,
        TileMode.mirror,
        Matrix4.diagonal3Values(k, k, 1).storage,
      );
    }

    // ── Ground ────────────────────────────────────────────────
    canvas.drawRect(
      rect,
      Paint()
        ..shader = tileShader(a.tiles[look.ground]!)
        ..colorFilter = look.groundFilter,
    );
    // A water scene gets a sandy beach along the bottom, with a ragged edge.
    if (element == CreatureElement.water) {
      final sand = Paint()..shader = tileShader(a.tiles['sand']!);
      const step = 7.0;
      var i = 0;
      for (var x = 0.0; x < w; x += step) {
        final edge = h * 0.80 + ((i * 5) % 3) * 3.0;
        canvas.drawRect(Rect.fromLTRB(x, edge, x + step, h), sand);
        canvas.drawRect(
          Rect.fromLTWH(x, edge - 2, step, 2),
          Paint()..color = const Color(0x66FFFFFF),
        );
        i++;
      }
    }

    // ── Props, shadows first, back to front ───────────────────
    final order = [...look.props]..sort((p, q) => p.y.compareTo(q.y));
    final shadowPaint = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(
        kShadowTint.withValues(alpha: kShadowOpacity),
        BlendMode.srcIn,
      );
    for (final p in order) {
      final mask = a.shadows[p.key];
      final image = a.props[p.key];
      if (mask == null || image == null) continue;
      _draw(canvas, mask, image, p, w, h, shadowPaint);
    }
    for (final p in order) {
      final image = a.props[p.key];
      if (image == null) continue;
      final paint = Paint()..filterQuality = FilterQuality.medium;
      if (p.tint) paint.colorFilter = look.propFilter;
      _draw(canvas, image, image, p, w, h, paint);
    }

    _weather(canvas, w, h);

    // A soft shade at the top so the level and gender badges always read.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.35),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h * 0.35), const [
          Color(0x66000000),
          Color(0x00000000),
        ]),
    );
    canvas.restore();
  }

  void _draw(
    Canvas canvas,
    ui.Image picture,
    ui.Image prop,
    _P p,
    double w,
    double h,
    Paint paint,
  ) {
    final destW = p.w * h;
    final unit = destW / prop.width;
    final foot = Offset(p.x * w, p.y * h);
    final dest = Rect.fromLTWH(
      foot.dx - destW / 2,
      foot.dy - prop.height * unit,
      picture.width * unit,
      picture.height * unit,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      picture.width.toDouble(),
      picture.height.toDouble(),
    );
    if (!p.flip) {
      canvas.drawImageRect(picture, src, dest, paint);
    } else {
      canvas.save();
      canvas.translate(foot.dx, 0);
      canvas.scale(-1, 1);
      canvas.translate(-foot.dx, 0);
      canvas.drawImageRect(picture, src, dest, paint);
      canvas.restore();
    }
  }

  /// The type's weather, over everything — only a few specks and one faint wash.
  void _weather(Canvas canvas, double w, double h) {
    final rnd = math.Random(element.index * 53 + 7);
    final b = math.max(2.0, (w / 48).roundToDouble()); // one speck
    void speck(double x, double y, Color c) => canvas.drawRect(
      Rect.fromLTWH(x.floorToDouble(), y.floorToDouble(), b, b),
      Paint()..color = c,
    );
    void scatter(int n, double top, double bottom, List<Color> cols) {
      for (var i = 0; i < n; i++) {
        speck(
          rnd.nextDouble() * w,
          top * h + rnd.nextDouble() * (bottom - top) * h,
          cols[rnd.nextInt(cols.length)],
        );
      }
    }

    void wash(double from, double to, Color c0, Color c1) {
      final r = Rect.fromLTRB(0, from * h, w, to * h);
      canvas.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [c0, c1]),
      );
    }

    switch (element) {
      case CreatureElement.water:
        scatter(5, 0.0, 0.7, const [Color(0x88FFFFFF), Color(0x44FFFFFF)]);
      case CreatureElement.ice:
        scatter(9, 0.0, 0.9, const [Color(0xCCFFFFFF), Color(0x88FFFFFF)]);
      case CreatureElement.fire:
        wash(0.65, 1.0, const Color(0x00FF6A1A), const Color(0x33FF6A1A));
        scatter(7, 0.1, 0.8, const [Color(0xFFFFC85A), Color(0xAAFF8A2A)]);
      case CreatureElement.plant:
        scatter(5, 0.05, 0.7, const [Color(0xAAEFFFD0), Color(0xAAFFF3A0)]);
      case CreatureElement.lightning:
        wash(0.0, 0.4, const Color(0x55120E3A), const Color(0x00120E3A));
        scatter(5, 0.05, 0.6, const [Color(0xFFFFE66D), Color(0xAAFFFFFF)]);
      case CreatureElement.stone:
        scatter(5, 0.3, 1.0, const [Color(0x44FFFFFF)]);
      case CreatureElement.light:
        wash(0.0, 0.5, const Color(0x33FFFFFF), const Color(0x00FFFFFF));
        for (final p in const [
          [0.14, 0.22],
          [0.84, 0.30],
        ]) {
          final x = p[0] * w, y = p[1] * h;
          final c = Paint()..color = const Color(0xCCFFFFFF);
          canvas.drawRect(Rect.fromLTWH(x, y - b, b, b * 3), c);
          canvas.drawRect(Rect.fromLTWH(x - b, y, b * 3, b), c);
        }
      case CreatureElement.shadow:
        wash(0.0, 1.0, const Color(0x1A140A2C), const Color(0x44140A2C));
        scatter(5, 0.0, 0.5, const [Color(0x88FFFFFF), Color(0x55E0D0FF)]);
      case CreatureElement.neutral:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.art != art || old.element != element;
}
