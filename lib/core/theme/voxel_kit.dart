import 'dart:math' as math;

import 'package:flutter/material.dart';

/// THE VOXEL UI KIT — a screen drawn the way a block model is built.
///
/// Everything here is made of the same few moves: squares with their corners
/// cut off one block deep, a lit top-left edge and a shaded bottom-right edge
/// on every piece, a hard dark outline, a hard offset shadow (never a blur),
/// bars cut into whole blocks, icons drawn on a coarse pixel grid and a pixel
/// face for the text. The creature art next to it is rendered from the same
/// kind of blocks (tool/blender/monster_voxel.py), so the page and the monster
/// read as one object.
///
/// Used by the monster detail screen for species that have voxel art; nothing
/// else in the app depends on it.
abstract final class Voxel {
  static const String font = 'Jersey10';

  /// One "block" of UI, in logical pixels. Corners, outlines and bevels are
  /// multiples of it.
  static const double unit = 2;

  static const Color outline = Color(0xFF0B1E27);

  /// A text style in the pixel face. [weight] 700 uses the bold cut.
  static TextStyle text({
    double size = 11,
    Color color = Colors.white,
    bool bold = false,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: font,
    fontSize: size,
    color: color,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    letterSpacing: spacing,
    height: 1.15,
  );

  /// The element colour pushed to a flat block palette: [i] 0 = deepest, 4 =
  /// lightest. Same hue, stepped lightness — no gradients.
  static Color tone(Color base, int i) => switch (i) {
    0 => Color.lerp(base, Colors.black, 0.62)!,
    1 => Color.lerp(base, Colors.black, 0.42)!,
    2 => Color.lerp(base, Colors.black, 0.22)!,
    3 => base,
    _ => Color.lerp(base, Colors.white, 0.45)!,
  };
}

/// The corner radius for anything that still needs a [BorderRadius] (a clip, an
/// InkWell, a BoxDecoration): a pixel or two instead of a curve, so even the
/// places that cannot take a [VoxelShape] read as square blocks. Drop-in for
/// BorderRadius.circular(r).
BorderRadius vr(double r) => BorderRadius.circular(r >= 18 ? 4 : (r >= 8 ? 3 : 2));

/// A rectangle whose corners are cut in whole blocks (a stair of [notch]
/// blocks), with a bevel and an outline drawn in [paint].
///
/// It is a [ShapeBorder], so it drops in wherever the app used
/// `FoE.facet(...)`: `ShapeDecoration(color: …, shape: VoxelShape())` fills
/// the stepped outline and this class adds the block edges on top.
class VoxelShape extends OutlinedBorder {
  /// Corner steps. 1 = a single cut pixel, 2 = a two-step stair.
  final int notch;

  /// Draw the lit/shaded bevel strips.
  final bool bevel;

  /// A different outline colour (e.g. a selected state); null = [Voxel.outline].
  final Color? edge;

  /// Outline thickness in blocks.
  final double lines;

  const VoxelShape({
    this.notch = 2,
    this.bevel = true,
    this.edge,
    this.lines = 1,
  });

  double get _n => notch * Voxel.unit;

  @override
  // Layout-neutral on purpose: the outline is painted INSIDE the box, so a
  // swap from a round corner to a block corner never moves content.
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) =>
      VoxelShape(notch: notch, bevel: bevel, edge: edge, lines: lines);

  // The outline is part of the shape (see [paint]); a Material side is
  // accepted and ignored.
  @override
  OutlinedBorder copyWith({BorderSide? side}) => this;

