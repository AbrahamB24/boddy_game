import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/services/overworld_layout.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';
import 'package:boddygame/features/creatures/services/region_dungeon.dart';

// The layout test next door checks the rules; this one runs against the BUNDLED
// content at a realistic size — Era I alone threads ~25 nodes onto one line, and
// a spacing rule that holds for four nodes says nothing about twenty-five.

void main() {
  // kFallbackAreaDefs is empty (user 2026-09-08: the placeholder regions are
  // gone), so the bundled fallback path's nodes carry no areaId at all now —
  // that association only exists once Dev Mode/DB defines an area at a
  // region's battleStage. A fresh kAreaDefs (no local seeding needed) matches
  // that bare state.

  List<OverworldNode> build() => buildLinearOverworld(battlesCleared: 0);

  test('the real map is not empty and is Era I only at the start', () {
    final nodes = build();
    expect(nodes, hasLength(greaterThan(15)));
    // Every node belongs to the first region while nothing beyond it is
    // reached — with no area content authored, that region has no areaId.
    expect(nodes.map((n) => n.areaId).toSet(), {''});
  });

  test('no two real nodes overlap on the line', () {
    const discSize = 58.0;
    final nodes = build();
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        expect(
          (nodes[i].pos - nodes[j].pos).distance,
          greaterThan(discSize),
          reason: '${nodes[i].label} overlaps ${nodes[j].label}',
        );
      }
    }
  });

  test('every real node lands inside the canvas', () {
    final nodes = build();
    final canvas = overworldCanvasSize(nodes);
    for (final n in nodes) {
      expect(n.pos.dx, inInclusiveRange(0.0, canvas.width), reason: n.label);
      expect(n.pos.dy, inInclusiveRange(0.0, canvas.height), reason: n.label);
    }
  });

  test('the line climbs in pathIndex order and the boss caps it', () {
    final nodes = build()..sort((a, b) => a.pathIndex.compareTo(b.pathIndex));
    for (var i = 1; i < nodes.length; i++) {
      // Higher pathIndex = further up = smaller y.
      expect(nodes[i].pos.dy, lessThan(nodes[i - 1].pos.dy));
    }
    expect(nodes.last.isBoss, isTrue,
        reason: 'nothing sits beyond the era boss');
  });

  test('spawnPathBattle scales the pack to the battle number', () {
    const area = AreaDef(
      id: 'region_1',
      name: 'Region I',
      emoji: '1️⃣',
      order: 1,
      battleStage: 1,
    );
    // An area with no authored species pool, so eligibleSpecies falls
    // back to ALL defined species — empty in a bare test → a graceful null.
    // The scaling rule itself lives in overworld_path (party size), asserted in
    // overworld_path_test; here we only pin the graceful-empty contract.
    expect(spawnPathBattle(area, 1), isNull);
    // And the party-size the battle would field follows the line position.
    expect(partySizeForBattle(1), 1);
    expect(partySizeForBattle(6), 2);
  });
}
