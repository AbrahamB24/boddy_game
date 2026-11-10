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

  /// THE PIXEL-WOOD HUD (user 2026-11-08): the settlement screen's boards, medals
  /// and glyphs as small hard-edged pixel art on plaster-and-timber, in the
  /// colours of the buildings, instead of the smooth steel-blue set. false
  /// brings the old look back — nothing else needs to change. Only the HUD's
  /// own (voxel) boards are affected; every other screen keeps its smooth rim.
  static const bool pixelWood = true;

  /// Where the pixelated copy of a HUD glyph lives (see tool/pixel/pixelate.js).
  static String px(String name) => 'assets/images/ui_px/$name.png';

  /// A pixelated glyph, every source pixel [PxArt.pixel] logical px wide, never
  /// smoothed. The files are tiny; the size comes from the picture itself.
  static Widget pxImage(String name) => Image.asset(
    px(name),
    scale: 1 / PxArt.pixel,
    filterQuality: FilterQuality.none,
    isAntiAlias: false,
    gaplessPlayback: true,
  );

  /// Ink for text that sits on the plaster boards.
  static const Color pxInk = Color(0xFF452714);
  static const Color pxInkSoft = Color(0xFF6A4A30);
  static const Color pxGood = Color(0xFF376135);
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

  /// The settings medal's real gear (user 2026-11-07, matching the reference
  /// image): [badgeKnot] was never a gear — a decorative three-ring knot that
  /// only ever stood in for it. Rendered by make_ui7.py.
  static const String badgeGear = '${_dir}badge_gear.webp';
  static const String badgeGearBare = '${_dir}badge_gear_bare.webp';

  /// The voxel glyphs ALONE, no ring and no dish (user 2026-11-05): they sit on
  /// the Flutter-drawn [WoodBoard]s. Rendered by make_ui4.py (`*_bare`).
  static const String chestBare = '${_dir}chest_nr.webp';
  static const String compassBare = '${_dir}compass_nr.webp';
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

  /// A finished tab tile (gold plate + slate cap + glyph, one picture) for the
  /// quick buttons that have one (user 2026-11-07); null = use the medal.
  static String? tileFor(String label) => switch (label) {
    'Build' => '${_dir}tab_hammer.webp',
    'Monsters' => '${_dir}tab_paw.webp',
    'Map' => '${_dir}tab_map.webp',
    _ => null,
  };

  /// The voxel glyph a header cell wears for a resource's emoji, where one has
  /// been modelled (user 2026-11-07: icons that match what they stand for).
  static String? hudGlyph(String emoji) => switch (emoji) {
    '🪵' => '${_dir}hud_log.webp',
    '🪨' => '${_dir}hud_stone.webp',
    '🐟' => '${_dir}hud_fish.webp',
    '🪙' => '${_dir}hud_coin.webp',
    '🏠' => '${_dir}hud_house.webp',
    '⏰' => '${_dir}hud_clock.webp',
    _ => null,
  };

  /// The pixelated twin of [hudGlyph], by file name (no extension), or null.
  static String? hudGlyphPx(String emoji) => switch (emoji) {
    '🪵' => 'hud_log',
    '🪨' => 'hud_stone',
    '🐟' => 'hud_fish',
    '🪙' => 'hud_coin',
    '🏠' => 'hud_house',
    '⏰' => 'hud_clock',
    _ => null,
  };

  /// The pixelated twin of [iconFor], by file name (no extension), or null.
  static String? iconPxFor(String label) => switch (label) {
    'Build' => 'icon_hammer',
    'Monsters' => 'icon_paw',
    'Map' => 'icon_map',
    'Social' => 'icon_people',
    'Profile' => 'icon_person',
    'Bag' => 'icon_bag',
    'Daily tasks' => 'icon_tasks',
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
    badgeGear: 256,
    badgeBoltBare: 256,
    badgeKnotBare: 256,
    badgeGearBare: 256,
    chestBare: 512,
    compassBare: 512,
    bell: 512,
    divider: 64,
  };

  /// The `cacheWidth` to hand an [Image] showing [asset] (null = full size).
  static int? decodeWidth(String asset) => _decodeWidth[asset];

  /// The provider for [asset] at its capped decode size.
  static ImageProvider provider(String asset) =>
      ResizeImage.resizeIfNeeded(decodeWidth(asset), null, AssetImage(asset));

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
      badgeGear,
      chestBare,
      compassBare,
      badgeBoltBare,
      badgeKnotBare,
      badgeGearBare,
      scroll,
      for (final l in ['Build', 'Monsters', 'Map']) tileFor(l)!,
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
  // 2026-11-09: no longer walnut. Every screen wears the main screen's blue now,
  // so the pieces that were drawn in wood take the blue family's colours (the
  // names stay, the screens still ask for them).
  static const Color groundTop = Color(0xFF1E5266);
  static const Color groundBottom = Color(0xFF0E2530);
  static const Color beamLight = Color(0xFF4C8CA6);
  static const Color beam = Color(0xFF2C6A80);
  static const Color beamDark = Color(0xFF1B4558);
  static const Color well = Color(0xFF123848);
  static const Color wellDeep = Color(0xFF0B2330);
  static const Color gold = Color(0xFF3FD0D0);
  static const Color goldDeep = Color(0xFF1C8C8C);
  static const Color glow = Color(0xFF9CF4F4);

  /// Text on the dark plates.
  static const Color onWood = Color(0xFFEAF4F8);
  static final Color onWoodSoft = onWood.withValues(alpha: 0.86);
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