  Path _stair(Rect r, double inset) {
    final n = _n;
    final x0 = r.left + inset, x1 = r.right - inset;
    final y0 = r.top + inset, y1 = r.bottom - inset;
    final steps = notch;
    final s = Voxel.unit;
    final p = Path()..moveTo(x0, y0 + n);
    // top-left stair
    for (var i = 0; i < steps; i++) {
      p
        ..lineTo(x0 + i * s, y0 + n - i * s)
        ..lineTo(x0 + i * s, y0 + n - (i + 1) * s)
        ..lineTo(x0 + (i + 1) * s, y0 + n - (i + 1) * s);
    }
    p.lineTo(x0 + n, y0);
    p.lineTo(x1 - n, y0);
    for (var i = 0; i < steps; i++) {
      p
        ..lineTo(x1 - n + (i + 1) * s, y0 + i * s)
        ..lineTo(x1 - n + (i + 1) * s, y0 + (i + 1) * s);
    }
    p.lineTo(x1, y0 + n);
    p.lineTo(x1, y1 - n);
    for (var i = 0; i < steps; i++) {
      p
        ..lineTo(x1 - i * s, y1 - n + (i + 1) * s)
        ..lineTo(x1 - (i + 1) * s, y1 - n + (i + 1) * s);
    }
    p.lineTo(x1 - n, y1);
    p.lineTo(x0 + n, y1);
    for (var i = 0; i < steps; i++) {
      p
        ..lineTo(x0 + n - (i + 1) * s, y1 - i * s)
        ..lineTo(x0 + n - (i + 1) * s, y1 - (i + 1) * s);
    }
    p.lineTo(x0, y1 - n);
    p.close();
    return p;
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _stair(rect, lines * Voxel.unit);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _stair(rect, 0);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final w = lines * Voxel.unit;
    final inner = _stair(rect, w);
    // The outline is a stroke along the stair, half a line inside the edge.
    // (Not Path.combine(difference): that silently returns the whole outer
    // path on this Flutter web build and paints the card solid.)
    canvas.drawPath(
      _stair(rect, w / 2),
      Paint()
        ..color = edge ?? Voxel.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeJoin = StrokeJoin.miter
        ..isAntiAlias = false,
    );
    if (!bevel) return;
    final b = Voxel.unit * 2;
    final clip = inner;
    canvas.save();
    canvas.clipPath(clip);
    final r = rect.deflate(w);
    // lit top and left strips, shaded bottom and right strips
    final light = Paint()..color = const Color(0x2EFFFFFF);
    final dark = Paint()..color = const Color(0x38000000);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, r.width, b), light);
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, b, r.height), light);
    canvas.drawRect(Rect.fromLTWH(r.left, r.bottom - b, r.width, b), dark);
    canvas.drawRect(Rect.fromLTWH(r.right - b, r.top, b, r.height), dark);
    canvas.restore();
  }

  @override
  bool operator ==(Object other) =>
      other is VoxelShape &&
      other.notch == notch &&
      other.bevel == bevel &&
      other.edge == edge &&
      other.lines == lines;

  @override
  int get hashCode => Object.hash(notch, bevel, edge, lines);
}

/// The hard offset shadow a block casts: one solid slab, no blur.
List<BoxShadow> voxelDrop({double depth = 3, Color? color}) => [
  BoxShadow(
    color: color ?? const Color(0x73000000),
    offset: Offset(depth, depth),
    blurRadius: 0,
  ),
];

/// A bar cut into whole blocks: filled blocks lit and bevelled, empty blocks a
/// dark socket. The last partly-filled block shows as a half block.
class VoxelBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  /// Target block width; the bar picks a whole number of blocks to fit.
  final double block;

  /// On a dark plate the empty sockets are lighter than the plate; on paper
  /// they are darker.
  final bool onDark;

  const VoxelBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 12,
    this.block = 9,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _VoxelBarPainter(value.clamp(0.0, 1.0), color, block, onDark),
    ),
  );
}

class _VoxelBarPainter extends CustomPainter {
  final double v;
  final Color color;
  final double block;
  final bool onDark;
  _VoxelBarPainter(this.v, this.color, this.block, this.onDark);

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.max(3, (size.width / block).floor());
    const gap = 2.0;
    final w = (size.width - gap * (n - 1)) / n;
    final filled = v * n;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final r = Rect.fromLTWH(x, 0, w, size.height);
      canvas.drawRect(
        r,
        Paint()
          ..color = onDark
              ? const Color(0x33FFFFFF)
              : const Color(0x522B1810),
      );
      canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, 1.5),
        Paint()..color = const Color(0x40000000),
      );
      final f = (filled - i).clamp(0.0, 1.0);
      if (f <= 0) continue;
      final fr = Rect.fromLTWH(x, 0, w * (f >= 0.5 ? 1 : 0.5), size.height);
      canvas.drawRect(fr, Paint()..color = color);
      // lit top strip, shaded bottom strip
      canvas.drawRect(
        Rect.fromLTWH(fr.left, fr.top, fr.width, size.height * 0.28),
        Paint()..color = Color.lerp(color, Colors.white, 0.45)!,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          fr.left,
          fr.bottom - size.height * 0.22,
          fr.width,
          size.height * 0.22,
        ),
        Paint()..color = Color.lerp(color, Colors.black, 0.35)!,
      );
    }
  }

  @override
  bool shouldRepaint(_VoxelBarPainter o) =>
      o.v != v || o.color != color || o.block != block || o.onDark != onDark;
}

