import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/services/expedition_targets.dart';

// What the Expeditions screen offers now that the map no longer does (user
// 2026-07-25). The list has to stay tied to campaign progress: a screen that is
// always reachable from the main nav must not become a back door into a region
// the player hasn't opened.

void main() {
  setUp(() {
    kAreaDefs
      ..clear()
      ..addAll({for (final a in kFallbackAreaDefs) a.id: a});
  });

  group('only unlocked regions are offered', () {
    test('a fresh player sees region 1 alone', () {
      final areas = unlockedAreas(1);
      expect(areas, hasLength(1));
      expect(areas.first.battleStage, 1);
    });

    test('clearing a region boss adds the next one, keeping the old', () {
      final areas = unlockedAreas(2).map((a) => a.battleStage).toList();
      expect(areas, [1, 2]);
    });

    test('regions come in map order, not definition order', () {
      final stages = unlockedAreas(3).map((a) => a.battleStage).toList();
      expect(stages, [1, 2, 3]);
    });
  });

  group('targets in a region', () {
    test('every resource spot plus exactly one hunt, hunt last', () {
      final area = kFallbackAreaDefs.first;
      final targets = targetsIn(area);
      expect(targets.length, area.spots.length + 1);
      expect(targets.where((t) => t.isHunt), hasLength(1));
      expect(targets.last.isHunt, isTrue,
          reason: 'gathering is the everyday trip and should lead');
    });

    test('a gather target carries its spot; a hunt carries none', () {
      final targets = targetsIn(kFallbackAreaDefs.first);
      final gather = targets.first;
      expect(gather.spot, isNotNull);
      expect(gather.label, gather.spot!.resource);
      expect(targets.last.spot, isNull);
      expect(targets.last.label, 'Hunt');
    });

    test('ids are unique across every offered target', () {
      final ids = expeditionTargets(3).map((t) => t.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });

  test('a locked region contributes no targets at all', () {
    final earlyIds = expeditionTargets(1).map((t) => t.id).toSet();
    final laterArea = kFallbackAreaDefs.firstWhere((a) => a.battleStage == 2);
    for (final t in targetsIn(laterArea)) {
      expect(earlyIds, isNot(contains(t.id)));
    }
  });

  test('no areas defined at all degrades to an empty list, not a crash', () {
    kAreaDefs.clear();
    expect(expeditionTargets(9), isEmpty);
    expect(unlockedAreas(9), isEmpty);
  });
}
