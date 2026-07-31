import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';

// ── Was eine Raffinerie verbrennt (user 2026-07-31) ─────────
// "clay rafinery soll anzeigen, welche Ressourcen verbraucht werden, um die
// neue herzustellen"
//
// The building card derives the burn from the rate it is already printing, so
// the two halves of the trade cannot drift apart. What is pinned here is that
// derivation — a card that overstates the burn scares you off a building that is
// fine, and one that understates it hides why the yard keeps running dry.
void main() {
  test('the era-II element is the one paid for in wood and stone', () {
    // The premise of the whole feature: era II is where raw becomes refined.
    final frame = kGoodsDefs['frame']!;
    expect(frame.refinedFrom, {'wood': 2, 'stone': 2});
    expect(elementForEra(2)?.id, 'frame');
  });

  test('a recipe is reported only for goods that are assembled', () {
    final r = refiningRecipes(['frame', 'fur', 'wood', 'nonsense']);
    expect(r.keys, ['frame'], reason: 'fur is gathered, wood is raw');
  });

  test('the burn is the rate times the recipe, per input', () {
    // 7 frames an hour is 14 wood and 14 stone an hour.
    expect(refiningInputsPerHour({'frame': 7}), {'wood': 14.0, 'stone': 14.0});
  });

  test('two refined goods at once add up per input', () {
    // daub eats frames, frames eat wood — a card listing both must not lose one.
    final burn = refiningInputsPerHour({'frame': 2, 'daub': 3});
    expect(burn['wood'], 4);
    expect(burn['stone'], 4);
    expect(burn['frame'], 6);
    expect(burn['clay'], 6);
  });

  test('nothing produced, nothing burned', () {
    expect(refiningInputsPerHour({'frame': 0}), isEmpty);
    expect(refiningInputsPerHour({'fur': 12}), isEmpty,
        reason: 'a Fur Lodge consumes no inputs');
    expect(refiningInputsPerHour(const {}), isEmpty);
  });

  test('the burn is ONE step down the ladder, not the raw price', () {
    // rawCostOf answers "what is a Daub Wall worth in wood"; the card answers
    // "what does this building take off my pile this hour". Different questions.
    expect(refiningInputsPerHour({'daub': 1}), {'frame': 2.0, 'clay': 2.0});
    expect(rawCostOf('daub'), containsPair('wood', 4.0));
  });

  group('the stock a refinery is checked against', () {
    ResourceModel res({double wood = 0, double stone = 0, Map<String, double> goods = const {}}) =>
        ResourceModel(
          settlementId: 's',
          wood: wood,
          stone: stone,
          goods: goods,
          lastUpdatedAt: DateTime(2026),
        );

    test('columns and goods answer through one lookup', () {
      final r = res(wood: 12, stone: 3, goods: {'frame': 5});
      expect(r.amountOf('wood'), 12);
      expect(r.amountOf('stone'), 3);
      expect(r.amountOf('gold'), 0);
      expect(r.amountOf('frame'), 5);
      expect(r.amountOf('nothing_at_all'), 0);
    });

    test('an input at zero is what «nothing is being refined» means', () {
      final r = res(wood: 40, goods: {'frame': 9});
      final inputs = refiningRecipes(['frame']).values.first.keys;
      expect(inputs.where((i) => r.amountOf(i) <= 0), ['stone'],
          reason: 'wood in the yard, no stone — the tick refines nothing');
    });
  });
}
