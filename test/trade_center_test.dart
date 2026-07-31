import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/services/gold_economy.dart';
import 'package:boddygame/features/settlement/services/trade_center.dart';

// The Trade Center's whole promise is that no direction of trade pays for
// itself: every loop through gold or barter must LOSE value, or the market is an
// infinite-money machine and the rest of the economy stops mattering. Most of
// this file is that one property, checked from each direction.

void main() {
  group('gold → goods costs more than selling paid', () {
    test('round trip loses gold at every discount, including the ceiling', () {
      for (final d in [0.0, 0.25, kMaxTradeDiscount, 1.0 /* clamped */]) {
        for (final r in ['wood', 'stone', 'fish', 'fur']) {
          const amount = 100.0;
          final earned = sellValue(r, amount);
          final cost = goodsBuyCost(r, amount, discount: d);
          expect(cost, greaterThan(earned),
              reason: 'sell→buy $r at discount $d must not break even');
        }
      }
    });

    test('a purchase is never free', () {
      expect(goodsBuyCost('wood', 1), greaterThanOrEqualTo(1));
      expect(goodsBuyCost('wood', 0), 0);
    });

    test('gold cannot be bought with gold', () {
      expect(goodsBuyCost('gold', 100), 0);
      expect(goodsForGold('gold', 100), 0);
    });

    test('goodsForGold is the inverse of goodsBuyCost (whole units, no gain)', () {
      final units = goodsForGold('fish', 100);
      expect(units, greaterThan(0));
      expect(goodsBuyCost('fish', units), lessThanOrEqualTo(100));
      // One more unit than the gold covers must cost more than the gold.
      expect(goodsBuyCost('fish', units + 1), greaterThan(100));
    });

    test('the discount narrows the spread but never reaches par', () {
      expect(goodsBuyMarkup(0), kGoodsBuyMarkup);
      expect(goodsBuyMarkup(kMaxTradeDiscount), lessThan(kGoodsBuyMarkup));
      expect(goodsBuyMarkup(5), greaterThan(1.0)); // clamped, still a spread
    });
  });

  group('barter keeps value minus the fee', () {
    test('two goods swap 1:1 minus the fee', () {
      // Every good shares one sell rate, so the ratio is the fee alone.
      expect(barterYield('fish', 'fur', 100), 100 * (1 - kBarterFee));
    });

    test('across the bulk/goods divide it follows the sell rates', () {
      // A good is worth 3.5 logs, so 100 logs buy ~21 fish after the fee.
      final gain = barterYield('wood', 'fish', 100);
      final expected =
          (100 * kBasicSellRate * (1 - kBarterFee) / kGoodsSellRate).floor();
      expect(gain, expected.toDouble());
    });

    test('a round trip loses value at every discount', () {
      for (final d in [0.0, 0.3, kMaxTradeDiscount]) {
        final there = barterYield('fish', 'fur', 100, discount: d);
        final back = barterYield('fur', 'fish', there, discount: d);
        expect(back, lessThan(100), reason: 'fish→fur→fish at discount $d');
      }
    });

    test('same resource, gold, or too little pays nothing', () {
      expect(barterYield('fish', 'fish', 100), 0);
      expect(barterYield('gold', 'fish', 100), 0);
      expect(barterYield('fish', 'gold', 100), 0);
      expect(barterYield('fish', 'fur', 1), 0); // 0.75 fur floors to none
    });

    test('minBarterAmount is the smallest offer that pays out', () {
      final min = minBarterAmount('fish', 'fur');
      expect(barterYield('fish', 'fur', min), greaterThanOrEqualTo(1));
      expect(barterYield('fish', 'fur', min - 1), 0);
    });
  });

  group('the item shop is a sink, not an arbitrage', () {
    const sold = ItemDef(
      id: 'x',
      name: 'X',
      emoji: '🧪',
      description: '',
      craftSeconds: 100,
      buyPrice: 20,
      sellPrice: 6,
    );

    test('selling back always loses gold, even at the discount ceiling', () {
      for (final d in [0.0, 0.3, kMaxTradeDiscount, 1.0]) {
        expect(itemSellValue(sold, discount: d),
            lessThan(itemBuyCost(sold, discount: d)),
            reason: 'buy→sell at discount $d');
      }
    });

    test('the discount makes buying cheaper, never free', () {
      expect(itemBuyCost(sold), 20);
      expect(itemBuyCost(sold, discount: kMaxTradeDiscount), lessThan(20));
      expect(itemBuyCost(sold, discount: 1), greaterThanOrEqualTo(1));
    });

    test('an unpriced item is neither stocked nor sellable', () {
      const free = ItemDef(
        id: 'y',
        name: 'Y',
        emoji: '🧪',
        description: '',
        craftSeconds: 100,
      );
      expect(itemIsSold(free), isFalse);
      expect(itemBuyCost(free), 0);
      expect(itemSellValue(free), 0);
    });

    test('the bundled starter items are all stocked, cheapest first', () {
      final stock = shopStock();
      expect(stock, isNotEmpty);
      for (var i = 1; i < stock.length; i++) {
        expect(stock[i].buyPrice, greaterThanOrEqualTo(stock[i - 1].buyPrice));
      }
    });
  });

  group('what is tradeable', () {
    test('era I trades wood, stone and its two luxuries — nothing later', () {
      final e1 = tradeableResources(1);
      expect(e1, containsAll(['wood', 'stone', 'fish', 'fur']));
      expect(e1, isNot(contains('honey'))); // era II
      expect(e1, isNot(contains('gold'))); // gold is the price, not the ware
    });

    test('a later era adds its goods without dropping the old ones', () {
      final e3 = tradeableResources(3);
      expect(e3, containsAll(['fish', 'honey', 'wine']));
      expect(e3.length, greaterThan(tradeableResources(1).length));
    });
  });

  group('the Trade Center building', () {
    test('exists, is era I and unlocks mid-era on the path', () {
      final def = kFallbackBuildingDefs['trading_post'];
      expect(def, isNotNull, reason: 'the Market action keys on this id');
      expect(def!.eraIds, contains('era_1'));
      expect(buildingUnlockBattle('trading_post'), 11);
    });

    test('its trade effect grows with the level and is read per level', () {
      final def = kFallbackBuildingDefs['trading_post']!;
      final l1 = def.tradePercentAt(1);
      final l3 = def.tradePercentAt(3);
      expect(l1, greaterThan(0));
      expect(l3, greaterThan(l1));
      // Anything else must not hand out trade rates.
      expect(kFallbackBuildingDefs['healing_hut']!.tradePercentAt(5), 0);
    });
  });
}
