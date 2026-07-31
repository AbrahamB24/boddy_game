import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/expedition_risk.dart';

CreatureInstance _mob({
  int attack = 10,
  int defense = 10,
  int hp = 50,
  String id = 'm',
}) => CreatureInstance(
  id: id,
  userId: 'u',
  speciesId: 's',
  gender: CreatureGender.male,
  statBase: {
    CreatureStat.attack: attack.toDouble(),
    CreatureStat.defense: defense.toDouble(),
    CreatureStat.hp: hp.toDouble(),
  },
  statSlope: const {},
);

void main() {
  group('perilRatio', () {
    test('danger 1 areas are risk-free', () {
      expect(perilRatio(1, [_mob()]), 0);
    });

    test('rises with danger, falls with group power', () {
      final group = [_mob(attack: 20, defense: 20)];
      final low = perilRatio(2, group);
      final high = perilRatio(5, group);
      expect(high, greaterThan(low));
      expect(low, greaterThan(0));

      final strong = perilRatio(5, [
        _mob(attack: 200, defense: 200),
        _mob(attack: 200, defense: 200),
      ]);
      expect(strong, lessThan(high)); // bigger/stronger group is safer
    });
  });

  group('rollCasualties', () {
    test('no casualties in a risk-free area', () {
      final out = rollCasualties(1, [_mob(), _mob(id: 'm2')], math.Random(1));
      expect(out, isEmpty);
    });

    test('casualties never exceed a member\'s current HP', () {
      final members = [
        _mob(attack: 5, defense: 5, hp: 30, id: 'a'),
        _mob(attack: 5, defense: 5, hp: 30, id: 'b'),
        _mob(attack: 5, defense: 5, hp: 30, id: 'c'),
      ];
      // High danger + weak group → plenty of incidents across seeds.
      for (var seed = 0; seed < 25; seed++) {
        final out = rollCasualties(5, members, math.Random(seed));
        for (final cas in out) {
          final m = members.firstWhere((x) => x.id == cas.creatureId);
          expect(cas.hpLost, greaterThan(0));
          expect(cas.hpLost, lessThanOrEqualTo(m.hp));
          expect(cas.ko, cas.hpLost >= m.hp);
        }
      }
    });
  });

  group('lootPenalty', () {
    test('none without casualties, capped at 0.4', () {
      expect(lootPenalty(const []), 0);
      final many = [
        for (var i = 0; i < 10; i++)
          Casualty(creatureId: 'c$i', hpLost: 5, ko: true),
      ];
      expect(lootPenalty(many), 0.4);
    });

    test('K.O. hurts the haul more than a wound', () {
      final wounded = [const Casualty(creatureId: 'a', hpLost: 5, ko: false)];
      final ko = [const Casualty(creatureId: 'a', hpLost: 5, ko: true)];
      expect(lootPenalty(ko), greaterThan(lootPenalty(wounded)));
    });
  });

  group('perilLabel', () {
    test('maps ratio to a coarse label', () {
      expect(perilLabel(0), 'None');
      expect(perilLabel(0.1), 'Low');
      expect(perilLabel(0.25), 'Medium');
      expect(perilLabel(0.5), 'High');
      expect(perilLabel(0.8), 'Extreme');
    });
  });
}
