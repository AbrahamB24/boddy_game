import 'package:flutter/material.dart';

import '../../creatures/models/creature_enums.dart' show CreatureStat;

// ── Workshop role ─────────────────────────────────────────
// A single work station a building offers. Under the creature-worker economy
// a building produces NOTHING on its own — its output is entirely the sum of
// the civilian stat of the creatures stationed in this role, so the role
// declares WHICH stat it reads and WHAT it produces.
//
// [resource] is either a settlement resource key ('wood', 'stone', 'gold',
// 'fish', 'fur') that gets added to the stockpile, or a pseudo-output
// ('construction' / 'research') that advances the active build/tech instead.
// [mult] converts one point of the stat into output-per-hour (raw stats run
// ~10-150, so 0.1 turns a 100-stat worker into ~10 units/h). [slots] caps how
// many creatures can fill THIS role in THIS building.
class WorkshopRole {
  final CreatureStat stat;
  final String resource;
  final double mult;
  final int slots;
  const WorkshopRole({
    required this.stat,
    required this.resource,
    this.mult = 0.1,
    this.slots = 1,
  });

  static const String kConstruction = 'construction';
  static const String kResearch = 'research';

  bool get producesResource =>
      resource != kConstruction && resource != kResearch;
}

// ── Game constants ────────────────────────────────────────
const kEnergyPerStep = 1.0 / 100.0; // 100 steps = 1 energy
const kMaxEnergy = 100.0;
const kDrainPerHour = 80.0 / 24.0; // ~3.33/h (8 000 steps/day = break-even)

const kBaseBuildSlots = 1; // max simultaneous active construction sites
const kBaseQueueSlots = 0; // build queue starts locked — research unlocks slots

const kGridCols = 60;
const kGridRows = 40;
const kCellSize = 12.0;

// Starting buildable territory: a 12x12 zone centered on the map, containing
// the Main Hall. More space is unlocked by building "Building Plot"s (see
// isBuildPlot below) — see GameEngine.buildableRegionCells.
const kInitialPlotX = 24;
const kInitialPlotY = 14;
const kInitialPlotSize = 12;

// ── Building definition ───────────────────────────────────
class BuildingDef {
  final String id;
  final String name;
  // Public URL of a Dev-Mode-uploaded PNG (Supabase Storage bucket
  // 'building-images', see widgets/building_icon.dart for rendering with a
  // placeholder fallback when null — buildings have no emoji anymore).
  final String? imageUrl;
  final Color color;
  final int gridW;
  final int gridH;
  final Map<String, double>
  resourceCost; // keys: 'wood', 'stone' (no food — food is now a good)
  final double constructionHours;
  // Eras this building is buildable in. Empty = available in every era
  // (used by main_hall/road, which must always be placeable). A building
  // can list several non-contiguous eras — see EraDef in era_definitions.dart.
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
  // Work stations this building offers. Empty = not a workshop (pure housing/
  // infrastructure). Each role is staffed by specific creatures whose civilian
  // stat drives its output — see WorkshopRole. Replaces the old
  // workerRequirement/maxLaborers/perWorker economy entirely.
  final List<WorkshopRole> workshops;
  // DEPRECATED (kept only so legacy defs/rows deserialize without error; no
  // longer read by the economy, which now uses [workshops]).
  final int workerRequirement;
  final int maxLaborers;
  // Goods production, split the same way as wood/stone below: goodsBase is a
  // flat units/h contribution per good id, goodsPerWorker scales with the
  // workers assigned to THIS building instance (PlacedBuilding.laborersAssigned).
  final Map<String, double> goodsBase;
  final Map<String, double> goodsPerWorker;
  // Wood/Stone production, split into a flat per-hour base (produced
  // regardless of staffing, as long as the building is complete + connected
  // + there's energy) and a per-worker rate that only pays out for THIS
  // instance's own PlacedBuilding.laborersAssigned (capped by maxLaborers
  // below). Both are literal units/h — no hidden multiplier or /100 calibration.
  // This lets buildings specialize: staffing-heavy extraction buildings lean
  // on woodPerWorker (scales automatically as population grows), steady
  // infrastructure buildings lean on woodBase (produces even when workers
  // are allocated elsewhere). Future eras/tech are expected to raise base
  // values explicitly (base doesn't auto-scale with population the way
  // perWorker does) — see EraDef in era_definitions.dart.
  final double woodBase;
  final double woodPerWorker;
  final double stoneBase;
  final double stonePerWorker;
  // Construction/research progress. buildSpeedBase/researchSpeedBase are a
  // flat real-seconds-of-progress-per-hour baseline (Main Hall owns the
  // build one unconditionally; Thinker Circle owns the research one — see
  // GameEngine.tick()'s buildSecondsGained/researchSecondsGained). The
  // PctPerWorker variants are NOT flat units/h like every other perWorker
  // field above — they're a fractional percentage speed bonus per laborer
  // assigned to THIS instance (e.g. 0.02 = +2% faster per laborer), summed
  // alongside buildSpeedBonus/techBuildSpeed into the same multiplicative
  // bonus tick() already applies on top of the base.
  final double buildSpeedBase;
  final double buildSpeedPctPerWorker;
  final double researchSpeedBase;
  final double researchSpeedPctPerWorker;
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
  // Gold produced per hour — flat, gated only by energy (no worker allocation).
  final double goldPerHour;
  // Needs system: while `needGoodId` has stock > 0 in the warehouse, this
  // building's need bonuses are active; once it runs out they simply switch
  // off (no penalty). needPopulationBonus boosts this building's OWN
  // population output; the wood/stone/gold bonuses are settlement-wide,
  // additive on top of the unconditional woodBonus/stoneBonus/allBonus above.
  // needConsumptionPerHour is REAL upkeep: this many units of needGoodId are
  // drained per hour per instance (on top of/instead of population's own
  // per-capita consumption of that good — see GoodsDef.consumptionPerCapitaPerHour),
  // independent of whether the bonus is currently active.
  final String? needGoodId;
  final double needPopulationBonus;
  final double needWoodBonus;
  final double needStoneBonus;
  final double needGoldBonus;
  final double needConsumptionPerHour;

