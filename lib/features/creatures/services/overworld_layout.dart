import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset, Size;

import '../models/area.dart';
import '../models/path_node.dart';
import 'overworld_path.dart';

// ── THE overworld: ONE straight line you climb ───────────────
// (linear rebuild 2026-07-24, user: "Der Weg auf der Map ist Linear, d.h auch
// die Ressourcenspots sind in einer geraden Linie.")
//
// The map is a single vertical trail of NUMBERED BATTLES, bottom → top: battle 1
// at the foot, each fight up the line a little stronger (enemyLevelForBattle),
// the era boss capping each segment.
//
// It is battles and NOTHING ELSE. Research nodes went first (buildings unlock by
// map progress, see kBuildingUnlockBattle); resource spots and the hunt followed
// 2026-07-25, when expeditions moved to their own screen off the main nav ("der
// Zugang zu den Expeditionen soll über den Hauptbildschirm sein und nicht über
// die Karte"). One door per room: the map is the campaign, the Expeditions
// screen is the trips.
//
// Pure geometry + state, no frame needed to test; the screen draws the returned
// nodes in pathIndex order.

const double _laneX = 150; // the straight line's x — every node sits on it
const double _canvasWidth = 300;
const double _topMargin = 110; // clearance below the top bar for the boss
const double _bottomMargin = 90; // room under the first node for its label
const double _stopGap = 116; // vertical distance between consecutive stops

/// How a node reads as you climb: cleared, the one you're on, or still out of
/// reach. (`open` is gone with the spot/hunt nodes — every node is a fight now.)
enum OverworldNodeState { done, current, locked }

class OverworldNode {
  /// The node's area id, used for its species pool / boss / legendary.
  final String id;
  final String areaId;
  final String emoji;
  final String label;

  /// Position on the line.
  final Offset pos;
  final OverworldNodeState state;

  /// Order along the line, 0 = foot of the trail climbing up. The screen threads
  /// the road through the nodes in this order.
  final int pathIndex;

  /// 1-based battle number on the continuous line.
  final int battleNumber;

  /// The enemy level and how many monsters you may bring (partySizeForBattle).
  final int enemyLevel;
  final int partySize;
  final bool isBoss;

  const OverworldNode({
    required this.id,
    required this.areaId,
    required this.emoji,
    required this.label,
    required this.pos,
    required this.state,
    required this.pathIndex,
    required this.battleNumber,
    required this.enemyLevel,
    required this.partySize,
    this.isBoss = false,
  });
}

/// The area whose pool/boss/spots an [era]'s battles use. Region and era are
/// 1:1 (an area's battleStage IS its era order), so the era's area is the one
/// whose battleStage matches. Null when no content is authored that far.
AreaDef? areaForEra(int era) {
  for (final a in areasInOrder()) {
    if (a.battleStage == era) return a;
  }
  return null;
}

/// The area a specific battle number belongs to.
AreaDef? areaForBattle(int battleNumber) => areaForEra(eraForBattle(battleNumber));

/// The canvas the [nodes] need — width is fixed (one lane), height is the
/// bounding box plus a margin so the trail is never clipped.
Size overworldCanvasSize(List<OverworldNode> nodes) {
  if (nodes.isEmpty) return const Size(_canvasWidth, _topMargin + _bottomMargin);
  var maxY = 0.0;
  for (final n in nodes) {
    maxY = math.max(maxY, n.pos.dy);
  }
  return Size(_canvasWidth, maxY + _bottomMargin);
}

/// The zoom at which [canvas] covers the whole [screen] — BOTH axes (user
/// 2026-07-31: "balken links und rechts dürfen nicht sichtbar sein, daher den
/// zoom anpassen", then "oben und unten will ich die balken auch nicht sehen").
///
/// The canvas is one fixed-width lane, so on a wider phone it was drawn at 1:1
/// and centred and the bare background showed down both sides. The larger of the
/// two ratios covers whichever axis falls short; the other axis simply overflows,
/// which is what panning is for.
///
/// This is both the opening zoom AND the floor the viewer may not go below — a
/// minimum that is not the opening value would let the bars back in on the first
/// pinch. It also keeps the SCALED canvas at least as tall as the screen, which
/// is what makes the vertical clamp in the screen's centring well-formed.
///
/// Guards against a zero/absent size (the first frame, before layout) by
/// answering 1.0: no zoom rather than an infinity in the transform matrix.
double overworldFillScale(Size screen, Size canvas) {
  if (screen.width <= 0 || screen.height <= 0) return 1.0;
  if (canvas.width <= 0 || canvas.height <= 0) return 1.0;
  return math.max(screen.width / canvas.width, screen.height / canvas.height);
}

