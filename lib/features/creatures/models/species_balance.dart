import 'creature_enums.dart';

// NB: distinct from services/species_balance.dart (the combat-simulation
// balance tool). This is the per-rarity BUDGET config.

/// Everything the stat-budget system reads for ONE rarity (user 2026-07-24):
/// the point budgets (combat/civil, base + growth) and the per-attribute LIMITS
/// (one for every combat attribute, one for every civil attribute — base and
/// growth each), plus the rarity's catch rate. A limit of 0 means "no cap".
class RarityConfig {
  final double combatBase;
  final double workBase;
  final double combatGrowth;
  final double workGrowth;
  final double combatMaxBase;
  final double workMaxBase;
  final double combatMaxGrowth;
  final double workMaxGrowth;
  final double catchRate;

  /// Base MATING time in HOURS for this rarity (user 2026-07-24): rarer =
  /// longer. The Breeding Hut breeders' `breeding` stat cuts it down (see
  /// breedingHours). Legendary is never bred, so its value is unused.
  final double breedHours;

  /// Base HATCHING time in HOURS — the second, separate clock the egg runs in
  /// the Hatchery (user 2026-07-26). It used to reuse [breedHours], which made
  /// the two phases impossible to tune apart. Same soft-cap cut, but driven by
  /// the breeders stationed in the HATCHERY.
  final double hatchHours;

  /// HEALING, per point of missing HP: seconds of treatment and goods billed
  /// (user 2026-07-26 — "die Seltenheitsstufen haben unterschiedliche
  /// Heildauern"). Both were single global constants; a rare monster costing
  /// exactly what a common one does made rarity a stat difference only.
  ///
  /// The K.O. factor multiplies BOTH and stays global (HealConfig), and the
  /// building's heal effects/medic post cut them further.
  final double healSecondsPerHp;
  final double healGoodsPerHp;

  /// What ONE MATING costs in supplies (user 2026-07-27: "Breeding soll
  /// luxuswaren kosten von der ära, aus welcher die Monster stammen"). Billed
  /// once for the pair, in the goods of the PARENTS' era — see breeding_cost.
  ///
  /// Breeding was the one creature sink that was completely free: it cost time
  /// and nothing else, so a hut with slots to spare had no reason not to run.
  /// Rarer = dearer, on the same shape as the mating clock.
  final double breedGoods;

  /// How often a monster of this rarity appears on capture expeditions (user
  /// 2026-07-25). [encounterWeightBase] is the weight at danger level 1, and
  /// [encounterWeightPerDanger] shifts it by that much per danger level above 1
  /// (so danger D uses base + perDanger·(D−1)). Weights are relative within the
  /// area's pool. See rarityWeights in capture_math.dart.
  final double encounterWeightBase;
  final double encounterWeightPerDanger;

  /// Catch DIFFICULTY: how many times the shrinking ring must land in the golden
  /// zone (perfect hits in a row) to catch this rarity — miss once and it
  /// escapes (user 2026-07-25). See qteHitsRequired in capture_math.dart.
  final int catchHits;

  const RarityConfig({
    required this.combatBase,
    required this.workBase,
    required this.combatGrowth,
    required this.workGrowth,
    this.combatMaxBase = 0,
    this.workMaxBase = 0,
    this.combatMaxGrowth = 0,
    this.workMaxGrowth = 0,
    required this.catchRate,
    this.breedHours = 8,
    this.hatchHours = 8,
    this.healSecondsPerHp = 25,
    this.healGoodsPerHp = 0.1,
    this.breedGoods = 10,
    this.encounterWeightBase = 20,
    this.encounterWeightPerDanger = 0,
    this.catchHits = 1,
  });

  /// The per-attribute BASE cap for [stat]'s category, or null when uncapped.
  double? maxBaseFor(CreatureStat stat) {
    final v = stat.isCombat ? combatMaxBase : workMaxBase;
    return v > 0 ? v : null;
  }

  /// The per-attribute GROWTH cap for [stat]'s category, or null when uncapped.
  double? maxGrowthFor(CreatureStat stat) {
    final v = stat.isCombat ? combatMaxGrowth : workMaxGrowth;
    return v > 0 ? v : null;
  }

