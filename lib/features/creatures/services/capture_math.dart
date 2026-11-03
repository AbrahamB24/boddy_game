import 'dart:math' as math;

import '../models/area.dart';
import '../models/creature_enums.dart';
import '../models/dungeon.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';
import '../../../core/tuning/game_tuning.dart';

// Pure, unit-tested math for CAPTURE expeditions — the encounter/QTE model
// (user design, 2026-07-15, replacing the old weaken-then-catch chance roll):
//
//   1. A capture expedition goes to an AREA, not to a chosen species. What it
//      finds is rolled from the area's pool, with rarity odds that improve in
//      later/more dangerous areas (rollEncounter/rarityWeights).
//   2. The find stays hidden while the group is out. When the timer is up the
//      player plays the encounter: a shrinking ring, tap in the target zone.
//   3. The rarer the find, the faster the ring — the group's summed catch
//      stat slows it back down (qteSeconds). Rare finds need several perfect
//      hits in a row; commons need just one (qteHitsRequired). Any miss and
//      the monster escapes.
//
// Catching is now SKILL-gated, not RNG-gated — the dice decide only WHAT you
// find, never whether a well-played catch sticks.

/// Species that live in [area] — its explicit pool, or every defined species
/// when the pool is empty (the dungeon `null = all` convention). Only ids that
/// actually resolve in kSpeciesDefs are returned. The region's LEGENDARY (= the
/// area's boss species) is excluded unless [includeLegendary].
///
/// This is the REGION'S ROSTER, which is what a region dungeon fields. It is no
/// longer what a hunt may catch — see [catchableSpecies].
List<SpeciesDef> eligibleSpecies(AreaDef area, {bool includeLegendary = true}) {
  final pool = area.speciesPoolIds.isNotEmpty
      ? [
          for (final id in area.speciesPoolIds)
            if (kSpeciesDefs[id] != null) kSpeciesDefs[id]!,
        ]
      : kSpeciesDefs.values.toList();
  if (includeLegendary || area.bossSpeciesId == null) return pool;
  return pool.where((s) => s.id != area.bossSpeciesId).toList();
}

/// EVERY SPECIES IS ALWAYS CATCHABLE — except the legendaries (user 2026-07-27:
/// "nimm die barriere raus, dass monster nur bei gewissen Stufen des pfades
/// gefangen werden können. Es sind alle immer frei zum Fangen, ausser die
/// Legendären, welche dem Pool erst nach dem besiegen hinzugefügt werden").
///
/// A hunt used to roll from the AREA's own pool, and areas open with the path —
/// so which monsters existed for you at all was a function of how far you had
/// climbed. Two thirds of the roster were simply unreachable for hours, and a
/// species you had seen in the Bestiary could not be gone after.
///
/// Now the path decides only WHERE you hunt (danger level, wild level, the
/// travel), never WHICH species the world contains. The one exception is the
/// legendaries: they join the pool the moment they have been beaten, which is
/// what makes clearing a region's boss worth something beyond the XP.
///
/// [dungeonMaxStage] is the campaign progress — see [defeatedLegendaryIds].
List<SpeciesDef> catchableSpecies(int dungeonMaxStage) {
  final unlocked = defeatedLegendaryIds(dungeonMaxStage);
  return [
    for (final s in kSpeciesDefs.values)
      if (s.rarity != CreatureRarity.legendary || unlocked.contains(s.id)) s,
  ];
}

/// The legendaries that have been DEFEATED at [dungeonMaxStage] — the boss
/// species of every region whose boss is down.
///
/// A region counts as cleared once the campaign has moved PAST its stage, which
/// is the same test the launch sheet and the overworld already use.
Set<String> defeatedLegendaryIds(int dungeonMaxStage) => {
  for (final a in areasInOrder())
    if (a.bossSpeciesId != null && a.battleStage < dungeonMaxStage)
      a.bossSpeciesId!,
};

/// The level a wild of any species appears at in [area] (shared with combat).
int captureTargetLevel(AreaDef area) => wildLevelForStage(area.battleStage);

// ── What you find ───────────────────────────────────────────

/// Encounter weight per rarity (tunable per rarity in Dev Mode → Species
/// Balance). No longer scaled by an area "danger level" (removed 2026-09-11
/// — no area had ever actually been authored above the default, so that
/// dimension changed nothing in the live game). Sums to 100 by default, so it
/// reads directly as percentages before any hunt-length bias.
Map<CreatureRarity, double> rarityWeights() => {
  for (final r in CreatureRarity.values)
    r: kSpeciesBalance.of(r).encounterWeightBase.clamp(0.0, double.infinity),
};

