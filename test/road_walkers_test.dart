import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/settlement/data/road_tiles.dart';
import 'package:boddygame/features/settlement/widgets/road_walkers.dart';
import 'package:flutter_test/flutter_test.dart';

// Monsters walking the roads (user 2026-11-03): they must stay on road cells,
// walk on rather than turn straight back, stay within the cap, and tell the
// map to re-sort only when they step onto a new cell.
CreatureInstance tidelord(String id) => CreatureInstance(
  id: id,
  userId: 'u',
  speciesId: 'tidelord',
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

  test('walkers stay on the road and never step off it', () {
    final w = RoadWalkers();
    w.sync(roads, [for (var i = 0; i < 3; i++) tidelord('t$i')]);
    expect(w.walkers, hasLength(3));
    for (var i = 0; i < 2000; i++) {
      w.step(1 / 30);
      for (final r in w.walkers) {
        expect(roads.contains(roadCellKey(r.fromX, r.fromY)), isTrue);
        expect(roads.contains(roadCellKey(r.toX, r.toY)), isTrue);
        expect((r.toX - r.fromX).abs() + (r.toY - r.fromY).abs(), lessThan(2));
      }
    }
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
    w.sync(roads, [other, tidelord('t')]);
    expect(w.walkers.map((r) => r.creature.id), ['t']);
    w.dispose();
  });

  test('the count is capped by the road length and kMaxRoadWalkers', () {
    final w = RoadWalkers();
    w.sync(roads, [for (var i = 0; i < 30; i++) tidelord('t$i')]);
    // 21 road cells -> at most one walker per four cells.
    expect(w.walkers.length, 21 ~/ 4);
    expect(w.walkers.length, lessThanOrEqualTo(kMaxRoadWalkers));
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
    for (var i = 0; i < 3000; i++) {
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
