import 'dart:math' as math;

import 'ability_def.dart';
import 'creature_enums.dart';
import 'creature_instance.dart';
import 'species_def.dart';
import 'status_effects.dart';
import '../../../core/tuning/game_tuning.dart';

/// Combat-stat multiplier for generated NON-BOSS wilds (docs/balancing.md
/// §4a): wilds fight slightly below player quality so a same-level dungeon
/// pack is winnable without being trivial — action economy stopped deciding
/// everything once fights got short. Applies to battle STATS only; a caught
/// wild keeps its full-quality genes.
double get kWildStatMult => GameTuning.i.raw(Dials.wildStatMult);

// One participant in a battle — wraps either a player's CreatureInstance
// (instanceId set, pools written back after the fight) or a generated wild/
// enemy creature. Stats are RESOLVED ints at construction time; the combat
// engine never touches species defs or the DB.
class Combatant {
  /// Unique within one battle (list index-based for enemies).
  final String id;

  /// Backing player creature — null for enemies. Used after the battle to
  /// write hp/XP back to the collection.
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

  /// Battle back-view for the player's own monster (seen from behind). Null for
  /// enemies — they're always shown from the front.
  final String? backImageUrl;
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

  /// Tutorial hook: damage can bring this combatant to 1 HP but never to 0
  /// (see CombatEngine's damage clamps). Set on the wild in the guided
  /// intro's catch fight — its script promises the catch cannot be lost, so
  /// overkill (which normally forfeits the find) must be impossible, not
  /// merely unlikely. Runtime-only; never persisted.
  bool cannotBeKoed = false;

  // ── CTB scheduling ──────────────────────────────────────
  /// Absolute "time" of this combatant's next turn on the initiative queue.
  double nextTurnAt = 0;

  /// Action points this monster is CARRYING (user redesign 2026-07-20). It is
  /// per-combatant, not per-turn: unspent points stay, and only
  /// [apRegenForStage] are added at the start of each of its own turns, capped
  /// at [maxActionPointsForStage]. The engine seeds it at battle start
  /// (kStartApFirst / kStartApSecond). Runtime-only; never persisted.
  int ap = 0;

  // ── Status effects (balance spec section 8) ─────────────
  // Every active effect carries the DURATION AND MAGNITUDE it was applied with
  // (user 2026-07-30), not just its kind: the numbers belong to the move that
  // inflicted it, so two burns from two different abilities really burn
  // differently. The catalog in status_effects.dart is the default those numbers
  // fall back to, not the answer.
  /// At most one main status at a time (burn/frost/poison/fear/sleep).
  MainStatusKind? mainStatus;
  int mainStatusTurnsRemaining = 0;
  int mainStatusTurnsActive = 0; // for poison's escalating DoT

  /// The magnitude THIS instance was inflicted with, as the positive fraction
  /// [AbilityEffect.resolvedValue] hands over: damage per turn for burn/poison,
  /// speed lost for frost, chance to lose the turn for fear.
  double mainStatusValue = 0;

  /// Secondary debuffs stack independently of the main status — turns left and
  /// the magnitude each was applied with.
  final Map<SecondaryDebuffKind, ActiveEffect> secondaryDebuffs = {};

  /// Self buffs coexist; reapplying refreshes duration rather than stacking.
  final Map<SelfBuffKind, ActiveEffect> selfBuffs = {};

  /// REGENERATION on this combatant (user 2026-07-30): heals [regenValue] of max
  /// HP at the end of each of its own turns while [regenTurnsRemaining] lasts.
  /// The mirror image of a DoT, and it ticks in the same place.
  double regenValue = 0;
  int regenTurnsRemaining = 0;