/// Rolls what a capture expedition finds: rarity first (restricted to
/// rarities the pool actually offers), then a uniform species within that
/// rarity. Null when the pool is empty.
///
/// The POOL is every species in the game minus the legendaries still standing
/// ([catchableSpecies]) — not a per-area guest list. Odds are the SAME
/// regardless of hunt length (removed 2026-09-11 — a longer hunt used to bias
/// toward rarer finds; the user wants length to only ever change the NUMBER
/// of finds, never their odds).
SpeciesDef? rollEncounter(math.Random rng, {required int dungeonMaxStage}) {
  final pool = catchableSpecies(dungeonMaxStage);
  if (pool.isEmpty) return null;

  final byRarity = <CreatureRarity, List<SpeciesDef>>{};
  for (final s in pool) {
    byRarity.putIfAbsent(s.rarity, () => []).add(s);
  }
  final weights = rarityWeights();
  final available = byRarity.keys.toList();
  final total = available.fold<double>(0, (sum, r) => sum + (weights[r] ?? 0));
  if (total <= 0) return pool[rng.nextInt(pool.length)];

  var roll = rng.nextDouble() * total;
  for (final r in available) {
    roll -= weights[r] ?? 0;
    if (roll <= 0) {
      final candidates = byRarity[r]!;
      return candidates[rng.nextInt(candidates.length)];
    }
  }
  return pool[rng.nextInt(pool.length)];
}

// ── The catch battle ────────────────────────────────────────

/// Battle-stat multiplier for the wild in a CATCH fight (on top of the
/// general kWildStatMult, so ~0.64 combined). Catching is skill-gated — the
/// QTE is the challenge, and the battle in front of it is the lever that
/// opens the window, not a survival check (user report 2026-07-17: an
/// equal-level wild sometimes beat the starter outright). Dungeon and trial
/// wilds are untouched: those fights ARE the challenge.
double get kCaptureWildStatMult => GameTuning.i.raw(Dials.captureWildStatMult);

/// HP fraction the wild must be fought DOWN TO before the catch QTE opens —
/// the encounter's battle phase. Rarer finds must be brought lower, without
/// killing them: a dead wild is nothing to catch.
const Map<CreatureRarity, double> kCatchHpThreshold = {
  CreatureRarity.common: 0.70,
  CreatureRarity.uncommon: 0.55,
  CreatureRarity.rare: 0.40,
  CreatureRarity.epic: 0.25,
  CreatureRarity.legendary: 0.12,
};

double catchHpThreshold(CreatureRarity rarity) =>
    kCatchHpThreshold[rarity] ?? 0.5;

// ── The catch QTE ───────────────────────────────────────────

/// Seconds the ring takes to shrink fully, per rarity — before the group's
/// catch stat slows it down. (Tightened after playtest: "too easy".)
const Map<CreatureRarity, double> kQteBaseSeconds = {
  CreatureRarity.common: 2.2,
  CreatureRarity.uncommon: 1.9,
  CreatureRarity.rare: 1.55,
  CreatureRarity.epic: 1.2,
  CreatureRarity.legendary: 0.9,
};

// (kQteCatchK / kQteMaxSlow removed 2026-07-17 — catchRate no longer slows
// the ring; it widens the window instead. See kQteWindowCatchK / qteWindow.)

/// Each successive hit round shrinks a bit faster than the last.
double get kQteRoundSpeedup => GameTuning.i.raw(Dials.qteRoundSpeedup);

/// Every round's duration is jittered by up to ±this fraction so the rhythm
/// can't simply be memorized across rounds/retries.
const double kQteDurationJitter = 0.12;

/// Ring-timing window: the tap counts while the shrinking ring's radius
/// fraction (1 → 0) sits inside the band around [kQteWindowCenter]. Rarer
/// finds demand TIGHTER timing — precision scales with rarity alongside
/// speed. (At the threshold: common ≈ 300ms of valid window, legendary ≈
/// 50ms — both grow as the wild is fought lower, see [qteWindow].)
double get kQteWindowCenter => GameTuning.i.raw(Dials.qteWindowCenter);

