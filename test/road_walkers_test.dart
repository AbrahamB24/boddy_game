import 'dart:math' as math;

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/settlement/data/road_tiles.dart';
import 'package:boddygame/features/settlement/widgets/road_walkers.dart';
import 'package:flutter_test/flutter_test.dart';

// Monsters walking the roads (user 2026-11-03): they must stay on road cells,
// walk on rather than turn straight back, stay within the cap, tell the map to
// re-sort only when they step onto a new cell — and never crowd the town: one
// per type (species + stage), each leaving after a while and the next one
// turning up somewhere else.
CreatureInstance tidelord(String id, {int stage = 0}) => CreatureInstance(
  id: id,
  userId: 'u',
  speciesId: 'tidelord',
  stage: stage,
  gender: CreatureGender.male,
  statBase: const {},
  statSlope: const {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // An L of road: (10..20, 5) then (20, 5..15).
  final roads = <int>{
    for (var x = 10; x <= 20; x++) roadCellKey(x, 5),
    for (var y = 5; y <= 15; y++) roadCellKey(20, y),
  };
  final allStages = [
    for (var s = 0; s < 3; s++) tidelord('t$s', stage: s),
  ];

  test('walkers stay on the road and never step off it', () {
    final w = RoadWalkers(random: math.Random(1));
    w.sync(roads, allStages);
    expect(w.walkers, hasLength(3));
    for (var i = 0; i < 6000; i++) {
      w.step(1 / 30);
      for (final r in w.walkers) {
        expect(roads.contains(roadCellKey(r.fromX, r.fromY)), isTrue);
        expect(roads.contains(roadCellKey(r.toX, r.toY)), isTrue);
        expect((r.toX - r.fromX).abs() + (r.toY - r.fromY).abs(), lessThan(2));
      }
    }
    w.dispose();
  });

  test('all three Tidelord stages walk, but only one per stage', () {
    final w = RoadWalkers(random: math.Random(2));
    w.sync(roads, [
      for (var i = 0; i < 5; i++) tidelord('a$i'),
      for (var i = 0; i < 5; i++) tidelord('b$i', stage: 1),
      for (var i = 0; i < 5; i++) tidelord('c$i', stage: 2),
    ]);
    for (var i = 0; i < 9000; i++) {
      w.step(1 / 30);
      final types = [for (final r in w.walkers) r.type];
      expect(types.toSet().length, types.length);
    }
    w.dispose();
  });

  test('evolutions are drawn bigger than the pup', () {
    final w = RoadWalkers(random: math.Random(3));
    w.sync(roads, allStages);
    final h = {for (final r in w.walkers) r.creature.stage: r.height};
    expect(h[0], kWalkerHeight);
    expect(h[1]!, greaterThan(h[0]!));
    expect(h[2]!, greaterThan(h[1]!));
    w.dispose();
  });

  test('only species with walk sheets walk (for now: the Tidelord)', () {
    final w = RoadWalkers();
    final other = CreatureInstance(
      id: 'x',
      userId: 'u',
      speciesId: 'infernoclaw',
      gender: CreatureGender.male,
      statBase: const {},
      statSlope: const {},
    );
    w.sync(roads, [other]);
    expect(w.walkers, isEmpty);
    expect(w.active, isFalse);
    w.sync(roads, [other, tidelord('t')]);
    expect(w.walkers.map((r) => r.creature.id), ['t']);
    w.dispose();
  });

  test('a short road gets fewer walkers', () {
    final w = RoadWalkers();
    final short = {for (var x = 0; x < 8; x++) roadCellKey(x, 3)};
    w.sync(short, allStages);
    expect(w.walkers, hasLength(1));
    expect(w.walkers.length, lessThanOrEqualTo(kMaxRoadWalkers));
    w.dispose();
  });

  test('walkers leave after a while and a new one turns up elsewhere', () {
    final w = RoadWalkers(random: math.Random(4));
    w.sync(roads, [tidelord('a')]);
    final first = w.walkers.single;
    var gone = false;
    var cameBack = false;
    for (var i = 0; i < 30 * 120; i++) {
      w.step(1 / 30);
      if (!w.walkers.contains(first)) gone = true;
      if (gone && w.walkers.isNotEmpty) {
        cameBack = true;
        final again = w.walkers.single;
        expect(again.serial, isNot(first.serial));
        // Fading in, not popping.
        expect(again.opacity, lessThan(1));
        break;
      }
    }
    expect(gone, isTrue);
    expect(cameBack, isTrue);
    w.dispose();
  });

  test('no road, no walkers; the walk re-sorts the map as it goes', () {
    final w = RoadWalkers();
    w.sync(<int>{}, [tidelord('a')]);
    expect(w.walkers, isEmpty);
    w.sync(roads, [tidelord('a')]);
    final before = w.order.value;
    for (var i = 0; i < 600; i++) {
      w.step(1 / 30);
    }
    expect(w.order.value, greaterThan(before));
    w.dispose();
  });

  test('a walker never doubles back mid-road', () {
    final w = RoadWalkers();
    // A straight road far from its ends: every turn-around would be a choice.
    final line = {for (var x = 0; x < 200; x++) roadCellKey(x, 50)};
    w.sync(line, [tidelord('a')]);
    final r = w.walkers.single;
    var lastDir = 0;
    var reversals = 0;
    for (var i = 0; i < 3000 && w.walkers.contains(r); i++) {
      w.step(1 / 30);
      final dir = r.toX - r.fromX;
      if (dir != 0) {
        if (lastDir != 0 && dir == -lastDir && r.fromX > 0 && r.fromX < 199) {
          reversals++;
        }
        lastDir = dir;
      }
    }
    expect(reversals, 0);
    w.dispose();
  });
}
