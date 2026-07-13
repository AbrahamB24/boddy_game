import 'dart:math' as math;

// Procedural dungeon map, Slay-the-Spire style (decided design): layered
// path graph, free path choice at every fork, paths can re-merge, and every
// route ends at the single boss node. Node types: battle / catch / heal.
// Rewards are credited IMMEDIATELY after each cleared space, so failing (or
// abandoning) a run keeps everything earned so far — no escrow needed.
//
// Layered on top of that shape (balance-pass refinement): a PERMANENT stage
// ladder (1-9) replaces the old free tier slider. Clearing a stage's boss
// permanently unlocks the next (see SettlementController.dungeonMaxStage);
// earlier stages stay playable for farming. Stage 9's boss IS the dungeon's
// Legendary (see kLegendaryStage / DungeonMapScreen._rollBossSpecies) — only
// there does beating the boss offer a catch attempt.

const int kMaxDungeonStage = 9;
const int kLegendaryStage = kMaxDungeonStage;

/// Wild-Level(Stufe) = 5 + (Stufe-1)·8 — S1=5 .. S9=69, using the full
/// level range up to the cap once Boss-Level (+6) is added.
int wildLevelForStage(int stage) => 5 + (stage - 1) * 8;
int bossLevelForStage(int stage) => wildLevelForStage(stage) + 6;

/// Species allowed to spawn in the currently-active dungeon (encounters AND
/// bosses, excluding the stage-9 Legendary itself). `null` = every defined
/// species is eligible — the only dungeon that exists today. Future
/// multi-dungeon content sets this per-dungeon to enforce "new dungeon = new
/// monster pool, old max-level monsters can't trivialize it" (decided
/// design's anti-powercreep gating).
const List<String>? kActiveDungeonAllowedSpeciesIds = null;

enum DungeonNodeType {
  battle('Battle', '⚔️'),
  catchNode('Catch', '🪤'),
  heal('Heal', '💚'),
  boss('Boss', '👑');

  final String label;
  final String emoji;
  const DungeonNodeType(this.label, this.emoji);
}

class DungeonNode {
  final String id;

  /// 0 = first layer after the entrance; the boss sits alone on the last.
  final int layer;

  /// Horizontal slot within the layer (for drawing).
  final int index;
  final DungeonNodeType type;

  /// Ids of reachable nodes on the NEXT layer.
  final List<String> next;

  bool cleared = false;

  DungeonNode({
    required this.id,
    required this.layer,
    required this.index,
    required this.type,
    required this.next,
  });
}

class DungeonMap {
  /// Permanent progression stage (1..kMaxDungeonStage) this run is for —
  /// drives wild/boss level, entry cost and loot (see [wildLevel]/[bossLevel]
  /// below and the economy functions at the bottom of this file).
  final int stage;
  final List<DungeonNode> nodes;
  final int layerCount;

  DungeonMap({required this.stage, required this.nodes, required this.layerCount});

  int get wildLevel => wildLevelForStage(stage);
  int get bossLevel => bossLevelForStage(stage);
  bool get isLegendaryStage => stage == kLegendaryStage;

  DungeonNode byId(String id) => nodes.firstWhere((n) => n.id == id);
  List<DungeonNode> layer(int i) =>
      nodes.where((n) => n.layer == i).toList(growable: false);
  DungeonNode get boss => nodes.firstWhere((n) => n.type == DungeonNodeType.boss);