/// The pixel-wood palette, sampled from the rendered buildings (roof terracotta,
/// plaster and stone, timber beams, moss): see [UiArt.pixelWood].
abstract final class PxArt {
  /// One art pixel on screen, in logical px. Every edge of the pixel look snaps to it.
  static const double pixel = 2;

  static const Color outline = Color(0xFF2E1A0E);
  static const Color shadow = Color(0x992E1A0E);
  static const Color plasterMid = Color(0xFFB69D78);
  static const Color plasterHi = Color(0xFFBDA680);
  static const Color bevelLight = Color(0xFFE6D6B4);
  static const Color bevelDark = Color(0xFF7E6142);

  /// Rim per tier: light, body, shade. Timber at the ends of the header, aged
  /// brass beside the emblem.
  static const List<List<Color>> rims = [
    [Color(0xFF8A6A44), Color(0xFF5A3A26), Color(0xFF3A2416)],
    [Color(0xFFC4A868), Color(0xFF8A6A3A), Color(0xFF5A3A1E)],
    [Color(0xFFECD9A0), Color(0xFFB08A40), Color(0xFF7A5A22)],
  ];
}

/// STEEL AND METAL FOR THE MAIN SCREEN'S UI (user 2026-11-07, second concept:
/// "die Farben viel kräftiger und fröhlicher"). A bright steel-blue board in a
/// rim of silver, pale gold or gold ([tier] 0, 1, 2). The header runs from silver
/// at both ends to gold at the chest in the middle. A rounded square, or a round
/// board ([round] true). Used by the header cells, the quick buttons, the
/// medals and the bell's bracket, so all the metal on the screen reads as one.
/// (Class name kept from the timber version, which is what it replaced.)
class WoodBoard extends StatelessWidget {
  final bool round;
  final bool pegs;
  final double radius;
  final int tier;
  final Widget? child;

  /// Draws the rim as a pixel-art staircase instead of a smooth arc (user
  /// 2026-11-07, matching the reference image) — opt-in: see [SteelPainter].
  final bool voxel;

  const WoodBoard({
    super.key,
    this.round = false,
    this.pegs = false,
    this.radius = 9,
    this.tier = 2,
    this.child,
    this.voxel = false,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: round ? null : BorderRadius.circular(radius),
      boxShadow: voxel && UiArt.pixelWood
          ? const []
          : const [
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 4,
                offset: Offset(0, 3),
              ),
            ],
    ),
    child: CustomPaint(
      painter: SteelPainter(
        round: round,
        radius: radius,
        tier: tier,
        voxel: voxel,
      ),
      child: child,
    ),
  );
}

/// The rim colours of the three tiers, light edge, body, shade, glint.
const List<List<Color>> kSteelRims = [
  [Color(0xFFFFFFFF), Color(0xFFC7D2E0), Color(0xFF7F8EA3), Color(0xFFEAF0F7)],
  [Color(0xFFFFF6D0), Color(0xFFE8D79A), Color(0xFFA9955A), Color(0xFFFFF0B8)],
  [Color(0xFFFFF0A0), Color(0xFFFFC62E), Color(0xFFD98200), Color(0xFFFFE27A)],
];

