import 'dart:math' as math;

import 'ability_def.dart';
import 'creature_enums.dart';
import 'creature_instance.dart';
import 'species_def.dart';
import 'status_effects.dart';

// One participant in a battle — wraps either a player's CreatureInstance
// (instanceId set, pools written back after the fight) or a generated wild/
// enemy creature. Stats are RESOLVED ints at construction time; the combat
// engine never touches species defs or the DB.
class Combatant {
  /// Unique within one battle (list index-based for enemies).
  final String id;

  /// Backing player creature — null for enemies. Used after the battle to
  /// write hp/energy/XP back to the collection.
  final String? instanceId;

  /// Identity data needed to CATCH this combatant (phase 5): a successful
  /// catch keeps the wild's species, evolution stage and gender. Null
  /// speciesId = not catchable (shouldn't happen in practice).
  final String? speciesId;
  final CreatureGender gender;
  final int stage;

  /// The wild's own sampled genes (base+slope per stat) — carried over
  /// verbatim into a new CreatureInstance on a successful catch, exactly
  /// like a player creature's genes. Null for player-side combatants (their
  /// genes already live on the backing CreatureInstance).
  final Map<CreatureStat, double>? wildStatBase;
  final Map<CreatureStat, double>? wildStatSlope;

  final String name;
  final String? imageUrl;
  final CreatureElement element;
  final CreatureRarity rarity;
  final bool isPlayerSide;
  final int level;

  /// True for a dungeon stage's boss (gets the +20% elite stat bump and the
  /// ×6 XP-on-kill multiplier — see CombatEngine.totalXpReward).
  final bool isBoss;

  final Map<CreatureStat, int> stats;

  /// Abilities usable at this evolution stage (species' stage-unlock filter
  /// already applied).
  final List<AbilityDef> abilities;

  int hp;
  int energy;

  // ── CTB scheduling ──────────────────────────────────────
  /// Absolute "time" of this combatant's next turn on the initiative queue.
  double nextTurnAt = 0;

  // ── Status effects (balance spec section 8) ─────────────
  /// At most one main status at a time (burn/frost/poison/fear).
  MainStatusKind? mainStatus;
  int mainStatusTurnsRemaining = 0;
  int mainStatusTurnsActive = 0; // for poison's escalating DoT

  /// Secondary debuffs stack independently of the main status.
  final Map<SecondaryDebuffKind, int> secondaryDebuffs = {};

  /// Self buffs coexist; reapplying refreshes duration rather than stacking.
  final Map<SelfBuffKind, int> selfBuffs = {};

  /// One-off self-inflicted cost of a move (Kraftakt/Gaia-Zorn) — always
  /// applies fully (no chance roll), single active instance.
  SelfPenaltyStat? selfPenaltyStat;
  double selfPenaltyMult = 1.0;
  int selfPenaltyTurnsRemaining = 0;

  Combatant({
    required this.id,
    this.instanceId,
    this.speciesId,
    this.gender = CreatureGender.male,
    this.stage = 0,
    this.wildStatBase,
    this.wildStatSlope,
    required this.name,
    this.imageUrl,
    required this.element,
    required this.rarity,
    required this.isPlayerSide,
    required this.level,
    this.isBoss = false,
    required this.stats,
    required this.abilities,
    int? hp,
    int? energy,
  }) : hp = hp ?? (stats[CreatureStat.hp] ?? 1),
       energy = energy ?? (stats[CreatureStat.energy] ?? 0);

  int stat(CreatureStat s) => stats[s] ?? 1;
  int get maxHp => stat(CreatureStat.hp);
  int get maxEnergy => stat(CreatureStat.energy);
  bool get alive => hp > 0;

