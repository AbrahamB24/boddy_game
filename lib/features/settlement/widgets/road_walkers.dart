import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../creatures/models/creature_instance.dart';
import '../../creatures/widgets/monster_sheet.dart';
import '../data/building_definitions.dart' show kGridCols;
import '../data/iso_grid.dart';
import '../data/road_tiles.dart' show roadCellKey;

// ── Monsters walking the roads (user 2026-11-03: "lasse die Monster auf den
// Strassen laufen") ──────────────────────────────────────────────────────────
//
// The player's own monsters that are home and well stroll the road network:
// from cell to neighbouring cell, never doubling back unless the road ends,
// stopping now and then to look around, playing its real baked walk cycle in
// all four directions. ONLY species with walk sheets (MonsterSheets.map) walk
// — for now the Tidelord in all three of its stages. A species joins the
// moment its sheets are added there; nothing here names one.
//
// Never crowded (user 2026-11-03: "Es kann immer nur ein Monster je Typ in der
// Stadt herumlaufen. Diese verschwinden nach einer Zeit und ein neues kommt an
// einem anderen Ort. Bitte nicht überfüllen"):
//   * at most ONE walker per type — a type is a species at one stage, so a
//     pup, an Oceanking and an Abyssal Titan may be out together, two pups not;
//   * at most [kMaxRoadWalkers] in all, and one per [_kCellsPerWalker] road
//     cells, so a small town has one or two;
//   * each stays a while ([_kLifeMin]..[_kLifeMax] s), fades out, and after a
//     pause the next one fades in on a road cell far from everyone else and
//     from where the last one left. Types take turns when there are more of
//     them than places.
//
// Cheap by construction: positions are worked out once per frame for at most
// [kMaxRoadWalkers] monsters, each walker repaints only its own small layer,
// and the map's depth-sorted stack is rebuilt only when a walker steps onto a
// new cell (so it slips behind the buildings in front of it), arrives or
// leaves — not per frame.

/// Never more walkers than this, however big the town or the collection.
const int kMaxRoadWalkers = 3;

/// One walker per this many road cells, at most.
const int _kCellsPerWalker = 6;

/// How long one walker stays out, in seconds.
const double _kLifeMin = 25, _kLifeMax = 50;

/// The pause before the next one arrives after one left, in seconds.
const double _kGapMin = 4, _kGapMax = 10;

/// Seconds a walker takes to fade in or out.
const double _kFade = 0.8;

/// Cells per second at a walk.
const double _kSpeed = 0.85;

/// How tall a pup's sprite box is, in map pixels (a cell is 64 wide); an
/// evolution's box is its walk sheets' [MonsterSheetSet.scale] times this.
const double kWalkerHeight = 58;

/// Where the monster stands inside a walk frame, as a fraction of the frame's
/// height from its top: the baked sheets leave open air below the body for
/// their own ground shadow, so the frame's bottom edge is not its feet.
const double _kFootInFrame = 0.75;

/// The walker type of [c]: its species at its stage.
String walkerType(CreatureInstance c) => '${c.speciesId}:${c.stage}';

/// One monster on the roads.
class RoadWalker {
  final CreatureInstance creature;

  /// Unique per appearance: the same monster coming back later is a new one.
  final int serial;

  /// Its sprite box height on the map.
  final double height;

  /// The cell it is leaving and the one it is heading for.
  int fromX, fromY, toX, toY;

  /// 0..1 along the way from `from` to `to`.
  double t = 0;

  /// Seconds left standing still; 0 = walking.
  double pause = 0;

  /// Seconds out on the road so far, and seconds left before it leaves.
  double age = 0;
  double life;

  /// The last step taken, kept across a rest so it walks ON afterwards
  /// instead of picking a direction afresh (and maybe turning back).
  int lastDx = 0, lastDy = 0;

  /// The screen direction it faces ('se', 'ne', 'nw', 'sw') and whether it is
  /// walking — the only two things its picture depends on, so the picture
  /// rebuilds only when one of them changes.
  final ValueNotifier<(String, bool)> look;

