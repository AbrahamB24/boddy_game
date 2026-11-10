import 'package:flutter/material.dart' hide Text;

import '../ui/pressable.dart';
import 'fachwerk.dart';
import 'ui_art.dart';
import 'strategy_theme.dart';
import 'voxel_kit.dart';
import 'voxel_icons.dart';
import '../ui/game_text.dart';

// ── The cream kit: the building detail dialog's look, as shared parts ──────
//
// User 2026-09-18: "das gesamte UI an den Gebäudedetailscreen anpassen. Nimm
// diesen als Vorlage." The dialog had grown these pieces privately; they live
// here now so every screen builds its menu out of the SAME parts:
//
//  * [creamCard]      — the card surface: paper-to-sand gradient, the map's iso
//                       grid faintly through it, a thin inner frame, a hard tan
//                       shadow.
//  * [sectionCard]    — a card with a FLAT heading (glyph, capitals, hairline).
//                       Never a pill: pills are for things you can press.
//  * [raisedTile]     — a small light tile standing on a card (a monster, a trip).
//  * [goldButton]     — the one button look: chunky gold, navy ink.
//  * the [kBoxInk] family — navy ink for text ON a card.
//  * [pushMenu] / [MenuScaffold] — a full screen built of those parts: a deep
//                       navy ground, a cream title card, cream cards on it. (Only
//                       the building dialog shows the dimmed map behind it —
//                       user 2026-09-18: screens that are their own screen stay
//                       their own screen.)

/// The kit's colours in ONE place — "Holz" (user 2026-09-19, picked from ten
/// colour worlds for the building detail redesign): sand-coloured paper, leather
/// tan, dark-brown ink, amber buttons, a brown ground. Everything in this file
/// reads these, so a screen built from the kit recolours by editing here.
///
/// FACHWERK (user 2026-11-02, matching the new rendered buildings): the
/// paper is the houses' pale PLASTER now (less yellow than the old sand),
/// lines and shadows are TIMBER (red-brown, not leather tan), headings take
/// the dark of a roof tile, and the ground is a timber beam in shade. Gold
/// stays — it is the lit windows and the ridge finial.
abstract final class CreamPalette {
  static const Color paperTop = Color(0xFF1F4E63);
  static const Color paperBottom = Color(0xFF1B4558);

  /// Lines, dashed seats — light timber.
  static const Color tan = Color(0xFF4C8CA6);

  /// The hard shadow under a card or tile — timber in shade.
  static const Color tanShadow = Color(0xFF0A2029);

  /// Headings on a card — a shaded roof tile.
  static const Color accent = Color(0xFF7FD6E8);
  static const Color ink = Color(0xFF08222B);

  /// The one button colour (a lit window), and the shade its hard shadow
  /// falls in.
  static const Color gold = Color(0xFF3FD0D0);
  static const Color goldDeep = Color(0xFF1C8C8C);

  /// Gold as TEXT or glyph colour on a card: [goldDeep] is a shadow tone and is
  /// too dim to read on the dark cards.
  static const Color goldInk = Color(0xFF7DE8E8);

  /// A raised tile standing on a card — fresh plaster.
  static const Color tileTop = Color(0xFF2C6A80);
  static const Color tileBottom = Color(0xFF265C70);

  /// The menu ground and the tint dimming the map behind a dialog.
  static const Color groundTop = Color(0xFF1E5266);
  static const Color groundBottom = Color(0xFF0E2530);
  static const Color dim = Color(0x9E0E2530);

  /// A locked seat.
  static const Color lockedTop = Color(0xFF2E5367);
  static const Color lockedBottom = Color(0xFF28485A);
  static const Color lockedShadow = Color(0xFF1A3442);

  /// "Gets better" — the upgrade deltas. The lawn's shaded green.
  static const Color better = Color(0xFF4AE08F);

  /// A warning ON paper — what you are short of, MAX, QUEUE. [FoE.danger] is
  /// the light coral for dark grounds; on cream it is too faint to read.
  static const Color warn = Color(0xFFFF8A5C);
}

