import 'dart:math' as math;

import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';

import '../models/energy_model.dart';
import '../models/placed_building.dart';
import '../models/resource_model.dart';

// One row in the "where does this come from" breakdown tooltip — buildings
// of the same type are grouped together (count > 1) since the player thinks
// in terms of "my Lumber Camps", not individual grid positions. A negative
// amount is used for the goods-consumption row.
class ProductionSource {
  final String emoji;
  final String? imageUrl;
  final String label;
  final int count;
  final double amount;

  const ProductionSource({
    this.emoji = '',
    this.imageUrl,
    required this.label,
    required this.count,
    required this.amount,
  });
}

class GameTickResult {
  final EnergyModel energy;
  final ResourceModel resources;
  final List<PlacedBuilding> buildings;

  /// Hours of this tick that actually produced (energy-gated) — lets the
  /// controller accrue tick-proportional extras (passive BP) at exactly the
  /// same uptime the engine used.
  final double effectiveHours;

  /// Building id → the wall-clock moment it FINISHED, for any building that
  /// completed during this tick. A load-time catch-up folds hours of offline
  /// time into one tick, so a building that finished long ago would otherwise
  /// be reported "just now"; this lets the controller timestamp the event to
  /// the real finish. Empty when nothing completed.
  final Map<String, DateTime> completedAt;

  const GameTickResult({
    required this.energy,
    required this.resources,
    required this.buildings,
    this.effectiveHours = 0,
    this.completedAt = const {},
  });
}

// ── Creature-worker economy ───────────────────────────────────────────────────
// Buildings no longer produce anything on their own. Every workshop's output is
// entirely the sum of its stationed creatures' relevant civilian stat (see
// WorkshopRole / SettlementController.workshopPower, which does the summing and
// hands tick() a ready-made `workshopPower` map keyed by resource, plus the
// pseudo-outputs 'construction' and 'research'). tick() therefore never touches
// creatures directly — it just spends that per-hour power, energy-gated, exactly
// as it used to spend the old building base+perWorker rates.
//
// Population is gone: captured creatures ARE the population. Housing buildings
// provide capacity (BuildingDef.housingCapacity) that caps how many creatures a
// player can own; nothing is "reserved" and there's no idle pool.
// ─────────────────────────────────────────────────────────────────────────────
class GameEngine {
  GameEngine._();

  // ── Road connectivity ─────────────────────────────────────
  // A building only "functions" (contributes production/housing/bonuses) if it
  // touches a road tile — edge-adjacent only, no diagonals — that is itself
  // part of a road network reachable from the Main Hall. Roads therefore aren't
  // gated by this check themselves; they ARE the network.
  static int _cellKey(int x, int y) => y * kGridCols + x;

  static Iterable<int> _borderCells(int x, int y, int w, int h) sync* {
    for (int i = 0; i < w; i++) {
      if (y - 1 >= 0) yield _cellKey(x + i, y - 1);
      if (y + h < kGridRows) yield _cellKey(x + i, y + h);
    }
    for (int j = 0; j < h; j++) {
      if (x - 1 >= 0) yield _cellKey(x - 1, y + j);
      if (x + w < kGridCols) yield _cellKey(x + w, y + j);
    }
  }

  static Set<String> connectedBuildingIds(List<PlacedBuilding> buildings) {
    final roadCells = <int>{};
    PlacedBuilding? mainHall;
    for (final b in buildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || !b.isComplete) continue;
      if (def.isRoad) {
        roadCells.add(_cellKey(b.gridX, b.gridY));
      } else if (def.isMainBuilding) {
        mainHall = b;
      }
    }
    if (mainHall == null) return {};
    final mainDef = kBuildingDefs[mainHall.buildingTypeId]!;

    // Flood-fill the road network starting from roads touching the Main Hall.
    final reachableRoads = <int>{};
    final frontier = <int>[];
    for (final c in _borderCells(
      mainHall.gridX,
      mainHall.gridY,
      mainDef.gridW,
      mainDef.gridH,
    )) {
      if (roadCells.contains(c) && reachableRoads.add(c)) frontier.add(c);
    }
    for (int i = 0; i < frontier.length; i++) {
      final key = frontier[i];
      final x = key % kGridCols, y = key ~/ kGridCols;
      for (final n in [
        if (x + 1 < kGridCols) _cellKey(x + 1, y),
        if (x - 1 >= 0) _cellKey(x - 1, y),
        if (y + 1 < kGridRows) _cellKey(x, y + 1),
        if (y - 1 >= 0) _cellKey(x, y - 1),
      ]) {
        if (roadCells.contains(n) && reachableRoads.add(n)) frontier.add(n);
      }
    }

