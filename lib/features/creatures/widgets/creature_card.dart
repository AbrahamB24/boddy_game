import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../services/creature_power.dart';
import 'creature_backdrop.dart';
import 'creature_family.dart' show CreatureFigure, creatureHpColor;
import 'creature_sprite.dart';
import '../../../core/theme/voxel_icons.dart';

/// One extra figure a screen wants on the tile — the stat this seat or trip is
/// judged on, the level-1 power a breeding parent passes on. It hangs from the
/// tile as a small flag in the free part above the foot; up to three fit.
class TileValue {
  final String label;
  final Object value;

  const TileValue(this.label, this.value);
}

/// The monster tile (user 2026-09-19, "Variante 9, Werte-Fahnen" of the second
/// round): an element-coloured FOOT carrying everything a monster is —
/// name and gender, level and power, rarity — with the HP bar as an edge along
/// its bottom, and the monster standing half in the foot and half FREE above
/// it, big, its feet resting just over the name.
///
/// The foot never changes between screens. What a particular screen adds
/// (the stat a work post reads, the mining figure of an expedition, the
/// level-1 power in Breeding) goes in [extras], as flags in the free upper
/// right — so the tile keeps one shape and one place for everything, and a
/// screen without extras shows a calm tile.
///
/// Shared by the Monsters screen, the Bestiary, teams, breeding, the pickers
/// and the market. The Bestiary uses [CreatureCard.shrouded] for undiscovered
/// species: the same shape, a dark foot, a black silhouette and "???" — every
/// detail hidden.
class CreatureCard extends StatelessWidget {
  final CreatureInstance? creature;
  final String? shroudImageUrl;
  final bool shrouded;
  final VoidCallback? onTap;

  /// The HP bar along the foot's bottom edge. Off where health is beside the
  /// point (Breeding picks a parent on its genes, not its wounds).
  final bool showHp;

  /// Up to three extra figures, as flags at the top right.
  final List<TileValue> extras;

  /// Show the level AND work the ⚡ power out AT this level instead of the monster's own (user
  /// 2026-09-28: the Breeding page switches between Now, Lv 1 and Max). Null = its own
  /// level, as everywhere else.
  final int? atLevel;

  const CreatureCard({
    super.key,
    required CreatureInstance this.creature,
    this.onTap,
    this.showHp = true,
    this.extras = const [],
    this.atLevel,
  }) : shrouded = false,
       shroudImageUrl = null;

  const CreatureCard.shrouded({super.key, this.shroudImageUrl, this.onTap})
    : shrouded = true,
      creature = null,
      showHp = false,
      extras = const [],
      atLevel = null;

  // The tile's geometry, from the design: everything below the foot's top edge
  // is anchored to the BOTTOM, so the text keeps its place whatever height the
  // grid gives the tile; the foot's top and the monster follow from it.
  static const double _barH = 9;
  // The text zone, tight (user 2026-09-20: "level, energie, name und Geschlecht
  // weiter nach unten, dafür das Asset grösser") — the three lines (16 + 14 + 12)
  // now sit almost touching, and every pixel this gives up goes to the monster,
  // whose box ends where the text begins.
  static const double _zoneH = 44;
  static const double _footTopFraction = 0.347;
  static const double _monsterOverhang = 0.10; // of the width, each side
  static const double _monsterTop = -12;
  static const double _flagH = 16;
  static const double _flagStep = 19;
  static const int _maxExtras = 3;

