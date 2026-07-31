import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/widgets/scroll_paper.dart' show kParchmentInk;
import '../models/breeding_job.dart';
import '../models/creature_enums.dart';
import '../models/species_def.dart';
import '../services/creature_power.dart';
import 'creature_sprite.dart';

/// The parchment screens' accent gold — the same value the Hatchery, the
/// breeding page and the building dialog each declare for their own readouts.
const Color _kParchmentAccent = FoE.gold;

/// Luminance-preserving greyscale (Rec. 709 weights), applied to the egg glyph
/// before it is tinted — see the comment at its use. Alpha is passed through
/// untouched so the shell keeps its silhouette.
const List<double> _kGreyscale = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

/// An egg, standing free on the parchment: the shell, its POWER and its NAME —
/// nothing else (user 2026-07-27: "Die Kachel kann gelöscht werden, nur die
/// Power und der Name soll stehen bleiben").
///
/// It began as [CreatureCard]'s tile with the egg swapped in for the sprite,
/// and the tile turned out to be carrying nothing: the element backdrop said
/// the same thing the shell's own colour now says, and the rarity strip framed
/// data that had already been cut back to one line. What is left is the object
/// itself on the page — which is what an egg in a bag is.
///
/// The shell wears its TYPE's colour and holds the monster's silhouette, so it
/// still answers "what is in there?" without a frame around it.
///
/// The ⚡ is the frozen child's gene sum ([genePower]) — the same figure the
/// breeding screen ranks parents by, which is what makes two eggs of one
/// species comparable at a glance. An egg laid before migration 0027 carries no
/// genes; it shows "⚡ ?" rather than a made-up number.
class EggCard extends StatelessWidget {
  final BreedingJob job;
  final VoidCallback? onTap;

  /// Marks the egg currently chosen in the Hatchery's slot — a green check in
  /// the same corner the breeding picker puts it.
  final bool selected;

  const EggCard({
    super.key,
    required this.job,
    this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final species = kSpeciesDefs[job.speciesId];

    return GestureDetector(
      onTap: onTap,
      // THE WHOLE CELL TAKES THE TAP (user 2026-07-27: "wenn ich auf das ei
      // klicke, soll es auch ausgewählt werden, nicht nur der name").
      //
      // Without this only the two caption lines answered: a GestureDetector
      // hit-tests what its child PAINTS, the Column paints nothing of its own,
      // and the egg above it sits in an IgnorePointer. So the one part of the
      // card you would actually aim at was the one part that was dead.
      behavior: HitTestBehavior.opaque,
      // Caption UNDER the egg, both lines together (user 2026-07-27: "Den Namen
      // und die Power besser positionieren und stylen"). The power used to
      // float in the top-right corner — that was its place on the TILE, where a
      // frame held it; with the frame gone it read as a stray number beside the
      // egg rather than as a fact about it.
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Off-centre BY THE SHADOW'S WIDTH (user 2026-07-27: "Der Name
                // wirkt nicht zentriert zum Ei"). The shell sat exactly in the
                // middle, but its drop shadow adds 4 px of mass on the right
                // only — so the thing you SEE is 2 px right of centre, and a
                // caption centred on the cell reads as 2 px left of the egg.
                //
                // Leaving the extra room on the right instead puts shell +
                // shadow in the middle, which is what the eye lines the text up
                // with. Keep `right` = `left` + the shadow's x-offset.
                Positioned.fill(
                  left: 4,
                  right: 8,
                  child: IgnorePointer(child: EggGlyph(job: job)),
                ),
                if (selected)
                  const Positioned(
                    top: 0,
                    left: 0,
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: FoE.positive,
                    ),
                  ),
              ],
            ),
          ),
          // Tight against the shell (user 2026-07-27: "Name näher an das Ei
          // rücken") — the caption belongs to the egg, and a gap made it look
          // like a separate row.
          const SizedBox(height: 1),
          // THE POWER CAME BACK OUT OF THE SHELL (user 2026-07-27: "Nimm die
          // Energie aus dem Ei raus und unter Das Ei"). Directly under the egg,
          // above the name: on the shell it had to fight the silhouette behind
          // it for contrast, and it needed a drop shadow to win — on the
          // parchment it just reads.
          //
          // Accent gold, the tone every other comparable number on this paper
          // wears; white would disappear here.
          // Nudged 4 px left (user 2026-07-27). The ⚡ carries a trailing space
          // in the emoji font that the name line does not, so centring the two
          // strings on the same axis still left the power sitting right of the
          // name. A transform, not padding: this is an optical correction, and
          // it must not change what the column reserves.
          Transform.translate(
            offset: const Offset(-4, 0),
            child: Text(
              job.hasChildGenes ? '⚡ ${genePower(job.childBase)}' : '⚡ ?',
              style: FoE.value(size: 13).copyWith(color: _kParchmentAccent),
            ),
          ),
          // The SPECIES, not "<species> Egg" (user 2026-07-27: "man sieht, dass
          // es ein Ei ist") — the shell is the whole picture above it.
          Text(
            species?.name ?? job.speciesId,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 12).copyWith(color: kParchmentInk),
          ),
        ],
      ),
    );
  }

}