  // ── Effective (modified) stats used by combat math ─────────
  double get effectiveAttack {
    var mult = 1.0;
    if (mainStatus != null) mult *= statusAttackMult(mainStatus!);
    if (selfBuffs.containsKey(SelfBuffKind.rage)) {
      mult *= selfBuffAttackMult(SelfBuffKind.rage);
    }
    if (selfPenaltyStat == SelfPenaltyStat.defense) {
      // penalty only affects defense — attack untouched here, kept for
      // clarity that penalties are stat-specific.
    }
    return stat(CreatureStat.attack) * mult;
  }

  double get effectiveDefense {
    var mult = 1.0;
    if (selfBuffs.containsKey(SelfBuffKind.armor)) {
      mult *= selfBuffDefenseMult(SelfBuffKind.armor);
    }
    if (selfPenaltyStat == SelfPenaltyStat.defense) mult *= selfPenaltyMult;
    return stat(CreatureStat.defense) * mult;
  }

  double get effectiveSpeed {
    var mult = 1.0;
    if (mainStatus != null) mult *= statusSpeedMult(mainStatus!);
    for (final d in secondaryDebuffs.keys) {
      mult *= secondarySpeedMult(d);
    }
    if (selfBuffs.containsKey(SelfBuffKind.haste)) {
      mult *= selfBuffSpeedMult(SelfBuffKind.haste);
    }
    if (selfPenaltyStat == SelfPenaltyStat.speed) mult *= selfPenaltyMult;
    return math.max(1.0, stat(CreatureStat.speed) * mult);
  }

  double get effectiveAccuracy {
    var mult = 1.0;
    for (final d in secondaryDebuffs.keys) {
      mult *= secondaryAccuracyMult(d);
    }
    return mult;
  }

  bool get hasted => selfBuffs.containsKey(SelfBuffKind.haste);
  bool get slowed =>
      secondaryDebuffs.containsKey(SecondaryDebuffKind.speedDown) ||
      mainStatus == MainStatusKind.frost;

  // ── Status application ─────────────────────────────────────
  /// Applies a main status if the target doesn't already have one (main
  /// statuses are mutually exclusive — a second inflict attempt while one
  /// is active simply fails, matching "kein Lock-Spam" from the spec).
  void applyMainStatus(MainStatusKind kind) {
    if (mainStatus != null) return;
    mainStatus = kind;
    mainStatusTurnsRemaining = mainStatusDuration(kind);
    mainStatusTurnsActive = 0;
  }

  /// Re-applying a secondary debuff just refreshes its duration (no stack).
  void applySecondaryDebuff(SecondaryDebuffKind kind) {
    secondaryDebuffs[kind] = kSecondaryDebuffDuration;
  }

  /// Re-applying a self buff just refreshes its duration (no stack).
  void applySelfBuff(SelfBuffKind kind) {
    selfBuffs[kind] = kSelfBuffDuration;
  }

  void applySelfPenalty(SelfPenalty penalty) {
    selfPenaltyStat = penalty.stat;
    selfPenaltyMult = penalty.mult;
    selfPenaltyTurnsRemaining = penalty.turns;
  }

  /// Rolled once per round at the start of this combatant's turn: main
  /// status (frost/fear) can skip the turn entirely.
  bool rollSkipTurn(math.Random rng) {
    if (mainStatus == null) return false;
    final chance = statusSkipChance(mainStatus!);
    return chance > 0 && rng.nextDouble() < chance;
  }

  /// End-of-round upkeep: DoT damage (returns the damage dealt, already
  /// applied to `hp`), then decrements every active duration and clears
  /// anything that's expired. Called once per round for every combatant,
  /// regardless of whose turn it was (statuses tick on a global round
  /// clock, not per-actor).
  int tickStatusEndOfRound() {
    var dot = 0;
    if (mainStatus != null) {
      final frac = statusDotFraction(mainStatus!, mainStatusTurnsActive);
      dot = (maxHp * frac).round();
      hp = math.max(0, hp - dot);
      mainStatusTurnsActive++;
      mainStatusTurnsRemaining--;
      if (mainStatusTurnsRemaining <= 0) {
        mainStatus = null;
        mainStatusTurnsActive = 0;
      }
    }
    _decrementAndPrune(secondaryDebuffs);
    _decrementAndPrune(selfBuffs);
    if (selfPenaltyTurnsRemaining > 0) {
      selfPenaltyTurnsRemaining--;
      if (selfPenaltyTurnsRemaining <= 0) {
        selfPenaltyStat = null;
        selfPenaltyMult = 1.0;
      }
    }
    return dot;
  }

