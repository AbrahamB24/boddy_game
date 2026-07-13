import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/tech_definitions.dart';

// Dev Mode Balance tab's "Simulation" mode — the time-axis companion to
// balance_simulator.dart's instantaneous min/max snapshot. Answers: starting
// from nothing, how many real days does it take a player with this profile
// to research all of an era's tech and build up to a given target loadout,
// and which resource is the bottleneck along the way?
//
// Mirrors GameEngine.tick()'s exact formula shapes (wood/stone/goods
// production, build/research shared-rate-with-activeCount-divisor, single-
// slot research) so the numbers can't silently drift from the real engine —
// same simplification balance_simulator.dart already makes: no road/
// connectivity model, every built instance is assumed functional. Hour-
// stepped rather than a full per-hour energy replay: `uptimeFraction` below
// is the steady-state duty-cycle closed form, not a tick-by-tick energy
// simulation — accurate on average, much simpler, matches this tool's
// "balance estimate" purpose rather than an exact replay.

// ── Player profile ─────────────────────────────────────────
class PlayerProfile {
  final String name;
  // Real steps/day. 8000 is the game's actual energy break-even point:
  // kDrainPerHour(80/24) * 24h = 80 energy/day drained, kEnergyPerStep(0.01)
  // * 8000 steps = 80 energy/day gained. Below that, energy runs dry some of
  // the time; above it, energy stays topped up. See building_definitions.dart.
  final int stepsPerDay;
  // Real workout BP earned/day, clamped each hour to the era's current daily
  // cap (kBaseWorkoutBpPerDay=20, raised by physical_training once researched).
  final int bpPerDay;
  // Fraction (0-1) of each building's maxLaborers kept staffed once
  // population allows it.
  final double laborerStaffing;
  // Hours of idle time between a research/build slot freeing up and the
  // player re-queuing the next item — models check-in cadence.
  final double reactionDelayHours;

  const PlayerProfile({
    required this.name,
    required this.stepsPerDay,
    required this.bpPerDay,
    required this.laborerStaffing,
    required this.reactionDelayHours,
  });

  double get uptimeFraction => (stepsPerDay / 8000.0).clamp(0.0, 1.0);

  PlayerProfile copyWith({
    String? name,
    int? stepsPerDay,
    int? bpPerDay,
    double? laborerStaffing,
    double? reactionDelayHours,
  }) => PlayerProfile(
    name: name ?? this.name,
    stepsPerDay: stepsPerDay ?? this.stepsPerDay,
    bpPerDay: bpPerDay ?? this.bpPerDay,
    laborerStaffing: laborerStaffing ?? this.laborerStaffing,
    reactionDelayHours: reactionDelayHours ?? this.reactionDelayHours,
  );
}

// bpPerDay values assume completeWorkout()'s 10 BP/minute rate against the
// 200 BP/day cap (SettlementController.kBaseWorkoutBpPerDay) — Optimiert
// stays "cap-hitting" (a ~20 min daily workout already maxes it).
const kPlayerProfilePresets = <PlayerProfile>[
  PlayerProfile(
    name: 'Optimized',
    stepsPerDay: 12000,
    bpPerDay: 200,
    laborerStaffing: 1.0,
    reactionDelayHours: 0,
  ),
  PlayerProfile(
    name: 'Average',
    stepsPerDay: 8000,
    bpPerDay: 100,
    laborerStaffing: 0.7,
    reactionDelayHours: 4,
  ),
  PlayerProfile(
    name: 'Casual',
    stepsPerDay: 4000,
    bpPerDay: 30,
    laborerStaffing: 0.4,
    reactionDelayHours: 24,
  ),
];

// ── Results ─────────────────────────────────────────────────
class TimelineEvent {
  final double day;
  final String label;
  const TimelineEvent(this.day, this.label);
}

class TimelineResult {
  // False if the safety cap (1 simulated year) was hit before the era
  // finished — e.g. uptimeFraction near 0 stalls everything forever.
  final bool completed;
  final double totalDays;
  // Hours where a free research/build slot existed but the resource named
  // by the key couldn't cover it — the "what's actually scarce" signal.
  // Keys: 'wood', 'stone', 'bp', 'population'.
  final Map<String, double> starvedHours;
  final double totalHoursSimulated;
  final List<TimelineEvent> events;
  final int finalPopulation;
  final double finalWood;
  final double finalStone;
  final Map<String, double> finalGoods;

  const TimelineResult({
    required this.completed,
    required this.totalDays,
    required this.starvedHours,
    required this.totalHoursSimulated,
    required this.events,
    required this.finalPopulation,
    required this.finalWood,
    required this.finalStone,
    required this.finalGoods,
  });

