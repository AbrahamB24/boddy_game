import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/services/stat_budget.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

// ── The 2026-07-25 work-stat rework ─────────────────────────
// The old set was four era-I trades (woodcutting / mining / prospecting /
// luxuryProduction) plus three roles, and it stopped describing the game the
// moment an era produced steel. The new set follows the PLACES a monster can
// be, and every one of them must actually have a place: a stat no building
// reads is a stat that silently eats budget.

void main() {
  group('the stat set', () {
    test('5 combat + 8 work roles + carry', () {
      expect(kCombatStats.length, 5);
      expect(kCivilianStats.length, 8);
      expect(CreatureStat.values.length, 14);
      expect(kCivilianStats, [
        CreatureStat.gathering,
        CreatureStat.production,
        CreatureStat.construction,
        CreatureStat.crafting,
        CreatureStat.breeding,
        CreatureStat.medicine,
        CreatureStat.trade,
        CreatureStat.logistics,
      ]);
    });

    test('logistics is back — and this time it names a PLACE', () {
      // User 2026-07-30: "Ich brauche trotzdem noch einen neuen Stat: Logistics,
      // welcher in den Lagerhäusern benutzt wird."
      //
      // The FIRST logistics was deleted on 2026-07-26 for a reason that still
      // holds: it was a catch-all for three posts that each really read another
      // stat. This one is a work role like the rest — it has buildings, and
      // those buildings read nothing else for their room.
      expect(CreatureStat.logistics.isWorkRole, isTrue);
      expect(CreatureStat.logistics.isCombat, isFalse);
      final stores = ['storehouse', 'gold_vault'];
      for (final id in stores) {
        final role = kFallbackBuildingDefs[id]!.workshops.single;
        expect(role.stat, CreatureStat.logistics, reason: id);
        expect(role.resource, WorkshopRole.kStorageRoom, reason: id);
        expect(role.mult, greaterThan(0), reason: '$id: an inert post');
      }
      // And the trip posts still read what they amplify — the thing the first
      // logistics got in the way of.
      expect(
        kFallbackBuildingDefs['warehouse']!.workshops.single.stat,
        CreatureStat.carry,
      );
      expect(
        kFallbackBuildingDefs['smokehouse']!.workshops.single.stat,
        CreatureStat.gathering,
      );
    });

    test('carry is civilian but not a work role', () {
      expect(CreatureStat.carry.isCivilian, isTrue);
      expect(CreatureStat.carry.isWorkRole, isFalse);
      expect(kCivilianStats, isNot(contains(CreatureStat.carry)));
    });

    test('a POST may read carry and speed, which are not work roles', () {
      // The list the Dev-Mode editor offers. Wider than kCivilianStats since
      // 2026-07-26 — a scout post reads `speed`, a warehouse reads `carry`.
      expect(kPostableStats, containsAll(kCivilianStats));
      expect(kPostableStats, contains(CreatureStat.carry));
      expect(kPostableStats, contains(CreatureStat.speed));
      expect(kPostableStats, isNot(contains(CreatureStat.hp)));
    });

    test('the retired trade names still resolve — for CONTENT, not genes', () {
      // A DB workshop row authored before the rework says 'woodcutting'; every
      // one of those sits on a production building.
      for (final old in ['woodcutting', 'mining', 'prospecting',
        'luxuryProduction', 'fishing', 'hunting']) {
        expect(CreatureStat.fromName(old), CreatureStat.production,
            reason: '$old must not fall back to hp');
      }
      // But a GENE stored under the old key is NOT inherited — it re-rolls.
      final base = CreatureStat.production
          .readJson({'woodcutting': 42.0, 'mining': 13.0});
      expect(base, isNull);
    });
  });

  group('every work role has somewhere to work', () {
    /// Which stats the bundled roster actually staffs.
    Set<CreatureStat> stationable() => {
      for (final d in kFallbackBuildingDefs.values)
        for (final w in d.workshops) w.stat,
    };

    test('production, construction, crafting, breeding are staffed', () {
      final staffed = stationable();
      expect(staffed, containsAll([
        CreatureStat.production,
        CreatureStat.construction,
        CreatureStat.crafting,
        CreatureStat.breeding,
      ]));
    });

    test('the civil services are staffed too', () {
      // These replaced hardcoded bonuses (healing speed, trade rates) — if no
      // building offers the post, the stat is dead weight.
      final staffed = stationable();
      expect(staffed, contains(CreatureStat.medicine));
      expect(staffed, contains(CreatureStat.trade));
    });

    test('the trip amplifiers read the stat they amplify', () {
      // User 2026-07-26, replacing `logistics`: the post and the number it
      // moves must be the same thing, or the choice of who to station there
      // is arbitrary.
      CreatureStat statOf(String id, String output) =>
          kFallbackBuildingDefs[id]!
              .workshops
              .firstWhere((w) => w.resource == output)
              .stat;
      expect(statOf('warehouse', WorkshopRole.kExpCarry), CreatureStat.carry);
      expect(
        statOf('smokehouse', WorkshopRole.kExpGoods),
        CreatureStat.gathering,
      );
      // The Scout Post runs ONE combined post; the rule holds for the seat's
      // own stat as well as for each part (checked just below).
      for (final w in kFallbackBuildingDefs['scout_post']!.workshops) {
        expect(
          w.stat,
          isIn([
            for (final part in WorkshopRole.partsOf(WorkshopRole.kExpedition).keys)
              WorkshopRole.combinedPartStat(part),
          ]),
          reason: w.resource,
        );
      }
      // And the combined post reads them the same way, part by part.
      expect(WorkshopRole.combinedPartStat('travel'), CreatureStat.speed);
      expect(WorkshopRole.combinedPartStat('carry'), CreatureStat.carry);
      expect(
        WorkshopRole.combinedPartStat('goods'),
        CreatureStat.gathering,
      );
    });

    test('one combined seat feeds all three amplifiers', () {
      // User 2026-07-29: "exp carry capacity, exp goods und exp speed in einem
      // Effekt … welchen ich aber separat einstellen kann". One post, one seat
      // count — but three buckets, each on its own dial and its own stat.
      //
      // Built here rather than read off the Scout Post so the arithmetic below
      // has fixed numbers; that the Scout Post really uses the role is
      // asserted separately.
      const role = WorkshopRole(
        stat: CreatureStat.speed,
        resource: WorkshopRole.kExpedition,
        slots: 2,
        mults: {'carry': 0.001, 'goods': 0.001, 'travel': 0.002},
      );
      expect(role.isCombined, isTrue);
      // And the Scout Post really uses it — ONE seat count for both numbers,
      // which is the whole request.
      final scout = kFallbackBuildingDefs['scout_post']!.workshops.single;
      expect(scout.isCombined, isTrue);
      expect(scout.mults['travel'], greaterThan(0));
      expect(scout.mults['carry'], greaterThan(0));
      expect(role.mults.keys.toSet(), {'carry', 'goods', 'travel'});

      // A monster worth 100 carry, 50 gathering and 10 speed, at level 1
      // (level factor 1) — each part reads ITS stat, not the post's.
      final out = role.contribution(
        (s) => switch (s) {
          CreatureStat.carry => 100.0,
          CreatureStat.gathering => 50.0,
          CreatureStat.speed => 10.0,
          _ => 0.0,
        },
        1,
      );
      expect(out[WorkshopRole.kExpCarry], closeTo(100 * role.mults['carry']!, 1e-9));
      expect(out[WorkshopRole.kExpGoods], closeTo(50 * role.mults['goods']!, 1e-9));
      expect(
        out[WorkshopRole.kExpTravel],
        closeTo(10 * role.mults['travel']!, 1e-9),
      );
    });

    test('the Caravanserai is the Scout Post on the other road', () {
      // User 2026-07-30: "karawansarei gleich wie scout post. Geschwindigkeit,
      // carry etc. in einen Effekt packen mit den gleichen Monster." One seat,
      // one hire list, a dial per part — and its OWN buckets, so a drover
      // never shortens a hunt.
      final post = kFallbackBuildingDefs['caravanserai']!.workshops.single;
      expect(post.isCombined, isTrue);
      expect(post.resource, WorkshopRole.kCaravan);
      expect(post.mults.keys.toSet(), {'carry', 'travel'});

      final out = post.contribution(
        (s) => switch (s) {
          CreatureStat.carry => 100.0,
          CreatureStat.speed => 10.0,
          _ => 0.0,
        },
        1,
      );
      // The CARAVAN keys, never the expedition ones — that separation is the
      // whole reason the two roads have four output keys between them.
      expect(out.keys.toSet(),
          {WorkshopRole.kCarCarry, WorkshopRole.kCarTravel});
      expect(out[WorkshopRole.kCarCarry],
          closeTo(100 * post.mults['carry']!, 1e-9));
      expect(out[WorkshopRole.kCarTravel],
          closeTo(10 * post.mults['travel']!, 1e-9));
    });

    test('an ordinary post still yields exactly one output', () {
      final role = kFallbackBuildingDefs['warehouse']!.workshops.single;
      expect(role.isCombined, isFalse);
      final out = role.contribution((_) => 100, 1);
      expect(out.keys, [WorkshopRole.kExpCarry]);
      expect(out.values.single, closeTo(100 * role.mult, 1e-9));
    });

    test('a saved `logistics` post still resolves, by which post it is', () {
      // DB rows authored before the deletion say stat:"logistics". A flat
      // rename could not tell the three apart, so the resource decides.
      CreatureStat parsed(String resource) => WorkshopRole.fromJson({
        'stat': 'logistics',
        'resource': resource,
        'mult': 0.003,
      }).stat;
      expect(parsed(WorkshopRole.kExpTravel), CreatureStat.speed);
      expect(parsed(WorkshopRole.kExpCarry), CreatureStat.carry);
      expect(parsed(WorkshopRole.kExpGoods), CreatureStat.gathering);
      // And never the silent fallback that would turn a post into a gym.
      expect(parsed(WorkshopRole.kExpTravel), isNot(CreatureStat.hp));
      // On any OTHER post the name means the stat again (2026-07-30) — the
      // translation is scoped to the three trips it was written for, or a store
      // authored in Dev Mode would silently be staffed by carriers.
      expect(parsed(WorkshopRole.kStorageRoom), CreatureStat.logistics);
    });

    test('gathering now has a building too — the smokehouse', () {
      // It used to be the one work stat that only worked on the MAP.
      expect(stationable(), contains(CreatureStat.gathering));
    });

    test('their outputs are systems, not stockpile resources', () {
      for (final key in [
        WorkshopRole.kHealSpeed,
        WorkshopRole.kTradeRate,
        WorkshopRole.kExpCarry,
        WorkshopRole.kExpTravel,
        WorkshopRole.kExpGoods,
        WorkshopRole.kExpedition,
      ]) {
        final role = WorkshopRole(
          stat: CreatureStat.medicine,
          resource: key,
          mult: 1,
        );
        expect(role.producesResource, isFalse,
            reason: '$key must not land in the storehouse');
      }
    });

    test('the civil-service and trip-amplifier posts pay per point', () {
      double multOf(String id, String output) => kFallbackBuildingDefs[id]!
          .workshops
          .firstWhere((w) => w.resource == output)
          .mult;
      // Small fractions: a 30-point worker is a nudge, a full crew is a real
      // bonus, and nothing here can run away with the economy.
      for (final (id, output) in [
        ('healing_hut', WorkshopRole.kHealSpeed),
        ('trading_post', WorkshopRole.kTradeRate),
        ('warehouse', WorkshopRole.kExpCarry),
        ('smokehouse', WorkshopRole.kExpGoods),
      ]) {
        final mult = multOf(id, output);
        expect(mult, greaterThan(0), reason: id);
        expect(mult, lessThan(0.01),
            reason: '$id: a single point must not swing a whole system');
      }
      // The Scout Post obeys it too, whether it runs the two older
      // single-purpose posts or the combined post with its three dials. A dial
      // may be 0 — that is how one PART of a combined post is switched off (the
      // Scout Post leaves the goods yield to the Smokehouse) — but never large,
      // and never all of them at once.
      for (final w in kFallbackBuildingDefs['scout_post']!.workshops) {
        final dials = w.isCombined ? w.mults : {w.resource: w.mult};
        expect(dials.values.any((v) => v > 0), isTrue,
            reason: 'a post with every dial at 0 does nothing at all');
        for (final e in dials.entries) {
          expect(e.value, greaterThanOrEqualTo(0), reason: e.key);
          expect(e.value, lessThanOrEqualTo(0.01),
              reason: 'scout_post ${e.key}: one point must not swing a system');
        }
      }
    });
  });

  group('civil archetypes follow the stats', () {
    test('every work-role stat can be a species focus', () {
      final focuses = {
        for (final a in CivilArchetype.values) civilFocusStat(a),
      };
      for (final s in kCivilianStats) {
        expect(focuses, contains(s), reason: '${s.name} has no archetype');
      }
      expect(focuses, contains(CreatureStat.carry)); // the carrier
      expect(focuses, contains(null)); // the generalist
    });

    test('a focus really concentrates the budget', () {
      final w = civilArchetypeWeights(CivilArchetype.medic);
      expect(w[CreatureStat.medicine]!, greaterThan(w[CreatureStat.trade]!));
      expect(w.values.reduce((a, b) => a + b),
          closeTo(kNonCombatBudgetTarget, 1e-9));
    });
  });
}
