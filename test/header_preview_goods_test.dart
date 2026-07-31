import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';

// ── Die neue Ressource, sobald die Raffinerie fällt (2026-07-31) ──
// "die rafinery wird jeweils beim zweitletzten Knotenpunkt freigeschalten. Ab
// diesem Zeitpunkt, soll oben diese Ressource ebenfalls angezeigt werden."
//
// The header strip asks the ROSTER when a material becomes real, rather than
// hardcoding "the next era's element". These pin the lookup that answer rests
// on — including the one that made the old seed silently wrong: a node reward
// naming a building nobody generates unlocks NOTHING, and looks identical to a
// node reward that works.
void main() {
  test('the Clay Refinery is what the era-I path really unlocks', () {
    // refinery_e1 cannot exist — era I has no element to refine.
    expect(kBuildingDefs.containsKey('refinery_e1'), isFalse);
    expect(elementForEra(1), isNull);
    expect(kBuildingDefs.containsKey('refinery_e2'), isTrue);
    expect(kBuildingUnlockBattle['refinery_e2'], isNotNull,
        reason: 'the seed must grant a building that exists');
  });

  test('every seeded unlock names a building that exists', () {
    // The class of bug this file was written for, guarded for the whole table.
    for (final id in kBuildingUnlockBattle.keys) {
      expect(kBuildingDefs.containsKey(id), isTrue,
          reason: '$id is unlocked by a node but has no def');
    }
  });

  test('the refinery is the second-to-last node of the era', () {
    // 18 regular fights, boss at 19 — so the refinery sits at 18.
    expect(kBuildingUnlockBattle['refinery_e2'], 18);
    for (final entry in kBuildingUnlockBattle.entries) {
      expect(entry.value, lessThanOrEqualTo(18),
          reason: '${entry.key} would land on or past the boss');
    }
  });

  test('a good is traced to the building that makes it', () {
    expect(buildingProduces(kBuildingDefs['refinery_e2']!, 'frame'), isTrue);
    expect(buildingProduces(kBuildingDefs['refinery_e2']!, 'wood'), isFalse,
        reason: 'wood is what it EATS, not what it makes');
  });

  test('the unlock battle of a material is its producer\'s', () {
    final seeded = {
      for (final e in kBuildingUnlockBattle.entries)
        'node_${e.value}': PathNode(
          id: 'node_${e.value}',
          order: e.value,
          name: 'Battle ${e.value}',
          rewards: PathRewards(buildings: [e.key]),
        ),
    };
    final before = {...kPathNodes};
    addTearDown(() => kPathNodes
      ..clear()
      ..addAll(before));
    kPathNodes
      ..clear()
      ..addAll(seeded);

    // Era II's grand works ALSO makes Timber Frame and needs no node — the
    // gated producer is the one that answers, or nothing would ever preview.
    expect(producerUnlockBattle('frame'), 18,
        reason: 'the Clay Refinery is what the path hands you');
    // Only ELEMENTS ever preview (see _previewedGoods), but the lookup itself
    // answers for anything a node gates — wood's bigger works is won at 9.
    expect(producerUnlockBattle('wood'), 9);
    // Nothing makes it, so no battle can hand it to you.
    expect(producerUnlockBattle('not_a_good'), isNull);
  });
}
