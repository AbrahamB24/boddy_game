import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/voxel_kit.dart' show vr;

// ── Tutorial spotlight ────────────────────────────────────────
// The guided intro (user design 2026-07-17) highlights exactly ONE control at
// a time: the target stays bright and tappable, everything else is dimmed AND
// dead. That second half is the point — a tutorial that merely *suggests*
// where to tap still lets a new player wander into screens the script hasn't
// explained yet, and then the script is narrating a state it isn't in.
//
// Two layers do two different jobs now (2026-09-30 rework): a single
// CustomPainter draws the DIMMING, as one seamless fill-with-a-hole so there
// is no seam for two abutting rectangles to show (user report: "teilweise
// sieht man die Übergänge von den Boxen") — and four INVISIBLE rects around
// the hole still do the actual tap-blocking, so target hit-testing still
// needs no custom render object: the gap between them IS the interactive
// hole, and pointers over the target never meet the overlay at all.

/// Registry of spotlight anchors. Screens hang a [GlobalKey] per highlight
/// target on their widgets and look it up here by a stable name, so the
/// intro flow can say "highlight 'build-target-row'" without the two
/// screens knowing each other.
class IntroSpotlightAnchors {
  IntroSpotlightAnchors._();

  static final Map<String, GlobalKey> _keys = {};

  /// The key for [name], created on first use. Using the same name from the
  /// overlay and from the target widget is the whole contract.
  static GlobalKey of(String name) => _keys.putIfAbsent(name, GlobalKey.new);
}

/// Dims and dead-zones everything except the widget carrying
/// [IntroSpotlightAnchors.of(anchorName)]. Layer it as the LAST child of a
/// screen-level [Stack] (so it sits above the content it gates).
///
/// While the anchor hasn't been laid out yet (first frame, target off-screen
/// in a scrollable) the whole screen is dimmed-but-dead: better to briefly
/// block everything than to let a frame of unguarded taps through.
class IntroSpotlightOverlay extends StatefulWidget {
  /// Name of the anchor to highlight — see [IntroSpotlightAnchors.of].
  final String anchorName;

  /// One short line of guidance, drawn near the hole.
  final String? hint;

  /// Breathing room around the target's own bounds.
  final double padding;

  /// Draws the glow frame as a circle instead of a rounded rectangle — for a
  /// round target (the overworld's own disc nodes, user 2026-09-02: "der
  /// Button ist nicht richtig markiert" over a square glow sitting on a
  /// circular node) a facet border reads as a mismatched shape rather than a
  /// highlight.
  final bool circular;

  /// Tapping the DIMMED area (not the hole) runs this instead of doing
  /// nothing — used by a screen's own sequential callouts ("turn order →
  /// AP → actions → HP") to advance on any tap, since the highlighted
  /// target itself is sometimes a real button the callout must not trigger
  /// (see battle_screen.dart's action-row explanation). Null keeps the
  /// original behaviour: the scrim only ever blocks.
  final VoidCallback? onScrimTap;

  /// False draws no gold glow ring around the hole at all — only the hint
  /// text near it. For an explainer that has no real target to point at
  /// (battle_screen.dart's "Miss" concept explainer, anchored to
  /// 'battle-hp' purely so the text has somewhere to sit near, not because
  /// the player's own monster is actually relevant — user 2026-09-30: "Hier
  /// musst du nicht das eigene Monster highlighten"): a glow ring around it
  /// would wrongly suggest the monster itself is what the text is about.
  final bool showRing;

  /// False makes the dimming fully transparent — everywhere outside the
  /// hole is still dead (taps absorbed), just not visually darkened. For
  /// the same "Miss" explainer as [showRing] (user 2026-09-30: "nur der
  /// Text ist gehighlighted, sonst nichts") — with nothing to ring, darkening
  /// the whole screen just to show one line of text has nothing to justify
  /// it either.
  final bool dim;

  const IntroSpotlightOverlay({
    super.key,
    required this.anchorName,
    this.hint,
    this.padding = 6,
    this.circular = false,
    this.onScrimTap,
    this.showRing = true,
    this.dim = true,
  });

  @override
  State<IntroSpotlightOverlay> createState() => _IntroSpotlightOverlayState();
}

class _IntroSpotlightOverlayState extends State<IntroSpotlightOverlay> {
  Rect? _hole;

  /// This overlay's OWN box, re-measured alongside [_hole] — [_hintLabel]
  /// positions the bubble against this, not [MediaQuery]'s screen size (user
  /// 2026-10-01, screenshot of the healing-hut-heal-action hint cut off at
  /// the real screen edge): this overlay sits inside the building dialog's
  /// own `Stack`, which is WIDTH-CAPPED well short of the screen
  /// (building_detail_dialog.dart's `SizedBox(width: ...clamp(360, 728))`),
  /// so `Positioned.fill` here only ever spans that narrower box. Clamping
  /// the bubble's `left` against the full screen width let it sit past this
  /// box's own right edge — still a valid position in the Stack's unclipped
  /// coordinate space, just one the dialog never actually occupies on
  /// screen.
  Size? _overlaySize;

