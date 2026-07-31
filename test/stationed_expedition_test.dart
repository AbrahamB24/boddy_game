import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/settlement/data/gather_defs.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// A stationed creature may go on an expedition; its building keeps the post
// but loses the output. That rule lives in two halves that must not drift
// apart: availableForExpedition (who may go) and isWorkingNow (who produces).
// Both the settlement's production loop and passive XP read isWorkingNow, so
// these tests are what stop a creature from mining and exploring at once.

CreatureInstance _mob(String id, {String? building, CreatureStat? stat}) =>
    CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      statBase: const {},
      statSlope: const {},
      assignedBuildingId: building,
      assignedStat: stat,
    );

void main() {
  final ctrl = CreaturesController();

  setUp(() {
    ctrl.creatures.clear();
    ctrl.expeditionIds.clear();
  });

  test('a creature stationed in a building can still be sent out', () {
    // The old rule excluded isAssigned, forcing an un-station/re-station round
    // trip just to use your own worker.
    ctrl.creatures.add(_mob('a', building: 'hut_1', stat: CreatureStat.carry));
    expect(ctrl.availableForExpedition().map((c) => c.id), ['a']);
  });

  test('a creature already away is not available twice', () {
    ctrl.creatures.add(_mob('a', building: 'hut_1', stat: CreatureStat.carry));
    ctrl.expeditionIds.add('a');
    expect(ctrl.availableForExpedition(), isEmpty);
  });

  test('away means holds the post but does not work it', () {
    // The whole point of the feature: assignment survives the trip (so the
    // slot is still theirs on return) while production stops.
    final c = _mob('a', building: 'hut_1', stat: CreatureStat.carry);
    ctrl.creatures.add(c);
    expect(ctrl.isWorkingNow(c), isTrue);

    ctrl.expeditionIds.add('a');
    expect(ctrl.isWorkingNow(c), isFalse, reason: 'must stop producing');
    expect(c.isAssigned, isTrue, reason: 'the post must be held for its return');
    expect(c.assignedBuildingId, 'hut_1');
  });

  test('an unstationed creature never counts as working', () {
    ctrl.creatures.add(_mob('a'));
    expect(ctrl.isWorkingNow(ctrl.creatures.single), isFalse);
  });

  test('no region is poorer than the tutorial valley in spot count', () {
    // The ⭐/BP spots left regions 2 and 3 when the currency was deleted. Left
    // alone that made the later, more dangerous regions offer FEWER places to
    // work than the starting valley — the map getting worse as you progress.
    final byOrder = [...kFallbackAreaDefs]..sort((a, b) => a.order - b.order);
    for (final area in byOrder.skip(1)) {
      expect(area.spots.length, greaterThanOrEqualTo(3), reason: area.id);
    }
  });

  test('a resource gathers the same everywhere — richness is per resource', () {
    // Spots carried their own yield/capacity/regen until 2026-07-25, so the
    // same wood spot was richer in one region than another. Those dials moved
    // to Dev Mode → Resources: a region is now distinguished by WHICH resources
    // it offers and by its danger, not by secretly better numbers.
    for (final area in kFallbackAreaDefs) {
      for (final spot in area.spots) {
        final dials = gatherDefFor(spot.resource);
        expect(dials.spotCapacity, greaterThan(0), reason: spot.id);
        expect(dials.secondsPerUnitPerStat, greaterThan(0), reason: spot.id);
      }
    }
  });

  test('region 1 has a stone spot', () {
    // Era I bills stone but region 1 offered none, so the intended ~60%
    // actively-gathered share was unreachable and the era dragged to ~15 days.
    final region1 = kFallbackAreaDefs.firstWhere((a) => a.order == 1);
    expect(region1.spots.where((s) => s.resource == 'stone'), isNotEmpty,
        reason: 'Era I cannot be finished without stone');
  });
}
