import 'dart:math' as math;

import 'creature_enums.dart';
import 'species_def.dart';

// One creature OWNED by a player — a row in the `creatures` table. Species
// data (per-stat mean curves, stages, abilities) lives in kSpeciesDefs; this
// holds the individual: level/XP, gender, the 12 independently-sampled genes
// (6 stat bases + 6 growth slopes — see rollGenes), evolution stage and the
// persistent HP/energy pools (both survive between fights by design).
class CreatureInstance {
  final String id; // uuid (DB-generated on insert)
  final String userId;
  final String speciesId;
  String? nickname;
  final CreatureGender gender;

  int level;
  int xp;

  /// 0 = base form, 1/2 = evolutions (gated by the species' own evoLevel1/2
  /// + BP cost). Evolving bumps [statBase] additively — see
  /// CreaturesController.evolve.
  int stage;

  /// This individual's own sampled Ausgangswert (Level-1 base) per stat —
  /// mutated additively on evolution. THE thing that makes two creatures of
  /// the same species different, alongside [statSlope].
  final Map<CreatureStat, double> statBase;

  /// This individual's own sampled WertProLevel (growth) per stat — rolled
  /// once at catch/hatch time and never touched again (per the balance
  /// spec: evolution bumps the base/socket, never the slope).
  final Map<CreatureStat, double> statSlope;

  /// Persistent pools. `currentHp` is clamped to maxHp on read so a level-up
  /// or evolution never leaves it out of range; 0 = K.O. until healed.
  int currentHp;
  int currentEnergy;

  /// Work assignment (settlement economy). A creature works in AT MOST ONE
  /// workshop at a time: [assignedBuildingId] is the PlacedBuilding it's
  /// stationed in and [assignedStat] is which of that building's work roles
  /// it fills (a building can offer several — e.g. the Tribal Center offers
  /// both construction and research). Both null = idle. Being assigned does
  /// NOT block battle-team selection; a creature only stops producing while
  /// it's K.O., out of energy, or breeding (see CreaturesController).
  String? assignedBuildingId;
  CreatureStat? assignedStat;

  /// Breeding lineage (null for caught/starter creatures).
  final String? parentAId;
  final String? parentBId;

  CreatureInstance({
    required this.id,
    required this.userId,
    required this.speciesId,
    this.nickname,
    required this.gender,
    this.level = 1,
    this.xp = 0,
    this.stage = 0,
    required this.statBase,
    required this.statSlope,
    int? currentHp,
    int? currentEnergy,
    this.assignedBuildingId,
    this.assignedStat,
    this.parentAId,
    this.parentBId,
  }) : currentHp = currentHp ?? -1,
       currentEnergy = currentEnergy ?? -1;

  bool get isAssigned => assignedBuildingId != null && assignedStat != null;

  /// Whether any civilian gene is missing from the sampled maps — true for
  /// legacy rows saved before the 8 civilian stats existed. Such creatures
  /// are lazily backfilled from their species curve on load (see
  /// CreaturesController.load).
  bool get needsGeneBackfill =>
      CreatureStat.values.any((s) => !statBase.containsKey(s) || !statSlope.containsKey(s));

  SpeciesDef? get species => kSpeciesDefs[speciesId];

  /// Display name: nickname > current stage name > species name.
  String get displayName {
    if (nickname != null && nickname!.isNotEmpty) return nickname!;
    final s = species;
    if (s == null) return speciesId;
    final stageName = s.stageAt(stage).name;
    return stageName.isNotEmpty ? stageName : s.name;
  }

  String? get imageUrl => species?.stageAt(stage).imageUrl;

  // ── Stat formula (single source of truth) ─────────────────
  // Stat(Level) = Ausgangswert + WertProLevel·(Level-1) — linear, per the
  // balance spec. Kept unrounded until the very last step to avoid
  // compounding rounding error across 75 levels.
  int statValue(CreatureStat stat) {
    final base = statBase[stat] ?? 10;
    final slope = statSlope[stat] ?? 1;
    final raw = base + slope * (level - 1);
    return math.max(1, raw.round());
  }

  int get maxHp => statValue(CreatureStat.hp);
  int get maxEnergy => statValue(CreatureStat.energy);

  int get hp => currentHp < 0 ? maxHp : currentHp.clamp(0, maxHp);
  set hp(int v) => currentHp = v.clamp(0, maxHp);

  int get energy =>
      currentEnergy < 0 ? maxEnergy : currentEnergy.clamp(0, maxEnergy);
  set energy(int v) => currentEnergy = v.clamp(0, maxEnergy);

  bool get isKo => hp <= 0;

  // ── XP / leveling ─────────────────────────────────────────
  /// Adds XP, consuming level-ups until the cap. Returns levels gained.
  int gainXp(int amount) {
    var gained = 0;
    xp += amount;
    while (level < kCreatureMaxLevel && xp >= xpToNextLevel(level)) {
      xp -= xpToNextLevel(level);
      level++;
      gained++;
    }
    if (level >= kCreatureMaxLevel) xp = 0;
    return gained;
  }

  // ── Evolution ─────────────────────────────────────────────
  bool get canEvolve {
    final s = species;
    if (s == null || stage >= 2) return false;
    return level >= s.evoLevelFrom(stage);
  }

  /// BP price for the NEXT evolution (null if already final stage).
  int? get nextEvolutionCostBp {
    final s = species;
    if (s == null || stage >= 2) return null;
    return evolutionCostBp(s.rarity, stage + 1);
  }

