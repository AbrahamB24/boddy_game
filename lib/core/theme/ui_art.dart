import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── RENDERED INTERFACE PIECES ───────────────────────────────────────────────
//
// User 2026-11-04, showing a painted concept of the whole main screen
// ("schaffst du es, genau dieses Interface 1:1 nachzubauen mit dem genau
// gleichen Detaillierungsgrad?") and choosing the Blender route: the parts a
// vector painter cannot do — brass bell, iron buttons, the compass and the
// stone frame, parchment, the iron energy housing — are RENDERED, once, by
// tool/blender/make_ui.py into assets/images/ui/, and laid out here. The numbers
// and texts stay live widgets on top of them.
//
// Source sizes (px) of the pictures, for the nine-slices below:
//   frame 900x442 · parchment 900x83 · energy 900x223 · bell 900x530
//   button / compass / emblem 900x900 · scroll 900x550

abstract final class UiArt {
  static const String _dir = 'assets/images/ui/';
  static const String frame = '${_dir}frame.webp';
  static const String parchment = '${_dir}parchment.webp';
  static const String energy = '${_dir}energy.webp';
  static const String bell = '${_dir}bell.webp';
  static const String button = '${_dir}button.webp';
  static const String compass = '${_dir}compass.webp';
  static const String globe = '${_dir}globe.webp';
  static const String chest = '${_dir}chest.webp';
  static const String plaque = '${_dir}plaque_wood.webp';
  static const String bar = '${_dir}bar.webp';
  static const String divider = '${_dir}divider.webp';
  static const String badgeBolt = '${_dir}badge_bolt.webp';
  static const String badgeKnot = '${_dir}badge_knot.webp';

  /// The voxel glyphs ALONE, no ring and no dish (user 2026-11-05): they sit on
  /// the Flutter-drawn [WoodBoard]s. Rendered by make_ui4.py (`*_bare`).
  static const String chestBare = '${_dir}chest_bare.webp';
  static const String compassBare = '${_dir}compass_bare.webp';
  static const String badgeBoltBare = '${_dir}badge_bolt_bare.webp';
  static const String badgeKnotBare = '${_dir}badge_knot_bare.webp';
  static const String scroll = '${_dir}scroll.webp';

  /// The 3D glyph for a quick button, by its label; null where there is none.
  static String? iconFor(String label) => switch (label) {
    'Build' => '${_dir}icon_hammer.webp',
    'Monsters' => '${_dir}icon_paw.webp',
    'Map' => '${_dir}icon_map.webp',
    'Social' => '${_dir}icon_people.webp',
    'Profile' => '${_dir}icon_person.webp',
    'Bag' => '${_dir}icon_bag.webp',
    'Daily tasks' => '${_dir}icon_tasks.webp',
    _ => null,
  };

  /// Brown ink and its quieter weight, for text on the parchment.
  static const Color ink = Color(0xFF3B2814);
  static const Color inkSoft = Color(0xFF6E5636);
  static const Color warn = Color(0xFFA8281F);

  /// Light parchment and its wooden rim, for the resource plaques.
  static const Color plaqueLight = Color(0xFFF2E6C4);
  static const Color plaqueDark = Color(0xFFDFCB98);
  static const Color plaqueRim = Color(0xFF7A4E26);

  /// How thick the stone frame is on screen.
  static const double frameEdge = 22;

  /// Decode width per picture. The sources are 900-2400 px but most are drawn
  /// at 30-120 dp; decoding a 900x900 badge costs 3.2 MB of texture, the
  /// 2400x1800 globe 17 MB. The nine-slices (frame, parchment, energy, button,
  /// scroll, bar, plaque) are NOT listed: their corners need the full picture.
  /// One table feeds both the widgets and [precache], so the ImageCache key a
  /// preload files is exactly the one the widget looks up.
  static const Map<String, int> _decodeWidth = {
    globe: 1800, // 8x6 sprite sheet: 225 px per frame
    badgeBolt: 256,
    badgeKnot: 256,
    badgeBoltBare: 256,
    badgeKnotBare: 256,
    chestBare: 512,
    compassBare: 512,
    bell: 512,
    divider: 64,
  };