  const BuildingDef({
    required this.id,
    required this.name,
    this.imageUrl,
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
    this.workerRequirement = 0,
    this.maxLaborers = 0,
    this.goodsBase = const {},
    this.goodsPerWorker = const {},
    this.woodBase = 0,
    this.woodPerWorker = 0,
    this.stoneBase = 0,
    this.stonePerWorker = 0,
    this.buildSpeedBase = 0,
    this.buildSpeedPctPerWorker = 0,
    this.researchSpeedBase = 0,
    this.researchSpeedPctPerWorker = 0,
    this.buildSpeedBonus = 0,
    this.populationBonus = 0,
    this.queueSlotsBonus = 0,
    this.maxCount = 1,
    this.goldPerHour = 0,
    this.needGoodId,
    this.needPopulationBonus = 0,
    this.needWoodBonus = 0,
    this.needStoneBonus = 0,
    this.needConsumptionPerHour = 0,
    this.needGoldBonus = 0,
  });

  double get constructionSeconds => constructionHours * 3600;

  bool canAfford(Map<String, double> stockpile) {
    for (final e in resourceCost.entries) {
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
    double woodBase = 0, woodPerWorker = 0, stoneBase = 0, stonePerWorker = 0;
    double buildSpeedBase = 0,
        buildSpeedPctPerWorker = 0,
        researchSpeedBase = 0,
        researchSpeedPctPerWorker = 0;
    final goodsBase = <String, double>{};
    final goodsPerWorker = <String, double>{};
    double buildSpeedBonus = 0, populationBonus = 0, goldPerHour = 0;
    int queueSlotsBonus = 0;
    String? needGoodId;
    double needPopulationBonus = 0,
        needWoodBonus = 0,
        needStoneBonus = 0,
        needGoldBonus = 0,
        needConsumptionPerHour = 0;

    final workshops = <WorkshopRole>[];
    final effects = (row['effects'] as List?) ?? const [];
    for (final raw in effects) {
      final e = Map<String, dynamic>.from(raw as Map);
      final type = e['type'] as String?;
      if (type == 'workshop') {
        workshops.add(WorkshopRole(
          stat: CreatureStat.fromName(e['stat'] as String?),
          resource: e['resource'] as String? ?? 'wood',
          mult: (e['mult'] as num?)?.toDouble() ?? 0.1,
          slots: (e['slots'] as num?)?.toInt() ?? 1,
        ));
      } else if (type == 'production') {
        final resource = e['resource'] as String? ?? '';
        final base = (e['base'] as num?)?.toDouble() ?? 0;
        final perWorker = (e['perWorker'] as num?)?.toDouble() ?? 0;
        if (resource == 'wood') {
          woodBase += base;
          woodPerWorker += perWorker;
        } else if (resource == 'stone') {
          stoneBase += base;
          stonePerWorker += perWorker;
        } else if (resource == 'buildSpeed') {
          buildSpeedBase += base;
          buildSpeedPctPerWorker += perWorker;
        } else if (resource == 'researchSpeed') {
          researchSpeedBase += base;
          researchSpeedPctPerWorker += perWorker;
        } else if (resource.isNotEmpty) {
          goodsBase[resource] = (goodsBase[resource] ?? 0) + base;
          goodsPerWorker[resource] =
              (goodsPerWorker[resource] ?? 0) + perWorker;
        }
      } else if (type == 'gold') {
        goldPerHour += (e['perHour'] as num?)?.toDouble() ?? 0;
      } else if (type == 'bonus') {
        final value = (e['value'] as num?)?.toDouble() ?? 0;
        final target = e['target'] as String?;
        if (target == 'buildSpeed') {
          buildSpeedBonus += value;
        } else if (target == 'population') {
          populationBonus += value;
        } else if (target == 'queueSlots') {
          queueSlotsBonus += value.toInt();
        }
      } else if (type == 'need') {
        needGoodId = e['goodId'] as String?;
        needPopulationBonus += (e['populationBonus'] as num?)?.toDouble() ?? 0;
        needWoodBonus += (e['woodBonus'] as num?)?.toDouble() ?? 0;
        needStoneBonus += (e['stoneBonus'] as num?)?.toDouble() ?? 0;
        needGoldBonus += (e['goldBonus'] as num?)?.toDouble() ?? 0;
        needConsumptionPerHour +=
            (e['consumptionPerHour'] as num?)?.toDouble() ?? 0;
      }
    }

    return BuildingDef(
      id: row['id'] as String,
      name: row['name'] as String,
      imageUrl: row['image_url'] as String?,
      color: Color(int.parse(row['color'] as String? ?? 'FF7C5CBF', radix: 16)),
      gridW: (row['grid_w'] as num).toInt(),
      gridH: (row['grid_h'] as num).toInt(),
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
      workshops: workshops,
      workerRequirement: (row['worker_requirement'] as num?)?.toInt() ?? 0,
      maxLaborers: (row['max_laborers'] as num?)?.toInt() ?? 0,
      goodsBase: goodsBase,
      goodsPerWorker: goodsPerWorker,
      woodBase: woodBase,
      woodPerWorker: woodPerWorker,
      stoneBase: stoneBase,
      stonePerWorker: stonePerWorker,
      buildSpeedBase: buildSpeedBase,
      buildSpeedPctPerWorker: buildSpeedPctPerWorker,
      researchSpeedBase: researchSpeedBase,
      researchSpeedPctPerWorker: researchSpeedPctPerWorker,
      buildSpeedBonus: buildSpeedBonus,
      populationBonus: populationBonus,
      queueSlotsBonus: queueSlotsBonus,
      maxCount: (row['max_count'] as num?)?.toInt() ?? 1,
      goldPerHour: goldPerHour,
      needGoodId: needGoodId,
      needPopulationBonus: needPopulationBonus,
      needWoodBonus: needWoodBonus,
      needStoneBonus: needStoneBonus,
      needGoldBonus: needGoldBonus,
      needConsumptionPerHour: needConsumptionPerHour,
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
      });
    }
    if (woodBase != 0 || woodPerWorker != 0) {
      effects.add({
        'type': 'production',
        'resource': 'wood',
        'base': woodBase,
        'perWorker': woodPerWorker,
      });
    }
    if (stoneBase != 0 || stonePerWorker != 0) {
      effects.add({
        'type': 'production',
        'resource': 'stone',
        'base': stoneBase,
        'perWorker': stonePerWorker,
      });
    }
    if (buildSpeedBase != 0 || buildSpeedPctPerWorker != 0) {
      effects.add({
        'type': 'production',
        'resource': 'buildSpeed',
        'base': buildSpeedBase,
        'perWorker': buildSpeedPctPerWorker,
      });
    }
    if (researchSpeedBase != 0 || researchSpeedPctPerWorker != 0) {
      effects.add({
        'type': 'production',
        'resource': 'researchSpeed',
        'base': researchSpeedBase,
        'perWorker': researchSpeedPctPerWorker,
      });
    }
    for (final gid in {...goodsBase.keys, ...goodsPerWorker.keys}) {
      effects.add({
        'type': 'production',
        'resource': gid,
        'base': goodsBase[gid] ?? 0,
        'perWorker': goodsPerWorker[gid] ?? 0,
      });
    }
    if (goldPerHour != 0) effects.add({'type': 'gold', 'perHour': goldPerHour});
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
    if (needGoodId != null) {
      effects.add({
        'type': 'need',
        'goodId': needGoodId,
        'populationBonus': needPopulationBonus,
        'woodBonus': needWoodBonus,
        'stoneBonus': needStoneBonus,
        'goldBonus': needGoldBonus,
        'consumptionPerHour': needConsumptionPerHour,
      });
    }