  @override
  Widget build(BuildContext context) {
    final inst = creature;
    final ko = inst?.isKo ?? false;
    final species = inst?.species;
    final element = shrouded
        ? FoE.textMuted
        : (species?.element.color ?? FoE.borderGold);

    return Pressable(
      // THE WHOLE CELL TAKES THE TAP (user 2026-07-27): the top of the tile is
      // empty on purpose, and a GestureDetector only hit-tests what its child
      // paints, so without this every tap up there fell through — including one
      // on the Market's ✕ badge, which sits exactly there. [EggCard] documents
      // the same trap.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final footTop = h * _footTopFraction;
          final zoneTop = h - _barH - _zoneH;
          return Stack(
            // The monster's head, the flags and the foot's shadow all reach past
            // the cell; the grid's gaps and padding are the room they use.
            clipBehavior: Clip.none,
            children: [
              // The foot: the element's backdrop (with its symbol at the top),
              // shade toward the bottom for the text, the text, the HP edge.
              Positioned(
                top: footTop,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: Color.lerp(element, Colors.black, 0.36),
                    shape: FoE.facet(radius: 20),
                    shadows: const [
                      BoxShadow(color: Color(0x4D000000), offset: Offset(0, 3)),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (shrouded)
                        const ColoredBox(color: FoE.bg)
                      else if (species != null)
                        CreatureBackdrop(
                          element: species.element,
                          radius: 0,
                          watermarkTop: true,
                          child: const SizedBox.expand(),
                        )
                      else
                        ColoredBox(color: element),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: _zoneH + _barH + 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0x59000000)],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: _barH,
                        height: _zoneH,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: shrouded ? _shroudText() : _text(inst!),
                        ),
                      ),
                      if (!shrouded && showHp)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _barH,
                          child: _hpEdge(inst!),
                        ),
                    ],
                  ),
                ),
              ),
              // The monster: bigger than the tile is wide, feet just over the
              // name, its top half free of any backdrop.
              Positioned(
                top: _monsterTop,
                left: -w * _monsterOverhang,
                right: -w * _monsterOverhang,
                bottom: h - zoneTop - 2,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: ko ? 0.35 : 1,
                    child: shrouded
                        ? _silhouette(shroudImageUrl)
                        // Half the monster stands on bare paper, so its drop
                        // shadow — the silhouette in the element's shadow tone —
                        // is what keeps a pale one from vanishing there. The
                        // figure is shared with every avatar (creature_family).
                        : CreatureFigure(
                            imageUrl: inst!.imageUrl,
                            element: species?.element ?? CreatureElement.fire,
                          ),
                  ),
                ),
              ),
              // Can evolve: a green arrow on the upper right — INSIDE the
              // foot (user 2026-09-29: "sollte noch im blauen Kästchen sein …
              // so dass es nicht verdeckt werden kann"). It used to sit at
              // the cell's own top edge, above the foot entirely, in the free
              // strip a neighbouring row's tile can overlap in a tight grid —
              // exactly where it could be clipped or covered. Anchored to
              // [footTop] instead, it always paints on the tile's own
              // coloured card, never past its edge.
              if (!shrouded && inst!.canEvolve)
                Positioned(
                  top: footTop + 4,
                  right: 2,
                  child: Semantics(label: 'Can evolve', child: _evolveStamp()),
                ),
              // Extra figures, as flags in the free upper right. The evolve
              // arrow moved into the foot below (2026-09-29), so it no longer
              // shares this strip and flags need no push-down for it.
              if (!shrouded)
                for (var i = 0; i < extras.length && i < _maxExtras; i++)
                  Positioned(
                    top: 6 + i * _flagStep,
                    right: -5,
                    child: _flag(extras[i]),
                  ),
              // Treatment / K.O. badge, over the middle of the monster.
              if (!shrouded && (inst!.isHealing || ko))
                Positioned(
                  top: h * 0.4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: inst.isHealing
                        ? _badge(
                            '🩹 ${_fmtShort(inst.healingRemaining)}',
                            FoE.accentBlue,
                          )
                        : _badge('K.O.', FoE.danger),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── The foot's text ───────────────────────────────────────────────────

  /// Name and gender centred (the evolve arrow behind them), then level and
  /// power on one line, then the rarity between two hairlines.
  Widget _text(CreatureInstance inst) {
    final rarity = inst.species?.rarity;
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nameRow(inst),
        SizedBox(
          height: 14,
          // Level and power sit TOGETHER in the middle, on the name's own inset
          // (user 2026-09-28: "lvl und energie näher zusammen / gleiches Padding
          // wie der Name") — spread to the two edges they read as two unrelated
          // corners.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Each side scales down rather than overflowing if a font runs wide.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Lv ${atLevel ?? inst.level}',
                    style: FoE.value(size: 11).copyWith(
                      color: _ink.withValues(alpha: 0.9),
                      shadows: _shadowLine,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '⚡${atLevel == null ? totalPower(inst) : powerAtLevel(inst, atLevel!)}',
                    style: FoE.value(
                      size: 11,
                    ).copyWith(color: _ink, shadows: _shadowLine),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 12,
          child: rarity == null
              ? null
              // The word sits at its own width, capped, and the two hairlines
              // share what is left EQUALLY (user 2026-09-22: "die Seltenheit ist
              // nicht mittig"). The word used to be a loose Flexible next to two
              // Expanded hairlines: it took less than its share and the unused
              // room piled up on the right, so a short word ("EPIC") sat left of
              // centre.
              : LayoutBuilder(
                  builder: (context, box) => Row(
                    children: [
                      Expanded(child: _hairline),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: box.maxWidth * 0.72,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              rarity.label.toUpperCase(),
                              maxLines: 1,
                              style: FoE.dim(size: 8.5).copyWith(
                                color: Color.lerp(
                                  rarity.color,
                                  Colors.white,
                                  0.45,
                                ),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                shadows: _shadowLine,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: _hairline),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _nameRow(CreatureInstance inst) => SizedBox(
    height: 16,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            inst.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 13).copyWith(
              color: _ink,
              fontWeight: FontWeight.w700,
              shadows: _shadowLine,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          inst.gender.symbol,
          style: TextStyle(
            color: Color.lerp(inst.gender.color, Colors.white, 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.0,
            shadows: _shadowLine,
          ),
        ),
      ],
    ),
  );

  /// "This one can evolve" (user 2026-09-28: "nur grüner Pfeil nach oben, oben
  /// rechts in der Kachel"): JUST a green arrow pointing up, on the tile's upper
  /// right — no disc, no ring. A soft dark edge keeps it readable on a pale
  /// monster or backdrop.
  Widget _evolveStamp() => const PixelIcon(
    Icons.arrow_upward_rounded,
    size: 26,
    color: Color(0xFF2FD37A),
    shadows: [
      Shadow(color: Color(0xCC000000), blurRadius: 3),
      Shadow(color: Color(0x99000000), offset: Offset(0, 1.5)),
    ],
  );

  /// The undiscovered foot: just "???" where the name would be.
  Widget _shroudText() => Align(
    alignment: Alignment.topCenter,
    child: SizedBox(
      height: 16,
      child: Text(
        '???',
        style: FoE.label(size: 13).copyWith(
          color: Colors.white.withValues(alpha: 0.55),
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    ),
  );

  static const Color _ink = Colors.white;
  static const List<Shadow> _shadowLine = [
    Shadow(color: Color(0x66000000), blurRadius: 0, offset: Offset(0, 1)),
  ];
  static final Widget _hairline = Container(
    height: 1,
    color: Colors.white.withValues(alpha: 0.3),
  );

  // ── HP edge, flags, badge ─────────────────────────────────────────────

  /// HP as the foot's bottom edge (from the first round's variant 5): a dark
  /// track and a bar, full width. Colour is the signal — coral is "this one
  /// will go down in the next fight", not only K.O.
  Widget _hpEdge(CreatureInstance c) {
    final fraction = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    final color = creatureHpColor(fraction);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0x59000000)),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: ColoredBox(color: color),
        ),
      ],
    );
  }

  Widget _flag(TileValue v) => Container(
    height: _flagH,
    padding: const EdgeInsets.fromLTRB(8, 0, 7, 0),
    decoration: BoxDecoration(
      color: const Color(0xD62A1A0C),
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
      border: Border(left: _flagEdge, top: _flagEdge, bottom: _flagEdge),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          v.label.toUpperCase(),
          maxLines: 1,
          style: FoE.dim(size: 7).copyWith(
            color: Colors.white.withValues(alpha: 0.7),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${v.value}',
          maxLines: 1,
          style: FoE.value(size: 9).copyWith(color: Colors.white),
        ),
      ],
    ),
  );

  static final BorderSide _flagEdge = BorderSide(
    color: const Color(0xFFF5B83A).withValues(alpha: 0.45),
  );

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: ShapeDecoration(color: color, shape: FoE.facet(radius: 6)),
    child: Text(
      label,
      style: FoE.title(size: 11).copyWith(color: Colors.white),
    ),
  );

  static String _fmtShort(Duration d) =>
      d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

  // ── The sprite ────────────────────────────────────────────────────────

  /// The undiscovered species as a near-black silhouette.
  Widget _silhouette(String? url) => url == null
      ? const Center(child: PixelIcon(Icons.pets, color: Colors.black87, size: 40))
      : ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0xE6000000),
            BlendMode.srcIn,
          ),
          child: CreatureSprite(
            url: url,
            alignment: Alignment.bottomCenter,
            fallback: const Center(
              child: PixelIcon(Icons.pets, color: Colors.black87, size: 40),
            ),
          ),
        );
}
