import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';

/// THE VERSUS PAGE (user 2026-09-20, "Variante 8, Karten-Duell", with the power
/// comparison bar of "Variante 2" wherever the other side's power is known).
///
/// Before a fight — or in the lobby of a duel — the two sides face each other as
/// FANNED CARDS: the enemy's on top, yours below, a "VS" between them. Where the
/// enemy's total power is known, the VS sits on a bar that splits by the two
/// totals, so "my 434 against their 630" reads before a word is.
///
/// Used by Battle Prep, the PvP lobby, the capture encounter's find list and
/// Survival's team pick.

/// A fan of cards: gently rotated around the middle, edges dropped a little —
/// like cards held in a hand. [down] flips the drop so the bottom fan mirrors the
/// top one.
class VersusFan extends StatelessWidget {
  final List<Widget> cards;
  final double tileW;
  final double tileH;
  final bool down;

  const VersusFan({
    super.key,
    required this.cards,
    this.tileW = 72,
    this.tileH = 120,
    this.down = false,
  });

  @override
  Widget build(BuildContext context) {
    final n = cards.length;
    // Fewer tilt steps when there are many, so six cards still fit a row.
    final step = n <= 3 ? 0.07 : 0.035;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < n; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Transform.translate(
              offset: Offset(
                0,
                (down ? 1 : -1) * ((i - (n - 1) / 2).abs() * 5),
              ),
              child: Transform.rotate(
                angle: (i - (n - 1) / 2) * step,
                child: SizedBox(width: tileW, height: tileH, child: cards[i]),
              ),
            ),
          ),
      ],
    );
  }
}

/// The gold "VS" medallion.
class VsBadge extends StatelessWidget {
  const VsBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: CreamPalette.gold,
      shape: BoxShape.circle,
      boxShadow: const [
        BoxShadow(color: CreamPalette.goldDeep, offset: Offset(0, 3)),
      ],
    ),
    child: const Text(
      'VS',
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: kBoxInk,
      ),
    ),
  );
}

/// "VS" between two hairlines — the middle row when the enemy's power is not
/// known (a duel: their team stays hidden until the battle starts).
class VsDivider extends StatelessWidget {
  const VsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: CreamPalette.tan.withValues(alpha: 0.5),
      ),
    );
    return Row(
      children: [
        line,
        const SizedBox(width: 14),
        const VsBadge(),
        const SizedBox(width: 14),
        line,
      ],
    );
  }
}

/// The power comparison: "⚡ 434 [green | red] ⚡ 630" with the VS medallion at
/// the split. The bar is drawn by the two totals; equal or empty splits in half.
class PowerVersusBar extends StatelessWidget {
  final int mine;
  final int theirs;

  const PowerVersusBar({super.key, required this.mine, required this.theirs});

  @override
  Widget build(BuildContext context) {
    final total = mine + theirs;
    final share = total <= 0 ? 0.5 : (mine / total).clamp(0.05, 0.95);
    Widget figure(int v, {required bool mineSide}) => SizedBox(
      width: 62,
      child: Text(
        '⚡ $v',
        textAlign: mineSide ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: mineSide ? CreamPalette.better : CreamPalette.warn,
        ),
      ),
    );
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          figure(mine, mineSide: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: (share * 1000).round(),
                            child: const ColoredBox(color: CreamPalette.better),
                          ),
                          Expanded(
                            flex: ((1 - share) * 1000).round(),
                            child: const ColoredBox(color: CreamPalette.warn),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: c.maxWidth * share - 20,
                    child: const VsBadge(),
                  ),
                ],
              ),
            ),
          ),
          figure(theirs, mineSide: false),
        ],
      ),
    );
  }
}

/// A side of the duel: a caption column on the left (who, and their total
/// power), the fan in the middle, and a small column on the right for what
/// belongs to that side (the rewards, the saved teams).
class VersusSide extends StatelessWidget {
  final String caption;

  /// "⚡ 630", or null when unknown.
  final String? power;
  final Widget fan;
  final Widget? trailing;

  const VersusSide({
    super.key,
    required this.caption,
    required this.fan,
    this.power,
    this.trailing,
  });

  static const double sideWidth = 96;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: sideWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              caption.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: kBoxAccent,
              ),
            ),
            if (power != null)
              Text(
                power!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kBoxInk,
                ),
              ),
          ],
        ),
      ),
      Expanded(child: Center(child: fan)),
      SizedBox(
        width: sideWidth + 20,
        child: trailing == null
            ? null
            : Align(alignment: Alignment.centerRight, child: trailing),
      ),
    ],
  );
}

/// The whole page body: [enemy] side (optional — Survival's team pick has none),
/// the [middle] row, [mine], and the [actions] row at the bottom.
class VersusStage extends StatelessWidget {
  final Widget? enemy;
  final Widget? middle;
  final Widget mine;
  final Widget actions;

  const VersusStage({
    super.key,
    required this.mine,
    required this.actions,
    this.enemy,
    this.middle,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: creamCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        children: [
          if (enemy != null) ...[
            Expanded(child: enemy!),
            if (middle != null) middle!,
          ],
          Expanded(child: mine),
          Container(
            height: 1,
            color: CreamPalette.tan.withValues(alpha: 0.4),
            margin: const EdgeInsets.only(top: 4, bottom: 6),
          ),
          SizedBox(height: 40, child: actions),
        ],
      ),
    ),
  );
}

/// A Combatant's tile: the same monster tile the Monsters grid draws, built from
/// a display-only stand-in whose stats ARE the combatant's resolved stats (so the
/// power, level and HP on the tile are the ones the fight will use). A boss gets
/// a crown before its name.
CreatureInstance enemyInstanceOf(Combatant e) => CreatureInstance(
  id: e.id,
  userId: '',
  speciesId: e.speciesId ?? '',
  nickname: e.isBoss ? '👑 ${e.name}' : e.name,
  gender: e.gender,
  level: e.level,
  stage: e.stage,
  statBase: {
    for (final s in CreatureStat.values) s: (e.stats[s] ?? 1).toDouble(),
  },
  statSlope: {for (final s in CreatureStat.values) s: 0.0},
  currentHp: e.hp,
);

/// Total of every stat — what the tile's ⚡ and the comparison bar show.
int combatantPower(Combatant e) =>
    CreatureStat.values.fold(0, (sum, s) => sum + (e.stats[s] ?? 0));

/// A small quiet line of text used under the fans.
Widget versusHint(String text) => Text(
  text,
  textAlign: TextAlign.center,
  style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
);
