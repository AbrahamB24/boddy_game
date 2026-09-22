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

    test(
      'a sale pays a thousandth of the trade value: 10 000 wood → 1 gold',
      () {
        // User 2026-09-22: "10000 für 1 Gold" — selling is no longer how you get
        // gold, it is a drain for stock you cannot store.
        expect(kSellPayoutFactor, 0.001);
        expect(sellValue('wood', 10000), 1);
        expect(sellValue('stone', 10000), 1);
        expect(sellValue('wood', 9999), 0);
      },
    );

    test('selling floors — it never invents a coin', () {
      expect(sellValue('wood', 19999), 1); // 1.9999 → 1
      expect(sellValue('wood', 20000), 2);
    });

    test('trading keeps the old values — only the payout was cut', () {
      // Barter and buying goods price on sellRate, which did not change.
      expect(sellRate('wood'), kBasicSellRate);
      expect(sellPayoutRate('wood'), closeTo(sellRate('wood') * 0.001, 1e-12));
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

    test('ten coins a minute — the exchange rate of the game', () {
      // User 2026-09-22: skipping is "viel viel teurer" (it was 1 a minute).
      expect(kSecondsPerGold, 6);
      expect(goldToSkip(const Duration(minutes: 30)), 300);
      expect(goldToSkip(const Duration(hours: 1)), 600);
    });

    test('a day of goals buys minutes of skipping, not hours', () {
      // Three daily tasks (~15-30 gold each) plus the plain chest (25) ≈ 100 gold.
      final minutes = 100 * kSecondsPerGold / 60;
      expect(minutes, lessThan(30));
    });
  });

  group('gold is worth something and does not erase the game', () {
    test('a day of wood, or a full store, sells for nothing', () {
      // Anchored on docs/balancing.md §2's ~850 wood/day target: gold used to
      // come from this (≈ 85 a day); it must not any more.
      expect(sellValue('wood', 850), 0);
      expect(sellValue('wood', 2000), 0);
      expect(sellValue('fish', 1000), 0);
    });

    test('gold is a real resource the map can produce', () {
      // "abbauen wie Holz auf der Karte" — it needs a gather stat mapping and
      // an emoji like any other, or a spot for it could not exist.
      expect(kResourceEmoji['gold'], isNotNull);
    });
  });
}