  // ── Gene sampling (IV replacement) ─────────────────────────
  // Every one of the 12 genes (6 stat bases + 6 growth slopes) is sampled
  // INDEPENDENTLY from a Gaussian around the species' own stage-1 mean,
  // clamped to ±2σ (base σ=8% of mean, slope σ=6% — see creature_enums.dart)
  // so no roll is ever a wild outlier. Best-vs-worst individual of the same
  // species lands ~26% apart at max level, per the balance spec.
  static Map<CreatureStat, double> rollBaseGenes(
    SpeciesDef species,
    math.Random rng,
  ) => {
    for (final stat in CreatureStat.values)
      stat: _sample(species.statCurve(stat).baseAt(0), kBaseSigmaPct, rng),
  };

  static Map<CreatureStat, double> rollSlopeGenes(
    SpeciesDef species,
    math.Random rng,
  ) => {
    for (final stat in CreatureStat.values)
      stat: _sample(species.statCurve(stat).growth, kSlopeSigmaPct, rng),
  };

  /// One-time legacy migration: fills any gene missing from [statBase]/
  /// [statSlope] (i.e. the civilian stats on a pre-migration row) with a
  /// fresh Gaussian sample from the species curve, in place. Returns true if
  /// anything was added (so the caller can persist). No-op once complete.
  bool backfillGenes(math.Random rng) {
    final s = species;
    if (s == null) return false;
    var changed = false;
    for (final stat in CreatureStat.values) {
      if (!statBase.containsKey(stat)) {
        statBase[stat] = _sample(s.statCurve(stat).baseAt(0), kBaseSigmaPct, rng);
        changed = true;
      }
      if (!statSlope.containsKey(stat)) {
        statSlope[stat] =
            _sample(s.statCurve(stat).growth, kSlopeSigmaPct, rng);
        changed = true;
      }
    }
    return changed;
  }

  static double _sample(double mu, double sigmaPct, math.Random rng) {
    final sigma = mu * sigmaPct;
    if (sigma <= 0) return mu;
    final raw = mu + _gaussian(rng) * sigma;
    return raw.clamp(
      mu - kSigmaClampFactor * sigma,
      mu + kSigmaClampFactor * sigma,
    );
  }

  /// Standard normal sample via Box-Muller (dart:math has no built-in
  /// Gaussian generator).
  static double _gaussian(math.Random rng) {
    final u1 = 1.0 - rng.nextDouble(); // (0,1] avoids log(0)
    final u2 = rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2);
  }

  // ── Breeding (ARK-style favored-gene inheritance) ───────────
  /// Each gene is inherited INDEPENDENTLY from the parents' CURRENT values
  /// (including any evolution bonus they've earned — an intentional incentive
  /// to evolve breeding stock first). [favoredChance] is the probability the
  /// BETTER parent's value wins; it's no longer a fixed 0.70 but scales with
  /// the pair's `breeding` civilian stat (0.50 = coin-flip at breeding 0, up
  /// toward 1.0 — see breedingFavoredChance). Never re-sampled.
  static Map<CreatureStat, double> inheritGenes(
    Map<CreatureStat, double> a,
    Map<CreatureStat, double> b,
    math.Random rng, {
    double favoredChance = 0.70,
  }) => {
    for (final s in CreatureStat.values)
      s: rng.nextDouble() < favoredChance
          ? math.max(a[s] ?? 0, b[s] ?? 0)
          : math.min(a[s] ?? 0, b[s] ?? 0),
  };

  // ── Row mapping ───────────────────────────────────────────
  factory CreatureInstance.fromRow(Map<String, dynamic> row) {
    final baseJson = (row['stat_base'] as Map?) ?? const {};
    final slopeJson = (row['stat_slope'] as Map?) ?? const {};
    return CreatureInstance(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      speciesId: row['species_id'] as String,
      nickname: row['nickname'] as String?,
      gender: CreatureGender.fromName(row['gender'] as String?),
      level: (row['level'] as num?)?.toInt() ?? 1,
      xp: (row['xp'] as num?)?.toInt() ?? 0,
      stage: (row['stage'] as num?)?.toInt() ?? 0,
      // Only the genes actually present in the jsonb are loaded — a legacy row
      // (saved before the civilian stats existed) yields a partial map that
      // CreaturesController.load backfills from the species curve. statValue
      // falls back to 10/1 for any still-missing stat in the meantime.
      statBase: {
        for (final stat in CreatureStat.values)
          if (baseJson[stat.name] != null)
            stat: (baseJson[stat.name] as num).toDouble(),
      },
      statSlope: {
        for (final stat in CreatureStat.values)
          if (slopeJson[stat.name] != null)
            stat: (slopeJson[stat.name] as num).toDouble(),
      },
      currentHp: (row['current_hp'] as num?)?.toInt() ?? -1,
      currentEnergy: (row['current_energy'] as num?)?.toInt() ?? -1,
      assignedBuildingId: row['assigned_building_id'] as String?,
      assignedStat: row['assigned_stat'] == null
          ? null
          : CreatureStat.fromName(row['assigned_stat'] as String?),
      parentAId: row['parent_a'] as String?,
      parentBId: row['parent_b'] as String?,
    );
  }

  /// Row for updates/inserts. `id` is omitted when empty so the DB generates
  /// the uuid on first insert.
  Map<String, dynamic> toRow() => {
    if (id.isNotEmpty) 'id': id,
    'user_id': userId,
    'species_id': speciesId,
    'nickname': nickname,
    'gender': gender.name,
    'level': level,
    'xp': xp,
    'stage': stage,
    'stat_base': {for (final e in statBase.entries) e.key.name: e.value},
    'stat_slope': {for (final e in statSlope.entries) e.key.name: e.value},
    'current_hp': currentHp,
    'current_energy': currentEnergy,
    'assigned_building_id': assignedBuildingId,
    'assigned_stat': assignedStat?.name,
    'parent_a': parentAId,
    'parent_b': parentBId,
  };
}
