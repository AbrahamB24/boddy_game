import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/settlement/data/gather_defs.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';

// The per-resource gathering dials (user 2026-07-25). Three separate complaints
// created them and each one is a test here: carry must not be weight 1:1, bulk
// must out-haul luxury and gold, and every number must live in exactly one
// place so a spot cannot disagree with it.

void main() {
  group('the bulk / luxury / gold split', () {
    test('a carry point holds far more wood than fish, and least gold', () {
      final wood = gatherDefFor('wood').unitsPerCarry;
      final fish = gatherDefFor('fish').unitsPerCarry;
      final gold = gatherDefFor('gold').unitsPerCarry;
      expect(wood, greaterThan(fish));
      expect(fish, greaterThan(gold));
      // The point of the rework: a carry point is worth MORE than one unit for
      // build resources, or an expedition can't compete with the storehouse.
      expect(wood, greaterThan(1));
    });

    test('gold is the slowest thing to dig out', () {
      final gold = gatherDefFor('gold').secondsPerUnitPerStat;
      for (final r in ['wood', 'stone', 'fish', 'fur']) {
        expect(gold, greaterThan(gatherDefFor(r).secondsPerUnitPerStat),
            reason: 'gold must trickle slower than $r');
      }
    });

    test('a full trip is worth sending: bulk beats luxury by volume', () {
      // Same group, two resources — the haul difference is the whole design.
      const carry = 15, gather = 190;
      final woodHaul = gatherDefFor('wood').loadCap(carry);
      final fishHaul = gatherDefFor('fish').loadCap(carry);
      expect(woodHaul, greaterThan(fishHaul * 2));
      // And it arrives in a sane time — not a 12-hour slog.
      final hours = woodHaul / gatherDefFor('wood').ratePerHour(gather);
      expect(hours, lessThan(6));
      expect(hours, greaterThan(0.2), reason: 'instant hauls make it free');
    });
  });

  group('the maths behind the dials', () {
    test('rate is linear in stat points', () {
      final d = gatherDefFor('wood');
      expect(d.ratePerHour(100), closeTo(d.ratePerHour(50) * 2, 1e-9));
      expect(d.ratePerHour(0), 0);
    });

    test('load cap is linear in carry points', () {
      final d = gatherDefFor('stone');
      expect(d.loadCap(10), d.unitsPerCarry * 10);
      expect(d.loadCap(0), 0);
    });

    test('a zero seconds-per-unit dial cannot divide by zero', () {
      const broken = ResourceGatherDef(
        resource: 'x',
        unitsPerCarry: 1,
        secondsPerUnitPerStat: 0,
        spotCapacity: 10,
        regenPerHour: 1,
      );
      expect(broken.ratePerHour(100), 0);
    });

    test('a def round-trips through its DB row', () {
      final d = gatherDefFor('wood');
      final back = ResourceGatherDef.fromDefRow(d.toDefRow());
      expect(back.resource, d.resource);
      expect(back.unitsPerCarry, d.unitsPerCarry);
      expect(back.secondsPerUnitPerStat, d.secondsPerUnitPerStat);
      expect(back.spotCapacity, d.spotCapacity);
      expect(back.regenPerHour, d.regenPerHour);
    });
  });

  group('coverage', () {
    test('every spot in the bundled map has dials', () {
      for (final area in kFallbackAreaDefs) {
        for (final spot in area.spots) {
          final d = gatherDefFor(spot.resource);
          expect(d.spotCapacity, greaterThan(0), reason: spot.id);
          expect(d.unitsPerCarry, greaterThan(0), reason: spot.id);
        }
      }
    });

    test('a later era\'s good gathers sensibly without a row of its own', () {
      // No dev row for honey/clay yet — the fallback must still be usable, the
      // same way a new good already sells at the goods rate on day one.
      final honey = gatherDefFor('honey'); // era II luxury
      expect(honey.unitsPerCarry, greaterThan(0));
      expect(honey.secondsPerUnitPerStat, greaterThan(0));
      // A build material stacks better than a luxury.
      final material = kGoodsDefs.values.firstWhere((g) => !g.isSupply);
      expect(gatherDefFor(material.id).unitsPerCarry,
          greaterThan(honey.unitsPerCarry));
    });

    test('the editor lists the authored dials and every good', () {
      final listed = gatherTunableResources();
      expect(listed, containsAll(kGatherDefs.keys));
      expect(listed, contains('honey'));
      expect(listed.toSet().length, listed.length, reason: 'no duplicates');
    });
  });

  test('a spot carries no numbers of its own any more', () {
    // The whole point of moving them: the JSON keeps only what a spot IS.
    const spot = ResourceSpotDef(id: 'sp', resource: 'wood');
    expect(spot.toJson().keys.toSet(), {'id', 'resource'});
    // Legacy rows with the old keys still load — they are simply ignored.
    final legacy = ResourceSpotDef.fromJson({
      'id': 'sp',
      'resource': 'wood',
      'yield_per_hour': 30,
      'capacity': 600,
      'regen_per_hour': 60,
    });
    expect(legacy.resource, 'wood');
    expect(legacy.toJson().containsKey('capacity'), isFalse);
  });

  group('a trip is stored as an unambiguous instant', () {
    // User 2026-07-25: "8min57 in der Vorschau, 2h08 effektiv". started_at was
    // serialised from a LOCAL DateTime with no zone suffix; Postgres reads such
    // a string into timestamptz as UTC, so a CEST send landed two hours in the
    // future and every countdown came back two hours too long.
    test('started_at is written in UTC, whatever zone it was made in', () {
      final local = DateTime(2026, 7, 25, 21, 30); // local wall clock
      final e = Expedition(
        id: '',
        userId: 'u',
        type: ExpeditionType.gather,
        areaId: 'a',
        memberIds: const ['c'],
        startedAt: local,
        duration: const Duration(minutes: 9),
      );
      final written = e.toRow()['started_at'] as String;
      expect(written.endsWith('Z'), isTrue,
          reason: 'a zoneless string is read as UTC by Postgres');
      expect(DateTime.parse(written).isAtSameMomentAs(local), isTrue);
    });

    test('a round trip through the row keeps the countdown', () {
      final started = DateTime(2026, 7, 25, 21, 30);
      final e = Expedition(
        id: 'x',
        userId: 'u',
        type: ExpeditionType.gather,
        areaId: 'a',
        memberIds: const ['c'],
        startedAt: started,
        duration: const Duration(minutes: 9),
      );
      final back = Expedition.fromRow({
        ...e.toRow(),
        'id': 'x',
        'duration_seconds': e.duration.inSeconds,
      });
      // Nine minutes after the start, nine minutes are gone — not 2h09.
      expect(back.remaining(started), const Duration(minutes: 9));
      expect(back.remaining(started.add(const Duration(minutes: 9))),
          Duration.zero);
    });
  });
}
