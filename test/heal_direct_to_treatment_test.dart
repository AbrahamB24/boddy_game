import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart' show IntroStep;
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// ── A free slot means TREATMENT, not the line (user 2026-07-30) ──
// "healing hut, wenn treating noch frei ist, direkt dorhin verschieben und nicht
// über die in line."
//
// The old path set `healQueuedAt`, PERSISTED it, notified the UI, and only then
// let the auto-start pull the monster back out — so with a slot standing empty
// the card still appeared under "In line" for the length of a database round
// trip. What this pins is the decision, not the write: with room in the hut,
// nothing is ever put in the queue.
const _hutId = 'test_healing_hut';

void main() {
  final creatures = CreaturesController();
  final settlement = SettlementController();

  PlacedBuilding at(String id, String type, int x, int y) => PlacedBuilding(
    id: id,
    settlementId: 's',
    buildingTypeId: type,
    gridX: x,
    gridY: y,
    level: 1,
    constructionSecondsRequired: 0,
    constructionSecondsBuilt: 0,
    isComplete: true,
    placedAt: DateTime.utc(2026),
  );

  /// A hall, a road touching it and the hut touching the road — the real
  /// road-connection rule, because `healCapacity` only counts a CONNECTED
  /// building. (The tutorial window would connect everything for free, but it
  /// also makes healAll instant and uncapped, which is precisely what these tests
  /// must not run in.)
  List<PlacedBuilding> layout() {
    final hall = kBuildingDefs.values.firstWhere((d) => d.isMainBuilding);
    return [
      at('hall', hall.id, 10, 10),
      at('road', 'road', 10 + hall.gridW, 10),
      at('b', _hutId, 10 + hall.gridW + 1, 10),
    ];
  }

  CreatureInstance mob(String id, {int hp = 10, bool healing = false}) {
    final c = CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      level: 1,
      statBase: {for (final s in CreatureStat.values) s: 20.0},
      statSlope: {for (final s in CreatureStat.values) s: 1.0},
      currentHp: hp,
    );
    if (healing) c.healingUntil = DateTime.now().add(const Duration(hours: 1));
    return c;
  }

  setUp(() {
    // ONE treatment slot, so "full" and "free" are one monster apart.
    kBuildingDefs[_hutId] = BuildingDef(
      id: _hutId,
      name: 'Healing Hut',
      color: const Color(0xFF000000),
      gridW: 1,
      gridH: 1,
      effects: const [
        BuildingEffect(type: 'healSlots', value: 1),
        // A line with room in it — so landing in the queue would SUCCEED, which
        // is what makes the assertions below meaningful.
        BuildingEffect(type: 'healQueue', value: 5),
      ],
    );
    settlement.buildings = layout();
    settlement.introStep = IntroStep.done;
    // A WORKING settlement: treatment refuses on an empty tank and on an empty
    // purse, and both refusals look exactly like "it went to the line instead".
    settlement.energy = EnergyModel(
      settlementId: 's',
      currentEnergy: 100,
      lastUpdatedAt: DateTime.now(),
    );
    settlement.resources = ResourceModel(
      settlementId: 's',
      wood: 99999,
      stone: 99999,
      gold: 99999,
      goods: {for (final g in kGoodsDefs.keys) g: 99999},
      lastUpdatedAt: DateTime.now(),
    );
    creatures.creatures.clear();
  });

  tearDown(() {
    kBuildingDefs.remove(_hutId);
    settlement.buildings = [];
    settlement.energy = null;
    settlement.resources = null;
    creatures.creatures.clear();
  });

  test('the hut really has one slot and a line to stand in', () {
    // Guards the harness itself: with no cap authored every slot is free and the
    // test below would pass for the wrong reason.
    expect(settlement.healCapacity, 1);
    expect(settlement.healQueueCapacity, 5);
  });

  test('with a slot FREE, nothing is put in the line', () async {
    final c = mob('hurt');
    creatures.creatures.add(c);
    await creatures.queueForHealing(c);
    // Straight under treatment, and never in the queue on the way there — that
    // intermediate state is the one the old path passed through.
    expect(c.isHealing, isTrue);
    expect(c.healQueuedAt, isNull);
    expect(creatures.healQueue, isEmpty);
  });

  test('with the slot TAKEN, it joins the line', () async {
    final busy = mob('busy', healing: true);
    final waiting = mob('waiting');
    creatures.creatures.addAll([busy, waiting]);
    expect(creatures.healingCreatures.map((c) => c.id), ['busy']);
    await creatures.queueForHealing(waiting);
    expect(waiting.healQueuedAt, isNotNull);
    expect(creatures.healQueue.map((c) => c.id), ['waiting']);
  });

  test('a full hut AND a full line is a refusal, not a silent drop', () async {
    kBuildingDefs[_hutId] = BuildingDef(
      id: _hutId,
      name: 'Healing Hut',
      color: const Color(0xFF000000),
      gridW: 1,
      gridH: 1,
      effects: const [
        BuildingEffect(type: 'healSlots', value: 1),
        BuildingEffect(type: 'healQueue', value: 0),
      ],
    );
    settlement.buildings = layout();
    final busy = mob('busy', healing: true);
    final waiting = mob('waiting');
    creatures.creatures.addAll([busy, waiting]);
    final err = await creatures.queueForHealing(waiting);
    expect(err, contains('waiting room is full'));
    expect(waiting.healQueuedAt, isNull);
  });

  test('healAll treats whoever fits and queues the rest', () async {
    // Two hurt monsters, one slot: the first must not end up in the line behind
    // an empty treatment bed.
    final a = mob('a', hp: 5);
    final b = mob('b', hp: 8);
    creatures.creatures.addAll([a, b]);
    await creatures.healAll();
    // Worst off first: 'a' takes the slot and is TREATED, 'b' waits.
    expect(a.isHealing, isTrue);
    expect(a.healQueuedAt, isNull);
    expect(creatures.healQueue.map((c) => c.id), ['b']);
  });

  test('an already-full hut sends everyone healAll finds into the line',
      () async {
    creatures.creatures.addAll([
      mob('busy', healing: true),
      mob('x', hp: 4),
      mob('y', hp: 6),
    ]);
    await creatures.healAll();
    expect(creatures.healQueue.map((c) => c.id).toSet(), {'x', 'y'});
  });
}
