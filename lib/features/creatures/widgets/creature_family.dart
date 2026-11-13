import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart'
    show CreamPalette, kBoxInk, kBoxInkSoft;
import '../../../core/theme/foe_theme.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import 'battle_scene.dart' show TypePodium;
import '../../../core/theme/voxel_kit.dart' show VoxelBackdrop;
import 'creature_sprite.dart';
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

// ── THE MONSTER FAMILY (user 2026-09-20: "Monsterkacheln müssen vereinheitlicht
// werden. Aktuell gibt es sehr viele verschiedene Darstellungen") ──
//
// The big tile is [CreatureCard] ("Variante 1", the foot). Everything smaller
// that used to be its own thing — a round badge in the healing hut, a 30-px
// circle at a work seat, a Gegner face on the overworld, a portrait on the
// market's caravan — is now the SAME tile at a small size: [CreatureAvatar].
// It keeps the tile's three tells: the element-coloured foot, the monster
// standing half over it, and the HP as a flush bar along the foot's bottom edge
// ("die HP-Balken sind bei allen wie bei der Kachel").
//
// The battle has its own sibling (user 2026-09-20: "Nimm die Sockelkachel für
// den Kampf"): [SockelAvatar], the monster standing on the same podium the arena
// uses ([TypePodium]) with the HP on the platform's rim. The arena already is
// that look; this brings the small parts of the battle screen (the turn order,
// the bench, the actor's portrait, the reserve list) into it.

/// What a small monster display needs, from either kind of monster the app has:
/// a collection's [CreatureInstance] or a fight's [Combatant].
class CreatureFace {
  final String? imageUrl;
  final CreatureElement element;

  /// 0..1 of its health.
  final double hp;

  const CreatureFace({
    required this.imageUrl,
    required this.element,
    required this.hp,
  });

  bool get ko => hp <= 0;

  factory CreatureFace.of(CreatureInstance c) => CreatureFace(
    imageUrl: c.imageUrl,
    element: c.species?.element ?? CreatureElement.neutral,
    hp: c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0),
  );

  factory CreatureFace.combatant(Combatant c) => CreatureFace(
    imageUrl: c.imageUrl,
    element: c.element,
    hp: c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0),
  );
}

/// The tile's HP colour scale — coral is "this one goes down in the next fight",
/// not only K.O. One place, so the tile, its avatars and the lists agree.
Color creatureHpColor(double fraction) => fraction < 0.3
    ? FoE.danger
    : fraction < 0.6
    ? CreamPalette.gold
    : FoE.positive;

/// The monster art with its drop shadow: the sprite's SHARP silhouette painted in
/// the element's shadow tone, nudged down-right and a little smaller, feet
/// aligned — the same crisp offset as the type icon's emboss. Shared by the tile
/// and by every avatar so a monster casts the same shadow everywhere.
class CreatureFigure extends StatelessWidget {
  final String? imageUrl;
  final CreatureElement element;
  final double? decodeSize;

  const CreatureFigure({
    super.key,
    required this.imageUrl,
    required this.element,
    this.decodeSize,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) {
      return const Center(child: PixelIcon(Icons.pets, color: FoE.gold, size: 40));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // No coloured silhouette shadow behind the sprite any more (user
        // 2026-11-08: "den gelben Schatten rechts von dem Fuss").
        Positioned.fill(
          child: CreatureSprite(
            url: url,
            height: decodeSize,
            alignment: Alignment.bottomCenter,
            fallback: const Center(
              child: PixelIcon(Icons.pets, color: FoE.gold, size: 40),
            ),
          ),
        ),
      ],
    );
  }
}

/// The small monster, at any size — the "Chip" and "Avatar" of the family (user
/// 2026-09-21: "nimm für die ganz kleinen Monsterkacheln (Chip) die Sockel"): the
/// monster standing on its type's podium, its HP the platform's rim, exactly what
/// the battle uses ([SockelAvatar]). The big tile ([CreatureCard]) keeps its foot.
///
/// [size] is the SQUARE it occupies; the monster reaches a little above and to the
/// sides of it, so give it a row that can spare that. A knocked-out monster fades
/// and, from 40 px up, says so.
class CreatureAvatar extends StatelessWidget {
  final CreatureFace face;
  final double size;