  RarityConfig copyWith({
    double? combatBase,
    double? workBase,
    double? combatGrowth,
    double? workGrowth,
    double? combatMaxBase,
    double? workMaxBase,
    double? combatMaxGrowth,
    double? workMaxGrowth,
    double? catchRate,
    double? breedHours,
    double? hatchHours,
    double? healSecondsPerHp,
    double? healGoodsPerHp,
    double? breedGoods,
    double? encounterWeightBase,
    double? encounterWeightPerDanger,
    int? catchHits,
  }) => RarityConfig(
    combatBase: combatBase ?? this.combatBase,
    workBase: workBase ?? this.workBase,
    combatGrowth: combatGrowth ?? this.combatGrowth,
    workGrowth: workGrowth ?? this.workGrowth,
    combatMaxBase: combatMaxBase ?? this.combatMaxBase,
    workMaxBase: workMaxBase ?? this.workMaxBase,
    combatMaxGrowth: combatMaxGrowth ?? this.combatMaxGrowth,
    workMaxGrowth: workMaxGrowth ?? this.workMaxGrowth,
    catchRate: catchRate ?? this.catchRate,
    breedHours: breedHours ?? this.breedHours,
    hatchHours: hatchHours ?? this.hatchHours,
    healSecondsPerHp: healSecondsPerHp ?? this.healSecondsPerHp,
    healGoodsPerHp: healGoodsPerHp ?? this.healGoodsPerHp,
    breedGoods: breedGoods ?? this.breedGoods,
    encounterWeightBase: encounterWeightBase ?? this.encounterWeightBase,
    encounterWeightPerDanger:
        encounterWeightPerDanger ?? this.encounterWeightPerDanger,
    catchHits: catchHits ?? this.catchHits,
  );

  Map<String, dynamic> toJson() => {
    'combatBase': combatBase,
    'workBase': workBase,
    'combatGrowth': combatGrowth,
    'workGrowth': workGrowth,
    'combatMaxBase': combatMaxBase,
    'workMaxBase': workMaxBase,
    'combatMaxGrowth': combatMaxGrowth,
    'workMaxGrowth': workMaxGrowth,
    'catchRate': catchRate,
    'breedHours': breedHours,
    'hatchHours': hatchHours,
    'healSecondsPerHp': healSecondsPerHp,
    'healGoodsPerHp': healGoodsPerHp,
    'breedGoods': breedGoods,
    'encounterWeightBase': encounterWeightBase,
    'encounterWeightPerDanger': encounterWeightPerDanger,
    'catchHits': catchHits,
  };

  factory RarityConfig.fromJson(Map<String, dynamic> j, RarityConfig fallback) {
    double d(String k, double f) => (j[k] as num?)?.toDouble() ?? f;
    return RarityConfig(
      combatBase: d('combatBase', fallback.combatBase),
      workBase: d('workBase', fallback.workBase),
      combatGrowth: d('combatGrowth', fallback.combatGrowth),
      workGrowth: d('workGrowth', fallback.workGrowth),
      combatMaxBase: d('combatMaxBase', fallback.combatMaxBase),
      workMaxBase: d('workMaxBase', fallback.workMaxBase),
      combatMaxGrowth: d('combatMaxGrowth', fallback.combatMaxGrowth),
      workMaxGrowth: d('workMaxGrowth', fallback.workMaxGrowth),
      catchRate: d('catchRate', fallback.catchRate),
      breedHours: d('breedHours', fallback.breedHours),
      // A config saved before hatching had its own clock falls back to that
      // row's OWN breedHours — which is exactly what the Hatchery used then, so
      // an existing save keeps its balance instead of jumping to the code
      // default.
      hatchHours: d('hatchHours', d('breedHours', fallback.hatchHours)),
      healSecondsPerHp: d('healSecondsPerHp', fallback.healSecondsPerHp),
      healGoodsPerHp: d('healGoodsPerHp', fallback.healGoodsPerHp),
      breedGoods: d('breedGoods', fallback.breedGoods),
      encounterWeightBase:
          d('encounterWeightBase', fallback.encounterWeightBase),
      encounterWeightPerDanger:
          d('encounterWeightPerDanger', fallback.encounterWeightPerDanger),
      catchHits: (j['catchHits'] as num?)?.toInt() ?? fallback.catchHits,
    );
  }
}

/// Global species-balance tuning (dev-authorable), one [RarityConfig] per
/// rarity. Seeded from the historical code defaults, overridable in the
/// Species-dev config screen, persisted in `game_config` under 'species_balance'.
class SpeciesBalance {
  final Map<CreatureRarity, RarityConfig> byRarity;
  const SpeciesBalance({required this.byRarity});

  RarityConfig of(CreatureRarity r) =>
      byRarity[r] ?? defaultSpeciesBalance().byRarity[r]!;