/// Ink on the cards, in three weights, plus a deep brown for headings
/// ("Production", "Storage").
// NACHT (2026-11-03): the cards are dark now, so ink ON THEM is light. [CreamPalette.ink]
// stays the dark navy that goes on the orange buttons.
const Color kBoxInk = Color(0xFFEAF4F8);
// Voxel pass (2026-11-03): a pixel face has thin strokes, so ink that was fine
// for a smooth face at 78 % / 50 % is too faint now. Raised to read at 11-12 px.
final Color kBoxInkSoft = kBoxInk.withValues(alpha: 0.92);
final Color kBoxInkFaint = kBoxInk.withValues(alpha: 0.72);
const Color kBoxAccent = CreamPalette.accent;

/// Which texture [_CreamPatternPainter] draws (user 2026-09-30, picked from
/// ten background proposals to replace the diamond lattice — "lieber gar
/// kein Muster, sondern nur den Farbverlauf", then "direkt auf die gesamte
/// app übernehmen. Nur beim Baumenü nicht, dort die Vierecke behalten"):
/// [none] — just the paper gradient and the corner glow — is the app-wide
/// default now; [diamond] (the map's own iso grid, faint) is kept ONLY for
/// the build menu's own cards (`building_carousel.dart`), the one place the
/// user asked to leave alone.
enum CreamPatternStyle { none, diamond, blocks }

/// The card surface. Still the build menu's cream and tan — but not a flat fill:
/// a warm gradient from paper to sand, a faint background texture (see
/// [CreamPatternStyle]) showing through it, and a thin inner frame, so it
/// reads as a printed plate rather than a white rectangle. Drawn by
/// [_CreamPatternPainter], which does its own rounded clipping — a ClipRRect
/// here would cut off art that rises out of a card's top edge.
Widget creamCard({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  Color? deep,
  CreamPatternStyle pattern = CreamPatternStyle.none,

  /// A control laid on the card's top-right corner — the dialog's
  /// [KitCloseButton] (user 2026-09-22: one leaving button, always there).
  Widget? corner,

  /// A TIMBER FRAME round the card (Fachwerk, 2026-11-02) — for a main
  /// surface: a menu screen, a dialog. Inner cards leave it off, or a page
  /// would be beams inside beams.
  bool framed = false,

  /// A course of ROOF TILES along the top edge, inside the frame — the
  /// "roof" over a screen's or dialog's title. The child is pushed down by
  /// [kRoofHeight] to make room for it.
  bool roof = false,
}) => _withCorner(
  corner,
  // VOXEL (2026-11-03): one flat sheet of paper, cut at the corners in whole
  // blocks, with a bevel, a dark outline and a hard shadow underneath. A framed
  // card (a screen, a dialog) gets the heavier outline instead of the old
  // timber beam and roof tiles.
  Container(
    decoration: ShapeDecoration(
      color: CreamPalette.paperTop,
      shape: VoxelShape(
        notch: framed ? 3 : 2,
        lines: framed ? 2 : 1,
        light: Voxel.rim,
      ),
      shadows: voxelDrop(
        depth: framed ? 4 : 3,
        color: deep ?? CreamPalette.tanShadow,
      ),
    ),
    child: pattern != CreamPatternStyle.none
        ? CustomPaint(
            painter: _CreamPatternPainter(
              radius: 2,
              frame: false,
              pattern: pattern,
            ),
            child: Padding(padding: padding, child: child),
          )
        : Padding(padding: padding, child: child),
  ),
);

/// The beam width of a framed [creamCard].
const double kTimberWidth = 4;

/// The height of the roof-tile course a roofed [creamCard] wears.
const double kRoofHeight = 0;

Widget _withCorner(Widget? corner, Widget card) => corner == null
    ? card
    : Stack(
        children: [
          card,
          Positioned(top: 8, right: 8, child: corner),
        ],
      );

class _CreamPatternPainter extends CustomPainter {
  const _CreamPatternPainter({
    this.radius = 14,
    this.frame = true,
    this.pattern = CreamPatternStyle.none,
  });

