import 'dart:math' as math;

import '../models/ability_def.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/species_def.dart';
import 'combat_engine.dart';

// Species-vs-species balancing matrix (dev tool, user spec 2026-07-21):
// every pairing of authored species fights 100 seeded 1v1 auto-battles at
// EQUAL level, through the REAL CombatEngine — abilities, buffs, the carried
// AP economy (the AI banks, see performAutoAction) and the type matrix all
// included. Reported per pairing: win rate, fight length in TOTAL actions
// (both sides; the 3–10 band is the user's requirement), per-ability usage,
// and on demand the level the LOSER needs to reach ≥50%.
//
// Combatants use MEAN genes (the species curve itself, no Gaussian roll):
// two runs of the matrix must measure balance, not luck.
//
// Pure Dart, no widgets — testable headless; the dev screen only renders it.

/// Fights per pairing (user: "immer 100 Kämpfe").
const int kMatrixRuns = 100;

/// A fight must last at least this many TOTAL actions (both sides)…
const int kMinFightActions = 3;

/// …and at most this many. Outside the band = a violation the tool flags.
const int kMaxFightActions = 10;

/// Safety guard: engine steps per run before a fight counts as stalled
/// (two healers can loop forever). A stalled fight is counted as a
/// too-long violation, not an exception.
const int kStallGuard = 400;

/// The evolution stage a species has reached at [level] — same rule as
/// Combatant.fromSpecies.
int stageAtLevel(SpeciesDef s, int level) =>
    level >= s.evoLevel2 ? 2 : (level >= s.evoLevel1 ? 1 : 0);

/// A combatant built from the species MEAN curves at [level] — no gene roll,
/// no wild handicap (kWildStatMult is a live-game dial, not a balance
/// property of the species itself).
Combatant meanCombatant(
  SpeciesDef s, {
  required int level,
  required bool isPlayerSide,
}) {
  final stage = stageAtLevel(s, level);
  final abilities = <AbilityDef>[];
  for (final sa in s.abilitiesAt(stage)) {
    final def = kAbilityDefs[sa.abilityId];
    if (def == null) continue;
    // Same affordability cap as Combatant._resolveAbilities: a move must be
    // payable at the stage it unlocks.
    final cap = maxActionPointsForStage(sa.unlockStage);
    abilities.add(def.resolvedApCost > cap ? def.withApCost(cap) : def);
  }
  return Combatant(
    id: '${s.id}_L$level${isPlayerSide ? 'p' : 'e'}',
    speciesId: s.id,
    name: s.name,
    element: s.element,
    rarity: s.rarity,
    isPlayerSide: isPlayerSide,
    level: level,
    stage: stage,
    stats: {
      for (final stat in kCombatStats)
        stat: math.max(
          1,
          (s.statCurve(stat).baseAt(stage) +
                  s.statCurve(stat).growth * (level - 1))
              .round(),
        ),
    },
    abilities: abilities,
  );
}

/// One cell of the matrix: [a] (player side) vs [b] (enemy side).
class PairingResult {
  final String aId;
  final String bId;
  final int runs;

  /// How often A won. Draw/stall counts as a loss for A — a stalled fight is
  /// a balance failure, not half a win.
  final double aWinRate;

  final int minActions;
  final int maxActions;
  final double medianActions;

  /// Runs shorter than [kMinFightActions] / longer than [kMaxFightActions]
  /// (stalls count as too long).
  final int tooShort;
  final int tooLong;

  /// Ability uses across all runs, per side (ability id → count).
  final Map<String, int> aAbilityUses;
  final Map<String, int> bAbilityUses;

  const PairingResult({
    required this.aId,
    required this.bId,
    required this.runs,
    required this.aWinRate,
    required this.minActions,
    required this.maxActions,
    required this.medianActions,
    required this.tooShort,
    required this.tooLong,
    required this.aAbilityUses,
    required this.bAbilityUses,
  });

  bool get lengthViolated => tooShort > 0 || tooLong > 0;
}

