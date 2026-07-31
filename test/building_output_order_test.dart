import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/workshop_role_effects.dart';

// User 2026-07-26: "Gold ist über housing bei effects, soll bei housing die
// gleiche Reihenfolge sein. Bitte bei allen Gebäude so übernehmen."
//
// The building dialog has two panels listing the same worker-free outputs: the
// current level, and the upgrade preview. The first renders production and then
// housing, structurally. The second built its list by sorting the keys — and
// the housing sentinel '__housing' sorts before every letter, so one building
// read "Gold, Housing" above and "Housing, Gold" below. Both call
// buildingOutputOrder now, so there is one order and it cannot drift again.

BuildingDef _def(List<BuildingEffect> effects) => BuildingDef(
  id: 'b',
  name: 'B',
  color: const Color(0xFF000000),
  gridW: 1,
  gridH: 1,
  effects: effects,
);

BuildingDef _camp({
  int slots = 2,
  Map<int, int> slotSteps = const {},
  double? levelFactor,
}) => BuildingDef(
  id: 'camp',
  name: 'Camp',
  color: const Color(0xFF000000),
  gridW: 1,
  gridH: 1,
  workshops: [
    WorkshopRole(
      stat: CreatureStat.production,
      resource: 'wood',
      mult: 0.5,
      slots: slots,
      slotSteps: slotSteps,
      levelFactor: levelFactor,
    ),
  ],
);

