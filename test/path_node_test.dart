import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart'
    show buildingUnlockBattle, kBuildingUnlockBattle;

void main() {
  group('PathNode round-trips through the DB row', () {
    test('full node survives toDefRow/fromDefRow', () {
      const node = PathNode(
        id: 'node_7',
        order: 7,
        name: 'Ambush',
        areaId: 'verdant_hollow',
        isBoss: false,
        enemies: [
          PathEnemy(speciesId: 'sprout', level: 4),
          PathEnemy(speciesId: 'pebble', level: 5),
        ],
        rewards: PathRewards(
          // Raw resources are gone (user 2026-07-30) — a node's material reward
          // is a PACKAGE, which travels as an ordinary item.
          items: {'minor_potion': 2, 'pack_wood_crate': 5},
          buildings: ['healing_hut'],
          expansions: 1,
        ),
      );
      final r = PathNode.fromDefRow(node.toDefRow());
      expect(r.id, 'node_7');
      expect(r.order, 7);
      expect(r.areaId, 'verdant_hollow');
      expect(r.isBoss, isFalse);
      expect(r.enemies.length, 2);
      expect(r.enemies[0].speciesId, 'sprout');
      expect(r.enemies[1].level, 5);
      expect(r.rewards.items['minor_potion'], 2);
      expect(r.rewards.items['pack_wood_crate'], 5, reason: '5×500 wood');
      expect(r.rewards.buildings, ['healing_hut']);
      expect(r.rewards.expansions, 1);
    });

    test('an item reward of 0 is dropped, not promised', () {
      final r = PathRewards.fromJson({'items': {'minor_potion': 0}});
      expect(r.items, isEmpty);
      expect(r.isEmpty, isTrue);
    });

    test('empty rewards/enemies round-trip to empties', () {
      const node = PathNode(id: 'n', order: 1, name: 'x');
      final r = PathNode.fromDefRow(node.toDefRow());
      expect(r.enemies, isEmpty);
      expect(r.rewards.isEmpty, isTrue);
    });
  });

  group('fallback path seeded from the formula', () {
    test('one node per battle across the bundled areas, boss flag matches', () {
      final ordered = pathNodesInOrder();
      expect(ordered, isNotEmpty);
      // Orders are contiguous 1..N.
      for (var i = 0; i < ordered.length; i++) {
        expect(ordered[i].order, i + 1);
      }
      // Boss flags follow the formula.
      for (final n in ordered) {
        expect(n.isBoss, isBossBattle(n.order), reason: 'battle ${n.order}');
      }
    });

    test('seeded building rewards match the seed table', () {
      for (final e in kBuildingUnlockBattle.entries) {
        final n = kPathNodes['node_${e.value}'];
        if (n == null) continue; // beyond the bundled areas' range
        expect(n.rewards.buildings, contains(e.key));
      }
    });

    test('seed leaves enemies empty (formula fallback until authored)', () {
      expect(pathNodesInOrder().every((n) => n.enemies.isEmpty), isTrue);
    });

    test('the Trade Center is a node reward in era I', () {
      expect(kPathNodes['node_11']?.rewards.buildings, contains('trading_post'));
    });
  });

  // User 2026-07-26: "nur diese Gebäude, welche ich als Belohnung anwähle, gibt
  // es auch als Belohnung." The unlock tables are a SEED for a fresh path; once
  // a node is authored, it is the whole answer.
  group('the authored path is the only authority on building unlocks', () {
    late Map<String, PathNode> saved;

    setUp(() => saved = Map.of(kPathNodes));
    tearDown(() => kPathNodes
      ..clear()
      ..addAll(saved));

    test('the seeded path gates the Trade Center at its node', () {
      expect(buildingUnlockBattle('trading_post'), 11);
    });

    test('unticking it on the node really un-gates it', () {
      // This is the bug the fallback caused: the editor showed no reward while
      // the game still demanded battle 11, and the two could not be reconciled.
      final n = kPathNodes['node_11']!;
      kPathNodes['node_11'] = PathNode(
        id: n.id,
        order: n.order,
        name: n.name,
        areaId: n.areaId,
        isBoss: n.isBoss,
        rewards: PathRewards(
          buildings: n.rewards.buildings
              .where((b) => b != 'trading_post')
              .toList(),
        ),
      );
      expect(buildingUnlockBattle('trading_post'), 0);
      // …and the legacy table still SAYS 11, which is exactly why it must not
      // be consulted at runtime.
      expect(kBuildingUnlockBattle['trading_post'], 11);
    });

    test('moving it to another node moves the gate', () {
      final n = kPathNodes['node_4']!;
      kPathNodes['node_4'] = PathNode(
        id: n.id,
        order: n.order,
        name: n.name,
        areaId: n.areaId,
        isBoss: n.isBoss,
        rewards: PathRewards(
          buildings: [...n.rewards.buildings, 'trading_post'],
        ),
      );
      // The EARLIEST node that grants it wins.
      expect(buildingUnlockBattle('trading_post'), 4);
    });

    test('a building no node grants is simply not path-gated', () {
      expect(kBuildingUnlockBattle.containsKey('scout_post'), isFalse);
      expect(buildingUnlockBattle('scout_post'), 0);
    });
  });

  // Loot is CONSUMABLE, so unlike a building unlock it must be paid out exactly
  // once, for the nodes a step actually cleared — see the window rule in
  // pathResourceLoot. These two guard against both failure modes: paying twice
  // (a re-clear) and skipping the nodes a multi-step jump passed over.
  group('node loot is a delta, paid once', () {
    setUp(() {
      kPathNodes
        ..clear()
        ..addAll({
          'a': const PathNode(
            id: 'a',
            order: 1,
            name: 'A',
            rewards: PathRewards(items: {'minor_potion': 1}),
          ),
          'b': const PathNode(
            id: 'b',
            order: 2,
            name: 'B',
            rewards: PathRewards(
              items: {'minor_potion': 2, 'catch_lure': 1},
            ),
          ),
          'c': const PathNode(id: 'c', order: 3, name: 'C'),
        });
    });

    tearDown(() {
      kPathNodes
        ..clear()
        ..addAll(kFallbackPathNodes);
    });

    test('a jump over several nodes sums every one of them', () {
      expect(pathItemLoot(0, 3), {'minor_potion': 3, 'catch_lure': 1});
    });

    test('already-cleared nodes pay nothing again', () {
      expect(pathItemLoot(2, 3), isEmpty); // node 3 grants nothing
      expect(pathItemLoot(1, 2), {'minor_potion': 2, 'catch_lure': 1});
    });

    test('a node can no longer pay raw resources at all', () {
      // The rule, not just the absence of a field: an old row that still carries
      // a `resources` map grants NOTHING from it (user 2026-07-30).
      final legacy = PathRewards.fromJson({
        'resources': {'wood': 500},
        'items': {'minor_potion': 1},
      });
      expect(legacy.items, {'minor_potion': 1});
      expect(legacy.toJson().containsKey('resources'), isFalse,
          reason: 'and saving the node drops the dead map');
    });
  });
}
