import 'dart:math' as math;

import 'package:flutter/material.dart';

// ── Creature system: shared enums & balancing constants ─────
// Refined 2026-07-06 against a detailed external balance pass (see
// [[project_creature_battle_system]]): 6 stats (no physical/magic split),
// 5 rarities, level cap 75, Gaussian-sampled individuality, additive
// evolution bonus, CTB combat kept (per user decision) with a full status
// effect layer. Numbers here are the single source of truth for the whole
// feature — balancing changes happen HERE, not scattered across screens.

/// The 5 combat elements. Explicit 5x5 matrix (not a simple beats/loses
/// pair) since Licht/Schatten mutually hit each other hard (2.0 both ways)
/// while also strongly resisting themselves (0.5) — asymmetric vs. the
/// Feuer→Pflanze→Wasser→Feuer cycle's clean 2.0/0.5/1.0 triangle.
enum CreatureElement {
  fire('Fire', '🔥', Color(0xFFE25822)),
  water('Water', '💧', Color(0xFF018ABE)),
  plant('Plant', '🌿', Color(0xFF3BAE78)),
  light('Light', '✨', Color(0xFFE9B44C)),
  shadow('Shadow', '🌑', Color(0xFF6B5B95));

  final String label;
  final String emoji;
  final Color color;
  const CreatureElement(this.label, this.emoji, this.color);

  // Row = attacker, column = defender. Matches the spec's matrix exactly:
  // Fire/Water/Plant/Light/Shadow order both ways.
  static const List<List<double>> _matrix = [
    // vs   Fire Water Plant Light Shadow
    [1.0, 0.5, 2.0, 1.0, 1.0], // Fire attacks
    [2.0, 1.0, 0.5, 1.0, 1.0], // Water attacks
    [0.5, 2.0, 1.0, 1.0, 1.0], // Plant attacks
    [1.0, 1.0, 1.0, 0.5, 2.0], // Light attacks
    [1.0, 1.0, 1.0, 2.0, 0.5], // Shadow attacks
  ];

  /// Damage multiplier when [this] attacks [defender].
  double multiplierVs(CreatureElement defender) =>
      _matrix[index][defender.index];

  static CreatureElement fromName(String? name) => CreatureElement.values
      .firstWhere((e) => e.name == name, orElse: () => CreatureElement.fire);
}

/// 5 rarity tiers. Rarity now only drives catch chance, breeding time and
/// BP evolution cost — base stats come directly from each species' own
/// balanced table (no more global stat multiplier layered on top).
enum CreatureRarity {
  common('Common', Color(0xFF9E9E9E), 1.00, 4, 1.0),
  uncommon('Uncommon', Color(0xFF4CAF50), 0.85, 6, 1.25),
  rare('Rare', Color(0xFF2196F3), 0.70, 8, 1.5),
  epic('Epic', Color(0xFF9C27B0), 0.45, 16, 2.5),
  legendary('Legendary', Color(0xFFFFB300), 0.25, 24, 4.0);

  final String label;
  final Color color;

  /// Factor on the catch chance (legendaries are hard to catch).
  final double catchFactor;

  /// Mating timer in hours for the breeding building.
  final int breedHours;

  /// Multiplier on the BP evolution costs below.
  final double evoCostMult;

  const CreatureRarity(
    this.label,
    this.color,
    this.catchFactor,
    this.breedHours,
    this.evoCostMult,
  );

  static CreatureRarity fromName(String? name) => CreatureRarity.values
      .firstWhere((r) => r.name == name, orElse: () => CreatureRarity.common);
}

enum CreatureGender {
  male('♂', Color(0xFF018ABE)),
  female('♀', Color(0xFFE91E63));

  final String symbol;
  final Color color;
  const CreatureGender(this.symbol, this.color);

  static CreatureGender fromName(String? name) => CreatureGender.values
      .firstWhere((g) => g.name == name, orElse: () => CreatureGender.male);
}

/// Every creature stat. The first 6 are COMBAT stats (used by the battle
/// engine): no physical/magic split — every move rolls ATK vs. DEF; `energy`
/// is the MAX energy pool; `catchRate` is the Fangwert used when THIS
/// creature attempts a catch. The remaining 8 are CIVILIAN stats — one per
/// settlement work role. Civilian stats behave IDENTICALLY to combat stats
/// (Gaussian-sampled per species, grow with level, inherited on breeding);
/// they're just read by the settlement economy instead of the battle engine.
/// A workshop's output is the sum of its assigned creatures' relevant stat,
/// so a creature's civilian profile decides where it's worth stationing.
enum CreatureStat {
  // Combat
  hp('HP'),
  attack('Attack'),
  defense('Defense'),
  speed('Speed'),
  catchRate('Catch Rate'),
  energy('Energy'),
  // Civilian (one per work role — see WorkshopRole on BuildingDef)
  woodcutting('Woodcutting'),
  mining('Mining'),
  prospecting('Prospecting'),
  fishing('Fishing'),
  hunting('Hunting'),
  research('Research'),
  construction('Construction'),
  breeding('Breeding');

