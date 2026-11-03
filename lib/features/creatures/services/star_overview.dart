import '../models/path_node.dart';
import 'overworld_layout.dart' show areaForRegion;

/// One region's share of the stars, for the overview on the map (user
/// 2026-09-28: "auf der Map braucht es eine Gesamtübersicht über die erreichten
/// Sterne").
class RegionStars {
  /// 1-based region number.
  final int region;

  /// The region's name — its area's, or "Region N" when none is authored yet.
  final String name;

  /// Stars earned here, and the most there are to earn (3 per battle).
  final int earned;
  final int max;

  /// Whether the player has got this far (regions beyond the frontier are fog:
  /// listed, but their battles are not spelled out).
  final bool reached;

  /// Every battle of the region, in order, with the best stars earned in it.
  final List<BattleStarsEntry> battles;

  const RegionStars({
    required this.region,
    required this.name,
    required this.earned,
    required this.max,
    required this.reached,
    required this.battles,
  });
}

class BattleStarsEntry {
  final int battle;
  final int stars;
  final bool isBoss;

  /// Cleared at least once (so its stars mean something even at zero — a battle
  /// cleared before stars existed has none until it is fought again).
  final bool cleared;

  const BattleStarsEntry({
    required this.battle,
    required this.stars,
    required this.isBoss,
    required this.cleared,
  });
}

/// The whole campaign's stars, region by region, in order.
///
/// [stars] is the best-per-battle record, [battlesCleared] the campaign progress
/// (which decides what is "reached" and what is "cleared").
List<RegionStars> starOverview({
  required Map<int, int> stars,
  required int battlesCleared,
}) {
  final nodes = pathNodesInOrder();
  if (nodes.isEmpty) return const [];
  final frontierRegion = regionForBattle(battlesCleared + 1);
  final byRegion = <int, List<PathNode>>{};
  for (final n in nodes) {
    byRegion.putIfAbsent(regionForBattle(n.order), () => []).add(n);
  }
  final out = <RegionStars>[];
  for (final region in byRegion.keys.toList()..sort()) {
    final list = byRegion[region]!;
    final entries = [
      for (final n in list)
        BattleStarsEntry(
          battle: n.order,
          stars: stars[n.order] ?? 0,
          isBoss: n.isBoss,
          cleared: n.order <= battlesCleared,
        ),
    ];
    out.add(
      RegionStars(
        region: region,
        name: areaForRegion(region)?.name ?? 'Region $region',
        earned: entries.fold(0, (a, e) => a + e.stars),
        max: entries.length * 3,
        reached: region <= frontierRegion,
        battles: entries,
      ),
    );
  }
  return out;
}

/// Every star earned, and every star there is, over the whole campaign.
({int earned, int max}) starTotals({
  required Map<int, int> stars,
  required int battlesCleared,
}) {
  final regions = starOverview(stars: stars, battlesCleared: battlesCleared);
  return (
    earned: regions.fold(0, (a, r) => a + r.earned),
    max: regions.fold(0, (a, r) => a + r.max),
  );
}