  RoadWalker(
    this.creature,
    int x,
    int y,
    String heading, {
    this.serial = 0,
    this.life = _kLifeMax,
  }) : fromX = x,
       fromY = y,
       toX = x,
       toY = y,
       height =
           kWalkerHeight *
           (MonsterSheets.map(creature.speciesId, creature.stage, 'se')
                   ?.scale ??
               1),
       look = ValueNotifier((heading, false));

  String get type => walkerType(creature);

  /// Fading in as it arrives, out as it leaves.
  double get opacity =>
      math.min(1.0, math.min(age, math.max(0.0, life)) / _kFade);

  /// The continuous grid position of its feet.
  double get gx => fromX + (toX - fromX) * t;
  double get gy => fromY + (toY - fromY) * t;

  /// The cell it is sorted by among the buildings: whichever of the two it
  /// is between lies further FORWARD, so a building beside the road it has
  /// not yet passed never paints over it.
  (int, int) get drawCell =>
      (toX + toY >= fromX + fromY) ? (toX, toY) : (fromX, fromY);

  bool get moving => pause <= 0 && (toX != fromX || toY != fromY);
}

/// The walkers, their road network and their clock.
class RoadWalkers {
  final List<RoadWalker> walkers = [];

  /// Bumped whenever a walker's [RoadWalker.drawCell] changes or one comes or
  /// goes — the map re-sorts its standing layer on this, not every frame.
  final ValueNotifier<int> order = ValueNotifier(0);

  /// Fires every frame the walkers move.
  final ChangeNotifier pulse = _Pulse();

  final math.Random _rng;
  Set<int>? _roads;
  String _roster = '';
  final Map<int, (int, int)> _lastCell = {};

  /// The monsters that may walk, by type.
  Map<String, List<CreatureInstance>> _pool = {};

  /// Types waiting for their turn, the next first.
  final List<String> _queue = [];

  /// How many may be out at once in this town.
  int _want = 0;

  /// Seconds before the next one may arrive.
  double _wait = 0;

  /// Where the last one left, so the next does not pop up on the same spot.
  (int, int)? _lastGone;

  int _serial = 0;

  RoadWalkers({math.Random? random}) : _rng = random ?? math.Random();

  /// True while anyone is out or due to arrive: the map's clock runs then.
  bool get active => _want > 0;

  /// Brings the walkers in line with the current [roads] and the monsters
  /// that may walk ([candidates]). Cheap when nothing changed — it is called
  /// from the map's build.
  void sync(Set<int> roads, List<CreatureInstance> candidates) {
    final usable = [
      for (final c in candidates)
        if (_canDraw(c)) c,
    ];
    final roster = [
      for (final c in usable) '${c.id}:${c.speciesId}:${c.stage}',
    ].join(',');
    if (identical(roads, _roads) && roster == _roster) return;
    final roadsChanged = !identical(roads, _roads);
    final first = _roads == null || _want == 0;
    _roads = roads;
    _roster = roster;

    _pool = {};
    for (final c in usable) {
      _pool.putIfAbsent(walkerType(c), () => []).add(c);
    }
    // Decoded before their turn comes, so nobody fades in as a blank box.
    for (final p in _pool.values) {
      precacheMonsterWalkSheets(p.first.speciesId, p.first.stage);
    }
    _want = roads.length < 2 || _pool.isEmpty
        ? 0
        : math.min(
            kMaxRoadWalkers,
            math.min(_pool.length, math.max(1, roads.length ~/ _kCellsPerWalker)),
          );

    final before = walkers.length;
    // Drop the ones no longer allowed (gone, evolved, off a changed road).
    walkers.removeWhere(
      (w) =>
          !(_pool[w.type]?.any((c) => c.id == w.creature.id) ?? false) ||
          (roadsChanged &&
              (!roads.contains(roadCellKey(w.fromX, w.fromY)) ||
                  !roads.contains(roadCellKey(w.toX, w.toY)))),
    );
    while (walkers.length > _want) {
      walkers.removeLast();
    }
    // The queue: every type not out, in its old order, newcomers at the end.
    final out = {for (final w in walkers) w.type};
    _queue.removeWhere((t) => !_pool.containsKey(t) || out.contains(t));
    for (final t in _pool.keys) {
      if (!out.contains(t) && !_queue.contains(t)) _queue.add(t);
    }
    // Opening the town: everyone due is already out (staggered, so they do
    // not all leave together). Later, newcomers wait their turn in [step].
    if (first) {
      while (walkers.length < _want && _queue.isNotEmpty) {
        _spawn(_queue.removeAt(0), staggered: true);
      }
      _wait = _gap();
    }
    if (walkers.length != before || first) order.value++;
  }