/// Runs [runs] seeded battles of [a] vs [b], both at [level].
PairingResult simulatePairing(
  SpeciesDef a,
  SpeciesDef b, {
  required int level,
  int runs = kMatrixRuns,
  int seed = 42,
}) {
  var aWins = 0;
  var tooShort = 0;
  var tooLong = 0;
  final actionCounts = <int>[];
  final aUses = <String, int>{};
  final bUses = <String, int>{};

  for (var run = 0; run < runs; run++) {
    final engine = CombatEngine(
      players: [meanCombatant(a, level: level, isPlayerSide: true)],
      enemies: [meanCombatant(b, level: level, isPlayerSide: false)],
      rng: math.Random(seed + run),
    );
    var guard = 0;
    while (engine.outcome == null && guard < kStallGuard) {
      engine.performAutoAction();
      guard++;
    }
    final stalled = engine.outcome == null;
    if (engine.outcome == CombatOutcome.victory) aWins++;

    final total = engine.playerActionsTaken + engine.enemyActionsTaken;
    actionCounts.add(total);
    if (stalled || total > kMaxFightActions) {
      tooLong++;
    } else if (total < kMinFightActions) {
      tooShort++;
    }
    engine.playerAbilityUses.forEach(
      (id, n) => aUses[id] = (aUses[id] ?? 0) + n,
    );
    engine.enemyAbilityUses.forEach(
      (id, n) => bUses[id] = (bUses[id] ?? 0) + n,
    );
    engine.dispose();
  }

  actionCounts.sort();
  final median = actionCounts.isEmpty
      ? 0.0
      : actionCounts.length.isOdd
          ? actionCounts[actionCounts.length ~/ 2].toDouble()
          : (actionCounts[actionCounts.length ~/ 2 - 1] +
                  actionCounts[actionCounts.length ~/ 2]) /
              2.0;

  return PairingResult(
    aId: a.id,
    bId: b.id,
    runs: runs,
    aWinRate: runs > 0 ? aWins / runs : 0,
    minActions: actionCounts.isEmpty ? 0 : actionCounts.first,
    maxActions: actionCounts.isEmpty ? 0 : actionCounts.last,
    medianActions: median,
    tooShort: tooShort,
    tooLong: tooLong,
    aAbilityUses: aUses,
    bAbilityUses: bUses,
  );
}

