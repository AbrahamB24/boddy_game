import '../data/building_definitions.dart';

// Pure, connectivity-free balancing calculator for Dev Mode's "Balance" tab
// (dev/balance_simulator_screen.dart) — lets the user plug in a hypothetical
// building loadout (just counts per building type, no map/roads/positions at
// all, same as their own Excel balancing sheet never modeled connectivity
// either) and see the aggregate stats their sheet already computes by hand:
// min/max production, population capacity, laborer surplus/deficit, etc.
//
// Deliberately mirrors GameEngine.tick()'s exact formula shapes (base +
// perWorker, then the % bonus layer) so these numbers can't silently drift
// from the real engine — the only thing skipped is the `connectedBuildingIds`
// gate, since every counted instance here is assumed complete + connected
// (exactly what the Excel sheet already assumed).
//
// Min = 0 laborers, need-bonuses off (worst case). Max = every instance
// staffed to its own maxLaborers, need-bonuses on (best case) — this
// replaces a separate "needs fulfilled" toggle, since it's the same min/max
// split the Excel sheet itself uses.
//
// Tech/era % bonuses are NOT modeled here — every current Era I tech/era
// bonus field is 0 (nothing in tech_definitions.dart/era_definitions.dart
// sets one yet), so there's nothing to plug in. If a future tech/era adds a
// woodBonus/stoneBonus/etc., thread techBonusTotals(...)/eraBonusTotals(...)
// into the woodMax/stoneMax/etc. formulas below the same way GameEngine does.
class BalanceSnapshot {
  // "Max" (needs-fulfilled) population figure — matches how the Excel sheet
  // itself only ever showed a single "Max Population", not a range.
  final int population;
  final int workerRequirement;
  final int assignablePopulation;
  final int maxLaborerCapacity;
  // assignablePopulation - maxLaborerCapacity — negative means there isn't
  // enough free population to staff every laborer slot to its cap.
  final int laborerBalance;

  final double woodMin, woodMax;
  final double stoneMin, stoneMax;
  final Map<String, double> goodsMin;
  final Map<String, double> goodsMax;
  final double goldMin, goldMax;
  // Real-seconds of construction progress credited per hour, at full
  // capacity — NOT divided by concurrent build-site count (that's a
  // real-time queueing concern, orthogonal to this steady-state capacity
  // figure).
  final double buildSpeedMin, buildSpeedMax;
  // Research has no rate — this is the flat % reduction of a tech's own
  // researchSeconds (Thinker Circle etc.), min = 0 laborers, max = full
  // laborers, both clamped to 0.9 same as GameEngine.tick().
  final double researchSpeedBonusMin, researchSpeedBonusMax;

  final int queueSlotsBonus;
  final int totalTiles;
  final double woodCost, stoneCost;
  // Real per-building upkeep (needConsumptionPerHour) — flat, not
  // laborer-dependent, so no min/max split.
  final Map<String, double> goodsUpkeep;

  const BalanceSnapshot({
    required this.population,
    required this.workerRequirement,
    required this.assignablePopulation,
    required this.maxLaborerCapacity,
    required this.laborerBalance,
    required this.woodMin,
    required this.woodMax,
    required this.stoneMin,
    required this.stoneMax,
    required this.goodsMin,
    required this.goodsMax,
    required this.goldMin,
    required this.goldMax,
    required this.buildSpeedMin,
    required this.buildSpeedMax,
    required this.researchSpeedBonusMin,
    required this.researchSpeedBonusMax,
    required this.queueSlotsBonus,
    required this.totalTiles,
    required this.woodCost,
    required this.stoneCost,
    required this.goodsUpkeep,
  });
}

class BalanceSimulator {
  BalanceSimulator._();