const Map<CreatureRarity, double> kQteWindowHalfWidth = {
  CreatureRarity.common: 0.07,
  CreatureRarity.uncommon: 0.06,
  CreatureRarity.rare: 0.05,
  CreatureRarity.epic: 0.04,
  CreatureRarity.legendary: 0.03,
};

/// How deep the wild's HP sits INSIDE its catchable band, on a 0→1 scale:
/// 0 exactly at the catch threshold, 1 as HP approaches 0. The band
/// (threshold → 0 HP) is treated as its own 100% — e.g. threshold 50% and
/// HP 25% → depth 0.5.
double catchDepth(CreatureRarity rarity, double hpFraction) {
  final threshold = catchHpThreshold(rarity);
  if (threshold <= 0) return 0;
  return ((threshold - hpFraction) / threshold).clamp(0.0, 1.0);
}

/// catchRate at which the window-widening bonus is halfway to its cap.
double get kQteWindowCatchK => GameTuning.i.raw(Dials.qteWindowCatchK);

/// The most the ACTIVE monster's catchRate can widen the golden zone
/// (+120% at an infinite catchRate). This is now catchRate's ONLY effect —
/// the ring SPEED no longer depends on it (user design 2026-07-17).
double get kQteMaxWidthBonus => GameTuning.i.raw(Dials.qteMaxWidthBonus);

/// The valid tap band, as radius fractions. Width is set by three things:
/// the rarity base, how deep the wild was fought below its threshold, and —
/// the key lever now — the ACTIVE catcher's catchRate (user design
/// 2026-07-17: a dedicated catcher widens the zone; ring speed is fixed).
/// The number of required hits and the ring speed are untouched by catchRate.
({double lo, double hi}) qteWindow(
  CreatureRarity rarity, {
  double hpFraction = 1.0,
  int catchRate = 0,
}) {
  final catcherBonus =
      kQteMaxWidthBonus * (catchRate / (catchRate + kQteWindowCatchK));
  final half =
      (kQteWindowHalfWidth[rarity] ?? 0.05) *
      (1 + catchDepth(rarity, hpFraction)) *
      (1 + catcherBonus);
  return (lo: kQteWindowCenter - half, hi: kQteWindowCenter + half);
}

/// Ring-shrink duration for one QTE round. FIXED per rarity (rarer = faster)
/// — catchRate no longer affects it (user design 2026-07-17). A slippery
/// species (catchRate < 1) still speeds it back up, and later rounds shrink
/// a bit faster.
double qteSeconds(SpeciesDef species, {int round = 0}) {
  final base = kQteBaseSeconds[species.rarity] ?? 2.5;
  final slippery = species.catchRate.clamp(0.5, 1.5);
  final roundFactor = math.pow(kQteRoundSpeedup, round).toDouble();
  return base * slippery * roundFactor;
}

/// Perfect hits in a row required to catch, by rarity — miss once and the
/// monster escapes. Dev-tunable per rarity (kSpeciesBalance.catchHits); at least
/// one hit is always needed.
int qteHitsRequired(CreatureRarity rarity) =>
    kSpeciesBalance.of(rarity).catchHits.clamp(1, 99);

// ── Hunt variants (user design 2026-07-17; switched from a wall clock to
// REAL STEPS 2026-10-02 — "ich möchte nur noch diese Hunts und nicht mehr
// auf Zeit") ──────────────────────────────────────────────────
// Five fixed-step hunts. The step count is FIXED per variant (not derived
// from a base × multiplier) — the trip length still never leaks the hidden
// finds' rarity because it's the same for everyone who picks that variant.
//
// Gating is by campaign progress, not by roster size (see _unlockedOptions in
// the launch sheet) — how many hunters you send no longer decides which
// variants are reachable at all (see the ladder's own comment below).

class CaptureHuntOption {
  final String id;

  /// Real steps (StepTrackerService) this hunt needs — see
  /// Expedition.stepsTarget/stepsWalked for how a trip actually tracks
  /// this, and ExpeditionController.creditSteps for how steps reach it.
  final int steps;

  /// How many monsters the hunt brings home. Each is a wild fielded in ONE
  /// continuous battle, not a separate fight per find (2026-09-11 — see the
  /// ladder's own comment).
  final int finds;

  /// Short human label for the step count ("500 Schritte", "10.000 Schritte").
  final String label;

