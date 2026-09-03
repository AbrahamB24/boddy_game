import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';

// ── Tutorial spotlight ────────────────────────────────────────
// The guided intro (user design 2026-07-17) highlights exactly ONE control at
// a time: the target stays bright and tappable, everything else is dimmed AND
// dead. That second half is the point — a tutorial that merely *suggests*
// where to tap still lets a new player wander into screens the script hasn't
// explained yet, and then the script is narrating a state it isn't in.
//
// Mechanically this is four opaque scrims AROUND the target's rect rather
// than one scrim with a punched hole: the gap between the scrims IS the
// hole, so target hit-testing needs no custom render object — pointers over
// the target never meet the overlay at all. The scrims absorb taps AND
// drags (opaque hit test, no recognizers), so nothing under them scrolls,
// pans or taps.

/// Registry of spotlight anchors. Screens hang a [GlobalKey] per highlight
/// target on their widgets and look it up here by a stable name, so the
/// intro flow can say "highlight 'quick-build'" without the two screens
/// knowing each other.
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

  /// False makes the scrim fully TRANSPARENT instead of the usual ~70%
  /// black — everywhere outside the hole is still dead (taps absorbed,
  /// nothing pressable), just not visually darkened. For a screen where
  /// there's something worth WATCHING outside the one lit control (user
  /// 2026-09-03, the battle screen specifically: "ich möchte aber, dass der
  /// gesamte screen erhellt ist, damit ich das Kampfgeschehen verfolgen
  /// kann" — HP bars dropping, hit reactions, floating numbers) rather than
  /// a screen that's genuinely just one button and a lot of nothing.
  final bool dim;

  const IntroSpotlightOverlay({
    super.key,
    required this.anchorName,
    this.hint,
    this.padding = 6,
    this.circular = false,
    this.onScrimTap,
    this.dim = true,
  });

  @override
  State<IntroSpotlightOverlay> createState() => _IntroSpotlightOverlayState();
}

class _IntroSpotlightOverlayState extends State<IntroSpotlightOverlay> {
  Rect? _hole;

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
    // ~70% black — dim, not blind. Fully transparent when [dim] is false;
    // the scrim rects still absorb every tap either way.
    final scrim = widget.dim
        ? const Color(0xB3000000)
        : const Color(0x00000000);

    return Positioned.fill(
      child: hole == null
          ? _Scrim(rect: null, color: scrim, onTap: widget.onScrimTap)
          : Stack(
              children: [
                // Four scrims around the hole; the gap between them is the
                // one place a pointer reaches the real UI.
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: hole.top,
                  child: _Scrim(
                    rect: null,
                    color: scrim,
                    onTap: widget.onScrimTap,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: hole.bottom,
                  right: 0,
                  bottom: 0,
                  child: _Scrim(
                    rect: null,
                    color: scrim,
                    onTap: widget.onScrimTap,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: hole.top,
                  width: hole.left,
                  height: hole.height,
                  child: _Scrim(
                    rect: null,
                    color: scrim,
                    onTap: widget.onScrimTap,
                  ),
                ),
                Positioned(
                  left: hole.right,
                  top: hole.top,
                  right: 0,
                  height: hole.height,
                  child: _Scrim(
                    rect: null,
                    color: scrim,
                    onTap: widget.onScrimTap,
                  ),
                ),
                // Glow frame around the hole — draws attention without
                // intercepting the pointer.
                Positioned.fromRect(
                  rect: hole,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: widget.circular
                            ? const CircleBorder(
                                side: BorderSide(
                                  color: FoE.goldBright,
                                  width: 2,
                                ),
                              )
                            : FoE.facet(
                                radius: 10,
                                side: BorderSide(
                                  color: FoE.goldBright,
                                  width: 2,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                if (widget.hint != null) _hintLabel(context, hole),
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
    if (next != _hole) setState(() => _hole = next);
  }

  /// Hint below the hole, or above it when the hole is in the bottom half —
  /// wherever there's room to read.
  Widget _hintLabel(BuildContext context, Rect hole) {
    final screenH = MediaQuery.sizeOf(context).height;
    final below = hole.bottom < screenH * 0.6;
    return Positioned(
      left: 16,
      right: 16,
      top: below ? hole.bottom + 12 : null,
      bottom: below ? null : screenH - hole.top + 12,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: FoE.panel(radius: 10, overrideBorder: FoE.goldBright),
            child: Text(
              widget.hint!,
              textAlign: TextAlign.center,
              style: FoE.label(size: 12).copyWith(color: FoE.parchment),
            ),
          ),
        ),
      ),
    );
  }
}

/// One dimming rectangle that eats every pointer that lands on it. A bare
/// colored box would let taps fall through to the UI beneath; an
/// [AbsorbPointer] would need a gesture arena entry to win drags. Opaque
/// hit-test behavior with no recognizers swallows both.
class _Scrim extends StatelessWidget {
  final Rect? rect; // unused, kept for readability at call sites
  final Color color;
  final VoidCallback? onTap;
  const _Scrim({required this.rect, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap ?? () {},
    child: ColoredBox(color: color),
  );
}