    return {
      'id': id,
      'name': name,
      'image_url': imageUrl,
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
      'worker_requirement': workerRequirement,
      'max_laborers': maxLaborers,
      'max_count': maxCount,
      'effects': effects,
    };
  }
}

// ── Era I ──────────────────────────────────────────────────
// Sourced from Balancing/Houses.xlsx + Balancing/Research.xlsx — every
// building/tech below reproduces those sheets' numbers exactly (cross-
// checked against the sheet's own "Metric" validation block). Everything is
// assigned to Era I (`eraIds: ['era_1']`) except the two always-available
// structures (Main Hall/Tribal Center, Road, `eraIds: []`) — see
// EraDef/kEraDefs in era_definitions.dart for the progression track itself.
//
// Construction/research times are calibrated the same way as before: at
// 1 440 s of progress credited per real hour (one active build slot / one
// research slot), real time = constructionSeconds * 2.5 (same for
// researchSeconds), so e.g. sheet's "20 min" real time → constructionHours
// = (20*60/2.5)/3600. Research now requires Thinker Circle to exist at all
// (it owns researchSpeedBase — Main Hall no longer does); construction stays
// ungated since Main Hall keeps buildSpeedBase unconditionally — Builder
// Camp only adds the extra queue slot + its own laborer speed bonus.
// Bundled fallback content — used synchronously at import time (before any
// network round trip) and again if GameDefsController's DB load fails, so
// the app never boots into a blank/crashing state. GameDefsController
// overwrites kBuildingDefs' *contents* in place once dev-mode DB rows load —
// see lib/features/settlement/services/game_defs_controller.dart.
// Public (not `_`-prefixed) so GameDefsService.seedFromFallback() can push
// this exact bundled content regardless of whatever's currently loaded into
// the live kBuildingDefs map below — see the note on that function for why
// reading kBuildingDefs itself there would silently reseed stale DB content.
const kFallbackBuildingDefs = <String, BuildingDef>{
  // ── Starter building (free, auto-placed) ───────────────────
  'main_hall': BuildingDef(
    id: 'main_hall',
    name: 'Tribal Center',
    color: Color(0xFF7C5CBF),
    gridW: 5,
    gridH: 5,
    constructionHours: 0,
    isMainBuilding: true,
    isUnique: true,
    // Shelters your first creatures AND bootstraps the economy: it offers a
    // few construction + research slots so a fresh settlement can build and
    // research from turn one (station your starter here). Specialised
    // workshops (Builder Camp / Thinker Circle) add more slots later.
    population: 5,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.construction,
        resource: WorkshopRole.kConstruction,
        mult: 30,
        slots: 3,
      ),
      WorkshopRole(
        stat: CreatureStat.research,
        resource: WorkshopRole.kResearch,
        mult: 40,
        slots: 3,
      ),
    ],
  ),
  'road': BuildingDef(
    id: 'road',
    name: 'Road',
    color: Color(0xFF6B6455),
    gridW: 1,
    gridH: 1,
    constructionHours: 0,
    isRoad: true,
    maxCount: 0, // unlimited — painted freely, no resource cost
  ),

  // ── Housing (creatures ARE the population) ────────────────
  'hut': BuildingDef(
    id: 'hut',
    name: 'Hut',
    color: Color(0xFF8D6E63),
    gridW: 2,
    gridH: 2,
    resourceCost: {'wood': 100},
    constructionHours: 120 / 3600, // 5 min real time
    eraIds: ['era_1'],
    population: 10, // shelters 10 creatures
    maxCount: 10,
    needGoodId: 'fish',
    needWoodBonus: 0.20, // fish in stock → +20% wood production
    needConsumptionPerHour: 1, // drinks 1 fish/h per instance, real upkeep
  ),
  'house': BuildingDef(
    id: 'house',
    name: 'Longhouse',
    color: Color(0xFF795548),
    gridW: 2,
    gridH: 3,
    resourceCost: {'wood': 300, 'stone': 200},
    constructionHours: 360 / 3600, // 15 min real time
    eraIds: ['era_1'],
    requiredTechId: 'longhouse_construction',
    population: 15, // shelters 15 creatures
    maxCount: 5,
    needGoodId: 'fur',
    needStoneBonus: 0.20, // fur in stock → +20% stone production
    needConsumptionPerHour: 1, // drinks 1 fur/h per instance, real upkeep
  ),

  // ── Wood (woodcutting stat → wood) ────────────────────────
  'woodland_camp': BuildingDef(
    id: 'woodland_camp',
    name: 'Woodland Camp',
    color: Color(0xFF6B8E4E),
    gridW: 3,
    gridH: 3,
    resourceCost: {'wood': 160},
    constructionHours: 240 / 3600, // 10 min real time
    eraIds: ['era_1'],
    maxCount: 3,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.woodcutting,
        resource: 'wood',
        mult: 0.5,
        slots: 6,
      ),
    ],
  ),
  'lumber_camp': BuildingDef(
    id: 'lumber_camp',
    name: 'Lumber Camp',
    color: Color(0xFF795548),
    gridW: 4,
    gridH: 3,
    resourceCost: {'wood': 500, 'stone': 200},
    constructionHours: 480 / 3600, // 20 min real time
    eraIds: ['era_1'],
    requiredTechId: 'primitive_woodworking',
    maxCount: 1,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.woodcutting,
        resource: 'wood',
        mult: 0.7,
        slots: 10,
      ),
    ],
  ),

  // ── Stone (mining stat → stone) ───────────────────────────
  'quarry': BuildingDef(
    id: 'quarry',
    name: 'Quarry',
    color: Color(0xFF607D8B),
    gridW: 3,
    gridH: 3,
    resourceCost: {'wood': 100},
    constructionHours: 240 / 3600, // 10 min real time
    eraIds: ['era_1'],
    maxCount: 2,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.mining,
        resource: 'stone',
        mult: 0.5,
        slots: 4,
      ),
    ],
  ),
  'large_quarry': BuildingDef(
    id: 'large_quarry',
    name: 'Large Quarry',
    color: Color(0xFF546E7A),
    gridW: 4,
    gridH: 4,
    resourceCost: {'wood': 400, 'stone': 300},
    constructionHours: 480 / 3600, // 20 min real time
    eraIds: ['era_1'],
    requiredTechId: 'primitive_masonry',
    maxCount: 1,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.mining,
        resource: 'stone',
        mult: 0.7,
        slots: 10,
      ),
    ],
  ),

  // ── Goods (fishing → fish, hunting → fur) ─────────────────
  'fishing_hut': BuildingDef(
    id: 'fishing_hut',
    name: 'Fishing Hut',
    color: Color(0xFF2E86AB),
    gridW: 3,
    gridH: 2,
    resourceCost: {'wood': 200},
    constructionHours: 240 / 3600, // 10 min real time
    eraIds: ['era_1'],
    requiredTechId: 'fishing',
    maxCount: 2,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.fishing,
        resource: 'fish',
        mult: 0.4,
        slots: 3,
      ),
    ],
  ),
  'hunter_lodge': BuildingDef(
    id: 'hunter_lodge',
    name: 'Hunter Lodge',
    color: Color(0xFF8D6E4A),
    gridW: 3,
    gridH: 3,
    resourceCost: {'wood': 200, 'stone': 150},
    constructionHours: 360 / 3600, // 15 min real time
    eraIds: ['era_1'],
    requiredTechId: 'hunting',
    maxCount: 2,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.hunting,
        resource: 'fur',
        mult: 0.4,
        slots: 4,
      ),
    ],
  ),

  // ── Special buildings — each unlocked by its own tech ───────
  'thinker_circle': BuildingDef(
    id: 'thinker_circle',
    name: 'Thinker Circle',
    color: Color(0xFF5C6BC0),
    gridW: 3,
    gridH: 3,
    resourceCost: {'wood': 400, 'stone': 400},
    constructionHours: 480 / 3600, // 20 min real time
    eraIds: ['era_1'],
    requiredTechId: 'tribal_knowledge',
    // Dedicated research workshop — many more slots than the Tribal Center's
    // starter pair, for serious research throughput.
    workshops: [
      WorkshopRole(
        stat: CreatureStat.research,
        resource: WorkshopRole.kResearch,
        mult: 40,
        slots: 8,
      ),
    ],
  ),
  'builder_camp': BuildingDef(
    id: 'builder_camp',
    name: 'Builder Camp',
    color: Color(0xFF546E7A),
    gridW: 2,
    gridH: 2,
    resourceCost: {'wood': 300, 'stone': 400},
    constructionHours: 480 / 3600, // 20 min real time
    eraIds: ['era_1'],
    requiredTechId: 'construction_planning',
    // Dedicated construction workshop + an extra build queue slot.
    queueSlotsBonus: 1,
    workshops: [
      WorkshopRole(
        stat: CreatureStat.construction,
        resource: WorkshopRole.kConstruction,
        mult: 30,
        slots: 8,
      ),
    ],
  ),
  'explorer_camp': BuildingDef(
    id: 'explorer_camp',
    name: 'Explorer Camp',
    color: Color(0xFF00897B),
    gridW: 2,
    gridH: 4,
    resourceCost: {'wood': 300, 'stone': 300},
    constructionHours: 480 / 3600, // 20 min real time
    eraIds: ['era_1'],
    requiredTechId: 'exploration',
    // No function yet — Expeditions don't exist in this codebase.
  ),
  'trading_post': BuildingDef(
    id: 'trading_post',
    name: 'Trading Post',
    color: Color(0xFFFFB300),
    gridW: 3,
    gridH: 3,
    resourceCost: {'wood': 500, 'stone': 500},
    constructionHours: 480 / 3600, // 20 min real time
    eraIds: ['era_1'],
    requiredTechId: 'barter_trade',
    // Gold workshop (prospecting stat → gold) — gold's only production source.
    workshops: [
      WorkshopRole(
        stat: CreatureStat.prospecting,
        resource: 'gold',
        mult: 0.3,
        slots: 6,
      ),
    ],
  ),
  'warrior_grounds': BuildingDef(
    id: 'warrior_grounds',
    name: 'Warrior Grounds',
    color: Color(0xFF8B2020),
    gridW: 3,
    gridH: 3,
    resourceCost: {'wood': 500, 'stone': 700},
    constructionHours: 600 / 3600, // 25 min real time
    eraIds: ['era_1'],
    requiredTechId: 'warrior_training',
    // No function yet — Military/warrior units don't exist in this codebase.
  ),

  // ── Territory expansion — doesn't occupy space once built, only marks
  //    6x6 of new buildable ground (see isBuildPlot) ──────────────────
  'building_plot': BuildingDef(
    id: 'building_plot',
    name: 'Building Plot',
    color: Color(0xFF8D6E4A),
    gridW: 6,
    gridH: 6,
    resourceCost: {'wood': 200, 'stone': 150},
    constructionHours: 120 / 3600, // 5min real time @ reference scenario (cap)
    eraIds: ['era_1'],
    requiredTechId: 'expansion',
    isBuildPlot: true,
    maxCount: 0,
  ),
};

// Live, mutable roster — GameDefsController replaces its contents in place
// once DB-backed defs load or a dev-mode edit arrives (`.clear()` + `.addAll(...)`).
// Every other file references this exact map object, so nothing else needs
// to change for def edits to propagate.
final Map<String, BuildingDef> kBuildingDefs = Map.of(kFallbackBuildingDefs);

List<BuildingDef> availableBuildings(
  String currentEraId,
  Set<String> unlockedTechs,
) => kBuildingDefs.values
    .where(
      (b) =>
          !b.isMainBuilding &&
          !b.isRoad &&
          (b.eraIds.isEmpty || b.eraIds.contains(currentEraId)) &&
          (b.requiredTechId == null ||
              unlockedTechs.contains(b.requiredTechId)),
    )
    .toList();