  const CaptureHuntOption({
    required this.id,
    required this.steps,
    required this.finds,
    required this.label,
  });
}

// ── The hunt ladder (user 2026-07-30, revised 2026-09-11, moved to real
// steps 2026-10-02) ──────────────────────────────────────────
// A hunt's TEAM still follows the same growing cap Gather already uses
// (CreaturesController.teamSizeCap) rather than a fixed count tied to the
// variant — see the launch sheet's own _groupCap. That reverses the
// 2026-07-30 "every hunt sends exactly one monster" rule, but for a
// different reason than the one that rule fixed: a longer hunt still never
// NEEDS more hunters to be reachable at all, it needs them to actually
// survive fighting through all its finds. All N of a hunt's finds are now
// fielded as ONE continuous multi-enemy battle (CombatEngine's existing
// field-of-3-plus-bench mechanic, the same one dungeon/Survival/Training
// battles already use) instead of N separate back-to-back 1v1s with no HP
// reset between them — which is what made a solo hunter on a long hunt
// nearly guaranteed to get KO'd partway through and forfeit every find after
// that (user: "Das schaffe ich wohl mit nur einem Monster nicht"). Bringing
// more than one hunter is now a real, useful choice again, not a
// requirement.
//
// The only thing a longer hunt costs is EFFORT (real steps, or gold to skip
// them — see ExpeditionController.goldSkipCost), and the only thing it buys
// is finds: 1 · 2 · 3 · 5 · 8. Growth is steep but sub-linear against the
// step count — 10.000 steps returns 8 finds where 20× 500-step hunts would
// return 20 — so sitting on a long hunt is a convenience, never the
// efficient play (same invariant the old time ladder had, just measured in
// steps now).
const List<CaptureHuntOption> kCaptureHuntOptions = [
  CaptureHuntOption(id: 'h500', steps: 500, finds: 1, label: '500 Schritte'),
  CaptureHuntOption(id: 'h1000', steps: 1000, finds: 2, label: '1.000 Schritte'),
  CaptureHuntOption(id: 'h2000', steps: 2000, finds: 3, label: '2.000 Schritte'),
  CaptureHuntOption(id: 'h5000', steps: 5000, finds: 5, label: '5.000 Schritte'),
  CaptureHuntOption(
    id: 'h10000',
    steps: 10000,
    finds: 8,
    label: '10.000 Schritte',
  ),
];

// kMaxHunters and huntOptionForHunters were DELETED on 2026-07-30. Both were
// ways of identifying a variant by its party size, which stopped meaning
// anything the moment every hunt sends exactly one monster: the lookup would
// have answered "the 10-minute hunt" for every possible input, silently. The
// variant is chosen by the player, and `_option` is what carries it.

/// A hunt's real step target after the Scout Post's travel bonus and the
/// tutorial's jumpstart scale — both previously shrank [captureDuration]
/// (now deleted); they shrink the step count the same way instead, down to
/// a floor of 1 so a hunt is never free. Applied ONCE at send time (see
/// ExpeditionController.startCapture) and stored on the trip itself, so a
/// later Scout Post upgrade never retroactively shortens a hunt already
/// under way.
int effectiveHuntSteps(
  CaptureHuntOption option, {
  double timeScale = 1.0,
  double travelMult = 1.0,
}) {
  final mult = travelMult <= 0 ? 1.0 : travelMult;
  return math.max(1, (option.steps * timeScale / mult).round());
}

// ── The Balkenjagd catch minigame (user 2026-10-01, replacing the ring QTE
// above for the actual catch moment — the ring's own math is left in place
// since Dials/kSpeciesBalance still reference it, but battle_screen.dart no
// longer calls it) ──────────────────────────────────────────
//
// Four independent levers, each owning exactly one thing (user's own split):
//   1. Resteleben (how deep the wild sits below its catch threshold, see
//      [catchDepth] above) → the wild's SPEED in the bar (deeper = slower).
//   2. The active catcher's catchRate stat → the catch BAR'S WIDTH.
//   3. Rarity → the wild's BASE speed/erraticism AND the fixed round length.
//   4. The thrown item (ItemKind.catchBoost) → ONLY the starting percentage —
//      see that enum case's own doc for why it's capped well under 50%.
//
// The live percentage can only ever climb (no drain) while the bar overlaps
// the wild, and never drops — a round never "fails early", it always runs
// its full fixed length, then rolls once against whatever percentage was
// reached. A miss does not forfeit the wild (see CombatEngine.attemptCatch's
// own doc) — only the thrown item is spent.