  final double radius;
  final bool frame;
  final CreamPatternStyle pattern;
  final bool timber = false;
  final bool roof = false;

  @override
  void paint(Canvas canvas, Size size) {
    final card = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(card);

    if (pattern == CreamPatternStyle.diamond) _paintDiamond(canvas, size);
    if (pattern == CreamPatternStyle.blocks) _paintBlocks(canvas, size);
    // Plaster grain (Fachwerk, 2026-11-02).
    paintPlaster(canvas, Offset.zero & size);

    // A warm glow in the top-left corner, where the light comes from.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.9, -1.0),
          radius: 1.2,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Offset.zero & size),
    );
    if (roof) {
      final inset = timber ? kTimberWidth : 0.0;
      paintRoofTiles(
        canvas,
        Rect.fromLTWH(inset, inset, size.width - 2 * inset, kRoofHeight),
        tileWidth: 22,
      );
    }
    canvas.restore();

    if (timber) {
      paintTimberFrame(canvas, card, width: kTimberWidth);
      return;
    }
    if (!frame) return;
    // The inner frame — a thin timber line, like a beam seen edge-on.
    canvas.drawRRect(
      card.deflate(3),
      Paint()
        ..color = CreamPalette.tan.withValues(alpha: 0.32)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  // The block wall of the monster page, faint enough for text to sit on: every
  // 26 px block a little lighter or darker than the card, by a stable hash.
  void _paintBlocks(Canvas canvas, Size size) {
    const cell = 26.0;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final h = ((x * 73856093) ^ (y * 19349663)) & 0xFFFF;
        final j = (h % 5) / 4.0 - 0.5; // -0.5 .. 0.5
        final r = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        canvas.drawRect(
          r,
          Paint()
            ..color = (j >= 0 ? Colors.white : Colors.black).withValues(
              alpha: j.abs() * 0.10,
            ),
        );
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, cell, 1.5),
          Paint()..color = const Color(0x12FFFFFF),
        );
        canvas.drawRect(
          Rect.fromLTWH(r.left, r.top, 1.5, cell),
          Paint()..color = const Color(0x0DFFFFFF),
        );
      }
    }
  }

  // The iso grid: two families of 2:1 diagonals, the slope every cell on the
  // settlement map has. Faint enough that the ink on top never fights it.
  void _paintDiamond(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = CreamPalette.tan.withValues(alpha: 0.14)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const step = 28.0;
    final h = size.height;
    for (var x = -2 * h; x <= size.width + 2 * h; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + 2 * h, h), grid); // down-right
      canvas.drawLine(Offset(x, 0), Offset(x - 2 * h, h), grid); // down-left
    }
  }

  @override
  bool shouldRepaint(covariant _CreamPatternPainter old) =>
      old.radius != radius ||
      old.frame != frame ||
      old.pattern != pattern ||
      old.timber != timber ||
      old.roof != roof;
}

/// One grouped block: a titled [creamCard]. Grouping is what turns a long run of
/// loose rows into something scannable.
///
/// The title is a HEADING, not a control: a small glyph, the title in capitals,
/// and a hairline under it — no fill, no edge, no shadow, so the only gold left
/// on a card is a real button. Pass [trailing] for a small right-aligned action
/// or readout. [padding] overrides the body padding, for a body that wants to
/// run edge to edge. [expand] makes the body fill the card's remaining height —
/// for a scrolling list, which needs bounded room; the card itself then has to
/// be given a bounded height.
Widget sectionCard({
  required Widget child,
  String? title,
  IconData? icon,
  Widget? trailing,
  EdgeInsetsGeometry? padding,
  bool expand = false,
}) => creamCard(
  padding: padding ?? EdgeInsets.fromLTRB(12, title == null ? 14 : 11, 12, 14),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null) ...[
        Row(
          children: [
            if (icon != null) ...[
              PixelIcon(icon, size: 17, color: kBoxAccent),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: 1.0,
                  color: kBoxAccent,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 2, color: CreamPalette.tan.withValues(alpha: 0.6)),
        const SizedBox(height: 10),
      ],
      if (expand) Expanded(child: child) else child,
    ],
  ),
);

