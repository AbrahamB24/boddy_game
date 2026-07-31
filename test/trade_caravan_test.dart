import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/settlement/data/gather_defs.dart';
import 'package:boddygame/features/settlement/services/trade_caravan.dart';

// A trade is a TRIP since 2026-07-26 (user: "sobald ich einen trade auswähle,
// sende ich eine Expedition. Die Zeitdauer ist abhängig vom Wert speed, und die
// maximale Ladekapazität von carry").
//
// One stat per number, and no others — the point of the rework. `trade` is
// deliberately absent from this file: prices stayed the Trade Center's job
// (user decision), so a caravan can change WHEN and HOW MUCH, never the rate.

CreatureInstance _mule({int carry = 0, int speed = 0, String id = 'm'}) =>
    CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      statBase: {
        CreatureStat.carry: carry.toDouble(),
        CreatureStat.speed: speed.toDouble(),
      },
      statSlope: const {},
    );

void main() {
  group('speed decides how long the caravan is away', () {
    test('with no speed to spend, the trip is the full authored time', () {
      expect(tradeTimeCut(0), 0);
      // A real monster never has 0 in a stat (statValue floors at 1), so the
      // slowest possible caravan lands a hair under the base rather than on
      // it — the base is the ceiling, and this is how close you get to it.
      expect(
        tradeTripDuration([_mule(carry: 5)]).inMinutes,
        closeTo(kTradeBaseHours * 60, 2),
      );
    });

    test('kTradeSpeedForHalfTime halves it', () {
      expect(tradeTimeCut(kTradeSpeedForHalfTime), closeTo(0.5, 1e-9));
      expect(tradeTimeCut(kTradeSpeedForHalfTime * 4), closeTo(0.8, 1e-9));
      final half = tradeTripDuration(
        [_mule(carry: 5, speed: kTradeSpeedForHalfTime.round())],
      );
      expect(half.inMinutes, (kTradeBaseHours * 30).round());
    });

    test('speed is SUMMED — a second courier shortens the same trip', () {
      final one = tradeTripDuration([_mule(carry: 1, speed: 50)]);
      final two = tradeTripDuration([
        _mule(carry: 1, speed: 50, id: 'a'),
        _mule(carry: 1, speed: 50, id: 'b'),
      ]);
      expect(two, lessThan(one));
    });

    test('no ceiling, and the road is never instant', () {
      expect(tradeTimeCut(1e6), lessThan(1.0));
      final fast = tradeTripDuration([_mule(carry: 1, speed: 100000)]);
      expect(fast.inSeconds, greaterThanOrEqualTo(0));
      expect(tradeTimeCut(1e6), greaterThan(tradeTimeCut(1e5)));
    });

    test('the scout post still shortens a trade trip', () {
      final plain = tradeTripDuration([_mule(carry: 1, speed: 100)]);
      final scouted =
          tradeTripDuration([_mule(carry: 1, speed: 100)], travelMult: 0.5);
      expect(scouted.inSeconds, (plain.inSeconds / 2).round());
    });
  });

  group('carry decides how much fits', () {
    test('capacity reads the SAME per-resource dial a gather trip does', () {
      final crew = [_mule(carry: 10)];
      expect(
        tradeCapacity('wood', crew),
        gatherDefFor('wood').loadCap(10),
      );
      // Bulk hauls in bulk; gold is one coin per point. A caravan is worth
      // very different unit counts depending on what it is carrying.
      expect(tradeCapacity('wood', crew),
          greaterThan(tradeCapacity('gold', crew)));
    });

    test('a warehouse raises it', () {
      final crew = [_mule(carry: 10)];
      expect(
        tradeCapacity('wood', crew, carryMult: 1.5),
        closeTo(tradeCapacity('wood', crew) * 1.5, 1e-9),
      );
    });

    test('the haul is capped by the caravan AND by the storehouse', () {
      final crew = [_mule(carry: 10)];
      final cap = tradeCapacity('wood', crew);
      // Plenty in store → the caravan is the limit.
      expect(maxTradeAmount('wood', crew, 1e9), cap.floorToDouble());
      // Little in store → the storehouse is.
      expect(maxTradeAmount('wood', crew, 7), 7);
      // Never a fraction of a log.
      expect(maxTradeAmount('wood', crew, 7.8), 7);
    });

    test('a barter is bounded by the RETURN leg too', () {
      // 1 wood → 5 gold would come home five times heavier than it left. The
      // outbound cap alone would happily promise a load nobody can haul.
      final crew = [_mule(carry: 10)];
      final outCap = tradeCapacity('wood', crew);
      final bounded = maxBarterInput(
        from: 'wood',
        to: 'gold',
        available: 1e9,
        yieldPerUnit: 5,
        members: crew,
        carryMult: 1.0,
      );
      expect(bounded, lessThan(outCap));
      expect(bounded * 5, lessThanOrEqualTo(tradeCapacity('gold', crew)));
    });
  });

  group('who may be sent', () {
    test('an empty caravan is not a caravan', () {
      expect(caravanCanHaul(const []), isFalse);
    });

    test('any real monster can haul — statValue never returns 0', () {
      // Which is why the carry check is about the LIST being empty, not about
      // finding a monster too weak to help: even a rolled 0 reads back as 1.
      expect(caravanCanHaul([_mule(carry: 0, speed: 90)]), isTrue);
      expect(caravanCanHaul([_mule(carry: 4)]), isTrue);
    });
  });
}