  @override
  void initState() {
    super.initState();
    _scheduleMeasure();
  }

  /// Re-measures after EVERY rendered frame, not after every overlay build:
  /// the anchor can move without this widget rebuilding at all (panning an
  /// InteractiveViewer repaints via its own transform listenable), and a
  /// build-time measurement would leave the hole behind. Post-frame
  /// callbacks don't request frames, so an idle app costs nothing — and when
  /// nothing renders, nothing has moved.
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _measure();
      _scheduleMeasure();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hole = _hole;
    const transparent = Color(0x00000000);

    return Positioned.fill(
      child: Stack(
        children: [
          // THE DIMMING — one painted mask, hole and all, so there is no
          // seam between two abutting pieces the way four separately
          // coloured Positioned rects could show one.
          if (widget.dim)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HolePainter(hole: hole, circular: widget.circular),
                ),
              ),
            ),
          // THE TAP-BLOCKING — invisible, and still four rects around the
          // hole rather than one painted region: the gap between them is
          // what makes the hole genuinely interactive with no custom
          // hit-testing at all.
          if (hole == null)
            _Scrim(color: transparent, onTap: widget.onScrimTap)
          else ...[
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: hole.top,
              child: _Scrim(color: transparent, onTap: widget.onScrimTap),
            ),
            Positioned(
              left: 0,
              top: hole.bottom,
              right: 0,
              bottom: 0,
              child: _Scrim(color: transparent, onTap: widget.onScrimTap),
            ),
            Positioned(
              left: 0,
              top: hole.top,
              width: hole.left,
              height: hole.height,
              child: _Scrim(color: transparent, onTap: widget.onScrimTap),
            ),
            Positioned(
              left: hole.right,
              top: hole.top,
              right: 0,
              height: hole.height,
              child: _Scrim(color: transparent, onTap: widget.onScrimTap),
            ),
            // Glow frame around the hole — draws attention without
            // intercepting the pointer. The kit's gold, and a rounded
            // rectangle rather than FoE's facet: nothing else in the
            // redesigned UI is bevelled any more, so a facet read as a
            // leftover from the old chrome (2026-09-21).
            if (widget.showRing)
              Positioned.fromRect(
                rect: hole,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: widget.circular
                          ? const CircleBorder(
                              side: BorderSide(
                                color: CreamPalette.gold,
                                width: 2.5,
                              ),
                            )
                          : RoundedRectangleBorder(
                              borderRadius: vr(12),
                              side: const BorderSide(
                                color: CreamPalette.gold,
                                width: 2.5,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            if (widget.hint != null) _hintLabel(context, hole),
          ],
        ],
      ),
    );
  }

  void _measure() {
    if (!mounted) return;
    final targetContext = IntroSpotlightAnchors.of(
      widget.anchorName,
    ).currentContext;
    final box = targetContext?.findRenderObject() as RenderBox?;
    final overlayBox = context.findRenderObject() as RenderBox?;
    Rect? next;
    if (box != null &&
        box.hasSize &&
        overlayBox != null &&
        overlayBox.hasSize) {
      // Map BOTH corners through localToGlobal rather than taking the
      // target's own (unscaled) box.size — every other anchor in the game
      // sits in a 1:1 layout, where those are the same rect, but the
      // overworld's nodes live inside an InteractiveViewer's zoom (user
      // 2026-09-03: "Die Markierung ist an der falschen Position"). Taking
      // box.size there under-measured the node at whatever the viewer's
      // scale was, leaving the hole sized for the UNZOOMED node and
      // anchored only at its top-left corner.
      final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
      final bottomRight = box.localToGlobal(
        Offset(box.size.width, box.size.height),
        ancestor: overlayBox,
      );
      next = Rect.fromPoints(topLeft, bottomRight).inflate(widget.padding);
    }
    final nextSize = overlayBox != null && overlayBox.hasSize
        ? overlayBox.size
        : null;
    if (next != _hole || nextSize != _overlaySize) {
      setState(() {
        _hole = next;
        _overlaySize = nextSize;
      });
    }
  }

  /// Hint below the hole, or above it when the hole is in the bottom half —
  /// wherever there's room to read. PINNED to the hole horizontally (user
  /// 2026-09-30: "an den Button anheften (mit etwas space) und nicht
  /// zentriert") rather than centred across the full screen width — for a
  /// target off to one side (the Map tile in a bottom corner, say) a
  /// screen-centred bubble used to float nowhere near what it's talking
  /// about.
  Widget _hintLabel(BuildContext context, Rect hole) {
    // This overlay's OWN box, not the screen's — see [_overlaySize]'s doc
    // comment on why the two differ for an overlay drawn inside a
    // width-capped dialog.
    final size = _overlaySize ?? MediaQuery.sizeOf(context);
    final below = hole.bottom < size.height * 0.6;
    const margin = 16.0;
    final maxWidth = math.min(260.0, size.width - margin * 2);
    final left = (hole.center.dx - maxWidth / 2).clamp(
      margin,
      size.width - maxWidth - margin,
    );
    return Positioned(
      left: left,
      width: maxWidth,
      top: below ? hole.bottom + 10 : null,
      bottom: below ? null : size.height - hole.top + 10,
      child: IgnorePointer(
        // The same paper the guide card is made of, so the hint reads as
        // the card still talking rather than as a second voice
        // (2026-09-21). A [raisedTile] and not a full [creamCard]: it is
        // one line, and the card's iso-grid pattern under that much
        // whitespace looks like a card that failed to fill.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: raisedTile(lit: true, radius: 12),
          child: Text(
            widget.hint!,
            textAlign: TextAlign.center,
            style: FoE.label(size: 12).copyWith(color: kBoxInk),
          ),
        ),
      ),
    );
  }
}

