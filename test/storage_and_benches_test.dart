import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/tuning/game_tuning.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart' show IntroStep;
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/data/building_effects.dart';
import 'package:boddygame/features/settlement/data/workshop_role_effects.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/models/settlement.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// Two systems added on 2026-07-30, both authored as ordinary building effects:
//
//   STORAGE   a ceiling per resource ("jede Ressource will ich einzeln pro
//             Level einstellen können"), above which production STOPS, and a
//             save made before it existed is trimmed to fit.
//   BENCHES   how many items the Workshop makes at once, plus a queue for the
//             rest — both per level.
//
// The rules pinned here are the ones that would fail quietly: a ceiling that
// doesn't clamp loses nothing visibly but breaks the loop, and a queue whose
// order is not preserved hands the player a different item than they asked for.
void main() {
  setUp(() => GameTuning.i.debugClear());
  tearDown(() => GameTuning.i.debugClear());

  ResourceModel res({
    double wood = 0,
    double stone = 0,
    double gold = 0,
    Map<String, double> goods = const {},
  }) => ResourceModel(
    settlementId: 's',
    wood: wood,
    stone: stone,
    gold: gold,
    goods: goods,
    lastUpdatedAt: DateTime(2026),
  );

  group('storage ceilings', () {
    test('a ceiling clamps, and everything under it is untouched', () {
      final capped = res(wood: 900, stone: 100, goods: {'fish': 40})
          .capped({'wood': 500, 'stone': 500, 'fish': 500});
      expect(capped.wood, 500);
      expect(capped.stone, 100);
      expect(capped.goods['fish'], 40);
    });

    test('a resource with NO ceiling is unlimited', () {
      // What keeps a half-authored roster playable: a good nobody has written
      // a store for must not be pinned to zero.
      final capped = res(goods: {'clay': 9999}).capped(const {'wood': 10});
      expect(capped.goods['clay'], 9999);
    });

    test('atCapacity names exactly what has stopped growing', () {
      final full = res(wood: 500, stone: 10, gold: 2000);
      final caps = {'wood': 500.0, 'stone': 500.0, 'gold': 2000.0};
      expect(full.atCapacity(caps).toSet(), {'wood', 'gold'});
    });

    test('the era-I stores raise the ceiling they are for, and no other', () {
      final store = kBuildingEffects['storehouse']!;
      final vault = kBuildingEffects['gold_vault']!;
      final stored = {
        for (final e in store.effects)
          if (e.type == 'storage') e.key,
      };
      // "alle Produktion und Luxusressourcen" — the era-I raws and goods.
      expect(stored, containsAll(['wood', 'stone', 'fish', 'fur']));
      // Coin is the vault's job, and only the vault's.
      expect(stored, isNot(contains('gold')));
      expect(
        {for (final e in vault.effects) if (e.type == 'storage') e.key},
        {'gold'},
      );
    });

    test('a store grows by a PERCENTAGE, so the dial really governs it', () {
      // User 2026-07-30: "gold und storehaus will ich auch einen prozentualen
      // anstieg festlegen können". It was a 23-rung absolute ladder, and
      // because an authored step overrides the factor, the percentage field
      // was inert. What this pins is that no store authors levelSteps — the
      // moment one does, its percentage stops being read.
      for (final id in ['storehouse', 'gold_vault']) {
        for (final e in kBuildingEffects[id]!.effects) {
          if (e.type != 'storage') continue;
          expect(e.levelSteps, isEmpty,
              reason: '$id/${e.key}: a step would override the percentage');
          expect(e.levelFactor, isNotNull, reason: '$id/${e.key}');
          // Compounding, not linear: the gap between rungs widens.
          final l1 = e.valueAtLevel(1);
          final l2 = e.valueAtLevel(2);
          final l3 = e.valueAtLevel(3);
          expect(l2, greaterThan(l1));
          expect(l3 - l2, greaterThan(l2 - l1));
          expect(l2 / l1, closeTo(e.levelFactor!, 1e-9));
        }
      }
    });

    test('a stale ladder in the row cannot swallow the percentage', () {
      // The bug this exists for (user 2026-07-30: "growth per level (%) bei
      // storehaus funktioniert nicht"). The Storehouse was first authored as a
      // 23-rung absolute ladder; rows written then still carry those rungs, and
      // `levelSteps` silently overrides `levelFactor` — so every percentage
      // typed afterwards did nothing, with nothing on screen saying why.
      //
      // The growth MODE is shape and follows the code; only its numbers come
      // from the row. So a leftover ladder is dropped rather than obeyed.
      final row = kFallbackBuildingDefs['storehouse']!.toDefRow();
      final stale = {
        ...row,
        'effects': [
          {
            'type': 'storage',
            'key': 'wood',
            'value': 500.0,
            'levelFactor': 1.25,
            'levelSteps': {for (var l = 2; l <= 24; l++) '$l': 500.0},
          },
        ],
      };
      final def = BuildingDef.fromDefRow(stale);
      expect(def.effectAt('storage', 'wood', 1, level: 1), 500);
      // +25 %, not +500 flat.
      expect(def.effectAt('storage', 'wood', 1, level: 2), closeTo(625, 1e-9));
    });

    test('an edited percentage really reaches the game', () {
      // The whole round trip the dev form runs: read the row, change the
      // factor, load it back.
      final row = kFallbackBuildingDefs['storehouse']!.toDefRow();
      final edited = {
        ...row,
        'effects': [
          for (final e in (row['effects'] as List))
            if ((e as Map)['type'] == 'storage' && e['key'] == 'wood')
              {...e, 'levelFactor': 2.0}
            else
              e,
        ],
      };
      final def = BuildingDef.fromDefRow(edited);
      expect(def.effectAt('storage', 'wood', 1, level: 2), 1000);
      expect(def.effectAt('storage', 'wood', 1, level: 3), 2000);
    });

    test('the ceiling names where its room came from', () {
      // What the header cell opens (user 2026-07-30: "wenn ich oben auf die
      // Ressourcen drücke, will ich auch das Cap sehen"). A full store is the
      // same kind of question as a slow one — which building fixes this — so
      // it gets the same kind of answer: a list of contributors.
      //
      // The settlement's own room is always the first entry, because with no
      // store built it is the ONLY entry and an empty list would read as
      // "nothing holds this".
      final ctrl = SettlementController();
      final sources = ctrl.storageSources('wood');
      expect(sources, isNotEmpty);
      expect(sources.first.label, 'The settlement itself');
      expect(sources.first.amount, GameTuning.i.raw(Dials.baseStorage));
      // Everything listed adds up to the ceiling the game clamps against.
      final summed = sources.fold<double>(0, (a, s) => a + s.amount);
      expect(summed, closeTo(ctrl.storageCapacity('wood'), 1e-9));
    });

    test('gold has its own ceiling, and it is not the goods one', () {
      final ctrl = SettlementController();
      expect(ctrl.storageCapacity('gold'),
          GameTuning.i.raw(Dials.baseGoldStorage));
      expect(ctrl.storageCapacity('wood'), GameTuning.i.raw(Dials.baseStorage));
      expect(ctrl.storageCapacity('gold'),
          isNot(ctrl.storageCapacity('wood')));
    });

    // ── The stores are STAFFED (user 2026-07-30) ──
    // "Die Lagerhäuser können wie die Produktionsgebäude Monster beherbergen,
    // wobei ihre Punkte in Logistics die Lagerkapazität definieren."
    //
    // The rule that would fail quietly is LOCALITY: room is made in one store,
    // for the goods that store holds. Summed settlement-wide (the way every
    // other post is) a Gold Vault logistician would widen the Storehouse.
    group('logisticians make room', () {
      PlacedBuilding placed(String id, String type, {int level = 1}) =>
          PlacedBuilding(
            id: id,
            settlementId: 's',
            buildingTypeId: type,
            gridX: 0,
            gridY: 0,
            level: level,
            constructionSecondsRequired: 0,
            constructionSecondsBuilt: 0,
            isComplete: true,
            placedAt: DateTime.utc(2026),
          );

      CreatureInstance worker(String id, double logistics, String? postedTo) {
        final c = CreatureInstance(
          id: id,
          userId: 'u',
          speciesId: id,
          gender: CreatureGender.male,
          statBase: {CreatureStat.logistics: logistics},
          statSlope: const {},
        );
        c.level = 1;
        if (postedTo != null) {
          c.assignedBuildingId = postedTo;
          c.assignedStat = CreatureStat.logistics;
        }
        return c;
      }

      late SettlementController ctrl;

      setUp(() {
        ctrl = SettlementController();
        ctrl.buildings = [
          placed('b_store', 'storehouse'),
          placed('b_vault', 'gold_vault'),
        ];
        // The tutorial window is the documented "every building counts as
        // connected" state (connectedBuildingIds) — cheaper than laying a road
        // network for a capacity test, and it exercises the same code path.
        ctrl.introStep = IntroStep.assignWorker;
        CreaturesController().creatures.clear();
      });

      tearDown(() {
        ctrl.buildings = [];
        ctrl.introStep = IntroStep.done;
        CreaturesController().creatures.clear();
        CreaturesController().expeditionIds.clear();
      });

      double roomPerPoint(String id, String resource) =>
          kFallbackBuildingDefs[id]!.workshops.single.storageMultFor(resource);

      test('a posted logistician raises exactly the ceilings of ITS store', () {
        final before = {
          for (final r in ['wood', 'stone', 'fish', 'fur', 'gold'])
            r: ctrl.storageCapacity(r),
        };
        CreaturesController().creatures.add(worker('w', 20, 'b_store'));
        // Each resource gains 20 points of logistics × ITS OWN dial.
        for (final res in ['wood', 'stone', 'fish', 'fur']) {
          expect(
            ctrl.storageCapacity(res) - before[res]!,
            closeTo(20 * roomPerPoint('storehouse', res), 1e-9),
            reason: res,
          );
        }
        // …and the Vault, which holds none of them, gains nothing.
        expect(ctrl.storageCapacity('gold'), before['gold']);
      });

      test('the Vault\'s own staff raises coin, and only coin', () {
        final woodBefore = ctrl.storageCapacity('wood');
        final goldBefore = ctrl.storageCapacity('gold');
        CreaturesController().creatures.add(worker('v', 20, 'b_vault'));
        expect(
          ctrl.storageCapacity('gold') - goldBefore,
          closeTo(20 * roomPerPoint('gold_vault', 'gold'), 1e-9),
        );
        expect(ctrl.storageCapacity('wood'), woodBefore);
      });

      // ── One dial PER RESOURCE (user 2026-07-30) ──
      // "Ich muss den output pro worker für jede Ressource einzeln einstellen
      // können." The failure mode is silent: one shared number looks right for
      // as long as every dial happens to be equal.
      test('each resource reads its OWN dial, not one shared number', () {
        final role = kFallbackBuildingDefs['storehouse']!.workshops.single;
        // Every resource this store holds has a dial of its own…
        for (final res in ['wood', 'stone', 'fish', 'fur']) {
          expect(role.mults, contains(res), reason: res);
        }
        // …and the runtime really reads that one. Tuning ONE resource must move
        // only that ceiling — the bug a shared `mult` cannot even express.
        final tuned = WorkshopRole(
          stat: role.stat,
          resource: role.resource,
          mult: role.mult,
          slots: role.slots,
          levelFactor: role.levelFactor,
          slotSteps: role.slotSteps,
          mults: {...role.mults, 'fur': 1},
        );
        expect(tuned.storageRoomFor('fur', 20, 1), closeTo(20, 1e-9));
        expect(
          tuned.storageRoomFor('wood', 20, 1),
          closeTo(20 * role.mults['wood']!, 1e-9),
        );
      });

      test('a resource with no dial falls back to the flat mult', () {
        // What keeps a half-tuned store playable: add a `storage` effect for a
        // later era's good and it gets room immediately, at the fallback rate,
        // instead of silently getting none.
        const role = WorkshopRole(
          stat: CreatureStat.logistics,
          resource: WorkshopRole.kStorageRoom,
          mult: 7,
          mults: {'wood': 3},
        );
        expect(role.storageMultFor('wood'), 3);
        expect(role.storageMultFor('clay'), 7);
      });

      test('an ABSENT worker holds the post but makes no room', () {
        // The same rule every other post follows: away on an expedition, K.O.
        // or breeding means the seat is theirs and the output is not.
        CreaturesController().creatures.add(worker('w', 20, 'b_store'));
        final withWorker = ctrl.storageCapacity('wood');
        CreaturesController().expeditionIds.add('w');
        expect(ctrl.storageCapacity('wood'), lessThan(withWorker));
      });

      test('the breakdown names the staff, and still adds up', () {
        CreaturesController().creatures.add(worker('w', 20, 'b_store'));
        final sources = ctrl.storageSources('wood');
        expect(
          sources.map((s) => s.label),
          contains('Logisticians on duty'),
        );
        final summed = sources.fold<double>(0, (a, s) => a + s.amount);
        expect(summed, closeTo(ctrl.storageCapacity('wood'), 1e-9));
      });

      test('room is a COUNT of units, not a rate or a percentage', () {
        // It sits in the same map as every other post's output, so the shared
        // vocabulary has to know it is neither goods per hour nor a fraction.
        expect(workshopRoleFeedsSystem(WorkshopRole.kStorageRoom), isTrue);
        expect(workshopRoleName(WorkshopRole.kStorageRoom), 'Storage room');
        expect(workshopRoleEffect(WorkshopRole.kStorageRoom, 190.4),
            '+190 room');
        expect(
          kFallbackBuildingDefs['storehouse']!
              .workshops
              .single
              .producesResource,
          isFalse,
        );
      });

      test('the room a store\'s post makes is NOT settlement-wide power', () {
        // If it landed in workshopPower it would be one number made of ceilings
        // belonging to different stores and different goods.
        CreaturesController().creatures.add(worker('w', 20, 'b_store'));
        expect(ctrl.workshopPower()[WorkshopRole.kStorageRoom], isNull);
        expect(
          ctrl.storageRoomPosted(ctrl.buildings.first, 'wood'),
          greaterThan(0),
        );
        // And a resource this store does not hold gets nothing, even though the
        // post's fallback dial would happily produce a number.
        expect(ctrl.storageRoomPosted(ctrl.buildings.first, 'clay'), 0);
      });
    });

    test('the ceiling reads as a bare number under one Storage heading', () {
      // User 2026-07-30, on the building dialog: "«Ressource» zu «Storage»
      // ändern, dafür überall sonst storage löschen. Gib nur die Zahl, ohne
      // Max und ohne Icon." The rows used to read "Storage · wood  500 max 🏚"
      // — the word, the unit and the glyph all repeating what the heading and
      // the resource name already say.
      expect(buildingEffectLabel('storage'), 'Storage');
      expect(formatBuildingEffect('storage', 'wood', 500), '500');
      expect(formatBuildingEffect('storage', 'gold', 2000), '2000');
    });

    test('the upgrade rows keep the card order and show only the new max', () {
      // "unten die gleiche Reihenfolge wie oben (wood, stone, fish, fur)" +
      // "Unten nur das neue Max angeben". The panel used to sort by label, so
      // the same four ceilings appeared wood/stone/fish/fur on the card and
      // fish/fur/stone/wood one panel below.
      for (final id in ['storehouse', 'gold_vault']) {
        final def = kFallbackBuildingDefs[id]!;
        final authored = [
          for (final e in kBuildingEffects[id]!.effects)
            if (e.type == 'storage') e.key,
        ];
        final lines = buildingEffectUpgradeLines(def, 1, 2, 1)
            .where((l) => l.group == 'Storage')
            .toList();
        expect(lines.map((l) => l.label), authored, reason: id);
        for (final l in lines) {
          expect(l.onlyNext, isTrue, reason: '$id/${l.label}');
          // The row names the resource alone — the heading carries the word.
          expect(l.label, isNot(contains('Storage')));
          // No glyph: the heading and the resource already say what it is.
          expect(l.emoji, isEmpty);
        }
      }
    });

    test('both stores are buildable in era I', () {
      for (final id in ['storehouse', 'gold_vault']) {
        expect(kFallbackBuildingDefs[id]!.eraIds, contains('era_1'),
            reason: id);
      }
    });
  });

  group('the Workshop’s benches and queue', () {
    test('the Workshop authors both, and both grow with the level', () {
      final effects = kBuildingEffects['thinker_circle']!.effects;
      final slots = effects.firstWhere((e) => e.type == 'craftSlots');
      final queue = effects.firstWhere((e) => e.type == 'craftQueue');
      expect(slots.valueAtLevel(24), greaterThan(slots.valueAtLevel(1)));
      expect(queue.valueAtLevel(24), greaterThan(queue.valueAtLevel(1)));
      // A bench is worth far more than a waiting place — each runs at the full
      // crafting rate — so benches must not outpace the line.
      expect(slots.valueAtLevel(24), lessThan(queue.valueAtLevel(24)));
    });

    test('a job round-trips through its json', () {
      final back = CraftJob.fromJson(
        const CraftJob('torch', secondsBuilt: 12.5).toJson(),
      );
      expect(back.itemId, 'torch');
      expect(back.secondsBuilt, 12.5);
    });

    test('the queue keeps the order it was given', () {
      // Order IS the queue: the first entries are on a bench, the rest wait in
      // the order they were added. A set would lose the player's answer to
      // "which one next".
      final s = SettlementModel(
        id: 's',
        userId: 'u',
        name: 'n',
        eraIndex: 1,
        mainBuildingLevel: 1,
        craftJobs: const [
          CraftJob('a'),
          CraftJob('b'),
          CraftJob('c'),
        ],
        createdAt: DateTime(2026),
      );
      final back = SettlementModel.fromMap({
        ...s.toMap(),
        'created_at': DateTime(2026).toIso8601String(),
      });
      expect(back.craftJobs.map((j) => j.itemId), ['a', 'b', 'c']);
    });

    test('a PRE-0030 row keeps the recipe and the seconds it had banked', () {
      // The one migration hazard: a settlement caught mid-craft must not lose
      // both the recipe and the work when the column arrives.
      final back = SettlementModel.fromMap({
        'id': 's',
        'user_id': 'u',
        'name': 'n',
        'era_index': 1,
        'main_building_level': 1,
        'active_craft_id': 'torch',
        'craft_seconds_built': 42.0,
        'created_at': DateTime(2026).toIso8601String(),
      });
      expect(back.craftJobs, hasLength(1));
      expect(back.craftJobs.single.itemId, 'torch');
      expect(back.craftJobs.single.secondsBuilt, 42);
    });

    test('an empty legacy row starts with nothing on the bench', () {
      final back = SettlementModel.fromMap({
        'id': 's',
        'user_id': 'u',
        'name': 'n',
        'era_index': 1,
        'main_building_level': 1,
        'created_at': DateTime(2026).toIso8601String(),
      });
      expect(back.craftJobs, isEmpty);
    });
  });
}
