import 'package:flutter/material.dart';

import '../ui/pressable.dart';
import 'strategy_theme.dart';

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
abstract final class CreamPalette {
  static const Color paperTop = Color(0xFFF6E7CC);
  static const Color paperBottom = Color(0xFFE2C9A0);

  /// Lines, the iso grid, dashed seats.
  static const Color tan = Color(0xFF9C6B3E);

  /// The hard shadow under a card or tile.
  static const Color tanShadow = Color(0xFF7C532C);

  /// Headings on a card.
  static const Color accent = Color(0xFF5A3A1B);
  static const Color ink = Color(0xFF2A1A0C);

  /// The one button colour, and the shade its hard shadow falls in.
  static const Color gold = Color(0xFFF5B83A);
  static const Color goldDeep = Color(0xFFC98A10);

  /// A raised tile standing on a card.
  static const Color tileTop = Color(0xFFFCF2DE);
  static const Color tileBottom = Color(0xFFEBD5AE);

  /// The menu ground and the tint dimming the map behind a dialog.
  static const Color groundTop = Color(0xFF5C3B22);
  static const Color groundBottom = Color(0xFF2A1A0C);
  static const Color dim = Color(0x9E2A1A0C);

  /// A locked seat.
  static const Color lockedTop = Color(0xFFDCCDB5);
  static const Color lockedBottom = Color(0xFFC9B79B);
  static const Color lockedShadow = Color(0xFFA69577);

  /// "Gets better" — the upgrade deltas.
  static const Color better = Color(0xFF2E7D4F);

  /// A warning ON paper — what you are short of, MAX, QUEUE. [FoE.danger] is
  /// the light coral for dark grounds; on cream it is too faint to read.
  static const Color warn = Color(0xFFB4531F);
}

/// Ink on the cards, in three weights, plus a deep brown for headings
/// ("Production", "Storage").
const Color kBoxInk = CreamPalette.ink;
final Color kBoxInkSoft = CreamPalette.ink.withValues(alpha: 0.78);
final Color kBoxInkFaint = CreamPalette.ink.withValues(alpha: 0.5);
const Color kBoxAccent = CreamPalette.accent;

/// The card surface. Still the build menu's cream and tan — but not a flat fill:
/// a warm gradient from paper to sand, the map's own ISOMETRIC GRID showing
/// faintly through it, and a thin inner frame, so it reads as a printed plate
/// rather than a white rectangle. Drawn by [_CreamPatternPainter], which does its
/// own rounded clipping — a ClipRRect here would cut off art that rises out of a
/// card's top edge.
Widget creamCard({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  Color? deep,

  /// A control laid on the card's top-right corner — the dialog's
  /// [KitCloseButton] (user 2026-09-22: one leaving button, always there).
  Widget? corner,
}) => _withCorner(
  corner,
  Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: deep ?? CreamPalette.tanShadow,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: CustomPaint(
      painter: const _CreamPatternPainter(),
      child: Padding(padding: padding, child: child),
    ),
  ),
);

Widget _withCorner(Widget? corner, Widget card) => corner == null
    ? card
    : Stack(
        children: [
          card,
          Positioned(top: 8, right: 8, child: corner),
        ],
      );

class _CreamPatternPainter extends CustomPainter {
  const _CreamPatternPainter({this.radius = 14, this.frame = true});

  final double radius;
  final bool frame;

  @override
  void paint(Canvas canvas, Size size) {
    final card = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(card);

    // The iso grid: two families of 2:1 diagonals, the slope every cell on the
    // settlement map has. Faint enough that the ink on top never fights it.
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
    canvas.restore();

    if (!frame) return;
    // The inner frame.
    canvas.drawRRect(
      card.deflate(3),
      Paint()
        ..color = CreamPalette.tan.withValues(alpha: 0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CreamPatternPainter old) =>
      old.radius != radius || old.frame != frame;
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
              Icon(icon, size: 15, color: kBoxAccent),
              const SizedBox(width: 6),
            ],
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: kBoxAccent,
              ),
            ),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: CreamPalette.tan.withValues(alpha: 0.55)),
        const SizedBox(height: 10),
      ],
      if (expand) Expanded(child: child) else child,
    ],
  ),
);