    final connected = <String>{mainHall.id};
    for (final b in buildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || !b.isComplete || def.isRoad || def.isMainBuilding) {
        continue;
      }
      // A Build Plot is a free AREA, not a structure (it has no art) — it just
      // extends buildable territory and never needs a road connection.
      if (def.isBuildPlot) {
        connected.add(b.id);
        continue;
      }
      final touches = _borderCells(
        b.gridX,
        b.gridY,
        def.gridW,
        def.gridH,
      ).any(reachableRoads.contains);
      if (touches) connected.add(b.id);
    }
    return connected;
  }

  static bool functional(PlacedBuilding b, Set<String> connected) =>
      b.isComplete && connected.contains(b.id);

  // Sum of buildSpeedBonus from functional buildings only (e.g. Builder's
  // Guild) — a settlement-wide % on top of the creature-driven construction
  // power. Excludes tech bonuses, which the caller adds via techBuildSpeed.
  static double buildingsBuildSpeedBonusTotal(List<PlacedBuilding> buildings) {
    final connected = connectedBuildingIds(buildings);
    double total = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def != null) {
        total += def.buildSpeedBonus * buildingYieldFactor(b.level);
      }
    }
    return total;
  }

  // Extra build queue slots granted by functional buildings (e.g. Builder
  // Camp) — added on top of kBaseQueueSlots/tech-granted slots. Two sources,
  // summed: the legacy flat [queueSlotsBonus] scalar (globally level-scaled),
  // and the per-level `queueSlots` effect (user 2026-07-25) authored with
  // explicit per-level steps in Dev Mode. Pass the settlement's [eraOrder] so a
  // per-era queueSlots entry only counts once its era is reached.
  static int buildingsQueueSlotsBonusTotal(
    List<PlacedBuilding> buildings, {
    int eraOrder = 99,
  }) {
    final connected = connectedBuildingIds(buildings);
    int total = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      total += (def.queueSlotsBonus * buildingYieldFactor(b.level)).floor();
      total += def.queueSlotsAt(b.level, eraOrder: eraOrder);
    }
    return total;
  }

  // Extra SIMULTANEOUS construction sites granted by functional buildings, from
  // their per-level `buildSlots` effect (user 2026-07-25) — added on top of
  // kBaseBuildSlots + tech-granted slots. Same shape as the queue-slot total;
  // pass the settlement's [eraOrder] so a per-era entry only counts once reached.
  static int buildingsBuildSlotsBonusTotal(
    List<PlacedBuilding> buildings, {
    int eraOrder = 99,
  }) {
    final connected = connectedBuildingIds(buildings);
    int total = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      total += def.buildSlotsAt(b.level, eraOrder: eraOrder);
    }
    return total;
  }

  // ── Buildable territory ────────────────────────────────────
  static Set<int> buildableRegionCells(List<PlacedBuilding> buildings) {
    final cells = <int>{};
    for (int x = kInitialPlotX; x < kInitialPlotX + kInitialPlotSize; x++) {
      for (int y = kInitialPlotY; y < kInitialPlotY + kInitialPlotSize; y++) {
        cells.add(_cellKey(x, y));
      }
    }
    for (final b in buildings) {
      if (!b.isComplete) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || !def.isBuildPlot) continue;
      for (int dx = 0; dx < def.gridW; dx++) {
        for (int dy = 0; dy < def.gridH; dy++) {
          cells.add(_cellKey(b.gridX + dx, b.gridY + dy));
        }
      }
    }
    return cells;
  }

  /// [region] lets a caller pass an already-built region set. Without it this
  /// rebuilds the whole thing — and it's called from the placement ghost on
  /// every pointer move, so the drag path was rebuilding it per frame.
  static bool isAreaBuildable(
    int x,
    int y,
    int w,
    int h,
    List<PlacedBuilding> buildings, {
    Set<int>? region,
  }) {
    region ??= buildableRegionCells(buildings);
    for (int dx = 0; dx < w; dx++) {
      for (int dy = 0; dy < h; dy++) {
        if (!region.contains(_cellKey(x + dx, y + dy))) return false;
      }
    }
    return true;
  }

  static bool touchesBuildableRegion(
    int x,
    int y,
    int w,
    int h,
    List<PlacedBuilding> buildings, {
    Set<int>? region,
  }) {
    region ??= buildableRegionCells(buildings);
    for (int dx = 0; dx < w; dx++) {
      for (int dy = 0; dy < h; dy++) {
        if (region.contains(_cellKey(x + dx, y + dy))) return true;
      }
    }
    return _borderCells(x, y, w, h).any(region.contains);
  }

  // ── Main tick ─────────────────────────────────────────────
  static GameTickResult tick(
    EnergyModel energy,
    ResourceModel resources,
    List<PlacedBuilding> buildings,
    DateTime now, {
    required Map<String, double> workshopPower,
    int creatureCount = 0,
    double techWood = 0,
    double techStone = 0,
    double techGoods = 0,
    double techAll = 0,
    double techBuildSpeed = 0,
    // Multiplicative scale on top of the additive bonuses above — the
    // new-player jumpstart passes 1/kJumpstartTimeScale (= 5x). Separate
    // because the tech/building bonuses are a SUM and this is a factor;
    // folding it in there would make it scale with them.
    double buildSpeedScale = 1.0,
  }) {
    final hoursDelta =
        now.difference(energy.lastUpdatedAt).inMicroseconds / 3.6e9;
    if (hoursDelta <= 0) {
      return GameTickResult(
        energy: energy,
        resources: resources,
        buildings: buildings,
      );
    }

    final startEnergy = energy.currentEnergy;

    // Energy is a BOOST, not a gate (user 2026-07-21): hours with energy in
    // the tank run at full rate, hours after it empties still run at
    // kEnergyFloorRate. An empty settlement slows to a trickle instead of
    // stopping dead — the old hard stop punished exactly the player who
    // hadn't walked, at the moment the game needed to win them back.
    final drainNeeded = kDrainPerHour * hoursDelta;
    final double fullHours = startEnergy <= 0
        ? 0
        : (startEnergy >= drainNeeded
              ? hoursDelta
              : startEnergy / kDrainPerHour);
    final double effectiveHours =
        fullHours + (hoursDelta - fullHours) * kEnergyFloorRate;

    final connected = connectedBuildingIds(buildings);

    // Percentage bonuses still come from functional build-speed buildings —
    // they layer on top of the creature-driven power.
    double woodBonusPct = 0, stoneBonusPct = 0;
    double buildingsBuildSpeedBonus = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      buildingsBuildSpeedBonus += def.buildSpeedBonus;
    }
    woodBonusPct += techWood + techAll;
    stoneBonusPct += techStone + techAll;

    final woodPower = workshopPower['wood'] ?? 0;
    final stonePower = workshopPower['stone'] ?? 0;
    final goldPower = workshopPower['gold'] ?? 0;

    final newWood =
        resources.wood + woodPower * (1 + woodBonusPct) * effectiveHours;
    final newStone =
        resources.stone + stonePower * (1 + stoneBonusPct) * effectiveHours;
    final newGold = resources.gold + goldPower * effectiveHours;

    // Construction: workshopPower['construction'] is a count of BUILD POINTS
    // (stationed builders + passive effects, 1:1), and points buy a percent off
    // the authored build time — buildSpeedFromPoints is 1/(1 − that cut), so
    // 3600 × it is the build-seconds one real hour is worth. EVERY active site
    // builds at the FULL rate (user 2026-07-24: no split across sites).
    //
    // Zero builders no longer means zero progress (user 2026-07-26): a site
    // with nobody on it advances at 3600 s/h, i.e. finishes in exactly the time
    // its def says. Builders only ever make that shorter.
    final buildPoints = workshopPower[WorkshopRole.kConstruction] ?? 0;
    final buildSecondsGained = 3600 *
        buildSpeedFromPoints(buildPoints) *
        (1.0 + techBuildSpeed + buildingsBuildSpeedBonus) *
        buildSpeedScale *
        effectiveHours;

    // Construction only runs during the energy-gated effectiveHours, which
    // occupy the START of this tick's window (energy drains, then work stops),
    // so a build finishes at prevNow + (fraction of the gain it needed) ×
    // effectiveHours. Precise enough to timestamp the "finished" event to when
    // it really happened rather than to screen-open.
    final prevNow = energy.lastUpdatedAt;
    final completedAt = <String, DateTime>{};

    final newBuildings = buildings.map((b) {
      if (b.isComplete || b.isQueued || b.constructionSecondsRequired <= 0) {
        return b;
      }
      final newBuilt = (b.constructionSecondsBuilt + buildSecondsGained).clamp(
        0.0,
        b.constructionSecondsRequired,
      );
      final done = newBuilt >= b.constructionSecondsRequired;
      if (done && buildSecondsGained > 0) {
        final remaining =
            b.constructionSecondsRequired - b.constructionSecondsBuilt;
        final frac = (remaining / buildSecondsGained).clamp(0.0, 1.0);
        completedAt[b.id] = prevNow.add(
          Duration(microseconds: (frac * effectiveHours * 3.6e9).round()),
        );
      }
      return b.copyWith(
        constructionSecondsBuilt: newBuilt,
        isComplete: done,
      );
    }).toList();

    // Refineries buy their input out of THIS tick's yard (raw already banked
    // plus what was just gathered), so a sawmill can eat the wood the camps
    // produced alongside it.
    final goodsTick = _tickGoods(
      resources.goods,
      workshopPower,
      creatureCount,
      effectiveHours,
      techGoods,
      rawStock: {'wood': newWood, 'stone': newStone, 'gold': newGold},
    );
    final newGoods = goodsTick.goods;

    final newEnergyLevel = (startEnergy - kDrainPerHour * hoursDelta).clamp(
      0.0,
      kMaxEnergy,
    );

    return GameTickResult(
      energy: energy.copyWith(
        currentEnergy: newEnergyLevel,
        lastUpdatedAt: now,
      ),
      resources: resources.copyWith(
        wood: newWood - (goodsTick.rawSpent['wood'] ?? 0),
        stone: newStone - (goodsTick.rawSpent['stone'] ?? 0),
        gold: newGold - (goodsTick.rawSpent['gold'] ?? 0),
        goods: newGoods,
        lastUpdatedAt: now,
      ),
      buildings: newBuildings,
      effectiveHours: effectiveHours,
      completedAt: completedAt,
    );
  }

  // ── Goods tick ────────────────────────────────────────────
  /// Produces this tick's goods and returns them together with the RAW
  /// resources the refineries burned (wood/stone/gold), which tick() then
  /// deducts.
  ///
  /// A refined good (GoodsDef.refinedFrom, user 2026-07-22) is throttled to
  /// what its inputs actually cover: a sawmill with no wood in the yard makes
  /// no planks, it doesn't mint them from nothing. Materials are processed in
  /// era order so a chain (planks → steel) can spend what the same tick just
  /// refined.
  static ({Map<String, double> goods, Map<String, double> rawSpent}) _tickGoods(
    Map<String, double> currentGoods,
    Map<String, double> workshopPower,
    int creatureCount,
    double hours,
    double techGoods, {
    Map<String, double> rawStock = const {},
  }) {
    final newGoods = Map<String, double>.from(currentGoods);
    final rawSpent = <String, double>{};
    double rawLeft(String id) => (rawStock[id] ?? 0) - (rawSpent[id] ?? 0);

    final ordered = kGoodsDefs.values.toList()
      ..sort((a, b) {
        final byEra = a.eraOrder.compareTo(b.eraOrder);
        return byEra != 0 ? byEra : a.id.compareTo(b.id);
      });

    for (final gDef in ordered) {
      final rate = (workshopPower[gDef.id] ?? 0) * (1 + techGoods);
      var produced = rate * hours;
      if (produced > 0 && gDef.isElement) {
        // Cap by the scarcest input, then charge every input for what was
        // really made.
        for (final input in gDef.refinedFrom.entries) {
          final available = kGoodsDefs.containsKey(input.key)
              ? (newGoods[input.key] ?? 0)
              : rawLeft(input.key);
          produced = math.min(produced, available / input.value);
        }
        produced = math.max(0, produced);
        for (final input in gDef.refinedFrom.entries) {
          final cost = produced * input.value;
          if (kGoodsDefs.containsKey(input.key)) {
            newGoods[input.key] = ((newGoods[input.key] ?? 0) - cost).clamp(
              0.0,
              double.infinity,
            );
          } else {
            rawSpent[input.key] = (rawSpent[input.key] ?? 0) + cost;
          }
        }
      }
      final consumed = creatureCount * gDef.consumptionPerCapitaPerHour * hours;
      newGoods[gDef.id] = ((newGoods[gDef.id] ?? 0) + produced - consumed)
          .clamp(0.0, double.infinity);
    }
    return (goods: newGoods, rawSpent: rawSpent);
  }

  // ── Housing capacity ──────────────────────────────────────
  // How many creatures the settlement can shelter — the sum of every
  // functional housing building's capacity, scaled by the settlement-wide
  // populationBonus of every functional building.
  static int housingCapacity(List<PlacedBuilding> buildings, {int eraOrder = 1}) {
    final connected = connectedBuildingIds(buildings);
    double cap = 0;
    double bonusTotal = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      // Level scales both a building's own housing and any % bonus it grants.
      final f = buildingYieldFactor(b.level);
      // A per-era `housing` effect OVERRIDES the flat population column — that
      // is how a persistent dwelling shelters more each era.
      // The housing effect carries its own level scaling now; the flat
      // population-column fallback is still scaled by the global curve here.
      final baseCap = def.hasEffect('housing', eraOrder)
          ? def.effectAt('housing', '', eraOrder, level: b.level)
          : def.housingCapacity.toDouble() * f;
      cap += baseCap;
      bonusTotal += def.populationBonus * f;
    }
    return (cap * (1 + bonusTotal)).round();
  }

  // Grouped-by-type breakdown of housing capacity, for the housing overview.
  static List<ProductionSource> housingSources(
    List<PlacedBuilding> buildings, {
    int eraOrder = 1,
  }) {
    final connected = connectedBuildingIds(buildings);
    final functionalBuildings =
        buildings.where((b) => functional(b, connected));
    double bonusTotal = 0;
    for (final b in functionalBuildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def != null) {
        bonusTotal += def.populationBonus * buildingYieldFactor(b.level);
      }
    }

    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final b in functionalBuildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      final baseCap = def.hasEffect('housing', eraOrder)
          ? def.effectAt('housing', '', eraOrder, level: b.level)
          : def.housingCapacity.toDouble() * buildingYieldFactor(b.level);
      if (baseCap == 0) continue;
      final amount = baseCap * (1 + bonusTotal);
      totals[def.id] = (totals[def.id] ?? 0) + amount;
      counts[def.id] = (counts[def.id] ?? 0) + 1;
    }

    final sources = totals.entries.map((e) {
      final def = kBuildingDefs[e.key]!;
      return ProductionSource(
        imageUrl: def.imageUrl,
        label: def.name,
        count: counts[e.key]!,
        amount: e.value,
      );
    }).toList()..sort((a, b) => b.amount.compareTo(a.amount));
    return sources;
  }

  // ── Steps → energy ────────────────────────────────────────
  static EnergyModel addSteps(EnergyModel energy, int steps) {
    final gained = steps * kEnergyPerStep;
    final newEnergy = (energy.currentEnergy + gained).clamp(0.0, kMaxEnergy);
    return energy.copyWith(currentEnergy: newEnergy);
  }

  // ── Hourly display rates ──────────────────────────────────
  // Turns the raw creature-driven workshop power into the per-hour rate shown
  // in the top bar, applying the same tech bonuses tick() does. Energy boosts
  // everything: an empty tank runs at kEnergyFloorRate, not zero.
  static Map<String, double> hourlyRates(
    EnergyModel energy,
    Map<String, double> workshopPower, {
    double techWood = 0,
    double techStone = 0,
    double techGoods = 0,
    double techAll = 0,
  }) {
    final woodBonusPct = techWood + techAll;
    final stoneBonusPct = techStone + techAll;

    final active = energy.currentEnergy > 0 ? 1.0 : kEnergyFloorRate;
    final rates = <String, double>{
      'wood': (workshopPower['wood'] ?? 0) * (1 + woodBonusPct) * active,
      'stone': (workshopPower['stone'] ?? 0) * (1 + stoneBonusPct) * active,
      'gold': (workshopPower['gold'] ?? 0) * active,
    };
    for (final gDef in kGoodsDefs.values) {
      rates[gDef.id] =
          (workshopPower[gDef.id] ?? 0) * (1 + techGoods) * active;
    }
    // A refinery's INPUT is a real drain on the rate the player reads: a
    // sawmill running at 5 planks/h is quietly eating 10 wood/h, and a top bar
    // that showed the gross wood rate would promise a surplus that never
    // arrives. Assumes the inputs are covered (the yard's stock isn't known
    // here) — the same optimism the gross rate already had.
    for (final gDef in kGoodsDefs.values.where((g) => g.isElement)) {
      final made = rates[gDef.id] ?? 0;
      if (made <= 0) continue;
      gDef.refinedFrom.forEach((input, per) {
        rates[input] = (rates[input] ?? 0) - made * per;
      });
    }
    return rates;
  }

  static double hoursUntilEmpty(double currentEnergy) =>
      currentEnergy / kDrainPerHour;
}
