import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/tuning/game_tuning.dart';
import 'xp_balance.dart';

export 'xp_balance.dart' show XpConfig, kXpBalance;

// ── Creature system: shared enums & balancing constants ─────
// Refined 2026-07-06 against a detailed external balance pass (see
// [[project_creature_battle_system]]): 6 stats (no physical/magic split),
// 5 rarities, level cap 75, Gaussian-sampled individuality, additive
// evolution bonus, CTB combat kept (per user decision) with a full status
// effect layer. Numbers here are the single source of truth for the whole
// feature — balancing changes happen HERE, not scattered across screens.

/// The 5 combat elements. Explicit 5x5 matrix (not a simple beats/loses
/// pair) since Licht/Schatten mutually hit each other hard (1.5 both ways)
/// while also strongly resisting themselves (0.5) — asymmetric vs. the
/// Feuer→Pflanze→Wasser→Feuer cycle's clean 1.5/0.5/1.0 triangle.
///
/// Type ADVANTAGE is +50% (×1.5), not double (user decision 2026-07-17:
/// "doppelt ist sehr viel"). This also shrinks the multiplier stack that
/// drives extreme hits: STAB 1.5 × type 1.5 × crit 1.5 = 3.4× now (was
/// 4.5×). The DISADVANTAGE stays at ×0.5 (half damage) unless changed.
enum CreatureElement {
  fire('Fire', '🔥', Color(0xFFE25822)),
  water('Water', '💧', Color(0xFF018ABE)),
  plant('Plant', '🌿', Color(0xFF3BAE78)),
  light('Light', '✨', Color(0xFFE9B44C)),
  shadow('Shadow', '🌑', Color(0xFF6B5B95)),
  // A typeless option for abilities that have no elemental identity — most
  // buffs and the normal Attack (user request). Neutral never lands or takes
  // bonus damage (multiplierVs is always 1.0), and it is NOT a creature type
  // (kept out of the species editor). Placed LAST so the 5 real types keep
  // their indices for the effectiveness matrix below.
  neutral('Neutral', '⚪', Color(0xFF8B95A5));

  final String label;
  final String emoji;
  final Color color;
  const CreatureElement(this.label, this.emoji, this.color);

  /// The element's dark "shadow" tone — the EXACT colour the type-icon 3D
  /// emboss uses for its extruded face (`lerp(color, black, 0.32)`). Reused for
  /// every monster's drop shadow so a sprite's shadow matches the shadow of its
  /// own type icon (user request). Keep this in sync with the emboss face in
  /// creature_backdrop.dart — both read this getter.
  Color get shadowColor => Color.lerp(color, Colors.black, 0.32)!;

  // Row = attacker, column = defender. Matches the spec's matrix exactly:
  // Fire/Water/Plant/Light/Shadow order both ways.
  static const List<List<double>> _matrix = [
    // vs   Fire Water Plant Light Shadow  (advantage 1.5, disadvantage 0.5)
    [1.0, 0.5, 1.5, 1.0, 1.0], // Fire attacks
    [1.5, 1.0, 0.5, 1.0, 1.0], // Water attacks
    [0.5, 1.5, 1.0, 1.0, 1.0], // Plant attacks
    [1.0, 1.0, 1.0, 0.5, 1.5], // Light attacks
    [1.0, 1.0, 1.0, 1.5, 0.5], // Shadow attacks
  ];

  /// Damage multiplier when [this] attacks [defender]. Neutral on either side
  /// is always 1.0 — no advantage, no resistance — and it also keeps the 5×5
  /// matrix from being indexed with neutral's out-of-range index.
  double multiplierVs(CreatureElement defender) =>
      (this == neutral || defender == neutral)
          ? 1.0
          : _matrix[index][defender.index];

  static CreatureElement fromName(String? name) => CreatureElement.values
      .firstWhere((e) => e.name == name, orElse: () => CreatureElement.fire);
}

