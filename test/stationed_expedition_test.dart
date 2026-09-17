import 'package:flutter_test/flutter_test.dart';

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

  // The three tests that used to live here (spot-count parity across
  // regions, per-resource gather dials, "region 1 has a stone spot") all
  // asserted properties of the bundled kFallbackAreaDefs content. That list
  // is deliberately empty now (user 2026-09-08: the placeholder regions are
  // gone; a fresh install has no region until Dev Mode/DB defines one) — the
  // invariants they guarded are the DB content's responsibility, not
  // something a unit test can see.
}