  /// The `cacheWidth` to hand an [Image] showing [asset] (null = full size).
  static int? decodeWidth(String asset) => _decodeWidth[asset];

  /// The provider for [asset] at its capped decode size.
  static ImageProvider provider(String asset) => ResizeImage.resizeIfNeeded(
    decodeWidth(asset),
    null,
    AssetImage(asset),
  );

  static Future<void> precache(BuildContext context) => Future.wait([
    for (final a in [
      frame,
      parchment,
      energy,
      bell,
      button,
      compass,
      globe,
      chest,
      plaque,
      bar,
      divider,
      badgeBolt,
      badgeKnot,
      chestBare,
      compassBare,
      badgeBoltBare,
      badgeKnotBare,
      scroll,
      for (final l in [
        'Build',
        'Monsters',
        'Map',
        'Social',
        'Profile',
        'Bag',
        'Daily tasks',
      ])
        iconFor(l)!,
    ])
      precacheImage(provider(a), context),
  ]);
}

/// A nine-patch picture, drawn at 1/[scale] of its pixel size. Flutter's own
/// nine-slice ignores `scale` for the corners, so the whole thing is laid out
/// at [scale] times the size it is wanted and painted back down: the corners
/// keep the picture's full resolution and come out at slice / scale logical
/// pixels.
class _NineBg extends StatelessWidget {
  final String asset;
  final Rect slice;
  final double scale;

  const _NineBg({
    required this.asset,
    required this.slice,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        width: w,
        height: h,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: w * scale,
          maxWidth: w * scale,
          minHeight: h * scale,
          maxHeight: h * scale,
          child: Transform.scale(
            scale: 1 / scale,
            alignment: Alignment.topLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(asset),
                  fit: BoxFit.fill,
                  centerSlice: slice,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    },
  );
}

/// The stone frame round the whole main screen. Paints only; wrap it in an
/// [IgnorePointer]. The picture's middle is empty, so the map shows through.
class UiFrame extends StatelessWidget {
  const UiFrame({super.key});

  @override
  Widget build(BuildContext context) => const _NineBg(
    asset: UiArt.frame,
    slice: Rect.fromLTRB(51, 51, 849, 391),
    scale: 51 / UiArt.frameEdge,
  );
}

/// THE HEADER BAR (user 2026-11-05: "ein verbundener Balken, damit alle die
/// gleiche Form haben"): one continuous timber beam with bronze corner caps and a
/// light wooden panel, stretched to its child. Every cell of the header sits in
/// it, so they all share one shape; the chest hangs in the middle.
class UiBar extends StatelessWidget {
  final Widget child;
  const UiBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: _NineBg(
          asset: UiArt.bar,
          // bar.webp is 900 x 484: a timber frame under a tiled eave round a
          // plaster panel (rows 208-413, columns 103-813).
          slice: Rect.fromLTRB(116, 202, 796, 404),
          scale: 6.7,
        ),
      ),
      child,
    ],
  );
}

// ── The menu screens in the main screen's timber (user 2026-11-05: "gestalte den
// Monsterscreen mit allen Elementen so um, dass es optisch zum Hauptscreen
// passt") ──────────────────────────────────────────────────────────────────
//
// The same materials the header bar is made of: walnut planks, terracotta eave,
// plaster plaques with a wooden rim, bronze-studded medals. [MenuScaffold]
// (`timber: true`) assembles them; the pieces are public so a screen's own
// controls can wear them too.

/// Walnut colours, sampled from bar.webp / divider.webp.
abstract final class UiWood {
  static const Color groundTop = Color(0xFF3E2415);
  static const Color groundBottom = Color(0xFF22130A);
  static const Color beamLight = Color(0xFF9A5530);
  static const Color beam = Color(0xFF7A4023);
  static const Color beamDark = Color(0xFF4E2713);
  static const Color well = Color(0xFF2B190D);
  static const Color wellDeep = Color(0xFF1E1109);
  static const Color gold = Color(0xFFE2B53E);
  static const Color goldDeep = Color(0xFF9C7418);
  static const Color glow = Color(0xFFFFD27A);

