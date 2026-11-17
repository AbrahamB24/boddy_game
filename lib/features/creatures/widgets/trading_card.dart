import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/voxel_icons.dart';
import '../../../core/theme/voxel_kit.dart'
    show VoxelBackdrop, VoxelBar, VoxelShape, Voxel, vr;
import '../../../core/ui/game_text.dart';
import '../../../core/ui/pressable.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../services/creature_power.dart';
import 'creature_card.dart' show TileValue;
import 'creature_family.dart' show CreatureFigure, creatureHpColor;
import 'creature_sprite.dart';

/// A monster as a TRADING CARD — the card of the Monsters library (user
/// 2026-11-10; extracted 2026-11-15 so Battle Prep can use it too): steel frame
/// tinted by the type, the monster on block tiles in its colour, level and
/// gender on the picture, a dark band with name, rarity and power, the blocky HP
/// bar. Fills whatever box it is given (aspect ≈ 0.7).
class TradingCard extends StatelessWidget {
  final CreatureInstance? creature;
  final VoidCallback? onTap;
  final bool showHp;

  /// Up to three extra figures (the stat a post reads, a breeding parent's
  /// level-1 power), as flags down the picture's right edge.
  final List<TileValue> extras;

  /// Show the level AND the power worked out AT this level (Breeding).
  final int? atLevel;

  /// Thin gold XP line above the HP bar.
  final bool showXp;

  /// Undiscovered species (Bestiary): dark card, black silhouette, "???".
  final bool shrouded;
  final String? shroudImageUrl;

  const TradingCard(
    CreatureInstance this.creature, {
    super.key,
    this.onTap,
    this.showHp = true,
    this.extras = const [],
    this.atLevel,
    this.showXp = false,
  }) : shrouded = false,
       shroudImageUrl = null;

  const TradingCard.shrouded({super.key, this.shroudImageUrl, this.onTap})
    : shrouded = true,
      creature = null,
      showHp = false,
      extras = const [],
      atLevel = null,
      showXp = false;

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
    final c = creature;
    if (c == null) return _shroudedCard();
    final rarity = c.species?.rarity;
    final rc = rarity?.color ?? const Color(0xFF9FB0BD);
    final element = c.species?.element ?? CreatureElement.fire;
    final ko = c.isKo;
    final hp = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    final cap = xpToNextLevel(c.level);
    final xp = (showXp && cap > 0) ? (c.xp / cap).clamp(0.0, 1.0) : 0.0;
    final dark = Color.lerp(element.color, Colors.black, 0.7)!;
    final band = Color.alphaBlend(const Color(0x73040E14), dark);
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
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
                          child: Opacity(
                            opacity: ko ? 0.35 : 1,
                            child: CreatureFigure(
                              imageUrl: c.imageUrl,
                              element: element,
                              tight: true,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 5,
                        left: 5,
                        // No dark plate: the figure's backdrop is calm enough
                        // for a white number with a hard dark edge.
                        child: Text(
                          'Lv ${atLevel ?? c.level}',
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
                          c.gender == CreatureGender.male ? 'male' : 'female',
                          size: 22 * s,
                        ),
                      ),
                      if (c.canEvolve)
                        Positioned(
                          right: 4,
                          bottom: 2,
                          child: Semantics(
                            label: 'Can evolve',
                            child: PixelIcon(
                              Icons.arrow_upward_rounded,
                              size: 22 * s,
                              color: const Color(0xFF2FD37A),
                              shadows: const [
                                Shadow(
                                  color: Color(0xCC000000),
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      for (var i = 0; i < extras.length && i < 3; i++)
                        Positioned(
                          top: 26 * s + i * 17 * s,
                          right: 0,
                          child: _flag(extras[i], s),
                        ),
                      if (ko || c.isHealing)
                        Positioned.fill(
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8 * s,
                                vertical: 3 * s,
                              ),
                              decoration: ShapeDecoration(
                                color: c.isHealing && !ko
                                    ? FoE.accentBlue
                                    : FoE.danger,
                                shape: FoE.facet(radius: 6),
                              ),
                              child: Text(
                                c.isHealing && !ko
                                    ? '🩹 ${_fmtShort(c.healingRemaining)}'
                                    : 'K.O.',
                                style: FoE.title(
                                  size: 11 * s,
                                ).copyWith(color: Colors.white),
                              ),
                            ),
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
                        c.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.title(size: 14 * s).copyWith(color: kBoxInk),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (rarity?.label ?? '').toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FoE.dim(size: 8.5 * s).copyWith(
                                color: Color.lerp(rc, Colors.white, 0.35),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                          Text(
                            '$kPowerIcon${atLevel == null ? totalPower(c) : powerAtLevel(c, atLevel!)}',
                            style: FoE.value(
                              size: 12 * s,
                            ).copyWith(color: const Color(0xFFFFD45A)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (xp > 0)
                  SizedBox(
                    height: 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0x66000000)),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: xp,
                          child: const ColoredBox(color: Color(0xFFF5C84A)),
                        ),
                      ],
                    ),
                  ),
                if (showHp)
                  Container(
                    color: band,
                    padding: EdgeInsets.fromLTRB(8 * s, 0, 8 * s, 6 * s),
                    child: VoxelBar(
                      value: hp,
                      color: creatureHpColor(hp),
                      height: 8 * s,
                      block: 6 * s,
                      onDark: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtShort(Duration d) =>
      d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

  Widget _flag(TileValue v, double s) => Container(
    height: 16 * s,
    padding: EdgeInsets.fromLTRB(7 * s, 0, 6 * s, 0),
    decoration: const BoxDecoration(
      color: Color(0xD62A1A0C),
      borderRadius: BorderRadius.horizontal(left: Radius.circular(3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          v.label.toUpperCase(),
          maxLines: 1,
          style: FoE.dim(
            size: 7 * s,
          ).copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
        SizedBox(width: 4 * s),
        Text(
          '${v.value}',
          maxLines: 1,
          style: FoE.value(size: 9 * s).copyWith(color: Colors.white),
        ),
      ],
    ),
  );

  /// The undiscovered card: same shape, dark, black silhouette, "???".
  Widget _shroudedCard() => LayoutBuilder(
    builder: (context, box) {
      final s = box.maxWidth.isFinite
          ? (box.maxWidth / 150).clamp(0.55, 1.3)
          : 1.0;
      const dark = Color(0xFF10181D);
      return Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: ShapeDecoration(
            shape: VoxelShape(notch: 3, light: Voxel.rim, smooth: true),
            gradient: Voxel.shaded(const Color(0xFF3A4650)),
            shadows: const [
              BoxShadow(color: Color(0x73000000), offset: Offset(3, 3)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(1, 4, 1, 4),
          child: ClipRRect(
            borderRadius: vr(8),
            child: ColoredBox(
              color: dark,
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: shroudImageUrl == null
                          ? const Center(
                              child: PixelIcon(
                                Icons.pets,
                                color: Colors.black87,
                                size: 40,
                              ),
                            )
                          : ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                Color(0xE6000000),
                                BlendMode.srcIn,
                              ),
                              child: CreatureSprite(
                                url: shroudImageUrl!,
                                alignment: Alignment.bottomCenter,
                                fallback: const Center(
                                  child: PixelIcon(
                                    Icons.pets,
                                    color: Colors.black87,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                  Container(
                    color: const Color(0xFF0A1014),
                    padding: EdgeInsets.symmetric(vertical: 8 * s),
                    alignment: Alignment.center,
                    child: Text(
                      '???',
                      style: FoE.title(size: 14 * s).copyWith(
                        color: Colors.white.withValues(alpha: 0.55),
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