  static bool _canDraw(CreatureInstance c) =>
      MonsterSheets.map(c.speciesId, c.stage, 'se') != null;

  double _gap() => _kGapMin + _rng.nextDouble() * (_kGapMax - _kGapMin);

  void _spawn(String type, {bool staggered = false}) {
    final roads = _roads!;
    final pool = _pool[type]!;
    final c = pool[_rng.nextInt(pool.length)];
    final (x, y) = _farCell(roads);
    final life = _kLifeMin + _rng.nextDouble() * (_kLifeMax - _kLifeMin);
    final w = RoadWalker(
      c,
      x,
      y,
      const ['se', 'ne', 'nw', 'sw'][_rng.nextInt(4)],
      serial: ++_serial,
      // The first ones out leave at different times.
      life: staggered ? life * (0.35 + 0.65 * _rng.nextDouble()) : life,
    );
    w.pause = _rng.nextDouble() < 0.4 ? _rng.nextDouble() * 3 : 0;
    walkers.add(w);
    precacheMonsterWalkSheets(c.speciesId, c.stage);
  }

  /// A road cell far from every walker and from where the last one left:
  /// the best of a dozen random picks.
  (int, int) _farCell(Set<int> roads) {
    final cells = roads.toList();
    final others = [
      for (final w in walkers) (w.fromX, w.fromY),
      ?_lastGone,
    ];
    (int, int)? best;
    var bestD = -1;
    for (var i = 0; i < 12; i++) {
      final k = cells[_rng.nextInt(cells.length)];
      final p = (k % kGridCols, k ~/ kGridCols);
      var d = 1 << 30;
      for (final o in others) {
        d = math.min(d, (o.$1 - p.$1).abs() + (o.$2 - p.$2).abs());
      }
      if (d > bestD) {
        bestD = d;
        best = p;
      }
    }
    return best!;
  }

  /// Advances every walker by [dt] seconds.
  void step(double dt) {
    final roads = _roads;
    if (roads == null || _want == 0) return;
    var reorder = false;
    for (final w in walkers) {
      w.age += dt;
      w.life -= dt;
      if (w.pause > 0) {
        w.pause -= dt;
      } else if (w.toX == w.fromX && w.toY == w.fromY) {
        _chooseNext(w, roads);
      } else {
        w.t += dt * _kSpeed;
        if (w.t >= 1) {
          w.fromX = w.toX;
          w.fromY = w.toY;
          w.t = 0;
          // Now and then it stops to look around before walking on.
          if (_rng.nextDouble() < 0.12) {
            w.pause = 1.5 + _rng.nextDouble() * 2.5;
          } else {
            _chooseNext(w, roads);
          }
        }
      }
      final look = (w.look.value.$1, w.moving);
      if (look != w.look.value) w.look.value = look;
      final cell = w.drawCell;
      if (_lastCell[w.serial] != cell) {
        _lastCell[w.serial] = cell;
        reorder = true;
      }
    }
    // Time's up: it leaves, and its type queues for another turn.
    for (final w in walkers.where((w) => w.life <= 0).toList()) {
      walkers.remove(w);
      _lastCell.remove(w.serial);
      _lastGone = (w.fromX, w.fromY);
      _queue.add(w.type);
      _wait = math.max(_wait, _gap());
      reorder = true;
    }
    // The next one arrives once the pause is over; several due ones still
    // come one at a time.
    if (walkers.length < _want && _queue.isNotEmpty) {
      _wait -= dt;
      if (_wait <= 0) {
        _spawn(_queue.removeAt(0));
        _wait = _gap() / 2;
        reorder = true;
      }
    }
    if (reorder) order.value++;
    (pulse as _Pulse).fire();
  }

