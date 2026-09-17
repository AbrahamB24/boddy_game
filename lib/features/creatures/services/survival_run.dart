import 'dart:math' as math;

import '../../../core/tuning/game_tuning.dart';
import '../models/combatant.dart';
import '../models/species_def.dart';
import 'combat_engine.dart' show CombatEngine;
import 'overworld_path.dart' show enemyCountForBattle, kBossLevelBonus;

// ── Survival Mode — endless, campaign-independent battles (user 2026-09-06:
// "ich hätte gerne den survival modus, aber mit 6 Monster") ─────────────────
//
// Pick a full 6-monster party once, then fight floor after floor with no
// return to base between them (Bag items ARE allowed) until the whole team
// is wiped or the player retreats. Difficulty climbs on its OWN floor
// counter — never the player's actual campaign battlesCleared — which is
// what makes it a mode you can dip into at any point in the campaign rather
// than something that gets easier the further along you already are.
//
// Deliberately reuses the campaign's own TUNED pacing shape rather than
// inventing a fresh, unplaytested curve: [enemyCountForBattle] is a pure
// function of an integer "battle number" already (see overworld_path.dart),
// so feeding it the floor number directly is safe. The one thing NOT reused
// is [isBossBattle]/[enemyLevelForBattle] as a pair — those tie a boss's
// timing to the campaign's own region-length dial, which would make
// Survival's boss cadence silently follow a campaign balance knob it has
// nothing to do with. So the level curve is replicated here (same simple
// "+1 every two floors" shape) with boss timing gated on Survival's own
// dial instead.

/// Every so many floors is a boss (stronger stats, more XP) instead of a
/// normal encounter.
int get kSurvivalBossEveryNFloors =>
    GameTuning.i.count(Dials.survivalBossEveryNFloors);

/// Gold paid out per floor cleared, before the triangular scaling in
/// [goldRewardForFloors] — see that dial's own help text for why triangular.
double get kSurvivalGoldPerFloor =>
    GameTuning.i.raw(Dials.survivalGoldPerFloor);

/// Whether [floor] (1-based) is a boss floor.
bool isSurvivalBossFloor(int floor) =>
    floor > 0 && floor % kSurvivalBossEveryNFloors == 0;

/// Enemy level for [floor] — same "+1 every two steps" shape
/// [enemyLevelForBattle] uses for the campaign, but gated on Survival's OWN
/// boss cadence ([isSurvivalBossFloor]), not the campaign's region length.
int survivalEnemyLevel(int floor) {
  final n = floor < 1 ? 1 : floor;
  final base = 1 + (n - 1) ~/ 2;
  return isSurvivalBossFloor(n) ? base + kBossLevelBonus : base;
}

/// The enemy squad for [floor] — a fresh random pick every time (unlike the
/// campaign's own seeded-per-node squads, Survival has no "node" to keep
/// reproducible; variety is the point of an endless mode).
///
/// [rng] is exposed only for tests; real callers should omit it.
List<Combatant> buildFloorSquad(int floor, {math.Random? rng}) {
  final pool = kSpeciesDefs.values.toList();
  if (pool.isEmpty) return const [];
  final r = rng ?? math.Random();
  final level = survivalEnemyLevel(floor);
  final isBoss = isSurvivalBossFloor(floor);
  // Bosses are always a lone elite, same convention the campaign uses (see
  // enemyCountForBattle's own doc) — a boss with backup would both outgun
  // the stat bump AND read like a regular pack.
  final count = isBoss
      ? 1
      : enemyCountForBattle(floor).clamp(1, CombatEngine.kFieldSlots);
  return [
    for (var i = 0; i < count; i++)
      Combatant.fromSpecies(
        pool[r.nextInt(pool.length)],
        level: level,
        id: 'surv_f${floor}_$i',
        isBoss: isBoss,
        rng: r,
      ),
  ];
}

/// Gold for banking a run that reached [floorsCleared] (0 if the player was
/// wiped or retreated before clearing even the first floor). Triangular
/// (1+2+…+N, not N) so a deeper run pays disproportionately more than N
/// times a shallow one — see Dials.survivalGoldPerFloor's help text.
double goldRewardForFloors(int floorsCleared) => floorsCleared <= 0
    ? 0
    : kSurvivalGoldPerFloor * floorsCleared * (floorsCleared + 1) / 2;
