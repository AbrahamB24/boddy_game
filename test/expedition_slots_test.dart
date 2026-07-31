import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/tuning/game_tuning.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

// Hunt lengths and expedition slots hang off the SCOUT POST now (user
// 2026-07-26: "Expeditionen werden an scout geknüpft, jagdt an scout"). The
// feature-unlock ids that used to open them — hunt_length_2..6,
// expedition_slots_1..3 — are deleted along with the whole `unlockedFeatures`
// system, so both are things the player can see and build toward.
//
// Team size is not gated here either: it is a rule of position on the linear
// path — see test/overworld_path_test.dart.

void main() {
  group('hunt lengths come from the settlement, not from an unlock id', () {
    test('with no scouting, only the shortest hunt exists', () {
      expect(maxHuntOptionCount(0), 1);
      // Defensive: a negative can only come from bad data, and it must not
      // take away the one hunt everybody has.
      expect(maxHuntOptionCount(-3), 1);
    });

    test('each point of huntOptions opens the next variant in order', () {
      expect(maxHuntOptionCount(1), 2);
      expect(maxHuntOptionCount(2), 3);
      expect(maxHuntOptionCount(5), kCaptureHuntOptions.length);
    });
  });

  group('the Scout Post is what grants both', () {
    BuildingEffect effect(String type) => kFallbackBuildingDefs['scout_post']!
        .effects
        .firstWhere((e) => e.type == type);

    test('it exists in ERA I — the region its grants belong to', () {
      // It used to be an era-II building. Left there, the first region would
      // have had one hunt variant and no extra slots at all, because nothing
      // else grants them any more.
      expect(kFallbackBuildingDefs['scout_post']!.eraIds, ['era_1']);
    });

    test('a level-1 post opens the second hunt and one extra slot', () {
      expect(effect('huntOptions').valueAtLevel(1), 1);
      expect(effect('expeditionSlots').valueAtLevel(1), 1);
    });

    test('levelling it opens the rest — every variant is reachable', () {
      // WHICH levels open them is tuned in Dev Mode; what must hold is that
      // the ladder reaches all of them, or a hunt variant would exist in
      // code and be unreachable in play.
      // Measured against the LADDER's own top rung, not the building's
      // level cap: the two disagree today (the authored ladder runs to L23,
      // the bundled def caps the post at L10), and what must not break is
      // that the ladder itself reaches every variant.
      final hunts = effect('huntOptions');
      final top = hunts.levelSteps.keys.fold<int>(1, (a, b) => a > b ? a : b);
      expect(hunts.valueAtLevel(top), greaterThan(hunts.valueAtLevel(1)));
      expect(maxHuntOptionCount(hunts.valueAtLevel(top).round()),
          greaterThanOrEqualTo(kCaptureHuntOptions.length));
    });

    test('slots climb more slowly than hunts', () {
      final slots = effect('expeditionSlots');
      final hunts = effect('huntOptions');
      expect(slots.valueAtLevel(99), greaterThan(slots.valueAtLevel(1)));
      expect(slots.valueAtLevel(99), lessThan(hunts.valueAtLevel(99)));
    });

    test('the post is the WHOLE supply — no post, no expedition', () {
      // User 2026-07-29: "ohne scout post darf keine expedition möglich sein,
      // d.h nur was ich beim dev menü bei scout post einstelle gilt". The two
      // free seats every settlement used to have were a grant no Dev-Mode
      // number could take away.
      expect(kBaseExpeditionSlots, 0);
    });

    test('both are COUNTS — no silent per-level percentage', () {
      // A levelSteps ladder must win over the global +50%/level yield curve;
      // "1.5 hunt variants at level 2" is not a thing.
      for (final type in ['huntOptions', 'expeditionSlots']) {
        expect(effect(type).levelSteps, isNotEmpty, reason: type);
        expect(effect(type).valueAtLevel(1), 1, reason: type);
      }
    });
  });

  // A hunt that has LANDED but whose encounter is unplayed stops occupying a
  // travel slot and stops locking its party (user 2026-07-27: "wenn eine
  // expedition beendet ist / bsp fangen und diese schon zurueck ist, aber ich
  // das minispiel noch nicht gemacht habe, soll der slot fuer die karawana
  // trotzdem freigegeben werden").
  //
  // The controller needs a database to run, so what is pinned here is the
  // predicate both `travelling` and `_syncLocks` are built on: the moment a
  // trip counts as home.
  group('a landed trip is not out any more', () {
    Expedition trip({required Duration ago, required Duration length}) =>
        Expedition(
          id: 'e',
          userId: 'u',
          type: ExpeditionType.capture,
          areaId: 'a',
          memberIds: const ['m1', 'm2'],
          startedAt: DateTime.now().subtract(ago),
          duration: length,
        );

    test('still out while the timer runs', () {
      final e = trip(ago: const Duration(minutes: 5), length: const Duration(hours: 1));
      expect(e.isFinished(DateTime.now()), isFalse);
    });

    test('home the moment the timer elapses, encounter unplayed', () {
      final e = trip(ago: const Duration(hours: 2), length: const Duration(hours: 1));
      expect(e.isFinished(DateTime.now()), isTrue);
      // …and it is STILL something to play: the row is not collected, which is
      // exactly the state that used to impound the party.
      expect(e.state, ExpeditionState.active);
      expect(e.isReadyToCollect(DateTime.now()), isTrue);
    });

    test('a collected trip is neither out nor waiting', () {
      final e = trip(ago: const Duration(hours: 2), length: const Duration(hours: 1))
        ..state = ExpeditionState.collected;
      expect(e.isFinished(DateTime.now()), isTrue);
      expect(e.isReadyToCollect(DateTime.now()), isFalse);
    });
  });

  // ── Caravans are their own pool (user 2026-07-29) ──
  // "unterscheide expeditions und karawanen für den Markt". A trade run used to
  // take an expedition seat, so sending wood to market cost you a hunt, and the
  // Warehouse's carry bonus somehow made the trade road shorter. Two pools, two
  // effect types, two buildings — and the test that keeps them from silently
  // being merged again is that no building may hand out both.
  group('the Caravanserai is what grants the caravan pool', () {
    BuildingDef get(String id) => kFallbackBuildingDefs[id]!;

    test('it grants caravanSlots, and the Scout Post does not', () {
      final car = get('caravanserai');
      expect(car.effects.where((e) => e.type == 'caravanSlots'), isNotEmpty);
      expect(car.effects.where((e) => e.type == 'expeditionSlots'), isEmpty);

      final scout = get('scout_post');
      expect(scout.effects.where((e) => e.type == 'caravanSlots'), isEmpty);
    });

    test('it exists in ERA I, where the Market already does', () {
      expect(get('caravanserai').eraIds, contains('era_1'));
      expect(get('trading_post').eraIds, contains('era_1'));
    });

    test('no building carries both an expedition and a caravan post', () {
      const expRoles = {
        WorkshopRole.kExpCarry,
        WorkshopRole.kExpTravel,
        WorkshopRole.kExpGoods,
        // The combined post counts as an expedition post too — without it the
        // guard would pass vacuously for the very building that has one.
        WorkshopRole.kExpedition,
      };
      const carRoles = {
        WorkshopRole.kCarCarry,
        WorkshopRole.kCarTravel,
        WorkshopRole.kCaravan,
      };
      for (final def in kFallbackBuildingDefs.values) {
        final roles = def.workshops.map((w) => w.resource).toSet();
        final hasExp = roles.intersection(expRoles).isNotEmpty;
        final hasCar = roles.intersection(carRoles).isNotEmpty;
        expect(hasExp && hasCar, isFalse, reason: def.id);
      }
    });

    test('the caravan post reads the stats it amplifies', () {
      // ONE post since 2026-07-30 ("karawansarei gleich wie scout post"),
      // so the rule lives per PART — each still reads what it amplifies.
      final post = get('caravanserai').workshops.single;
      expect(post.isCombined, isTrue);
      expect(post.parts.keys.toSet(), {'carry', 'travel'});
      expect(post.parts['carry'], WorkshopRole.kCarCarry);
      expect(post.parts['travel'], WorkshopRole.kCarTravel);
      expect(WorkshopRole.combinedPartStat('carry'), CreatureStat.carry);
      expect(WorkshopRole.combinedPartStat('travel'), CreatureStat.speed);
      // A caravan is priced at send, so it has no goods part to give.
      expect(post.parts.containsKey('goods'), isFalse);
    });

    test('neither road grants a seat the buildings did not', () {
      // Both start at 0 since 2026-07-29 (the author's own setting for the
      // caravans): the Scout Post and the Caravanserai ARE their pools. They
      // stay two separate numbers all the same — that is what stops a trade
      // run from eating a hunt's seat.
      expect(kBaseExpeditionSlots, 0);
      expect(kBaseCaravanSlots, 0);
      expect(Dials.baseExpeditionSlots, isNot(Dials.baseCaravanSlots));
    });
  });
}