/// A pixel-art staircase in place of a smooth arc, for [SteelPainter]'s
/// [SteelPainter.voxel] boards (user 2026-11-07, matching the reference
/// image's stepped corners: "die Ecken als Voxel"). Every step moves by the
/// same [step] in x then y, so the cut reads as a 45° stair, not a circle —
/// that is what the reference's corners actually look like up close.
Path voxelRRect(Rect r, double corner, double step) {
  final n = math.max(1, (corner / step).round());
  final s = corner / n;
  final path = Path()..moveTo(r.left + corner, r.top);
  path.lineTo(r.right - corner, r.top);
  for (var i = 0; i < n; i++) {
    path.lineTo(r.right - corner + (i + 1) * s, r.top + i * s);
    path.lineTo(r.right - corner + (i + 1) * s, r.top + (i + 1) * s);
  }
  path.lineTo(r.right, r.bottom - corner);
  for (var i = 0; i < n; i++) {
    path.lineTo(r.right, r.bottom - corner + (i + 1) * s);
    path.lineTo(r.right - (i + 1) * s, r.bottom - corner + (i + 1) * s);
  }
  path.lineTo(r.left + corner, r.bottom);
  for (var i = 0; i < n; i++) {
    path.lineTo(r.left + corner - (i + 1) * s, r.bottom);
    path.lineTo(r.left + corner - (i + 1) * s, r.bottom - (i + 1) * s);
  }
  path.lineTo(r.left, r.top + corner);
  for (var i = 0; i < n; i++) {
    path.lineTo(r.left, r.top + corner - (i + 1) * s);
    path.lineTo(r.left + (i + 1) * s, r.top + corner - (i + 1) * s);
  }
  path.close();
  return path;
}