  static BalanceSnapshot compute(Map<String, int> counts) {
    double popRaw = 0;
    double popBonusTotal = 0;
    int workerRequirement = 0;
    int maxLaborerCapacity = 0;

    double woodBase = 0, woodPerWorkerMax = 0;
    double stoneBase = 0, stonePerWorkerMax = 0;
    double needWoodBonusTotal = 0,
        needStoneBonusTotal = 0,
        needGoldBonusTotal = 0;

    final goodsBaseTotal = <String, double>{};
    final goodsPerWorkerMaxTotal = <String, double>{};
    final goodsUpkeep = <String, double>{};

    double goldBase = 0;

    double buildSpeedBaseTotal = 0, buildSpeedPctMaxTotal = 0;
    double buildSpeedBonusFlatTotal = 0;
    double researchSpeedBonusFlatTotal = 0, researchSpeedBonusPctMaxTotal = 0;

    int queueSlotsBonusTotal = 0;
    int totalTiles = 0;
    double woodCost = 0, stoneCost = 0;

    for (final def in kBuildingDefs.values) {
      if (def.isRoad) continue;
      final count = counts[def.id] ?? 0;
      if (count <= 0) continue;

      popRaw += def.population * (1 + def.needPopulationBonus) * count;
      popBonusTotal += def.populationBonus * count;
      workerRequirement += def.workerRequirement * count;
      maxLaborerCapacity += def.maxLaborers * count;

      woodBase += def.woodBase * count;
      woodPerWorkerMax += def.woodPerWorker * def.maxLaborers * count;
      stoneBase += def.stoneBase * count;
      stonePerWorkerMax += def.stonePerWorker * def.maxLaborers * count;

      goldBase += def.goldPerHour * count;

      for (final e in def.goodsBase.entries) {
        goodsBaseTotal[e.key] = (goodsBaseTotal[e.key] ?? 0) + e.value * count;
      }
      for (final e in def.goodsPerWorker.entries) {
        goodsPerWorkerMaxTotal[e.key] =
            (goodsPerWorkerMaxTotal[e.key] ?? 0) +
            e.value * def.maxLaborers * count;
      }

      buildSpeedBaseTotal += def.buildSpeedBase * count;
      buildSpeedPctMaxTotal +=
          def.buildSpeedPctPerWorker * def.maxLaborers * count;
      buildSpeedBonusFlatTotal += def.buildSpeedBonus * count;

      researchSpeedBonusFlatTotal += def.researchSpeedBase * count;
      researchSpeedBonusPctMaxTotal +=
          def.researchSpeedPctPerWorker * def.maxLaborers * count;

      queueSlotsBonusTotal += def.queueSlotsBonus * count;
      totalTiles += def.gridW * def.gridH * count;
      woodCost += (def.resourceCost['wood'] ?? 0) * count;
      stoneCost += (def.resourceCost['stone'] ?? 0) * count;

      if (def.needGoodId != null) {
        needWoodBonusTotal += def.needWoodBonus * count;
        needStoneBonusTotal += def.needStoneBonus * count;
        needGoldBonusTotal += def.needGoldBonus * count;
        if (def.needConsumptionPerHour != 0) {
          goodsUpkeep[def.needGoodId!] =
              (goodsUpkeep[def.needGoodId!] ?? 0) +
              def.needConsumptionPerHour * count;
        }
      }
    }

    final population = (popRaw * (1 + popBonusTotal)).round();
    final assignablePopulation = (population - workerRequirement).clamp(
      0,
      population,
    );
    final laborerBalance = assignablePopulation - maxLaborerCapacity;

    final goodsMin = <String, double>{};
    final goodsMax = <String, double>{};
    for (final gid in {
      ...goodsBaseTotal.keys,
      ...goodsPerWorkerMaxTotal.keys,
    }) {
      final base = goodsBaseTotal[gid] ?? 0;
      goodsMin[gid] = base;
      goodsMax[gid] = base + (goodsPerWorkerMaxTotal[gid] ?? 0);
    }

    return BalanceSnapshot(
      population: population,
      workerRequirement: workerRequirement,
      assignablePopulation: assignablePopulation,
      maxLaborerCapacity: maxLaborerCapacity,
      laborerBalance: laborerBalance,
      woodMin: woodBase,
      woodMax: (woodBase + woodPerWorkerMax) * (1 + needWoodBonusTotal),
      stoneMin: stoneBase,
      stoneMax: (stoneBase + stonePerWorkerMax) * (1 + needStoneBonusTotal),
      goodsMin: goodsMin,
      goodsMax: goodsMax,
      goldMin: goldBase,
      goldMax: goldBase * (1 + needGoldBonusTotal),
      buildSpeedMin: buildSpeedBaseTotal,
      buildSpeedMax:
          buildSpeedBaseTotal *
          (1 + buildSpeedBonusFlatTotal + buildSpeedPctMaxTotal),
      researchSpeedBonusMin: researchSpeedBonusFlatTotal.clamp(0.0, 0.9),
      researchSpeedBonusMax:
          (researchSpeedBonusFlatTotal + researchSpeedBonusPctMaxTotal).clamp(
            0.0,
            0.9,
          ),
      queueSlotsBonus: queueSlotsBonusTotal,
      totalTiles: totalTiles,
      woodCost: woodCost,
      stoneCost: stoneCost,
      goodsUpkeep: goodsUpkeep,
    );
  }
}
