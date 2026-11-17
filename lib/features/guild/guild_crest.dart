import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../social/widgets/social_kit.dart';

// The guild crest: a shape, a pattern in two colours and a symbol. It is stored
// as a handful of small numbers (see [GuildCrest.toJson], migration 0071), so a
// crest is a few bytes and every client draws the same one.

/// The colours a crest can use.
const List<Color> kCrestColors = [
  Color(0xFFC62F2F), // red
  Color(0xFFE8782A), // orange
  Color(0xFFE9B930), // gold
  Color(0xFF4E9B3F), // green
  Color(0xFF2FA39A), // teal
  Color(0xFF2E78C7), // blue
  Color(0xFF243B73), // navy
  Color(0xFF7A4BB0), // purple
  Color(0xFFD9618F), // pink
  Color(0xFFF3EAD3), // cream
  Color(0xFF8A8F98), // grey
  Color(0xFF2B2420), // black
];

const List<String> kCrestShapeNames = ['Shield', 'Round', 'Banner', 'Kite'];
const List<String> kCrestPatternNames = [
  'Plain',
  'Left-right',
  'Top-bottom',
  'Diagonal',
  'Quarters',
  'Stripe',
  'Chevron',
  'Cross',
];
const List<String> kCrestSymbolNames = [
  'Star',
  'Crown',
  'Sword',
  'Tower',
  'Paw',
  'Flame',
  'Leaf',
  'Moon',
  'Heart',
  'Diamond',
  'Bolt',
  'Tree',
];

class GuildCrest {
  final int shape;
  final int pattern;
  final int symbol; // -1 = none
  final int c1; // field
  final int c2; // pattern
  final int c3; // symbol

  const GuildCrest({
    this.shape = 0,
    this.pattern = 1,
    this.symbol = 0,
    this.c1 = 5,
    this.c2 = 6,
    this.c3 = 2,
  });

  /// The same crest for the same name, for a guild that never picked one.
  factory GuildCrest.fromName(String name) {
    final h = name.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7FFFFFFF);
    final c1 = h % kCrestColors.length;
    var c2 = (h ~/ 7) % kCrestColors.length;
    if (c2 == c1) c2 = (c2 + 5) % kCrestColors.length;
    return GuildCrest(
      shape: h % kCrestShapeNames.length,
      pattern: (h ~/ 3) % kCrestPatternNames.length,
      symbol: (h ~/ 5) % kCrestSymbolNames.length,
      c1: c1,
      c2: c2,
      c3: _contrast(c1, c2),
    );
  }

  static int _contrast(int a, int b) {
    // gold or cream or black, whichever differs from both fields
    for (final c in const [2, 9, 11]) {
      if (c != a && c != b) return c;
    }
    return 9;
  }

  factory GuildCrest.random(math.Random r) {
    final c1 = r.nextInt(kCrestColors.length);
    var c2 = r.nextInt(kCrestColors.length);
    if (c2 == c1) c2 = (c2 + 4) % kCrestColors.length;
    return GuildCrest(
      shape: r.nextInt(kCrestShapeNames.length),
      pattern: r.nextInt(kCrestPatternNames.length),
      symbol: r.nextInt(kCrestSymbolNames.length),
      c1: c1,
      c2: c2,
      c3: _contrast(c1, c2),
    );
  }

  factory GuildCrest.fromJson(Object? j, String fallbackName) {
    if (j is! Map) return GuildCrest.fromName(fallbackName);
    int pick(String k, int max, int def, {int min = 0}) {
      final v = (j[k] as num?)?.toInt();
      return v == null || v < min || v >= max ? def : v;
    }

    return GuildCrest(
      shape: pick('s', kCrestShapeNames.length, 0),
      pattern: pick('p', kCrestPatternNames.length, 0),
      symbol: pick('y', kCrestSymbolNames.length, -1, min: -1),
      c1: pick('c1', kCrestColors.length, 5),
      c2: pick('c2', kCrestColors.length, 6),
      c3: pick('c3', kCrestColors.length, 2),
    );
  }

  Map<String, int> toJson() => {
    's': shape,
    'p': pattern,
    'y': symbol,
    'c1': c1,
    'c2': c2,
    'c3': c3,
  };

  GuildCrest copyWith({
    int? shape,
    int? pattern,
    int? symbol,
    int? c1,
    int? c2,
    int? c3,
  }) => GuildCrest(
    shape: shape ?? this.shape,
    pattern: pattern ?? this.pattern,
    symbol: symbol ?? this.symbol,
    c1: c1 ?? this.c1,
    c2: c2 ?? this.c2,
    c3: c3 ?? this.c3,
  );

  @override
  bool operator ==(Object other) =>
      other is GuildCrest &&
      other.shape == shape &&
      other.pattern == pattern &&
      other.symbol == symbol &&
      other.c1 == c1 &&
      other.c2 == c2 &&
      other.c3 == c3;

  @override
  int get hashCode => Object.hash(shape, pattern, symbol, c1, c2, c3);
}