  /// Generates a run map: 5-8 path layers (decided spec) of 2-3 nodes each,
  /// plus the boss layer. Every node has ≥1 outgoing edge and every node on
  /// the next layer ≥1 incoming edge (no dead ends, everything reaches the
  /// boss). Edges only go to horizontally adjacent slots so drawn paths
  /// never cross. Type weights: battle 55% / catch 20% / heal 25%, first
  /// layer always battle, and at least one heal is guaranteed mid-run.
  factory DungeonMap.generate({required int stage, math.Random? rng}) {
    final random = rng ?? math.Random();
    final pathLayers = 5 + random.nextInt(4); // 5..8
    final nodes = <DungeonNode>[];

    // Layer sizes first, then edges between adjacent layers.
    final sizes = [for (var i = 0; i < pathLayers; i++) 2 + random.nextInt(2)];

    DungeonNodeType rollType(int layer) {
      if (layer == 0) return DungeonNodeType.battle;
      final roll = random.nextDouble();
      if (roll < 0.55) return DungeonNodeType.battle;
      if (roll < 0.75) return DungeonNodeType.catchNode;
      return DungeonNodeType.heal;
    }

    for (var l = 0; l < pathLayers; l++) {
      for (var i = 0; i < sizes[l]; i++) {
        nodes.add(
          DungeonNode(
            id: 'n${l}_$i',
            layer: l,
            index: i,
            type: rollType(l),
            next: [],
          ),
        );
      }
    }

    // Guarantee a heal room somewhere in the middle third — a run without
    // any heal would make persistent-HP dungeons brutally luck-based.
    final hasHeal = nodes.any((n) => n.type == DungeonNodeType.heal);
    if (!hasHeal) {
      final midLayer = 1 + pathLayers ~/ 3 + random.nextInt(pathLayers ~/ 3 + 1);
      final candidates = nodes.where((n) => n.layer == midLayer).toList();
      final pick = candidates[random.nextInt(candidates.length)];
      final replaced = DungeonNode(
        id: pick.id,
        layer: pick.layer,
        index: pick.index,
        type: DungeonNodeType.heal,
        next: pick.next,
      );
      nodes[nodes.indexOf(pick)] = replaced;
    }

    // Edges: connect each node of layer l to 1-2 ADJACENT slots on l+1
    // (indices within ±1 scaled by layer widths), then patch any next-layer
    // node without an incoming edge.
    for (var l = 0; l < pathLayers - 1; l++) {
      final from = nodes.where((n) => n.layer == l).toList();
      final to = nodes.where((n) => n.layer == l + 1).toList();
      for (final n in from) {
        // Map this node's slot onto the next layer's slot range.
        final ratio = to.length / from.length;
        final center = (n.index * ratio).clamp(0, to.length - 1.0);
        final lo = center.floor();
        final hi = math.min(to.length - 1, lo + 1);
        n.next.add(to[lo].id);
        if (hi != lo && random.nextBool()) n.next.add(to[hi].id);
      }
      for (final t in to) {
        final hasIncoming = from.any((n) => n.next.contains(t.id));
        if (!hasIncoming) {
          // Nearest from-node by slot ratio gets an extra edge.
          final ratio = from.length / to.length;
          final nearest = from[(t.index * ratio)
              .clamp(0, from.length - 1.0)
              .round()];
          nearest.next.add(t.id);
        }
      }
    }

    // Boss layer: single node, every last-layer node leads to it.
    final bossNode = DungeonNode(
      id: 'boss',
      layer: pathLayers,
      index: 0,
      type: DungeonNodeType.boss,
      next: const [],
    );
    for (final n in nodes.where((n) => n.layer == pathLayers - 1)) {
      n.next.add(bossNode.id);
    }
    nodes.add(bossNode);

    return DungeonMap(stage: stage, nodes: nodes, layerCount: pathLayers + 1);
  }
}

// ── Economy (all dungeon numbers in one place) ──────────────
// Keyed by the STAGE's wild level (not the raw 1-9 stage number) so the
// original cost/reward balance — tuned against creature level — still
// scales correctly now that the input is a bounded ladder instead of a free
// 5-50 slider.

/// Entry cost, scaled by the stage's wild level. Gold is THE decided gold
/// sink.
Map<String, double> dungeonEntryCost(int stage) {
  final lvl = wildLevelForStage(stage);
  return {
    'gold': 10.0 + 4.0 * lvl,
    'wood': 5.0 + 2.0 * lvl,
    'stone': 5.0 + 2.0 * lvl,
  };
}

/// Resource loot for one cleared space. Catch spaces pay a bit more (their
/// fight is harder), the boss pays roughly a whole path's worth.
Map<String, double> dungeonSpaceReward(int stage, DungeonNodeType type) {
  final lvl = wildLevelForStage(stage);
  final base = switch (type) {
    DungeonNodeType.battle => 1.0,
    DungeonNodeType.catchNode => 1.4,
    DungeonNodeType.heal => 0.0,
    DungeonNodeType.boss => 5.0,
  };
  return {
    'gold': (6.0 + 2.0 * lvl) * base,
    'wood': (4.0 + 1.5 * lvl) * base,
    'stone': (4.0 + 1.5 * lvl) * base,
  };
}