// ── One page, not several boxes ─────────────────────────────────────────────
//
// User 2026-09-29, looking at a screen built of two/three stacked
// [sectionCard]s (Management: "OUT NOW" card beside a "TARGETS" card): "ich
// möchte bei den Menüs nicht, dass es unterschiedliche Boxen sind... diese
// sollen eine volle Seite ausmachen." The rule that followed, picked from ten
// mockups: "Trennlinien und Zonen gemischt. Bei deutlich unterschiedlichen
// Gebieten eine Zone machen zum Abheben, sonst nur eine Trennlinie oder gar
// nichts." — applied app-wide to every screen that used to stack several
// [sectionCard]s in one body.
//
// So a screen with several facets now builds ONE [pageCard] (the title card
// stays separate — that is chrome, not a content "Gebiet") and lays its
// facets out with [sectionLabel] headings, reaching for [zoneBox] only where
// two facets are genuinely different SYSTEMS (gather vs Hunt, what's out vs
// where you can go), [hairline]/[vHairline] where they are just two halves of
// the same list, and neither when the heading and the spacing already say
// enough on their own.

/// The one surface a multi-facet menu body stands on, replacing what used to
/// be several separate [sectionCard]s. Compose its [child] from
/// [sectionLabel], [zoneBox], [hairline] and [vHairline] — never nest another
/// [creamCard] inside it, or the "several boxes" look is right back.
Widget pageCard({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(14, 11, 14, 14),
  bool framed = false,
}) => creamCard(padding: padding, framed: framed, child: child);

/// A facet's heading with no card of its own — the surface comes from the
/// enclosing [pageCard]. The same glyph/capitals/[trailing] row
/// [sectionCard] used to draw above its hairline.
Widget sectionLabel(String title, {IconData? icon, Widget? trailing}) => Row(
  children: [
    if (icon != null) ...[
      PixelIcon(icon, size: 17, color: kBoxAccent),
      const SizedBox(width: 6),
    ],
    Text(
      title.toUpperCase(),
      style: TextStyle(fontSize: 13, letterSpacing: 1.0, color: kBoxAccent),
    ),
    const Spacer(),
    if (trailing != null) trailing,
  ],
);

/// A thin rule — the ONLY separator between two facets that are different
/// halves of the same thing (not different "Gebiete"; those get [zoneBox]
/// instead). Stacks two facets in a [Column].
Widget hairline({double gap = 10}) => Padding(
  padding: EdgeInsets.symmetric(vertical: gap),
  child: Container(height: 2, color: CreamPalette.tan.withValues(alpha: 0.6)),
);

/// [hairline]'s vertical twin, for two facets sitting side by side in a
/// [Row].
Widget vHairline({double gap = 12}) => Padding(
  padding: EdgeInsets.symmetric(horizontal: gap),
  child: Container(width: 2, color: CreamPalette.tan.withValues(alpha: 0.6)),
);

/// A tonal zone — for a facet that is a genuinely different SYSTEM from its
/// neighbour, not just another entry in the same list (Hunt beside the
/// gather targets; "out now" beside "where you can go"). A tint plus a thin
/// edge, no shadow, so it reads as a region of the same sheet rather than a
/// card sitting on top of it — but a visible one (user 2026-09-30: "diese
/// etwas dunkleren Boxen fallen fast nicht auf" — the original 8%-alpha fill
/// alone was too close to the paper behind it to register as its own zone).
Widget zoneBox({
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.all(8),
  Color? tint,
}) => Container(
  padding: padding,
  decoration: BoxDecoration(
    color: tint ?? CreamPalette.tan.withValues(alpha: 0.18),
    borderRadius: vr(12),
    // (No shadow ring here: the fill is translucent and a ring behind it would
    // show through as mud.)
    border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.9)),
  ),
  child: child,
);

