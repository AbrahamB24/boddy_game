import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/species_def.dart';
import '../services/creature_power.dart';
import 'creature_backdrop.dart';
import 'creature_sprite.dart';
import 'xp_arc.dart';
import '../../common/widgets/recess_bar.dart';

/// A monster tile styled like a trading card (user 2026-07-17): a big image
/// that POPS OUT the top (~20% of the art overflows above the tile), a
/// borderless, strongly-rounded tile with the ELEMENT backdrop, and the key
/// data (name, HP, level, power) in a RARITY-coloured strip along the bottom.
///
/// Shared by the Monsters screen and the Bestiary (user 2026-07-18) so both use
/// the exact same tile. The Bestiary uses [CreatureCard.shrouded] for
/// undiscovered species: the same shape, but a dark tile with a black
/// silhouette and every detail hidden.
class CreatureCard extends StatelessWidget {
  final CreatureInstance? creature;
  final String? shroudImageUrl;
  final bool shrouded;
  final VoidCallback? onTap;

  /// The VITALS: the XP arc under the monster's feet and the HP bar in the
  /// strip. Both off in the breeding screen (user 2026-07-27) — a parent is
  /// chosen on its GENES, and neither its level progress nor its wounds are
  /// part of that decision, so they are noise there.
  final bool showXp;
  final bool showHp;

  /// Adds the power at LEVEL 1 under the top-right power readout, small — the
  /// breeding screen's reading (user 2026-07-27). A parent passes on its genes,
  /// not its levels, so there the level-1 figure is worth seeing next to the
  /// current one.
  final bool showLevelOnePower;

  const CreatureCard({
    super.key,
    required CreatureInstance this.creature,
    this.onTap,
    this.showXp = true,
    this.showHp = true,
    this.showLevelOnePower = false,
  }) : shrouded = false,
       shroudImageUrl = null;

  const CreatureCard.shrouded({super.key, this.shroudImageUrl, this.onTap})
    : shrouded = true,
      creature = null,
      // An undiscovered species shows no data at all — the flags are moot.
      showXp = false,
      showHp = false,
      showLevelOnePower = false;