/// JUST THE EGG — the tinted shell with the monster's silhouette inside it and
/// its drop shadow, filling whatever box it is given. No caption, no power, no
/// tap.
///
/// Split out of [EggCard] (user 2026-07-27: "das png durch das Ei mit dem
/// Monsterschatten ersetzen") so the Hatchery's incubating rows can show the
/// same object at thumbnail size. They showed the species sprite there, which
/// is a picture of something that has not hatched yet.
class EggGlyph extends StatelessWidget {
  final BreedingJob job;

  const EggGlyph({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    final species = kSpeciesDefs[job.speciesId];
    // THE SHADOW IS THE TYPE'S COLOUR (user 2026-07-27: "wie dies bei den
    // Typicons der Fall ist") — [CreatureElement.shadowColor], the exact tone
    // the type-icon emboss uses for its extruded face and every monster sprite
    // for its drop shadow. So an egg casts the same shadow its hatchling will.
    final elementShadow =
        (species?.element ?? CreatureElement.fire).shadowColor;
    // THE EGG WEARS ITS TYPE (user 2026-07-27), tinted rather than filled flat
    // — the shell KEEPS ITS STRUCTURE (user 2026-07-27: "Das Ei soll die
    // Struktur behalten"), only the top-left gloss is painted out (see [_Egg]).
    //
    // Lightened towards white so the dark shape inside still reads against it —
    // but less than before (0.42 → 0.30): the greyscale pass in [_Egg]
    // multiplies the shell's own shading on top, which lightens it again, so
    // the old value washed the type out.
    final shellTint = Color.lerp(
      (species?.element ?? CreatureElement.fire).color,
      Colors.white,
      0.30,
    );

    // The monster is INSIDE IT as a silhouette (user 2026-07-27) — a shape
    // showing through the shell says what is in there without showing the
    // creature, which is exactly what an unhatched egg knows about itself.
    return LayoutBuilder(
      // THE SHADOW SCALES WITH THE EGG (user 2026-07-27: "der Schatten des Eis
      // ist viel zu gross"). Its offset was a fixed 4/6 px, tuned on the big
      // picker tile — on the Hatchery's 46 px row thumbnail those same pixels
      // are a tenth of the whole egg, so the shadow read as a second egg
      // behind the first.
      //
      // [_kShadowRef] is the size that offset was chosen at; everything else is
      // a proportion of it.
      builder: (context, box) {
        // Clamped: an unbounded box would make this infinite, and an infinite
        // Transform offset poisons layout and hit testing downstream. The
        // callers all give it a bounded box today; this keeps a future one from
        // finding out the hard way.
        final k = (box.biggest.shortestSide / _kShadowRef).clamp(0.0, 4.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _eggShadow(elementShadow, k)),
            Positioned.fill(
              child: _Egg(
                inside: _silhouette(species?.stageAt(0).imageUrl),
                tint: shellTint,
              ),
            ),
          ],
        );
      },
    );
  }

  /// The box size the shadow's 4/6 px offset was tuned at — the picker tile's
  /// art area. See the [LayoutBuilder] above.
  static const double _kShadowRef = 120;

  /// The monster showing through the shell: its sprite flattened to one soft
  /// dark tone — the Bestiary's shrouded silhouette, lightened, because here it
  /// is meant to look like a shape seen THROUGH something rather than a
  /// blacked-out secret.
  ///
  /// A species with no art contributes nothing: an empty egg beats a stand-in
  /// paw print, which would read as the species itself.
  Widget? _silhouette(String? url) => url == null
      ? null
      : ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0x8C1A1208),
            BlendMode.srcIn,
          ),
          child: CreatureSprite(
            url: url,
            alignment: Alignment.bottomCenter,
            fallback: const SizedBox.shrink(),
          ),
        );

  /// The egg's drop shadow: its own silhouette in [color], nudged down-right by
  /// [scale] × the reference offset — a sprite's shadow ([CreatureCard]'s
  /// `_creatureShadow`) at full size rather than shrunk to 0.9: the shell is a
  /// smooth oval with none of a sprite's outline, so at 0.9 the shadow vanished
  /// behind it entirely. At 1.0 a clean crescent sits along the bottom-right
  /// edge.
  ///
  /// Without the monster inside it — this is the shape the egg casts on the
  /// page, and the shell is opaque to it.
  Widget _eggShadow(Color color, double scale) => Transform.translate(
    offset: Offset(4 * scale, 6 * scale),
    child: ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcATop),
      child: const _Egg(),
    ),
  );
}