void main() {
  // User 2026-07-26: "produktionsgebäude: zeige bei upgrade den Effekt, d.h
  // plus 1 Worker meistens oder was das upgrade wirklich bringt."
  //
  // A production building has NO worker-free output, so the upgrade panel —
  // which listed only those — was blank for exactly the buildings whose levels
  // matter most. The two numbers a level really moves are the post count and
  // each worker's multiplier.
  group('what a level buys a production building', () {
    test('a production building HAS something to show now', () {
      final lines = workshopUpgradeLines(_camp(), 1, 2);
      expect(lines, isNotEmpty);
      expect(lines.map((l) => l.label), containsAll(['Workers', 'Per worker']));
    });

    test('+1 worker is stated as the slot count, not as a percentage', () {
      final lines = workshopUpgradeLines(_camp(slotSteps: {2: 1}), 1, 2);
      final workers = lines.firstWhere((l) => l.label == 'Workers');
      expect(workers.now, '2');
      expect(workers.next, '3');
      expect(workers.changed, isTrue);
    });

    test('a level that adds NO worker reports changed=false, so the panel '
        'can drop the row', () {
      // User 2026-07-26: "Stats die gleich bleiben, sollen nicht angezeigt
      // werden" — a "2 → 2" line spends a row of the panel saying nothing and
      // buries the number that did move.
      final workers =
          workshopUpgradeLines(_camp(), 1, 2).firstWhere((l) => l.label == 'Workers');
      expect(workers.now, workers.next);
      expect(workers.changed, isFalse);
    });

    test('per-worker output follows the global +50 %/level curve', () {
      final l = workshopUpgradeLines(_camp(), 1, 2)
          .firstWhere((l) => l.label == 'Per worker');
      expect(l.now, '×1');
      expect(l.next, '×1.5');
    });

    test('an authored per-role factor overrides that curve', () {
      final l = workshopUpgradeLines(_camp(levelFactor: 2.0), 2, 3)
          .firstWhere((l) => l.label == 'Per worker');
      expect(l.now, '×2'); // 2^(2−1)
      expect(l.next, '×4'); // 2^(3−1)
    });

    test('a building with several posts names each one', () {
      final def = BuildingDef(
        id: 'multi',
        name: 'Multi',
        color: const Color(0xFF000000),
        gridW: 1,
        gridH: 1,
        workshops: const [
          WorkshopRole(stat: CreatureStat.production, resource: 'wood'),
          WorkshopRole(
            stat: CreatureStat.medicine,
            resource: WorkshopRole.kHealSpeed,
          ),
        ],
      );
      final labels = workshopUpgradeLines(def, 1, 2).map((l) => l.label);
      expect(labels, contains('Workers · wood'));
      expect(labels, contains('Workers · Healing time'));
    });

    test('a building with no posts contributes no lines', () {
      expect(workshopUpgradeLines(_def(const []), 1, 2), isEmpty);
    });

    test('a flat post (no steps, factor 1) reports nothing changed at all', () {
      // The panel drops every unchanged row, so this def's upgrade preview is
      // empty and the dialog says so in words instead of showing a blank list.
      final lines = workshopUpgradeLines(_camp(levelFactor: 1.0), 1, 2);
      expect(lines, isNotEmpty, reason: 'the lines still exist…');
      expect(lines.where((l) => l.changed), isEmpty, reason: '…but none moved');
    });

    test('only the line that MOVED survives the filter', () {
      // A level that adds a worker but not a factor, and vice versa: the
      // panel's filter is `changed`, so this is the contract it relies on.
      final slotsOnly =
          workshopUpgradeLines(_camp(slotSteps: {2: 1}, levelFactor: 1.0), 1, 2)
              .where((l) => l.changed)
              .map((l) => l.label);
      expect(slotsOnly, ['Workers']);
      final factorOnly = workshopUpgradeLines(_camp(), 1, 2)
          .where((l) => l.changed)
          .map((l) => l.label);
      expect(factorOnly, ['Per worker']);
    });
  });

  // User 2026-07-26: "buildercamp hat bei lvl 3 z.b einen weiteren build slot.
  // Solche Boni sollen über alle Gebäude hinweg bei den upgrades auf das
  // nächste lvl angezeigt werden."
  //
  // The panel listed worker-free OUTPUTS and the work posts, and nothing else —
  // so a level whose entire point was "+1 build site" showed no rows at all.
  group('every per-level bonus shows up in the upgrade preview', () {
    UpgradeLine line(BuildingDef d, int from, int to, String label) =>
        buildingEffectUpgradeLines(d, from, to, 99)
            .firstWhere((l) => l.label == label);

    test('the Builder Camp case: a build slot arriving at a level', () {
      final def = _def(const [
        BuildingEffect(type: 'buildSlots', value: 1, levelSteps: {3: 1}),
      ]);
      final l = line(def, 2, 3, 'Build sites');
      expect(l.now, '1');
      expect(l.next, '2');
      expect(l.changed, isTrue);
      // …and the level BEFORE it changes nothing, so the panel drops the row.
      expect(line(def, 1, 2, 'Build sites').changed, isFalse);
    });

    test('every authored type is offered, in its own unit', () {
      final def = _def(const [
        BuildingEffect(type: 'queueSlots', value: 2),
        BuildingEffect(type: 'trade', value: 5),
        BuildingEffect(type: 'healQueue', value: 3),
        BuildingEffect(type: 'healSlots', value: 1),
      ]);
      final byLabel = {
        for (final l in buildingEffectUpgradeLines(def, 1, 2, 99)) l.label: l,
      };
      expect(byLabel.keys, containsAll(
        ['Queue slots', 'Trade bonus', 'Waiting room', 'Healing slots'],
      ));
      // Units, not bare numbers.
      expect(byLabel['Trade bonus']!.now, '−5 %');
      expect(byLabel['Queue slots']!.now, '2');
    });

    test('a FLAT type is not given a curve it does not have', () {
      // heal/resource/expeditionSlots/huntOptions are read through
      // levelScaleExplicit — a preview that applied +50 %/level here would
      // promise growth the runtime never grants.
      final flat = _def(const [BuildingEffect(type: 'heal', key: 'speed', value: 0.2)]);
      // The key is named when the type has one — "Healing cut · speed" tells
      // time from cost, which a bare "Healing cut" could not.
      final l = line(flat, 1, 4, 'Healing cut · speed');
      expect(l.now, l.next);
      expect(l.changed, isFalse);
      // A SCALED one does grow: +50 %/level by default.
      final scaled = _def(const [BuildingEffect(type: 'trade', value: 10)]);
      expect(line(scaled, 1, 3, 'Trade bonus').next, '−20 %');
    });

    test('an explicit ladder beats the flat default', () {
      // This is what lets the Scout Post open one more hunt length at a level.
      final def = _def(const [
        BuildingEffect(type: 'huntOptions', value: 1, levelSteps: {2: 1}),
      ]);
      expect(line(def, 1, 2, 'Hunt lengths').now, '1');
      expect(line(def, 1, 2, 'Hunt lengths').next, '2');
    });

    test('production and housing are NOT repeated here', () {
      // The outputs table above already carries them; listing them twice is
      // the duplication that started this whole thread.
      final def = _def(const [
        BuildingEffect(type: 'production', key: 'wood', value: 5),
        BuildingEffect(type: 'housing', value: 4),
        BuildingEffect(type: 'buildSlots', value: 1),
      ]);
      final labels =
          buildingEffectUpgradeLines(def, 1, 2, 99).map((l) => l.label);
      expect(labels, ['Build sites']);
    });

    test('an effect from a LATER era is not previewed yet', () {
      final def = _def(const [
        BuildingEffect(type: 'buildSlots', value: 1, era: 3),
      ]);
      expect(buildingEffectUpgradeLines(def, 1, 2, 1), isEmpty);
      expect(buildingEffectUpgradeLines(def, 1, 2, 3), isNotEmpty);
    });
  });

  test('housing comes LAST, whatever it sorts as', () {
    final def = _def(const [
      BuildingEffect(type: 'production', key: 'gold', value: 1),
      BuildingEffect(type: 'housing', value: 5),
    ]);
    expect(
      buildingOutputOrder(def, {kHousingOutputKey, 'gold'}),
      ['gold', kHousingOutputKey],
    );
    // The exact case from the report: alphabetically '__housing' < 'gold', so
    // a plain sort would put it first.
    final sorted = [kHousingOutputKey, 'gold']..sort();
    expect(sorted.first, kHousingOutputKey, reason: 'the old behaviour');
  });

  test('production keys keep the order the DEF authors them in', () {
    // Authoring order, not alphabetical: it is the order shown in the effects
    // editor and the order the current-level panel already uses.
    final def = _def(const [
      BuildingEffect(type: 'production', key: 'wood', value: 1),
      BuildingEffect(type: 'production', key: 'gold', value: 1),
      BuildingEffect(type: 'production', key: 'stone', value: 1),
    ]);
    expect(
      buildingOutputOrder(def, {'stone', 'gold', 'wood'}),
      ['wood', 'gold', 'stone'],
    );
  });

  test('a key the def does not author still gets a stable place', () {
    final def = _def(const [
      BuildingEffect(type: 'production', key: 'gold', value: 1),
    ]);
    expect(
      buildingOutputOrder(def, {kHousingOutputKey, 'gold', 'zzz', 'aaa'}),
      ['gold', 'aaa', 'zzz', kHousingOutputKey],
    );
  });

  test('it never invents or drops a key', () {
    final def = _def(const [
      BuildingEffect(type: 'production', key: 'wood', value: 1),
      BuildingEffect(type: 'production', key: 'fish', value: 1),
    ]);
    // Only what was asked for: 'fish' is authored but not passed in.
    final out = buildingOutputOrder(def, {'wood', kHousingOutputKey});
    expect(out.toSet(), {'wood', kHousingOutputKey});
    expect(out.length, 2, reason: 'no duplicates');
    expect(buildingOutputOrder(def, const <String>[]), isEmpty);
  });

  test('housing-only and production-only buildings both work', () {
    final housingOnly = _def(const [BuildingEffect(type: 'housing', value: 5)]);
    expect(
      buildingOutputOrder(housingOnly, {kHousingOutputKey}),
      [kHousingOutputKey],
    );
    final prodOnly = _def(const [
      BuildingEffect(type: 'production', key: 'wood', value: 1),
    ]);
    expect(buildingOutputOrder(prodOnly, {'wood'}), ['wood']);
  });

  test('every bundled building orders deterministically', () {
    // Same def, same keys, same answer — twice. A Set iteration order leaking
    // into the list is exactly how "it looked fine on my phone" happens.
    for (final def in kFallbackBuildingDefs.values) {
      final keys = <String>{
        ...def.effectKeys('production'),
        if (def.housingCapacity > 0) kHousingOutputKey,
      };
      final a = buildingOutputOrder(def, keys);
      final b = buildingOutputOrder(def, keys.toList().reversed);
      expect(a, b, reason: def.id);
      if (a.contains(kHousingOutputKey) && a.length > 1) {
        expect(a.last, kHousingOutputKey, reason: def.id);
      }
    }
  });
}