  double baseTotal(CreatureRarity r) => of(r).combatBase + of(r).workBase;
  double growthTotal(CreatureRarity r) => of(r).combatGrowth + of(r).workGrowth;

  /// [value] clamped to [stat]'s per-category BASE cap for [rarity] (no-op when
  /// unset).
  double clampBase(CreatureStat stat, CreatureRarity rarity, double value) {
    final cap = of(rarity).maxBaseFor(stat);
    return (cap != null && value > cap) ? cap : value;
  }

  /// [value] clamped to [stat]'s per-category GROWTH cap for [rarity].
  double clampGrowth(CreatureStat stat, CreatureRarity rarity, double value) {
    final cap = of(rarity).maxGrowthFor(stat);
    return (cap != null && value > cap) ? cap : value;
  }

  SpeciesBalance copyWith(Map<CreatureRarity, RarityConfig> updates) =>
      SpeciesBalance(byRarity: {...byRarity, ...updates});

  Map<String, dynamic> toJson() => {
    for (final e in byRarity.entries) e.key.name: e.value.toJson(),
  };

  factory SpeciesBalance.fromJson(Map<String, dynamic> j) {
    final def = defaultSpeciesBalance();
    return SpeciesBalance(
      byRarity: {
        for (final r in CreatureRarity.values)
          r: j[r.name] is Map
              ? RarityConfig.fromJson(
                  Map<String, dynamic>.from(j[r.name] as Map),
                  def.byRarity[r]!,
                )
              : def.byRarity[r]!,
      },
    );
  }
}