/// The egg glyph filling its box, bottom-anchored — as large as the space
/// allows, sitting on the name line.
///
/// [FittedBox] rather than a computed font size: an emoji's drawn height is not
/// its point size, and the tile appears at two scales (the Hatchery slot and
/// the picker grid). Scaling a fixed glyph to the box is the only version that
/// fills both identically.
///
/// [inside] rides INSIDE the same FittedBox, positioned in the glyph's own
/// coordinates — that is the point of the nested Stack. Placed in the outer art
/// box instead it would drift, because the egg is width-limited and
/// bottom-anchored in a box much taller than itself.
class _Egg extends StatelessWidget {
  /// Drawn within the shell, at the fat lower end where an egg is opaque
  /// enough to hold a shape.
  final Widget? inside;

  /// The shell's colour (user 2026-07-27: "Nimm die Farbe des Typs für das
  /// jeweilige Ei"). MULTIPLIED onto the glyph, so the emoji's own shading
  /// survives and the shell keeps its structure — only the gloss is painted
  /// out first, see [_shell].
  ///
  /// Null leaves the glyph alone — the drop-shadow copy, whose colour is
  /// replaced wholesale anyway.
  final Color? tint;

  const _Egg({this.inside, this.tint});

  /// The emoji's body tone, the colour the gloss is patched over WITH. Read off
  /// the shell right beside the highlight rather than picked: patched in the
  /// glyph's own palette, before any tint, it disappears into the surface for
  /// every element colour at once.
  static const Color _shellBody = Color(0xFFF2EBE0);