/// 5 rarity tiers — a label and a colour, nothing else. Base stats come from
/// each species' own balanced table (no global multiplier on top) and evolution
/// is free. Everything a rarity NUMERICALLY decides is dev-authored in
/// [SpeciesBalance]: the stat budgets, the catch difficulty, and the mating /
/// hatching durations. (The enum used to carry its own `breedHours`; nothing
/// read it once the config existed, and leaving a second copy of a number the
/// Dev-Mode screen edits is how the two silently disagree.)
enum CreatureRarity {
  common('Common', Color(0xFF9E9E9E)),
  uncommon('Uncommon', Color(0xFF4CAF50)),
  rare('Rare', Color(0xFF2196F3)),
  epic('Epic', Color(0xFF9C27B0)),
  legendary('Legendary', Color(0xFFFFB300));

  final String label;
  final Color color;

  const CreatureRarity(this.label, this.color);

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

/// Every creature stat, in three groups:
///   • The first 4 are COMBAT stats (battle engine): no physical/magic split —
///     every move rolls ATK vs. DEF. (Combat runs on ACTION POINTS now, not an
///     energy pool — the old `energy` stat is gone.)
///   • The next 8 are WORK-ROLE stats (`kCivilianStats`) — one per settlement
///     workshop role. A workshop's output is the sum of its assigned
///     creatures' relevant stat, so a creature's profile decides where it's
///     worth stationing.
///   • `carry` and `catchRate` are NON-COMBAT UTILITY stats — not work roles:
///     `carry` is how much a creature hauls, both as expedition loot and as a
///     trade caravan's cargo (see [[expedition-overworld-redesign]]);
///     `catchRate` is the Fangwert used when THIS creature attempts a catch.
///     Both are civilian for the budget and excluded from `kCivilianStats`.
///     `carry` and the combat stat `speed` CAN still be posted in a building —
///     the trip-amplifier posts read them (see [kPostableStats]).
/// Every stat (all groups) is Gaussian-sampled per species, grows with level
/// and is inherited on breeding — identical mechanics, different readers.
enum CreatureStat {
  // Combat (user 2026-07-22: Catch Rate is a COMBAT capability now — it moved
  // into the combat budget; its function is unchanged, it still only drives
  // catching).
  hp('HP'),
  attack('Attack'),
  defense('Defense'),
  speed('Speed'),
  catchRate('Catch Rate'),
  // ── Work roles (user 2026-07-25) ──
  // Rebuilt around WHAT a monster does, not which era-I trade it learned.
  // Woodcutting / Mining / Gold Panning / Luxury Production were four names for
  // one gesture and all four stopped making sense the moment an era produced
  // steel or aether. The split now follows the PLACES a monster can be:
  //
  //   gathering    out on the map, filling a load        (all spots, all eras)
  //   production   inside a production building          (build + luxury goods)
  //   construction on a building site
  //   crafting     at the workbench, making items
  //   breeding     in the Breeding Hut / Hatchery
  //   medicine     in the Healing Hut
  //   trade        in the Trade Center
  //   logistics    inside a STORE, making room               (user 2026-07-30)
  //
  // WHICH resource is gathered or produced no longer needs its own stat — the
  // per-resource dials (settlement/data/gather_defs.dart) already say how slow
  // gold is compared with wood.
  //
  // `logistics` is BACK since 2026-07-30 (user: "Ich brauche trotzdem noch einen
  // neuen Stat: Logistics, welcher in den Lagerhäusern benutzt wird … wobei ihre
  // Punkte in Logistics die Lagerkapazität definieren"), and this time it names
  // a PLACE like every other work stat: the Storehouse and the Gold Vault.
  //
  // It was deleted on 2026-07-26 for the opposite reason — it was then a
  // catch-all "trip amplifier" with no building of its own, and once a trip's
  // real numbers became speed (how long) and carry (how much), those three posts
  // read the stat they amplify instead. They still do: a warehouse reads `carry`,
  // a scout post `speed`, a smokehouse `gathering` (see [kPostableStats]). This
  // stat is about how much the settlement can HOLD, not how much comes back.
  gathering('Gathering'),
  production('Production'),
  construction('Construction'),
  crafting('Crafting'),
  breeding('Breeding'),
  medicine('Medicine'),
  trade('Trade'),
  logistics('Logistics'),
  // Non-combat utility (not a work role, but a building may still post it)
  carry('Carry');

  final String label;
  const CreatureStat(this.label);

