import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/workshop_role_effects.dart';

// The Breeding Hut and the Hatchery are two buildings, built the same way but
// staffed and capped apart (user 2026-07-26: "breeding und hatching muss
// getrennt werden bei den gebäuden … allerdings gleich aufgebaut").
//
// Before the split both ran on the single `breeding` key, so a monster posted in
// the hut also sped up eggs in the Hatchery and one job cap covered both. These
// tests pin the two vocabularies apart — and pin the fallback that keeps a
// Hatchery saved BEFORE the split working.
BuildingDef _def({
  required String roleResource,
  required String jobEffect,
  int jobs = 1,
}) => BuildingDef(
  id: 'b',
  name: 'B',
  color: const Color(0xFF000000),
  gridW: 2,
  gridH: 2,
  workshops: [
    WorkshopRole(
      stat: CreatureStat.breeding,
      resource: roleResource,
      mult: 1,
      slots: 2,
    ),
  ],
  effects: [BuildingEffect(type: jobEffect, value: jobs.toDouble())],
);

void main() {
  group('the two job caps are separate effects', () {
    test('a mating cap is invisible to the hatching lookup', () {
      final hut = _def(
        roleResource: WorkshopRole.kBreeding,
        jobEffect: 'breeding',
        jobs: 3,
      );
      expect(hut.concurrentJobsAt(1), 3); // defaults to 'breeding'
      expect(hut.concurrentJobsAt(1, type: 'hatching'), 0);
    });

    test('and an incubation cap is invisible to the breeding lookup', () {
      final hatchery = _def(
        roleResource: WorkshopRole.kHatching,
        jobEffect: 'hatching',
        jobs: 2,
      );
      expect(hatchery.concurrentJobsAt(1, type: 'hatching'), 2);
      expect(hatchery.concurrentJobsAt(1), 0);
    });

    test('hatching survives a DB round-trip like every other effect', () {
      final restored = BuildingDef.fromDefRow(
        _def(
          roleResource: WorkshopRole.kHatching,
          jobEffect: 'hatching',
          jobs: 4,
        ).toDefRow(),
      );
      expect(restored.hasEffect('hatching', 1), isTrue);
      expect(restored.concurrentJobsAt(1, type: 'hatching'), 4);
      expect(restored.workshops.single.resource, WorkshopRole.kHatching);
    });
  });

  group('the hatcher post is its own role', () {
    test('it produces no stockpile resource, same as the breeder post', () {
      const r = WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kHatching,
      );
      expect(r.producesResource, isFalse);
    });

    test('it feeds a system and is named by the clock it shortens', () {
      expect(workshopRoleFeedsSystem(WorkshopRole.kHatching), isTrue);
      expect(workshopRoleName(WorkshopRole.kHatching), 'Incubation time');
      expect(workshopRoleName(WorkshopRole.kBreeding), 'Mating time');
      // Both read the SAME curve — only the duration they apply to differs.
      expect(
        workshopRoleEffect(WorkshopRole.kHatching, kBreedingK),
        workshopRoleEffect(WorkshopRole.kBreeding, kBreedingK),
      );
    });
  });

  group('the bundled roster uses one key per building', () {
    test('the Breeding Hut works in breeding, the Hatchery in hatching', () {
      final hut = kFallbackBuildingDefs['breeding_hut']!;
      final hatchery = kFallbackBuildingDefs['hatchery']!;

      expect(hut.workshops.single.resource, WorkshopRole.kBreeding);
      expect(hut.hasEffect('breeding', 1), isTrue);
      expect(hut.hasEffect('hatching', 1), isFalse);

      expect(hatchery.workshops.single.resource, WorkshopRole.kHatching);
      // The POST is what must differ — that is what makes the two clocks
      // tunable apart. The job-cap effect may still be typed `breeding`:
      // hatchingCapacity falls back to it on purpose, for Hatchery rows
      // authored before the split, and the live config uses that path.
      expect(
        hatchery.hasEffect('hatching', 1) || hatchery.hasEffect('breeding', 1),
        isTrue,
        reason: 'the Hatchery must cap its incubations somehow',
      );
    });

    test('but they are built the same way — same stat, slots and mult', () {
      final hut = kFallbackBuildingDefs['breeding_hut']!;
      final hatchery = kFallbackBuildingDefs['hatchery']!;
      expect(hatchery.workshops.single.stat, hut.workshops.single.stat);
      expect(hatchery.workshops.single.slots, hut.workshops.single.slots);
      expect(hatchery.workshops.single.mult, hut.workshops.single.mult);
      // XP is no longer part of this comparison because it cannot differ: both
      // have a work post, and every building with one pays the same rate
      // (user 2026-07-30). See xp_balance_test.dart.
    });
  });
}
