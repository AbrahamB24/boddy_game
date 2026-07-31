import 'dart:math' as math;
import '../../settlement/data/goods_definitions.dart';
import '../../settlement/data/item_definitions.dart'
    show packId, packSizesFor;
import '../../settlement/data/building_definitions.dart'
    show kBuildingUnlockBattle;
import '../services/overworld_path.dart';
import 'area.dart';

// ── Authored overworld path (user 2026-07-25) ──────────────────────────────
// The linear map path used to be a pure FORMULA (overworld_path.dart) keyed off
// `battlesCleared`. It is becoming authored DATA: an ordered list of PathNodes,
// each a battle with its own enemies and rewards, editable in Dev Mode and
// stored in Supabase (table `path_nodes`), mirroring the AreaDef pattern.
//
// This file is Phase 1: the model + a fallback SEEDED FROM the old formula, so
// nothing changes in play until Phase 2 wires the path to read these nodes. A
// node with an empty [enemies] list means "use the formula" (backward-compat),
// so the seed carries only order/area/boss/rewards and leaves enemies empty.

/// One concrete enemy in a battle node: a chosen species at a chosen level.
class PathEnemy {
  final String speciesId;
  final int level;
  const PathEnemy({required this.speciesId, required this.level});

  factory PathEnemy.fromJson(Map<String, dynamic> j) => PathEnemy(
    speciesId: (j['speciesId'] ?? j['species_id'] ?? '') as String,
    level: (j['level'] as num?)?.toInt() ?? 1,
  );

  Map<String, dynamic> toJson() => {'speciesId': speciesId, 'level': level};
}

/// Everything CLEARING a node grants (user 2026-07-25): any resources, items,
/// building unlocks (auto-reflected in Edit Building) and territory expansions.
///
/// The FEATURE unlocks (evolution / breeding / hunts / expedition + team slots)
/// are gone (user 2026-07-26). Each of those now hangs off something visible —
/// a level, a Breeding Hut, a Scout Post — instead of an invisible id earned
/// here. Old rows carrying a `features` list simply stop being read.
class PathRewards {
  // RAW RESOURCES ARE GONE (user 2026-07-30: "«normale» Ressourcen gibt es nicht
  // mehr als Belohnungen. Diese können gelöscht werden").
  //
  // A node paid its wood out the instant the battle ended, so a reward worth 800
  // was worth 300 to a settlement whose Storehouse tops out at 500 — and the
  // difference vanished with no message. Everything material is a PACKAGE now:
  // it waits in the bag at full value until you open it, and opening it may
  // overfill the store on purpose (ItemKind.resourcePack).
  //
  // A pre-2026-07-30 row's `resources` map is simply no longer read. It is left
  // in the database rather than migrated away, so nothing is destroyed by a
  // decision that is one line to reverse.

  /// Item id → count dropped into the bag (user 2026-07-25, item Phase 3) —
  /// potions, revives, lures, and since 2026-07-30 the resource PACKAGES that
  /// replaced raw loot. The one reward that is CONSUMABLE, which is what makes
  /// it a good fit for the many regular nodes between the milestone ones.
  final Map<String, int> items;

  /// Building ids this node makes buildable.
  final List<String> buildings;

  /// How many territory-expansion points this node unlocks.
  final int expansions;

  const PathRewards({
    this.items = const {},
    this.buildings = const [],
    this.expansions = 0,
  });

  bool get isEmpty =>
      items.isEmpty &&
      buildings.isEmpty &&
      expansions == 0;