  void _chooseNext(RoadWalker w, Set<int> roads) {
    // Where it came from, to avoid turning straight back.
    final backX = w.fromX - w.lastDx;
    final backY = w.fromY - w.lastDy;
    final options = <(int, int)>[];
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = w.fromX + dx, ny = w.fromY + dy;
      if (nx < 0 || ny < 0 || nx >= kGridCols) continue;
      if (roads.contains(roadCellKey(nx, ny))) options.add((nx, ny));
    }
    if (options.isEmpty) {
      // An isolated road cell: stand on it.
      w.toX = w.fromX;
      w.toY = w.fromY;
      w.pause = 2;
      return;
    }
    final forward = options.where((o) => o != (backX, backY)).toList();
    final pick = (forward.isEmpty ? options : forward)[_rng.nextInt(
      forward.isEmpty ? options.length : forward.length,
    )];
    w.toX = pick.$1;
    w.toY = pick.$2;
    w.lastDx = w.toX - w.fromX;
    w.lastDy = w.toY - w.fromY;
    w.t = 0;
    final from = gridToScreen(w.fromX + 0.5, w.fromY + 0.5);
    final to = gridToScreen(w.toX + 0.5, w.toY + 0.5);
    final heading = (to.dy > from.dy ? 's' : 'n') + (to.dx > from.dx ? 'e' : 'w');
    w.look.value = (heading, true);
  }

  /// Where [w]'s feet are on the map canvas.
  static Offset footOf(RoadWalker w) => gridToScreen(w.gx + 0.5, w.gy + 0.5);

  void dispose() {
    for (final w in walkers) {
      w.look.dispose();
    }
    order.dispose();
    pulse.dispose();
  }
}

class _Pulse extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// One walker, placed in the map's standing layer at its depth. Moves by a
/// translation of its own layer every frame; never relayouts the map.
class RoadWalkerView extends StatelessWidget {
  final RoadWalker walker;
  final RoadWalkers walkers;

  const RoadWalkerView({
    super.key,
    required this.walker,
    required this.walkers,
  });

  /// The walk frames are 544 x 435.
  static const double _aspect = 544 / 435;

  @override
  Widget build(BuildContext context) {
    final h = walker.height;
    final w = h * _aspect;
    return Positioned(
      left: 0,
      top: 0,
      width: w,
      height: h,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: walkers.pulse,
            builder: (context, child) {
              final foot = RoadWalkers.footOf(walker);
              // No shadow of our own: the walk sheets bake theirs in.
              return Transform.translate(
                offset: Offset(foot.dx - w / 2, foot.dy - h * _kFootInFrame),
                child: Opacity(opacity: walker.opacity, child: child),
              );
            },
            child: RepaintBoundary(child: _WalkerArt(walker: walker)),
          ),
        ),
      ),
    );
  }
}

class _WalkerArt extends StatelessWidget {
  final RoadWalker walker;
  const _WalkerArt({required this.walker});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<(String, bool)>(
    valueListenable: walker.look,
    builder: (context, look, _) {
      final (heading, moving) = look;
      final c = walker.creature;
      final set = MonsterSheets.map(c.speciesId, c.stage, heading);
      if (set == null) return const SizedBox.shrink();
      return Align(
        alignment: Alignment.bottomCenter,
        child: MonsterSheetPlayer(
          set: set,
          anim: moving ? 'walk' : 'idle',
          height: walker.height,
          fill: 1,
          lift: 0,
        ),
      );
    },
  );
}
