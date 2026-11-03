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
// — for now that is the Tidelord alone (user 2026-11-03: "mache es zunächst
// nur bei tidelord, da dies das einzige neue asset ist"). A species joins the
// moment its sheets are added there; nothing here names one.
//
// Cheap by construction: positions are worked out once per frame for at most
// [kMaxRoadWalkers] monsters, each walker repaints only its own small layer,
// and the map's depth-sorted stack is rebuilt only when a walker steps onto a
// new cell (so it slips behind the buildings in front of it), not per frame.

/// Never more walkers than this, however big the town or the collection.
const int kMaxRoadWalkers = 8;

/// Cells per second at a walk.
const double _kSpeed = 0.85;

/// How tall a walker's sprite box is, in map pixels (a cell is 64 wide).
const double kWalkerHeight = 76;

/// Where the monster stands inside a walk frame, as a fraction of the frame's
/// height from its top: the baked sheets leave open air below the body for
/// their own ground shadow, so the frame's bottom edge is not its feet.
const double _kFootInFrame = 0.75;

/// One monster on the roads.
class RoadWalker {
  final CreatureInstance creature;

  /// The cell it is leaving and the one it is heading for.
  int fromX, fromY, toX, toY;

  /// 0..1 along the way from `from` to `to`.
  double t = 0;

  /// Seconds left standing still; 0 = walking.
  double pause = 0;

  /// The last step taken, kept across a rest so it walks ON afterwards
  /// instead of picking a direction afresh (and maybe turning back).
  int lastDx = 0, lastDy = 0;

  /// The screen direction it faces ('se', 'ne', 'nw', 'sw') and whether it is
  /// walking — the only two things its picture depends on, so the picture
  /// rebuilds only when one of them changes.
  final ValueNotifier<(String, bool)> look;

  RoadWalker(this.creature, int x, int y, String heading)
    : fromX = x,
      fromY = y,
      toX = x,
      toY = y,
      look = ValueNotifier((heading, false));

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

  /// Bumped whenever a walker's [RoadWalker.drawCell] changes — the map
  /// re-sorts its standing layer on this, not every frame.
  final ValueNotifier<int> order = ValueNotifier(0);

  /// Fires every frame the walkers move.
  final ChangeNotifier pulse = _Pulse();

  final math.Random _rng = math.Random();
  Set<int>? _roads;
  String _roster = '';
  final Map<String, (int, int)> _lastCell = {};

  /// Brings the walkers in line with the current [roads] and the monsters
  /// that may walk ([candidates]). Cheap when nothing changed — it is called
  /// from the map's build.
  void sync(Set<int> roads, List<CreatureInstance> candidates) {
    final usable = [
      for (final c in candidates)
        if (_canDraw(c)) c,
    ];
    final roster = [for (final c in usable) '${c.id}:${c.speciesId}:${c.stage}']
        .join(',');
    if (identical(roads, _roads) && roster == _roster) return;
    final roadsChanged = !identical(roads, _roads);
    _roads = roads;
    _roster = roster;

    if (roads.length < 2 || usable.isEmpty) {
      if (walkers.isNotEmpty) {
        walkers.clear();
        order.value++;
      }
      return;
    }
    final want = math.min(
      kMaxRoadWalkers,
      math.min(usable.length, math.max(1, roads.length ~/ 4)),
    );
    // Keep the ones still allowed (and still standing on a road); drop the
    // rest; add newcomers on random road cells.
    final keep = {for (final c in usable.take(want)) c.id};
    walkers.removeWhere(
      (w) =>
          !keep.contains(w.creature.id) ||
          (roadsChanged &&
              (!roads.contains(roadCellKey(w.fromX, w.fromY)) ||
                  !roads.contains(roadCellKey(w.toX, w.toY)))),
    );
    final present = {for (final w in walkers) w.creature.id};
    final cells = roads.toList();
    for (final c in usable.take(want)) {
      if (present.contains(c.id)) continue;
      final k = cells[_rng.nextInt(cells.length)];
      final w = RoadWalker(
        c,
        k % kGridCols,
        k ~/ kGridCols,
        const ['se', 'ne', 'nw', 'sw'][_rng.nextInt(4)],
      );
      // Start somewhere along the way, some of them resting, so the town
      // does not set off in lockstep.
      w.pause = _rng.nextDouble() < 0.4 ? _rng.nextDouble() * 3 : 0;
      walkers.add(w);
      if (MonsterSheets.map(c.speciesId, c.stage, 'se') != null) {
        precacheMonsterWalkSheets(c.speciesId, c.stage);
      }
    }
    order.value++;
  }

  static bool _canDraw(CreatureInstance c) =>
      MonsterSheets.map(c.speciesId, c.stage, 'se') != null;

  /// Advances every walker by [dt] seconds.
  void step(double dt) {
    final roads = _roads;
    if (roads == null || walkers.isEmpty) return;
    var reorder = false;
    for (final w in walkers) {
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
      if (_lastCell[w.creature.id] != cell) {
        _lastCell[w.creature.id] = cell;
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
  static const double _boxW = kWalkerHeight * 544 / 435;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    top: 0,
    width: _boxW,
    height: kWalkerHeight,
    child: IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: walkers.pulse,
          builder: (context, child) {
            final foot = RoadWalkers.footOf(walker);
            // No shadow of our own: the walk sheets bake theirs in.
            return Transform.translate(
              offset: Offset(
                foot.dx - _boxW / 2,
                foot.dy - kWalkerHeight * _kFootInFrame,
              ),
              child: child,
            );
          },
          child: RepaintBoundary(child: _WalkerArt(walker: walker)),
        ),
      ),
    ),
  );
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
          height: kWalkerHeight,
          fill: 1,
          lift: 0,
        ),
      );
    },
  );
}