  @override
  Widget build(BuildContext context) {
    final inst = creature;
    final ko = shrouded ? false : inst!.isKo;
    final imageUrl = shrouded ? shroudImageUrl : inst!.imageUrl;
    // ONE TILE, ONE COLOUR — THE TYPE'S (user 2026-07-27: "mache den
    // Hintergrund einmal komplett in der Farbe des Typs und entferne die
    // Seltenheitsstufe").
    //
    // The tile used to be two colours meeting at a seam: the element behind the
    // art, the RARITY behind the name. Two hues on an object this small fought
    // each other, and the rarity half was the louder of the two — a fire
    // monster on a purple plinth read as purple. Rarity has its own homes (the
    // Bestiary, the detail screen, the breeding tables); it does not need to
    // repaint half of every tile.
    //
    // The strip is now the SAME element colour carried on past where the
    // backdrop's diagonal gradient ends (element + 20 % black at its bottom-
    // right corner), just deeper — so the seam reads as the same surface
    // turning into shade rather than as a join between two materials.
    //
    // A shrouded tile has no type to show, so it stays neutral grey.
    final element = shrouded
        ? FoE.textMuted
        : (inst!.species?.element.color ?? FoE.borderGold);
    final stripLight = Color.lerp(element, Colors.black, 0.30)!;
    final stripDark = Color.lerp(element, Colors.black, 0.46)!;
    // The sprite's drop shadow uses the element's own shadow tone — the same
    // colour its type icon is embossed with (user request). Only read for
    // discovered tiles; a shrouded one draws a flat silhouette instead.
    final elementShadow =
        (inst?.species?.element ?? CreatureElement.fire).shadowColor;

    return GestureDetector(
      // THE WHOLE CELL TAKES THE TAP (user 2026-07-27: the Market's ✕ did not
      // remove a hauler).
      //
      // Without this the default is `deferToChild`, and a GestureDetector then
      // hit-tests only what its child actually PAINTS. This tile deliberately
      // leaves its top ~17 % empty for the art to pop into, so every tap in
      // that band fell through — including one on the Market's ✕ badge, which
      // sits exactly there and is the one part of the card that looks like a
      // button. [EggCard] documents the same trap; the tiles simply never had
      // an affordance up there before.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, c) {
          // 54, not 52 (2026-07-27): the rebuilt strip is a name line (14 px
          // at height 1.4 = 20) over a state line (15), and at 52 the column
          // overflowed by exactly 1 px. Two more give it real slack, so a font
          // fallback with different metrics cannot bring the overflow back —
          // pixel-tuning the padding to fit exactly would have been a trap.
          const stripH = 54.0;
          // Reserve room at the top of the cell for the art to pop into, so it
          // overflows the TILE (not the neighbouring cell). Kept small (user
          // 2026-07-18) so the square-sprite pop-out stays ~20px while rows
          // sit close.
          final topReserve = c.maxHeight * 0.17;
          final imgH = c.maxHeight - stripH; // art spans cell-top → strip-top
          final artAreaH = (imgH - topReserve).clamp(0.0, double.infinity);
          return Stack(
            children: [
              // Borderless, strongly-rounded tile: element backdrop + strip,
              // starting BELOW the reserved pop-out space.
              Positioned(
                top: topReserve,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(color: stripDark, shape: FoE.facet(radius: 22)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: shrouded
                            // A shrouded tile hides its type: a plain dark area,
                            // no element backdrop.
                            ? const ColoredBox(color: FoE.bg)
                            : _backdrop(
                                inst!.species,
                                const SizedBox.expand(),
                                radius: 0,
                              ),
                      ),
                      SizedBox(
                        height: stripH,
                        // The type's colour, deepening from the seam DOWNWARD
                        // (user 2026-07-27) — the backdrop's own gradient runs
                        // top-left light to bottom-right dark, and this picks
                        // up where it stops so the two read as one surface.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [stripLight, stripDark],
                            ),
                          ),
                          child:
                              shrouded ? _shroudStrip() : _cardStrip(inst!),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Power (top-right) over the element area — drawn BEFORE the art
              // so the monster overlaps it (user 2026-07-18).
              if (!shrouded)
                Positioned(
                  top: topReserve + 6,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '⚡${totalPower(inst!)}',
                        style: FoE.value(size: showLevelOnePower ? 14 : 11)
                            .copyWith(
                          color: Colors.white,
                          shadows: _stripShadow,
                        ),
                      ),
                      // The genes, small, under the current power (user
                      // 2026-07-27): the big number stays the one every other
                      // screen shows.
                      if (showLevelOnePower)
                        Text(
                          // "lv", not "lvl" (user 2026-07-29).
                          'lv 1  ${levelOnePower(inst)}',
                          style: FoE.dim(size: 10).copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            shadows: _stripShadow,
                          ),
                        ),
                      // THE RARITY, UNDER THE ENERGY (user 2026-07-27:
                      // "schreibe die Seltenheit unter die Energie").
                      //
                      // It left the tile when the strip became one type colour,
                      // and a monster's rarity is worth knowing at a glance —
                      // so it comes back as a WORD rather than as paint. In its
                      // own colour, lightened so it holds against any element
                      // backdrop, and small: it is a label on the power block,
                      // not a second headline.
                      if (inst.species case final sp?)
                        Text(
                          sp.rarity.label,
                          style: FoE.dim(size: 9).copyWith(
                            color: Color.lerp(
                              sp.rarity.color,
                              Colors.white,
                              0.35,
                            ),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            shadows: _stripShadow,
                          ),
                        ),
                    ],
                  ),
                ),
              // The monster art — bottom-aligned so its feet sit at the strip
              // and its top overflows above the tile.
              Positioned(
                top: 0,
                left: 4,
                right: 4,
                height: imgH,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: ko ? 0.35 : 1,
                    child: shrouded
                        ? _silhouette(imageUrl)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              // Drop shadow behind the sprite — its silhouette
                              // in the element's shadow tone (matching its type
                              // icon), blurred + nudged down.
                              Positioned.fill(
                                child: _creatureShadow(imageUrl, elementShadow),
                              ),
                              Positioned.fill(
                                child: _creatureImage(
                                  imageUrl,
                                  alignment: Alignment.bottomCenter,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              // Treatment / K.O. badge centred on the visible art area.
              if (!shrouded && (inst!.isHealing || ko))
                Positioned(
                  top: topReserve + artAreaH * 0.42,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: inst.isHealing
                        ? _badge('🩹 ${_fmtShort(inst.healingRemaining)}',
                            FoE.accentBlue)
                        : _badge('K.O.', FoE.danger),
                  ),
                ),
              // The XP indicator: an open-topped arc "bowl" under the monster's
              // feet at the seam — the SAME as the detail screen (user
              // 2026-07-24), replacing the old thin seam line.
              if (!shrouded && showXp)
                Positioned(
                  left: c.maxWidth * 0.12,
                  right: c.maxWidth * 0.12,
                  top: (c.maxHeight - stripH) - 18,
                  height: 24,
                  child: IgnorePointer(child: _xpArc(inst!)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The undiscovered strip: just a muted "???" — no name, level or HP.
  ///
  /// Light ink like the discovered strip's (2026-07-27): a shrouded tile's
  /// strip is a dark neutral grey, and FoE.textDim is a faded brown INK made
  /// for paper.
  Widget _shroudStrip() => Center(
    child: Text(
      '???',
      style: FoE.label(size: 14).copyWith(
        color: Colors.white.withValues(alpha: 0.55),
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    ),
  );

  /// The sprite as a near-black silhouette for undiscovered species.
  Widget _silhouette(String? url) => url == null
      ? const Center(child: Icon(Icons.pets, color: Colors.black87, size: 40))
      : ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0xE6000000),
            BlendMode.srcIn,
          ),
          child: CreatureSprite(
            url: url,
            alignment: Alignment.bottomCenter,
            fallback: const Center(
                child: Icon(Icons.pets, color: Colors.black87, size: 40)),
          ),
        );

  /// The XP indicator: the open-topped arc "bowl" under the monster's feet — the
  /// same [XpArcPainter] the detail screen uses, so the two read identically.
  Widget _xpArc(CreatureInstance creature) {
    final atMax = creature.level >= kCreatureMaxLevel;
    final need = atMax ? 1 : xpToNextLevel(creature.level);
    final frac = atMax ? 1.0 : (creature.xp / need).clamp(0.0, 1.0);
    return CustomPaint(painter: XpArcPainter(frac, stroke: 3, dotRadius: 3.5));
  }

  /// THE BOTTOM STRIP, REBUILT (user 2026-07-27: "gestalte den unteren Teil
  /// der Monsterkachel neu").
  ///
  /// It was a name with "Lv 4" as plain text beside it and a hairline HP bar
  /// running edge to edge underneath — which read as the tile's bottom border
  /// rather than as a gauge. The gender, meanwhile, floated over the artwork
  /// just above the seam, where it collided with the sprite's feet and the XP
  /// bowl.
  ///
  /// Now it is two lines with one job each:
  ///
  ///   NAME   the thing you are looking for, on its own line, with the evolve
  ///          arrow beside it and the level as a BADGE rather than as text —
  ///          a number that means something different from the name should not
  ///          look like more of the name.
  ///   STATE  the HP gauge, inset from the edges so it reads as a bar, with
  ///          the gender at its end. Both are facts about the monster's
  ///          condition, so they share a line.
  Widget _cardStrip(CreatureInstance creature) => Padding(
    padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                creature.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.label(size: 13).copyWith(
                  color: _stripInk,
                  fontWeight: FontWeight.w700,
                  shadows: _stripShadow,
                ),
              ),
            ),
            if (creature.canEvolve)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Icon(Icons.upgrade, color: _stripInk, size: 14),
              ),
            const SizedBox(width: 5),
            // NO BOX (user 2026-07-27: "bei lvl will ich keine Box"). The badge
            // was a dark plate punched into the strip — it did its job of
            // separating the number from the name, but on a strip that is now
            // one saturated colour it read as a hole in the surface. Weight and
            // opacity do the same separating without cutting anything out.
            Text(
              'Lv ${creature.level}',
              style: FoE.value(size: 10).copyWith(
                color: _stripInkSoft,
                shadows: _stripShadow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showHp)
              Expanded(child: _hpBar(creature))
            else
              const Spacer(),
            const SizedBox(width: 6),
            _genderTag(creature.gender),
          ],
        ),
      ],
    ),
  );

  // ── Ink on the type-coloured strip (user 2026-07-27) ──────────────────
  // The strip carries the monster's own type colour now, so it can be anything
  // from a pale plant green to a deep shadow purple. FoE.parchment is the app's
  // dark brown INK — right on paper, unreadable on a saturated colour, which is
  // what it had become here.
  //
  // White with a soft dark shadow is the one pair that holds on all of them:
  // the shadow is what keeps it legible on the LIGHT elements, where white
  // alone would wash out.
  static const Color _stripInk = Colors.white;
  static final Color _stripInkSoft = Colors.white.withValues(alpha: 0.82);
  static const List<Shadow> _stripShadow = [
    Shadow(color: Color(0x66000000), blurRadius: 0, offset: Offset(0, 1)),
  ];

  /// Gender as a small disc in the strip, beside the HP gauge. It used to be a
  /// bare glyph floating over the artwork, where it fought the sprite behind
  /// it.
  ///
  /// JUST THE GLYPH, BIGGER (user 2026-07-27: "bei dem Geschlechtssymbol bitte
  /// keinen Kreis als Hintergrund, dafür das Symbol etwas grösser machen").
  ///
  /// It sat on a near-white disc, which was one way to make pink-on-red and
  /// blue-on-blue survive a strip in the monster's own type colour. At 16 px
  /// with the strip's own drop shadow the glyph carries itself, and the colour
  /// is lifted a fifth of the way to white so it stays a ♂/♀ rather than a
  /// smudge on the darker elements.
  Widget _genderTag(CreatureGender gender) => Text(
    gender.symbol,
    style: TextStyle(
      color: Color.lerp(gender.color, Colors.white, 0.2),
      fontSize: 16,
      fontWeight: FontWeight.bold,
      height: 1.0,
      shadows: _stripShadow,
    ),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: ShapeDecoration(color: color, shape: FoE.facet(radius: 6)),
    child: Text(label, style: FoE.title(size: 11).copyWith(color: Colors.white)),
  );

  static String _fmtShort(Duration d) =>
      d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

  /// HP at a glance. Colour is the signal — red isn't only K.O., it's "this one
  /// will die in the next fight".
  Widget _hpBar(CreatureInstance c) {
    final fraction = c.maxHp <= 0 ? 0.0 : c.hp / c.maxHp;
    final color = fraction <= 0
        ? FoE.danger
        : fraction < 0.3
        ? FoE.danger
        : fraction < 0.6
        ? FoE.gold
        : FoE.positive;
    // Rounded and 6 px tall on a translucent track (user 2026-07-27): a 4 px
    // bar on an opaque panel colour, running the full width of the tile, read
    // as the tile's own edge rather than as a reading of anything.
    // The app's one bar (user 2026-07-29: "jetzt alle Balken im gleichen
    // Effekt gestalten"). Still 6 px — the strip's height is spoken for — so
    // the groove is shallow here, but it is the same groove.
    return RecessBar(value: fraction, color: color, height: 6, onDark: true);
  }

  /// Wraps a card's image area in the rarity backdrop; a creature with no
  /// species def (should not happen) just skips it.
  Widget _backdrop(SpeciesDef? species, Widget child, {double radius = 8}) =>
      species == null
      ? child
      : CreatureBackdrop(
          element: species.element,
          radius: radius,
          child: child,
        );

  Widget _creatureImage(String? url, {Alignment alignment = Alignment.center}) =>
      url == null
      ? const Center(child: Icon(Icons.pets, color: FoE.gold, size: 40))
      : CreatureSprite(
          url: url,
          alignment: alignment,
          fallback:
              const Center(child: Icon(Icons.pets, color: FoE.gold, size: 40)),
        );

  /// The sprite's drop shadow: its SHARP silhouette painted [color] (the
  /// element's shadow tone), just nudged down/right and bottom-aligned to match
  /// the sprite — the same crisp, un-blurred offset as the type icon's 3D
  /// emboss (user request).
  Widget _creatureShadow(String? url, Color color) => url == null
      ? const SizedBox.shrink()
      : Transform.translate(
          offset: const Offset(2, 4),
          // Slightly SMALLER than the sprite, anchored at the feet (user
          // request) so it stays a subtle base shadow on the tile.
          child: Transform.scale(
            scale: 0.9,
            alignment: Alignment.bottomCenter,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.srcATop),
              child: CreatureSprite(
                url: url,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
        );
}