/// The wild's base speed (bar-fraction per second) and how erratically it
/// re-directs, before the Resteleben multiplier below. Also sets how long one
/// round runs — longer for rarer finds (more time to accumulate skill
/// points), but speed grows faster than duration, so it nets out HARDER, not
/// easier (user 2026-10-01: "mehr Zeit, aber auch mehr Zeit für Fehler").
const Map<CreatureRarity, double> kBarBaseSpeed = {
  CreatureRarity.common: 0.24,
  CreatureRarity.uncommon: 0.29,
  CreatureRarity.rare: 0.34,
  CreatureRarity.epic: 0.40,
  CreatureRarity.legendary: 0.47,
};

/// Chance per ~16ms frame the wild snaps to a new random direction/target —
/// the "erratic" half of its movement, on top of the steady bounce.
const Map<CreatureRarity, double> kBarTurnProb = {
  CreatureRarity.common: 0.0035,
  CreatureRarity.uncommon: 0.0048,
  CreatureRarity.rare: 0.0065,
  CreatureRarity.epic: 0.0085,
  CreatureRarity.legendary: 0.0105,
};

/// Fixed round length per rarity. Doubled 2026-10-04 (user: "sollte das
/// Fangminispiel länger dauern, doppelt so lange") — [barSkillGainPerSecond]
/// divides [kBarSkillMax] by this, so the doubled length alone keeps the
/// same 60-point ceiling reachable, just spread over twice the real time.
const Map<CreatureRarity, int> kBarDurationMs = {
  CreatureRarity.common: 9000,
  CreatureRarity.uncommon: 10400,
  CreatureRarity.rare: 12000,
  CreatureRarity.epic: 13600,
  CreatureRarity.legendary: 15000,
};

double barBaseSpeed(CreatureRarity r) => kBarBaseSpeed[r] ?? 0.3;
double barTurnProb(CreatureRarity r) => kBarTurnProb[r] ?? 0.006;
int barDurationMs(CreatureRarity r) => kBarDurationMs[r] ?? 6000;

/// Resteleben's effect on the wild's speed: reuses [catchDepth] (0 = just
/// crossed into the catchable band, 1 = HP approaching 0) — fought deeper
/// below the threshold moves up to 45% slower, down to a floor of 0.55×.
double barSpeedMul(CreatureRarity rarity, double hpFraction) =>
    1.0 - catchDepth(rarity, hpFraction) * 0.45;

/// Final wild speed for one Balkenjagd round (bar-fraction/second).
double barWildSpeed(CreatureRarity rarity, double hpFraction) =>
    barBaseSpeed(rarity) * barSpeedMul(rarity, hpFraction);

/// The catch bar's width as a fraction of the track, from the active
/// catcher's catchRate stat — a saturating curve (same shape as the old
/// ring's [qteWindow] width bonus): 16% at catchRate 0, approaching 38% at
/// very high catchRate, half the bonus already banked by catchRate 18.
const double kBarWidthBase = 0.16;
const double kBarWidthMaxBonus = 0.22;
const double kBarWidthHalfPoint = 18;

double barWidthFraction(int catchRate) {
  final rate = catchRate.clamp(0, 1 << 20).toDouble();
  return kBarWidthBase +
      kBarWidthMaxBonus * (rate / (rate + kBarWidthHalfPoint));
}

/// The SAME ceiling for every capture item (see [ItemKind.catchBoost]'s own
/// doc) — a perfect round adds at most this many percentage points on top of
/// whatever the thrown item started at. Only the best item (40% start) can
/// reach a true 100%; cheaper items cap below it even on a flawless run.
const double kBarSkillMax = 60.0;

/// Skill points earned per second of overlap for a round of [durationMs] —
/// scaled so holding overlap for the ENTIRE round earns exactly
/// [kBarSkillMax] points, never more.
double barSkillGainPerSecond(int durationMs) =>
    kBarSkillMax / (durationMs / 1000);

/// The live catch percentage: item start + accumulated skill points,
/// clamped 0–100. Monotonic by construction — callers only ever grow
/// [skillPoints], never shrink it.
double barCatchPercent(double itemStart, double skillPoints) =>
    (itemStart * 100 + skillPoints).clamp(0.0, 100.0);