// ── drawing ────────────────────────────────────────────────

const Color _ink = Color(0xFF2B2016);

/// The crest as a widget, [size] wide and a little taller.
class CrestView extends StatelessWidget {
  final GuildCrest crest;
  final double size;

  const CrestView(this.crest, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 1.12),
    painter: _CrestPainter(crest),
  );
}

class _CrestPainter extends CustomPainter {
  final GuildCrest c;
  _CrestPainter(this.c);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final shape = _shapePath(c.shape, w, h);
    final c1 = kCrestColors[c.c1], c2 = kCrestColors[c.c2];

    canvas.save();
    canvas.clipPath(shape);
    canvas.drawRect(Offset.zero & s, Paint()..color = c1);
    final p = Paint()..color = c2;
    switch (c.pattern) {
      case 1:
        canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h), p);
      case 2:
        canvas.drawRect(Rect.fromLTWH(0, h / 2, w, h / 2), p);
      case 3:
        canvas.drawPath(
          Path()
            ..moveTo(w, 0)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          p,
        );
      case 4:
        canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h / 2), p);
        canvas.drawRect(Rect.fromLTWH(0, h / 2, w / 2, h / 2), p);
      case 5:
        canvas.drawRect(Rect.fromLTWH(w * 0.34, 0, w * 0.32, h), p);
      case 6:
        canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.46)
            ..lineTo(w / 2, h * 0.12)
            ..lineTo(w, h * 0.46)
            ..lineTo(w, h * 0.7)
            ..lineTo(w / 2, h * 0.36)
            ..lineTo(0, h * 0.7)
            ..close(),
          p,
        );
      case 7:
        canvas.drawRect(Rect.fromLTWH(w * 0.4, 0, w * 0.2, h), p);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.28, w, h * 0.2), p);
    }
    canvas.restore();

    if (c.symbol >= 0) {
      final box = Rect.fromCenter(
        center: Offset(w / 2, h * 0.47),
        width: w * 0.5,
        height: w * 0.5,
      );
      drawCrestSymbol(canvas, box, c.symbol, kCrestColors[c.c3]);
    }

    // the rim: a dark outline with a thin light line inside it
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * 0.07)
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * 0.1)
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrestPainter o) => o.c != c;
}

Path _shapePath(int shape, double w, double h) {
  final p = Path();
  switch (shape) {
    case 1: // round
      p.addOval(Rect.fromLTWH(w * 0.02, h * 0.07, w * 0.96, h * 0.86));
    case 2: // banner with a notched foot
      p
        ..moveTo(w * 0.04, h * 0.02)
        ..lineTo(w * 0.96, h * 0.02)
        ..lineTo(w * 0.96, h * 0.98)
        ..lineTo(w * 0.5, h * 0.78)
        ..lineTo(w * 0.04, h * 0.98)
        ..close();
    case 3: // kite
      p
        ..moveTo(w * 0.5, h * 0.01)
        ..lineTo(w * 0.98, h * 0.38)
        ..lineTo(w * 0.5, h * 0.99)
        ..lineTo(w * 0.02, h * 0.38)
        ..close();
    default: // heater shield
      p
        ..moveTo(w * 0.04, h * 0.03)
        ..lineTo(w * 0.96, h * 0.03)
        ..lineTo(w * 0.96, h * 0.5)
        ..quadraticBezierTo(w * 0.96, h * 0.82, w * 0.5, h * 0.98)
        ..quadraticBezierTo(w * 0.04, h * 0.82, w * 0.04, h * 0.5)
        ..close();
  }
  return p;
}

/// One of the [kCrestSymbolNames] drawn into [r] — a dark outline first so it
/// reads on any field colour. No path booleans (they fail on the web build).
void drawCrestSymbol(Canvas canvas, Rect r, int index, Color color) {
  final path = _symbolPath(index, r);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, r.width * 0.09)
      ..strokeJoin = StrokeJoin.round
      ..color = _ink,
  );
  canvas.drawPath(path, Paint()..color = color);
  if (index == 4) {
    // paw toes are separate circles, drawn above
  }
}