/// A small light tile standing on a [creamCard] — lighter than the card, with a
/// hard tan shadow: a trip, a target, a monster. [lit] gives it a gold rim (a
/// trip that is READY); [locked] greys it (a spot you cannot use).
BoxDecoration raisedTile({
  bool lit = false,
  bool locked = false,
  double radius = 12,
}) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: locked
        ? const [CreamPalette.lockedTop, CreamPalette.lockedBottom]
        : const [CreamPalette.tileTop, CreamPalette.tileBottom],
  ),
  borderRadius: BorderRadius.circular(radius),
  border: lit ? Border.all(color: CreamPalette.gold, width: 2) : null,
  boxShadow: [
    BoxShadow(
      color: lit ? CreamPalette.goldDeep : CreamPalette.tanShadow,
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
    active ? CreamPalette.ink : CreamPalette.ink.withValues(alpha: 0.5);

// ── Full-screen menus ───────────────────────────────────────────────────────

/// The ground a menu screen stands on: deep navy, a shade lighter at the top —
/// the build menu's own colour, so the cream cards read as they do on the map.
const LinearGradient kMenuGround = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [CreamPalette.groundTop, CreamPalette.groundBottom],
);

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

  /// Whether the button reads BACK (an arrow) instead of CLOSE (a cross). Null =
  /// worked out: a menu opened over another menu goes back, a menu opened from
  /// the map closes. See [KitCloseButton].
  final bool? back;

  /// Passed straight to the [Scaffold].
  final Widget? floatingActionButton;

  const MenuScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.maxWidth = 960,
    this.showClose = true,
    this.onClose,
    this.back,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) => _MenuDepth(
    builder: (nested) => Scaffold(
      backgroundColor: CreamPalette.groundBottom,
      floatingActionButton: floatingActionButton,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: kMenuGround),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    creamCard(
                      padding: const EdgeInsets.fromLTRB(14, 7, 8, 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
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
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
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

  const KitCloseButton({super.key, this.onTap, this.back = false});

  /// Its size, for a layout that has to leave room for it.
  static const double size = 34;

  @override
  Widget build(BuildContext context) => Semantics(
    label: back ? 'Back' : 'Close',
    button: true,
    child: Pressable(
      onTap: onTap ?? () => Navigator.of(context).maybePop(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: CreamPalette.gold,
          boxShadow: [
            BoxShadow(color: CreamPalette.goldDeep, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(
          back ? Icons.arrow_back_rounded : Icons.close,
          size: 19,
          color: CreamPalette.ink,
        ),
      ),
    ),
  );
}

/// A cream SURFACE for a sheet or a page body: the same paper, iso grid and glow
/// as [creamCard], but no hard shadow and only the corners you ask for rounded,
/// so it can fill the width of a bottom sheet or sit flush in a page.
Widget creamSurface({
  required Widget child,
  BorderRadius radius = const BorderRadius.vertical(top: Radius.circular(18)),
}) => DecoratedBox(
  decoration: BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
    ),
    borderRadius: radius,
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
            Icon(icon, size: 15, color: kBoxAccent),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: kBoxAccent,
              ),
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
      const SizedBox(height: 6),
      Container(height: 1, color: CreamPalette.tan.withValues(alpha: 0.55)),
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
              shape: BoxShape.circle,
              color: CreamPalette.gold,
              boxShadow: [
                BoxShadow(
                  color: CreamPalette.goldDeep,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.add, size: 18, color: CreamPalette.ink),
          ),
          if (label != null) ...[
            const SizedBox(height: 5),
            Text(
              label!,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: CreamPalette.tan,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
