import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/tech_definitions.dart';
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
  final double researchSecondsBuilt;
  final bool researchComplete;

  const GameTickResult({
    required this.energy,
    required this.resources,
    required this.buildings,
    this.researchSecondsBuilt = 0,
    this.researchComplete = false,
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
      if (def != null) total += def.buildSpeedBonus;
    }
    return total;
  }

  // Extra build queue slots granted by functional buildings (e.g. Builder
  // Camp) — added on top of kBaseQueueSlots/tech-granted slots.
  static int buildingsQueueSlotsBonusTotal(List<PlacedBuilding> buildings) {
    final connected = connectedBuildingIds(buildings);
    int total = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def != null) total += def.queueSlotsBonus;
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

  static bool isAreaBuildable(
    int x,
    int y,
    int w,
    int h,
    List<PlacedBuilding> buildings,
  ) {
    final region = buildableRegionCells(buildings);
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
    List<PlacedBuilding> buildings,
  ) {
    final region = buildableRegionCells(buildings);
    for (int dx = 0; dx < w; dx++) {
      for (int dy = 0; dy < h; dy++) {
        if (region.contains(_cellKey(x + dx, y + dy))) return true;
      }
    }
    return _borderCells(x, y, w, h).any(region.contains);
  }

  // ── Needs system ───────────────────────────────────────────
  // A building's need bonuses are active exactly while its required good has
  // stock > 0 — no penalty when it runs out, the bonus just switches off.
  static bool _needFulfilled(BuildingDef def, Map<String, double> goodsStock) =>
      def.needGoodId != null && (goodsStock[def.needGoodId] ?? 0) > 0;

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
    String? activeResearchId,
    double researchSecondsBuilt = 0,
  }) {
    final hoursDelta =
        now.difference(energy.lastUpdatedAt).inMicroseconds / 3.6e9;
    if (hoursDelta <= 0) {
      return GameTickResult(
        energy: energy,
        resources: resources,
        buildings: buildings,
        researchSecondsBuilt: researchSecondsBuilt,
      );
    }

    final startEnergy = energy.currentEnergy;
    if (startEnergy <= 0) {
      return GameTickResult(
        energy: energy.copyWith(lastUpdatedAt: now),
        resources: resources,
        buildings: buildings,
        researchSecondsBuilt: researchSecondsBuilt,
      );
    }

    final drainNeeded = kDrainPerHour * hoursDelta;
    final double effectiveHours = startEnergy >= drainNeeded
        ? hoursDelta
        : startEnergy / kDrainPerHour;

    final connected = connectedBuildingIds(buildings);
    final goodsStock = resources.goods;

    // Percentage bonuses still come from functional buildings (needs system +
    // build-speed buildings) — they layer on top of the creature-driven power.
    double woodBonusPct = 0, stoneBonusPct = 0;
    double goldMult = 1.0;
    double buildingsBuildSpeedBonus = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      buildingsBuildSpeedBonus += def.buildSpeedBonus;
      if (_needFulfilled(def, goodsStock)) {
        woodBonusPct += def.needWoodBonus;
        stoneBonusPct += def.needStoneBonus;
        goldMult += def.needGoldBonus;
      }
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
    final newGold = resources.gold + goldPower * goldMult * effectiveHours;

    // Construction: creatures stationed in construction roles produce
    // build-seconds/hour (workshopPower['construction']), split evenly across
    // all active (non-queued) build sites. Zero builders = nothing builds.
    final buildPower = workshopPower[WorkshopRole.kConstruction] ?? 0;
    final activeCount = buildings
        .where(
          (b) =>
              !b.isComplete && !b.isQueued && b.constructionSecondsRequired > 0,
        )
        .length;
    final buildSecondsGained = activeCount > 0
        ? buildPower *
              (1.0 + techBuildSpeed + buildingsBuildSpeedBonus) *
              effectiveHours /
              activeCount
        : 0.0;

    final newBuildings = buildings.map((b) {
      if (b.isComplete || b.isQueued || b.constructionSecondsRequired <= 0) {
        return b;
      }
      final newBuilt = (b.constructionSecondsBuilt + buildSecondsGained).clamp(
        0.0,
        b.constructionSecondsRequired,
      );
      return b.copyWith(
        constructionSecondsBuilt: newBuilt,
        isComplete: newBuilt >= b.constructionSecondsRequired,
      );
    }).toList();

    final newGoods = _tickGoods(
      buildings,
      resources.goods,
      workshopPower,
      creatureCount,
      effectiveHours,
      techGoods,
      connected,
    );

    // Research: creatures in research roles produce research-seconds/hour
    // (workshopPower['research']), accrued into the active tech until it
    // reaches its own researchSeconds. Zero researchers = no progress.
    final researchPower = workshopPower[WorkshopRole.kResearch] ?? 0;
    double newResearchSecondsBuilt = researchSecondsBuilt;
    bool researchComplete = false;
    if (activeResearchId != null) {
      final researchDef = kTechDefs[activeResearchId];
      if (researchDef != null) {
        newResearchSecondsBuilt =
            (researchSecondsBuilt + researchPower * effectiveHours)
                .clamp(0.0, researchDef.researchSeconds);
        researchComplete =
            newResearchSecondsBuilt >= researchDef.researchSeconds;
      }
    }

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
        wood: newWood,
        stone: newStone,
        gold: newGold,
        goods: newGoods,
        lastUpdatedAt: now,
      ),
      buildings: newBuildings,
      researchSecondsBuilt: newResearchSecondsBuilt,
      researchComplete: researchComplete,
    );
  }

  // ── Goods tick ────────────────────────────────────────────
  static Map<String, double> _tickGoods(
    List<PlacedBuilding> buildings,
    Map<String, double> currentGoods,
    Map<String, double> workshopPower,
    int creatureCount,
    double hours,
    double techGoods,
    Set<String> connected,
  ) {
    final needConsumption = _needConsumptionTotals(buildings, connected);
    final newGoods = Map<String, double>.from(currentGoods);
    for (final gDef in kGoodsDefs.values) {
      final rate = (workshopPower[gDef.id] ?? 0) * (1 + techGoods);
      final produced = rate * hours;
      final consumed =
          (creatureCount * gDef.consumptionPerCapitaPerHour +
              (needConsumption[gDef.id] ?? 0)) *
          hours;
      newGoods[gDef.id] = ((newGoods[gDef.id] ?? 0) + produced - consumed)
          .clamp(0.0, double.infinity);
    }
    return newGoods;
  }

  // Real per-building upkeep, keyed by the good it drains — e.g. every
  // functional Hut drinks 1 Fish/h regardless of whether its own need-bonus is
  // currently active. Independent of creatures' per-capita consumption.
  static Map<String, double> _needConsumptionTotals(
    List<PlacedBuilding> buildings,
    Set<String> connected,
  ) {
    final totals = <String, double>{};
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || def.needGoodId == null) continue;
      if (def.needConsumptionPerHour == 0) continue;
      totals[def.needGoodId!] =
          (totals[def.needGoodId!] ?? 0) + def.needConsumptionPerHour;
    }
    return totals;
  }

  // ── Housing capacity ──────────────────────────────────────
  // How many creatures the settlement can shelter — the sum of every
  // functional housing building's capacity (needPopulationBonus/populationBonus
  // still boost it, matching the old population math so existing housing tuning
  // carries over unchanged; they just now cap the collection instead of
  // spawning workers).
  static int housingCapacity(
    List<PlacedBuilding> buildings,
    Map<String, double> goodsStock,
  ) {
    final connected = connectedBuildingIds(buildings);
    double cap = 0;
    double bonusTotal = 0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      final bonus = _needFulfilled(def, goodsStock)
          ? def.needPopulationBonus
          : 0;
      cap += def.housingCapacity * (1 + bonus);
      bonusTotal += def.populationBonus;
    }
    return (cap * (1 + bonusTotal)).round();
  }

  // Grouped-by-type breakdown of housing capacity, for the housing overview.
  static List<ProductionSource> housingSources(
    List<PlacedBuilding> buildings,
    Map<String, double> goodsStock,
  ) {
    final connected = connectedBuildingIds(buildings);
    final functionalBuildings =
        buildings.where((b) => functional(b, connected));
    double bonusTotal = 0;
    for (final b in functionalBuildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def != null) bonusTotal += def.populationBonus;
    }

    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final b in functionalBuildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || def.housingCapacity == 0) continue;
      final bonus = _needFulfilled(def, goodsStock)
          ? def.needPopulationBonus
          : 0;
      final amount = def.housingCapacity * (1 + bonus) * (1 + bonusTotal);
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
  // in the top bar, applying the same need/tech bonuses tick() does. Energy
  // gates everything: zero energy = zero rate.
  static Map<String, double> hourlyRates(
    EnergyModel energy,
    List<PlacedBuilding> buildings,
    Map<String, double> workshopPower,
    Map<String, double> goodsStock, {
    double techWood = 0,
    double techStone = 0,
    double techGoods = 0,
    double techAll = 0,
  }) {
    final connected = connectedBuildingIds(buildings);
    double woodBonusPct = 0, stoneBonusPct = 0, goldMult = 1.0;
    for (final b in buildings.where((b) => functional(b, connected))) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || !_needFulfilled(def, goodsStock)) continue;
      woodBonusPct += def.needWoodBonus;
      stoneBonusPct += def.needStoneBonus;
      goldMult += def.needGoldBonus;
    }
    woodBonusPct += techWood + techAll;
    stoneBonusPct += techStone + techAll;

    final active = energy.currentEnergy > 0 ? 1.0 : 0.0;
    final rates = <String, double>{
      'wood': (workshopPower['wood'] ?? 0) * (1 + woodBonusPct) * active,
      'stone': (workshopPower['stone'] ?? 0) * (1 + stoneBonusPct) * active,
      'gold': (workshopPower['gold'] ?? 0) * goldMult * active,
    };
    for (final gDef in kGoodsDefs.values) {
      rates[gDef.id] =
          (workshopPower[gDef.id] ?? 0) * (1 + techGoods) * active;
    }
    return rates;
  }

  static double hoursUntilEmpty(double currentEnergy) =>
      currentEnergy / kDrainPerHour;
}