  factory PathRewards.fromJson(Map<String, dynamic> j) => PathRewards(
    // `resources` is deliberately NOT read (see above) — an old row keeps it,
    // and it grants nothing.
    // Skips 0s and negatives: a reward row that grants nothing would still show
    // up in the pre-battle briefing as a promise.
    items: {
      for (final e in ((j['items'] as Map?) ?? const {}).entries)
        if (((e.value as num?)?.toInt() ?? 0) > 0)
          e.key as String: (e.value as num).toInt(),
    },
    buildings: ((j['buildings'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    expansions: (j['expansions'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    if (items.isNotEmpty) 'items': items,
    if (buildings.isNotEmpty) 'buildings': buildings,
    if (expansions != 0) 'expansions': expansions,
  };
}

/// One battle node on the linear overworld path.
class PathNode {
  final String id;

  /// Position along the path — 1-based, ascending; also the battle number.
  final int order;
  final String name;

  /// The region this node belongs to (species pool / danger / boss legendary).
  /// Null = derive from the era the [order] falls in.
  final String? areaId;

  /// A boss node clears the region: advances the era and captures the area's
  /// legendary on first clear.
  final bool isBoss;

  /// Concrete enemies (species + level). EMPTY = fall back to the old formula
  /// (random-from-pool at the formula level) — this is what the seed uses so
  /// existing play is unchanged until an author fills real enemies in.
  final List<PathEnemy> enemies;

  final PathRewards rewards;

  const PathNode({
    required this.id,
    required this.order,
    required this.name,
    this.areaId,
    this.isBoss = false,
    this.enemies = const [],
    this.rewards = const PathRewards(),
  });

  PathNode copyWith({int? order, List<PathEnemy>? enemies}) => PathNode(
    id: id,
    order: order ?? this.order,
    name: name,
    areaId: areaId,
    isBoss: isBoss,
    // [enemies] was added for the per-era re-roll (user 2026-07-30) — the only
    // bulk edit the campaign tools make.
    enemies: enemies ?? this.enemies,
    rewards: rewards,
  );

  // ── Dev Mode: DB row <-> PathNode ────────────────────────────
  factory PathNode.fromDefRow(Map<String, dynamic> row) => PathNode(
    id: row['id'] as String,
    order: (row['node_order'] as num?)?.toInt() ?? 0,
    name: row['name'] as String? ?? '',
    areaId: row['area_id'] as String?,
    isBoss: row['is_boss'] as bool? ?? false,
    enemies: ((row['enemies'] as List?) ?? const [])
        .map((e) => PathEnemy.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    rewards: PathRewards.fromJson(
      Map<String, dynamic>.from((row['rewards'] as Map?) ?? const {}),
    ),
  );

  Map<String, dynamic> toDefRow() => {
    'id': id,
    'node_order': order,
    'name': name,
    'area_id': areaId,
    'is_boss': isBoss,
    'enemies': [for (final e in enemies) e.toJson()],
    'rewards': rewards.toJson(),
  };
}

/// Item loot the bundled path hands out, keyed by battle number (user
/// 2026-07-25, item Phase 3). Era-I only and deliberately thin: a handful of
/// potions and lures spread over the first region, so the bag is never the
/// reason a fight is lost, but the Healing Hut and the Workshop are still what
/// supply it. Tunable per node in Dev Mode → Path; this is only the seed.
///
/// Ids must exist in kItemDefs — an unknown id is skipped by [PathRewards], and
/// battle_rewards falls back to the raw id in the preview.
const Map<int, Map<String, int>> kNodeItemRewards = {
  2: {'minor_potion': 1}, // right after the Healing Hut: something to carry
  4: {'minor_potion': 2},
  7: {'catch_lure': 1}, // the first hunt is around here
  10: {'potion': 1},
  13: {'revive_charm': 1}, // the party is 3 by now — one can fall
  16: {'minor_potion': 2, 'catch_lure': 1},
  19: {'potion': 2, 'revive_charm': 1}, // the era boss: stock up for the wall
};

// ── Was ein Knoten abwirft (user 2026-07-30) ────────────────
// "Jetzt bitte die Belohnung einmal für alle Knoten verteilen, je schwieriger,
// später der Knoten, desto mehr Ressourcen gibt es."
//
// Generated rather than typed out, for the same reason the packages themselves
// are: there are five eras × 19 battles today and eight eras' worth of content
// authored, so a hand-written table would be wrong the day an era is added and
// nobody would notice. Every node can still be overridden in Dev Mode ▸ Path —
// this is the seed, exactly like the enemies and the building unlocks.
//
// ── The curve, and what it is anchored to ──
//
// TWO axes, because the request has two: "später" and "schwieriger".
//
//   WITHIN an era the share rises linearly with the battle number, so the last
//   regular fight of a region is worth about eighteen times the first. That is
//   the "later" axis, and it is steep on purpose: a region should feel like it
//   is paying out more as you get deeper into it.
//
//   ACROSS eras everything is multiplied by 1.4^(era-1) — the SAME factor the
//   building roster's costs grow by (_rosterCost in building_definitions). A
//   reward therefore keeps its purchasing power instead of quietly becoming
//   pocket change by era IV.
//
// The absolute level comes from the balancing doc (§2): era I spends roughly
// 5 000 wood on buildings and the ascension. The path through an era hands out
// about 40 % of that — a real supplement, never the main supply, which stays
// the settlement's own production plus gathering trips.
//
// THE BOSS is weighted like 2.2 regular fights and is the only node that pays
// GOLD, plus (from era II) the era's building ELEMENT: the thing you are short
// of the moment you walk into the next region.

/// Weight of the boss fight relative to a regular node's position weight.
const double _kBossWeight = 40;

/// Wood a weight-1 node pays in era I. Everything else is derived from it:
/// stone is 0.7 of it, and each era multiplies by [_kEraGrowth].
///
/// 9.5 × (the 171 weight of era I's regular fights + 40 for the boss) ≈ 2 000
/// wood over a region — about 40 % of what era I spends.
const double _kWoodPerWeight = 9.5;

/// The growth per era, matching _rosterCost's own 1.4.
const double _kEraGrowth = 1.4;

/// Rounds [units] onto the resource's package ladder: the largest rung that
/// fits, repeated as often as needed.
///
/// Returns null when even the smallest rung is too big — an early node paying
/// "0.4 of a package" gives nothing rather than rounding up into a reward the
/// curve did not intend.
MapEntry<String, int>? _asPackage(String resourceId, double units) {
  if (units <= 0) return null;
  final rungs = packSizesFor(resourceId);
  if (units < rungs.first * 0.75) return null;
  // Largest rung that divides the budget into a countable number of parcels;
  // capped at 9 so a reward stays something you can read at a glance.
  var chosen = rungs.first;
  for (final rung in rungs) {
    if (units >= rung) chosen = rung;
  }
  final count = (units / chosen).round().clamp(1, 9);
  return MapEntry(packId(resourceId, chosen), count);
}

/// The RESOURCE PACKAGES battle [battle] hands out, keyed by item id.
///
/// Everything material a node gives is a package since 2026-07-30 — see
/// [PathRewards].
Map<String, int> nodePackRewards(int battle) {
  final era = eraForBattle(battle);
  final perEra = kBattlesPerEra;
  final posInEra = battle - (era - 1) * perEra; // 1..perEra
  final boss = isBossBattle(battle);
  final weight = boss ? _kBossWeight : posInEra.toDouble();
  final scale = math.pow(_kEraGrowth, era - 1).toDouble();

  final out = <String, int>{};
  void add(MapEntry<String, int>? e) {
    if (e == null) return;
    out[e.key] = (out[e.key] ?? 0) + e.value;
  }

  // The universal build pair: every era's buildings are still paid in these.
  add(_asPackage('wood', _kWoodPerWeight * weight * scale));
  add(_asPackage('stone', _kWoodPerWeight * 0.7 * weight * scale));

  // From era II the region's own RAW is what you are short of — it is gathered
  // on this era's map spots and eaten by every building here.
  final raw = rawForEra(era);
  if (raw != null) {
    // An order of magnitude below wood: a building needs ~10 of it, not ~120.
    add(_asPackage(raw.id, _kWoodPerWeight * 0.09 * weight * scale));
  }

  // A LUXURY every fifth fight — healing and breeding bill in these, and the
  // rhythm keeps them from becoming the reward you stop reading.
  if (posInEra % 5 == 0 || boss) {
    final pool = luxuriesOfEra(era);
    final luxury = pool.isEmpty
        ? kGoodsDefs['fish']
        : pool[(battle ~/ 5) % pool.length];
    if (luxury != null) {
      // 12, not 6: the smallest luxury rung is 10, and a "reward" that rounds
      // away to nothing on every regular node would make the every-fifth rhythm
      // a lie the boss quietly covered for.
      add(_asPackage(luxury.id, 12.0 * (boss ? 3 : 1) * scale));
    }
  }

  if (boss) {
    // The only gold on the path, and the era's ELEMENT: the two things a fresh
    // region asks for before it gives you anything back.
    add(_asPackage('gold', 60.0 * math.pow(1.8, era - 1).toDouble()));
    final element = elementForEra(era);
    if (element != null) {
      add(_asPackage(element.id, _kWoodPerWeight * 0.12 * _kBossWeight * scale));
    }
  }
  return out;
}

/// The last battle the bundled path defines (user 2026-07-30: "bitte lösche alle
/// knoten ab Battle 21").
///
/// The path used to run to the end of every authored area — three regions, 57
/// battles — because it was seeded from the old formula, which had an answer for
/// any battle number. Most of that was filler nobody had designed: the same
/// generated enemies and the same generated rewards, region after region.
///
/// So the seed stops here, and everything past it is AUTHORED rather than
/// assumed. Dev Mode ▸ Pfad still appends nodes beyond this number and they
/// merge on top of the seed exactly like any other row — this is where the
/// bundled content ends, not where the path may.
const int kLastPathBattle = 20;

/// The bundled fallback path — one node per battle across every defined area
/// (era), seeded FROM the old formula (overworld_path.dart) + the current unlock
/// tables so a fresh DB plays exactly like before. Enemies are left empty on
/// purpose: Phase 2's spawn falls back to the formula for a node with no
/// authored enemies, so gameplay is identical until the author fills them in.
List<PathNode> _buildFallbackPath() {
  final nodes = <PathNode>[];
  // One era-segment per defined area, ordered by its battleStage.
  final areas = kFallbackAreaDefs.toList()
    ..sort((a, b) => a.battleStage.compareTo(b.battleStage));
  for (final area in areas) {
    final era = area.battleStage;
    final first = (era - 1) * kBattlesPerEra + 1;
    final last = era * kBattlesPerEra;
    for (var battle = first; battle <= last; battle++) {
      if (battle > kLastPathBattle) break;
      final boss = isBossBattle(battle);
      nodes.add(PathNode(
        id: 'node_$battle',
        order: battle,
        name: boss ? '${area.name} Boss' : 'Battle $battle',
        areaId: area.id,
        isBoss: boss,
        rewards: PathRewards(
          items: {
            // The consumables (potions, lures) and the RESOURCE PACKAGES that
            // replaced raw loot — both are items, so they travel together.
            ...?kNodeItemRewards[battle],
            ...nodePackRewards(battle),
          },
          buildings: [
            for (final e in kBuildingUnlockBattle.entries)
              if (e.value == battle) e.key,
          ],
        ),
      ));
    }
  }
  return nodes;
}

/// Bundled fallback path nodes, keyed by id (mirrors kFallbackBuildingDefs).
final Map<String, PathNode> kFallbackPathNodes = {
  for (final n in _buildFallbackPath()) n.id: n,
};

/// Live, mutable path — GameDefsController layers Supabase `path_nodes` rows
/// onto this per id (mirrors kBuildingDefs / kAreaDefs).
final Map<String, PathNode> kPathNodes = Map.of(kFallbackPathNodes);

/// The path in play order (by [PathNode.order]).
List<PathNode> pathNodesInOrder() =>
    kPathNodes.values.toList()..sort((a, b) => a.order.compareTo(b.order));

/// The node at battle position [order] (1-based), or null.
PathNode? pathNodeAtOrder(int order) {
  for (final n in kPathNodes.values) {
    if (n.order == order) return n;
  }
  return null;
}

/// The battle number at which [buildingId] becomes buildable: the earliest
/// authored node whose rewards grant it, and NOTHING else (user 2026-07-26 —
/// "nur diese Gebäude, welche ich als Belohnung anwähle, gibt es auch als
/// Belohnung").
///
/// This used to fall back to the [kBuildingUnlockBattle] table when no node
/// granted the building, which made the two disagree in the one case that
/// matters: untick the Trade Center on node 11 and the editor showed no reward
/// while the game still locked it behind battle 11. That table is a SEED for
/// [_buildFallbackPath] now — the live path is the only authority.
///
/// 0 = "as soon as its era is reached", which stays the answer for a building
/// no node hands out. A building that is not a reward is simply not gated by
/// the path; it is never made unreachable.
int pathBuildingUnlockBattle(String buildingId) {
  int? best;
  for (final n in kPathNodes.values) {
    if (n.rewards.buildings.contains(buildingId) &&
        (best == null || n.order < best)) {
      best = n.order;
    }
  }
  return best ?? 0;
}

// pathFeatureUnlocks() is gone with PathRewards.features (user 2026-07-26).

/// The ITEM loot of every node newly cleared by going from [fromCleared] to
/// [toCleared] (exclusive → inclusive), summed per item.
///
/// A delta rather than a running total because loot is CONSUMABLE: unlike a
/// building or a feature, "what you should own by now" can't be recomputed from
/// the progress counter, so it has to be paid out exactly once, at the step that
/// earned it. See SettlementController.advanceBattlesCleared.
///
/// This is the ONLY material reward a node pays since 2026-07-30 — resource
/// packages come through here like any other item.
Map<String, int> pathItemLoot(int fromCleared, int toCleared) {
  final out = <String, int>{};
  for (final n in kPathNodes.values) {
    if (n.order <= fromCleared || n.order > toCleared) continue;
    for (final e in n.rewards.items.entries) {
      out[e.key] = (out[e.key] ?? 0) + e.value;
    }
  }
  return out;
}

/// Total territory-expansion points granted by all cleared path nodes.
int pathExpansionsGranted(int battlesCleared) {
  var total = 0;
  for (final n in kPathNodes.values) {
    if (n.order <= battlesCleared) total += n.rewards.expansions;
  }
  return total;
}

// ── Authoring tools (Dev Mode, user 2026-07-30) ─────────────
// "die Option ein, dass ich die Monster zufällig hinzufügen kann … und ich
// möchte sehen, wie oft welches Monster in den Knoten vorkommt."
//
// Both live HERE rather than inside the two dev widgets that show them: they are
// facts about the path, they are the pair (roll, then inspect the roll), and a
// rule about content that only exists inside a build method cannot be tested.

/// How often each species appears across [nodes].
///
/// Two numbers, because they answer different questions: `total` is how much of
/// the path a species occupies, `nodes` is how widely it is spread — three
/// appearances in one node is not three nodes with one each.
Map<String, ({int total, int nodes})> pathSpeciesDistribution(
  Iterable<PathNode> nodes,
) {
  final out = <String, ({int total, int nodes})>{};
  for (final n in nodes) {
    final seenHere = <String>{};
    for (final e in n.enemies) {
      final prev = out[e.speciesId] ?? (total: 0, nodes: 0);
      out[e.speciesId] = (
        total: prev.total + 1,
        nodes: prev.nodes + (seenHere.add(e.speciesId) ? 1 : 0),
      );
    }
  }
  return out;
}

/// [total] levels handed out over [count] monsters, roughly evenly.
///
/// User 2026-07-30: "jetzt will ich nicht die level der Monster einzeln
/// eingeben, sondern den Gesamtlevel und diese werden einigermassen gleichmässig
/// auf alle Monster verteilt, auch wenn es Unterschiede geben darf (max 20%
/// Abweichung)."
///
/// A node's difficulty is ONE number — how much monster you are walking into —
/// and splitting it across three fields was three chances to get the sum wrong.
/// The spread is what makes a pack read as a pack rather than as three
/// identical clones: [jitter] is the fraction each may stray from the even
/// share, 0.2 by the author's rule.
///
/// The SUM IS EXACT. Jitter alone would drift, so the rounding remainder is
/// handed back out one level at a time, and only to monsters that can take it
/// without leaving the band — a node labelled 60 fields 60.
///
/// Level 1 is the floor. A [total] below [count] therefore cannot be honoured
/// exactly (three monsters cannot share two levels); everyone gets 1 and the
/// node is stronger than its label says, which is the only direction that does
/// not produce a level-0 monster.
List<int> spreadLevels({
  required int total,
  required int count,
  required math.Random rng,
  double jitter = 0.2,
}) {
  if (count <= 0) return const [];
  if (total <= count) return List.filled(count, 1);
  final base = total / count;
  final lo = math.max(1, (base * (1 - jitter)).floor());
  final hi = math.max(lo, (base * (1 + jitter)).ceil());
  final out = [
    for (var i = 0; i < count; i++)
      (base * (1 + (rng.nextDouble() * 2 - 1) * jitter))
          .round()
          .clamp(lo, hi),
  ];

  // Hand the remainder out (or take it back) one level at a time, skipping
  // anyone already at the edge of the band. Cycling by index keeps it fair; the
  // guard stops a total that cannot be reached inside the band from looping.
  var diff = total - out.reduce((a, b) => a + b);
  for (var pass = 0; diff != 0 && pass < count * 4; pass++) {
    final i = pass % count;
    if (diff > 0 && out[i] < hi) {
      out[i]++;
      diff--;
    } else if (diff < 0 && out[i] > lo && out[i] > 1) {
      out[i]--;
      diff++;
    }
  }
  // Whatever the band could not absorb goes on the first monster: the sum the
  // author typed is the promise, the band is the texture.
  if (diff != 0) out[0] = math.max(1, out[0] + diff);
  return out;
}

/// [count] enemies drawn from [poolIds], spread EVENLY.
///
/// Four promises, and each one is a thing the author asked to keep:
///  • EXACTLY [count] entries — the number is the author's decision, not the
///    dice's ("die Anzahl der Monster gleichbleiben, wie ich sie angegeben
///    habe").
///  • the LEVELS at [keepLevels] survive position by position, so re-rolling a
///    node does not throw away a difficulty curve somebody tuned. Positions past
///    the end reuse the last level (or 1 for an empty node).
///  • species are DISTINCT while the pool allows it — three copies of one
///    monster is a node nobody designed on purpose.
///  • the LEAST-USED species come first (user 2026-07-30: "Die Verteilung soll
///    etwa gleichmässig sein").
///
/// [usage] is how often each species is already placed — across the region being
/// rolled, or across the whole path for a single node. Uniform random is NOT
/// even: over seventeen fights it reliably leaves two monsters unused and gives
/// another five appearances, which is exactly what the distribution sheet was
/// built to show. Drawing from the least-used end instead makes the spread flat
/// by construction, and the roll stays a roll because ties are shuffled.
///
/// Pass an EMPTY map to get an unbiased draw. [usage] is not mutated; the caller
/// counts what it placed (that is what lets one call balance against the next).
List<PathEnemy> rollPathEnemies({
  required List<String> poolIds,
  required int count,
  required List<int> keepLevels,
  required math.Random rng,
  Map<String, int> usage = const {},
}) {
  if (poolIds.isEmpty || count <= 0) return const [];
  // Shuffle FIRST so equal-usage species are drawn in a random order, then sort
  // by usage — a stable sort keeps that randomness inside each usage band.
  final bag = List.of(poolIds)..shuffle(rng);
  final taken = <String, int>{...usage};
  bag.sort((a, b) => (taken[a] ?? 0).compareTo(taken[b] ?? 0));
  final fallback = keepLevels.isEmpty ? 1 : keepLevels.last;
  final out = <PathEnemy>[];
  for (var i = 0; i < count; i++) {
    // Walking the sorted bag gives distinct species until it runs out; past
    // that it wraps, which only happens when count exceeds the pool.
    final id = bag[i % bag.length];
    out.add(PathEnemy(
      speciesId: id,
      level: i < keepLevels.length ? keepLevels[i] : fallback,
    ));
  }
  return out;
}