/// A small light tile standing on a [creamCard] — lighter than the card, with a
/// hard tan shadow: a trip, a target, a monster. [lit] gives it a gold rim (a
/// trip that is READY); [locked] greys it (a spot you cannot use).
BoxDecoration raisedTile({
  bool lit = false,
  bool locked = false,
  double radius = 12,
}) => BoxDecoration(
  // One flat tone, a two-pixel outline and a hard slab of shadow: a block
  // standing on the card.
  gradient: Voxel.shaded(
    locked ? CreamPalette.lockedTop : CreamPalette.tileTop,
    up: 0.12,
    down: 0.22,
  ),
  borderRadius: vr(radius),
  border: Border.all(
    color: lit
        ? CreamPalette.goldDeep
        : CreamPalette.tan.withValues(alpha: 0.5),
  ),
  boxShadow: [
    BoxShadow(
      color: lit ? CreamPalette.goldDeep : Voxel.outline.withValues(alpha: 0.8),
      spreadRadius: 1.5,
      blurRadius: 0,
    ),
    BoxShadow(
      color: lit ? CreamPalette.gold : CreamPalette.tanShadow,
      offset: const Offset(0, 3),
    ),
  ],
);

/// The one button look: a chunky GOLD pill like the build menu's active
/// category, navy ink on it — or, when it can't be pressed, the grey the menu
/// shows for a card you cannot afford.
BoxDecoration goldButton({bool active = true}) => chunkyDecoration(
  fill: active ? CreamPalette.gold : Strategy.locked,
  deep: active ? CreamPalette.goldDeep : Strategy.lockedDeep,
  radius: 14,
  shadowOffset: 3,
);

Color goldButtonInk({bool active = true}) =>
    active ? CreamPalette.ink : kBoxInk.withValues(alpha: 0.6);

// ── Full-screen menus ───────────────────────────────────────────────────────

/// The ground a menu screen stands on: deep navy, a shade lighter at the top —
/// the build menu's own colour, so the cream cards read as they do on the map.
const LinearGradient kMenuGround = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [CreamPalette.groundTop, CreamPalette.groundBottom],
);

/// The ground of a screen that is not a [MenuScaffold] (the sign-in, the
/// loading screen): the block wall of the monster page over the menu gradient.
class VoxelGround extends StatelessWidget {
  final Widget child;
  const VoxelGround({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const VoxelBackdrop(color: CreamPalette.groundTop, vignette: 0.45),
      child,
    ],
  );
}

/// Pushes [page] as an ordinary full screen, with a short fade. Every
/// [MenuScaffold] page is pushed with this so the whole app opens its menus the
/// same way.
Future<T?> pushMenu<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );

/// The frame of a menu screen: a navy ground ([kMenuGround]), a cream title card
/// with a close button along the top, and the body below it. The body builds its
/// own cards ([sectionCard], [creamCard]) — text sits on those, never straight
/// on the ground.
///
/// Push it with [pushMenu].
class MenuScaffold extends StatelessWidget {
  final String title;

  /// A readout at the right of the title card — a count, a purse. It sits on
  /// cream, so it must use [kBoxInk], not white.
  final Widget? trailing;
  final Widget child;

  /// Caps the content's width so a wide window does not stretch a menu across
  /// the whole screen.
  final double maxWidth;

  /// The gold close button in the title card; off for a screen with nowhere to
  /// go back to. [onClose] replaces popping the route.
  final bool showClose;
  final VoidCallback? onClose;

  /// Drops the title row (and its close button) and the hairline under it
  /// entirely, handing [child] the whole card — for a screen with nothing to
  /// call itself or go back from (the empty-collection starter pick: there is
  /// no "Monsters" count worth showing before the first one exists, and
  /// nowhere earlier to close back to until it's chosen).
  final bool showHeader;

  /// Whether the button reads BACK (an arrow) instead of CLOSE (a cross). Null =
  /// worked out: a menu opened over another menu goes back, a menu opened from
  /// the map closes. See [KitCloseButton].
  final bool? back;