/// The historical code defaults: total base per rarity (270→290, +5/step),
/// split combat:work = 180:190, growth = base ÷ 30, no attribute caps, catch
/// rate by rarity (1.2 → 0.6). See docs/balancing.md §3.
SpeciesBalance defaultSpeciesBalance() {
  const combatShare = 180 / 370;
  const totals = {
    CreatureRarity.common: 270.0,
    CreatureRarity.uncommon: 275.0,
    CreatureRarity.rare: 280.0,
    CreatureRarity.epic: 285.0,
    CreatureRarity.legendary: 290.0,
  };
  const catch_ = {
    CreatureRarity.common: 1.2,
    CreatureRarity.uncommon: 1.05,
    CreatureRarity.rare: 0.9,
    CreatureRarity.epic: 0.75,
    CreatureRarity.legendary: 0.6,
  };
  // Mating time by rarity — rarer = longer (user 2026-07-24). Legendary is
  // never bred; its value is decorative.
  //
  // Taken over from the author's live config on 2026-07-29 (the 📋 export): a
  // clean doubling ladder, four times the old numbers, so a common pair is
  // most of a waking day and an epic pair is a multi-day commitment. Legendary
  // stays at the old 24 — nothing reads it.
  const breed = {
    CreatureRarity.common: 16.0,
    CreatureRarity.uncommon: 32.0,
    CreatureRarity.rare: 64.0,
    CreatureRarity.epic: 128.0,
    CreatureRarity.legendary: 24.0,
  };
  // Hatching time by rarity — its own clock since 2026-07-26. Seeded equal to
  // [breed] so the out-of-the-box pacing is what it always was (the Hatchery
  // used the mating figure); tune the two apart in Dev Mode.
  const hatch = breed;
  // Encounter weight = base@danger1 + slope·(danger−1). These reproduce the old
  // hardcoded rarityWeights curve exactly (common 60→20, rare 10→30, epic
  // 4→18, legendary 1→7 across danger 1..5; uncommon flat 25).
  const weightBase = {
    CreatureRarity.common: 60.0,
    CreatureRarity.uncommon: 25.0,
    CreatureRarity.rare: 10.0,
    CreatureRarity.epic: 4.0,
    CreatureRarity.legendary: 1.0,
  };
  const weightSlope = {
    CreatureRarity.common: -10.0,
    CreatureRarity.uncommon: 0.0,
    CreatureRarity.rare: 5.0,
    CreatureRarity.epic: 3.5,
    CreatureRarity.legendary: 1.5,
  };
  // Healing by rarity (user 2026-07-26): rarer = longer on the table. Seeded
  // from the old flat 25 s/HP at COMMON and rising from there, so the early
  // game is unchanged and a legendary's recovery is an event: at ~60 HP, a
  // −55 % trial is ~14 min for a common and ~41 min for a legendary; a K.O.
  // (×2) is ~50 min vs. ~2.5 h.
  const healSeconds = {
    CreatureRarity.common: 25.0,
    CreatureRarity.uncommon: 30.0,
    CreatureRarity.rare: 40.0,
    CreatureRarity.epic: 55.0,
    CreatureRarity.legendary: 75.0,
  };
  // The PRICE rises with rarity too, taken over from the author's live config
  // on 2026-07-29. It used to be a flat 0.1/HP everywhere — durations differed
  // by rarity and bills did not, so a legendary was slow to heal but no dearer.
  const healGoods = {
    CreatureRarity.common: 0.2,
    CreatureRarity.uncommon: 0.25,
    CreatureRarity.rare: 0.3,
    CreatureRarity.epic: 0.35,
    CreatureRarity.legendary: 0.4,
  };
  // What one MATING costs in supplies (user 2026-07-27). Anchored on healing:
  // a common's full recovery from K.O. is ~10 goods, so a common mating costs
  // about one of those, and an epic pair about six — dear enough that a hut
  // full of slots is a choice, cheap enough that the first pair is affordable
  // from a single gathering trip. Legendary is decorative (never bred).
  const breedGoods = {
    CreatureRarity.common: 10.0,
    CreatureRarity.uncommon: 18.0,
    CreatureRarity.rare: 30.0,
    CreatureRarity.epic: 60.0,
    CreatureRarity.legendary: 90.0,
  };
  // PER-ATTRIBUTE CEILINGS, taken over from the author's live config on
  // 2026-07-29. They were all 0 ("no cap") in code, which meant the budget
  // could legally be poured into one attribute — a species with everything in
  // Attack and nothing else was within budget and unbeatable in its band.
  // A cap per attribute is what makes the budget a SHAPE and not just a sum.
  const combatMaxBase = {
    CreatureRarity.common: 60.0,
    CreatureRarity.uncommon: 63.0,
    CreatureRarity.rare: 65.0,
    CreatureRarity.epic: 68.0,
    CreatureRarity.legendary: 70.0,
  };
  const workMaxBase = {
    CreatureRarity.common: 60.0,
    CreatureRarity.uncommon: 62.0,
    CreatureRarity.rare: 65.0,
    CreatureRarity.epic: 67.0,
    CreatureRarity.legendary: 70.0,
  };
  const combatMaxGrowth = {
    CreatureRarity.common: 2.0,
    CreatureRarity.uncommon: 2.1,
    CreatureRarity.rare: 2.1,
    CreatureRarity.epic: 2.2,
    CreatureRarity.legendary: 2.3,
  };
  const workMaxGrowth = {
    CreatureRarity.common: 1.6,
    CreatureRarity.uncommon: 1.7,
    CreatureRarity.rare: 1.8,
    CreatureRarity.epic: 1.9,
    CreatureRarity.legendary: 2.0,
  };
  // Ring-hits required to catch — reproduces the old qteHitsRequired (1/1/2/3/4).
  const hits = {
    CreatureRarity.common: 1,
    CreatureRarity.uncommon: 1,
    CreatureRarity.rare: 2,
    CreatureRarity.epic: 3,
    CreatureRarity.legendary: 4,
  };
  return SpeciesBalance(
    byRarity: {
      for (final e in totals.entries)
        e.key: RarityConfig(
          combatBase: e.value * combatShare,
          workBase: e.value * (1 - combatShare),
          combatGrowth: e.value * combatShare / 30,
          workGrowth: e.value * (1 - combatShare) / 30,
          combatMaxBase: combatMaxBase[e.key]!,
          workMaxBase: workMaxBase[e.key]!,
          combatMaxGrowth: combatMaxGrowth[e.key]!,
          workMaxGrowth: workMaxGrowth[e.key]!,
          catchRate: catch_[e.key]!,
          breedHours: breed[e.key]!,
          hatchHours: hatch[e.key]!,
          healSecondsPerHp: healSeconds[e.key]!,
          healGoodsPerHp: healGoods[e.key]!,
          breedGoods: breedGoods[e.key]!,
          encounterWeightBase: weightBase[e.key]!,
          encounterWeightPerDanger: weightSlope[e.key]!,
          catchHits: hits[e.key]!,
        ),
    },
  );
}

/// Whether a creature of [rarity] can be bred at all — legendaries never can
/// (user 2026-07-22 / 2026-07-24), each is a one-of-a-kind trophy.
bool rarityCanBreed(CreatureRarity rarity) =>
    rarity != CreatureRarity.legendary;

/// The LIVE config every reader consults. Replaced in place on load
/// (CreatureDefsController) / on save (the config screen).
SpeciesBalance kSpeciesBalance = defaultSpeciesBalance();