  Map<String, double> get starvedFractions => {
    for (final e in starvedHours.entries)
      e.key: totalHoursSimulated > 0 ? e.value / totalHoursSimulated : 0,
  };
}

class _SimBuilding {
  final String typeId;
  double secondsBuilt;
  bool queued;
  bool complete;
  double laborers;
  _SimBuilding({required this.typeId, this.queued = true})
    : secondsBuilt = 0,
      complete = false,
      laborers = 0;
}

class EraTimelineSimulator {
  EraTimelineSimulator._();

  static const double _maxHours = 24 * 365;

  static TimelineResult run(
    PlayerProfile profile,
    Map<String, int> targetCounts, {
    String eraId = 'era_1',
  }) {
    final eraDef = kEraDefs[eraId]!;
    final eraTechs = kTechDefs.values.where((t) => t.eraId == eraId).toList()
      ..sort(
        (a, b) =>
            a.col != b.col ? a.col.compareTo(b.col) : a.row.compareTo(b.row),
      );

    double bpPool = 0;
    // Mirrors SettlementService's actual new-settlement grant — starting
    // from 0 would deadlock the whole sim, since Main Hall itself produces
    // no wood/stone (see building_definitions.dart's note on it) and every
    // tech-free starter building still costs some to place.
    double wood = 500, stone = 300;
    final goods = <String, double>{for (final g in kGoodsDefs.values) g.id: 0};
    final researched = <String>{};
    String? activeTechId;
    double activeTechSeconds = 0;
    double researchIdleHours = 0;
    double buildIdleHours = 0;

    final built = <_SimBuilding>[];
    final builtCounts = <String, int>{};
    for (final def in kBuildingDefs.values) {
      if (def.isMainBuilding) {
        built.add(_SimBuilding(typeId: def.id, queued: false)..complete = true);
        builtCounts[def.id] = 1;
      }
    }

    final starved = <String, double>{
      'wood': 0,
      'stone': 0,
      'bp': 0,
      'population': 0,
    };
    final events = <TimelineEvent>[];
    double hour = 0;

    bool researchDone() => eraTechs.every((t) => researched.contains(t.id));
    bool eraReady() =>
        researchDone() &&
        wood >= (eraDef.advancementCost['wood'] ?? 0) &&
        stone >= (eraDef.advancementCost['stone'] ?? 0);

    while (hour < _maxHours) {
      if (eraReady()) break;

      final tb = techBonusTotals(researched);
      final eb = eraBonusTotals(eraDef.order);

      // ── BP income (capped to the current daily cap, averaged hourly) ──
      // 200 mirrors SettlementController.kBaseWorkoutBpPerDay — not imported
      // directly since that class pulls in Provider/Supabase and this file
      // stays pure logic (no Flutter/UI/DB), see the file header.
      final dailyCap = 200 * (1 + tb.workoutBp + eb.workoutBp);
      final bpRatePerHour =
          profile.bpPerDay.toDouble().clamp(0.0, dailyCap) / 24.0;
      bpPool += bpRatePerHour;

      final completeBuildings = built.where((b) => b.complete);

      // ── Population + laborer assignment ──
      double popRaw = 0, popBonusTotal = 0;
      for (final b in completeBuildings) {
        final def = kBuildingDefs[b.typeId]!;
        final needBonus =
            (def.needGoodId != null && (goods[def.needGoodId] ?? 0) > 0)
            ? def.needPopulationBonus
            : 0.0;
        popRaw += def.population * (1 + needBonus);
        popBonusTotal += def.populationBonus;
      }
      final population = (popRaw * (1 + popBonusTotal)).round();
      var idlePop = population.toDouble();
      var populationLimited = false;
      for (final b in completeBuildings) {
        final def = kBuildingDefs[b.typeId]!;
        final want = profile.laborerStaffing * def.maxLaborers;
        final assign = want
            .clamp(0.0, idlePop)
            .clamp(0.0, def.maxLaborers.toDouble());
        if (assign < want - 0.01) populationLimited = true;
        b.laborers = assign;
        idlePop -= assign;
      }
      if (populationLimited) starved['population'] = starved['population']! + 1;

      // ── Production (wood/stone/goods/gold — gold not tracked, no Era I sink yet) ──
      double woodRate = 0, stoneRate = 0;
      double woodBonusPct = tb.wood + eb.wood,
          stoneBonusPct = tb.stone + eb.stone;
      final goodsRate = <String, double>{};
      double buildSpeedBase = 0, buildSpeedPct = 0, buildSpeedFlat = 0;
      // Flat % research-time reduction (Thinker Circle etc.) — NOT a rate.
      // Research needs no building at all to progress; this only shortens
      // the tech's own researchSeconds, mirrored from GameEngine.tick().
      double researchSpeedBonusPct = 0;
      for (final b in completeBuildings) {
        final def = kBuildingDefs[b.typeId]!;
        woodRate += def.woodBase + def.woodPerWorker * b.laborers;
        stoneRate += def.stoneBase + def.stonePerWorker * b.laborers;
        for (final e in def.goodsBase.entries) {
          goodsRate[e.key] =
              (goodsRate[e.key] ?? 0) + e.value * (1 + tb.food + eb.food);
        }
        for (final e in def.goodsPerWorker.entries) {
          goodsRate[e.key] =
              (goodsRate[e.key] ?? 0) +
              e.value * b.laborers * (1 + tb.food + eb.food);
        }
        buildSpeedBase += def.buildSpeedBase;
        buildSpeedPct += def.buildSpeedPctPerWorker * b.laborers;
        buildSpeedFlat += def.buildSpeedBonus;
        researchSpeedBonusPct +=
            def.researchSpeedBase + def.researchSpeedPctPerWorker * b.laborers;
        if (def.needGoodId != null && (goods[def.needGoodId] ?? 0) > 0) {
          woodBonusPct += def.needWoodBonus;
          stoneBonusPct += def.needStoneBonus;
        }
      }
      researchSpeedBonusPct = researchSpeedBonusPct.clamp(0.0, 0.9);
      final uptime = profile.uptimeFraction;
      wood += woodRate * (1 + woodBonusPct) * uptime;
      stone += stoneRate * (1 + stoneBonusPct) * uptime;
      for (final e in goodsRate.entries) {
        goods[e.key] = (goods[e.key] ?? 0) + e.value * uptime;
      }
      for (final def in kBuildingDefs.values) {
        if (def.needGoodId == null || def.needConsumptionPerHour == 0) continue;
        final count = built
            .where((b) => b.typeId == def.id && b.complete)
            .length;
        if (count == 0) continue;
        goods[def.needGoodId!] =
            ((goods[def.needGoodId!] ?? 0) -
                    def.needConsumptionPerHour * count * uptime)
                .clamp(0.0, double.infinity);
      }

      // ── Research (single slot, mirrors GameEngine.tick) ──
      // A real player picks whatever unlocked tech they can afford rather
      // than staring at the one tier-first tech until it's affordable — scan
      // every prerequisite-satisfied tech for one bpPool can already cover;
      // only tally bp-starved if NONE of the ready techs are affordable.
      if (activeTechId == null) {
        TechDef? affordable;
        TechDef? firstReady;
        for (final t in eraTechs) {
          if (researched.contains(t.id)) continue;
          if (!t.prerequisites.every(researched.contains)) continue;
          firstReady ??= t;
          if (bpPool >= t.bpCost) {
            affordable = t;
            break;
          }
        }
        if (affordable != null) {
          if (researchIdleHours >= profile.reactionDelayHours) {
            bpPool -= affordable.bpCost;
            activeTechId = affordable.id;
            activeTechSeconds = 0;
            researchIdleHours = 0;
          } else {
            researchIdleHours += 1;
          }
        } else if (firstReady != null) {
          starved['bp'] = starved['bp']! + 1;
        }
      } else {
        final def = kTechDefs[activeTechId]!;
        final effectiveRequired =
            def.researchSeconds * (1 - researchSpeedBonusPct);
        activeTechSeconds += uptime * 3600;
        if (activeTechSeconds >= effectiveRequired) {
          researched.add(activeTechId);
          events.add(
            TimelineEvent(hour / 24, '${def.emoji} ${def.name} researched'),
          );
          activeTechId = null;
        }
      }

      // ── Construction: progress active sites ──
      final activeSites = built.where((b) => !b.queued && !b.complete).toList();
      if (activeSites.isNotEmpty) {
        final rate =
            buildSpeedBase *
            (1 +
                buildSpeedFlat +
                tb.buildSpeed +
                eb.buildSpeed +
                buildSpeedPct) *
            uptime /
            activeSites.length;
        for (final b in activeSites) {
          final def = kBuildingDefs[b.typeId]!;
          b.secondsBuilt = (b.secondsBuilt + rate).clamp(
            0.0,
            def.constructionSeconds,
          );
          if (b.secondsBuilt >= def.constructionSeconds) {
            b.complete = true;
            builtCounts[b.typeId] = (builtCounts[b.typeId] ?? 0) + 1;
            events.add(
              TimelineEvent(
                hour / 24,
                '${def.name} completed (#${builtCounts[b.typeId]})',
              ),
            );
          }
        }
      }

      // promote queued -> active if a slot is free
      final maxBuildSlots = kBaseBuildSlots + tb.buildSlots;
      var activeCount = built.where((b) => !b.queued && !b.complete).length;
      for (final b in built.where((b) => b.queued)) {
        if (activeCount >= maxBuildSlots) break;
        b.queued = false;
        activeCount++;
      }

      // place a new demanded building if a slot (active or queue) is free.
      // As with research: scan every unlocked, still-under-target building
      // type for one that's affordable right now, rather than staring at a
      // single priority pick — an expensive early-priority building must
      // not permanently block cheaper ones (or population housing) behind it.
      final maxQueueSlots = kBaseQueueSlots + tb.queueSlots;
      final pendingCount = built.where((b) => !b.complete).length;
      if (pendingCount < maxBuildSlots + maxQueueSlots) {
        final pick = _nextDemandedBuilding(
          researched,
          builtCounts,
          built,
          targetCounts,
          wood,
          stone,
        );
        if (pick.affordableId != null) {
          if (buildIdleHours >= profile.reactionDelayHours) {
            final def = kBuildingDefs[pick.affordableId]!;
            wood -= def.resourceCost['wood'] ?? 0;
            stone -= def.resourceCost['stone'] ?? 0;
            built.add(
              _SimBuilding(
                typeId: pick.affordableId!,
                queued: activeCount >= maxBuildSlots,
              ),
            );
            buildIdleHours = 0;
          } else {
            buildIdleHours += 1;
          }
        } else if (pick.blockedId != null) {
          final def = kBuildingDefs[pick.blockedId]!;
          if (wood < (def.resourceCost['wood'] ?? 0)) {
            starved['wood'] = starved['wood']! + 1;
          }
          if (stone < (def.resourceCost['stone'] ?? 0)) {
            starved['stone'] = starved['stone']! + 1;
          }
        }
      }

      hour += 1;
    }

    return TimelineResult(
      completed: hour < _maxHours,
      totalDays: hour / 24,
      starvedHours: starved,
      totalHoursSimulated: hour,
      events: events,
      finalPopulation: (() {
        double popRaw = 0, popBonusTotal = 0;
        for (final b in built.where((b) => b.complete)) {
          final def = kBuildingDefs[b.typeId]!;
          final needBonus =
              (def.needGoodId != null && (goods[def.needGoodId] ?? 0) > 0)
              ? def.needPopulationBonus
              : 0.0;
          popRaw += def.population * (1 + needBonus);
          popBonusTotal += def.populationBonus;
        }
        return (popRaw * (1 + popBonusTotal)).round();
      })(),
      finalWood: wood,
      finalStone: stone,
      finalGoods: goods,
    );
  }