/// A pixelated circle: the smooth circle's own outline, sampled and snapped
/// to a [step] grid — the same stepped-rim look as [voxelRRect], for the
/// round boards (chest, compass, the two medals).
Path voxelCircle(Offset center, double r, double step, {int samples = 48}) {
  final pts = <Offset>[
    for (var i = 0; i < samples; i++)
      Offset(
        ((center.dx + r * math.cos(i / samples * math.pi * 2)) / step).round() *
            step,
        ((center.dy + r * math.sin(i / samples * math.pi * 2)) / step).round() *
            step,
      ),
  ];
  final path = Path()..moveTo(pts.first.dx, pts.first.dy);
  for (final p in pts.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// A bright steel-blue board in a metal rim with a lit top edge. [voxel] draws
/// the rim as a pixel-art staircase instead of a smooth arc (user 2026-11-07)
/// — opt-in, so screens outside the settlement HUD keep the plain smooth rim
/// they always had.
class SteelPainter extends CustomPainter {
  final bool round;
  final double radius;
  final int tier;
  final bool rimOnly;
  final bool voxel;
  const SteelPainter({
    this.round = false,
    this.radius = 9,
    this.tier = 2,
    this.rimOnly = false,
    this.voxel = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (voxel && UiArt.pixelWood) {
      _paintPixelWood(canvas, size);
      return;
    }
    final rect = Offset.zero & size;
    final rim = kSteelRims[tier.clamp(0, 2)];
    final w = round ? math.max(3.0, size.shortestSide * 0.075) : 3.0;
    final voxelStep = math.max(3.0, size.shortestSide * 0.045);
    Path shape(Rect r) => voxel
        ? (round
              ? voxelCircle(r.center, r.shortestSide / 2, voxelStep)
              : voxelRRect(r, radius, voxelStep))
        : round
        ? (Path()..addOval(r))
        : (Path()
            ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(radius))));
    if (!rimOnly) {
      canvas.drawPath(
        shape(rect),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Colour-sampled off the reference image itself (user
            // 2026-11-07): its flat cell body measures ~#1B3348 — the old
            // gradient was a bright sky-blue, the first re-dark pass
            // overshot to near-black.
            colors: [Color(0xFF2A4D6E), Color(0xFF1B3348), Color(0xFF112232)],
            stops: [0.0, 0.5, 1.0],
          ).createShader(rect),
      );
      // a soft light across the top half
      canvas.save();
      canvas.clipPath(shape(rect.deflate(w)));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.46),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.46)),
      );
      canvas.restore();
    }
    // the metal rim: a lit edge, a body, a shade underneath
    canvas.drawPath(
      shape(rect.deflate(w / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rim[0], rim[1], rim[2], rim[1], rim[3]],
          stops: const [0.0, 0.3, 0.62, 0.85, 1.0],
        ).createShader(rect),
    );
    canvas.drawPath(
      shape(rect.deflate(w)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66102040),
    );
  }

  /// PIXEL WOOD: a timber (or aged-brass) rim round a plaster body, every edge
  /// on the [PxArt.pixel] grid. Light on the top-left, shade on the bottom-right,
  /// a hard one-pixel outline and a hard shadow under it.
  void _paintPixelWood(Canvas canvas, Size size) {
    const p = PxArt.pixel;
    final rect = Offset.zero & size;
    final c = PxArt.rims[tier.clamp(0, 2)];
    final rw = 2 * p; // rim: two pixels
    final corner = math.min(radius, 3 * p);
    Path shape(Rect r) => round
        ? voxelCircle(r.center, r.shortestSide / 2, p)
        : voxelRRect(r, corner, p);
    final fill = Paint()..isAntiAlias = false;
    if (!rimOnly) {
      // the hard drop shadow
      canvas.drawPath(
        shape(rect).shift(const Offset(0, 1.5 * p)),
        fill..color = PxArt.shadow,
      );
    }
    final rimRect = rect.deflate(p);
    final inner = rimRect.deflate(rw);
    final rimShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c[0], c[1], c[1], c[2]],
      stops: const [0.0, 0.3, 0.6, 1.0],
    ).createShader(rect);
    if (rimOnly) {
      // just the ring: outline, rim, hollow middle
      final ring = Path.combine(
        PathOperation.difference,
        shape(rect),
        shape(inner),
      );
      canvas.drawPath(ring, fill..color = PxArt.outline);
      canvas.drawPath(
        Path.combine(PathOperation.difference, shape(rimRect), shape(inner)),
        Paint()
          ..isAntiAlias = false
          ..shader = rimShader,
      );
      return;
    }
    // outline
    canvas.drawPath(shape(rect), fill..color = PxArt.outline);
    // rim: light top-left, shade bottom-right
    canvas.drawPath(
      shape(rimRect),
      Paint()
        ..isAntiAlias = false
        ..shader = rimShader,
    );
    canvas.drawPath(shape(inner), fill..color = PxArt.outline);
    final body = inner.deflate(p);
    final bodyPath = shape(body);
    canvas.drawPath(bodyPath, fill..color = PxArt.plasterMid);
    canvas.save();
    canvas.clipPath(bodyPath);
    // plank courses: a slightly lighter band every other four pixels
    final band = Paint()
      ..isAntiAlias = false
      ..color = PxArt.plasterHi;
    for (var y = body.top + 3 * p; y < body.bottom; y += 6 * p) {
      canvas.drawRect(Rect.fromLTWH(body.left, y, body.width, 2 * p), band);
    }
    // bevel: light top and left, shade bottom and right, one pixel thick
    final lit = Paint()
      ..isAntiAlias = false
      ..color = PxArt.bevelLight;
    final dim = Paint()
      ..isAntiAlias = false
      ..color = PxArt.bevelDark;
    canvas.drawRect(Rect.fromLTWH(body.left, body.top, body.width, p), lit);
    canvas.drawRect(Rect.fromLTWH(body.left, body.top, p, body.height), lit);
    canvas.drawRect(
      Rect.fromLTWH(body.left, body.bottom - p, body.width, p),
      dim,
    );
    canvas.drawRect(
      Rect.fromLTWH(body.right - p, body.top, p, body.height),
      dim,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SteelPainter old) =>
      old.round != round ||
      old.radius != radius ||
      old.tier != tier ||
      old.rimOnly != rimOnly ||
      old.voxel != voxel;
}

/// A round wooden button of [size], with [child] (the glyph) on its board.
/// [lit] adds a warm glow for a button that is open or pressed. [voxel] draws
/// its board's rim as a pixel-art staircase — opt-in (see [SteelPainter]),
/// used by the settlement HUD's own buttons only.
class IronButton extends StatelessWidget {
  final double size;
  final Widget child;
  final bool lit;
  final bool voxel;