  /// Text on the dark wood.
  static const Color onWood = Color(0xFFF6EFE0);
  static final Color onWoodSoft = onWood.withValues(alpha: 0.8);
}

/// A light plaster plaque with a wooden rim and a hard shadow: a shortcut, a
/// readout. [lit] gives it a gold rim and a warm glow (something is ready).
BoxDecoration uiPlaque({bool lit = false, double radius = 8}) => BoxDecoration(
  gradient: const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFDBD0B3), Color(0xFFCFC3A3)], // the header plaster
  ),
  borderRadius: BorderRadius.circular(radius >= 8 ? 3 : 2),
  border: Border.all(color: lit ? UiWood.gold : UiArt.plaqueRim, width: 2),
  boxShadow: [
    if (lit)
      BoxShadow(
        color: UiWood.glow.withValues(alpha: 0.55),
        blurRadius: 10,
        spreadRadius: 1,
      ),
    const BoxShadow(color: Color(0xCC140A04), offset: Offset(0, 3)),
  ],
);

/// The ground of a menu screen: dark walnut planks.
class UiGround extends StatelessWidget {
  const UiGround({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _GroundPainter(), size: Size.infinite);
}

class _GroundPainter extends CustomPainter {
  const _GroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    if (!r.isFinite || r.isEmpty) return;
    canvas.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [UiWood.groundTop, UiWood.groundBottom],
        ).createShader(r),
    );
    // Plank seams and a little grain, fixed (never random) so it never shimmers.
    const plank = 46.0;
    final seam = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 2;
    final lit = Paint()
      ..color = const Color(0x14FFD9A8)
      ..strokeWidth = 1;
    var i = 0;
    for (var y = plank; y < size.height; y += plank) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), seam);
      canvas.drawLine(Offset(0, y + 2), Offset(size.width, y + 2), lit);
      // Staggered butt joints.
      final x = ((i * 233) % 340) + 80.0;
      for (var jx = x; jx < size.width; jx += 340) {
        canvas.drawLine(Offset(jx, y - plank), Offset(jx, y), seam);
      }
      i++;
    }
    final grain = Paint()
      ..color = const Color(0x12000000)
      ..strokeWidth = 1;
    for (var y = 7.0; y < size.height; y += 11) {
      final off = (y * 37) % 90;
      for (var x = -off; x < size.width; x += 150) {
        canvas.drawLine(Offset(x, y), Offset(x + 70 + (y % 40), y), grain);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GroundPainter old) => false;
}

/// A recessed board in a walnut frame with gold studs at its corners: the
/// content area of a menu, where the header bar's plaster panel is the title.
class UiBoard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const UiBoard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(10, 8, 8, 8),
  });

  @override
  Widget build(BuildContext context) {
    Widget stud() => Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        color: UiWood.gold,
        boxShadow: [BoxShadow(color: UiWood.goldDeep, offset: Offset(1, 1))],
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [UiWood.beamLight, UiWood.beam, UiWood.beamDark],
                stops: [0, 0.4, 1],
              ),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFF1A0E06), width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0xCC0E0703), offset: Offset(0, 4)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [UiWood.wellDeep, UiWood.well],
                stops: [0, 0.12],
              ),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF140B05), width: 1.5),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
        Positioned(left: 1.5, top: 1.5, child: stud()),
        Positioned(right: 1.5, top: 1.5, child: stud()),
        Positioned(left: 1.5, bottom: 1.5, child: stud()),
        Positioned(right: 1.5, bottom: 1.5, child: stud()),
      ],
    );
  }
}

/// A carved post between two cells of the header bar (picture 386 x 900 px).
class UiDivider extends StatelessWidget {
  const UiDivider({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 9,
    // As tall as the row it stands in (never its picture's own aspect).
    height: double.infinity,
    child: Image.asset(
      UiArt.divider,
      cacheWidth: UiArt.decodeWidth(UiArt.divider),
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    ),
  );
}

/// A small round badge picture (the lightning bolt or the knot beside the chest).
class UiBadge extends StatelessWidget {
  final String asset;
  final double size;
  const UiBadge({super.key, required this.asset, required this.size});