  /// The HP rim. Off where health is beside the point (a caravan hauler, a
  /// breeding parent): the podium is then plain.
  final bool showHp;

  const CreatureAvatar(
    this.face, {
    super.key,
    this.size = 32,
    this.showHp = true,
  });

  CreatureAvatar.of(
    CreatureInstance c, {
    Key? key,
    double size = 32,
    bool showHp = true,
  }) : this(CreatureFace.of(c), key: key, size: size, showHp: showHp);

  @override
  Widget build(BuildContext context) =>
      SockelAvatar(face, size: size, showHp: showHp);
}

/// The battle's small monster ("Sockel"): the monster standing on the arena's own
/// podium, its HP the platform's rim ([TypePodium]). [size] is the square it
/// occupies; the podium is a little wider than that so the rim reads.
class SockelAvatar extends StatelessWidget {
  final CreatureFace face;
  final double size;

  /// The rim's colour scale. The battle passes its own so the small monsters and
  /// the big ones on the field never disagree about "half health".
  final Color Function(double fraction)? hpColor;

  /// False = a plain podium, no HP on the rim.
  final bool showHp;

  const SockelAvatar(
    this.face, {
    super.key,
    this.size = 32,
    this.hpColor,
    this.showHp = true,
  });

  SockelAvatar.combatant(
    Combatant c, {
    Key? key,
    double size = 32,
    Color Function(double fraction)? hpColor,
  }) : this(CreatureFace.combatant(c), key: key, size: size, hpColor: hpColor);

