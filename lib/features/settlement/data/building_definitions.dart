import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/tuning/game_tuning.dart';
import '../../creatures/models/creature_enums.dart' show CreatureStat;
import 'building_effects.dart';
import 'building_model.dart' show kModelFootprint;
import '../models/placed_building.dart' show PlacedBuilding;
import '../../creatures/models/path_node.dart' show pathBuildingUnlockBattle;
import 'goods_definitions.dart';

/// Parses the region order out of a region-id string (still `'era_N'` —
/// renaming the id itself would mean a data migration, so it stays an
/// internal identifier; only the MECHANIC it named is gone). Returns null for
/// a malformed/unknown id.
int? _regionOrderOfId(String id) => int.tryParse(id.split('_').last);

// ── Building levels (user design 2026-07-17) ────────────────
// Every placed building carries a level (PlacedBuilding.level, default 1).
// A higher level costs more and takes longer to build, but yields more —
// bigger workshop output, more housing, stronger settlement bonuses. Upgrade
// is a space-for-resources trade: territory is limited, so a level-5 building
// packs the output of several level-1 ones onto one footprint.
//
// Levels 1–5 need no research (user decision). Levels above that are gated —
// see kFreeBuildingLevelCap / maxBuildingLevel.
//
// The scaling lives in three pure factors so it's tunable in one place and
// documented in docs/balancing.md.

/// Highest level reachable without research.
const int kFreeBuildingLevelCap = 5;

/// DEFAULT level ceiling for a building that authors no [maxLevelPerEra] of its
/// own. The design intent (user 2026-07-22) is still that a building climbs ~10
/// levels and the next era brings a SUCCESSOR rather than a higher cap — but
/// this is a default now, NOT an enforced ceiling (user 2026-07-26): a def that
/// authors 21 levels really gets 21, and every per-level effect scales all the
/// way up with it. Clamping the authored number silently made the Dev-Mode
/// form and the game disagree.
const int kMaxBuildingLevel = 10;

/// Design formula for a successor building's base values, one region up:
/// base(region N) ≈ base(region 1) × this^(N−1). With the ×1.6 step and the
/// linear yield curve, region N+1 level 1 stays below a maxed region-N
/// building, and the crossover lands at level 6 — exactly the "old L10
/// beats new L1, new wins from L5/6" the user asked for. A GUIDE for
/// authoring content (dev mode / fallback defs), not something read at
/// runtime.
double regionProductionMult(int regionOrder) =>
    math.pow(1.6, regionOrder.clamp(1, 99) - 1).toDouble();

/// Worker slots a role offers at building [level]. The old automatic "+1 slot
/// every 3 levels" rule is GONE (user 2026-07-25): slot growth is authored
/// EXPLICITLY per level, exactly like housing capacity. The count is the role's
/// level-1 [WorkshopRole.slots] plus the sum of its per-level
/// [WorkshopRole.slotSteps] up to [level]. A role with no steps keeps a flat
/// slot count across every level.
///
/// No ceiling of its own (user 2026-07-26): the steps run to whatever level the
/// def allows. It used to clamp at [kMaxBuildingLevel], so a building authored
/// past level 10 kept taking slot steps in the form and silently dropped them
/// — worker slots were the ONLY per-level effect with that limit
/// (BuildingEffect.valueAtLevel never had one).
int effectiveSlots(WorkshopRole role, int level) {
  if (role.slotSteps.isEmpty) return role.slots;
  var s = role.slots;
  for (var l = 2; l <= math.max(1, level); l++) {
    s += role.slotSteps[l] ?? 0;
  }
  return s;
}

/// Output/bonus multiplier at [level]: linear, +N % per level over level 1.
/// At the default +50 %: L1 ×1.0, L2 ×1.5, L3 ×2.0, L4 ×2.5, L5 ×3.0.
///
/// The growth per level is a DIAL since 2026-07-29 (Settlement → Gebäude-Level)
/// — it is the single biggest lever in the economy, and it governs every effect
/// that doesn't author its own factor.
double buildingYieldFactor(int level) =>
    1 + GameTuning.i.raw(Dials.buildingLevelGrowth) * (level - 1);

/// Resource-cost multiplier to build/upgrade TO [level]: geometric ×1.6/level.
/// L1 ×1.0, L2 ×1.6, L3 ×2.56, L4 ×4.1, L5 ×6.55. Costs outrun yield so
/// upgrading is a deliberate trade (space + convenience), not free scaling.
double buildingCostFactor(int level) => math.pow(1.6, level - 1).toDouble();

/// Build-time multiplier to build/upgrade TO [level]: same shape as cost.
double buildingTimeFactor(int level) => math.pow(1.6, level - 1).toDouble();

/// The highest level [def] may reach while the settlement has reached region
/// [regionOrder]. Reads the def's per-region caps
/// ([BuildingDef.maxLevelPerEra]): the level of the highest region key ≤
/// regionOrder — so a persistent building unlocks more levels as the
/// settlement pushes on. Empty map → the [kMaxBuildingLevel] default. A
/// building whose earliest defined cap is a LATER region floors to that
/// earliest cap.
///
/// The AUTHORED number wins (user 2026-07-26). This used to clamp it to
/// [kMaxBuildingLevel], so a def edited to 21 levels in Dev Mode still stopped
/// at 10 in play, with no hint anywhere that the extra levels were being
/// thrown away.
int maxBuildingLevelFor(BuildingDef def, int regionOrder) {
  final m = def.maxLevelPerEra;
  if (m.isEmpty) return kMaxBuildingLevel;
  int? bestEra;
  for (final era in m.keys) {
    if (era <= regionOrder && (bestEra == null || era > bestEra)) bestEra = era;
  }
  if (bestEra != null) return math.max(1, m[bestEra]!);
  final earliest = m.keys.reduce((a, b) => a < b ? a : b);
  return math.max(1, m[earliest]!);
}

// ── Building category (user 2026-07-26) ───────────────────
// Which drawer of the Build menu a building lives in. It used to be DERIVED
// from what a def happened to do (has a wood/stone role → Materials, has
// housing → Housing, else Civic), which meant the menu sorted itself but the
// author could not disagree with it: a Trade Center is civic by that rule
// whatever you think it is, and there was no field to say otherwise.
//
// So it is authored now, on Edit Building → Basis, and the Build menu shows
// exactly these groups. [categoryOfBuilding] still derives one for a def that
// has never been given a category, so the 80-odd bundled buildings keep the
// drawer they were already in until somebody moves them on purpose.
// Labels are ENGLISH because these are the Build menu's tabs — the player
// surface — even though the Dev-Mode form that sets them is German, like every
// other dev screen. Order is the order the tabs appear in, and follows what a
// growing settlement reaches for first.
enum BuildingCategory {
  // Production holds what a settlement makes: the mortar (wood, stone) AND the
  // era goods and gold (user 2026-09-19: "goods kommen in production") — there
  // is no separate Goods drawer any more. A stored 'goods' key still reads, as
  // Production (see [fromId]).
  production('production', 'Production', Icons.forest),
  // "Habitats", not "Housing" (user 2026-08-03): monsters live in ground you
  // have made liveable, not in buildings. The KEY stays 'housing' — it is
  // written to the metadata jsonb and to every existing row.
  housing('housing', 'Habitats', Icons.grass),
  civic('civic', 'Civic', Icons.account_balance),
  military('military', 'Military', Icons.shield),
  // The odd-ones-out (user 2026-07-24): the Castle (auto-placed,
  // unique), Building Plots (expand territory, occupy no space) and Roads
  // (painted, free, unlimited) all work differently from a placed building.
  special('special', 'Special', Icons.hub);

  /// Stable key written to the `metadata` jsonb — renaming a label must never
  /// re-sort authored content.
  final String id;
  final String label;
  final IconData icon;
  const BuildingCategory(this.id, this.label, this.icon);