  // Priority = kBuildingDefs' own declaration order, which already follows
  // the tech-tree narrative sequence (see building_definitions.dart) — good
  // enough for a balance estimate, not meant to model perfectly optimal play.
  // Returns the first UNLOCKED, still-under-target building type that's
  // affordable right now (affordableId), or — if none are affordable — the
  // first one that's ready but blocked on cost (blockedId), so the caller
  // can attribute the starvation to the right resource. A type already
  // placed-but-incomplete counts toward its own target so it isn't queued
  // again before the first instance finishes.
  static ({String? affordableId, String? blockedId}) _nextDemandedBuilding(
    Set<String> researched,
    Map<String, int> builtCounts,
    List<_SimBuilding> built,
    Map<String, int> targetCounts,
    double wood,
    double stone,
  ) {
    String? blockedId;
    for (final def in kBuildingDefs.values) {
      if (def.isRoad || def.isMainBuilding) continue;
      final target = targetCounts[def.id] ?? 0;
      if (target <= 0) continue;
      final pending = built
          .where((b) => b.typeId == def.id && !b.complete)
          .length;
      if ((builtCounts[def.id] ?? 0) + pending >= target) continue;
      if (def.requiredTechId != null &&
          !researched.contains(def.requiredTechId)) {
        continue;
      }
      final affordable =
          wood >= (def.resourceCost['wood'] ?? 0) &&
          stone >= (def.resourceCost['stone'] ?? 0);
      if (affordable) return (affordableId: def.id, blockedId: null);
      blockedId ??= def.id;
    }
    return (affordableId: null, blockedId: blockedId);
  }
}