  /// The key this stat was stored under before it was renamed, or null.
  ///
  /// Genes are persisted BY NAME (`stat_base: {"mining": 42, …}`) on both
  /// creatures and species curves. `research` became `crafting` when BP and the
  /// research timer were deleted (2026-07-16) and the stat was repurposed to
  /// making goods. Without this alias every existing creature's rolled research
  /// value would simply stop being found, and _backfillGenes would quietly
  /// refill it from the species MEAN — silently destroying an individual roll
  /// that the whole gene system exists to preserve.
  ///
  /// Reads accept either key; writes always use the new one, so a row heals
  /// itself the first time it's saved.
  String? get legacyKey => this == CreatureStat.crafting ? 'research' : null;

  /// Reads this stat out of a name-keyed JSON map, tolerating the old key.
  ///
  /// `luxuryProduction` deliberately has NO legacy read from the old
  /// fishing/hunting genes (user 2026-07-22): existing creatures get a FRESH
  /// roll via the gene backfill instead of inheriting either value.
  num? readJson(Map<dynamic, dynamic> json) =>
      (json[name] ?? (legacyKey == null ? null : json[legacyKey])) as num?;

  /// The 5 battle stats (hp..catchRate) — catchRate joined the combat group
  /// (user 2026-07-22); its FUNCTION is unchanged (drives catching only).
  bool get isCombat => index <= CreatureStat.catchRate.index;

  /// Non-combat stats (the 8 work-role stats + carry).
  bool get isCivilian => !isCombat;

  /// The 7 settlement workshop-role stats — civilian minus the utility stat
  /// `carry` (which no building offers). Use this, not `isCivilian`, for
  /// work roles.
  bool get isWorkRole => isCivilian && this != CreatureStat.carry;

  /// CONTENT-side aliases for retired stat names (user 2026-07-25).
  ///
  /// A DB-authored workshop row still says `woodcutting` or `luxuryProduction`
  /// — every one of those rows sits on a PRODUCTION building, so they all mean
  /// [production] now. ('fishing'/'hunting' were merged into the luxury stat in
  /// 2026-07-22 and follow the same path.) Without this a lumber camp would
  /// silently fall back to `hp`, i.e. become a gym.
  ///
  /// This is deliberately NOT a gene alias: existing creatures do not inherit
  /// their old work genes, they are re-rolled from the species curve (user
  /// decision) — see [readJson] and CreatureInstance.needsGeneBackfill.
  static const Map<String, CreatureStat> _retiredNames = {
    'woodcutting': CreatureStat.production,
    'mining': CreatureStat.production,
    'prospecting': CreatureStat.production,
    'luxuryProduction': CreatureStat.production,
    'fishing': CreatureStat.production,
    'hunting': CreatureStat.production,
  };