  /// The glyph with its top-left specular blown out (user 2026-07-27: "Das Ei
  /// soll die Struktur behalten nur die Helle reflektion oben links will ich
  /// nicht").
  ///
  /// A soft patch of the body tone over the highlight, NOT a filter. Every
  /// filter that reaches a white specular reaches the shading with it —
  /// `srcIn` flattens the shell to one colour and a luminance squeeze dulls
  /// the whole curve. The structure the user wants kept IS that curve, so the
  /// gloss has to be covered rather than filtered.
  ///
  /// SHAPED LIKE THE GLOSS, not like a dot (user 2026-07-27: "nur diese helle
  /// bereich möchte ich nicht haben"). The specular on the 🥚 is a long streak
  /// following the shell's upper-left curve, so a round patch left its two ends
  /// showing — which is the bright area that was still there. This is an
  /// elongated, tilted ellipse laid along that same curve, big enough to take
  /// the whole streak.
  ///
  /// The patch sits at fixed glyph coordinates, which means it is aimed at
  /// where the platform's 🥚 puts its highlight. Fully transparent at the rim
  /// and well inside the oval, so a miss shows as nothing rather than as a
  /// blob on the backdrop.
  Widget _shell() => Stack(
    alignment: Alignment.center,
    children: [
      const Text('🥚', style: TextStyle(fontSize: 100)),
      Positioned.fill(
        child: Align(
          alignment: const Alignment(-0.34, -0.30),
          child: FractionallySizedBox(
            widthFactor: 0.34,
            heightFactor: 0.50,
            child: Transform.rotate(
              // Tilted with the shell: the streak runs down-left to up-right
              // along the egg's flank, not straight up the box.
              angle: -0.5,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  // A rectangle box makes the radial gradient an ELLIPSE
                  // stretched to it — the streak shape. BoxShape.circle would
                  // force it back to round.
                  gradient: RadialGradient(
                    colors: [_shellBody, _shellBody, Color(0x00F2EBE0)],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.contain,
    alignment: Alignment.bottomCenter,
    child: Stack(
      alignment: Alignment.center,
      children: [
        // Sizes the Stack — everything else is measured against this glyph.
        if (tint == null)
          _shell()
        else
          ColorFiltered(
            // modulate, not srcIn: it multiplies the tint into the artwork and
            // leaves the shading intact. srcIn would fill the silhouette flat
            // and take the structure with the gloss.
            colorFilter: ColorFilter.mode(tint!, BlendMode.modulate),
            // GREYSCALE FIRST, or the type colour comes out wrong (user
            // 2026-07-27: "hier sollte es wohl blau sein" — a Waveshark egg
            // rendered green).
            //
            // modulate MULTIPLIES, and the 🥚 glyph is a warm cream, not white.
            // A blue tint times a yellow shell is green; every cool type came
            // out shifted towards the emoji's own hue. Stripped to luminance
            // first, the multiply has nothing left to shift: what survives is
            // the shading, and the colour is purely the tint's.
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix(_kGreyscale),
              child: _shell(),
            ),
          ),
        if (inside != null)
          Positioned.fill(
            child: Align(
              // Below centre: the egg's wide end, and the only part of the
              // shell with room for a silhouette that does not touch an edge.
              alignment: const Alignment(0, 0.18),
              child: FractionallySizedBox(
                // NOTHING MAY STICK OUT (user 2026-07-27: "Das Monsterpng muss
                // immer innerhalb des Eis Platz haben").
                //
                // These fractions are of the GLYPH'S TEXT BOX, and the drawn
                // egg is much smaller than that box — an emoji sits inside a
                // full line box with side bearings and leading. The old 0.70
                // was therefore WIDER than the shell itself, so a broad sprite
                // ran over both flanks.
                //
                // 0.52 × 0.46 fits the widest part of the shell with room to
                // spare, and the ClipOval below makes it hold whatever the
                // platform's egg glyph actually looks like: the sprite is
                // BoxFit.contain'd into this box, so the box is the guarantee,
                // and an ellipse inscribed in it is strictly smaller again.
                widthFactor: 0.52,
                heightFactor: 0.46,
                child: ClipOval(child: inside),
              ),
            ),
          ),
      ],
    ),
  );
}
