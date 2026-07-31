import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../models/creature_enums.dart' show CreatureElement;
import 'creature_backdrop.dart';

// ── Der Kampfplatz (user 2026-07-31) ─────────────────────────
// "Jetzt kann der Hintergrund nicht mehr der Typ sein, da es mehrere haben kann.
//  Welche Lösung gibt es?"
//
// It used to be the lead monster's ELEMENT: each half of the field was tiled
// with a fire/water/plant backdrop. That worked while a side was one monster and
// broke the moment a rank could hold three — the tile picked one of the three
// and presented it as the world. Type is a property of a MONSTER, so it went
// where it belongs (the plate each one stands on); the background answers the
// other question instead: WHERE is this fight happening.
//
// The region's own art when it has been uploaded (AreaDef.imageUrl), else the
// era's painted gradient — a fallback that has to look deliberate, because most
// regions will not have art for a long time and "no image yet" must never read
// as "something failed to load".
/// The overworld's own ground, used as the stand-in battlefield until a region
/// has art of its own (user 2026-07-31). Same file the map draws.
const String kOverworldGroundAsset = 'assets/images/overworld_grass.png';

class BattleScene extends StatelessWidget {
  /// The region's scene art. Null = the era gradient.
  final String? imageUrl;

  /// 1-based era, for the fallback palette. Out-of-range values wrap, so a
  /// ninth era invents no crash.
  final int era;

  const BattleScene({super.key, this.imageUrl, this.era = 1});

  /// Sky/ground pair per era — the chapters read as different WORLDS: a green
  /// valley, then bare stone, then embers, and so on up the ladder.
  static const List<List<Color>> _eraPalette = [
    [Color(0xFF3E6B45), Color(0xFF23331F)], // I   verdant
    [Color(0xFF4E5A63), Color(0xFF23282B)], // II  stone
    [Color(0xFF6B4433), Color(0xFF2B1B16)], // III ember
    [Color(0xFF3F5570), Color(0xFF1B2430)], // IV  tide
    [Color(0xFF5C4A6B), Color(0xFF241D2B)], // V   dusk
    [Color(0xFF6B6242), Color(0xFF2B271B)], // VI  sand
    [Color(0xFF3A6B66), Color(0xFF162B29)], // VII glass
    [Color(0xFF4A4F6B), Color(0xFF1D1F2B)], // VIII crystal
  ];

  static List<Color> paletteFor(int era) =>
      _eraPalette[(era - 1).clamp(0, _eraPalette.length - 1)];

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(era);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.first, palette.last],
            ),
          ),
        ),
        if (imageUrl != null)
          Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            // A broken URL leaves the ground below standing rather than a grey
            // box with an icon in it — the fallback IS the design, not an error
            // state, so failing back to it costs nothing.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        else
          // ── Für's Erste der Overworld-Boden (user 2026-07-31) ──
          // "nimm den Hintergrund von der Overworld vorerst als Hintergrund für
          //  den Kampfscreen"
          //
          // The trail you walked in on, under the fight it led to — which is
          // truer than any gradient while no region has its own art yet, and it
          // is one asset the game already ships. The era palette stays UNDER it
          // as the last resort: it is what tints the scene if this asset ever
          // goes missing, and what a later era will fall back to before its own
          // ground exists.
          Image.asset(
            kOverworldGroundAsset,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        // The horizon: a band of light across the middle, where the two ranks
        // meet. It gives the field a floor without drawing a line on it, and it
        // is what keeps a photographic region image from swallowing the sprites.
        const _Horizon(),
        // Corner shade, so the nameplates and the log always sit on something
        // darker than themselves whatever the art behind them does.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [
                    Colors.transparent,
                    FoE.bg.withValues(alpha: 0.55),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Horizon extends StatelessWidget {
  const _Horizon();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.07),
            Colors.transparent,
          ],
          stops: const [0.36, 0.5, 0.64],
        ),
      ),
    ),
  );
}

/// The PLATFORM a fighter stands on — a slab of ground wearing the monster's
/// own type, with its HP running round the front edge (user 2026-07-31: "der
/// Typ ist so fast nicht ersichtlich, mache wie eine Plattform, Kampfplatz für
/// die Monster" → "das Logo wie bei der monster card in den Hintergrund der
/// Plattform einarbeiten" → "der hp balken wird zum Rand der Plattform, wobei
/// dieser ein Halbkreis bleibt").
///
/// The surface IS the card's: [CreatureBackdrop] paints the same diagonal
/// element gradient and embosses the same type glyph into it, so a monster's
/// platform and its card are the same material. Anything hand-mixed here would
/// drift from the card the first time the card changed.
///
/// Its FRONT EDGE is the health bar — the semicircle facing you, on the slab's
/// own curve. It is the only piece of chrome that can sit on a crowded field
/// without taking space from anything: a straight bar under six monsters is six
/// more rectangles, while the edge of a shape that is already there costs
/// nothing. There is no rim anywhere else: a second stroked arc, however thin,
/// is a second bar to anyone who has not read this file.
///
/// One monster, one platform, which is the whole point: a rank of three can hold
/// three types, and the half-wide tile this replaced could only ever show one.
/// [dim] fades the flanks standing further back.
class TypePodium extends StatelessWidget {
  final CreatureElement element;
  final double width;
  final bool dim;