  @override
  Widget build(BuildContext context) => Image.asset(
    asset,
    cacheWidth: UiArt.decodeWidth(asset),
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
  );
}

/// The energy bar's frame of timber beams with wooden pegs, stretched to its
/// child (user 2026-11-04: "aus Holzbalken anstatt Metall"; the class keeps its
/// old name).
class UiIronBar extends StatelessWidget {
  final Widget child;
  const UiIronBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: _NineBg(
          asset: UiArt.energy,
          slice: Rect.fromLTRB(110, 80, 790, 143),
          scale: 5.5,
        ),
      ),
      child,
    ],
  );
}

/// A parchment scroll, rolled and strapped at both ends, stretched to its
/// child: the card behind the floating tag over a building.
class UiScroll extends StatelessWidget {
  final EdgeInsets padding;
  final Widget child;
  const UiScroll({super.key, required this.padding, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned.fill(
        child: _NineBg(
          asset: UiArt.scroll,
          slice: Rect.fromLTRB(135, 60, 765, 490),
          scale: 4.2,
        ),
      ),
      Padding(padding: padding, child: child),
    ],
  );
}

/// TIMBER FOR THE MAIN SCREEN'S UI (user 2026-11-05): the beam browns with the
/// header's grain painted over them. A squared beam with pegs ([round] false) or
/// a round board ([round] true). Used by the header cells, the round quick
/// buttons and the bell's bracket, so all the wood on the screen reads as one.
class WoodBoard extends StatelessWidget {
  final bool round;
  final bool pegs;
  final double radius;
  final Widget? child;

  const WoodBoard({
    super.key,
    this.round = false,
    this.pegs = false,
    this.radius = 7,
    this.child,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: round ? null : BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [UiWood.beamLight, UiWood.beam, UiWood.beamDark],
        stops: [0.0, 0.45, 1.0],
      ),
      border: Border.all(color: const Color(0xFF2E170A), width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x80000000),
          blurRadius: 4,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: CustomPaint(
      painter: WoodGrainPainter(round: round, pegs: pegs, radius: radius),
      child: child,
    ),
  );
}

/// Grain, a lit top edge and (on a beam) two pegs over [WoodBoard]'s colours.
class WoodGrainPainter extends CustomPainter {
  final bool round;
  final bool pegs;
  final double radius;
  const WoodGrainPainter({
    this.round = false,
    this.pegs = false,
    this.radius = 7,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(1);
    canvas.save();
    canvas.clipPath(
      round
          ? (Path()..addOval(inner))
          : (Path()..addRRect(
              RRect.fromRectAndRadius(inner, Radius.circular(radius - 1)),
            )),
    );
    // Long wavy grain lines, dark and light alternating. Fixed phases, so the
    // pattern never flickers on rebuild.
    final lines = (size.height / 5).clamp(4, 12).round();
    for (var i = 0; i < lines; i++) {
      final y = size.height * (0.1 + i * 0.8 / lines);
      final path = Path()..moveTo(0, y);
      for (double x = 0; x <= size.width; x += 6) {
        path.lineTo(x, y + math.sin(x / 17 + i * 1.9) * 1.1);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = i.isEven ? 1.0 : 0.7
          ..color = i.isEven
              ? const Color(0x40240F05)
              : const Color(0x22FFD9A0),
      );
    }
    // A lit edge along the top.
    if (round) {
      canvas.drawArc(
        inner.deflate(2),
        math.pi * 1.15,
        math.pi * 0.7,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x66FFE0B0),
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, 1.5),
        Paint()..color = const Color(0x55FFE0B0),
      );
    }
    canvas.restore();
    if (pegs && !round) {
      for (final x in [6.0, size.width - 6]) {
        final c = Offset(x, size.height / 2);
        canvas.drawCircle(c, 2.4, Paint()..color = const Color(0xFF2E170A));
        canvas.drawCircle(
          c.translate(-0.4, -0.5),
          1.2,
          Paint()..color = const Color(0xFFC9923F),
        );
      }
    }
  }

  @override
  bool shouldRepaint(WoodGrainPainter old) =>
      old.round != round || old.pegs != pegs || old.radius != radius;
}