  static CreatureStat fromName(String? name) {
    final retired = _retiredNames[name];
    if (retired != null) return retired;
    return CreatureStat.values
        .firstWhere((s) => s.name == name, orElse: () => CreatureStat.hp);
  }
}

/// The five combat stats, in declaration order — a convenience for UI that
/// wants to show combat and civilian stats in separate groups.
const List<CreatureStat> kCombatStats = [
  CreatureStat.hp,
  CreatureStat.attack,
  CreatureStat.defense,
  CreatureStat.speed,
  CreatureStat.catchRate,
];

/// The eight civilian WORK-ROLE stats, in declaration order (user 2026-07-25;
/// `logistics` deleted 2026-07-26 and brought back 2026-07-30 as the STORES'
/// stat). `carry` is civilian too but is a utility stat, not a work role, so it
/// is not here — see [kPostableStats].
///
/// Every entry must have a building that reads it (test/work_roles_test.dart):
/// a work stat no post offers is a stat that silently eats species budget, which
/// is exactly what got the first `logistics` deleted.
const List<CreatureStat> kCivilianStats = [
  CreatureStat.gathering,
  CreatureStat.production,
  CreatureStat.construction,
  CreatureStat.crafting,
  CreatureStat.breeding,
  CreatureStat.medicine,
  CreatureStat.trade,
  CreatureStat.logistics,
];

/// Every stat a WORKSHOP POST may read — the work roles plus the two trip
/// stats (user 2026-07-26).
///
/// The expedition amplifiers used to run on a stat of their own (`logistics`)
/// that existed for no other reason. Now each of those posts reads the stat it
/// actually amplifies — a scout post shortens the trip, so it reads `speed`; a
/// warehouse raises the load, so it reads `carry` — which is why a combat stat
/// and a utility stat can both sit on a workshop role. Use THIS list wherever a
/// post's stat is offered or validated, not [kCivilianStats].
const List<CreatureStat> kPostableStats = [
  ...kCivilianStats,
  CreatureStat.carry,
  CreatureStat.speed,
];

// ── Progression constants ───────────────────────────────────
// ── Era-gated progression (user redesign 2026-07-22) ────────
// Eras are the game's spine now: each era raises the creature level cap by
// [kLevelsPerEra] (era 1 → Lv 10, era 2 → Lv 20 …), XP gain scales up per era
// so fresh catches reach the new band quickly, and the hard ceiling is
// kMaxEras × kLevelsPerEra. Everything is FORMULA-based (user request) so
// adding a 9th era is a constant bump, not a table edit.

// Dials since 2026-07-29 (Monster → Level). Everything here is FORMULA-based
// (user request), which is exactly what lets the two numbers be turned rather
// than a table be rewritten.
int get kMaxEras => GameTuning.i.count(Dials.maxEras);
int get kLevelsPerEra => GameTuning.i.count(Dials.levelsPerEra);

/// The level cap while the settlement is in era [eraOrder] (1-based). Global:
/// it caps EVERY monster, old and new alike — XP past it is forfeited.
int creatureLevelCap(int eraOrder) =>
    eraOrder.clamp(1, kMaxEras) * kLevelsPerEra;

// The per-era XP catch-up multiplier is GONE (user 2026-07-26: "Ära-
// Aufholfaktor löschen, das braucht es nicht"). Every XP source now pays what
// it says it pays, in every era; the enemies' own levels are what scale the
// battle reward — see XpConfig.killXp.

int get kCreatureMaxLevel => kMaxEras * kLevelsPerEra; // 80 at the defaults

/// Individual-variation sampling (decided design): every one of the 28
/// genes (a stage-1 base value AND a growth slope for each of the 14 stats)
/// is independently rolled
/// from a Gaussian around the species' own mean, clamped to ±2σ so no roll
/// is ever a wild outlier. Base values vary more (8%) than growth slopes
/// (6%) — growth compounds over 75 levels, so a tighter band there keeps
/// late-game gaps from exploding.
double get kBaseSigmaPct => GameTuning.i.raw(Dials.baseSigmaPct);
double get kSlopeSigmaPct => GameTuning.i.raw(Dials.slopeSigmaPct);
double get kSigmaClampFactor => GameTuning.i.raw(Dials.sigmaClampFactor);

// ── Action points (user redesign 2026-07-20) ───────────────
// Combat runs on ACTION POINTS. AP are a CARRIED resource now, not a per-turn
// allowance: a monster keeps whatever it didn't spend and only REGENERATES a
// few points at the start of each of its own turns, up to its capacity.
//
// That gap is the whole tactical point (user: "So muss ich taktisch arbeiten
// und kann nicht immer alles benutzen") — regen sits deliberately BELOW
// capacity, so emptying the pool now means a thin next turn, and holding back
// is how you afford an expensive move later. The old rule (refill to full every
// turn, lose the remainder) made every turn identical and the choice free.
//
// EVOLVING raises BOTH the capacity and the regen, so a final form banks more
// and refills faster.

/// AP an attack costs. Against a 3–5 regen that's about one attack per turn
/// unless you save up.
int get kBasicAttackApCost => GameTuning.i.count(Dials.basicAttackApCost);

/// AP a monster switch costs (spent from the OUTGOING monster's pool).
int get kSwitchApCost => GameTuning.i.count(Dials.switchApCost);

/// The CHEAPEST a buff/debuff-focused ability can be — deliberately low (user
/// request 2026-07-17: make buffs/debuffs something you WANT to play), and
/// exactly what the first actor opens the battle with, so turn one can be a
/// setup turn rather than a wasted one.
///
/// A FLOOR since 2026-07-30, not a fixed price: once every effect carries a
/// power value, a +60 %/4-turn Haste and a stock +30 %/2-turn one are not the
/// same purchase, and pricing both at this number made the dial inert for every
/// buff that had an effect at all. See AbilityDef._derivedApCost.
int get kBuffApCost => GameTuning.i.count(Dials.buffApCost);

/// How much POWER one action point buys — the exchange rate behind every
/// ability's cost (user 2026-07-30, dial since the same day: "damit es
/// vergleichbar wird mit den AP").
///
/// It was a bare `13` inside the cost formula, which made the single number that
/// governs what everything costs the one number Dev Mode could not turn.
int get kPowerPerAp => GameTuning.i.count(Dials.powerPerAp);

/// The cheapest any non-buff ability can be. A move still costs a turn to play,
/// so a weak one must not be free.
int get kMinAbilityApCost => GameTuning.i.count(Dials.minAbilityApCost);

/// What one step of PRIORITY is worth in power — priced through the same
/// exchange rate as everything else on a move (user 2026-07-30). It was a bare
/// 15 inside the cost formula.
int get kPriorityPower => GameTuning.i.count(Dials.priorityPower);

/// The most power a move can have and still be priced honestly: what the biggest
/// AP pool in the game can pay for. Beyond it the price is pinned at
/// [kMaxActionPoints] and extra strength is FREE — which is exactly the hole the
/// flat effect surcharges used to leave, so the ability form warns instead of
/// quietly saturating.
int get kMaxPricedPower => kMaxActionPoints * kPowerPerAp;

/// AP CAPACITY by evolution stage (user 2026-07-20; dials since 2026-07-29):
/// what a monster may bank UP TO, not what it receives each turn.
List<int> get kActionPointsByStage => [
  GameTuning.i.count(Dials.apCapacity1),
  GameTuning.i.count(Dials.apCapacity2),
  GameTuning.i.count(Dials.apCapacity3),
];

/// AP REGENERATED at the start of each of a monster's own turns, by stage
/// (user 2026-07-20) — meant to sit below the matching capacity, which is what
/// forces the planning. Nothing enforces that: an author who wants refill-to-
/// full every turn can have it, and will see the old flat game it produces.
List<int> get kApRegenByStage => [
  GameTuning.i.count(Dials.apRegen1),
  GameTuning.i.count(Dials.apRegen2),
  GameTuning.i.count(Dials.apRegen3),
];

/// AP capacity at the base evolution stage (stage 0).
int get kBaseActionPoints => kActionPointsByStage.first;

/// Hard ceiling — the largest capacity any stage grants.
int get kMaxActionPoints => kActionPointsByStage.reduce(math.max);

/// AP the battle OPENS with (user 2026-07-20): whoever acts FIRST starts on
/// [kStartApFirst], the other side on [kStartApSecond]. Both are lean on
/// purpose — the first actor can play a buff but cannot swing yet.
int get kStartApFirst => GameTuning.i.count(Dials.startApFirst);
int get kStartApSecond => GameTuning.i.count(Dials.startApSecond);

/// A monster's AP capacity at evolution [stage] (0–2, clamped).
int maxActionPointsForStage(int stage) =>
    kActionPointsByStage[stage.clamp(0, kActionPointsByStage.length - 1)];

/// AP a monster at evolution [stage] regains at the start of its own turn.
int apRegenForStage(int stage) =>
    kApRegenByStage[stage.clamp(0, kApRegenByStage.length - 1)];

/// XP needed to advance FROM [level] to level+1 — factor · level^exponent,
/// seeded with the balance-pass curve 6·L^2.5 and dev-tunable since 2026-07-26
/// (Species-Budget → XP). Kept as a top-level function here rather than inlined
/// in CreatureInstance since dungeon reward math also references it.
int xpToNextLevel(int level) => kXpBalance.xpToNext(level);

// ── The two automatic XP rates ──────────────────────────────
// WORK pays a trickle and TRAINING pays a wage; both are dev-tunable in
// Species-Budget → XP, and neither is meant to be the way you level (user
// 2026-07-30: "Primäre EP Quelle soll der Kampf sein oder das Training").
//
// The per-building `xp` EFFECT is gone (user 2026-07-30: "Jedes Gebäude, welches
// Monster «anstellt» soll EP geben. Jedes Gebäude gibt genau gleich viel EP").
// It could not express that rule: it was authored on eleven era-I buildings and
// on none of the other ~40 with work posts, and every one of the eleven was a
// separate number in Dev Mode. One rate for every post says it exactly, and
// says it once.

/// XP/h a monster earns for holding a post in a building of [buildingLevel] —
/// the SAME in every building that stations monsters (see [XpConfig.workPerHour]
/// for why one number, and CreaturesController.xpRatePerHour for the one place
/// that decides which of the two rates a post pays).
double workXpPerHourAt(int buildingLevel) =>
    kXpBalance.workXpAt(buildingLevel);

/// XP per hour in a TRAINING role (WorkshopRole.kTraining — the Training
/// Grounds), the higher of the two (user request 2026-07-17: a building to
/// station monsters in that levels them over time).
///
/// The trade is the point: a trainee produces NOTHING — no wood, no
/// construction — so this competes with the economy for bodies, and it is why
/// the Training Grounds keeps its own rate instead of falling back to the
/// settlement-wide work trickle (user 2026-07-30). Against
/// 6·L^2.5 that's ~1.3h to a level at Lv5, ~7.6h at Lv10, ~1.8d at Lv20, ~5d
/// at Lv30: real progress deep into the midgame, while fighting stays the
/// fastest way to keep pace with the trial-level curve (docs/balancing.md §7).
///
/// Energy-gated (accrues over the tick's effectiveHours), so an out-of-energy
/// settlement trains nobody. Dev-tunable in Species-Budget → XP.
double get kTrainingXpPerHour => kXpBalance.trainingPerHour;

// ── Breeding stat tuning ─────────────────────────────────────
// The `breeding` civilian stat drives two effects, both starting neutral at
// breeding=0 and improving asymptotically (same soft-cap shape as the
// catch/crit curves). [kBreedingK] is the value at which each is halfway.

/// The half-way point of both breeding curves. For the TIME cut this reads
/// directly: a building with this much breeding power runs its jobs in half
/// their base time; ×4 that power gets to −80 %, ×9 to −90 %.
double get kBreedingK => GameTuning.i.raw(Dials.breedingK);

/// Per-gene chance the BETTER parent value is inherited — a FLAT 60 % (user
/// 2026-07-27: "Der Breedingwert ist irrelevant dafür … ändere die Chance auf
/// 60%").
///
/// It used to scale with the parents' average `breeding` stat (0.50 at 0,
/// asymptoting toward 1.0). That made the number on the breeding screen move
/// for reasons the player could not act on — you cannot train a parent's
/// breeding stat — and it was the ONLY thing the parents' breeding stat did.
/// Breeding SPEED still comes from the breeders stationed in the hut, which is
/// a post you control.
double get kBreedingFavoredChance =>
    GameTuning.i.raw(Dials.breedingFavoredChance);

/// The odds each gene is rolled at. Kept as a function so every reader goes
/// through one place if it ever depends on something again.
double breedingFavoredChance() => kBreedingFavoredChance;

/// Fraction of [baseHours] the stationed breeders remove at [power]: 0 with an
/// empty post, rising toward 1 with diminishing returns.
///
/// NO CEILING (user 2026-07-26). It used to stop at a hard −50 %, which made
/// the building level pointless past a couple of breeders — every further
/// upgrade bought a fraction of a percent. The curve still flattens, so power
/// keeps costing more per point saved, but nothing is ever out of reach: −50 %
/// at [kBreedingK], −80 % at ×4, −90 % at ×9. The duration approaches zero
/// without reaching it, so a job always has a real timer.
double breedingTimeCut(double power) =>
    power <= 0 ? 0 : power / (power + kBreedingK);

/// Incubation hours for a job: the rarity base scaled down by the breeding
/// power posted in the building. Always > 0 — see [breedingTimeCut].
double breedingHours(double baseHours, double power) =>
    baseHours * (1 - breedingTimeCut(power));

/// Inverse of [breedingHours]: the breeding power a building must have posted
/// to bring [baseHours] down to [targetHours] (user 2026-07-26 — "ich gebe eine
/// Zeit an und du zeigst mir die benötigte Power").
///
/// Returns 0 when the target is at or above the base (no staff needed). Every
/// shorter duration is reachable now that the cut has no ceiling — the answer
/// just grows steeply as the target nears zero. null only for a target of zero
/// or less, which is not a duration at all.
double? breedingPowerForHours(double baseHours, double targetHours) {
  if (baseHours <= 0) return null;
  final cut = 1 - targetHours / baseHours;
  if (cut <= 0) return 0;
  if (cut >= 1) return null; // zero/negative time — no power expresses that
  return kBreedingK * cut / (1 - cut);
}

// ── Settlement integration ───────────────────────────────────
// All content-side hooks are CONVENTION-BY-ID and content-optional: create a
// tech/building with exactly these ids in Dev Mode and the game wires it up;
// while the def doesn't exist, the corresponding gate/entry simply stays off.

// ── The feature-unlock system is GONE (user 2026-07-26) ──
// Evolution, breeding, hunt lengths, expedition slots and team size were each
// opened by a `unlockedFeatures` id earned on the path. All of it is deleted;
// every one of them now hangs off something the player can SEE:
//
//   evolution        → the creature's LEVEL, nothing else ("evolution ist immer
//                      freigeschalten sobald das level erreicht wurde")
//   breeding         → owning a Breeding Hut, which it always needed anyway
//   hunt length      → the Scout Post's `huntOptions` effect
//   expedition slots → the Scout Post's `expeditionSlots` effect
//   team size        → position on the linear path (already true since
//                      2026-07-24 — see SettlementController.partyCap)

/// Hunts start at the shortest variant (10 min, 1 hunter); each point of the
/// settlement's `huntOptions` opens the next kCaptureHuntOptions entry in order
/// (30 min → 60 min → 4 h → 8 h → 24 h). The exact-hunter-count gate still
/// applies on top (user decision 2026-07-17): a longer variant needs BOTH the
/// scouting for it AND enough ready monsters.
/// Left unclamped on purpose: both callers bound it against the real option
/// list (`take` / an index check), and clamping here would mean naming
/// kCaptureHuntOptions from this file, which capture_math already imports.
int maxHuntOptionCount(int buildingHuntOptions) =>
    1 + (buildingHuntOptions < 0 ? 0 : buildingHuntOptions);

/// Placeable buildings that open creature features when tapped (must be
/// finished + road-connected). Interim quick-menu buttons stay as fallback.
const String kDungeonPortalBuildingId = 'dungeon_portal';
const String kBreedingHutBuildingId = 'breeding_hut';
const String kHatcheryBuildingId = 'hatchery';
const String kHealingHutBuildingId = 'healing_hut';

/// Opens the market (sell surplus for gold — see market_screen.dart).
/// It's also the building that PRODUCES gold, so the place you mint it and the
/// place you trade for it are the same.
const String kTradingPostBuildingId = 'trading_post';

/// Offers the training BATTLE (user decision 2026-07-17: moved here from the
/// Monsters screen) on top of its passive-XP training slots — the place you
/// train is the place you spar.
const String kTrainingGroundsBuildingId = 'training_grounds';

/// Opens the BUILD MENU (user 2026-07-29: "das build menü soll auch durch das
/// build camp aufrufbar sein"). The camp is where the builders are — the
/// building whose laborers set every construction speed — so it is the natural
/// second door to the menu beside the corner pad's Build button.
const String kBuilderCampBuildingId = 'builder_camp';

/// Opens the EXPEDITIONS hub (user 2026-07-29: "trips soll über den scoutpost
/// erreichbar sein"). The post is already what grants the expedition slots and
/// what shortens a trip, so it is the building the activity belongs to — and
/// the corner pad's Trips key is gone, which makes this and the Management
/// hub's leading tab the two ways in.
const String kScoutPostBuildingId = 'scout_post';

/// Opens the CRAFTING screen (user 2026-07-29: "workshop. Crafting ist ein
/// eigener screen und kann über den workshop geöffnet werden"). The id is
/// historical — the building was the "Thinker Circle" when research still
/// existed — and renaming it would orphan every placed one.
const String kWorkshopBuildingId = 'thinker_circle';