/// The page behind: flat square blocks in the element's hue with a stable,
/// uneven brightness (so it reads as a wall of blocks, not a texture), darker
/// toward the edges.
class VoxelBackdrop extends StatelessWidget {
  final Color color;
  const VoxelBackdrop({super.key, required this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _BackdropPainter(color), size: Size.infinite);
}

class _BackdropPainter extends CustomPainter {
  final Color color;
  _BackdropPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 26.0;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        // a stable hash: no randomness between frames
        final h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF;
        final jitter = (h % 5) / 4.0; // 0..1 in 5 steps
        final edge = math.min(
          math.min(x, cols - 1 - x) / 4.0,
          math.min(y, rows - 1 - y) / 3.0,
        ).clamp(0.0, 1.0);
        final base = Color.lerp(color, Colors.black, 0.46 - 0.10 * jitter)!;
        final c = Color.lerp(Colors.black, base, 0.55 + 0.45 * edge)!;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          Paint()..color = c,
        );
        // the lit top-left edge of each block
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, 2),
          Paint()..color = const Color(0x14FFFFFF),
        );
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, 2, cell),
          Paint()..color = const Color(0x0DFFFFFF),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter o) => o.color != color;
}

/// Pixel-grid icons for the tab rail and small marks. Each is a string bitmap:
/// `#` = block, `.` = empty, drawn in one colour.
enum VoxelGlyph { heart, bars, dna, sword, arrowUp, edit, back, close }

const Map<VoxelGlyph, List<String>> _glyphBits = {
  VoxelGlyph.heart: [
    '.##..##.',
    '########',
    '########',
    '########',
    '.######.',
    '..####..',
    '...##...',
    '........',
  ],
  VoxelGlyph.bars: [
    '......##',
    '......##',
    '...#..##',
    '...#..##',
    '##.#..##',
    '##.#..##',
    '##.#..##',
    '########',
  ],
  VoxelGlyph.dna: [
    '##....##',
    '.##..##.',
    '..####..',
    '...##...',
    '..####..',
    '.##..##.',
    '##....##',
    '........',
  ],
  VoxelGlyph.sword: [
    '......##',
    '.....###',
    '....###.',
    '#..###..',
    '.####...',
    '..##....',
    '.####...',
    '##..#...',
  ],
  VoxelGlyph.arrowUp: [
    '...##...',
    '..####..',
    '.######.',
    '########',
    '...##...',
    '...##...',
    '...##...',
    '........',
  ],
  VoxelGlyph.back: [
    '...#....',
    '..##....',
    '.#######',
    '########',
    '.#######',
    '..##....',
    '...#....',
    '........',
  ],
  VoxelGlyph.close: [
    '##....##',
    '###..###',
    '.######.',
    '..####..',
    '..####..',
    '.######.',
    '###..###',
    '##....##',
  ],
  VoxelGlyph.edit: [
    '.....##.',
    '....####',
    '...####.',
    '..####..',
    '.####...',
    '.###....',
    '##......',
    '........',
  ],
};

class VoxelIcon extends StatelessWidget {
  final VoxelGlyph glyph;
  final double size;
  final Color color;

  /// A darker copy offset one block down-right, so the glyph casts its own
  /// block shadow.
  final bool shadow;

  const VoxelIcon(
    this.glyph, {
    super.key,
    this.size = 22,
    this.color = Colors.white,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _GlyphPainter(glyph, color, shadow)),
  );
}

class _GlyphPainter extends CustomPainter {
  final VoxelGlyph glyph;
  final Color color;
  final bool shadow;
  _GlyphPainter(this.glyph, this.color, this.shadow);

  @override
  void paint(Canvas canvas, Size size) {
    final bits = _glyphBits[glyph]!;
    final u = (size.width / 9).floorToDouble().clamp(1.0, 99.0);
    final ox = (size.width - u * 8) / 2;
    final oy = (size.height - u * 8) / 2;
    void draw(Color c, double dx, double dy) {
      final p = Paint()..color = c;
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          if (bits[y][x] == '#') {
            canvas.drawRect(
              Rect.fromLTWH(ox + x * u + dx, oy + y * u + dy, u, u),
              p,
            );
          }
        }
      }
    }

    if (shadow) draw(const Color(0x99000000), u * 0.5, u * 0.5);
    draw(color, 0, 0);
  }

  @override
  bool shouldRepaint(_GlyphPainter o) =>
      o.glyph != glyph || o.color != color || o.shadow != shadow;
}

/// The text scale of the voxel UI: a pixel face is small for its size, and the
/// 8-10 px captions of the old layout (column heads, "Locked", "LENGTH") fall
/// apart in it. Everything steps up by a fifth, and nothing is drawn below
/// [floor] logical pixels, however small the code asked for.
class VoxelTextScaler extends TextScaler {
  const VoxelTextScaler({this.factor = 1.1, this.floor = 11.5});

  final double factor;
  final double floor;

  @override
  double scale(double fontSize) {
    final up = fontSize * factor;
    return up < floor ? floor : up;
  }

  @override
  double get textScaleFactor => factor;

  @override
  bool operator ==(Object other) =>
      other is VoxelTextScaler && other.factor == factor && other.floor == floor;

  @override
  int get hashCode => Object.hash(factor, floor);
}