/// The 1-based era a path node belongs to — from its authored area's
/// battleStage, or the formula fallback on its order.
int _eraOfNode(PathNode n) {
  final areaId = n.areaId;
  if (areaId != null) {
    final a = kAreaDefs[areaId];
    if (a != null) return a.battleStage;
  }
  return eraForBattle(n.order);
}

/// The badge level shown for a battle node: the toughest authored enemy, or the
/// formula level when the node has no explicit enemies.
int _nodeBadgeLevel(PathNode n) {
  if (n.enemies.isEmpty) return enemyLevelForBattle(n.order);
  return n.enemies.map((e) => e.level).reduce(math.max);
}

// One "stop" on the line before it's positioned — always a battle now.
typedef _Stop = ({
  String id,
  String areaId,
  String emoji,
  String label,
  int battleNumber,
  int enemyLevel,
  bool isBoss,
});

/// Builds the linear overworld for a player who has cleared [battlesCleared]
/// battles. The line runs from battle 1 up to the boss of the era they are
/// currently working through (eras beyond that are fog — not drawn).
List<OverworldNode> buildLinearOverworld({required int battlesCleared}) {
  // Authored path (user 2026-07-25): the line is now the ORDERED list of path
  // nodes, grouped into eras by each node's area. Eras beyond the one the player
  // is currently working through stay fogged (not drawn).
  final allNodes = pathNodesInOrder();
  if (allNodes.isEmpty) return const [];

  // The frontier is the next uncleared node; its era is the furthest in view.
  PathNode? frontier;
  for (final n in allNodes) {
    if (n.order > battlesCleared) {
      frontier = n;
      break;
    }
  }
  final viewEra = _eraOfNode(frontier ?? allNodes.last);

  final stops = <_Stop>[];
  for (var era = 1; era <= viewEra; era++) {
    final area = areaForEra(era);
    final eraNodes = allNodes.where((n) => _eraOfNode(n) == era).toList();

    // The era's regular fights (all but the boss), in order, then its boss.
    stops.addAll([
      for (final n in eraNodes.where((n) => !n.isBoss))
        (
          id: n.areaId ?? area?.id ?? '',
          areaId: n.areaId ?? area?.id ?? '',
          emoji: '⚔️',
          label: n.name.isNotEmpty ? n.name : 'Battle ${n.order}',
          battleNumber: n.order,
          enemyLevel: _nodeBadgeLevel(n),
          isBoss: false,
        ),
    ]);
    for (final n in eraNodes.where((n) => n.isBoss)) {
      stops.add((
        id: n.areaId ?? area?.id ?? '',
        areaId: n.areaId ?? area?.id ?? '',
        emoji: '👑',
        label: n.name.isNotEmpty ? n.name : 'Boss ${n.order}',
        battleNumber: n.order,
        enemyLevel: _nodeBadgeLevel(n),
        isBoss: true,
      ));
    }
  }

  // Lay the stops bottom → top: stop 0 at the foot, climbing up.
  final n = stops.length;
  final nodes = <OverworldNode>[];
  for (var i = 0; i < n; i++) {
    final s = stops[i];
    final y = _topMargin + (n - 1 - i) * _stopGap;
    nodes.add(
      OverworldNode(
        id: s.id,
        areaId: s.areaId,
        emoji: s.emoji,
        label: s.label,
        pos: Offset(_laneX, y),
        state: _stateFor(s, battlesCleared),
        pathIndex: i,
        battleNumber: s.battleNumber,
        enemyLevel: s.enemyLevel,
        partySize: partySizeForBattle(s.battleNumber),
        isBoss: s.isBoss,
      ),
    );
  }
  return nodes;
}

OverworldNodeState _stateFor(_Stop s, int battlesCleared) {
  if (s.battleNumber <= battlesCleared) return OverworldNodeState.done;
  if (s.battleNumber == battlesCleared + 1) return OverworldNodeState.current;
  return OverworldNodeState.locked;
}