/// A round wooden button of [size], with [child] (the glyph) on its board.
/// [lit] adds a warm glow for a button that is open or pressed.
class IronButton extends StatelessWidget {
  final double size;
  final Widget child;
  final bool lit;

  const IronButton({
    super.key,
    required this.size,
    required this.child,
    this.lit = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Positioned.fill(child: WoodBoard(round: true)),
        if (lit)
          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x99FFC060), Color(0x00FFC060)],
              ),
            ),
          ),
        child,
      ],
    ),
  );
}

/// The compass-and-globe button (the main tile of the bottom-left corner). The
/// globe in its middle turns slowly (user 2026-11-05: "lass sich die Erde drehen"):
/// 48 pre-rendered frames in one 8 x 6 sheet (globe.webp), played backwards so the
/// land travels left to right like the real Earth: west to east.
class CompassButton extends StatefulWidget {
  final double size;
  const CompassButton({super.key, required this.size});

  @override
  State<CompassButton> createState() => _CompassButtonState();
}

class _CompassButtonState extends State<CompassButton>
    with SingleTickerProviderStateMixin {
  static const int _cols = 8, _rows = 6, _frames = _cols * _rows;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // The picture is rendered in a 2.95-unit window round a 2.3-unit medal, so the
  // rose's tips can reach past the wooden ring: drawn 2.95/2.3 larger than the
  // button, centred, overflowing its box. The globe sheet's frames cover a
  // 0.9-unit window of the same scale.
  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // A timber board like the other buttons, with the voxel compass rose laid
    // over it round the turning globe (user 2026-11-05). The rose's tips reach
    // past the board.
    // Rose and globe 1.4x bigger (user 2026-11-05) so the gold ring now reaches
    // over the timber board's rim.
    // Mock-up 1 (user 2026-11-05): the board is the medal, 1.15 units in radius
    // in the 3.6-unit picture; the gold ring (0.98) sits just inside its rim, the
    // red spikes rise from behind it and the N plate straddles its top.
    final big = size * 3.6 / 2.3;
    final g = size * 0.83;
    final dy = big * 0.0238;
    return SizedBox(
      width: size,
      height: size,
      child: OverflowBox(
        maxWidth: big,
        maxHeight: big,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: const WoodBoard(round: true),
            ),
            // The dark dish the globe sits in, inside the gold ring.
            Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                width: size * 0.78,
                height: size * 0.78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF1C120B),
                ),
              ),
            ),
            Image.asset(
              UiArt.compassBare,
              cacheWidth: UiArt.decodeWidth(UiArt.compassBare),
              width: big,
              height: big,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
            Transform.translate(
              offset: Offset(0, dy),
              child: SizedBox(
                width: g,
                height: g,
                child: ClipRect(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final f =
                          (_frames - 1 - (_c.value * _frames).floor()) %
                          _frames;
                      final col = f % _cols, row = f ~/ _cols;
                      return OverflowBox(
                        alignment: Alignment(
                          -1 + 2 * col / (_cols - 1),
                          -1 + 2 * row / (_rows - 1),
                        ),
                        minWidth: g * _cols,
                        maxWidth: g * _cols,
                        minHeight: g * _rows,
                        maxHeight: g * _rows,
                        // The sphere sits low in its frame (centre at 58 % of the
                        // cell's height), so the sheet is lifted by the difference.
                        child: Transform.translate(
                          offset: Offset(0, -g * 0.08),
                          child: Image.asset(
                            UiArt.globe,
                            cacheWidth: UiArt.decodeWidth(UiArt.globe),
                            width: g * _cols,
                            height: g * _rows,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small round timber medal: the voxel picture's inner dish with its glyph
/// (the lightning bolt, the knot) set into a [WoodBoard] (user 2026-11-05: the
/// icons back in voxel look, the circle in timber).
class WoodMedal extends StatelessWidget {
  final String asset;
  final double size;
  const WoodMedal({super.key, required this.asset, required this.size});

  @override
  Widget build(BuildContext context) {
    // The picture's window is 2.3 units round a ring of radius 1: the board is
    // the ring's size (2.0 / 2.3), the glyph keeps the picture's full size.
    final board = size * 2.0 / 2.3;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: board,
            height: board,
            child: const WoodBoard(round: true),
          ),
          Image.asset(
            asset,
            cacheWidth: UiArt.decodeWidth(asset),
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ],
      ),
    );
  }
}

/// The closed treasure chest in the middle of the header: the voxel chest on a
/// round timber board (user 2026-11-05). The widget
/// keeps its square [size], so the medals beside it stay where they were.
class ChestImage extends StatelessWidget {
  final double size;
  const ChestImage({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    final d = size * 0.72;
    // The picture's window is 2.5 units round a medal of radius 1.
    final img = d * 2.5 / 2.0 * 1.04;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              const Positioned.fill(child: WoodBoard(round: true)),
              // Mock-up 1: the dark dish inside the gold ring.
              Center(
                child: Container(
                  width: d * 0.76,
                  height: d * 0.76,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF1C120B),
                  ),
                ),
              ),
              OverflowBox(
                maxWidth: img,
                maxHeight: img,
                child: Image.asset(
                  UiArt.chestBare,
                  cacheWidth: UiArt.decodeWidth(UiArt.chestBare),
                  width: img,
                  height: img,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The carved timber surround of the treasure chest AND both energy bars: one
/// rounded beam that swells into a circle behind the chest, trimmed in brass,
/// with a stud in each corner. Paints beyond the box it is given only by the
/// circle's radius, so give it room (Positioned with negative insets in a
/// non-clipping Stack).
class ChestSurround extends StatelessWidget {
  /// Radius of the circle that swells behind the chest.
  final double bulge;
  const ChestSurround({super.key, required this.bulge});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SurroundPainter(bulge), size: Size.infinite);
}

class _SurroundPainter extends CustomPainter {
  final double bulge;
  const _SurroundPainter(this.bulge);

  @override
  void paint(Canvas canvas, Size size) {
    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(13),
    );
    final disc = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: bulge,
    );
    void both(void Function(Path) draw) {
      draw(Path()..addRRect(bar));
      draw(Path()..addOval(disc));
    }

    final dark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = const Color(0xFF2E170A);
    final brass = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFFD8A53A);
    final shadow = Paint()
      ..color = const Color(0x80000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    both((p) => canvas.drawPath(p.shift(const Offset(0, 3)), shadow));
    both((p) => canvas.drawPath(p, dark));
    both((p) => canvas.drawPath(p, brass));
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [UiWood.beamLight, UiWood.beam, UiWood.beamDark],
        stops: [0.0, 0.45, 1.0],
      ).createShader(Rect.fromLTRB(0, disc.top, 0, disc.bottom));
    both((p) => canvas.drawPath(p, fill));
    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55FFE2A8);
    both((p) => canvas.drawPath(p, lip));
    for (final dx in [9.0, size.width - 9]) {
      for (final dy in [8.0, size.height - 8]) {
        final c = Offset(dx, dy);
        canvas.drawCircle(c, 3.2, Paint()..color = const Color(0xFF2E170A));
        canvas.drawCircle(c, 2.2, Paint()..color = const Color(0xFFE6B94A));
        canvas.drawCircle(
          c.translate(-0.6, -0.6),
          0.9,
          Paint()..color = const Color(0xFFFFF0B8),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SurroundPainter old) => old.bulge != bulge;
}

/// One half of the split energy bar (user 2026-11-04): the LEFT half is 0-100 %,
/// the RIGHT half the bonus range from 100 to 125 %. [fraction] is how full this
/// half is; [bonus] fills it cyan instead of amber. [label] is written across it.
class UiEnergyHalf extends StatelessWidget {
  final double fraction;
  final bool bonus;
  final Widget? label;

  const UiEnergyHalf({
    super.key,
    required this.fraction,
    this.bonus = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) => Padding(
    // Slimmer bars in the board (user 2026-11-05: "etwas zu gross, hoch").
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1008),
        borderRadius: BorderRadius.circular(5),
        // Set INTO the timber board: dark rim, a light lip under it.
        border: Border.all(color: const Color(0xFF120A04), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x55FFD9A0), offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The shade the rim casts into the recess.
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xAA000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      // The UI's own palette (user 2026-11-05): warm brass
                      // gold up to 100 %, leaf green for the bonus range.
                      colors: bonus
                          ? const [
                              Color(0xFFD6F08A),
                              Color(0xFF7DB83A),
                              Color(0xFF3F7A1E),
                            ]
                          : const [
                              Color(0xFFFFE08A),
                              Color(0xFFE0A030),
                              Color(0xFF9A5E16),
                            ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
              ),
            ),
            if (label != null) FittedBox(fit: BoxFit.scaleDown, child: label),
          ],
        ),
      ),
    ),
  );
}