  /// Passed straight to the [Scaffold].
  final Widget? floatingActionButton;

  /// The screen's background texture — [CreamPatternStyle.none] (just the
  /// paper gradient) app-wide by default (user 2026-09-30); only the build
  /// menu's own cards keep [CreamPatternStyle.diamond] — see
  /// `building_carousel.dart`, which sets it directly rather than through a
  /// [MenuScaffold].
  final CreamPatternStyle pattern;

  /// The main screen's own materials (user 2026-11-05): walnut ground, the
  /// header's timber bar with its terracotta eave as the title, a studded
  /// walnut board for the body, a bronze medal to leave by. See [UiBar].
  final bool timber;

  const MenuScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.maxWidth = 960,
    this.showClose = true,
    this.showHeader = true,
    this.onClose,
    this.back,
    this.floatingActionButton,
    this.pattern = CreamPatternStyle.none,
    this.timber = false,
  });

  // [timber] is ignored: every menu wears the main screen's blue (2026-11-09).
  @override
  Widget build(BuildContext context) => _buildCream(context);

  Widget _buildCream(BuildContext context) => _MenuDepth(
    builder: (nested) => Scaffold(
      backgroundColor: CreamPalette.groundBottom,
      floatingActionButton: floatingActionButton,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: VoxelBackdrop(color: CreamPalette.groundTop, vignette: 0.3),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                // ONE card for the whole screen now, the title included (user
                // 2026-09-29: "überall ist noch der Header abgetrennt, dieser
                // soll aber auch in den gleichen Kasten. Resp. diese Kasten
                // gibt es nicht mehr" — the last holdout of the old
                // several-boxes-per-menu look, after the "Trennlinien und
                // Zonen gemischt" pass folded every screen's OWN several
                // section cards into one), and FULL BLEED (user 2026-09-29,
                // seeing the card still framed by a brown margin: "es soll
                // wirklich ganz bis nach aussen gehen ohne den dunkelbraunen
                // Hintergrund") — no outer padding left for [kMenuGround] to
                // show through at all; it now only ever paints the sliver
                // behind a notch/home-indicator SafeArea has to leave clear.
                // The block wall (the monster page's background, user 2026-11-09)
                // shows round the card now: a frame of 8 px instead of nothing.
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: creamCard(
                    padding: const EdgeInsets.fromLTRB(14, 9, 10, 10),
                    pattern: pattern,
                    // Fachwerk (2026-11-02): the screen is a house wall — a beam
                    // round it and the roof's tiles over its title.
                    framed: true,
                    roof: showHeader,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showHeader) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 21,
                                    letterSpacing: 0.3,
                                    color: kBoxInk,
                                  ),
                                ),
                              ),
                              if (trailing != null) ...[
                                trailing!,
                                const SizedBox(width: 10),
                              ],
                              if (showClose)
                                KitCloseButton(
                                  back: back ?? nested,
                                  onTap: onClose,
                                ),
                            ],
                          ),
                          hairline(gap: 8),
                        ],
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Knows whether a menu was opened OVER another menu: the first one on the stack
/// closes back to the map, every one above it goes back one step. Pages under a
/// pushed route stay mounted, so a plain counter is enough.
class _MenuDepth extends StatefulWidget {
  final Widget Function(bool nested) builder;
  const _MenuDepth({required this.builder});

  @override
  State<_MenuDepth> createState() => _MenuDepthState();
}

class _MenuDepthState extends State<_MenuDepth> {
  static int _open = 0;
  late final bool _nested;

  @override
  void initState() {
    super.initState();
    _nested = _open > 0;
    _open++;
  }

  @override
  void dispose() {
    _open--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_nested);
}

/// THE BUTTON THAT LEAVES (user 2026-09-22: "Zurück und Schliessen-Button
/// vereinheitlichen mit Style und Platzierung"): one round gold button, always at
/// the RIGHT end of the title row of the screen or dialog it belongs to. A cross
/// CLOSES what was opened over the map; an arrow goes BACK one step to the page
/// underneath. Same size, colour and place either way, so it is always where the
/// thumb expects it.
class KitCloseButton extends StatelessWidget {
  /// Runs instead of popping the route.
  final VoidCallback? onTap;