Path _symbolPath(int i, Rect r) {
  double x(double f) => r.left + r.width * f;
  double y(double f) => r.top + r.height * f;
  final p = Path();
  switch (i) {
    case 0: // star
      final c = r.center;
      for (var k = 0; k < 10; k++) {
        final rad = (k.isEven ? 0.5 : 0.21) * r.width;
        final a = -math.pi / 2 + k * math.pi / 5;
        final pt = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
        k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      p.close();
    case 1: // crown
      p
        ..moveTo(x(0.05), y(0.85))
        ..lineTo(x(0.0), y(0.25))
        ..lineTo(x(0.27), y(0.55))
        ..lineTo(x(0.5), y(0.1))
        ..lineTo(x(0.73), y(0.55))
        ..lineTo(x(1.0), y(0.25))
        ..lineTo(x(0.95), y(0.85))
        ..close();
    case 2: // sword, point up
      p
        ..moveTo(x(0.5), y(0.0))
        ..lineTo(x(0.6), y(0.12))
        ..lineTo(x(0.6), y(0.68))
        ..lineTo(x(0.86), y(0.68))
        ..lineTo(x(0.86), y(0.78))
        ..lineTo(x(0.6), y(0.78))
        ..lineTo(x(0.6), y(0.92))
        ..lineTo(x(0.66), y(1.0))
        ..lineTo(x(0.34), y(1.0))
        ..lineTo(x(0.4), y(0.92))
        ..lineTo(x(0.4), y(0.78))
        ..lineTo(x(0.14), y(0.78))
        ..lineTo(x(0.14), y(0.68))
        ..lineTo(x(0.4), y(0.68))
        ..lineTo(x(0.4), y(0.12))
        ..close();
    case 3: // tower
      p
        ..moveTo(x(0.15), y(0.0))
        ..lineTo(x(0.3), y(0.0))
        ..lineTo(x(0.3), y(0.12))
        ..lineTo(x(0.43), y(0.12))
        ..lineTo(x(0.43), y(0.0))
        ..lineTo(x(0.57), y(0.0))
        ..lineTo(x(0.57), y(0.12))
        ..lineTo(x(0.7), y(0.12))
        ..lineTo(x(0.7), y(0.0))
        ..lineTo(x(0.85), y(0.0))
        ..lineTo(x(0.85), y(0.3))
        ..lineTo(x(0.75), y(0.36))
        ..lineTo(x(0.78), y(1.0))
        ..lineTo(x(0.22), y(1.0))
        ..lineTo(x(0.25), y(0.36))
        ..lineTo(x(0.15), y(0.3))
        ..close();
    case 4: // paw: pad + four toes
      p.addOval(Rect.fromLTWH(x(0.22), y(0.5), r.width * 0.56, r.height * 0.46));
      for (final t in const [
        (0.08, 0.32),
        (0.3, 0.08),
        (0.56, 0.08),
        (0.78, 0.32),
      ]) {
        p.addOval(Rect.fromLTWH(x(t.$1), y(t.$2), r.width * 0.2, r.height * 0.26));
      }
    case 5: // flame
      p
        ..moveTo(x(0.56), y(0.0))
        ..cubicTo(x(0.68), y(0.22), x(0.96), y(0.42), x(0.9), y(0.72))
        ..cubicTo(x(0.85), y(0.95), x(0.64), y(1.0), x(0.5), y(1.0))
        ..cubicTo(x(0.3), y(1.0), x(0.1), y(0.92), x(0.12), y(0.68))
        ..cubicTo(x(0.14), y(0.52), x(0.24), y(0.44), x(0.3), y(0.26))
        ..cubicTo(x(0.4), y(0.34), x(0.42), y(0.42), x(0.44), y(0.5))
        ..cubicTo(x(0.42), y(0.3), x(0.48), y(0.12), x(0.56), y(0.0))
        ..close();
    case 6: // leaf
      p
        ..moveTo(x(0.1), y(0.92))
        ..cubicTo(x(0.0), y(0.4), x(0.4), y(0.04), x(0.94), y(0.06))
        ..cubicTo(x(1.0), y(0.6), x(0.62), y(1.0), x(0.1), y(0.92))
        ..close();
    case 7: // crescent moon
      p
        ..moveTo(x(0.62), y(0.0))
        ..arcToPoint(
          Offset(x(0.62), y(1.0)),
          radius: Radius.circular(r.width * 0.52),
          clockwise: false,
        )
        ..arcToPoint(
          Offset(x(0.62), y(0.0)),
          radius: Radius.circular(r.width * 0.42),
          clockwise: true,
        )
        ..close();
    case 8: // heart
      p
        ..moveTo(x(0.5), y(0.95))
        ..cubicTo(x(-0.15), y(0.5), x(0.12), y(-0.1), x(0.5), y(0.28))
        ..cubicTo(x(0.88), y(-0.1), x(1.15), y(0.5), x(0.5), y(0.95))
        ..close();
    case 9: // diamond
      p
        ..moveTo(x(0.5), y(0.0))
        ..lineTo(x(0.88), y(0.5))
        ..lineTo(x(0.5), y(1.0))
        ..lineTo(x(0.12), y(0.5))
        ..close();
    case 10: // lightning bolt
      p
        ..moveTo(x(0.62), y(0.0))
        ..lineTo(x(0.18), y(0.56))
        ..lineTo(x(0.46), y(0.56))
        ..lineTo(x(0.34), y(1.0))
        ..lineTo(x(0.84), y(0.4))
        ..lineTo(x(0.54), y(0.4))
        ..close();
    default: // tree: two stacked triangles and a trunk
      p
        ..moveTo(x(0.5), y(0.0))
        ..lineTo(x(0.82), y(0.42))
        ..lineTo(x(0.66), y(0.42))
        ..lineTo(x(0.92), y(0.78))
        ..lineTo(x(0.56), y(0.78))
        ..lineTo(x(0.56), y(1.0))
        ..lineTo(x(0.44), y(1.0))
        ..lineTo(x(0.44), y(0.78))
        ..lineTo(x(0.08), y(0.78))
        ..lineTo(x(0.34), y(0.42))
        ..lineTo(x(0.18), y(0.42))
        ..close();
  }
  return p;
}

class _SymbolChipPainter extends CustomPainter {
  final int index;
  final Color color;
  _SymbolChipPainter(this.index, this.color);

  @override
  void paint(Canvas canvas, Size s) => drawCrestSymbol(
    canvas,
    Rect.fromCenter(center: s.center(Offset.zero), width: s.width * 0.62, height: s.height * 0.62),
    index,
    color,
  );

  @override
  bool shouldRepaint(_SymbolChipPainter o) => o.index != index || o.color != color;
}

// ── the creator ────────────────────────────────────────────

/// The crest creator: a big live preview on the left, the choices on the
/// right — shape, pattern, three colours, symbol — and "Surprise me".
class CrestCreator extends StatelessWidget {
  final GuildCrest crest;
  final ValueChanged<GuildCrest> onChanged;

  const CrestCreator({super.key, required this.crest, required this.onChanged});

  Widget _chip({
    required bool on,
    required VoidCallback onTap,
    required Widget child,
    double size = 40,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6, bottom: 6),
    child: Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? CreamPalette.gold.withValues(alpha: 0.45)
              : CreamPalette.tan.withValues(alpha: 0.18),
          borderRadius: vr(9),
          border: Border.all(
            color: on ? CreamPalette.goldDeep : Colors.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
    ),
  );

  Widget _swatches(int selected, ValueChanged<int> pick) => Wrap(
    children: [
      for (var i = 0; i < kCrestColors.length; i++)
        _chip(
          on: i == selected,
          size: 28,
          onTap: () => pick(i),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: kCrestColors[i],
              borderRadius: vr(4),
              border: Border.all(color: _ink.withValues(alpha: 0.6)),
            ),
          ),
        ),
    ],
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 5),
    child: Text(
      t.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 0.9,
        color: kBoxAccent,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          const SizedBox(height: 6),
          CrestView(crest, size: 110),
          const SizedBox(height: 10),
          SocialTileButton(
            'Surprise me',
            height: 28,
            onTap: () => onChanged(GuildCrest.random(math.Random())),
          ),
        ],
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Shape'),
            Wrap(
              children: [
                for (var i = 0; i < kCrestShapeNames.length; i++)
                  _chip(
                    on: i == crest.shape,
                    onTap: () => onChanged(crest.copyWith(shape: i)),
                    child: CrestView(
                      crest.copyWith(shape: i, pattern: 0, symbol: -1),
                      size: 26,
                    ),
                  ),
              ],
            ),
            _label('Pattern'),
            Wrap(
              children: [
                for (var i = 0; i < kCrestPatternNames.length; i++)
                  _chip(
                    on: i == crest.pattern,
                    onTap: () => onChanged(crest.copyWith(pattern: i)),
                    child: CrestView(
                      crest.copyWith(pattern: i, symbol: -1),
                      size: 26,
                    ),
                  ),
              ],
            ),
            _label('Field colour'),
            _swatches(crest.c1, (i) => onChanged(crest.copyWith(c1: i))),
            _label('Pattern colour'),
            _swatches(crest.c2, (i) => onChanged(crest.copyWith(c2: i))),
            _label('Symbol'),
            Wrap(
              children: [
                _chip(
                  on: crest.symbol == -1,
                  onTap: () => onChanged(crest.copyWith(symbol: -1)),
                  child: Text('none', style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft)),
                ),
                for (var i = 0; i < kCrestSymbolNames.length; i++)
                  _chip(
                    on: i == crest.symbol,
                    onTap: () => onChanged(crest.copyWith(symbol: i)),
                    child: CustomPaint(
                      size: const Size(34, 34),
                      painter: _SymbolChipPainter(i, kCrestColors[crest.c3]),
                    ),
                  ),
              ],
            ),
            _label('Symbol colour'),
            _swatches(crest.c3, (i) => onChanged(crest.copyWith(c3: i))),
          ],
        ),
      ),
    ],
  );
}
