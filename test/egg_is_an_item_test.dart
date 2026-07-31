import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/breeding_job.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';

// An EGG IS AN ITEM (user 2026-07-26: "Bitte ei als Item bezeichnen und somit
// in den Bag senden können"), and that only holds if it carries its own child.
//
// Hatching used to roll the child from the two parents' CURRENT genes, read
// live at hatch time — so an egg was a promise about two other creatures, and
// releasing a parent before it hatched silently turned the child into a fresh
// roll off the species curve. Migration 0027 freezes the child when the egg is
// LAID; these pin both halves of that.

BreedingJob _job({
  BreedingStatus status = BreedingStatus.egg,
  Map<CreatureStat, double> base = const {},
  Map<CreatureStat, double> slope = const {},
}) => BreedingJob(
  id: 'j',
  userId: 'u',
  parentAId: 'a',
  parentBId: 'b',
  speciesId: 's',
  startedAt: DateTime.utc(2026),
  readyAt: DateTime.utc(2026),
  status: status,
  childBase: base,
  childSlope: slope,
);

void main() {
  group('the egg carries its child', () {
    test('a fresh mating carries none — there is no egg yet', () {
      expect(_job(status: BreedingStatus.breeding).hasChildGenes, isFalse);
    });

    test('a laid egg with genes reports it', () {
      final j = _job(base: {CreatureStat.hp: 42});
      expect(j.hasChildGenes, isTrue);
      expect(j.childBase[CreatureStat.hp], 42);
    });

    test('genes survive the DB row round-trip', () {
      final j = _job(
        base: {CreatureStat.hp: 42, CreatureStat.attack: 17.5},
        slope: {CreatureStat.hp: 3},
      );
      final row = {
        'id': j.id,
        'user_id': j.userId,
        'parent_a': j.parentAId,
        'parent_b': j.parentBId,
        'species_id': j.speciesId,
        'started_at': j.startedAt.toIso8601String(),
        'ready_at': j.readyAt.toIso8601String(),
        'status': 'egg',
        'child_base': BreedingJob.genesToJson(j.childBase),
        'child_slope': BreedingJob.genesToJson(j.childSlope),
      };
      final back = BreedingJob.fromRow(row);
      expect(back.childBase[CreatureStat.hp], 42);
      expect(back.childBase[CreatureStat.attack], 17.5);
      expect(back.childSlope[CreatureStat.hp], 3);
    });

    test('a PRE-migration row reads as un-frozen, not as a zeroed child', () {
      // The columns simply are not there. Reading that as "all genes 0" would
      // hatch a statless creature; it has to mean "hatch the old way".
      final back = BreedingJob.fromRow({
        'id': 'j',
        'user_id': 'u',
        'parent_a': 'a',
        'parent_b': 'b',
        'species_id': 's',
        'started_at': DateTime.utc(2026).toIso8601String(),
        'ready_at': DateTime.utc(2026).toIso8601String(),
        'status': 'egg',
      });
      expect(back.hasChildGenes, isFalse);
      expect(back.childBase, isEmpty);
    });

    test('genes are written under the CURRENT stat names', () {
      // A row heals itself: whatever it was saved as, it comes back keyed by
      // the names the enum uses today.
      final json = BreedingJob.genesToJson({CreatureStat.breeding: 9});
      expect(json, {'breeding': 9.0});
      expect(BreedingJob.genesFromJson(json)[CreatureStat.breeding], 9);
    });

    test('a retired stat in an old row is dropped, not crashed on', () {
      // `mining` is one of the four era-I trade stats deleted on 2026-07-25. It
      // resolves for CONTENT (a workshop row) but never as a GENE — an old roll
      // is re-rolled from the species curve, not inherited.
      final genes = BreedingJob.genesFromJson({'mining': 5, 'hp': 20});
      expect(genes[CreatureStat.hp], 20);
      expect(genes.length, 1, reason: 'mining no longer exists');
    });
  });

  group('what gets frozen', () {
    CreatureInstance mob(Map<CreatureStat, double> base) => CreatureInstance(
      id: 'x',
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      statBase: base,
      statSlope: const {},
    );

    test('every gene is the better OR the worse parent, never a blend', () {
      // The whole point of the ★ column in the breeding screen: a child gets
      // one parent's number, not an average of the two.
      final a = mob({CreatureStat.hp: 10, CreatureStat.attack: 40});
      final b = mob({CreatureStat.hp: 30, CreatureStat.attack: 20});
      final rng = math.Random(7);
      for (var i = 0; i < 200; i++) {
        final child =
            CreatureInstance.inheritGenes(a.statBase, b.statBase, rng);
        expect([10.0, 30.0], contains(child[CreatureStat.hp]));
        expect([20.0, 40.0], contains(child[CreatureStat.attack]));
      }
    });

    test('GROWTH is a gene of its own, rolled apart from the base', () {
      // User 2026-07-27: "Das Wachstum pro Stufe muss ebenfalls angezeigt und
      // vererbt werden." The two are rolled separately, so over many children
      // every combination of the parents' base and growth appears — losing the
      // base does not decide the growth.
      final base = {CreatureStat.hp: 10.0};
      final other = {CreatureStat.hp: 30.0};
      final rng = math.Random(3);
      final pairs = <String>{};
      for (var i = 0; i < 300; i++) {
        final b = CreatureInstance.inheritGenes(base, other, rng);
        final g = CreatureInstance.inheritGenes(base, other, rng);
        pairs.add('${b[CreatureStat.hp]}/${g[CreatureStat.hp]}');
      }
      expect(pairs, containsAll(['10.0/30.0', '30.0/10.0']),
          reason: 'the two genes do not move together');
    });

    test('the better gene is favoured at a flat 60 %', () {
      // The number the breeding screen quotes. Flat since 2026-07-27 — no
      // parent stat moves it.
      expect(breedingFavoredChance(), closeTo(0.60, 1e-9));
    });

    test('at 100 % favour the child is the best of both parents', () {
      final a = mob({CreatureStat.hp: 10, CreatureStat.attack: 40});
      final b = mob({CreatureStat.hp: 30, CreatureStat.attack: 20});
      final child = CreatureInstance.inheritGenes(
        a.statBase,
        b.statBase,
        math.Random(1),
        favoredChance: 1.0,
      );
      expect(child[CreatureStat.hp], 30);
      expect(child[CreatureStat.attack], 40);
    });
  });
}