/// A screen-wide dead zone with NO hole and NO darkening — blocks every tap
/// without hiding anything underneath. For a moment with nothing to press
/// and nothing to point at (user 2026-09-30, battle_screen's own enemy-turn
/// window while its scripted fight runs: "während den Attacken soll der
/// ganze Screen frei sein (nicht abgedunkelt) aber ich kann nichts anwählen,
/// bis der nächste Tutorialschritt kommt") — [IntroSpotlightOverlay] would
/// have nothing to anchor a hole to here, and darkening the screen just to
/// show nothing would hide the very animation the player is meant to watch.
class IntroBlockOverlay extends StatelessWidget {
  const IntroBlockOverlay({super.key});

  @override
  Widget build(BuildContext context) =>
      const Positioned.fill(child: _Scrim(color: Color(0x00000000)));
}

/// Paints [CreamPalette.dim] everywhere in the widget's bounds EXCEPT [hole]
/// (a plain rect, or a circle when [circular]) — ONE fill with a hole erased
/// out of it via `saveLayer` + `BlendMode.clear`, so there is no seam for two
/// separately-drawn pieces to ever show at their shared edge the way the
/// previous four-rectangle scrim could.
///
/// NOT `Path.combine(PathOperation.difference, …)` — tried first, since it's
/// the obvious one-call way to cut a hole in a path. It compiles and runs
/// with no error, but on this Flutter/CanvasKit web build it does not
/// reliably return "outer minus hole": across otherwise-identical runs it
/// was observed to return the unmodified outer path (hole not cut, like
/// there were no hole at all) AND, separately, something that painted
/// nothing at all — confirmed with a debugPrint of the actual masked path
/// landing in Chrome's own console, not just inferred from the screenshot.
/// `saveLayer`/`BlendMode.clear` needs no path-ops support at all — it is
/// the standard, broadly-supported technique for this exact "dim everything
/// except a hole" shape, used by most spotlight/coach-mark packages.
class _HolePainter extends CustomPainter {
  final Rect? hole;
  final bool circular;
  const _HolePainter({required this.hole, required this.circular});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, Paint()..color = CreamPalette.dim);
    final h = hole;
    if (h != null) {
      final erase = Paint()..blendMode = BlendMode.clear;
      if (circular) {
        canvas.drawOval(h, erase);
      } else {
        canvas.drawRect(h, erase);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.circular != circular;
}

/// One dimming rectangle that eats every pointer that lands on it. A bare
/// colored box would let taps fall through to the UI beneath; an
/// [AbsorbPointer] would need a gesture arena entry to win drags. Opaque
/// hit-test behavior with no recognizers swallows both.
class _Scrim extends StatelessWidget {
  final Color color;
  final VoidCallback? onTap;
  const _Scrim({required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    // A pure dead zone (no real [onTap] — most spotlit steps) must not
    // animate as if it did something. `Pressable` keys its press feedback on
    // "onTap != null", and the old `onTap ?? () {}` here always satisfied
    // that, so tapping anywhere in the dimmed area played the same
    // darken+depth animation a real button gives, whether or not anything
    // happened (user report 2026-09-30: "Ich kann die abgedunkelten
    // Flächen anwählen. Es passiert nichts, ausser dass es einen Klickeffekt
    // gibt."). A bare GestureDetector still swallows the tap — nothing under
    // the scrim is reachable either way — it just gives no feedback when
    // there is nothing to give feedback ABOUT. Only the battle screen's
    // sequential callouts and its info hints pass a real [onTap], and keep
    // Pressable's animation, since tapping there genuinely advances them.
    if (onTap == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(color: color),
      );
    }
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: onTap!,
      child: ColoredBox(color: color),
    );
  }
}