class _RectClipper extends CustomClipper<Rect> {
  final Rect rect;
  const _RectClipper(this.rect);

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _RectClipper old) => old.rect != rect;
}

/// The brass bell on an iron strap, hung from a timber block that sits under the
/// header beam (user 2026-11-05: smaller, not from the side edge).
///
/// The bell SWAYS, very slightly (user 2026-11-04: "ganz leicht bewegen"): the
/// one picture is drawn in two clipped pieces — the timber block at the top stands
/// still, the strap and the bell turn about the strap's top.
class UiBell extends StatefulWidget {
  final double width;
  final Widget? badge;

  const UiBell({super.key, this.width = 120, this.badge});

  @override
  State<UiBell> createState() => _UiBellState();
}

class _UiBellState extends State<UiBell> with SingleTickerProviderStateMixin {
  // Where the bell hangs, as a fraction of the picture, and how far it swings.
  static const double _pivotY = 0.03; // the chains' top, at the header
  static const double _swing = 0.04; // radians, about 4 degrees

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 8000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// A pendulum that is nudged now and then rather than a metronome (user
  /// 2026-11-05: "schwingt sehr unnatürlich"): two swings of slightly different
  /// pitch beat against each other under a swell that starts and ends at rest, so
  /// the loop has no seam. [u] is 0..1 over the 8-second cycle.
  double _angle(double u) {
    final swell = math.pow(math.sin(math.pi * u), 1.5).toDouble();
    final s =
        0.65 * math.sin(2 * math.pi * 5 * u) +
        0.35 * math.sin(2 * math.pi * 8 * u + 0.8);
    return _swing * swell * s;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width, h = w * 600 / 403;
    Widget img() => Image.asset(
      UiArt.bell,
      cacheWidth: UiArt.decodeWidth(UiArt.bell),
      width: w,
      height: h,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    // Standing still: the timber block that sits under the header beam; the strap
    // and the bell turn about the strap's top.
    Widget piece(Rect r) => ClipRect(clipper: _RectClipper(r), child: img());
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The bracket it hangs from: a short timber beam in the header's
          // grain, now that the plaster beam above it is gone.
          Positioned(
            left: w * 0.1,
            right: w * 0.1,
            top: -8,
            height: 10,
            child: const WoodBoard(radius: 3, pegs: true),
          ),
          piece(Rect.fromLTRB(0, 0, w, h * _pivotY)),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => Transform.rotate(
                angle: _angle(_c.value),
                alignment: Alignment(0, _pivotY * 2 - 1),
                child: child,
              ),
              child: piece(Rect.fromLTRB(0, h * _pivotY, w, h)),
            ),
          ),
          if (widget.badge != null)
            Positioned(left: w * 0.62, top: h * 0.5, child: widget.badge!),
        ],
      ),
    );
  }
}