  static void _decrementAndPrune<K>(Map<K, int> durations) {
    final expired = <K>[];
    for (final k in durations.keys) {
      durations[k] = durations[k]! - 1;
      if (durations[k]! <= 0) expired.add(k);
    }
    for (final k in expired) {
      durations.remove(k);
    }
  }

  /// Player-side combatant backed by a collection creature. Pools start at
  /// the instance's persistent values (HP/energy carry over between fights).
  factory Combatant.fromInstance(CreatureInstance c) {
    final species = c.species;
    return Combatant(
      id: 'p_${c.id}',
      instanceId: c.id,
      speciesId: c.speciesId,
      gender: c.gender,
      stage: c.stage,
      name: c.displayName,
      imageUrl: c.imageUrl,
      element: species?.element ?? CreatureElement.fire,
      rarity: species?.rarity ?? CreatureRarity.common,
      isPlayerSide: true,
      level: c.level,
      stats: {for (final s in CreatureStat.values) s: c.statValue(s)},
      abilities: _resolveAbilities(species, c.stage),
      hp: c.hp,
      energy: c.energy,
    );
  }

  /// Generated wild/enemy creature of [species] at [level]. Stage follows
  /// the species' OWN evolution levels (a wild past its evo-2 level appears
  /// in final form), genes are freshly rolled (kept on [wildStatBase]/
  /// [wildStatSlope] so a catch preserves this exact individual), pools
  /// start full.
  factory Combatant.fromSpecies(
    SpeciesDef species, {
    required int level,
    required String id,
    math.Random? rng,
    bool isBoss = false,
  }) {
    final random = rng ?? math.Random();
    final stage = level >= species.evoLevel2
        ? 2
        : level >= species.evoLevel1
        ? 1
        : 0;
    final base = CreatureInstance.rollBaseGenes(species, random);
    final slope = CreatureInstance.rollSlopeGenes(species, random);
    // Reuse the one canonical stat formula via a throwaway instance.
    final temp = CreatureInstance(
      id: '',
      userId: '',
      speciesId: species.id,
      gender: CreatureGender.male,
      level: level,
      stage: stage,
      statBase: base,
      statSlope: slope,
    );
    // Dungeon boss elite bonus: flat +20% on every base stat (decided
    // design) — applied only for display/combat stats, never persisted
    // (bosses aren't catchable as themselves except the final Legendary).
    final stats = {
      for (final s in CreatureStat.values)
        s: isBoss ? (temp.statValue(s) * 1.20).round() : temp.statValue(s),
    };
    return Combatant(
      id: id,
      speciesId: species.id,
      gender: random.nextBool() ? CreatureGender.male : CreatureGender.female,
      stage: stage,
      wildStatBase: base,
      wildStatSlope: slope,
      name: species.stageAt(stage).name,
      imageUrl: species.stageAt(stage).imageUrl,
      element: species.element,
      rarity: species.rarity,
      isPlayerSide: false,
      level: level,
      isBoss: isBoss,
      stats: stats,
      abilities: _resolveAbilities(species, stage),
    );
  }

  static List<AbilityDef> _resolveAbilities(SpeciesDef? species, int stage) {
    if (species == null) return const [];
    return [
      for (final sa in species.abilitiesAt(stage))
        if (kAbilityDefs[sa.abilityId] != null) kAbilityDefs[sa.abilityId]!,
    ];
  }
}
