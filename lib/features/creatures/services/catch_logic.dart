import 'dart:math' as math;

import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/species_def.dart';

/// How catching behaves after a won battle. `none` = no attempt (training
/// fights — catching stays a dungeon reward, protecting the gold sink),
/// `standard` = one attempt at the formula chance, `guaranteed` = the
/// catch space's promise: one attempt that always succeeds.
enum CatchMode { none, standard, guaranteed }

// Catch chance (balance-pass formula, no ball items — per explicit design
// decision, the catcher's OWN Fangwert is the only lever, no item economy):
//
//   HP_Term    = (3·MaxHP − 2·CurHP) / (3·MaxHP)   — 0.33 (full) .. 1.0 (near dead)
//   CatchRatio = Fangwert / (Fangwert + Ziel-Level)
//   chance = HP_Term · (0.4 + 0.6·CatchRatio) · Seltenheit(Ziel) · speciesRate
//   clamped to [0.02, 1.0] — the spec's own ceiling is 1.0; the 0.02 floor
//   is a small UX addition so a chance bar never literally reads "0%".
//
// Uses the TEAM's best surviving Fangwert (see bestCatchPower) so keeping
// the catcher alive through the fight is rewarded. Pure function,
// unit-tested.
double catchChance({required Combatant target, required List<Combatant> team}) {
  final best = bestCatchPower(team);
  final hpTerm = (3 * target.maxHp - 2 * target.hp) / (3 * target.maxHp);
  final catchRatio = best / (best + target.level);
  final raw =
      hpTerm *
      (0.4 + 0.6 * catchRatio) *
      target.rarity.catchFactor *
      (kSpeciesDefs[target.speciesId]?.catchRate ?? 1.0);
  return raw.clamp(0.02, 1.0);
}

/// Highest Fangwert among living team members (0 if everyone is K.O. —
/// can't happen after a WON fight, but stays safe).
int bestCatchPower(List<Combatant> team) {
  var best = 0;
  for (final c in team) {
    if (!c.alive) continue;
    best = math.max(best, c.stat(CreatureStat.catchRate));
  }
  return best;
}