  static BuildingCategory? fromId(String? id) {
    if (id == null) return null;
    // The retired Goods drawer: authored defs that name it live in Production.
    if (id == 'goods') return production;
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// The drawer [def] belongs in: what its author chose, else the old derivation.
///
/// The fallback is what keeps this change free of a data migration — an
/// un-authored def lands exactly where it has always been, and saving it once
/// in Dev Mode pins it.
///
/// [isRoad] / [isBuildPlot] / [isMainBuilding] OVERRULE the authored category,
/// and that is not a style rule. Those three do not place like a building:
/// tapping a road card enters PAINT mode, a plot claims territory, the hall is
/// auto-placed. Letting a category move one of them into Production put a card
/// that paints roads in among the camps (user 2026-07-26: "wenn ich primitive
/// stone camp bauen will, baut es eine strasse"). Special is where the menu
/// knows they behave differently, so membership in it is a fact about the
/// building, not a preference.
BuildingCategory categoryOfBuilding(BuildingDef def) {
  // Road and Building Plot live in Civic, at its front (user 2026-09-19: "road
  // und building plot sollen bei civic sein, zu vorderst") — the menu sorts them
  // there. The castle stays the one thing in Special.
  if (def.isRoad || def.isBuildPlot) return BuildingCategory.civic;
  if (def.isMainBuilding) return BuildingCategory.special;
  if (def.category != null) return def.category!;
  for (final role in def.workshops) {
    // Mortar, gold and the era goods are all things the settlement makes.
    if (role.resource == 'wood' ||
        role.resource == 'stone' ||
        role.resource == 'gold' ||
        kGoodsDefs.containsKey(role.resource)) {
      return BuildingCategory.production;
    }
  }
  if (def.housingCapacity > 0) return BuildingCategory.housing;
  // Everything else: healing, breeding, crafting, construction crews,
  // training — the settlement's civic fabric.
  return BuildingCategory.civic;
}

// ── Workshop role ─────────────────────────────────────────
// A single work station a building offers. Under the creature-worker economy
// a building produces NOTHING on its own — its output is entirely the sum of
// the civilian stat of the creatures stationed in this role, so the role
// declares WHICH stat it reads and WHAT it produces.
//
// [resource] is either a settlement resource key ('wood', 'stone', 'gold',
// 'fish', 'meat') that gets added to the stockpile, or a pseudo-output
// (WorkshopRole.kConstruction / kCrafting) that feeds a system instead of the
// stockpile — construction advances the active build; crafting will make items
// once that system lands.
// [mult] converts one point of the stat into output-per-hour (raw stats run
// ~10-150, so 0.1 turns a 100-stat worker into ~10 units/h). [slots] caps how
// many creatures can fill THIS role in THIS building.
class WorkshopRole {
  final CreatureStat stat;
  final String resource;
  final double mult;
  final int slots;
  // Per-level output growth (user 2026-07-24), same contract as
  // BuildingEffect.levelFactor: output/stat at level L scales by
  // levelFactor^(L−1), or the global +50%/level curve when null (the default,
  // so existing content is unchanged). See [levelScale].
  final double? levelFactor;

  /// EXPLICIT per-level worker-slot increments (user 2026-07-25): the slot count
  /// at building level L = [slots] (the count at level 1) + Σ of [slotSteps] for
  /// levels 2..L. Authored as absolute amounts per level, mirroring
  /// [BuildingEffect.levelSteps] for housing. Empty = a flat slot count (there is
  /// no automatic growth anymore — see [effectiveSlots]). Keyed by level.
  final Map<int, int> slotSteps;

  /// The post's SEVERAL dials, when one number cannot describe it. Two shapes
  /// use it, and the KEYS say which:
  ///
  ///  • a COMBINED post ([kExpedition], [kCaravan]) — keyed by part name (user
  ///    2026-07-29: "die Effekte exp carry capacity, exp goods und exp speed in
  ///    einem Effekt haben, welchen ich aber separat einstellen kann"). A
  ///    missing or zero entry means that part does nothing, so a dial can be
  ///    turned off without splitting the post again, and [mult] is unused.
  ///
  ///  • a STORE post ([kStorageRoom]) — keyed by RESOURCE ID (user 2026-07-30:
  ///    "Ich muss den output pro worker für jede Ressource einzeln einstellen
  ///    können"). One store holds several goods and they are not worth the same
  ///    room per point: bulk timber and a cut of meat do not fill a shelf alike.
  ///    Here [mult] is the FALLBACK for a resource with no dial of its own — see
  ///    [storageMultFor] — so a store authored with one flat number keeps
  ///    working and only the resources you actually tune leave the pack.
  final Map<String, double> mults;

  const WorkshopRole({
    required this.stat,
    required this.resource,
    this.mult = 0.1,
    this.slots = 1,
    this.levelFactor,
    this.slotSteps = const {},
    this.mults = const {},
  });

  /// The stat a TRIP-AMPLIFIER post authored before the first `logistics` stat
  /// was deleted should read now (user 2026-07-26). Which one it is depends on
  /// the POST, not on the old name: the three amplifiers each read the stat they
  /// actually amplify. A flat rename could not express that, which is why this
  /// lives here rather than in CreatureStat._retiredNames — and why a DB row
  /// still saying `logistics` keeps working instead of falling back to `hp`.
  ///
  /// Scoped to those three resources since 2026-07-30, when `logistics` came
  /// back as the STORES' stat: on any other post the name now means the real
  /// stat again, so a store authored in Dev Mode reads what it says it reads.
  /// The three trip posts keep the translation — their code shape says
  /// speed/carry/gathering anyway (reconcileEffects takes `stat` from the code),
  /// so this only still matters for hand-written rows.
  static CreatureStat _statFor(String? name, String resource) {
    if (name != 'logistics') return CreatureStat.fromName(name);
    return switch (resource) {
      kExpTravel => CreatureStat.speed, // the scout post shortens the trip
      kExpCarry => CreatureStat.carry, // the warehouse raises the load
      kExpGoods => CreatureStat.gathering, // the smokehouse raises the yield
      _ => CreatureStat.logistics, // a real stat again — the stores' own
    };
  }

  /// Parses one `workshop` entry of the `effects` jsonb. Shared by
  /// [BuildingDef.fromDefRow] and the Dev-Mode per-level preview so both read a
  /// role exactly the same way.
  factory WorkshopRole.fromJson(Map<String, dynamic> e) => WorkshopRole(
    stat: _statFor(e['stat'] as String?, e['resource'] as String? ?? 'wood'),
    resource: e['resource'] as String? ?? 'wood',
    mult: (e['mult'] as num?)?.toDouble() ?? 0.1,
    slots: (e['slots'] as num?)?.toInt() ?? 1,
    levelFactor: (e['levelFactor'] as num?)?.toDouble(),
    slotSteps: {
      for (final s in ((e['slotSteps'] as Map?) ?? const {}).entries)
        int.parse(s.key.toString()): (s.value as num).toInt(),
    },
    mults: {
      for (final m in ((e['mults'] as Map?) ?? const {}).entries)
        m.key.toString(): (m.value as num).toDouble(),
    },
  );

  /// Output multiplier at building [level] — the per-role [levelFactor] when
  /// set, else the global level curve (buildingYieldFactor).
  double levelScale(int level) => levelFactor == null
      ? buildingYieldFactor(level)
      : math.pow(levelFactor!, level - 1).toDouble();

  /// Room ONE point of the worker's stat makes for [resource] in a store post:
  /// that resource's own dial when authored, else the flat [mult] (user
  /// 2026-07-30). See [mults].
  double storageMultFor(String resource) => mults[resource] ?? mult;

  /// Room one worker with [stat] points makes for [resource] at building
  /// [level] — the store post's whole formula, in one place.
  double storageRoomFor(String resource, double stat, int level) =>
      stat * storageMultFor(resource) * levelScale(level);

  static const String kConstruction = 'construction';

  /// Makes goods rather than gathering them. This was `kResearch` — the role
  /// drove the research countdown, which no longer exists (winning a tech's
  /// trial unlocks it outright). The string value stays 'research' so existing
  /// `building_defs` rows keep matching their role.
  static const String kCrafting = 'research';

  /// Trains the stationed creatures instead of producing anything: each one
  /// earns kTrainingXpPerHour instead of the kPassiveXpPerHour floor (see
  /// CreaturesController.accruePassiveXp). [stat] is only the slot key the
  /// assignment plumbing requires and [mult] is inert — no stat drives XP,
  /// every creature trains at the same rate.
  static const String kTraining = 'training';

  /// A LEGENDARY-only boost slot (user 2026-07-24): a stationed legendary
  /// multiplies the building's worker-free production by (1 + [mult]) each,
  /// INDEPENDENT of the creature's stats — [stat] is only the assignment slot
  /// key and [slots] caps how many legendaries fit. Special buildings use this;
  /// see SettlementController.workshopPower.
  static const String kLegendaryBoost = 'legendary_boost';

  /// The three CIVIL-SERVICE posts (user 2026-07-25). Each is an ordinary
  /// workshop role — stat × mult × level, summed into workshopPower — whose
  /// output feeds a system instead of the stockpile:
  ///   kHealSpeed  → fraction off healing time (Healing Hut, `medicine`)
  ///   kTradeRate  → fraction off the trade spread (Trade Center, `trade`)
  ///   kExpCarry / kExpTravel / kExpGoods → expedition amplifiers
  ///                (warehouse `carry` / scout post `speed` / smokehouse
  ///                `gathering`) — each reads the stat it amplifies since the
  ///                `logistics` stat was deleted (user 2026-07-26)
  /// They replace the hardcoded tables deleted the same day: a building boosts
  /// these systems only if someone is actually posted there.
  static const String kHealSpeed = 'heal_speed';
  static const String kTradeRate = 'trade_rate';
  static const String kExpCarry = 'exp_carry';
  static const String kExpTravel = 'exp_travel';
  static const String kExpGoods = 'exp_goods';

  /// The CARAVAN amplifiers (user 2026-07-29: "unterscheide expeditions und
  /// karawanen für den Markt"). Same shape as the expedition three, aimed at
  /// the trade run instead — the Caravanserai's two posts:
  ///   kCarCarry  → how much cargo a caravan holds   (`carry`)
  ///   kCarTravel → how long the market road takes   (`speed`)
  ///
  /// Separate keys rather than reusing kExpCarry/kExpTravel, because that is
  /// the whole point: a warehouse must not shorten a trade run, and a scout
  /// post must not widen a caravan's hold.
  static const String kCarCarry = 'car_carry';
  static const String kCarTravel = 'car_travel';

  /// The STORE post (user 2026-07-30: "Die Lagerhäuser können wie die
  /// Produktionsgebäude Monster beherbergen, wobei ihre Punkte in Logistics die
  /// Lagerkapazität definieren") — the Storehouse's and the Gold Vault's, read
  /// from the `logistics` stat that came back with it.
  ///
  /// Unlike every other post, its output is not settlement-wide: room made in a
  /// store is room in THAT store, so it raises the ceiling of each resource that
  /// building's own `storage` effects cover, and nothing else. A logistician in
  /// the Gold Vault does not widen the Storehouse — see
  /// SettlementController.storageCapacity / storageRoomPosted.
  static const String kStorageRoom = 'storage_room';

  /// The COMBINED posts (user 2026-07-29, extended 2026-07-30: "karawansarei
  /// gleich wie scout post"). ONE post: one seat count, one hire list, one row
  /// in the building dialog — and every amplifier that building grants at
  /// once, each with its own dial in Dev Mode.
  ///
  /// The single-purpose roles above stay exactly as they are: a warehouse still
  /// only widens the load and a smokehouse still only raises the yield. These
  /// two are for the buildings whose whole job IS the trip, where splitting one
  /// scout or one drover across several seats only ever meant hiring the same
  /// monster twice over.
  static const String kExpedition = 'expedition';
  static const String kCaravan = 'caravan';

  /// Every combined post's parts, in display order → the single-purpose output
  /// key each one feeds.
  ///
  /// Feeding the SAME keys is what keeps combined posts local: one lands in
  /// exactly the buckets it would have landed in as separate posts, so
  /// SettlementController.expeditionBonuses / caravanBonuses (and everything
  /// downstream) needs no idea that combined posts exist.
  ///
  /// The caravan has no `goods` part on purpose — a trade run's return is
  /// PRICED at send, so a yield multiplier would either be ignored or let the
  /// settlement renegotiate mid-road (see caravanBonuses).
  static const Map<String, Map<String, String>> kCombinedParts = {
    kExpedition: {'carry': kExpCarry, 'goods': kExpGoods, 'travel': kExpTravel},
    kCaravan: {'carry': kCarCarry, 'travel': kCarTravel},
  };

  /// The parts of [resource]'s combined post, or empty for a plain one.
  static Map<String, String> partsOf(String resource) =>
      kCombinedParts[resource] ?? const {};

  /// The stat a combined post's [part] reads — the one it AMPLIFIES, exactly as
  /// the single-purpose posts each do (user 2026-07-29). The role's own [stat]
  /// stays the slot key: it decides which seat a monster holds and how the hire
  /// list is ranked, not what any single part is worth.
  ///
  /// One table for both posts: `carry` is `carry` whether the load is a hunting
  /// party's or a caravan's, and `travel` is `speed` on either road.
  static CreatureStat combinedPartStat(String part) => switch (part) {
    'carry' => CreatureStat.carry, // how much it hauls
    'goods' => CreatureStat.gathering, // how much it finds
    _ => CreatureStat.speed, // how fast it gets there
  };

  /// Whether this post feeds several outputs at once.
  bool get isCombined => kCombinedParts.containsKey(resource);

  /// This post's parts, or empty when it is a plain one.
  Map<String, String> get parts => partsOf(resource);

  /// What ONE worker posted here is worth, per OUTPUT key: `stat × mult ×
  /// level factor`, the single formula every post has used since 2026-07-26.
  ///
  /// A plain post returns one entry, under its own [resource]. A combined post
  /// returns one per part — each read from the stat that part amplifies, each
  /// with that part's own mult — which is what makes "one post, three dials"
  /// work without a second code path in the controller or in any screen.
  ///
  /// [statOf] reads a stat off whoever is posted (CreatureInstance.statValue);
  /// the previews pass a reference stat instead.
  Map<String, double> contribution(
    double Function(CreatureStat) statOf,
    int level,
  ) {
    final f = levelScale(level);
    if (!isCombined) return {resource: statOf(stat) * mult * f};
    return {
      for (final part in parts.entries)
        part.value:
            statOf(combinedPartStat(part.key)) * (mults[part.key] ?? 0) * f,
    };
  }

  /// A BREEDER post (user 2026-07-24): a monster stationed in the Breeding Hut
  /// uses its `breeding` stat to speed the MATINGS running there and earns XP;
  /// it produces no stockpile resource. [slots] caps how many can staff it.
  static const String kBreeding = 'breeding';

  /// A HATCHER post — the same thing for the Hatchery's egg incubations (user
  /// 2026-07-26: "breeding und hatching muss getrennt werden bei den Gebäuden,
  /// da dies zwei unterschiedliche Gebäude sind, allerdings gleich aufgebaut").
  ///
  /// Identical in shape to [kBreeding] and driven by the same `breeding` stat —
  /// only the building it belongs to and the clock it shortens differ. Its own
  /// key so the two can be staffed, capped and tuned apart; a Hatchery that
  /// still authors the old [kBreeding] role keeps working (see
  /// SettlementController.hatchingPower).
  static const String kHatching = 'hatching';

  bool get producesResource =>
      resource != kConstruction &&
      resource != kCrafting &&
      resource != kTraining &&
      resource != kLegendaryBoost &&
      resource != kHealSpeed &&
      resource != kTradeRate &&
      resource != kExpCarry &&
      resource != kExpTravel &&
      resource != kExpGoods &&
      resource != kExpedition &&
      resource != kCaravan &&
      resource != kCarCarry &&
      resource != kCarTravel &&
      resource != kBreeding &&
      resource != kHatching &&
      // Room, not goods: a store's post makes space for wood, it does not make
      // wood (user 2026-07-30).
      resource != kStorageRoom;
}

// ── Game constants ────────────────────────────────────────
// Every number below is a DIAL (Settlement → Energie): they decide the whole
// day's pacing, and pacing is the thing that gets retuned most.
//
// ENERGY IS A POOL THAT STEPS FILL AND TIME EMPTIES (user 2026-09-20:
// "Energie wieder direktes Feedback. Wenn ich Schritte mache, dann soll die
// Energie hochgehen … und es geht wirklich runter auf 0"), replacing the
// 2026-09-14 daily-steps formula:
//
//   * FILLING — [kEnergyFullSteps] (5000) steps take it from 0 to 100 %; the
//     steps after that are worth less, [kEnergyBoostPerThousandSteps] per 1000
//     (5 %), up to the ceiling [kEnergyMaxPercent] (125 %, i.e. 10 000 steps
//     from empty). Steps taken AT the ceiling are lost — they count again the
//     moment the energy has fallen below it ([energyAfterSteps]).
//   * EMPTYING — a steady [kEnergyDrainPerHour], sized so that 100 % lasts
//     [kEnergyFullHours] (24 h) and therefore 125 % lasts 30 h ([energyDrain]).
//   * WHAT IT DOES — every production/construction rate is multiplied by the
//     energy's own fraction (100 % = ×1.0, 125 % = ×1.25), never below the
//     floor [kEnergyFloorMultiplier]: an empty pool slows the settlement, it
//     does not stop it. Nothing here gates an action — see
//     SettlementController.hasEnergy, permanently true.
double get kEnergyFullSteps => GameTuning.i.raw(Dials.energyFullSteps);
double get kEnergyFloorMultiplier =>
    GameTuning.i.raw(Dials.energyFloorMultiplier);
double get kEnergyBoostPerThousandSteps =>
    GameTuning.i.raw(Dials.energyBoostPerThousandSteps);
double get kEnergyMaxBoost => GameTuning.i.raw(Dials.energyMaxBoost);
double get kEnergyFullHours => GameTuning.i.raw(Dials.energyFullHours);

/// What a brand-new (or reset) settlement starts with: one full day, so the
/// first session is not spent crawling at the floor rate.
const double kEnergyStartPercent = 100.0;

/// The ceiling of the pool, in percent (100 + the bonus cap).
double get kEnergyMaxPercent => 100.0 + kEnergyMaxBoost * 100.0;

/// Percent lost per real hour. 0 when the dial is nonsense, so a bad value
/// freezes the pool instead of dividing by zero.
double get kEnergyDrainPerHour =>
    kEnergyFullHours <= 0 ? 0.0 : 100.0 / kEnergyFullHours;

/// The rate multiplier a pool at [percent] runs the settlement at: its own
/// fraction, but never below [kEnergyFloorMultiplier].
double energyMultiplierForPercent(double percent) => math.max(
  kEnergyFloorMultiplier,
  percent.clamp(0.0, kEnergyMaxPercent) / 100,
);

/// The pool after [steps] more steps, starting from [percent].
///
/// Piecewise, so the numbers a player is promised come out exactly: below 100 %
/// a step is worth 100 / [kEnergyFullSteps] percent; above it,
/// [kEnergyBoostPerThousandSteps] × 100 / 1000. Whatever does not fit under
/// [kEnergyMaxPercent] is dropped — it does NOT wait for later.
double energyAfterSteps(double percent, int steps) {
  final ceiling = kEnergyMaxPercent;
  var p = percent.clamp(0.0, ceiling);
  var left = steps.toDouble();
  if (left <= 0) return p;

  final lowPerStep = kEnergyFullSteps <= 0 ? 0.0 : 100.0 / kEnergyFullSteps;
  if (p < 100 && lowPerStep > 0) {
    final room = math.min(100.0, ceiling) - p;
    final use = math.min(left, room / lowPerStep);
    p += use * lowPerStep;
    left -= use;
  }
  final highPerStep = kEnergyBoostPerThousandSteps * 100.0 / 1000.0;
  if (left > 0 && p >= 100 && p < ceiling && highPerStep > 0) {
    final use = math.min(left, (ceiling - p) / highPerStep);
    p += use * highPerStep;
  }
  return p.clamp(0.0, ceiling);
}

/// What [hours] of running down do to a pool at [startPercent]: the pool at the
/// end, and the EFFECTIVE hours of work the settlement got done meanwhile —
/// the multiplier integrated over the window, because it is falling the whole
/// time (a night away is not priced at the rate you left with).
///
/// While the pool is above the floor the rate is the pool's own fraction and
/// falls linearly, so its integral is closed-form; once the pool is at or under
/// the floor (or empty) the rest of the window runs at the floor rate.
({double endPercent, double effectiveHours}) energyDrain(
  double startPercent,
  double hours,
) {
  if (hours <= 0) return (endPercent: startPercent, effectiveHours: 0.0);
  final drain = kEnergyDrainPerHour;
  final floor = kEnergyFloorMultiplier;
  final start = startPercent.clamp(0.0, kEnergyMaxPercent);
  final floorPct = floor * 100.0;

  // No drain: a constant rate for the whole window.
  if (drain <= 0) {
    return (
      endPercent: start,
      effectiveHours: hours * energyMultiplierForPercent(start),
    );
  }

  // Phase A: from [start] down to the floor, rate = pct / 100.
  final tA = start > floorPct
      ? math.min(hours, (start - floorPct) / drain)
      : 0.0;
  final effA = (start * tA - drain * tA * tA / 2) / 100.0;
  // Phase B: at the floor rate for whatever is left of the window.
  final effB = (hours - tA) * floor;
  return (
    endPercent: math.max(0.0, start - drain * hours),
    effectiveHours: effA + effB,
  );
}

/// Max simultaneous active construction sites, before any building adds more.
int get kBaseBuildSlots => GameTuning.i.count(Dials.baseBuildSlots);

/// DEV ONLY — how much the isDev grant button hands out, and the floor a DEV
/// reset restores the yard to (user 2026-07-26: "wenn ich auf plus
/// Gold/holz/stein drücke, will ich, dass dies bleibt").
///
/// One constant for both so they can't drift: a reset never leaves a dev
/// account with less than one press of the button. It touches nothing a real
/// player sees — SettlementService.resetSettlement only applies it when
/// `devFloat` is set, and only ever RAISES the starting bill.
const double kDevResetFloat = 1000.0;

// ── Construction points (user 2026-07-24, reworked 2026-07-26) ─────────────
// Build speed is measured in plain CONSTRUCTION POINTS, all equal. Every source
// is authored in that one unit and counts 1:1 — a point is a point:
//   points = Σ (stationed builder's `construction` stat × role mult × level)
//          + Σ (each building's passive `production`/`construction` effect)
// The role's `mult` is the only weighting dial ("Bau-Punkte pro Statpunkt": at
// 10, one point of the construction stat is worth 10 build points).
//
// Points then buy a PERCENT OFF the authored build time — the same currency
// every other duration effect in this game is stated in. There is NO points-to-
// seconds exchange rate anymore, and no anchor value a settlement has to reach
// first: what a def calls its Bauzeit IS the time it takes with nobody on site,
// and builders cut into it (user 2026-07-26). Every active site builds at the
// full rate (no split).
//
// The curve is [breedingTimeCut]'s shape and for the same reason (user
// 2026-07-26, on the breeding cap): a hard ceiling would make levelling the
// builder's hut pointless past a couple of workers. Diminishing but uncapped —
// −50 % at [kBuildPointsForHalfTime], −80 % at ×4 that, −90 % at ×9 — so the
// time approaches zero without reaching it and a build always has a real timer.
double get kBuildPointsForHalfTime =>
    GameTuning.i.raw(Dials.buildPointsForHalfTime);

/// Fraction of a building's authored construction time that [points] remove.
/// 0 with nobody building, rising toward 1 with diminishing returns.
double buildTimeCut(double points) =>
    points <= 0 ? 0 : points / (points + kBuildPointsForHalfTime);

/// [points] as the player actually cares about them: how much build time they
/// take off ("−23 % time"), not the abstract points behind it (user
/// 2026-09-28: "+n Points bringt dem User nichts, er will sehen, wie viel
/// Zeitreduktion die Monster bringen"). One decimal below 10 %, where a whole
/// number would round a single monster's share to nothing.
String buildPointsLabel(double points) {
  final pct = buildTimeCut(points) * 100;
  if (pct <= 0) return '0 % time';
  final text = pct >= 10
      ? pct.round().toString()
      : pct.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '−$text % time';
}

/// How many build-seconds one real second of work is worth at [points] — the
/// inverse of what's left of the authored time. 1.0 (authored time) at zero
/// points; each point adds a flat 1/[kBuildPointsForHalfTime] on top, which is
/// exactly what makes the CUT above flatten out.
double buildSpeedFromPoints(double points) =>
    points <= 0 ? 1.0 : 1 + points / kBuildPointsForHalfTime;

/// Points needed to bring an authored build time down to [cut] (0…1) — the
/// inverse of [buildTimeCut], for "I want −80 %, what do I need?" questions.
/// null for a cut of 1 or more, which no finite number of points expresses.
double? buildPointsForCut(double cut) {
  if (cut <= 0) return 0;
  if (cut >= 1) return null;
  return kBuildPointsForHalfTime * cut / (1 - cut);
}

/// Build-queue slots before any building grants some — 0 keeps the queue
/// locked until something opens it.
int get kBaseQueueSlots => GameTuning.i.count(Dials.baseQueueSlots);

// ── TEN TIMES THE LAND (user 2026-08-06) ──
// 200 x 120 = 24 000 cells, against 60 x 40 = 2 400. Ten times the area, and
// the proportions are kept so the diamond keeps its shape on screen.
//
// The grid is a CAMERA-side number in the same sense the projection is: a
// building stores gridX/gridY and nothing else, so growing the map cannot
// invalidate a saved row — every old coordinate still names the same cell it
// always did. What DOES move is anything defined relative to the map's middle,
// and the starting zone below is exactly that: it is centred on the grid, so an
// existing settlement built around the old centre (30, 20) now sits in the
// far north-west of a much larger world with its buildable zone somewhere else
// entirely. That needs a migration before this ships to anyone who has played.
const kGridCols = 200;
const kGridRows = 120;
const kCellSize = 12.0;

// Starting buildable territory: a zone centred on the map, containing the
// Castle. 20×20 (user request 2026-07-17: "mache das Anfangsgebiet
// 4x so gross" — 4× the former 10×10 area): the era-I roster now fits
// without expanding first, so Expansion/Building Plots are about the LATER
// eras' space needs rather than era I's squeeze. Still a small fraction
// (~17%) of the 60×40 map, so expanding outward from the edge (see
// isBuildPlot / touchesBuildableRegion) stays meaningful content.
const kInitialPlotX = 20;
const kInitialPlotY = 10;
const kInitialPlotSize = 20;

/// Top-left cell of the auto-placed Castle — centred in the starting
/// plot, derived from the hall's OWN footprint.
///
/// SettlementService used to hardcode `(kInitialPlotSize - 3) ~/ 2` here with
/// a "castle is 3x3" comment. It drifted the moment the def wasn't 3x3
/// anymore and the hall silently sat off-centre. Don't reintroduce a literal.
int get kMainHallStartX =>
    kInitialPlotX + (kInitialPlotSize - _mainHallDef.gridW) ~/ 2;
int get kMainHallStartY =>
    kInitialPlotY + (kInitialPlotSize - _mainHallDef.gridH) ~/ 2;

/// Live def when loaded, bundled fallback before that — placement happens in
/// getOrCreate, which runs BEFORE GameDefsController().load().
BuildingDef get _mainHallDef =>
    kBuildingDefs['castle'] ?? kFallbackBuildingDefs['castle']!;

/// Live def when loaded, bundled fallback before that — same reasoning as
/// [_mainHallDef].
BuildingDef get _healingHutDef =>
    kBuildingDefs['healing_hut'] ?? kFallbackBuildingDefs['healing_hut']!;

// ── Tutorial's own fixed spot for the Healing Hut + its road ──────────────
// One road cell then the hut, stacked directly off the Castle's SOUTH edge —
// in FRONT of it, from the camera's own point of view — both locked to the
// SAME cell for every account (user 2026-09-30: "gib die Position für das
// Healing hut vor, so dass ich immer genau am gleichen Ort bauen muss und es
// auch nicht schieben kann" / the same ask for the road; user 2026-10-01:
// "eine andere Position beim ersten Platzieren finden, dass das Healing Hut
// vor dem Castle ist" — the NORTH spot this used to be put the hut BEHIND
// the Castle on screen, since +y runs further from the viewer than the
// Castle's own near corner; see iso_grid.dart's projection comment).
//
// SOUTH, not east: the Castle is 10×10 inside a 20×20 starting plot, so it
// clears only (20-10)/2 = 5 cells on every side — enough room for the
// Healing Hut's 4-tall footprint plus the road's own cell (5 exactly) only
// on the sides that measure the Castle's SHORT way. East measures the
// Castle's own width, so "one road cell, then the hut" put the hut's far
// edge one cell past the plot's own boundary — unbuildable ground the
// first version of this shipped with (user 2026-09-30 screenshot: "wird
// aktuell ausserhalb des Landes angezeigt und kann daher nicht gebaut
// werden"). South has exactly the clearance both footprints need, not a
// cell more (same as north, since the Castle sits centred in the plot), so
// nothing here is safe to change without re-deriving it from the actual
// footprints again — never reintroduce a literal offset.
int get kTutorialRoadX =>
    kMainHallStartX + _mainHallDef.gridW ~/ 2;
int get kTutorialRoadY => kMainHallStartY + _mainHallDef.gridH;
int get kTutorialHealingHutX =>
    kTutorialRoadX - _healingHutDef.gridW ~/ 2;
int get kTutorialHealingHutY => kTutorialRoadY + 1;

// ── Building effect (dev-mode authorable, per era) ─────────
// The rich, per-era effect palette that lives in the `effects` jsonb alongside
// workshops and the legacy buildSpeed/population/queueSlots bonuses. Each entry
// is active once the settlement reaches era [era] (1 = from the start); for a
// given (type,key) the HIGHEST reached era wins (an override, not a sum), so a
// persistent building can grow stronger each era. See BuildingDef.effectAt.
//
// type      | key                                   | value
// ----------|---------------------------------------|--------------------------
// production| a resource id (wood/stone/gold/goods) | units/hour, worker-free
// resource  | wood/stone/gold/food/all              | +% to that production
// expedition| carry/travel/goods                    | +fraction to trips
// expeditionSlots | ''                              | +N concurrent trips
// huntOptions | ''                                  | +N longer hunt variants
// heal      | speed/cost                            | −fraction to heal time/cost
// housing   | ''                                    | absolute housing capacity
// trade     | ''                                    | % off the trade spread
class BuildingEffect {
  final String type;
  final String key;
  final double value;
  final int era;
  // Per-level growth of THIS effect (user 2026-07-24): the value at building
  // level L = [value] × levelFactor^(L−1). null (the default) means "use the
  // settlement's global +50%/level curve" (buildingYieldFactor) — so existing
  // content and hand-written rows keep their exact behaviour, and only an
  // explicitly authored factor overrides it. See [levelScale] / effectAt.
  final double? levelFactor;

  /// EXPLICIT per-level increments (user 2026-07-24, housing): the value at
  /// building level L = [value] (the start capacity at level 1) + Σ of
  /// [levelSteps] for levels 2..L. Authored as absolute amounts per level, not a
  /// percentage. When non-empty this OVERRIDES [levelFactor]/the global curve,
  /// so a house can grow by exact seats at exact levels. Keyed by level.
  final Map<int, double> levelSteps;

  const BuildingEffect({
    required this.type,
    this.key = '',
    required this.value,
    this.era = 1,
    this.levelFactor,
    this.levelSteps = const {},
  });

  /// Parses one entry of the `effects` jsonb. `key` names the resource/target;
  /// `target` and `resource` are accepted as aliases for hand-written rows.
  ///
  /// Shared by [BuildingDef.fromDefRow] and the Dev-Mode effects editor's
  /// per-level preview, so the preview can never disagree with what the app
  /// actually loads.
  factory BuildingEffect.fromJson(Map<String, dynamic> e) => BuildingEffect(
    type: e['type'] as String? ?? '',
    key: (e['key'] ?? e['target'] ?? e['resource'] ?? '') as String,
    value: (e['value'] as num?)?.toDouble() ?? 0,
    era: (e['era'] as num?)?.toInt() ?? 1,
    levelFactor: (e['levelFactor'] as num?)?.toDouble(),
    levelSteps: {
      for (final s in ((e['levelSteps'] as Map?) ?? const {}).entries)
        int.parse(s.key.toString()): (s.value as num).toDouble(),
    },
  );

  /// The per-era palette types [BuildingDef.fromDefRow] keeps as BuildingEffects
  /// (everything except `workshop`, which becomes a [WorkshopRole], and the
  /// legacy `bonus`, which folds into the scalar fields).
  ///
  /// A type missing here is silently DROPPED on load — which is exactly how the
  /// `trade` effect went missing from DB rows when it was added (2026-07-25).
  static const paletteTypes = {
    'production',
    'resource',
    'expedition',
    'expeditionSlots',
    // The caravan pair (user 2026-07-29). Missing here they would load as
    // nothing — which is the very drop this list exists to prevent.
    'caravan',
    'caravanSlots',
    // How many of the LONGER hunt variants this building opens (user
    // 2026-07-26: "Expeditionen werden an scout geknüpft, jagdt an scout").
    // Hunts used to be unlocked by a feature id earned on the path; a scout
    // post is the thing that plausibly finds longer trails, so it is the thing
    // that grants them.
    'huntOptions',
    'heal',
    'healSlots',
    'healQueue',
    'housing',
    // NO 'xp' (user 2026-07-30: "Jedes Gebäude gibt genau gleich viel EP") —
    // every building with a work post pays one settlement-wide rate, so a
    // per-building XP row has nothing left to say and is dropped on load.
    // See XpConfig.workPerHour / CreaturesController.xpRatePerHour.
    'breeding',
    'hatching',
    'queueSlots',
    'buildSlots',
    'trade',
    // How many items the Workshop makes AT ONCE, and how many may wait for
    // a bench (user 2026-07-30). Same pair, same shape as the Healing Hut's.
    'craftSlots',
    'craftQueue',
    // How much of ONE resource the settlement can hold (user 2026-07-30:
    // "jede Ressource will ich einzeln pro Level einstellen können"), keyed
    // by the resource id. Above it, production simply stops.
    'storage',
  };

  /// Multiplier applied to [value] at building [level]. Honours a per-effect
  /// [levelFactor] when set, else falls back to the global level curve.
  double levelScale(int level) => levelFactor == null
      ? buildingYieldFactor(level)
      : math.pow(levelFactor!, level - 1).toDouble();

  /// Like [levelScale] but returns 1.0 when no [levelFactor] is set — for
  /// effects the runtime historically did NOT level-scale (expeditionSlots,
  /// heal, resource): they stay flat unless a factor is explicitly authored.
  double levelScaleExplicit(int level) =>
      levelFactor == null ? 1.0 : math.pow(levelFactor!, level - 1).toDouble();

  /// The effect's value AT building [level]. Uses the explicit [levelSteps]
  /// ladder when authored (start capacity + the increments up to this level),
  /// else the multiplicative [levelScale]. Backward-compatible: with no steps
  /// it equals `value × levelScale(level)`, exactly what effectAt used before.
  double valueAtLevel(int level) {
    if (levelSteps.isNotEmpty) {
      var v = value;
      for (var l = 2; l <= level; l++) {
        v += levelSteps[l] ?? 0;
      }
      return v;
    }
    return value * levelScale(level);
  }
}

// ── Building definition ───────────────────────────────────
class BuildingDef {
  final String id;
  final String name;
  // Public URL of a Dev-Mode-uploaded PNG (Supabase Storage bucket
  // 'building-images', see widgets/building_icon.dart for rendering with a
  // placeholder fallback when null — buildings have no emoji anymore).
  final String? imageUrl;

  // ── WHERE THE BASE IS IN THE IMAGE (user 2026-08-01) ──
  // "Ich habe das Bild jetzt als Quadrat, aber die Grundfläche ist natürlich
  //  kleiner und weiter vorne … So ist das Gebäude zu weit hinten"
  //
  // The map used to assume every sprite's ground base filled the image's width
  // and touched its bottom edge. Generated art never does: it comes back square,
  // with the building somewhere inside it and air all round. The app then
  // matched the IMAGE to the tiles instead of the BASE, so the building sat
  // back and to one side of the ground it stands on.
  //
  // Three numbers fix it, and they are properties of the picture, not of the
  // building — which is why they live next to the URL and are edited wherever
  // the PNG is uploaded:
  //
  //   [artBaseWidth]  how much of the image's WIDTH the base spans (0..1)
  //   [artAnchorX]    where the base's bottom point sits across the image
  //   [artAnchorY]    …and down it
  //
  // The defaults are the old assumption exactly (1.0, 0.5, 1.0), so a def that
  // says nothing behaves as before.

  /// The base's width as a fraction of the image's. 0.62 = the base covers 62 %
  /// of the picture and the rest is air.
  final double artBaseWidth;

  // (see [kChimneyAnchor] below for where a building's smoke comes out)

  /// Where the base's bottom (south) point sits across the image, and how far
  /// above its bottom edge — both as fractions of the image's WIDTH.
  final double artAnchorX;
  final double artLift;

  final Color color;
  final int gridW;
  final int gridH;
  final Map<String, double>
  resourceCost; // keys: 'wood', 'stone' (no food — food is now a good)
  final double constructionHours;
  // Regions this building is buildable in — still `'era_N'` id strings
  // (renaming them would mean a data migration; only the mechanic named
  // "era" is gone, not this internal identifier — see [_regionOrderOfId]).
  // Empty = available in every region (used by castle/road, which must
  // always be placeable). A building can list several non-contiguous
  // regions.
  final List<String> eraIds;
  final bool isMainBuilding;
  final bool isUnique;
  final bool isRoad;
  // Marks territory as buildable when complete, instead of being a structure
  // itself — doesn't occupy space (see SettlementController._isAreaFreeImpl).
  final bool isBuildPlot;
  final String? requiredTechId;
  // Housing capacity: how many CREATURES this building can shelter. Captured
  // monsters ARE the population now, and every one you own occupies one slot
  // (uniform, regardless of rarity). When the settlement's total capacity is
  // full, no new creature can be caught/hatched/adopted. (DB column stays
  // named `population` for backward-compat — see fromDefRow/toDefRow.)
  final int population;
  int get housingCapacity => population;

  /// Whether this building gives monsters a ROOF at [eraOrder] — a per-era
  /// `housing` effect, or failing that the flat population column.
  ///
  /// The exact condition GameEngine.housingCapacity sums by, as a question:
  /// "is this a dwelling?" Asked by the building dialog, which puts the
  /// Population door on every one of them (user 2026-07-30: "Population über
  /// jedes Haus aufrufbar machen"). Keyed on what the building DOES rather than
  /// a list of ids, so a later era's pen gets the door by being a pen.
  bool sheltersMonsters(int eraOrder) => hasEffect('housing', eraOrder)
      ? effectAt('housing', '', eraOrder, level: 1) > 0
      : housingCapacity > 0;
  // Work stations this building offers. Empty = not a workshop (pure housing/
  // infrastructure). Each role is staffed by specific creatures whose civilian
  // stat drives its output — see WorkshopRole. Replaces the old
  // workerRequirement/maxLaborers/perWorker economy entirely.
  final List<WorkshopRole> workshops;
  // Unconditional, settlement-wide bonuses (always active while complete + connected).
  final double buildSpeedBonus; // e.g. 0.30 = +30% construction speed
  final double
  populationBonus; // e.g. 0.15 = +15% total population from all housing
  // Extra build QUEUE slots this building grants once complete + connected
  // (on top of kBaseQueueSlots/tech-granted slots) — see
  // GameEngine.buildingsQueueSlotsBonusTotal.
  final int queueSlotsBonus;
  // Max number of this building allowed per settlement (0 = unlimited).
  final int maxCount;

  /// Which Build-menu drawer this building sits in (user 2026-07-26). Null =
  /// never authored, so [categoryOfBuilding] derives one from what the def does
  /// — read it through that function, never this field, or an un-authored
  /// building falls out of the menu entirely.
  final BuildingCategory? category;

  // ── Per-era / scaling tunables (dev-mode authored via the `metadata` jsonb
  //    column, migration 0017) ──
  // Max UPGRADE level reachable, keyed by era ORDER: {1: 3, 3: 5, 8: 10} caps
  // the building at level 3 until era III, 5 until era VIII, 10 from VIII on.
  // Empty = the flat kMaxBuildingLevel. THIS is how a civic building (Healing
  // Hut, Workshop …) that PERSISTS across eras unlocks higher levels as the
  // settlement ascends, instead of being replaced by a successor. See
  // maxBuildingLevelFor.
  final Map<int, int> maxLevelPerEra;
  // Per-level cost/time growth (default 1.6 = the old global factor). Cost/time
  // to build/upgrade TO level L = base × factor^(L−1). See resourceCostAt /
  // constructionSecondsAt.
  final double costFactor;
  final double timeFactor;
  // Per-ERA build resources (user 2026-07-24): {1: {'wood': 100}, 2: {'frame':
  // 40, 'clay': 16}, …}. Each era key names the resources an upgrade costs while
  // the building is IN that era's level band (see maxLevelPerEra), and the
  // amounts are the cost at that band's FIRST level; [costFactor] scales them up
  // per level within the band. This is how a building that persists across eras
  // is paid in each era's own materials. Empty = the flat [resourceCost] ×
  // factor. Stored in the `metadata` jsonb bag alongside maxLevelPerEra.
  final Map<int, Map<String, double>> costPerEra;
  // The rich per-era effect palette (production/resource/expedition/heal/…).
  // The legacy buildSpeed/population/queueSlots bonuses stay in their own scalar
  // fields above; everything else the dev-mode editor writes lands here.
  final List<BuildingEffect> effects;

  /// Quarter turns this def is turned by (user 2026-11-03: "Gebäude um 90°
  /// drehen"). Always 0 for a def from the roster; a placed building that is
  /// turned reads its def through [placedDefOf], which hands back
  /// [rotated] — the same building with the footprint's sides swapped on an
  /// odd turn and its pictures taken from the matching side ([artId]).
  final int rotation;

  const BuildingDef({
    required this.id,
    required this.name,
    this.imageUrl,
    this.artBaseWidth = 1.0,
    this.artAnchorX = 0.5,
    this.artLift = 0.0,
    required this.color,
    required this.gridW,
    required this.gridH,
    this.resourceCost = const {},
    this.constructionHours = 0,
    this.eraIds = const [],
    this.isMainBuilding = false,
    this.isUnique = false,
    this.isRoad = false,
    this.isBuildPlot = false,
    this.requiredTechId,
    this.population = 0,
    this.workshops = const [],
    this.buildSpeedBonus = 0,
    this.populationBonus = 0,
    this.queueSlotsBonus = 0,
    this.maxCount = 1,
    this.category,
    this.maxLevelPerEra = const {},
    this.costFactor = 1.6,
    this.timeFactor = 1.6,
    this.costPerEra = const {},
    this.effects = const [],
    this.rotation = 0,
  });

  /// The same building with the numbers the RENDERER measured — footprint and
  /// where the picture's base sits in it — and nothing else changed.
  ///
  /// Named, narrow and deliberate, exactly like [withEffects] and for the same
  /// reason: a general copyWith is a second way to rewrite a def, and a second
  /// way is a second chance for two of them to disagree. This one exists for
  /// Dev Mode's "Vom Modell übernehmen", which has to touch five fields on a
  /// LIVE row and must not touch the forty it did not measure.
  ///
  /// image_url goes to null on purpose: a bundled picture already beats it
  /// (see data/building_art.dart), so a URL left behind is a value that looks
  /// live and is never drawn.
  BuildingDef withModelArt({
    required int gridW,
    required int gridH,
    required double artBaseWidth,
    required double artAnchorX,
    required double artLift,
  }) => BuildingDef(
    id: id,
    name: name,
    imageUrl: null,
    artBaseWidth: artBaseWidth,
    artAnchorX: artAnchorX,
    artLift: artLift,
    color: color,
    gridW: gridW,
    gridH: gridH,
    resourceCost: resourceCost,
    constructionHours: constructionHours,
    eraIds: eraIds,
    isMainBuilding: isMainBuilding,
    isUnique: isUnique,
    isRoad: isRoad,
    isBuildPlot: isBuildPlot,
    requiredTechId: requiredTechId,
    population: population,
    workshops: workshops,
    buildSpeedBonus: buildSpeedBonus,
    populationBonus: populationBonus,
    queueSlotsBonus: queueSlotsBonus,
    maxCount: maxCount,
    category: category,
    maxLevelPerEra: maxLevelPerEra,
    costFactor: costFactor,
    timeFactor: timeFactor,
    costPerEra: costPerEra,
    effects: effects,
  );

  /// The same building with its EFFECTS replaced — everything else identical.
  ///
  /// The one use is [_buildRoster] stamping each def with its authored entry
  /// from kBuildingEffects (user 2026-07-29: the effect SHAPE belongs in the
  /// repo, the numbers in Dev Mode). Deliberately not a general copyWith: a
  /// second way to rewrite a def is a second way for two of them to disagree.
  BuildingDef withEffects(BuildingEffects e) => BuildingDef(
    id: id,
    name: name,
    imageUrl: imageUrl,
    artBaseWidth: artBaseWidth,
    artAnchorX: artAnchorX,
    artLift: artLift,
    color: color,
    gridW: gridW,
    gridH: gridH,
    resourceCost: resourceCost,
    constructionHours: constructionHours,
    eraIds: eraIds,
    isMainBuilding: isMainBuilding,
    isUnique: isUnique,
    isRoad: isRoad,
    isBuildPlot: isBuildPlot,
    requiredTechId: requiredTechId,
    population: population,
    workshops: e.workshops,
    buildSpeedBonus: buildSpeedBonus,
    populationBonus: populationBonus,
    queueSlotsBonus: queueSlotsBonus,
    maxCount: maxCount,
    category: category,
    maxLevelPerEra: maxLevelPerEra,
    costFactor: costFactor,
    timeFactor: timeFactor,
    costPerEra: costPerEra,
    effects: e.effects,
  );

  /// The id its PICTURES are keyed by: `<id>` unturned, `<id>_r1` .. `_r3`
  /// turned — art box, chimney, moving parts, entrance and the asset files
  /// all follow it (tool/blender/make_building.py renders every turn).
  String get artId => rotation == 0 ? id : '${id}_r$rotation';

  /// Whether this building can be turned: only a rebuilt model has the other
  /// three sides rendered.
  bool get canRotate => kModelFootprint.containsKey('${id}_r1');

  /// This building turned by [quarterTurns] (clockwise on the map). An odd
  /// turn swaps [gridW] and [gridH]; nothing else about it changes.
  BuildingDef rotated(int quarterTurns) {
    final r = quarterTurns % 4;
    if (r == rotation) return this;
    final odd = (r - rotation).isOdd;
    return BuildingDef(
      id: id,
      name: name,
      imageUrl: imageUrl,
      artBaseWidth: artBaseWidth,
      artAnchorX: artAnchorX,
      artLift: artLift,
      color: color,
      gridW: odd ? gridH : gridW,
      gridH: odd ? gridW : gridH,
      resourceCost: resourceCost,
      constructionHours: constructionHours,
      eraIds: eraIds,
      isMainBuilding: isMainBuilding,
      isUnique: isUnique,
      isRoad: isRoad,
      isBuildPlot: isBuildPlot,
      requiredTechId: requiredTechId,
      population: population,
      workshops: workshops,
      buildSpeedBonus: buildSpeedBonus,
      populationBonus: populationBonus,
      queueSlotsBonus: queueSlotsBonus,
      maxCount: maxCount,
      category: category,
      maxLevelPerEra: maxLevelPerEra,
      costFactor: costFactor,
      timeFactor: timeFactor,
      costPerEra: costPerEra,
      effects: effects,
      rotation: r,
    );
  }

  double get constructionSeconds => constructionHours * 3600;

  /// The region ORDER this building first becomes buildable in (min of
  /// [eraIds]; 1 when it lists none — the always-available structures).
  int get startRegionOrder {
    if (eraIds.isEmpty) return 1;
    final orders = eraIds.map(_regionOrderOfId).whereType<int>();
    return orders.isEmpty ? 1 : orders.reduce(math.min);
  }

  /// The region ORDER whose level band contains [level]. Bands are
  /// contiguous — region R covers (prevMax, maxLevelPerEra[R]] — so a
  /// persistent building is paid in each region's own materials as it
  /// climbs. Empty caps → [startRegionOrder].
  int regionOrderForLevel(int level) {
    if (maxLevelPerEra.isEmpty) return startRegionOrder;
    final regions = maxLevelPerEra.keys.toList()..sort();
    for (final r in regions) {
      if (level <= maxLevelPerEra[r]!) return r;
    }
    return regions.last;
  }

  /// The first (lowest) level of region [order]'s band — 1 for the earliest
  /// capped region, and the level after the previous region's cap otherwise.
  int firstLevelOfRegion(int order) {
    if (maxLevelPerEra.isEmpty) return 1;
    final regions = maxLevelPerEra.keys.toList()..sort();
    var prevMax = 0;
    for (final e in regions) {
      if (e == order) return prevMax + 1;
      prevMax = maxLevelPerEra[e]!;
    }
    return 1;
  }

  /// Value of the [type]/[key] effect active in era [eraOrder] — the highest-era
  /// entry with era ≤ eraOrder wins (a per-era override, not a sum). 0 if none.
  ///
  /// Pass [level] to also apply the building-level scaling: the winning effect's
  /// own [BuildingEffect.levelScale] (its per-effect factor, or the global level
  /// curve when unset). Callers that already multiply by buildingYieldFactor
  /// themselves must pass [level] here INSTEAD of doing that, or the level
  /// scaling is double-counted.
  double effectAt(String type, String key, int eraOrder, {int? level}) {
    final best = effectEntry(type, key, eraOrder);
    if (best == null) return 0;
    return level == null ? best.value : best.valueAtLevel(level);
  }

  /// The winning [type]/[key] effect in era [eraOrder] (highest era ≤ eraOrder),
  /// or null. Sites that currently apply NO level scaling use this so an
  /// unset [BuildingEffect.levelFactor] stays unscaled, while an authored factor
  /// still takes effect via [BuildingEffect.levelScaleExplicit].
  BuildingEffect? effectEntry(String type, String key, int eraOrder) {
    BuildingEffect? best;
    int bestEra = -1;
    for (final e in effects) {
      if (e.type == type &&
          e.key == key &&
          e.era <= eraOrder &&
          e.era > bestEra) {
        bestEra = e.era;
        best = e;
      }
    }
    return best;
  }

  /// Whether any [type] effect is active in era [eraOrder] (e.g. a housing
  /// override exists at all, so 0 can be distinguished from "unset").
  bool hasEffect(String type, int eraOrder) =>
      effects.any((e) => e.type == type && e.era <= eraOrder);

  /// How many jobs of [type] may run at once in this building at [level] (user
  /// 2026-07-24) — from a `breeding` / `hatching` effect, level-scaled. 0 when
  /// unset (the building runs no jobs of its own).
  ///
  /// [type] since 2026-07-26: matings and incubations are separate buildings
  /// with separate caps, so they are separate effects too.
  int concurrentJobsAt(
    int level, {
    int eraOrder = 99,
    String type = 'breeding',
  }) => effectAt(type, '', eraOrder, level: level).round();

  /// How many treatments this building can run at once at [level] (user
  /// 2026-07-25) — from a `healSlots` effect, level-scaled via its explicit
  /// per-level steps (or factor). 0 when unset; see SettlementController's
  /// healCapacity, where "no building authored any" means unlimited.
  int healSlotsAt(int level, {int eraOrder = 99}) =>
      effectAt('healSlots', '', eraOrder, level: level).round();

  /// How many monsters may WAIT for a treatment at [level] (user 2026-07-27) —
  /// from a `healQueue` effect. 0 when unset; see SettlementController's
  /// healQueueCapacity, where "no building authored any" means unlimited.
  ///
  /// Separate from [healSlotsAt] because they are separate decisions: the slots
  /// are how fast the hut works, the queue is how many you may line up for it.
  int healQueueAt(int level, {int eraOrder = 99}) =>
      effectAt('healQueue', '', eraOrder, level: level).round();

  /// How many lessons the Combat School can run at once at [level] (user
  /// 2026-09-05) — from a `trainSlots` effect, level-scaled. 0 when unset;
  /// see SettlementController.trainCapacity, where "no building authored
  /// any" means unlimited.
  int trainSlotsAt(int level, {int eraOrder = 99}) =>
      effectAt('trainSlots', '', eraOrder, level: level).round();

  /// How many monsters may WAIT for a lesson at [level] — from a
  /// `trainQueue` effect. 0 when unset; see SettlementController.
  /// trainQueueCapacity.
  int trainQueueAt(int level, {int eraOrder = 99}) =>
      effectAt('trainQueue', '', eraOrder, level: level).round();

  /// Percentage points off the trade spread this building grants at [level]
  /// (user 2026-07-25) — from a `trade` effect, level-scaled. 0 when unset, so
  /// only a Trade Center improves rates. See SettlementController.tradeDiscount,
  /// which turns this into the 0..kMaxTradeDiscount fraction the math takes.
  double tradePercentAt(int level, {int eraOrder = 99}) =>
      effectAt('trade', '', eraOrder, level: level);

  /// Extra build-queue slots this building grants at [level] from a `queueSlots`
  /// effect, level-scaled. 0 when unset (legacy content uses the flat
  /// [queueSlotsBonus] scalar instead). See GameEngine.buildingsQueueSlotsBonusTotal.
  int queueSlotsAt(int level, {int eraOrder = 99}) =>
      effectAt('queueSlots', '', eraOrder, level: level).round();

  /// Extra SIMULTANEOUS construction sites this building grants at [level] from
  /// a `buildSlots` effect (user 2026-07-25), level-scaled. On top of
  /// kBaseBuildSlots + tech-granted slots; 0 when unset. See
  /// GameEngine.buildingsBuildSlotsBonusTotal / SettlementController.maxBuildSlots.
  int buildSlotsAt(int level, {int eraOrder = 99}) =>
      effectAt('buildSlots', '', eraOrder, level: level).round();

  /// The distinct [type] keys this building defines — for iterating every
  /// resource a `production`/`resource` effect covers.
  Set<String> effectKeys(String type) => {
    for (final e in effects)
      if (e.type == type) e.key,
  };

  /// Resource cost to build/upgrade this building TO [level]. When [costPerEra]
  /// is authored, the level's region band (see [regionOrderForLevel]) names the
  /// resources and their base amounts, and [costFactor] scales them from that
  /// band's first level up. Otherwise the flat [resourceCost] scaled by
  /// [costFactor]^(level−1) (the legacy path).
  Map<String, double> resourceCostAt(int level) {
    if (costPerEra.isNotEmpty) {
      final region = regionOrderForLevel(level);
      // Nearest defined band at or below this region, else the lowest one.
      final base =
          costPerEra[region] ??
          costPerEra[(costPerEra.keys.where((e) => e <= region).toList()
                    ..sort())
                  .lastOrNull ??
              (costPerEra.keys.toList()..sort()).first];
      final f = math
          .pow(costFactor, level - firstLevelOfRegion(region))
          .toDouble();
      return {for (final e in (base ?? const {}).entries) e.key: e.value * f};
    }
    final f = math.pow(costFactor, level - 1).toDouble();
    return {for (final e in resourceCost.entries) e.key: e.value * f};
  }

  /// Build time (seconds) to build/upgrade TO [level], scaled by [timeFactor].
  double constructionSecondsAt(int level) =>
      constructionSeconds * math.pow(timeFactor, level - 1).toDouble();

  bool canAfford(Map<String, double> stockpile) => canAffordAt(1, stockpile);

  /// Whether [stockpile] covers the level-[level] cost.
  bool canAffordAt(int level, Map<String, double> stockpile) {
    for (final e in resourceCostAt(level).entries) {
      if ((stockpile[e.key] ?? 0) < e.value) return false;
    }
    return true;
  }

  // ── Dev Mode: DB row <-> BuildingDef ────────────────────────
  // Parses the generic `effects` JSONB list (dev-mode's tunable vocabulary)
  // back into these same typed fields, so GameEngine and every UI display
  // never need to know defs came from a database instead of a Dart const.
  // See lib/features/settlement/services/game_defs_controller.dart.
  factory BuildingDef.fromDefRow(Map<String, dynamic> row) {
    double buildSpeedBonus = 0, populationBonus = 0;
    int queueSlotsBonus = 0;

    final workshops = <WorkshopRole>[];
    final parsedEffects = <BuildingEffect>[];
    final rawEffects = (row['effects'] as List?) ?? const [];
    for (final raw in rawEffects) {
      final e = Map<String, dynamic>.from(raw as Map);
      final type = e['type'] as String?;
      if (type == 'workshop') {
        workshops.add(WorkshopRole.fromJson(e));
      } else if (type == 'bonus') {
        // Legacy, era-agnostic settlement bonuses (their own scalar fields).
        final value = (e['value'] as num?)?.toDouble() ?? 0;
        final target = e['target'] as String?;
        if (target == 'buildSpeed') {
          buildSpeedBonus += value;
        } else if (target == 'population') {
          populationBonus += value;
        } else if (target == 'queueSlots') {
          queueSlotsBonus += value.toInt();
        }
      } else if (BuildingEffect.paletteTypes.contains(type)) {
        // The rich per-era palette — one list, shared with the Dev-Mode editor,
        // so adding a type can't silently drop it on load again.
        parsedEffects.add(BuildingEffect.fromJson(e));
      }
    }

    // SHAPE FROM CODE, NUMBERS FROM THE ROW (user 2026-07-29). Without this a
    // saved row would keep whatever effects it was saved with forever, and
    // editing building_effects.dart would only ever change a fresh database.
    final reconciled = reconcileEffects(
      row['id'] as String,
      dbWorkshops: workshops,
      dbEffects: parsedEffects,
    );

    // Per-building tunables live in the `metadata` jsonb bag (migration 0017).
    final metadata = (row['metadata'] as Map?) ?? const {};
    final maxLevelPerEra = <int, int>{
      for (final e
          in ((metadata['maxLevelPerEra'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): (e.value as num).toInt(),
    };
    // Per-era build resources: {'1': {'wood': 100}, '2': {'frame': 40}, …}.
    final costPerEra = <int, Map<String, double>>{
      for (final e in ((metadata['costPerEra'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): {
          for (final r in (e.value as Map).entries)
            r.key as String: (r.value as num).toDouble(),
        },
    };

    return BuildingDef(
      id: row['id'] as String,
      name: row['name'] as String,
      imageUrl: row['image_url'] as String?,
      artBaseWidth: (row['art_base_width'] as num?)?.toDouble() ?? 1.0,
      artAnchorX: (row['art_anchor_x'] as num?)?.toDouble() ?? 0.5,
      artLift: (row['art_lift'] as num?)?.toDouble() ?? 0.0,
      color: Color(int.parse(row['color'] as String? ?? 'FF7C5CBF', radix: 16)),
      // A REBUILT building's footprint is its model's (user 2026-11-03: the
      // live Small House row was still 3x3 for a 2x2 model, so its picture
      // was stretched and its entrance and moving parts were switched off).
      // The picture is rendered for exactly that ground; no row can change it.
      gridW: kModelFootprint[row['id']]?.$1 ?? (row['grid_w'] as num).toInt(),
      gridH: kModelFootprint[row['id']]?.$2 ?? (row['grid_h'] as num).toInt(),
      resourceCost: {
        for (final e in ((row['resource_cost'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
      constructionHours: (row['construction_hours'] as num?)?.toDouble() ?? 0,
      eraIds: ((row['era_ids'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      isMainBuilding: row['is_main_building'] as bool? ?? false,
      isUnique: row['is_unique'] as bool? ?? false,
      isRoad: row['is_road'] as bool? ?? false,
      isBuildPlot: row['is_build_plot'] as bool? ?? false,
      requiredTechId: row['required_tech_id'] as String?,
      population: (row['population'] as num?)?.toInt() ?? 0,
      // The main hall NEVER has worker slots (user 2026-07-22: fully passive,
      // no crafting). Enforced at PARSE time because DB-authored defs override
      // the bundled fallback — the user's live castle row (created by a
      // dev-mode PNG upload) still carried the old construction/crafting
      // workshops, which is exactly how they came back after the fallback
      // was cleaned. A rule, not content: no row can reintroduce them.
      workshops: (row['is_main_building'] as bool? ?? false)
          ? const <WorkshopRole>[]
          : reconciled.workshops,
      buildSpeedBonus: buildSpeedBonus,
      populationBonus: populationBonus,
      queueSlotsBonus: queueSlotsBonus,
      maxCount: (row['max_count'] as num?)?.toInt() ?? 1,
      // Unknown/absent key → null, i.e. "derive it" — a row written before the
      // field existed must not land in some arbitrary drawer.
      category: BuildingCategory.fromId(metadata['category'] as String?),
      maxLevelPerEra: maxLevelPerEra,
      costFactor: (metadata['costFactor'] as num?)?.toDouble() ?? 1.6,
      timeFactor: (metadata['timeFactor'] as num?)?.toDouble() ?? 1.6,
      costPerEra: costPerEra,
      effects: reconciled.effects,
    );
  }

  Map<String, dynamic> toDefRow() {
    final effects = <Map<String, dynamic>>[];
    for (final w in workshops) {
      effects.add({
        'type': 'workshop',
        'stat': w.stat.name,
        'resource': w.resource,
        'mult': w.mult,
        'slots': w.slots,
        if (w.levelFactor != null) 'levelFactor': w.levelFactor,
        if (w.slotSteps.isNotEmpty)
          'slotSteps': {
            for (final s in w.slotSteps.entries) s.key.toString(): s.value,
          },
        // A combined post's per-part dials. Written only when there are any, so
        // an ordinary post's row is byte-identical to what it always was.
        if (w.mults.isNotEmpty) 'mults': w.mults,
      });
    }
    if (buildSpeedBonus != 0) {
      effects.add({
        'type': 'bonus',
        'target': 'buildSpeed',
        'value': buildSpeedBonus,
      });
    }
    if (populationBonus != 0) {
      effects.add({
        'type': 'bonus',
        'target': 'population',
        'value': populationBonus,
      });
    }
    if (queueSlotsBonus != 0) {
      effects.add({
        'type': 'bonus',
        'target': 'queueSlots',
        'value': queueSlotsBonus,
      });
    }
    for (final e in this.effects) {
      effects.add({
        'type': e.type,
        if (e.key.isNotEmpty) 'key': e.key,
        'value': e.value,
        if (e.era != 1) 'era': e.era,
        if (e.levelFactor != null) 'levelFactor': e.levelFactor,
        if (e.levelSteps.isNotEmpty)
          'levelSteps': {
            for (final s in e.levelSteps.entries) s.key.toString(): s.value,
          },
      });
    }

    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
      'art_base_width': artBaseWidth,
      'art_anchor_x': artAnchorX,
      'art_lift': artLift,
      'color': color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0'),
      'grid_w': gridW,
      'grid_h': gridH,
      'resource_cost': resourceCost,
      'construction_hours': constructionHours,
      'era_ids': eraIds,
      'is_main_building': isMainBuilding,
      'is_unique': isUnique,
      'is_road': isRoad,
      'is_build_plot': isBuildPlot,
      'required_tech_id': requiredTechId,
      'population': population,
      'max_count': maxCount,
      'effects': effects,
      'metadata': {
        if (category != null) 'category': category!.id,
        if (maxLevelPerEra.isNotEmpty)
          'maxLevelPerEra': {
            for (final e in maxLevelPerEra.entries) '${e.key}': e.value,
          },
        if (costPerEra.isNotEmpty)
          'costPerEra': {
            for (final e in costPerEra.entries) '${e.key}': e.value,
          },
        'costFactor': costFactor,
        'timeFactor': timeFactor,
      },
    };
  }
}

// ── Region I ───────────────────────────────────────────────
// Sourced from Balancing/Houses.xlsx + Balancing/Research.xlsx — every
// building/tech below reproduces those sheets' numbers exactly (cross-
// checked against the sheet's own "Metric" validation block). Everything is
// assigned to region I (`eraIds: ['era_1']`) except the two always-available
// structures (Main Hall/Castle, Road, `eraIds: []`).
//
// Construction/research times are calibrated the same way as before: at
// 1 440 s of progress credited per real hour (one active build slot / one
// crafting slot), real time = constructionSeconds * 2.5, so e.g. sheet's
// "20 min" real time → constructionHours = (20*60/2.5)/3600. Construction is
// ungated since Main Hall keeps buildSpeedBase unconditionally — Builder
// Camp only adds the extra queue slot + its own laborer speed bonus.
// Bundled fallback content — used synchronously at import time (before any
// network round trip) and again if GameDefsController's DB load fails, so
// the app never boots into a blank/crashing state.
//
// It is also the BASE the DB is layered onto: GameDefsController rebuilds the
// live map as this content + dev-mode rows on top, per id. Public (not
// `_`-prefixed) so it can read this exact bundled roster rather than whatever
// the live map currently holds.
// ── FOOTPRINT LADDER ─────────────────────────────────────────
// Footprints are PROPORTIONAL to what the thing plausibly is, not levelled to
// fit a cramped plot (an earlier pass flattened almost everything to 2x2,
// which read as a village of identical sheds). Read this as one scale:
//
//   1x1   road                                    a path
//   2x2   hut                            4        one family's shelter
//   2x3   healing hut, fishing hut       6        a hut plus beds / a dock
//   3x3   woodland camp, hunter lodge,   9        a clearing, a work yard
//         workshop
//   2x5   longhouse                     10        long and narrow, by name
//   3x4   builder camp, breeding hut,   12        a hut plus a working yard
//         trading post
//   4x4   lumber camp, quarry           16        an industrial site
//   5x5   TRIBAL CENTER                 25        the landmark
//   6x5   large quarry                  30        an open pit, the biggest
//
// Two rules when adding a building: a dwelling is never bigger than a worksite
// of the same tier, and anything above 4x4 must be something the player
// EXPANDS for — the starting plot (10x10 = 100 cells) cannot hold two of them.
// ── No code-side bonuses live here any more (user 2026-07-25) ──
// A base-production table (kBaseProductionByType), an expedition-amplifier
// table (kExpeditionBonusByType) and a passive house-gold curve used to add
// yields that the Dev-Mode effects editor never showed: two sources of truth,
// one of them invisible. Both tables are DELETED. A building produces, boosts
// or shelters exactly what its `effects` list declares — nothing more.

// ═══════════════════════════════════════════════════════════════════════════
// GENERATED 8-ERA ROSTER (user 2026-07-24). The whole building set is emitted
// by formula here so code == the DB (building_roster.sql is serialised from
// this exact model). Per era: 2 producers per raw build-resource (cap 10 +2/era),
// 1 element refinery, 2 monster-pens and 1 producer per luxury. (The legendary
// Grand Works / Treasury pairs were removed 2026-11-04; something new replaces
// them.) Civic buildings (Builder Camp,
// Healing/Breeding Hut, Workshop, Scout, Training, Warehouse, Smokehouse) plus
// the always-available castle/road/building_plot. All numbers tune in Dev Mode.
// ═══════════════════════════════════════════════════════════════════════════
// ── Era I carries none (user 2026-08-12) ──
// Every other entry names the MATERIAL the era builds in, which is a fact
// about the building. "Primitive" named the people instead, and it sat on the
// first thing anyone ever places. Era I is where the church is just the
// church; the prefix returns with clay.
//
// Empty rather than absent, so `_pre(era)` can stay a lookup and nothing has
// to branch on the era number.
const Map<int, String> _eraPrefix = {
  1: '',
  2: 'Clay',
  3: 'Terracotta',
  4: 'Plaster',
  5: 'Iron',
  6: 'Forged',
  7: 'Glass',
  8: 'Crystal',
};

/// The ID for a generated building — bare in era I, suffixed after it.
///
/// ── Era I names things plainly (user 2026-08-12) ──
/// The live database says `small_wood_camp`, `church`, `marketplace`; the
/// generator said `small_wood_camp`, `church`,
/// `marketplace`. The user's ids are the same rule their NAMES follow
/// — describe the building, and let era I go without a qualifier — and the id
/// is what the map keys art and placement on, so the code follows the data
/// rather than the other way round.
///
/// Era II onward keeps the suffix it always had: `refinery_e2` is unchanged in
/// their database too, so nothing above era I was ever renamed and nothing
/// above era I is touched here.
String _idFor(int era, String bare, String suffixed) =>
    era == 1 ? bare : suffixed;

/// "$prefix Name" with the space dropped when there is no prefix.
String _named(int era, String what) {
  final p = _eraPrefix[era]!;
  return p.isEmpty ? what : '$p $what';
}

const Map<int, int> _eraHousingCap = {
  1: 12,
  2: 25,
  3: 35,
  4: 50,
  5: 70,
  6: 95,
  7: 125,
  8: 165,
};

// ── Named by SIZE again (user 2026-08-12) ──
// They were "Hut" and "Longhouse", became Thicket and Grove on the argument
// that monsters are not lodged but given somewhere to live (2026-08-03), and
// are now Small House and Large House: "Ich habe es zu Small House und Large
// House umbenannt jetzt. Die Effekte bleiben, da es die gleichen Gebäude
// sind."
//
// So it stays a rename and nothing else — same ids, same capacity, same costs.
// One pair for all eight tiers rather than eight invented place-names, and the
// era prefix is what keeps them apart from era II onwards; era I gets the bare
// pair, which is what the user wrote.
//
// Ids stay `hut`/`house`/`pen_*` — they are referenced by DB rows and by
// kBuildingUnlockBattle, and an id is not a name.
const (String, String) _habitatNames = ('Small House', 'Large House');

double _eraBuildHours(double seconds, int era) =>
    seconds * math.pow(1.2, era - 1).toDouble() / 3600;

Color _rosterColor(String res) {
  const map = {'wood': 0xFF6B8E4E, 'stone': 0xFF7A8288, 'gold': 0xFFC9971A};
  if (map.containsKey(res)) return Color(map[res]!);
  final g = kGoodsDefs[res];
  if (g != null && g.kind == GoodsKind.element) return const Color(0xFF5C6BC0);
  return const Color(0xFFB5651D);
}

Map<String, double> _rosterCost(int era, double k) {
  final c = <String, double>{};
  final s = k * math.pow(1.4, era - 1);
  c['wood'] = (120 * s).roundToDouble();
  c['stone'] = (80 * s).roundToDouble();
  final el = elementForRegion(era);
  if (el != null) {
    c[el.id] = math.max(4.0, 20 * k * math.pow(0.9, era - 2)).roundToDouble();
  }
  final rw = rawForRegion(era);
  if (rw != null) {
    c[rw.id] = math.max(2.0, 10 * k * math.pow(0.9, era - 2)).roundToDouble();
  }
  return c;
}

// Civic buildings climb +3 levels per era (user 2026-07-25), capped at the
// lifetime ceiling: intro era → 3, next → 6, then 9, then 10. This is what makes
// their per-level effects (housing/heal/breeding/…) actually reachable in the
// era they're new, instead of the old "stuck at level 1 until you ascend".
Map<int, int> _rosterCapCivic(int intro) => {
  for (var e = intro; e <= 8; e++)
    e: math.min(3 * (e - intro + 1), kMaxBuildingLevel),
};
// Material extractors cap at the lifetime ceiling (user 2026-07-25: don't let an
// era-1 camp inflate to L24 in era 8 — that broke the "successor building, not a
// higher cap" model). Flat 10 across every era band.
Map<int, int> _rosterCapMaterial(int intro) => {
  for (var e = intro; e <= 8; e++) e: kMaxBuildingLevel,
};
Map<int, Map<String, double>> _rosterCostPerEra(Map<int, int> cap, double k) =>
    {for (final e in cap.keys) e: _rosterCost(e, k)};

String _luxWord(String id) =>
    const {
      // 'Fish Hut' -> 'Fish Shop' (user 2026-08-31), the same shop-front word
      // 'meat' already gets via [_luxNameOverride]'s "Butcher Shop" — fish just
      // happens to fit the generic "{good} {word}" template, so no override
      // needed for it.
      'fish': 'Shop',
      'wine': 'Vineyard',
      'spices': 'Garden',
      'salt': 'Works',
      'coffee': 'Roastery',
      'tea': 'House',
      'perfume': 'Perfumery',
    }[id] ??
    'Works';

/// A full name that doesn't fit the "{good} {word}" template at all — meat
/// isn't a "Meat Lodge" or a "Meat Works", it's butchered, not gathered raw
/// (user 2026-08-31: "Ab jetzt ist es nicht mehr fur sondern meat... dafür
/// butcher shop"). Checked before [_luxWord] builds the generic name.
String? _luxNameOverride(String id) => const {'meat': 'Butcher Shop'}[id];

/// The ID for a luxury building — `fish`/`meat` (era I only, see
/// goods_definitions.dart's regionOrder: 1) get the plain shop-front ids the
/// user's renamed Blender sources use (fish_shop.blend, butcher_shop.blend,
/// 2026-09-06); every other luxury across every era keeps the generic
/// `lux_<goodId>` pattern.
String _luxId(String id) =>
    const {'fish': 'fish_shop', 'meat': 'butcher_shop'}[id] ?? 'lux_$id';

List<BuildingDef> _buildRoster() {
  final defs = <BuildingDef>[];

  defs.add(
    const BuildingDef(
      id: 'castle',
      // Castle, not Castle (user 2026-08-12). It has been a castle in the
      // art since 2026-08-04 — stone, battlements, a gatehouse and a donjon —
      // and the name was the last thing still calling it a camp.
      name: 'Castle',
      color: Color(0xFF7C5CBF),
      // 10x10, not 7x7 (user 2026-08-24: "Grösse 10x10 / hinteren beiden
      // Ecken sind Ecktürme / Vorne sind zwei Rundtürme / Zugbrücke / An der
      // hinteren Wand ist der grosse Bergfried") — a full four-tower
      // enclosure needs the room a five-piece skyline along one wall
      // didn't. See PRESETS['castle'] / MAIN_HALL_PLAN in
      // tool/blender/render_building.py for the matching render-side change.
      gridW: 10,
      gridH: 10,
      isMainBuilding: true,
      isUnique: true,
      population: 5,
    ),
  );
  defs.add(
    const BuildingDef(
      id: 'road',
      name: 'Road',
      color: Color(0xFF6B6455),
      gridW: 1,
      gridH: 1,
      isRoad: true,
      maxCount: 0,
    ),
  );
  defs.add(
    BuildingDef(
      id: 'building_plot',
      name: 'Building Plot',
      color: const Color(0xFF8D6E4A),
      gridW: 5,
      gridH: 5,
      resourceCost: {'wood': 350},
      isBuildPlot: true,
      maxCount: 0,
      eraIds: const ['era_1'],
    ),
  );

  for (var era = 1; era <= 8; era++) {
    final matCap = _rosterCapMaterial(era);
    final civCap = _rosterCapCivic(era);
    final element = elementForRegion(era);

    final rawIds = era == 1 ? const ['wood', 'stone'] : [rawForRegion(era)!.id];
    for (final res in rawIds) {
      final g = kGoodsDefs[res];
      final baseName =
          g?.name ?? const {'wood': 'Wood', 'stone': 'Stone'}[res] ?? res;
      for (final large in const [false, true]) {
        final k = large ? 1.6 : 1.0;
        // Renamed 2026-08-23: era 1's small stone camp only — the user's own
        // file is now small_quarry.blend, a noticeably wider quarry face.
        // Every other combination this loop produces (large_stone_camp, both
        // wood camps, every era-2+ raw pair) keeps the shared id/footprint.
        // See PRESETS['small_quarry'] in render_building.py and
        // supabase/rename_small_quarry.sql for the render and live-DB sides.
        final isSmallQuarry = era == 1 && res == 'stone' && !large;
        // small_wood_camp only (user 2026-08-23: "das small_wood_camp soll
        // nur 3x3 sein") — era 1's small wood camp alone, not every small
        // camp the loop produces. See PRESETS['small_wood_camp'] in
        // render_building.py for the matching render-side change.
        final isSmallWoodCamp = era == 1 && res == 'wood' && !large;
        final isLargeStoneCamp = era == 1 && res == 'stone' && large;
        defs.add(
          BuildingDef(
            id: isSmallQuarry
                ? 'small_quarry'
                : _idFor(
                    era,
                    '${large ? 'large' : 'small'}_${res}_camp',
                    '${res}_${large ? 'works' : 'camp'}_e$era',
                  ),
            // ── SIZE, not era (user 2026-08-12: "primitive wood camp ist
            // das small wood camp usw.") ──
            // The pair is the only place in the roster where two buildings
            // differ by nothing except how big they are, and "Primitive" said
            // nothing about that — it said which era, which the MATERIAL already
            // says: era 3 gathers Terracotta, era 5 gathers Iron. Era 1 is the
            // only one with two raws, and Wood and Stone are era 1's materials
            // anyway. So the adjective goes to the difference that is real.
            // BOTH are Camps (user 2026-08-12: "Large Wood Camp"). Small and
            // Large is the whole difference between them, and calling the big
            // one a Works said there was a second one as well.
            name: '${large ? 'Large' : 'Small'} $baseName Camp',
            color: _rosterColor(res),
            // A camp SHIPS what it gathers, so it needs room for a cart
            // beside the pile (2026-08-09). The works halls were already
            // 4 x 4 and stay there. small_quarry is 3 x 3 and large_stone_camp
            // 5 x 4 (the rebuilt models, user 2026-11-03; before that the small
            // quarry was 5 x 4, measured against
            // the hand-edited .blend, 2026-08-23). small_wood_camp is 3 x 3
            // (user 2026-08-23).
            gridW: isLargeStoneCamp ? 5 : ((isSmallQuarry || isSmallWoodCamp) ? 3 : 4),
            gridH: large ? 4 : 3,
            resourceCost: _rosterCost(era, k),
            constructionHours: _eraBuildHours(large ? 600 : 360, era),
            eraIds: ['era_$era'],
            maxCount: 0,
            maxLevelPerEra: matCap,
            costPerEra: _rosterCostPerEra(matCap, k),
            costFactor: 1.3,
            timeFactor: 1.3,
          ),
        );
      }
    }

    if (element != null) {
      defs.add(
        BuildingDef(
          id: 'refinery_e$era',
          name: _named(era, 'Refinery'),
          color: const Color(0xFF5C6BC0),
          gridW: 4,
          gridH: 4,
          resourceCost: _rosterCost(era, 1.4),
          constructionHours: _eraBuildHours(720, era),
          eraIds: ['era_$era'],
          maxCount: 0,
          maxLevelPerEra: matCap,
          costPerEra: _rosterCostPerEra(matCap, 1.4),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
    }

    final cap = _eraHousingCap[era]!;
    final habitat = _habitatNames;
    final houseSpecs = era == 1
        ? [
            // Was 3x3 (2026-08-09: "two cells square left it a dark lump
            // with no yard"). Put back to 2x2 (user 2026-09-29, as part of
            // rescaling every building's doors/windows/torches to the
            // Castle's own proportions) — the model itself was rescaled to
            // fit, along with its door, so it no longer needs the extra
            // cell to read.
            ('small_house', _named(era, habitat.$1), 2, 2, 0.7, cap),
            ('large_house', _named(era, habitat.$2), 2, 5, 1.1, cap + 5),
          ]
        : [
            ('pen_a_e$era', _named(era, habitat.$1), 3, 4, 0.9, cap),
            (
              'pen_b_e$era',
              _named(era, habitat.$2),
              3,
              5,
              1.3,
              (cap * 1.4).round(),
            ),
          ];
    for (final h in houseSpecs) {
      defs.add(
        BuildingDef(
          id: h.$1,
          name: h.$2,
          color: const Color(0xFF795548),
          gridW: h.$3,
          gridH: h.$4,
          resourceCost: _rosterCost(era, h.$5),
          constructionHours: _eraBuildHours(300, era),
          eraIds: ['era_$era'],
          maxCount: 0,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, h.$5),
          costFactor: 1.3,
          timeFactor: 1.3,
          population: h.$6,
        ),
      );
    }

    final luxuries =
        kGoodsDefs.values
            .where((g) => g.isSupply && g.regionOrder == era)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    for (final lux in luxuries) {
      defs.add(
        BuildingDef(
          id: _luxId(lux.id),
          name:
              '${lux.emoji} '
              '${_luxNameOverride(lux.id) ?? '${lux.name} ${_luxWord(lux.id)}'}',
          color: const Color(0xFF8D6E4A),
          // A luxury has to SHOW what it trades, and the showing is what needs
          // the ground: a dock with a boat in it, a tanning vat and a drying
          // frame. Three deep rather than two (2026-08-09).
          gridW: 3,
          gridH: 3,
          resourceCost: _rosterCost(era, 0.9),
          constructionHours: _eraBuildHours(360, era),
          eraIds: ['era_$era'],
          maxCount: 0,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.9),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
    }

    if (era == 1) {
      defs.add(
        BuildingDef(
          id: 'builder_camp',
          name: 'Builder Camp',
          color: const Color(0xFF546E7A),
          // 5 x 5, not 6 x 6 (user 2026-08-23) — shrunk in their own
          // builder_camp.blend edit; the measured model no longer fills 6 x 6.
          gridW: 5,
          gridH: 5,
          resourceCost: _rosterCost(1, 1.2),
          constructionHours: _eraBuildHours(480, 1),
          eraIds: const ['era_1'],
          maxCount: 0,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 1.2),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      defs.add(
        BuildingDef(
          id: 'healing_hut',
          name: 'Healing Hut',
          color: const Color(0xFF4FAE6B),
          // 5x4, not 4x4 (user 2026-08-23: first "nur 4x4", then "müsste wohl
          // 5 (x) und 4 (y) sein"). The hand-authored plan is still the 6x5 it
          // grew to (4x4→5x4→6x5, see prior history in git blame) — it now
          // gets scaled onto this smaller tile instead of redrawn, matching
          // the castle's own plan-scaling trick (tool/blender/render_building.py
          // HEALING_HUT_PLAN_W/H).
          gridW: 5,
          gridH: 4,
          resourceCost: _rosterCost(1, 0.6),
          constructionHours: _eraBuildHours(120, 1),
          eraIds: const ['era_1'],
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.6),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      // Combat School (user 2026-09-05) — evolution no longer grants a move
      // by itself; this is where a creature actually learns one (every
      // neutral move + every move of its own type, gated by that move's own
      // stage — see ability_def.dart's learnableAbilitiesFor). Era 1, same as
      // every other core-loop building since the "no feature unlocks" pass —
      // move variety matters from the very first fights, not partway through
      // the game. No bundled art yet (a Blender pass is a separate,
      // hands-on follow-up — see [[blender-render-kit]]); sized/costed off
      // the Healing Hut as the closest analog until real numbers are tuned.
      defs.add(
        BuildingDef(
          id: 'combat_school',
          name: 'Combat School',
          color: const Color(0xFFB5442E),
          gridW: 5,
          gridH: 4,
          resourceCost: _rosterCost(1, 0.6),
          constructionHours: _eraBuildHours(120, 1),
          eraIds: const ['era_1'],
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.6),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      // Trade Center (user 2026-07-25, item Phase 3) — the market's home and
      // gold's only real sink. The id stays `trading_post`
      // (kTradingPostBuildingId, which the map's Market action already keys on):
      // the constant and the sheet existed long before the building did, so the
      // market was unreachable until this def appeared.
      defs.add(
        BuildingDef(
          id: 'trading_post',
          name: 'Trade Center',
          color: const Color(0xFFC9A227),
          // A market needs stalls down BOTH sides of the hall, which 3 x 3 could not hold without the awnings overhanging the grass.
          gridW: 4,
          gridH: 3,
          resourceCost: _rosterCost(1, 1.0),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          maxCount: 1, // one market per settlement — a second adds nothing
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 1.0),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      defs.add(
        BuildingDef(
          id: 'breeding_hut',
          name: 'Breeding Hut',
          color: const Color(0xFFE91E63),
          // 4x4, not 3x4 (user 2026-08-04). The art was rebuilt as two wings
          // round a court, and a SQUARE footprint is what makes that read: the
          // plan projects to a true rhombus with its near corner at the bottom
          // of the picture, so a court left open at that corner is looked INTO
          // rather than past. The plot has to agree with the picture — the map
          // scales art to the footprint's width, so a 3x4 def would squash it.
          gridW: 4,
          gridH: 4,
          resourceCost: _rosterCost(1, 0.9),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.9),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      // Hatchery — hatches the eggs the Breeding Hut lays; unlocked together
      // with it (user 2026-07-24). Built the SAME WAY as the hut but on its own
      // keys (user 2026-07-26): a `hatching` post and a `hatching` job cap, so
      // the two buildings are staffed, capped and tuned independently.
      defs.add(
        BuildingDef(
          id: 'hatchery',
          name: 'Hatchery',
          color: const Color(0xFFF06292),
          // The clutches are the label, and they have to lie in front of the chamber rather than under its eaves.
          gridW: 4,
          gridH: 3,
          resourceCost: _rosterCost(1, 0.9),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.9),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      // ── Scout Post ──
      // ERA I, not II (moved 2026-07-26). It is the sole source of longer hunts
      // and extra expedition slots now that the feature unlocks are gone (user:
      // "Expeditionen werden an scout geknüpft, jagdt an scout"), and those
      // used to arrive in the FIRST region (battles 5 and 6). Leaving the post
      // in era II would have pushed both a whole region later — the building
      // has to exist where the thing it grants is meant to appear.
      defs.add(
        BuildingDef(
          id: 'scout_post',
          name: 'Scout Post',
          color: const Color(0xFF7E9E5B),
          gridW: 2,
          gridH: 2,
          resourceCost: _rosterCost(1, 0.7),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          maxCount: 2,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.7),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      // ── Caravanserai (user 2026-07-29) ──
      // The Scout Post's twin, on the other road. Trade caravans used to be
      // expeditions in every respect — same seats, same amplifiers — so a load
      // of wood going to market cost you a hunt, and a warehouse full of ore
      // somehow made the trade run faster. This is the building that knows the
      // MARKET road: it grants the caravan seats and staffs the two things a
      // trade run is made of.
      //
      // Era I, beside the Trade Center: the Market exists from the first era,
      // so its road has to as well — kBaseCaravanSlots alone would mean one
      // caravan forever until era II.
      defs.add(
        BuildingDef(
          id: 'caravanserai',
          name: 'Caravanserai',
          color: const Color(0xFFB07D3A),
          // Wider AND deeper (2026-08-09): the yard is the building. Camels and a wagon need floor, and at 3 x 2 twenty props ended up off the tile.
          gridW: 4,
          gridH: 3,
          resourceCost: _rosterCost(1, 0.8),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          maxCount: 2,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.8),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      // ── The two STORES (user 2026-07-30) ──
      // "Ein Lager für die Ära 1 einfügen, welches alle Produktion und
      // Luxusressourcen lagern kann. Zusätzlich ein Goldlager."
      //
      // Era I, because the ceiling exists from the first tick: without a store
      // to raise it, the settlement is stuck at whatever the base dial allows,
      // and that is the pressure these two relieve. Kept APART — goods and coin
      // are different problems, and a player short on room for wood should not
      // have to widen the vault to fix it.
      //
      // Which resources each one holds, and by how much per level, is authored
      // in building_effects.dart — one `storage` effect per resource.
      defs.add(
        BuildingDef(
          id: 'storehouse',
          name: 'Storehouse',
          color: const Color(0xFF9A7B4F),
          // Raised on staddle stones, so the ground floor is all shadow — the sacks, casks and the cart at the door need their own strip of yard.
          gridW: 4,
          gridH: 3,
          resourceCost: _rosterCost(1, 0.9),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          // Several, so more room is a thing you BUILD as well as a thing you
          // level — the same shape as the housing huts.
          maxCount: 4,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.9),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      defs.add(
        BuildingDef(
          id: 'gold_vault',
          name: 'Gold Vault',
          color: const Color(0xFFC9A227),
          // 4 x 4, not 3 x 3 (user 2026-08-23, rebuilt to a reference photo):
          // a keep with a tower, a rampart and one long exterior stair needs
          // real room to stand in.
          gridW: 4,
          gridH: 4,
          resourceCost: _rosterCost(1, 0.7),
          constructionHours: _eraBuildHours(300, 1),
          eraIds: const ['era_1'],
          maxCount: 2,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.7),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
    } else if (era == 2) {
      defs.add(
        BuildingDef(
          id: 'thinker_circle',
          name: 'Workshop',
          color: const Color(0xFF5C6BC0),
          gridW: 3,
          gridH: 3,
          resourceCost: _rosterCost(2, 1.2),
          constructionHours: _eraBuildHours(480, 2),
          eraIds: const ['era_2'],
          maxCount: 0,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 1.2),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
    } else if (era == 3) {
      defs.add(
        BuildingDef(
          id: 'training_grounds',
          name: 'Training Grounds',
          color: const Color(0xFFD84315),
          gridW: 3,
          gridH: 3,
          resourceCost: _rosterCost(3, 1.0),
          constructionHours: _eraBuildHours(360, 3),
          eraIds: const ['era_3'],
          maxCount: 1,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 1.0),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      defs.add(
        BuildingDef(
          id: 'warehouse',
          name: 'Warehouse',
          color: const Color(0xFF8D6E63),
          gridW: 2,
          gridH: 2,
          resourceCost: _rosterCost(3, 0.8),
          constructionHours: _eraBuildHours(300, 3),
          eraIds: const ['era_3'],
          maxCount: 3,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.8),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
      defs.add(
        BuildingDef(
          id: 'smokehouse',
          name: 'Smokehouse',
          color: const Color(0xFFB55E36),
          gridW: 2,
          gridH: 2,
          resourceCost: _rosterCost(3, 0.9),
          constructionHours: _eraBuildHours(300, 3),
          eraIds: const ['era_3'],
          maxCount: 2,
          maxLevelPerEra: civCap,
          costPerEra: _rosterCostPerEra(civCap, 0.9),
          costFactor: 1.3,
          timeFactor: 1.3,
        ),
      );
    }
  }

  // EFFECTS COME FROM ONE TABLE (user 2026-07-29). Whatever a def literal above
  // says about its own effects is replaced here by its entry in
  // kBuildingEffects — that table is the single authored source, so "which
  // effects does this building have" has exactly one answer and the Dev-Mode
  // form can stop offering to invent new ones.
  return [
    for (final d in defs)
      d.withEffects(kBuildingEffects[d.id] ?? BuildingEffects.none),
  ];
}

/// The bundled building roster (identical to building_roster.sql). GameDefs
/// controller layers Dev-Mode DB rows onto this per id.
final Map<String, BuildingDef> kFallbackBuildingDefs = {
  for (final d in _buildRoster()) d.id: d,
};

// Live, mutable roster — GameDefsController replaces its contents in place
// once DB-backed defs load or a dev-mode edit arrives (`.clear()` + `.addAll(...)`).
// Every other file references this exact map object, so nothing else needs
// to change for def edits to propagate.
final Map<String, BuildingDef> kBuildingDefs = Map.of(kFallbackBuildingDefs);

// ── Map-progress building unlocks (user 2026-07-24) ─────────
// Research is gone; buildings are REWARDS earned by working up the linear path.
// A fresh settlement starts with only the bare essentials — one wood + one
// stone gathering camp, one basic house, the road and the hall — and everything
// else "hides in the campaign", unlocking as battles are won.
//
// ⚠ THIS IS A SEED, NOT A LIVE TABLE (user 2026-07-26).
// Nothing reads it while the game runs. Its only job is to give
// _buildFallbackPath the era-I reward layout a fresh database starts with, so
// the bundled path is playable and — crucially — VISIBLE in Dev Mode → Path,
// where it can be changed. What a building actually costs in battles comes from
// the authored node rewards alone (see pathBuildingUnlockBattle); editing this
// map changes what a NEW save is seeded with, never what an existing path does.
//
// The ORDER matches the user's brief ("nach dem 1. Kampf die Healing Hut, dann
// im Verlauf der ersten Ära die anderen"). A building not listed here is seeded
// onto no node and is buildable as soon as its era is reached.
/// Where a building's chimney mouth sits inside its own sprite, as fractions of
/// the picture's width and height, measured from its top-left (user 2026-08-04:
/// "kleinere Animationen hinzufügen wie Licht, Rauch, Wind").
///
/// A LOOKUP rather than two more BuildingDef fields, deliberately. These are
/// properties of one PNG, they only exist for the handful of buildings that
/// have a chimney, and every field added to BuildingDef has to be threaded
/// through the constructor, withEffects, both DB translations and the Dev-Mode
/// form — four places to keep in step for a number that describes a picture.
/// A building not listed here simply does not smoke.
///
/// Measured off the render, not guessed: open `docs/renders/<id>.png` and read
/// the chimney's mouth as a fraction of the image.
/// Where a building's smoke comes out, as a fraction of its ART BOX.
///
/// ── Computed, not eyeballed (user 2026-08-09) ──
/// Every entry is the chimney POT's own position, projected through the same
/// camera tool/blender/render_building.py frames the picture with, so smoke
/// lands on the stack rather than near it. The two that were here were guessed
/// from the picture, and both were about a tenth of a box off — which at map
/// size is smoke coming out of a roof slope.
///
/// The renders deliberately have NO smoke baked into them: the app draws it
/// animated and phase-shifted per building (see ChimneySmoke in
/// building_life.dart), and a second, still one underneath would show as a grey
/// smudge that never moves. Re-render a building whose chimney moved and this
/// map has to be recomputed with it.
const Map<String, (double, double)> kChimneyAnchor = {
  // 'castle' had an entry here, but the 2026-08-23 rebuild-to-photo
  // dropped the keep hall (and its chimney) entirely — the new castle is
  // a wall and towers, nothing with a fireplace. A stale anchor would
  // put smoke over open air.
  // Recomputed for the 5x4 footprint (user 2026-08-23) — the plan-scaling
  // that fits the building onto its tile also reframes the camera, moving
  // the chimney mouth in the picture. Projected through the same camera as
  // before (hhchim-1_pot, the left of the two stacks).
  // 'large_wood_camp' had an entry here, but that building's chimney is
  // gone — the 2026-08-16 redesign replaced it with an open thatched shed
  // with no fireplace. A stale anchor would have put smoke over open air.

  // ── Round two (user 2026-08-31): "was kannst du alles sinnvoll
  // animieren" — every OTHER chimney or open-fire prop already sitting in
  // the roster's geometry gets the same treatment, no new art needed.
  // 'small_house'/'large_house' were projected against the user's own
  // hand-edited .blend in Houses/ (shchim_pot / lhchim_pot) — everything
  // below against the stock render_building.py recipe, since neither has a
  // hand-edited file of its own yet. An open brazier ('_fire0', not a
  // chimney pot) reads exactly as well with ChimneySmoke as a real stack —
  // it is still a fire putting smoke into the air.
  //
  // anchorY is a fraction of the OVERLAY box (art width * 1.25 — see
  // _LifeOverlay), not of the real render height, because that overlay box
  // is all the widget actually sizes the painter's canvas to. For a squat
  // building the two are almost the same; scout_post's watchtower is a lot
  // taller than 1.25x its own width, so its beacon projects to a NEGATIVE
  // anchorY — correct, not a bug: Clip.none all the way up this Stack lets
  // the smoke paint above the box exactly where the beacon really is.
  'thinker_circle': (0.498, 0.334),
  'refinery_e2': (0.231, 0.732),
  'small_house': (0.555, 0.134),
  'small_house_r1': (0.696, 0.235),
  'small_house_r2': (0.445, 0.291),
  'small_house_r3': (0.304, 0.191),
  'hatchery': (0.548, 0.371),
  'hatchery_r1': (0.657, 0.452),
  'hatchery_r2': (0.452, 0.496),
  'hatchery_r3': (0.343, 0.414),
  'castle': (0.531, 0.485),
  'small_wood_camp': (0.538, 0.468),
  'small_wood_camp_r1': (0.715, 0.569),
  'small_wood_camp_r2': (0.462, 0.640),
  'small_wood_camp_r3': (0.285, 0.539),
  'large_wood_camp': (0.203, 0.591),
  'castle_r1': (0.748, 0.597),
  'large_wood_camp_r1': (0.548, 0.491),
  'large_wood_camp_r2': (0.797, 0.630),
  'large_wood_camp_r3': (0.452, 0.729),
  'castle_r2': (0.469, 0.684),
  'castle_r3': (0.252, 0.572),
  'fish_shop': (0.549, 0.440),
  'fish_shop_r1': (0.735, 0.553),
  'fish_shop_r2': (0.451, 0.628),
  'fish_shop_r3': (0.265, 0.514),
  'butcher_shop': (0.464, 0.458),
  'butcher_shop_r1': (0.734, 0.537),
  'butcher_shop_r2': (0.536, 0.645),
  'butcher_shop_r3': (0.266, 0.566),
  'scout_post': (0.724, 0.413),
  'scout_post_r1': (0.446, 0.481),
  'scout_post_r2': (0.276, 0.369),
  'scout_post_r3': (0.554, 0.301),
  'large_house': (0.648, 0.472),
  'large_house_r1': (0.765, 0.637),
  'large_house_r2': (0.352, 0.684),
  'large_house_r3': (0.235, 0.519),
  'breeding_hut': (0.489, 0.491),
  'breeding_hut_r1': (0.756, 0.589),
  'breeding_hut_r2': (0.511, 0.696),
  'breeding_hut_r3': (0.244, 0.598),
  'healing_hut': (0.740, 0.627),
  'healing_hut_r1': (0.475, 0.713),
  'healing_hut_r2': (0.260, 0.607),
  'healing_hut_r3': (0.525, 0.521),
};

const Map<String, int> kBuildingUnlockBattle = {
  'healing_hut': 1, // "Nach dem 1. Kampf" — heal up right after the first win.
  'large_house': 3, // more housing than the starting Small House
  'fish_shop': 4,
  'butcher_shop': 6,
  'building_plot': 7, // expansion ground (still capped by expansionsUnlocked)
  'large_wood_camp': 9, // the bigger production buildings come mid-era
  'large_stone_camp': 10,
  // The market + item shop, once there IS a surplus worth trading (user
  // 2026-07-25). Gold has no other sink than skipping timers before this.
  'trading_post': 11,
  'breeding_hut': 12,
  'hatchery': 12, // unlocks together with the Breeding Hut (user 2026-07-24)
  'builder_camp': 14,
  // THE REFINERY IS THE SECOND-TO-LAST NODE OF AN ERA (user 2026-07-31: "die
  // rafinery wird jeweils beim zweitletzten Knotenpunkt freigeschalten"), i.e.
  // 18 with the boss at 19.
  //
  // It is era II's, not era I's: era I has no element (elementForRegion(1) is
  // null), so no `refinery_e1` def is ever generated — the entry that stood here
  // named a building that does not exist and unlocked nothing at all. What the
  // node really grants is the right to the CLAY REFINERY, built once you ascend,
  // which is why its output starts showing in the header strip from this battle
  // on (see _previewedGoods in settlement_screen).
  'refinery_e2': 18,
};

/// True when [def] makes [goodId] — from a worker-free `production` effect or
/// from a work post's output. The two ways a building produces anything.
bool buildingProduces(BuildingDef def, String goodId) =>
    def.effectKeys('production').contains(goodId) ||
    def.workshops.any((r) => r.resource == goodId);

/// The battle at which a NODE first hands you the means to make [goodId] — the
/// earliest path unlock among the buildings that produce it.
///
/// Null when nothing on the path gates a producer, which covers two cases that
/// mean the same thing for a reader: no building makes it at all, or every one
/// that does simply arrives with its era. Producers with no node gate are
/// therefore SKIPPED rather than answered as 0 — Timber Frame is made both by
/// the Clay Refinery (won at battle 18) and by era II's grand works (no gate),
/// and taking the minimum over both would report "no battle needed" for a
/// material the path very much gates.
int? producerUnlockBattle(String goodId) {
  int? best;
  for (final def in kBuildingDefs.values) {
    if (!buildingProduces(def, goodId)) continue;
    final at = buildingUnlockBattle(def.id);
    if (at <= 0) continue;
    if (best == null || at < best) best = at;
  }
  return best;
}

/// The battle a building unlocks at — 0 (available as soon as its era is
/// reached) unless an authored path node's rewards pin it later. The path is
/// the ONLY authority (user 2026-07-26); see [pathBuildingUnlockBattle].
int buildingUnlockBattle(String buildingId) =>
    pathBuildingUnlockBattle(buildingId);

/// Whether ANY node on the path hands out [buildingId] as a reward — the
/// stricter gate [availableBuildings]/[placeBuilding] apply on top of the
/// battle number (user 2026-08-31: "nur die Gebäude bauen lassen, welche
/// durch die Kampagne freigespielt wurden ... diejenigen, welche ich noch
/// gar keinem Knoten zugeordnet habe, sollen noch nicht baubar sein").
///
/// A building's own unlock battle is 0 for two different reasons that used
/// to be indistinguishable: "no node gates it, so it's free the moment its
/// era arrives" (era 2026-07-26's own stated behaviour) and "nobody has
/// authored a reward for it yet." Reaching 0 no longer means the same thing
/// [buildingUnlockBattle] alone still reports for it — see there for why
/// that number itself stays unchanged.
bool buildingHasPathReward(String buildingId) =>
    buildingUnlockBattle(buildingId) > 0;

/// [currentRegion] is `SettlementController.dungeonMaxStage` — the region
/// reached automatically on the last boss clear (user 2026-09-05: no more
/// paid Castle ascension standing between "boss beaten" and "buildings
/// available").
List<BuildingDef> availableBuildings(int currentRegion, int battlesCleared) {
  // CUMULATIVE regions (user 2026-07-22): older buildings STAY buildable
  // when a region passes — a def is available once any of its regions has
  // been reached. Exact matching used to make every region-1 building
  // vanish on ascension.
  bool regionReached(BuildingDef b) {
    if (b.eraIds.isEmpty) return true;
    for (final id in b.eraIds) {
      final order = _regionOrderOfId(id);
      if (order != null && order <= currentRegion) return true;
    }
    return false;
  }

  return kBuildingDefs.values
      .where(
        (b) =>
            !b.isMainBuilding &&
            !b.isRoad &&
            regionReached(b) &&
            // A Building Plot is governed by expansionsUnlocked/
            // buildPlotLimit, not by a path reward — it stays exempt from
            // this gate the way it already is from the battle number.
            (b.isBuildPlot || buildingHasPathReward(b.id)) &&
            battlesCleared >= buildingUnlockBattle(b.id),
      )
      .toList();
}

// ── Turned buildings (user 2026-11-03: "Gebäude um 90° drehen") ────────────

final Map<(String, int), (BuildingDef, BuildingDef)> _turnedCache = {};

/// [typeId]'s def turned by [quarterTurns] — the live def itself when not
/// turned (or when the building cannot turn: an old picture has one side).
/// Cached against the live def's identity, so a roster reload is picked up.
BuildingDef? defRotated(String typeId, int quarterTurns) {
  final base = kBuildingDefs[typeId];
  final r = quarterTurns % 4;
  if (base == null || r == 0 || !base.canRotate) return base;
  final hit = _turnedCache[(typeId, r)];
  if (hit != null && identical(hit.$1, base)) return hit.$2;
  final turned = base.rotated(r);
  _turnedCache[(typeId, r)] = (base, turned);
  return turned;
}

/// The def of a PLACED building, turned the way it stands on the map. Every
/// question about where a building is — its footprint, its picture, its
/// entrance — goes through this; questions about what it DOES are the same
/// either way.
BuildingDef? placedDefOf(PlacedBuilding b) =>
    defRotated(b.buildingTypeId, b.rotation);
