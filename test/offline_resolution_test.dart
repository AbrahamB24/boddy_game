import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/breeding_job.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';

// The idle-game promise: breeding eggs and heals resolve WHILE YOU ARE AWAY,
// from a timestamp in the past. The controllers do the DB side, but the
// readiness predicates they gate on are pure — these lock that core so an
// offline-resolve can never silently stop recognising a finished timer.
void main() {
  BreedingJob job({
    required BreedingStatus status,
    required Duration readyIn,
  }) => BreedingJob(
    id: 'j',
    userId: 'u',
    parentAId: 'a',
    parentBId: 'b',
    speciesId: 's',
    startedAt: DateTime.now().subtract(const Duration(hours: 2)),
    readyAt: DateTime.now().add(readyIn),
    status: status,
  );

  group('breeding offline readiness', () {
    test('a mating past its lay time is a laid egg, ready, no time left', () {
      final j = job(status: BreedingStatus.breeding, readyIn: -const Duration(minutes: 1));
      expect(j.isReady, isTrue);
      expect(j.isLaidEgg, isTrue);
      expect(j.remaining, Duration.zero);
    });

    test('a mating still incubating is not laid and has time left', () {
      final j = job(status: BreedingStatus.breeding, readyIn: const Duration(hours: 1));
      expect(j.isReady, isFalse);
      expect(j.isLaidEgg, isFalse);
      expect(j.remaining.inMinutes, greaterThan(0));
    });

    test('an egg is always collectable and never hatchable (no timer)', () {
      final j = job(status: BreedingStatus.egg, readyIn: const Duration(hours: 5));
      expect(j.isLaidEgg, isTrue);
      expect(j.isHatchable, isFalse);
    });

    test('a hatching job is hatchable only once its timer elapsed', () {
      final done = job(status: BreedingStatus.hatching, readyIn: -const Duration(seconds: 1));
      final busy = job(status: BreedingStatus.hatching, readyIn: const Duration(hours: 1));
      expect(done.isHatchable, isTrue);
      expect(busy.isHatchable, isFalse);
    });
  });

  group('heal offline completion', () {
    CreatureInstance mon({DateTime? healingUntil}) => CreatureInstance(
      id: 'c',
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      statBase: const <CreatureStat, double>{},
      statSlope: const <CreatureStat, double>{},
      healingUntil: healingUntil,
    );

    test('treatment whose timer elapsed reads as DONE (offline-resolvable)', () {
      final c = mon(healingUntil: DateTime.now().subtract(const Duration(minutes: 1)));
      expect(c.isHealing, isFalse, reason: 'past deadline = finished');
      expect(c.healingRemaining, Duration.zero);
    });

    test('treatment still running reads as healing with time left', () {
      final c = mon(healingUntil: DateTime.now().add(const Duration(minutes: 30)));
      expect(c.isHealing, isTrue);
      expect(c.healingRemaining.inMinutes, greaterThan(0));
    });

    test('a creature with no treatment is not healing', () {
      final c = mon();
      expect(c.isHealing, isFalse);
      expect(c.healingRemaining, Duration.zero);
    });
  });
}
