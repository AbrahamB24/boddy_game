import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/breeding_controller.dart';

CreatureInstance make({
  required String id,
  String species = 'emberfox',
  CreatureGender gender = CreatureGender.male,
  int hp = -1, // -1 = full sentinel
}) => CreatureInstance(
  id: id,
  userId: 'u',
  speciesId: species,
  gender: gender,
  level: 10,
  statBase: {for (final s in CreatureStat.values) s: 20.0},
  statSlope: {for (final s in CreatureStat.values) s: 2.0},
  currentHp: hp,
);

void main() {
  group('validatePair', () {
    final male = make(id: 'm');
    final female = make(id: 'f', gender: CreatureGender.female);

    test('valid pair passes', () {
      expect(
        BreedingController.validatePair(male, female, breedingIds: {}),
        isNull,
      );
    });

    test('same creature rejected', () {
      expect(
        BreedingController.validatePair(male, male, breedingIds: {}),
        isNotNull,
      );
    });

    test('different species rejected', () {
      final other = make(
        id: 'o',
        species: 'aquapup',
        gender: CreatureGender.female,
      );
      expect(
        BreedingController.validatePair(male, other, breedingIds: {}),
        isNotNull,
      );
    });

    test('same gender rejected', () {
      final male2 = make(id: 'm2');
      expect(
        BreedingController.validatePair(male, male2, breedingIds: {}),
        isNotNull,
      );
    });

    test('K.O. parent rejected', () {
      // hp: 0 always reads as K.O. regardless of species defs — maxHp falls
      // back to the instance's own statBase/statSlope (defaulted to 10/1
      // per stat when a stat key is missing), never zero.
      final ko = make(id: 'k', gender: CreatureGender.female, hp: 0);
      expect(
        BreedingController.validatePair(male, ko, breedingIds: {}),
        isNotNull,
      );
    });

    test('already-breeding parent rejected', () {
      expect(
        BreedingController.validatePair(male, female, breedingIds: {'f'}),
        isNotNull,
      );
    });
  });

  group('inheritGenes (70/30 per gene)', () {
    test('always picks one of the two parent values', () {
      final rng = math.Random(7);
      final a = {for (final s in CreatureStat.values) s: 12.0};
      final b = {for (final s in CreatureStat.values) s: 3.0};
      for (var i = 0; i < 50; i++) {
        final child = CreatureInstance.inheritGenes(a, b, rng);
        for (final s in CreatureStat.values) {
          expect(child[s], anyOf(12.0, 3.0));
        }
      }
    });

    test('better value wins ~70% of the time', () {
      final rng = math.Random(42);
      final a = {for (final s in CreatureStat.values) s: 10.0};
      final b = {for (final s in CreatureStat.values) s: 2.0};
      var better = 0, total = 0;
      for (var i = 0; i < 2000; i++) {
        final child = CreatureInstance.inheritGenes(a, b, rng);
        for (final s in CreatureStat.values) {
          total++;
          if (child[s] == 10.0) better++;
        }
      }
      final ratio = better / total;
      // 12k samples: statistically safe bounds around 0.70.
      expect(ratio, greaterThan(0.66));
      expect(ratio, lessThan(0.74));
    });

    test('equal parent values are inherited unchanged', () {
      final rng = math.Random(1);
      final a = {for (final s in CreatureStat.values) s: 8.0};
      final child = CreatureInstance.inheritGenes(a, a, rng);
      for (final s in CreatureStat.values) {
        expect(child[s], 8.0);
      }
    });
  });
}