  /// An arrow (back) instead of a cross (close).
  final bool back;

  /// Tints the disc away from the kit's default gold (user 2026-09-29, the
  /// creature detail screen: "Zurückbutton … sollen auch in der
  /// entsprechenden Typfarben gehalten werden") — every other screen omits
  /// this and keeps the shared gold.
  final Color? color;

  const KitCloseButton({super.key, this.onTap, this.back = false, this.color});

  /// Its size, for a layout that has to leave room for it.
  static const double size = 34;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? CreamPalette.gold;
    // A dark tint (most elements, over their own darkened backdrop) reads
    // best with a light icon; only a pale tint needs the kit's usual dark ink.
    final ink = fill.computeLuminance() > 0.45
        ? CreamPalette.ink
        : Colors.white;
    return Semantics(
      label: back ? 'Back' : 'Close',
      button: true,
      child: Pressable(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: fill,
            shape: const VoxelShape(notch: 2),
            shadows: voxelDrop(
              depth: 2,
              color: color == null
                  ? CreamPalette.goldDeep
                  : Color.lerp(fill, Colors.black, 0.35)!,
            ),
          ),
          child: VoxelIcon(
            back ? VoxelGlyph.back : VoxelGlyph.close,
            size: 20,
            color: ink,
            shadow: false,
          ),
        ),
      ),
    );
  }
}

/// A cream SURFACE for a sheet or a page body: the same paper, iso grid and glow
/// as [creamCard], but no hard shadow and only the corners you ask for rounded,
/// so it can fill the width of a bottom sheet or sit flush in a page.
Widget creamSurface({
  required Widget child,
  BorderRadius radius = const BorderRadius.vertical(top: Radius.circular(18)),
}) => DecoratedBox(
  decoration: BoxDecoration(
    color: CreamPalette.paperTop,
    borderRadius: radius,
    border: Border.all(color: Voxel.outline, width: 2),
  ),
  child: ClipRRect(
    borderRadius: radius,
    child: CustomPaint(
      painter: const _CreamPatternPainter(radius: 0, frame: false),
      child: child,
    ),
  ),
);

/// The flat heading row for a sheet, dialog or page section: glyph (optional),
/// the title in capitals, a hairline under it — the same heading [sectionCard]
/// draws, as a widget of its own. [trailing] sits at the right.
class CreamHeading extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;

  const CreamHeading({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          if (icon != null) ...[
            PixelIcon(icon, size: 17, color: kBoxAccent),
            const SizedBox(width: 6),
          ],
          // EXPANDED, not Flexible + Spacer (user 2026-09-28: "das X ist nicht
          // rechts sondern eher mittig"). Both were flex 1, so they split the
          // free room in half and a loose Flexible left its unused half empty —
          // a short title pushed everything on the right towards the middle.
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.1,
                color: kBoxAccent,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
      const SizedBox(height: 6),
      Container(height: 2, color: CreamPalette.tan.withValues(alpha: 0.6)),
    ],
  );
}

/// A rounded rectangle drawn as a dashed line — Flutter's borders have no dashed
/// style. The outline of an EMPTY seat (see [EmptySeat]).
class DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  const DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.75),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

/// A free seat: a dashed outline with a gold "+" — a place waiting to be filled.
/// Fills whatever box it is given; [label] is an optional caption under the "+".
class EmptySeat extends StatelessWidget {
  final double radius;
  final String? label;

  const EmptySeat({super.key, this.radius = 12, this.label});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: DashedRRectPainter(
      color: CreamPalette.tan.withValues(alpha: 0.85),
      radius: radius,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              color: CreamPalette.gold,
              boxShadow: [
                BoxShadow(
                  color: CreamPalette.goldDeep,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const PixelIcon(
              Icons.add,
              size: 18,
              color: CreamPalette.ink,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 5),
            Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: CreamPalette.accent,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
