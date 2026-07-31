import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/services/gold_economy.dart';

void main() {
  // Gold's whole job: turn SURPLUS into TIME. It gates nothing — a player who
  // ignores it loses no content, only patience. These pin the properties that
  // keep it that way.
  group('selling', () {
    test('gold cannot be sold for gold', () {
      expect(sellRate('gold'), 0);
      expect(sellValue('gold', 100), 0);
      expect(minSellable('gold'), double.infinity);
    });

    test('a special resource is worth more than a bulk one', () {
      // Goods are scarce AND have a real sink (healing) — selling them has to
      // be a trade-off, not a no-brainer.
      expect(sellRate('fish'), greaterThan(sellRate('wood')));
      expect(sellRate('wood'), sellRate('stone'));
    });

    test('a resource a later era introduces prices itself', () {
      // THE scaling property: sellRate is derived from "is this a good?", not
      // from a per-resource table, so new content needs no change here.
      expect(sellRate('bronze_unknown_to_this_code'), kBasicSellRate);
      for (final id in kGoodsDefs.keys) {
        expect(sellRate(id), kGoodsSellRate, reason: id);
      }
    });

    test('selling floors — it never invents a coin', () {
      expect(sellValue('wood', 19), 1); // 1.9 → 1
      expect(sellValue('wood', 9), 0);
    });

    test('minSellable is the point where a sale stops being a scam', () {
      // Below it the sale rounds to 0 gold and would silently eat the stock,
      // so the UI must refuse rather than take it.
      final min = minSellable('wood');
      expect(sellValue('wood', min), greaterThanOrEqualTo(1));
      expect(sellValue('wood', min - 1), 0);
    });
  });

  group('buying time', () {
    test('a finished timer is free', () {
      expect(goldToSkip(Duration.zero), 0);
      expect(goldToSkip(const Duration(seconds: -5)), 0);
    });

    test('an unfinished timer is never free', () {
      // Even one second left must cost a coin — a free skip is not a sink.
      expect(goldToSkip(const Duration(seconds: 1)), greaterThanOrEqualTo(1));
    });

    test('it is priced on time REMAINING, so waiting is always cheaper', () {
      final early = goldToSkip(const Duration(minutes: 30));
      final late = goldToSkip(const Duration(minutes: 5));
      expect(late, lessThan(early));
    });

    test('roughly a coin a minute — the exchange rate of the game', () {
      expect(goldToSkip(const Duration(minutes: 30)), 30);
      expect(goldToSkip(const Duration(hours: 1)), 60);
    });
  });

  group('the loop is worth doing but does not erase the game', () {
    test('a day of wood buys a meaningful, bounded amount of skipping', () {
      // Anchored on docs/balancing.md §2's ~850 wood/day target.
      final gold = sellValue('wood', 850);
      final minutesBought = gold * kSecondsPerGold / 60;
      expect(minutesBought, greaterThan(30), reason: 'too weak to bother with');
      expect(
        minutesBought,
        lessThan(60 * 4),
        reason: 'a day of logs should not skip half a day of timers',
      );
    });

    test('gold is a real resource the map can produce', () {
      // "abbauen wie Holz auf der Karte" — it needs a gather stat mapping and
      // an emoji like any other, or a spot for it could not exist.
      expect(kResourceEmoji['gold'], isNotNull);
    });
  });
}
