import 'dart:math' as math;

import 'creature_enums.dart';
import 'species_def.dart';

// One creature OWNED by a player — a row in the `creatures` table. Species
// data (per-stat mean curves, stages, abilities) lives in kSpeciesDefs; this
// holds the individual: level/XP, gender, the 28 independently-sampled genes
// (a base value AND a growth slope for each of the 14 stats — see rollGenes),
// evolution stage and the persistent HP pool (it survives between fights by
// design).
class CreatureInstance {
  final String id; // uuid (DB-generated on insert)
  final String userId;
  final String speciesId;
  String? nickname;
  final CreatureGender gender;

  int level;
  int xp;

  /// 0 = base form, 1/2 = evolutions (gated by the species' own evoLevel1/2
  /// Evolving bumps [statBase] additively — see
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

  /// Persistent HP pool. `currentHp` is clamped to maxHp on read so a level-up
  /// or evolution never leaves it out of range; 0 = K.O. until healed.
  /// (There is no energy pool any more — combat runs on Action Points.)
  int currentHp;

  /// When this creature's treatment finishes, or null when it isn't being
  /// healed. Healing takes real time proportional to the damage (see
  /// healing_cost.dart's healDuration) and a creature is UNAVAILABLE while it
  /// mends — that wait is what makes a knockout cost something beyond goods.
  ///
  /// Resolved lazily on read/load rather than by a timer, so a heal that
  /// finishes while the app is closed is simply done next launch — same rule
  /// as expeditions and breeding.
  DateTime? healingUntil;

  bool get isHealing =>
      healingUntil != null && healingUntil!.isAfter(DateTime.now());

  /// WHEN THIS MONSTER WAS PUT IN LINE for the Healing Hut, or null when it is
  /// not queued (migration 0029, user 2026-07-27: "treat all sollte nicht
  /// funktionieren, da ich aktuell keine Warteschlange habe").
  ///
  /// The hut treats only so many at once; anyone else waits here and is pulled
  /// in — oldest entry first — as a slot frees. Cleared the moment treatment
  /// starts, so [healingUntil] and this are never both set.
  DateTime? healQueuedAt;

  /// In line, but not yet under treatment.
  bool get isQueuedForHealing => healQueuedAt != null && !isHealing;

  /// Treatment time left, or zero when it isn't healing (or is done).
  Duration get healingRemaining {
    final until = healingUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

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
    this.healingUntil,
    this.healQueuedAt,
    this.assignedBuildingId,
    this.assignedStat,
    this.parentAId,
    this.parentBId,
  }) : currentHp = currentHp ?? -1;

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

  /// The battle back-view (player's own monster seen from behind). Falls back
  /// to the front view while no dedicated back art has been uploaded.
  String? get backImageUrl {
    final s = species?.stageAt(stage);
    return s?.backImageUrl ?? s?.imageUrl;
  }

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

  int get hp => currentHp < 0 ? maxHp : currentHp.clamp(0, maxHp);
  set hp(int v) => currentHp = v.clamp(0, maxHp);

  bool get isKo => hp <= 0;

  // ── XP / leveling ─────────────────────────────────────────
  /// Adds XP, consuming level-ups until the cap. Returns levels gained.
  ///
  /// [levelCap] is the ERA's ceiling (user 2026-07-22: era N caps every
  /// monster at N×10). XP past the cap is FORFEITED — the pool zeroes, so a
  /// capped monster banks nothing toward the next era.
  int gainXp(int amount, {int? levelCap}) {
    final cap = (levelCap ?? kCreatureMaxLevel).clamp(1, kCreatureMaxLevel);
    var gained = 0;
    xp += amount;
    while (level < cap && xp >= xpToNextLevel(level)) {
      xp -= xpToNextLevel(level);
      level++;
      gained++;
    }
    if (level >= cap) xp = 0;
    return gained;
  }

  // ── Evolution ─────────────────────────────────────────────
  bool get canEvolve {
    final s = species;
    if (s == null || stage >= 2) return false;
    return level >= s.evoLevelFrom(stage);
  }

  /// Whether a further evolution stage exists at all (stage 2 is final).
  ///
  /// This replaced `nextEvolutionCostBp`, which returned a BP price and used
  /// null to mean "final stage". Evolution costs nothing now — it's a reward
  /// for the levelling, claimed by hand — so only the question survives.
  bool get hasNextStage => species != null && stage < 2;

  // ── Gene sampling (IV replacement) ─────────────────────────
  // Every one of the 28 genes (a base value and a growth slope for each of the
  // 14 stats) is sampled INDEPENDENTLY from a Gaussian around the species' own
  // stage-1 mean,
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
  /// BETTER parent's value wins — a flat 60 % since 2026-07-27, passed in from
  /// [breedingFavoredChance]; it used to scale with the pair's `breeding` stat.
  /// Never re-sampled.
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
          if (stat.readJson(baseJson) != null)
            stat: stat.readJson(baseJson)!.toDouble(),
      },
      healingUntil: row['healing_until'] == null
          ? null
          : DateTime.tryParse(row['healing_until'] as String)?.toLocal(),
      healQueuedAt: row['heal_queued_at'] == null
          ? null
          : DateTime.tryParse(row['heal_queued_at'] as String)?.toLocal(),
      statSlope: {
        for (final stat in CreatureStat.values)
          if (stat.readJson(slopeJson) != null)
            stat: stat.readJson(slopeJson)!.toDouble(),
      },
      currentHp: (row['current_hp'] as num?)?.toInt() ?? -1,
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
    'healing_until': healingUntil?.toUtc().toIso8601String(),
    'heal_queued_at': healQueuedAt?.toUtc().toIso8601String(),
    'assigned_building_id': assignedBuildingId,
    'assigned_stat': assignedStat?.name,
    // NB: a creature's expedition lock is NOT stored here — it's derived at
    // load time from active rows in the `expeditions` table (member_ids) and
    // tracked in CreaturesController.expeditionIds, so `creatures` needs no
    // schema change. See [[expedition-overworld-redesign]].
    'parent_a': parentAId,
    'parent_b': parentBId,
  };
}