  @override
  Widget build(BuildContext context) {
    final podiumW = size * 1.08;
    final scale = hpColor ?? creatureHpColor;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: TypePodium(
              element: face.element,
              width: podiumW,
              hpFraction: showHp ? face.hp : null,
              hpColor: scale(face.hp),
              gauge: (size * 0.07).clamp(1.5, 4.0),
            ),
          ),
          Positioned(
            left: -size * 0.04,
            right: -size * 0.04,
            top: -size * 0.06,
            height: size * 0.9,
            child: IgnorePointer(
              child: Opacity(
                opacity: face.ko ? 0.35 : 1,
                child: CreatureFigure(
                  imageUrl: face.imageUrl,
                  element: face.element,
                  decodeSize: size * 0.9,
                ),
              ),
            ),
          ),
          if (face.ko && size >= 40)
            Positioned(
              left: 0,
              right: 0,
              top: size * 0.3,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: ShapeDecoration(
                    color: FoE.danger,
                    shape: FoE.facet(radius: 5),
                  ),
                  child: Text(
                    'K.O.',
                    style: FoE.title(
                      size: (size * 0.2).clamp(9.0, 12.0),
                    ).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A crew seat's tile (the building dialog's Crew card): the monster standing on
/// its podium — the Sockel, like every small monster now (user 2026-09-21: "beim
/// Gebäudedetailscreen auch diese Sockel machen") — with its name and what it
/// makes under it, in the card's own ink. The HP is the podium's rim.
///
/// [u] scales the whole tile; the caller shows the name only while the tile is
/// big enough to carry it. Drawn at [width] × [height] for u = 1.
/// A crew seat as a CARD ("Karten mit Balken", user 2026-11-11): the monster on
/// its podium rising out of a lighter card, underneath the name, a bar for the
/// stat that drives its output, and the figure it makes here. [u] scales it all;
/// the name and the stat figure only show while it is big enough.
class CreatureCrewCard extends StatelessWidget {
  final CreatureFace face;
  final String? name;
  final String figure;

  /// 0..1, how full the stat bar is.
  final double stat;

  /// The stat's number, printed beside the figure while there is room.
  final String? statLabel;
  final double u;

  const CreatureCrewCard({
    super.key,
    required this.face,
    required this.figure,
    required this.stat,
    this.name,
    this.statLabel,
    this.u = 1,
    this.compact = false,
  });

  /// Natural size at u = 1: the card itself, and the strip above it the
  /// monster's head rises into.
  /// The COMPACT form (monster, podium, figure — no card): what 20+ seats use.
  static const double compactWidth = 46;
  static const double compactHeight = 64;
  final bool compact;

  static const double width = 104;
  static const double height = 96;
  static const double rise = 16;

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact();
    final w = width * u;
    return SizedBox(
      width: w,
      height: (height + rise) * u,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: rise * u,
            // The trading card's foot: dark element base, the element
            // backdrop with its symbol at the top, a shade toward the text.
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: Color.lerp(face.element.color, Colors.black, 0.36),
                shape: FoE.facet(radius: 14 * u),
                shadows: const [
                  BoxShadow(color: Color(0x4D000000), offset: Offset(0, 3)),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Same block-tile wall as the Monsters screen's trading card.
                  VoxelBackdrop(
                    color: face.element.color,
                    vignette: 0.7,
                    darken: 0.22,
                    cell: 18 * u,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 58 * u,
            child: IgnorePointer(
              child: Opacity(
                opacity: face.ko ? 0.35 : 1,
                child: CreatureFigure(
                  imageUrl: face.imageUrl,
                  element: face.element,
                  decodeSize: 58 * u,
                ),
              ),
            ),
          ),
          Positioned(
            left: 7 * u,
            right: 7 * u,
            bottom: 6 * u,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (name != null)
                  Text(
                    name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(
                      size: 10.5 * u,
                    ).copyWith(color: Colors.white, fontWeight: FontWeight.w400),
                    textAlign: TextAlign.center,
                  ),
                SizedBox(height: 3 * u),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    figure,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: FoE.value(
                      size: (12 * u).clamp(8.0, 15.0),
                    ).copyWith(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension on CreatureCrewCard {
  Widget _buildCompact() {
    final w = CreatureCrewCard.compactWidth * u;
    return SizedBox(
      width: w,
      height: CreatureCrewCard.compactHeight * u,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 28 * u,
            child: TypePodium(
              element: face.element,
              width: w,
              hpFraction: null,
              hpColor: kBoxInk,
              gauge: (2.4 * u).clamp(1.5, 3.5),
            ),
          ),
          Positioned(
            left: -3 * u,
            right: -3 * u,
            top: 0,
            height: 42 * u,
            child: IgnorePointer(
              child: Opacity(
                opacity: face.ko ? 0.35 : 1,
                child: CreatureFigure(
                  imageUrl: face.imageUrl,
                  element: face.element,
                  decodeSize: 42 * u,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                figure,
                maxLines: 1,
                style: FoE.value(
                  size: (12 * u).clamp(8.0, 14.0),
                ).copyWith(color: kBoxInk),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CreatureSeatTile extends StatelessWidget {
  final CreatureFace face;

  /// Null hides the name line (small tiles; a long press gives the details).
  final String? name;

  /// What this monster makes here, or why it is not working.
  final String figure;
  final double u;

  const CreatureSeatTile({
    super.key,
    required this.face,
    required this.figure,
    this.name,
    this.u = 1,
  });

  static const double width = 60;
  static const double height = 88;

  @override
  Widget build(BuildContext context) {
    final podiumW = width * u;
    return SizedBox(
      width: width * u,
      height: height * u,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The podium, and the monster on it: feet a little inside the disc.
          Positioned(
            left: 0,
            top: 40 * u,
            child: TypePodium(
              element: face.element,
              width: podiumW,
              hpFraction: face.hp,
              hpColor: creatureHpColor(face.hp),
              gauge: (2.6 * u).clamp(1.5, 4.0),
            ),
          ),
          Positioned(
            left: -3 * u,
            right: -3 * u,
            top: 0,
            height: 54 * u,
            child: IgnorePointer(
              child: Opacity(
                opacity: face.ko ? 0.35 : 1,
                child: CreatureFigure(
                  imageUrl: face.imageUrl,
                  element: face.element,
                  decodeSize: 54 * u,
                ),
              ),
            ),
          ),
          // Name (when there is room), then the figure — on the card's own
          // cream, so in its ink.
          Positioned(
            left: 0,
            right: 0,
            bottom: 1 * u,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != null)
                  Text(
                    name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(
                      size: 9.5 * u,
                    ).copyWith(color: kBoxInkSoft, fontWeight: FontWeight.w400),
                  ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    figure,
                    maxLines: 1,
                    style: FoE.value(
                      size: (11.5 * u).clamp(8.0, 15.0),
                    ).copyWith(color: kBoxInk),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
