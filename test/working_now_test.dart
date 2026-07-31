import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// ── "Working here" is ONE question (user 2026-07-30) ─────────
// "wie kann ein Monster als idle angestellt sein? Entweder arbeitet es hier, oder
// ist nicht in diesem Gebäude."
//
// It was answered three different ways: CreaturesController.isWorkingNow
// excluded only expeditions, SettlementController's posted-role check excluded
// K.O./mating/expedition but NOT treatment, and the building dialog spelled out a
// third union for its labels. The visible symptoms were a K.O. monster earning
// work XP for a job it could not do, a monster producing fish from a bed in the
// Healing Hut, and a row that said "idle" for two unrelated reasons.
//
// Holding the post while absent stays deliberate — a K.O. lasts minutes and a
// mating hours, and dropping the job would mean re-staffing the whole settlement
// after every lost fight. What changed is that one predicate now decides it.
void main() {
  final ctrl = CreaturesController();

  CreatureInstance worker(String id, {int hp = 20, bool posted = true}) {
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
    if (posted) {
      c.assignedBuildingId = 'b';
      c.assignedStat = CreatureStat.production;
    }
    return c;
  }

  setUp(() {
    ctrl.creatures.clear();
    ctrl.expeditionIds.clear();
    ctrl.breedingIds.clear();
  });

  tearDown(() {
    ctrl.creatures.clear();
    ctrl.expeditionIds.clear();
    ctrl.breedingIds.clear();
  });

  test('a posted, healthy, present monster works', () {
    final c = worker('w');
    expect(c.isAssigned, isTrue);
    expect(ctrl.isWorkingNow(c), isTrue);
  });

  test('an unposted monster is not working, however healthy', () {
    expect(ctrl.isWorkingNow(worker('idle', posted: false)), isFalse);
  });

  test('away on a trip: post held, not working', () {
    final c = worker('w');
    ctrl.expeditionIds.add(c.id);
    expect(c.isAssigned, isTrue, reason: 'the job is still theirs');
    expect(ctrl.isWorkingNow(c), isFalse);
  });

  test('K.O.: post held, not working — and therefore no wage', () {
    // The old rule let this one earn work XP, because XP asked isWorkingNow and
    // production asked a different question.
    final c = worker('w', hp: 0);
    expect(c.isKo, isTrue);
    expect(c.isAssigned, isTrue);
    expect(ctrl.isWorkingNow(c), isFalse);
  });

  test('mating: post held, not working', () {
    final c = worker('w');
    ctrl.breedingIds.add(c.id);
    expect(ctrl.isWorkingNow(c), isFalse);
  });

  test('under treatment: post held, not working', () {
    // The case the label and the economy disagreed about — the dialog was about
    // to say "under treatment" while the building still counted its output.
    final c = worker('w', hp: 5);
    c.healingUntil = DateTime.now().add(const Duration(minutes: 20));
    expect(c.isHealing, isTrue);
    expect(c.isKo, isFalse, reason: 'hurt, not down — the case that slipped through');
    expect(ctrl.isWorkingNow(c), isFalse);
  });

  test('a finished treatment goes straight back to work', () {
    final c = worker('w');
    c.healingUntil = DateTime.now().subtract(const Duration(minutes: 1));
    expect(c.isHealing, isFalse);
    expect(ctrl.isWorkingNow(c), isTrue);
  });
}