  /// HP the last [tickStatusEndOfRound] restored through regen — read by the
  /// engine for its log line, the way the returned DoT is. Kept as a field
  /// because that return value is the DAMAGE channel and every caller treats a
  /// positive number as a hit taken.
  int lastRegenHeal = 0;

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
    this.backImageUrl,
    required this.element,
    required this.rarity,
    required this.isPlayerSide,
    required this.level,
    this.isBoss = false,
    required this.stats,
    required this.abilities,
    int? hp,
  }) : hp = hp ?? (stats[CreatureStat.hp] ?? 1);

  int stat(CreatureStat s) => stats[s] ?? 1;
  int get maxHp => stat(CreatureStat.hp);
  bool get alive => hp > 0;

  // ── Effective (modified) stats used by combat math ─────────
  double get effectiveAttack {
    var mult = 1.0;
    // Burn's attack sap is NOT authorable per move — it is what burn is, and the
    // move's own number is the damage per turn (see AbilityEffectKind.burn).
    if (mainStatus != null) mult *= statusAttackMult(mainStatus!);
    final rage = selfBuffs[SelfBuffKind.rage];
    if (rage != null) mult *= 1 + rage.value;
    // Growl (user 2026-07-30): stacks with burn's sap — two different sources.
    final weakened = secondaryDebuffs[SecondaryDebuffKind.attackDown];
    if (weakened != null) mult *= 1 - weakened.value;
    if (selfPenaltyStat == SelfPenaltyStat.defense) {
      // penalty only affects defense — attack untouched here, kept for
      // clarity that penalties are stat-specific.
    }
    return stat(CreatureStat.attack) * mult;
  }

  double get effectiveDefense {
    var mult = 1.0;
    // The buff's OWN magnitude (user 2026-07-30): a +30 % Armor and a +50 % one
    // are two different moves now, so the figure comes off the instance.
    final armor = selfBuffs[SelfBuffKind.armor];
    if (armor != null) mult *= 1 + armor.value;
    // Screech (user 2026-07-30): the support move that multiplies what the whole
    // party does to this target.
    final exposed = secondaryDebuffs[SecondaryDebuffKind.defenseDown];
    if (exposed != null) mult *= 1 - exposed.value;
    if (selfPenaltyStat == SelfPenaltyStat.defense) mult *= selfPenaltyMult;
    return stat(CreatureStat.defense) * mult;
  }

  double get effectiveSpeed {
    var mult = 1.0;
    // Frost's slow is the status' authored magnitude; every other main status
    // leaves speed alone.
    if (mainStatus == MainStatusKind.frost) mult *= 1 - mainStatusValue;
    final slow = secondaryDebuffs[SecondaryDebuffKind.speedDown];
    if (slow != null) mult *= 1 - slow.value;
    final haste = selfBuffs[SelfBuffKind.haste];
    if (haste != null) mult *= 1 + haste.value;
    if (selfPenaltyStat == SelfPenaltyStat.speed) mult *= selfPenaltyMult;
    return math.max(1.0, stat(CreatureStat.speed) * mult);
  }

  double get effectiveAccuracy {
    final blind = secondaryDebuffs[SecondaryDebuffKind.blind];
    return blind == null ? 1.0 : 1 - blind.value;
  }

  bool get hasted => selfBuffs.containsKey(SelfBuffKind.haste);
  bool get slowed =>
      secondaryDebuffs.containsKey(SecondaryDebuffKind.speedDown) ||
      mainStatus == MainStatusKind.frost;

  // ── Status application ─────────────────────────────────────
  /// Applies a main status if the target doesn't already have one (main
  /// statuses are mutually exclusive — a second inflict attempt while one
  /// is active simply fails, matching "kein Lock-Spam" from the spec).
  /// [turns] and [value] come from the ability that inflicted it (user
  /// 2026-07-30); both fall back to the catalog when 0, which is what a move
  /// authored before per-move numbers existed passes.
  void applyMainStatus(MainStatusKind kind, {int turns = 0, double value = 0}) {
    if (mainStatus != null) return;
    mainStatus = kind;
    mainStatusTurnsRemaining = turns > 0 ? turns : mainStatusDuration(kind);
    mainStatusValue = value > 0 ? value : _catalogMainValue(kind);
    mainStatusTurnsActive = 0;
  }

  /// The catalog magnitude for [kind], in the same "positive fraction" unit the
  /// authored value uses — the single place the two agree.
  static double _catalogMainValue(MainStatusKind kind) => switch (kind) {
    MainStatusKind.burn ||
    MainStatusKind.poison =>
      statusDotFraction(kind, 0),
    MainStatusKind.frost => 1 - statusSpeedMult(kind),
    MainStatusKind.fear || MainStatusKind.sleep => statusSkipChance(kind),
  };

  /// Re-applying a secondary debuff just refreshes its duration (no stack) —
  /// with the NEW move's magnitude, since that is the one that just landed.
  void applySecondaryDebuff(
    SecondaryDebuffKind kind, {
    int turns = 0,
    double value = 0,
  }) {
    secondaryDebuffs[kind] = ActiveEffect(
      turnsRemaining: turns > 0 ? turns : kSecondaryDebuffDuration,
      value: value > 0
          ? value
          : 1 -
                switch (kind) {
                  SecondaryDebuffKind.blind => secondaryAccuracyMult(kind),
                  SecondaryDebuffKind.speedDown => secondarySpeedMult(kind),
                  SecondaryDebuffKind.attackDown => secondaryAttackMult(kind),
                  SecondaryDebuffKind.defenseDown => secondaryDefenseMult(kind),
                },
    );
  }

  /// Re-applying a self buff just refreshes its duration (no stack).
  void applySelfBuff(SelfBuffKind kind, {int turns = 0, double value = 0}) {
    selfBuffs[kind] = ActiveEffect(
      turnsRemaining: turns > 0 ? turns : kSelfBuffDuration,
      value: value > 0
          ? value
          : switch (kind) {
              SelfBuffKind.armor => selfBuffDefenseMult(kind) - 1,
              SelfBuffKind.rage => selfBuffAttackMult(kind) - 1,
              SelfBuffKind.haste => selfBuffSpeedMult(kind) - 1,
            },
    );
  }

  /// Starts (or refreshes) regeneration on this combatant. Re-applying replaces
  /// rather than stacks — the same rule the buffs follow.
  void applyRegen({required int turns, required double value}) {
    regenValue = value;
    regenTurnsRemaining = turns;
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
    // FEAR is the status whose whole point is stealing turns, so its chance is
    // the authored one. Frost's 10 % is a side effect of being frozen and stays
    // the catalog's (its authored number is the speed loss) — see
    // AbilityEffectKind.frost, which says both out loud in the form.
    final chance =
        mainStatus == MainStatusKind.fear || mainStatus == MainStatusKind.sleep
        ? mainStatusValue
        : statusSkipChance(mainStatus!);
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
      // The move's own damage per turn, plus poison's escalation — which is the
      // SHAPE of poison rather than a magnitude, so it stays the catalog's
      // (statusDotFraction's step) and is stated in the form's description.
      final frac = mainStatus == MainStatusKind.poison
          ? mainStatusValue +
                (statusDotFraction(MainStatusKind.poison, 1) -
                        statusDotFraction(MainStatusKind.poison, 0)) *
                    mainStatusTurnsActive
          : (mainStatus == MainStatusKind.burn ? mainStatusValue : 0.0);
      dot = (maxHp * frac).round();
      hp = math.max(cannotBeKoed ? 1 : 0, hp - dot);
      mainStatusTurnsActive++;
      mainStatusTurnsRemaining--;
      if (mainStatusTurnsRemaining <= 0) {
        mainStatus = null;
        mainStatusTurnsActive = 0;
        mainStatusValue = 0;
      }
    }
    // REGEN ticks in the same upkeep as the DoT, and after it: a monster on 1 HP
    // with both should not die to the burn and then be healed.
    lastRegenHeal = 0;
    if (regenTurnsRemaining > 0) {
      if (alive) {
        final before = hp;
        hp = math.min(maxHp, hp + (maxHp * regenValue).round());
        lastRegenHeal = hp - before;
      }
      regenTurnsRemaining--;
      if (regenTurnsRemaining <= 0) regenValue = 0;
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

  static void _decrementAndPrune<K>(Map<K, ActiveEffect> active) {
    final expired = <K>[];
    for (final e in active.entries) {
      e.value.turnsRemaining--;
      if (e.value.turnsRemaining <= 0) expired.add(e.key);
    }
    for (final k in expired) {
      active.remove(k);
    }
  }

  /// Player-side combatant backed by a collection creature. HP starts at the
  /// instance's persistent value (it carries over between fights).
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
      backImageUrl: c.backImageUrl,
      element: species?.element ?? CreatureElement.fire,
      rarity: species?.rarity ?? CreatureRarity.common,
      isPlayerSide: true,
      level: c.level,
      stats: {for (final s in CreatureStat.values) s: c.statValue(s)},
      abilities: _resolveAbilities(species, c.stage),
      hp: c.hp,
    );
  }

  /// Generated wild/enemy creature of [species] at [level]. Stage follows
  /// the species' OWN evolution levels (a wild past its evo-2 level appears
  /// in final form), genes are freshly rolled (kept on [wildStatBase]/
  /// [wildStatSlope] so a catch preserves this exact individual), pools
  /// start full.
  /// [statScale] is an extra multiplier on the battle stats only (1.0 =
  /// balanced default). The new-player jumpstart passes
  /// kJumpstartEnemyStatMult so the intro's fights can't strand a lone
  /// starter; like the handicap below it never touches the genes a catch
  /// keeps, so a monster caught during the intro is a full-quality one.
  factory Combatant.fromSpecies(
    SpeciesDef species, {
    required int level,
    required String id,
    math.Random? rng,
    bool isBoss = false,
    double statScale = 1.0,
  }) {
    final random = rng ?? math.Random();
    // Evolution stage a creature has reached by [level] — the single copy of
    // this rule, so a caught wild matches exactly what was hunted.
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
    // Boss elite bonus (+20%) vs. plain-wild handicap (×kWildStatMult) —
    // applied only to the battle stats, never to the genes a catch keeps.
    final stats = {
      for (final s in CreatureStat.values)
        s: math.max(
          1,
          (temp.statValue(s) *
                  (isBoss
                          ? GameTuning.i.raw(Dials.bossStatMult)
                          : kWildStatMult) *
                  statScale)
              .round(),
        ),
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
    final out = <AbilityDef>[];
    for (final sa in species.abilitiesAt(stage)) {
      final def = kAbilityDefs[sa.abilityId];
      if (def == null) continue;
      // A move must be affordable at the stage it UNLOCKS — otherwise the form
      // that gets it could never pay for it. A STARTING ability (unlockStage 0)
      // is therefore capped at the base form's 4 AP; later unlocks at 5 / 7
      // (user request 2026-07-19).
      final cap = maxActionPointsForStage(sa.unlockStage);
      out.add(def.resolvedApCost > cap ? def.withApCost(cap) : def);
    }
    return out;
  }
}