  const IronButton({
    super.key,
    required this.size,
    required this.child,
    this.lit = false,
    this.voxel = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(child: WoodBoard(radius: 14, voxel: voxel)),
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

  /// TEMPORARILY OFF (user 2026-11-08: "vorerst nicht drehen"): the globe
  /// stands on its first frame. true brings the slow turn back.
  static const bool _spin = false;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void initState() {
    super.initState();
    if (_spin) _c.repeat();
  }

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
    if (UiArt.pixelWood) {
      // Pixel wood: a plain round board with the globe on it, no rose.
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: WoodBoard(round: true, voxel: true, tier: 2),
            ),
            UiArt.pxImage('globe'),
          ],
        ),
      );
    }
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
              child: const WoodBoard(round: true, voxel: true),
            ),
            // The dark dish the globe sits in, inside the gold ring.
            Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                width: size * 0.78,
                height: size * 0.78,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF15306B),
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
            // The gold ring over the spikes' feet — stepped, like the rest of
            // the reference image's rims (reverting 2026-11-07's "less
            // pixelated, like the chest's" now that the chest's ring is
            // stepped too).
            IgnorePointer(
              child: SizedBox(
                width: size,
                height: size,
                child: const CustomPaint(
                  painter: SteelPainter(
                    round: true,
                    tier: 2,
                    rimOnly: true,
                    voxel: true,
                  ),
                ),
              ),
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

  /// The pixelated glyph (file name in assets/images/ui_px/, no extension) worn
  /// instead of [asset] while [UiArt.pixelWood] is on.
  final String? pxName;
  const WoodMedal({
    super.key,
    required this.asset,
    required this.size,
    this.pxName,
  });

  @override
  Widget build(BuildContext context) {
    if (UiArt.pixelWood && pxName != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: WoodBoard(round: true, voxel: true, tier: 2),
            ),
            UiArt.pxImage(pxName!),
          ],
        ),
      );
    }
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
            child: const WoodBoard(round: true, voxel: true),
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

/// THE ENERGY EMBLEM in the middle of the header (user 2026-11-08: "die
/// Energieanzeige dort, wo die Kiste ist … die Füllung durch den Hintergrund
/// symbolisiert"): the round board the chest used to sit on, with a lightning
/// bolt in it and the dish behind the bolt filled like a flask — the more energy
/// there is, the higher the amber stands. Over 100 % the surface glows; at zero
/// the dish is empty and dark red.
///
/// Geometry matches [ChestImage] exactly (the visible disc is 0.72 of [size]),
/// so the medals hung off its lower corners stay where they were.
class EnergyEmblem extends StatelessWidget {
  final double size;

  /// How full the pool is, 0..1 of its ceiling.
  final double fraction;

  /// Above the normal 100 % mark (the pool can overfill to 125 %).
  final bool over;

  const EnergyEmblem({
    super.key,
    required this.size,
    required this.fraction,
    this.over = false,
  });

  @override
  Widget build(BuildContext context) {
    final d = size * 0.72;
    final dish = d * 0.76;
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
              const Positioned.fill(
                child: WoodBoard(round: true, voxel: true, tier: 2),
              ),
              SizedBox(
                width: dish,
                height: dish,
                child: CustomPaint(
                  painter: EnergyDishPainter(
                    fraction: fraction.clamp(0.0, 1.0),
                    over: over,
                  ),
                ),
              ),
              SizedBox(
                width: dish * 0.62,
                height: dish * 0.62,
                child: const CustomPaint(painter: PixelBoltPainter()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dish of the [EnergyEmblem]: a pixel circle, dark timber where it is empty
/// and amber, banded and with a stepped surface, up to [fraction].
class EnergyDishPainter extends CustomPainter {
  final double fraction;
  final bool over;
  const EnergyDishPainter({required this.fraction, required this.over});

  @override
  void paint(Canvas canvas, Size size) {
    const p = PxArt.pixel;
    final circle = voxelCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      p,
    );
    final px = Paint()..isAntiAlias = false;
    canvas.drawPath(
      circle,
      px
        ..color = fraction <= 0
            ? const Color(0xFF4A1C12)
            : const Color(0xFF2C1A0E),
    );
    canvas.save();
    canvas.clipPath(circle);
    if (fraction > 0) {
      final h = size.height;
      // snap the surface to the pixel grid
      final top = ((h - h * fraction) / p).round() * p;
      final bands = over
          ? const [Color(0xFFFFF0A0), Color(0xFFFFD04A), Color(0xFFF0A828)]
          : const [Color(0xFFFFD86A), Color(0xFFE8A92A), Color(0xFFC8841C)];
      final fillH = h - top;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, fillH),
        px..color = bands[1],
      );
      canvas.drawRect(
        Rect.fromLTWH(0, top + fillH * 0.62, size.width, fillH * 0.38 + p),
        px..color = bands[2],
      );
      // stepped surface: a lighter crest, every other block a pixel higher
      for (var x = 0.0, i = 0; x < size.width; x += 3 * p, i++) {
        final lift = i.isEven ? 0.0 : p;
        canvas.drawRect(
          Rect.fromLTWH(x, top - lift, 3 * p, 2 * p),
          px..color = bands[0],
        );
      }
      // a little glint, upper-left of the liquid
      canvas.drawRect(
        Rect.fromLTWH(size.width * 0.2, top + 3 * p, p, 3 * p),
        px..color = const Color(0x66FFFFFF),
      );
    }
    canvas.restore();
    // dark inner edge so the dish reads as sunk into its rim
    canvas.drawPath(
      circle,
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.stroke
        ..strokeWidth = p
        ..color = PxArt.outline,
    );
  }

  @override
  bool shouldRepaint(EnergyDishPainter old) =>
      old.fraction != fraction || old.over != over;
}

/// A lightning bolt in pixels: the polygon sampled on the 2 px grid, cream with
/// a shaded right half and a dark outline.
class PixelBoltPainter extends CustomPainter {
  const PixelBoltPainter();

