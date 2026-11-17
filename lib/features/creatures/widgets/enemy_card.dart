import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/voxel_kit.dart';
import '../../../core/ui/game_text.dart';
import '../../../core/theme/voxel_icons.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../services/creature_power.dart' show kPowerIcon;
import 'creature_family.dart' show CreatureFigure, creatureHpColor;
import 'versus_kit.dart' show combatantPower;

/// A foe as a TRADING CARD — the very card of the Monsters library
/// (collection_screen.dart's `_tradingCard`: steel frame tinted by the type,
/// the monster on block tiles in its colour, level and gender on the picture,
/// a dark band with name and rarity, the blocky HP bar), built from a
/// [Combatant] instead of a CreatureInstance (user 2026-11-15: "ich meinte so
/// eine trading card"). Not tappable; a foe about to be fought is at full HP.
class EnemyCard extends StatelessWidget {
  final Combatant enemy;
  const EnemyCard(this.enemy, {super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final s = box.maxWidth.isFinite
          ? (box.maxWidth / 150).clamp(0.55, 1.3)
          : 1.0;
      return _card(s);
    },
  );

  Widget _card(double s) {
    final e = enemy;
    final element = e.element;
    final rc = e.rarity.color;
    final dark = Color.lerp(element.color, Colors.black, 0.7)!;
    final band = Color.alphaBlend(const Color(0x73040E14), dark);
    return Container(
      decoration: ShapeDecoration(
        shape: VoxelShape(notch: 3, light: Voxel.rim, smooth: true),
        gradient: Voxel.shaded(
          Color.lerp(CreamPalette.tileTop, element.color, 0.55)!,
        ),
        shadows: const [
          BoxShadow(color: Color(0x73000000), offset: Offset(3, 3)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(1, 4, 1, 4),
      child: ClipRRect(
        clipBehavior: Clip.antiAlias,
        borderRadius: vr(8),
        child: DecoratedBox(
          decoration: BoxDecoration(color: dark),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: VoxelBackdrop(
                        color: element.color,
                        vignette: 0.7,
                        darken: 0.22,
                        cell: 18,
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: CreatureFigure(
                          imageUrl: e.imageUrl,
                          element: element,
                          tight: true,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Text(
                        'Lv ${e.level}',
                        style: FoE.value(size: 12 * s).copyWith(
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Color(0xFF061219), offset: Offset(1, 0)),
                            Shadow(color: Color(0xFF061219), offset: Offset(-1, 0)),
                            Shadow(color: Color(0xFF061219), offset: Offset(0, 1)),
                            Shadow(color: Color(0xFF061219), offset: Offset(0, -1)),
                            Shadow(color: Color(0xAA000000), blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 3,
                      right: 5,
                      child: GameIcon(
                        e.gender == CreatureGender.male ? 'male' : 'female',
                        size: 22 * s,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                color: band,
                padding: EdgeInsets.fromLTRB(8 * s, 5 * s, 8 * s, 4 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.title(size: 14 * s).copyWith(color: kBoxInk),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          // Shrinks rather than "UNCOM…": the rarity word is the
                          // one thing this line must say in full.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              e.rarity.label.toUpperCase(),
                              maxLines: 1,
                              style: FoE.dim(size: 8.5 * s).copyWith(
                                color: Color.lerp(rc, Colors.white, 0.35),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                        ),
                        Text(
                          '$kPowerIcon${combatantPower(e)}',
                          style: FoE.value(
                            size: 12 * s,
                          ).copyWith(color: const Color(0xFFFFD45A)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                color: band,
                padding: EdgeInsets.fromLTRB(8 * s, 0, 8 * s, 6 * s),
                child: VoxelBar(
                  value: 1,
                  color: creatureHpColor(1),
                  height: 8 * s,
                  block: 6 * s,
                  onDark: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
