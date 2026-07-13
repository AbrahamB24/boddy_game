import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/dungeon.dart';

void main() {
  test('generated maps are always well-formed (100 seeds)', () {
    for (var seed = 0; seed < 100; seed++) {
      final map = DungeonMap.generate(stage: 5, rng: math.Random(seed));

      // 5-8 path layers + boss layer.
      expect(map.layerCount, inInclusiveRange(6, 9), reason: 'seed $seed');

      // Exactly one boss, alone on the last layer.
      final bosses =
          map.nodes.where((n) => n.type == DungeonNodeType.boss).toList();
      expect(bosses.length, 1, reason: 'seed $seed');
      expect(bosses.single.layer, map.layerCount - 1, reason: 'seed $seed');

      // First layer is battles only.
      for (final n in map.layer(0)) {
        expect(n.type, DungeonNodeType.battle, reason: 'seed $seed');
      }

      // At least one heal room exists.
      expect(
        map.nodes.any((n) => n.type == DungeonNodeType.heal),
        isTrue,
        reason: 'seed $seed',
      );

      // Every non-boss node has ≥1 outgoing edge, all edges point exactly
      // one layer ahead.
      for (final n in map.nodes) {
        if (n.type == DungeonNodeType.boss) continue;
        expect(n.next, isNotEmpty, reason: 'seed $seed node ${n.id}');
        for (final id in n.next) {
          expect(map.byId(id).layer, n.layer + 1,
              reason: 'seed $seed node ${n.id}');
        }
      }

      // Every node (except layer 0) has ≥1 incoming edge — no orphans, and
      // therefore every start reaches the boss (edges always advance and
      // never dead-end).
      for (final n in map.nodes.where((n) => n.layer > 0)) {
        final hasIncoming = map.nodes.any((m) => m.next.contains(n.id));
        expect(hasIncoming, isTrue, reason: 'seed $seed node ${n.id}');
      }
    }
  });

  test('entry cost and rewards scale with stage; heal spaces pay nothing', () {
    final cheap = dungeonEntryCost(1);
    final pricey = dungeonEntryCost(kMaxDungeonStage);
    expect(pricey['gold']!, greaterThan(cheap['gold']!));

    final battle = dungeonSpaceReward(5, DungeonNodeType.battle);
    final boss = dungeonSpaceReward(5, DungeonNodeType.boss);
    final heal = dungeonSpaceReward(5, DungeonNodeType.heal);
    expect(boss['gold']!, greaterThan(battle['gold']!));
    expect(heal['gold'], 0);
  });

  test('wild/boss level formulas span the intended range', () {
    expect(wildLevelForStage(1), 5);
    expect(wildLevelForStage(kMaxDungeonStage), 69);
    expect(bossLevelForStage(kMaxDungeonStage), 75); // == kCreatureMaxLevel
  });
}