  /// 0..1 of its health, or null for a platform with nobody on it (previews,
  /// the dev form) — then the whole rim is plain.
  final double? hpFraction;

  /// The bar's colour at this level of health. The battle screen owns that
  /// scale (green → amber → red), so it hands the answer down rather than this
  /// widget inventing a second one.
  final Color hpColor;

  const TypePodium({
    super.key,
    required this.element,
    required this.width,
    this.dim = false,
    this.hpFraction,
    this.hpColor = const Color(0xFF6FBF73),
  });

  @override
  Widget build(BuildContext context) {
    final height = width * 0.34;
    // A true ellipse: BoxShape.circle would draw a circle of the shorter side,
    // which on a wide platform is a coin lying in the middle of it.
    final oval = BorderRadius.all(Radius.elliptical(width / 2, height / 2));
    return Opacity(
      opacity: dim ? 0.72 : 1.0,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The shadow the slab casts. Its own layer because the surface
            // above is clipped, and a clip eats the shadow of the thing it
            // clips.
            //
            // ONE RING ONLY (user 2026-07-31: "gibt es jetzt 2 Balken?"). There
            // used to be a second BoxShadow here, a halo in the element's own
            // colour meant to lift the slab off the region art — but a coloured
            // glow hugging the edge, next to a coloured rim, is two rings, and
            // the rim is the health bar. A bar you can mistake for decoration is
            // worse than a slab that blends in a little.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: oval,
                boxShadow: [
                  BoxShadow(
                    color: FoE.bg.withValues(alpha: 0.55),
                    blurRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
            // THE CARD'S OWN SURFACE — same gradient, same embossed glyph.
            // Watermarked to the LEFT because the monster stands in the middle
            // and would otherwise be standing on its own type symbol.
            ClipRRect(
              borderRadius: oval,
              child: CreatureBackdrop(
                element: element,
                radius: 0,
                watermarkLeft: true,
                // The platform is a wide, shallow strip, so the glyph is scaled
                // off its SHORT side and needs the boost to fill it the way it
                // fills a card.
                symbolScale: 1.9,
                child: const SizedBox.expand(),
              ),
            ),
            // A lit near edge — the monster stands ON this, so the front catches
            // the light and the back does not.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: oval,
                // A WASH, not an edge: the dark band that used to sit at the
                // bottom traced the ellipse just inside the rim, which is the
                // other half of "two bars".
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.75],
                ),
              ),
            ),
            // The health, drawn last so nothing paints over it.
            CustomPaint(
              painter: _PodiumRim(hpFraction: hpFraction, hpColor: hpColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// The health bar, drawn on the platform's own curve (user 2026-07-31: "Der HP
/// Balken soll genau die Krümmung haben wie das Podest, so als sähe es aus, als
/// wäre der HP Balken der Rand des Podests" → "lösche den anderen Balken und
/// allgemein den Rand des Podests").
///
/// NOTHING ELSE IS STROKED. The platform used to carry a plain rim all the way
/// round, and a second arc beside the gauge — however thin — is a second bar to
/// anyone who has not read this file. The slab's own edge is where its surface
/// stops; it needs no line to say so, and without one there is exactly one
/// stroked thing on a platform and it means exactly one thing.
///
/// The arc is the FRONT half (0 → π: 0 rad is 3 o'clock and positive sweeps
/// clockwise, so that is the half facing the player), on the ellipse the
/// platform itself is cut to — deflated by half its own width, which puts the
/// stroke's outer edge on the slab's edge. That is what makes it read as the
/// rim rather than as a bar lying on top.
class _PodiumRim extends CustomPainter {
  final double? hpFraction;
  final Color hpColor;

  const _PodiumRim({required this.hpFraction, required this.hpColor});

  static const double _front = 3.1415926535897932;

  /// Thick on purpose (user 2026-07-31: "dafür dicker machen, damit er besser
  /// ersichtlich ist") — it is the only gauge each monster has now that the
  /// straight bar under the name is gone.
  static const double _kGauge = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final frac = hpFraction;
    // Nobody standing here: nothing to report, so nothing is drawn.
    if (frac == null) return;

    final path = (Offset.zero & size).deflate(_kGauge / 2);
    Paint stroke(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = c
      ..strokeWidth = _kGauge;

    // The empty track first — without it a half-full bar has no end to be read
    // against, and "half health" and "a short platform" look the same.
    canvas.drawArc(
      path,
      0,
      _front,
      false,
      stroke(const Color(0xFF11161A).withValues(alpha: 0.8)),
    );
    final v = frac.clamp(0.0, 1.0);
    if (v <= 0) return;
    // Filled from the LEFT end so it drains to the right the way every other bar
    // in the game does. Sweeping backwards from π is what puts the start on the
    // left.
    canvas.drawArc(path, _front, -_front * v, false, stroke(hpColor));
  }

  @override
  bool shouldRepaint(_PodiumRim old) =>
      old.hpFraction != hpFraction || old.hpColor != hpColor;
}
