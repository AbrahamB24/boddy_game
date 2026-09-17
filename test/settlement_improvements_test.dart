import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/services/daily_tasks.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';
import 'package:boddygame/features/creatures/services/gather_math.dart';
import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';

void main() {
  // The 2026-07-21 settlement pass, pinned — except its energy floor, which the
  // user reversed on 2026-07-27: an empty tank now stops everything.

  // Defs resolve through the LIVE map, which starts empty in tests.
  setUp(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
  });
  tearDown(kBuildingDefs.clear);

  // ENERGY IS A DAILY-STEPS RATE (user 2026-09-14, replacing the 2026-07-27
  // hard gate this section used to pin): [stepsToday] never gates anything
  // any more, it only scales a continuous rate from a floor (0 steps) up to
  // a capped bonus (10 000 steps), reset each local day.
  group('energy scales the settlement, never stops it', () {
    final res = ResourceModel(
      settlementId: 's',
      wood: 0,
      stone: 0,
      lastUpdatedAt: DateTime.utc(2026, 1, 1),
    );

    test('0 steps runs at the floor rate, never zero', () {
      final energy = EnergyModel(
        settlementId: 's',
        lastUpdatedAt: DateTime.utc(2026, 1, 1),
      );
      final r = GameEngine.tick(
        energy,
        res,
        const [],
        DateTime.utc(2026, 1, 1, 10), // 10h later
        workshopPower: {'wood': 10},
      );
      expect(
        r.effectiveHours,
        closeTo(10 * kEnergyFloorMultiplier, 0.001),
        reason: 'no steps today, but still a working floor rate — never 0',
      );
      expect(r.resources.wood, closeTo(100 * kEnergyFloorMultiplier, 0.1));
    });

    test('the daily step target runs at exactly 100%', () {
      final energy = EnergyModel(
        settlementId: 's',
        stepsToday: kEnergyFullSteps.round(),
        stepsDayKey: dateKeyFor(DateTime.utc(2026, 1, 1).toLocal()),
        lastUpdatedAt: DateTime.utc(2026, 1, 1),
      );
      final r = GameEngine.tick(
        energy,
        res,
        const [],
        DateTime.utc(2026, 1, 1, 2),
        workshopPower: {'wood': 10},
      );
      expect(r.effectiveHours, closeTo(2, 0.001));
    });

    test('steps past the target buy a capped bonus rate', () {
      final maxBoostSteps =
          kEnergyFullSteps +
          1000 * (kEnergyMaxBoost / kEnergyBoostPerThousandSteps);
      expect(
        energyMultiplierForSteps(maxBoostSteps.round()),
        closeTo(1.0 + kEnergyMaxBoost, 0.001),
      );
      // Well past the cap still reads the SAME max — it never keeps climbing.
      expect(
        energyMultiplierForSteps(maxBoostSteps.round() + 5000),
        closeTo(1.0 + kEnergyMaxBoost, 0.001),
      );
    });

    test('a tick spanning midnight resets to the floor, not yesterday\'s rate', () {
      // Yesterday's steps must not silently keep boosting a NEW day that
      // hasn't walked yet.
      final energy = EnergyModel(
        settlementId: 's',
        stepsToday: kEnergyFullSteps.round(),
        stepsDayKey: dateKeyFor(DateTime.utc(2026, 1, 1).toLocal()),
        lastUpdatedAt: DateTime.utc(2026, 1, 1, 23),
      );
      final r = GameEngine.tick(
        energy,
        res,
        const [],
        DateTime.utc(2026, 1, 2, 1), // crosses local midnight
        workshopPower: {'wood': 10},
      );
      expect(r.energy.stepsToday, 0);
      expect(r.energy.stepsDayKey, dateKeyFor(DateTime.utc(2026, 1, 2).toLocal()));
    });

    test('the rate the top bar shows matches the tick\'s own', () {
      final empty = EnergyModel(settlementId: 's', lastUpdatedAt: DateTime.utc(2026));
      final rates = GameEngine.hourlyRates(empty, {'wood': 10});
      expect(rates['wood'], closeTo(10 * kEnergyFloorMultiplier, 0.001));
    });
  });

  group('SettlementController.energyMultiplier reads the live rate', () {
    tearDown(() => SettlementController().energy = null);

    test('the daily target reads 100%', () {
      SettlementController().energy = EnergyModel(
        settlementId: 's',
        stepsToday: kEnergyFullSteps.round(),
        stepsDayKey: dateKeyFor(DateTime.now()),
        lastUpdatedAt: DateTime.now(),
      );
      expect(SettlementController().energyMultiplier, closeTo(1.0, 0.001));
    });

    test('0 steps today reads the floor, not zero', () {
      SettlementController().energy = EnergyModel(
        settlementId: 's',
        stepsDayKey: dateKeyFor(DateTime.now()),
        lastUpdatedAt: DateTime.now(),
      );
      expect(
        SettlementController().energyMultiplier,
        closeTo(kEnergyFloorMultiplier, 0.001),
      );
    });

    test('no settlement loaded reads as the floor, not as unlimited', () {
      SettlementController().energy = null;
      expect(
        SettlementController().energyMultiplier,
        closeTo(kEnergyFloorMultiplier, 0.001),
      );
    });
  });

  group('main hall is fully passive (user 2026-07-22)', () {
    test('the bundled def has no worker slots', () {
      expect(kFallbackBuildingDefs['castle']!.workshops, isEmpty);
    });

    test('a DB row cannot smuggle workshops back onto the main hall', () {
      // DB-authored defs OVERRIDE the fallback (GameDefsController._merge), and
      // the user's live castle row still carried the old construction +
      // crafting slots — which is exactly how they reappeared after the
      // fallback was cleaned. fromDefRow strips them as a RULE.
      final def = BuildingDef.fromDefRow({
        'id': 'castle',
        'name': 'Castle',
        'grid_w': 5,
        'grid_h': 5,
        'is_main_building': true,
        'effects': [
          {'type': 'workshop', 'stat': 'construction', 'resource': 'construction', 'mult': 30, 'slots': 3},
          {'type': 'workshop', 'stat': 'crafting', 'resource': 'research', 'mult': 40, 'slots': 3},
        ],
      });
      expect(def.workshops, isEmpty);
      // ...while an ordinary building keeps its authored workshops.
      final camp = BuildingDef.fromDefRow({
        'id': 'x_camp',
        'name': 'Camp',
        'grid_w': 2,
        'grid_h': 2,
        'effects': [
          {'type': 'workshop', 'stat': 'woodcutting', 'resource': 'wood', 'mult': 0.5, 'slots': 2},
        ],
      });
      expect(camp.workshops, hasLength(1));
    });
  });

  group('era progression (user 2026-07-22)', () {
    test('the level cap is era × 10, formula-based up to 8 eras / Lv 80', () {
      expect(creatureLevelCap(1), 10);
      expect(creatureLevelCap(2), 20);
      expect(creatureLevelCap(8), 80);
      expect(creatureLevelCap(99), 80); // clamped — no era past the last
      expect(kCreatureMaxLevel, kMaxEras * kLevelsPerEra);
    });

    test('the cap forfeits overflow', () {
      // The per-era XP MULTIPLIER that used to be asserted here was deleted on
      // 2026-07-26 ("Ära-Aufholfaktor löschen, das braucht es nicht") — a later
      // era pays more only because its monsters are higher level. The cap is
      // the part of era progression that survives.
      final c = CreatureInstance(
        id: 'c',
        userId: 'u',
        speciesId: 's',
        gender: CreatureGender.male,
        level: 9,
        statBase: const {},
        statSlope: const {},
      );
      c.gainXp(1000000, levelCap: 10);
      expect(c.level, 10, reason: 'era 1 caps at Lv 10');
      expect(c.xp, 0, reason: 'XP past the cap is forfeited, not banked');
    });

    test('building lifetime cap is 10; slots are flat without explicit steps', () {
      // User 2026-07-25: the automatic "+1 slot every 3 levels" rule is gone.
      // A role with no slotSteps keeps a flat count across every level.
      expect(kMaxBuildingLevel, 10);
      const role = WorkshopRole(
        stat: CreatureStat.production,
        resource: 'wood',
        slots: 6,
      );
      expect(effectiveSlots(role, 1), 6);
      expect(effectiveSlots(role, 4), 6);
      expect(effectiveSlots(role, 10), 6);
    });

    test('worker slots grow by explicit per-level slotSteps', () {
      // Slots at level L = base (level 1) + Σ slotSteps up to L.
      const role = WorkshopRole(
        stat: CreatureStat.production,
        resource: 'wood',
        slots: 2,
        slotSteps: {3: 1, 5: 2},
      );
      expect(effectiveSlots(role, 1), 2);
      expect(effectiveSlots(role, 2), 2);
      expect(effectiveSlots(role, 3), 3); // +1 at L3
      expect(effectiveSlots(role, 4), 3);
      expect(effectiveSlots(role, 5), 5); // +2 at L5
      expect(effectiveSlots(role, 10), 5);
    });

    test('the region-2 successor crosses over at its own level ~6', () {
      // The design formula the successor content is authored against: a maxed
      // region-1 building beats the successor's level 1, and the successor
      // wins from level 6.
      final region1MaxYield = buildingYieldFactor(10); // ×5.5
      final mult = regionProductionMult(2); // ×1.6
      expect(mult * buildingYieldFactor(1), lessThan(region1MaxYield));
      expect(mult * buildingYieldFactor(6), greaterThan(region1MaxYield));
    });

    test('old-region buildings stay buildable after pushing on', () {
      // No more EraDef registry to mock (user 2026-09-05) — a building's
      // region gate is read straight off its `eraIds` id strings
      // (`'era_N'`), so nothing needs registering before calling
      // availableBuildings with a region number.
      //
      // Every building now ALSO needs a real node grant (2026-08-31: "nur
      // die Gebäude bauen lassen, welche durch die Kampagne freigespielt
      // wurden") — reusing node_1 for both; its own order doesn't matter
      // here since battlesCleared 999 clears any gate. This test is about
      // REGION gating on top of that, not the grant itself.
      final saved = kPathNodes['node_1']!;
      kPathNodes['node_1'] = PathNode(
        id: saved.id,
        order: saved.order,
        name: saved.name,
        areaId: saved.areaId,
        isBoss: saved.isBoss,
        rewards: PathRewards(
          buildings: [
            ...saved.rewards.buildings,
            'small_wood_camp',
            'clay_camp_e2',
          ],
        ),
      );
      // High battlesCleared so map-progress gating doesn't hide region-1
      // content — this test is about REGION gating only.
      final inRegion2 = availableBuildings(2, 999).map((d) => d.id).toSet();
      expect(inRegion2, contains('small_wood_camp'),
          reason: 'region-1 buildings remain buildable once granted '
              '(user answer 8)');
      expect(inRegion2, contains('clay_camp_e2'));
      // ...and region-2 buildings are NOT offered while still in region 1,
      // even though the SAME node already granted them — the region gate
      // is a second, independent condition.
      final inRegion1 = availableBuildings(1, 999).map((d) => d.id).toSet();
      expect(inRegion1, isNot(contains('clay_camp_e2')));
      kPathNodes['node_1'] = saved;
    });

    test('a building not yet granted by any node is not buildable, even in '
        'its own region', () {
      // Battle 0, the stock fallback path — the earliest anything is
      // granted is node_1 (the Healing Hut) and node_7 (the Build Plot, its
      // own expansionsUnlocked reward system rather than a node grant, but
      // still gated by ITS OWN battle number), so nothing is buildable at
      // all yet (user 2026-08-31: "diejenigen, welche ich noch gar keinem
      // Knoten zugeordnet habe, sollen noch nicht baubar sein").
      final start = availableBuildings(1, 0).map((d) => d.id).toSet();
      expect(start, isEmpty);

      // Granting it a node makes it buildable at that node's battle, same
      // as any other campaign reward — node_1 already grants the Healing
      // Hut in the seed table, so adding the Wood Camp to it proves the
      // grant (not the region) is what changed.
      final saved = kPathNodes['node_1']!;
      kPathNodes['node_1'] = PathNode(
        id: saved.id,
        order: saved.order,
        name: saved.name,
        areaId: saved.areaId,
        isBoss: saved.isBoss,
        rewards: PathRewards(
          buildings: [...saved.rewards.buildings, 'small_wood_camp'],
        ),
      );

      // Winning the first battle unlocks the Healing Hut and the Wood Camp,
      // and nothing else earlier.
      final afterFirst = availableBuildings(1, 1).map((d) => d.id).toSet();
      expect(afterFirst, containsAll(['healing_hut', 'small_wood_camp']));
      expect(afterFirst, isNot(contains('breeding_hut')));
      kPathNodes['node_1'] = saved;
    });
  });

  group('daily tasks', () {
    test('rolls are deterministic per date and distinct kinds', () {
      final a = rollDailyTasks(DateTime.utc(2026, 7, 21));
      final b = rollDailyTasks(DateTime.utc(2026, 7, 21));
      expect(a.tasks.map((t) => t.kind).toList(),
          b.tasks.map((t) => t.kind).toList());
      expect(a.tasks.map((t) => t.kind).toSet(), hasLength(3));
      expect(a.dateKey, '2026-07-21');
    });

    test('a new day rolls a different date key', () {
      final today = rollDailyTasks(DateTime.utc(2026, 7, 21));
      final tomorrow = rollDailyTasks(DateTime.utc(2026, 7, 22));
      expect(today.dateKey, isNot(tomorrow.dateKey));
    });

    test('progress, done and claimable round-trip through json', () {
      final s = rollDailyTasks(DateTime.utc(2026, 7, 21));
      s.tasks.first.progress = s.tasks.first.target;
      expect(s.tasks.first.claimable, isTrue);
      final restored = DailyTasksState.fromJson(s.toJson());
      expect(restored.dateKey, s.dateKey);
      expect(restored.tasks.first.claimable, isTrue);
      expect(restored.claimableCount, 1);
    });
  });

  group('expedition amplifiers in planGather', () {
    final area = AreaDef(
      id: 'a',
      name: 'a',
      emoji: '🌲',
      order: 1,
      battleStage: 1,
      spots: const [],
    );
    const spot = ResourceSpotDef(
      id: 'sp',
      resource: 'wood',
    );
    final member = CreatureInstance(
      id: 'c',
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      level: 10,
      statBase: {CreatureStat.gathering: 25, CreatureStat.carry: 50},
      statSlope: const {},
    );

    test('carryMult raises the load cap, travelMult cuts the overhead', () {
      // Stock well past the load cap, so the CARRY cap is what limits both
      // trips (a spot-limited haul would hide the amplifier entirely).
      const deepStock = 100000.0;
      final plain = planGather(
        area: area,
        spot: spot,
        members: [member],
        availableStock: deepStock,
      );
      final boosted = planGather(
        area: area,
        spot: spot,
        members: [member],
        availableStock: deepStock,
        carryMult: 1.3,
        travelMult: 0.8,
      );
      expect(boosted.loadCap, closeTo(plain.loadCap * 1.3, 0.01));
      expect(boosted.amount, greaterThan(plain.amount));
      // Travel share shrank: same mining rate, bigger haul, yet the trip is
      // not 30% longer — the cut travel absorbs part of it. Compare directly:
      final travelPlain = kTravelSeconds;
      final travelBoosted = travelPlain * 0.8;
      expect(travelBoosted, lessThan(travelPlain));
    });
  });
}
