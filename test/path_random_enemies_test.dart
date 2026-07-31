import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';

// ── Zufällige Gegner + ihre Verteilung (user 2026-07-30) ────
// "die Option ein, dass ich die Monster zufällig hinzufügen kann. Dabei soll die
// Anzahl der Monster gleichbleiben, wie ich sie angegeben habe und ich möchte
// sehen, wie oft welches Monster in den Knoten vorkommt."
//
// The dice and the tally are a pair: a roll you cannot inspect is a roll you
// cannot trust. Both rules are pinned here because both fail QUIETLY — a roll
// that drops a level, or a tally that counts one node's duplicate twice, still
// produces a screen full of plausible numbers.
void main() {
  PathNode node(String id, List<PathEnemy> enemies) => PathNode(
    id: id,
    order: 1,
    name: id,
    enemies: enemies,
  );

  PathEnemy foe(String species, [int level = 5]) =>
      PathEnemy(speciesId: species, level: level);

  group('the roll keeps what the author decided', () {
    final pool = ['a', 'b', 'c', 'd', 'e'];

    test('exactly the count asked for', () {
      for (final n in [1, 3, 5, 9]) {
        final rolled = rollPathEnemies(
          poolIds: pool,
          count: n,
          keepLevels: const [],
          rng: math.Random(1),
        );
        expect(rolled.length, n, reason: 'count $n');
      }
    });

    test('the LEVELS survive a re-roll, position by position', () {
      // The whole reason the dice only touches the species: a difficulty curve
      // is work, and re-rolling names must not undo it.
      final rolled = rollPathEnemies(
        poolIds: pool,
        count: 3,
        keepLevels: const [4, 9, 14],
        rng: math.Random(2),
      );
      expect(rolled.map((e) => e.level), [4, 9, 14]);
    });

    test('new slots continue at the last level, not at 1', () {
      final rolled = rollPathEnemies(
        poolIds: pool,
        count: 4,
        keepLevels: const [7, 8],
        rng: math.Random(3),
      );
      expect(rolled.map((e) => e.level), [7, 8, 8, 8]);
    });

    test('an empty node starts at level 1', () {
      final rolled = rollPathEnemies(
        poolIds: pool,
        count: 2,
        keepLevels: const [],
        rng: math.Random(4),
      );
      expect(rolled.every((e) => e.level == 1), isTrue);
    });

    test('species are DISTINCT while the pool allows it', () {
      // Three copies of one monster is a node nobody designed on purpose.
      for (var seed = 0; seed < 40; seed++) {
        final rolled = rollPathEnemies(
          poolIds: pool,
          count: 5,
          keepLevels: const [],
          rng: math.Random(seed),
        );
        expect(
          rolled.map((e) => e.speciesId).toSet().length,
          5,
          reason: 'seed $seed repeated a species with room to spare',
        );
      }
    });

    test('a pool smaller than the count wraps instead of coming up short', () {
      final rolled = rollPathEnemies(
        poolIds: const ['a', 'b'],
        count: 5,
        keepLevels: const [],
        rng: math.Random(5),
      );
      expect(rolled.length, 5, reason: 'the count still wins');
      expect(rolled.map((e) => e.speciesId).toSet(), {'a', 'b'});
    });

    test('it really rolls — two seeds disagree', () {
      List<String> ids(int seed) => rollPathEnemies(
        poolIds: pool,
        count: 3,
        keepLevels: const [],
        rng: math.Random(seed),
      ).map((e) => e.speciesId).toList();
      // Guards the one bug that would make the feature pointless while every
      // other test still passed: a "shuffle" that returns the same order.
      expect({for (var s = 0; s < 12; s++) ids(s).join()}.length,
          greaterThan(1));
    });

    test('no pool, no enemies — and no crash', () {
      expect(
        rollPathEnemies(
          poolIds: const [],
          count: 3,
          keepLevels: const [],
          rng: math.Random(6),
        ),
        isEmpty,
      );
      expect(
        rollPathEnemies(
          poolIds: pool,
          count: 0,
          keepLevels: const [],
          rng: math.Random(6),
        ),
        isEmpty,
      );
    });
  });

  group('the tally answers both questions', () {
    test('total counts every appearance, nodes counts places', () {
      // 'wolf' twice in ONE node is 2 appearances but 1 node — the distinction
      // that makes the panel worth reading.
      final dist = pathSpeciesDistribution([
        node('n1', [foe('wolf'), foe('wolf'), foe('bear')]),
        node('n2', [foe('wolf')]),
        node('n3', [foe('bear')]),
      ]);
      expect(dist['wolf'], (total: 3, nodes: 2));
      expect(dist['bear'], (total: 2, nodes: 2));
    });

    test('a species nobody fights is simply absent', () {
      // Which is what lets the panel list the unused ones separately.
      final dist = pathSpeciesDistribution([
        node('n1', [foe('wolf')]),
      ]);
      expect(dist.containsKey('bear'), isFalse);
    });

    test('nodes without enemies contribute nothing', () {
      final dist = pathSpeciesDistribution([
        node('empty', const []),
        node('n1', [foe('wolf')]),
      ]);
      expect(dist.length, 1);
      expect(dist['wolf']!.total, 1);
    });

    test('an empty path tallies to nothing', () {
      expect(pathSpeciesDistribution(const []), isEmpty);
    });

    test('the totals add up to the enemies actually placed', () {
      // The invariant that catches a miscount: whatever the panel prints as the
      // per-species totals must sum to the number of enemy entries on the path.
      final nodes = [
        node('n1', [foe('a'), foe('b'), foe('a')]),
        node('n2', [foe('c')]),
        node('n3', [foe('b'), foe('b')]),
      ];
      final placed = nodes.fold<int>(0, (s, n) => s + n.enemies.length);
      final summed = pathSpeciesDistribution(nodes)
          .values
          .fold<int>(0, (s, v) => s + v.total);
      expect(summed, placed);
    });
  });
  // ── Gleichmässig, nicht nur zufällig (user 2026-07-30) ──────
  // "Die Verteilung soll etwa gleichmässig sein."
  //
  // Uniform random is NOT even, and the difference is exactly what the
  // distribution sheet exists to show: over a region's worth of fights it
  // reliably leaves a monster unused while another appears five times.
  group('the roll spreads evenly', () {
    final pool = ['a', 'b', 'c', 'd', 'e', 'f'];

    /// Rolls a whole region the way the sheet's button does — one running tally
    /// across every fight.
    Map<String, int> rollRegion({
      required int fights,
      required int perFight,
      required int seed,
    }) {
      final usage = {for (final id in pool) id: 0};
      final rng = math.Random(seed);
      for (var i = 0; i < fights; i++) {
        for (final e in rollPathEnemies(
          poolIds: pool,
          count: perFight,
          keepLevels: const [3],
          rng: rng,
          usage: usage,
        )) {
          usage[e.speciesId] = (usage[e.speciesId] ?? 0) + 1;
        }
      }
      return usage;
    }

    test('every species is used, and none runs away with it', () {
      // 17 fights × 2 over 6 species = 34 placements ≈ 5.7 each.
      for (var seed = 0; seed < 20; seed++) {
        final usage = rollRegion(fights: 17, perFight: 2, seed: seed);
        final counts = usage.values.toList()..sort();
        expect(counts.first, greaterThan(0),
            reason: 'seed $seed left a species unused');
        // Perfectly flat is 5 or 6; the spread must never exceed one step.
        expect(counts.last - counts.first, lessThanOrEqualTo(1),
            reason: 'seed $seed spread ${counts.first}..${counts.last}');
      }
    });

    test('it is still a ROLL — two seeds place them differently', () {
      String shape(int seed) {
        final usage = {for (final id in pool) id: 0};
        final rng = math.Random(seed);
        final out = <String>[];
        for (var i = 0; i < 6; i++) {
          final rolled = rollPathEnemies(
            poolIds: pool,
            count: 2,
            keepLevels: const [1],
            rng: rng,
            usage: usage,
          );
          for (final e in rolled) {
            usage[e.speciesId] = (usage[e.speciesId] ?? 0) + 1;
            out.add(e.speciesId);
          }
        }
        return out.join();
      }

      expect({for (var s = 0; s < 12; s++) shape(s)}.length, greaterThan(1));
    });

    test('an empty tally behaves exactly as before', () {
      // The default: no bias, just a shuffle. Callers that know nothing about
      // the rest of the path must not be forced to invent a tally.
      final rolled = rollPathEnemies(
        poolIds: pool,
        count: 3,
        keepLevels: const [5],
        rng: math.Random(1),
      );
      expect(rolled.length, 3);
      expect(rolled.map((e) => e.speciesId).toSet().length, 3);
    });

    test('the least-used come FIRST, whatever the shuffle', () {
      // The rule in one assertion: with everything else placed twice and one
      // species never, that species must be in the next draw.
      final usage = {for (final id in pool) id: 2}..['f'] = 0;
      for (var seed = 0; seed < 20; seed++) {
        final rolled = rollPathEnemies(
          poolIds: pool,
          count: 1,
          keepLevels: const [1],
          rng: math.Random(seed),
          usage: usage,
        );
        expect(rolled.single.speciesId, 'f', reason: 'seed $seed');
      }
    });

    test('the tally the caller passed is not mutated', () {
      // The sheet counts what it placed itself; a roll that silently edited the
      // map would double-count and skew the next node.
      final usage = {'a': 1};
      rollPathEnemies(
        poolIds: pool,
        count: 2,
        keepLevels: const [1],
        rng: math.Random(3),
        usage: usage,
      );
      expect(usage, {'a': 1});
    });
  });
}