  static const List<Offset> _poly = [
    Offset(0.60, 0.04),
    Offset(0.20, 0.56),
    Offset(0.46, 0.56),
    Offset(0.36, 0.96),
    Offset(0.82, 0.40),
    Offset(0.54, 0.40),
  ];

  static bool _inside(double x, double y) {
    var ins = false;
    for (var i = 0, j = _poly.length - 1; i < _poly.length; j = i++) {
      final a = _poly[i], b = _poly[j];
      if ((a.dy > y) != (b.dy > y) &&
          x < (b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx) {
        ins = !ins;
      }
    }
    return ins;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const p = PxArt.pixel;
    final cols = (size.width / p).floor(), rows = (size.height / p).floor();
    final fill = List.generate(rows, (_) => List.filled(cols, false));
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        fill[r][c] = _inside((c + 0.5) / cols, (r + 0.5) / rows);
      }
    }
    bool at(int r, int c) =>
        r >= 0 && c >= 0 && r < rows && c < cols && fill[r][c];
    final paint = Paint()..isAntiAlias = false;
    for (var r = -1; r <= rows; r++) {
      for (var c = -1; c <= cols; c++) {
        if (at(r, c)) {
          // the right half of the bolt a shade darker
          paint.color = c / cols > 0.5
              ? const Color(0xFFF0C850)
              : const Color(0xFFFFF6C8);
        } else if (at(r, c - 1) ||
            at(r, c + 1) ||
            at(r - 1, c) ||
            at(r + 1, c)) {
          paint.color = const Color(0xFF3A2208);
        } else {
          continue;
        }
        canvas.drawRect(Rect.fromLTWH(c * p, r * p, p, p), paint);
      }
    }
  }

  @override
  bool shouldRepaint(PixelBoltPainter old) => false;
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
              const Positioned.fill(child: WoodBoard(round: true, voxel: true)),
              // Mock-up 1: the dark dish inside the gold ring.
              Center(
                child: Container(
                  width: d * 0.76,
                  height: d * 0.76,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF15306B),
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
      ..color = const Color(0xFF0E1E40);
    final brass = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFFFFC62E);
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
        colors: [Color(0xFF3F79C4), Color(0xFF244C92), Color(0xFF1A356E)],
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
        canvas.drawCircle(c, 3.2, Paint()..color = const Color(0xFF0E1E40));
        canvas.drawCircle(c, 2.2, Paint()..color = const Color(0xFFFFC62E));
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
        color: const Color(0xFF0C1630),
        borderRadius: BorderRadius.circular(5),
        // Set INTO the timber board: dark rim, a light lip under it.
        border: Border.all(color: const Color(0xFF081024), width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x55BFD8FF), offset: Offset(0, 1)),
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
    Widget img() => UiArt.pixelWood
        ? Image.asset(
            UiArt.px('bell'),
            width: w,
            height: h,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.none,
            isAntiAlias: false,
            gaplessPlayback: true,
          )
        : Image.asset(
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
