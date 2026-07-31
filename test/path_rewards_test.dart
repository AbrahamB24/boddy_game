import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';
import 'package:boddygame/features/settlement/data/item_definitions.dart';

// ── Die Belohnungskurve (user 2026-07-30) ───────────────────
// "Jetzt bitte die Belohnung einmal für alle Knoten verteilen, je schwieriger,
// später der Knoten, desto mehr Ressourcen gibt es."
//
// The curve is generated, so what needs guarding is not a table of numbers but
// the two PROMISES in that sentence — later is more, and harder is more — plus
// the thing that would break them silently: a package id that resolves to
// nothing, which the bag would then hold as an unopenable mystery.
void main() {
  /// Build-resource units a node pays (wood + stone), read back off the ids.
  double buildUnits(PathNode n) {
    var total = 0.0;
    for (final e in n.rewards.items.entries) {
      final p = parsePackId(e.key);
      if (p == null) continue;
      if (p.resourceId == 'wood' || p.resourceId == 'stone') {
        total += p.amount * e.value;
      }
    }
    return total;
  }

  final path = pathNodesInOrder();

  test('every node on the path pays something', () {
    expect(path, isNotEmpty);
    for (final n in path) {
      expect(n.rewards.items, isNotEmpty, reason: 'battle ${n.order}');
      expect(buildUnits(n), greaterThan(0), reason: 'battle ${n.order}');
    }
  });

  test('LATER is more, within a region', () {
    // The steep axis: a region should pay out more the deeper you are in it.
    // Non-decreasing rather than strictly rising, because the amounts land on
    // the package ladder and two neighbouring fights can share a rung.
    for (var i = 1; i < path.length; i++) {
      final prev = path[i - 1];
      final cur = path[i];
      if (prev.isBoss) continue; // a new region restarts the climb
      if (eraForBattle(prev.order) != eraForBattle(cur.order)) continue;
      expect(
        buildUnits(cur),
        greaterThanOrEqualTo(buildUnits(prev)),
        reason: 'battle ${cur.order} pays less than ${prev.order}',
      );
    }
  });

  test('HARDER is more: the boss beats every fight in its region', () {
    for (final boss in path.where((n) => n.isBoss)) {
      final era = eraForBattle(boss.order);
      final regulars = path.where(
        (n) => !n.isBoss && eraForBattle(n.order) == era,
      );
      for (final n in regulars) {
        expect(buildUnits(boss), greaterThan(buildUnits(n)),
            reason: 'boss ${boss.order} vs ${n.order}');
      }
    }
  });

  test('a later region pays more, at the same position in it', () {
    // Across eras the whole curve is lifted by the same 1.4 the building costs
    // grow by, so a reward keeps its purchasing power.
    //
    // Asked of the CURVE, not of the bundled path: the seed stops at
    // kLastPathBattle (user 2026-07-30), so summing "what era II pays" would
    // measure how much content is authored rather than how the reward scales.
    double unitsOf(int battle) {
      var total = 0.0;
      for (final e in nodePackRewards(battle).entries) {
        final p = parsePackId(e.key);
        if (p == null) continue;
        if (p.resourceId == 'wood' || p.resourceId == 'stone') {
          total += p.amount * e.value;
        }
      }
      return total;
    }

    for (var era = 2; era <= 8; era++) {
      final here = (era - 1) * kBattlesPerEra + 10; // mid-region
      final before = (era - 2) * kBattlesPerEra + 10;
      expect(unitsOf(here), greaterThan(unitsOf(before)),
          reason: 'era $era vs ${era - 1}');
    }
  });

  test('era I lands where the balancing doc puts it', () {
    // ~40 % of the ~5 000 wood era I spends. Loose bounds: this pins the ORDER
    // of magnitude, which is what stops a refactor from silently paying 20 000.
    final eraOne = path.where((n) => eraForBattle(n.order) == 1);
    final wood = eraOne.fold<double>(0, (sum, n) {
      for (final e in n.rewards.items.entries) {
        final p = parsePackId(e.key);
        if (p?.resourceId == 'wood') sum += p!.amount * e.value;
      }
      return sum;
    });
    expect(wood, greaterThan(1200));
    expect(wood, lessThan(3000));
  });

  test('only the boss pays gold', () {
    for (final n in path) {
      final paysGold = n.rewards.items.keys
          .any((id) => parsePackId(id)?.resourceId == 'gold');
      expect(paysGold, n.isBoss, reason: 'battle ${n.order}');
    }
  });

  test('every reward id is a real item', () {
    // An id nothing defines sits in the bag as a parcel that cannot be opened.
    for (final n in path) {
      for (final id in n.rewards.items.keys) {
        expect(kItemDefs[id], isNotNull,
            reason: 'battle ${n.order} grants unknown "$id"');
      }
    }
  });

  test('the consumables survived the packages', () {
    // kNodeItemRewards' potions and lures are merged with the generated packs,
    // not replaced by them.
    final potions = path
        .where((n) => n.rewards.items.containsKey('minor_potion'))
        .length;
    expect(potions, greaterThan(0));
  });
}