  final String label;
  const CreatureStat(this.label);

  /// The 6 battle stats — read by combat/catch math, never by the economy.
  bool get isCombat =>
      index <= CreatureStat.energy.index; // hp..energy are the first six

  /// The 8 work-role stats — read by the settlement economy, never by combat.
  bool get isCivilian => !isCombat;

  static CreatureStat fromName(String? name) => CreatureStat.values
      .firstWhere((s) => s.name == name, orElse: () => CreatureStat.hp);
}

/// The six combat stats, in declaration order — a convenience for UI that
/// wants to show combat and civilian stats in separate groups.
const List<CreatureStat> kCombatStats = [
  CreatureStat.hp,
  CreatureStat.attack,
  CreatureStat.defense,
  CreatureStat.speed,
  CreatureStat.catchRate,
  CreatureStat.energy,
];

/// The eight civilian (work-role) stats, in declaration order.
const List<CreatureStat> kCivilianStats = [
  CreatureStat.woodcutting,
  CreatureStat.mining,
  CreatureStat.prospecting,
  CreatureStat.fishing,
  CreatureStat.hunting,
  CreatureStat.research,
  CreatureStat.construction,
  CreatureStat.breeding,
];

// ── Progression constants ───────────────────────────────────

const int kCreatureMaxLevel = 75;

/// Individual-variation sampling (decided design): every one of the 12
/// genes (6 stage-1 base values + 6 growth slopes) is independently rolled
/// from a Gaussian around the species' own mean, clamped to ±2σ so no roll
/// is ever a wild outlier. Base values vary more (8%) than growth slopes
/// (6%) — growth compounds over 75 levels, so a tighter band there keeps
/// late-game gaps from exploding.
const double kBaseSigmaPct = 0.08;
const double kSlopeSigmaPct = 0.06;
const double kSigmaClampFactor = 2.0;

/// Energy a basic attack generates (basic attacks cost nothing; abilities
/// burn energy — this is the tactical core loop).
const int kBasicAttackEnergyGain = 10;

/// XP needed to advance FROM [level] to level+1: round(6 * level^2.5).
/// Matches the balance-pass EP curve exactly (kept as a top-level function
/// here rather than inlined in CreatureInstance since dungeon reward math
/// also references it).
int xpToNextLevel(int level) => (6 * math.pow(level, 2.5)).round();

/// BP cost for evolving a creature of [rarity] to [targetStage] (1 or 2).
/// Base costs unchanged from the original design (~150 / ~500 Common);
/// scaled by the same evoCostMult dial rarity already carries.
const List<int> kEvolutionBaseCostBp = [150, 500];

int evolutionCostBp(CreatureRarity rarity, int targetStage) {
  final base = kEvolutionBaseCostBp[(targetStage - 1).clamp(0, 1)];
  return (base * rarity.evoCostMult).round();
}

// ── Breeding stat tuning ─────────────────────────────────────
// The parents' `breeding` civilian stat drives two effects, both starting
// neutral at breeding=0 and improving asymptotically (same soft-cap shape as
// the catch/crit curves). [kBreedingK] is the stat value at which each
// effect is halfway to its cap — a mid-range breeding stat.

const double kBreedingK = 60.0;

/// Fraction of the rarity base incubation time removed at an infinite
/// breeding stat (so time never drops below 1-this of the base).
const double kBreedingMaxTimeCut = 0.50;

/// Per-gene chance the BETTER parent value is inherited, as a function of the
/// pair's average breeding stat: 0.50 at breeding=0 (pure coin-flip),
/// asymptoting toward 1.0. [avgBreeding] = mean of both parents' breeding
/// stat values.
double breedingFavoredChance(double avgBreeding) =>
    0.50 + 0.50 * (avgBreeding / (avgBreeding + kBreedingK));

/// Incubation hours for a pair: the rarity base scaled down by the pair's
/// average breeding stat (never below (1-kBreedingMaxTimeCut) of the base).
double breedingHours(int baseHours, double avgBreeding) {
  final cut = kBreedingMaxTimeCut * (avgBreeding / (avgBreeding + kBreedingK));
  return baseHours * (1 - cut);
}

// ── Settlement integration ───────────────────────────────────
// All content-side hooks are CONVENTION-BY-ID and content-optional: create a
// tech/building with exactly these ids in Dev Mode and the game wires it up;
// while the def doesn't exist, the corresponding gate/entry simply stays off.

/// Research-tree gates: evolving to stage 1 / stage 2 requires these techs —
/// but only once a tech def with the id actually exists (index = targetStage-1).
const List<String> kEvolutionTechIds = [
  'creature_evolution_1',
  'creature_evolution_2',
];

/// Placeable buildings that open creature features when tapped (must be
/// finished + road-connected). Interim quick-menu buttons stay as fallback.
const String kDungeonPortalBuildingId = 'dungeon_portal';
const String kBreedingHutBuildingId = 'breeding_hut';
const String kHealingHutBuildingId = 'healing_hut';