/// The smallest level the LOSER of [winner] vs [loser] (at [baseLevel]) needs
/// to win ≥50% of fights — the loser levels up, the winner stays at
/// [baseLevel]. Null when even level [kCreatureMaxLevel] doesn't get there
/// (a hard type counter with mild level growth may never flip).
///
/// Binary search: win rate is monotonic in level for all practical purposes,
/// and a linear walk to 75 would cost dozens of simulations per cell.
int? levelToWinHalf(
  SpeciesDef loser,
  SpeciesDef winner, {
  required int baseLevel,
  int runs = 60,
  int seed = 42,
}) {
  // simulatePairing puts both at the same level, so the asymmetric probe (the
  // loser levels, the winner stays put) is inlined here.
  double asymRate(int loserLevel) {
    var wins = 0;
    for (var run = 0; run < runs; run++) {
      final engine = CombatEngine(
        players: [meanCombatant(loser, level: loserLevel, isPlayerSide: true)],
        enemies: [
          meanCombatant(winner, level: baseLevel, isPlayerSide: false),
        ],
        rng: math.Random(seed + run),
      );
      var guard = 0;
      while (engine.outcome == null && guard < kStallGuard) {
        engine.performAutoAction();
        guard++;
      }
      if (engine.outcome == CombatOutcome.victory) wins++;
      engine.dispose();
    }
    return wins / runs;
  }

  if (asymRate(baseLevel) >= 0.5) return baseLevel;
  var lo = baseLevel + 1;
  var hi = kCreatureMaxLevel;
  if (asymRate(hi) < 0.5) return null;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if (asymRate(mid) >= 0.5) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

// ── Auto-tuning (one previewable step) ─────────────────────

/// One proposed change, shown in the preview diff before anything is written.
class TuneChange {
  /// 'species' or 'ability'.
  final String kind;
  final String id;
  final String field;
  final String oldValue;
  final String newValue;
  final String reason;

  /// The full updated def to upsert when applied (exactly one of the two).
  final SpeciesDef? species;
  final AbilityDef? ability;

  const TuneChange({
    required this.kind,
    required this.id,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.reason,
    this.species,
    this.ability,
  });
}

/// Proposes ONE tuning step from a computed matrix — deliberately not an
/// autopilot: you run the matrix, look at the diff, apply, run again. Rules:
///
///  • Fights too SHORT across a species' pairings → shift stat budget from
///    attack into HP (same total — the budget framework stays intact); too
///    LONG → the reverse.
///  • A species winning ≫50% against same-rarity peers → its most-used
///    ability loses 10% power; ≪50% → its best ability gains 10%.
///    (Same-rarity only: rarity and tier hierarchies are deliberate. Type
///    advantage is INCLUDED per user decision 2026-07-21 — perfect 50%
///    everywhere is impossible with a type cycle, so this minimises the
///    spread instead.)
///  • An ability with ZERO uses across every pairing → AP cost −1 (min 1);
///    if already at 1, power +15% — make it worth picking.
List<TuneChange> proposeTuning({
  required List<PairingResult> results,
  required Map<String, SpeciesDef> species,
  required Map<String, AbilityDef> abilities,
}) {
  final changes = <TuneChange>[];
  if (results.isEmpty) return changes;

  // Aggregate per species: win rate vs same-rarity peers, fight-length skew,
  // ability usage.
  final winSum = <String, double>{};
  final winCnt = <String, int>{};
  final shortRuns = <String, int>{};
  final longRuns = <String, int>{};
  final uses = <String, Map<String, int>>{};

  for (final r in results) {
    final a = species[r.aId];
    final b = species[r.bId];
    if (a == null || b == null) continue;
    if (a.rarity == b.rarity && r.aId != r.bId) {
      winSum[r.aId] = (winSum[r.aId] ?? 0) + r.aWinRate;
      winCnt[r.aId] = (winCnt[r.aId] ?? 0) + 1;
      winSum[r.bId] = (winSum[r.bId] ?? 0) + (1 - r.aWinRate);
      winCnt[r.bId] = (winCnt[r.bId] ?? 0) + 1;
    }
    shortRuns[r.aId] = (shortRuns[r.aId] ?? 0) + r.tooShort;
    longRuns[r.aId] = (longRuns[r.aId] ?? 0) + r.tooLong;
    shortRuns[r.bId] = (shortRuns[r.bId] ?? 0) + r.tooShort;
    longRuns[r.bId] = (longRuns[r.bId] ?? 0) + r.tooLong;
    uses.putIfAbsent(r.aId, () => {});
    r.aAbilityUses.forEach(
      (id, n) => uses[r.aId]![id] = (uses[r.aId]![id] ?? 0) + n,
    );
    uses.putIfAbsent(r.bId, () => {});
    r.bAbilityUses.forEach(
      (id, n) => uses[r.bId]![id] = (uses[r.bId]![id] ?? 0) + n,
    );
  }

  final touchedAbilities = <String>{};

  for (final s in species.values) {
    // 1) Fight length → budget-locked HP↔ATK shift (5% of the smaller pool).
    final short = shortRuns[s.id] ?? 0;
    final long = longRuns[s.id] ?? 0;
    if (short + long > 0 && short != long) {
      final hp = s.statCurve(CreatureStat.hp);
      final atk = s.statCurve(CreatureStat.attack);
      final tooShortDominates = short > long;
      // Too short → tankier: ATK gives 5% of itself to HP. Too long → reverse.
      final from = tooShortDominates ? atk : hp;
      final to = tooShortDominates ? hp : atk;
      final delta = [for (final b in from.stageBase) b * 0.05];
      final newFrom = StatCurve(
        stageBase: [
          for (var i = 0; i < 3; i++) from.stageBase[i] - delta[i],
        ],
        growth: from.growth,
      );
      final newTo = StatCurve(
        stageBase: [for (var i = 0; i < 3; i++) to.stageBase[i] + delta[i]],
        growth: to.growth,
      );
      final stats = Map<CreatureStat, StatCurve>.from(s.stats);
      stats[tooShortDominates ? CreatureStat.attack : CreatureStat.hp] =
          newFrom;
      stats[tooShortDominates ? CreatureStat.hp : CreatureStat.attack] = newTo;
      changes.add(
        TuneChange(
          kind: 'species',
          id: s.id,
          field: tooShortDominates ? 'ATK→HP 5%' : 'HP→ATK 5%',
          oldValue: tooShortDominates
              ? 'ATK ${atk.stageBase.map((b) => b.round()).toList()}'
              : 'HP ${hp.stageBase.map((b) => b.round()).toList()}',
          newValue: tooShortDominates
              ? 'ATK ${newFrom.stageBase.map((b) => b.round()).toList()}'
              : 'ATK ${newTo.stageBase.map((b) => b.round()).toList()}',
          reason: tooShortDominates
              ? '$short runs under $kMinFightActions actions — fights too short'
              : '$long runs over $kMaxFightActions actions — fights too long',
          species: s.copyWithStats(stats),
        ),
      );
    }

    // 2) Same-rarity win-rate outliers → tune the species' signature ability.
    final cnt = winCnt[s.id] ?? 0;
    if (cnt > 0) {
      final avg = winSum[s.id]! / cnt;
      if ((avg - 0.5).abs() > 0.07) {
        final used = uses[s.id] ?? {};
        // Most-used damage ability this species actually owns.
        AbilityDef? pick;
        var pickUses = -1;
        for (final sa in s.abilities) {
          final def = kAbilityDefs[sa.abilityId] ?? abilities[sa.abilityId];
          if (def == null || def.kind != AbilityKind.damage) continue;
          final n = used[def.id] ?? 0;
          if (n > pickUses) {
            pickUses = n;
            pick = def;
          }
        }
        if (pick != null && !touchedAbilities.contains(pick.id)) {
          touchedAbilities.add(pick.id);
          final factor = avg > 0.5 ? 0.9 : 1.1;
          final newPower = math.max(5, (pick.power * factor).round());
          if (newPower != pick.power) {
            changes.add(
              TuneChange(
                kind: 'ability',
                id: pick.id,
                field: 'power',
                oldValue: '${pick.power}',
                newValue: '$newPower',
                reason:
                    '${s.name} wins ${(avg * 100).round()}% vs same rarity',
                ability: _abilityWithPower(pick, newPower),
              ),
            );
          }
        }
      }
    }

    // 3) Dead abilities → cheaper, or stronger once already at 1 AP.
    final used = uses[s.id] ?? {};
    for (final sa in s.abilities) {
      final def = kAbilityDefs[sa.abilityId] ?? abilities[sa.abilityId];
      if (def == null) continue;
      if ((used[def.id] ?? 0) > 0) continue;
      if (touchedAbilities.contains(def.id)) continue;
      touchedAbilities.add(def.id);
      if (def.resolvedApCost > 1) {
        changes.add(
          TuneChange(
            kind: 'ability',
            id: def.id,
            field: 'apCost',
            oldValue: '${def.resolvedApCost}',
            newValue: '${def.resolvedApCost - 1}',
            reason: 'never used by ${s.name} across the whole matrix',
            ability: def.withApCost(def.resolvedApCost - 1),
          ),
        );
      } else {
        final newPower = math.max(5, (def.power * 1.15).round());
        changes.add(
          TuneChange(
            kind: 'ability',
            id: def.id,
            field: 'power',
            oldValue: '${def.power}',
            newValue: '$newPower',
            reason: 'never used by ${s.name}, already at 1 AP',
            ability: _abilityWithPower(def, newPower),
          ),
        );
      }
    }
  }
  return changes;
}

AbilityDef _abilityWithPower(AbilityDef a, int power) => AbilityDef(
      id: a.id,
      name: a.name,
      description: a.description,
      element: a.element,
      kind: a.kind,
      target: a.target,
      power: power,
      priority: a.priority,
      healPct: a.healPct,
      lifestealPct: a.lifestealPct,
      inflictMain: a.inflictMain,
      inflictMainChance: a.inflictMainChance,
      inflictDebuff: a.inflictDebuff,
      inflictDebuffChance: a.inflictDebuffChance,
      selfBuff: a.selfBuff,
      selfPenaltyStat: a.selfPenaltyStat,
      selfPenaltyMult: a.selfPenaltyMult,
      selfPenaltyTurns: a.selfPenaltyTurns,
      apCost: a.apCost,
    );
