import 'dart:math' as math;

import '../models/creature_enums.dart';
import '../models/creature_instance.dart';

// A monster's POWER (user request 2026-07-16): "so kann ich schnell sehen, wie
// mächtig ein Monster ist und wo es seine Stärken hat".
//
// Two numbers that add to one:
//
//   Power = Combat + Civil
//
// The split is the point. A single number tells you how good a monster is; the
// split tells you what it's good AT — a Carrier and a Tank can share a total
// and be nothing alike. That's the whole design of the stat system (every
// species spends the same budget, archetypes only redistribute it — see
// stat_budget.dart), so power has to show it or it hides the only decision.
//
// Deliberately just the SUM of the live stats, not a weighted "effectiveness"
// score. It is comparable to the budget targets by construction: a standard
// common at level 1 reads ~180 combat / ~190 civil (kCombatBudgetTarget /
// kNonCombatBudgetTarget), so the numbers on the card mean something you can
// look up. A weighting would drift from the framework the moment either moved.

/// Sum of the four combat stats — HP, attack, defense, speed.
/// Compare against kCombatBudgetTarget (180 for a standard common at Lv1).
int combatPower(CreatureInstance c) => CreatureStat.values
    .where((s) => s.isCombat)
    .fold(0, (sum, s) => sum + c.statValue(s));

/// Sum of the ten non-combat stats — the eight work roles plus carry and
/// catchRate. Compare against kNonCombatBudgetTarget (190 for a common at Lv1).
int civilPower(CreatureInstance c) => CreatureStat.values
    .where((s) => s.isCivilian)
    .fold(0, (sum, s) => sum + c.statValue(s));

/// The headline number: combat + civil.
int totalPower(CreatureInstance c) => combatPower(c) + civilPower(c);

/// The same sum read at LEVEL 1 — the monster's GENES, before any levelling.
///
/// The figure a breeding pair is judged on (user 2026-07-27): the current power
/// says how far a monster has been levelled, which tells you nothing about what
/// it passes on. Two creatures with the same total can carry very different
/// genes, and only this number separates them.
///
/// Mirrors [CreatureInstance.statValue] at level 1 — same missing-stat default
/// (10) and same floor (1) — so it is comparable with [totalPower] rather than
/// being a second, subtly different sum.
int levelOnePower(CreatureInstance c) => genePower(c.statBase);

/// [levelOnePower] over RAW genes, for something that is not a creature yet —
/// an egg's frozen child stats (user 2026-07-27, the Hatchery's egg tile).
///
/// Shared rather than re-summed there so an egg's ⚡ and the ⚡ the hatchling
/// wears on the very same tile shape are the same number by construction.
int genePower(Map<CreatureStat, double> genes) => CreatureStat.values.fold(
      0,
      (sum, s) => sum + math.max(1, (genes[s] ?? 10).round()).toInt(),
    );

/// Which side a monster leans to, 0..1 (0 = purely civil, 1 = purely combat,
/// 0.5 = balanced). Drives the "where are its strengths" bar.
double combatShare(CreatureInstance c) {
  final total = totalPower(c);
  return total <= 0 ? 0.5 : combatPower(c) / total;
}

/// The stats a monster is actually notable for: its [count] highest, ignoring
/// anything at or below the [floor] every creature gets for free.
///
/// statValue defaults a MISSING stat to 10 and floors at 1, so a monster with
/// no curve for a stat still reads 10 — listing those as "strengths" would
/// make every creature look like a generalist. Only what's above the pack
/// counts.
List<CreatureStat> topStats(
  CreatureInstance c, {
  int count = 3,
  int floor = 10,
}) {
  final ranked =
      CreatureStat.values.where((s) => c.statValue(s) > floor).toList()
        // Value desc, then name for a stable order between equal stats.
        ..sort((a, b) {
          final byValue = c.statValue(b).compareTo(c.statValue(a));
          return byValue != 0 ? byValue : a.name.compareTo(b.name);
        });
  return ranked.take(count).toList();
}
