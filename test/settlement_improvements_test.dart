import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/era_definitions.dart';
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

  // ENERGY IS A GATE AGAIN (user 2026-07-27: "wenn ich keine Energie habe, dann
  // läuft nichts"). It ran at kEnergyFloorRate = 0.30 from 2026-07-21; that
  // constant is 0 now, so an empty tank stops the settlement outright. The
  // assertions still read the constant, so the day it becomes a trickle again
  // they follow it.
  group('energy gates the settlement', () {
    final res = ResourceModel(
      settlementId: 's',
      wood: 0,
      stone: 0,
      lastUpdatedAt: DateTime.utc(2026, 1, 1),
    );

    test('an EMPTY tank produces nothing', () {
      final energy = EnergyModel(
        settlementId: 's',
        currentEnergy: 0,
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
        closeTo(10 * kEnergyFloorRate, 0.001),
        reason: 'no energy, no work (user 2026-07-27)',
      );
      expect(r.resources.wood, closeTo(100 * kEnergyFloorRate, 0.1));
    });

    test('a full tank still runs at 100% — the boost is unchanged', () {
      final energy = EnergyModel(
        settlementId: 's',
        currentEnergy: kMaxEnergy,
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

    test('a tank that empties mid-tick pays only for the hours it had', () {
      // 100 energy lasts 24h; a 48h tick = 24 worked + 24 idle.
      final energy = EnergyModel(
        settlementId: 's',
        currentEnergy: kMaxEnergy,
        lastUpdatedAt: DateTime.utc(2026, 1, 1),
      );
      final r = GameEngine.tick(
        energy,
        res,
        const [],
        DateTime.utc(2026, 1, 3),
        workshopPower: {'wood': 10},
      );
      expect(
        r.effectiveHours,
        closeTo(24 + 24 * kEnergyFloorRate, 0.01),
      );
    });

    test('the rate the top bar shows stops with it', () {
      final empty = EnergyModel(
        settlementId: 's',
        currentEnergy: 0,
        lastUpdatedAt: DateTime.utc(2026),
      );
      final rates = GameEngine.hourlyRates(empty, {'wood': 10});
      expect(rates['wood'], closeTo(10 * kEnergyFloorRate, 0.001));
    });
  });

  group('the action gate reads the same empty', () {
    // Every player-triggered action (expedition, treatment, mating, incubation)
    // asks SettlementController.hasEnergy first, so it has to agree with the
    // tick — including the drain SINCE the last tick, or an action would slip
    // through in the seconds after the tank ran dry.
    tearDown(() => SettlementController().energy = null);

    test('a full tank runs', () {
      SettlementController().energy = EnergyModel(
        settlementId: 's',
        currentEnergy: kMaxEnergy,
        lastUpdatedAt: DateTime.now(),
      );
      expect(SettlementController().hasEnergy, isTrue);
    });

    test('an empty tank refuses', () {
      SettlementController().energy = EnergyModel(
        settlementId: 's',
        currentEnergy: 0,
        lastUpdatedAt: DateTime.now(),
      );
      expect(SettlementController().hasEnergy, isFalse);
    });

    test('a stale anchor is drained forward, not taken at face value', () {
      // 100 energy lasts 24h. An anchor from two days ago means empty NOW,
      // however full the last saved number looks.
      SettlementController().energy = EnergyModel(
        settlementId: 's',
        currentEnergy: kMaxEnergy,
        lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 48)),
      );
      expect(SettlementController().energyNow, 0);
      expect(SettlementController().hasEnergy, isFalse);
    });

    test('no settlement loaded reads as empty, not as unlimited', () {
      SettlementController().energy = null;
      expect(SettlementController().hasEnergy, isFalse);
    });
  });

  group('main hall is fully passive (user 2026-07-22)', () {
    test('the bundled def has no worker slots', () {
      expect(kFallbackBuildingDefs['main_hall']!.workshops, isEmpty);
    });

    test('a DB row cannot smuggle workshops back onto the main hall', () {
      // DB-authored defs OVERRIDE the fallback (GameDefsController._merge), and
      // the user's live main_hall row still carried the old construction +
      // crafting slots — which is exactly how they reappeared after the
      // fallback was cleaned. fromDefRow strips them as a RULE.
      final def = BuildingDef.fromDefRow({
        'id': 'main_hall',
        'name': 'Tribal Center',
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

    test('the era-2 successor crosses over at its own level ~6', () {
      // The design formula the successor content is authored against: a maxed
      // era-1 building beats the successor's level 1, and the successor wins
      // from level 6.
      final era1MaxYield = buildingYieldFactor(10); // ×5.5
      final mult = eraProductionMult(2); // ×1.6
      expect(mult * buildingYieldFactor(1), lessThan(era1MaxYield));
      expect(mult * buildingYieldFactor(6), greaterThan(era1MaxYield));
    });

    test('old-era buildings stay buildable after ascension', () {
      kEraDefs
        ..clear()
        ..addAll({
          'era_1': const EraDef(id: 'era_1', name: 'I', emoji: '🏺', order: 1),
          'era_2': const EraDef(id: 'era_2', name: 'II', emoji: '🥉', order: 2),
        });
      // High battlesCleared so map-progress gating doesn't hide era-1 content —
      // this test is about ERA gating only.
      final inEra2 =
          availableBuildings('era_2', 999).map((d) => d.id).toSet();
      expect(inEra2, contains('wood_camp_e1'),
          reason: 'era-1 buildings remain buildable (user answer 8)');
      expect(inEra2, contains('clay_camp_e2'));
      // ...and era-2 buildings are NOT offered while still in era 1.
      final inEra1 =
          availableBuildings('era_1', 999).map((d) => d.id).toSet();
      expect(inEra1, isNot(contains('clay_camp_e2')));
      kEraDefs.clear();
    });

    test('map-progress unlocks: minimal start roster, healing hut after '
        'battle 1', () {
      kEraDefs
        ..clear()
        ..addAll({
          'era_1': const EraDef(id: 'era_1', name: 'I', emoji: '🏺', order: 1),
        });
      // Battle 0 — a fresh settlement: the gathering camps and the basic house
      // are there, but the campaign rewards are not.
      final start =
          availableBuildings('era_1', 0).map((d) => d.id).toSet();
      expect(start, contains('wood_camp_e1'));
      expect(start, contains('stone_camp_e1'));
      expect(start, contains('hut'));
      expect(start, isNot(contains('healing_hut')));
      expect(start, isNot(contains('breeding_hut')));
      expect(start, isNot(contains('special_treasury_e1')));

      // Winning the first battle unlocks the Healing Hut, and nothing earlier.
      final afterFirst =
          availableBuildings('era_1', 1).map((d) => d.id).toSet();
      expect(afterFirst, contains('healing_hut'));
      expect(afterFirst, isNot(contains('breeding_hut')));
      kEraDefs.clear();
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
      dangerLevel: 2,
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
      final travelPlain = kTravelSecondsPerDanger * area.dangerLevel;
      final travelBoosted = travelPlain * 0.8;
      expect(travelBoosted, lessThan(travelPlain));
    });
  });
}
