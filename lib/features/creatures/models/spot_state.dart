import '../../settlement/data/gather_defs.dart';
import 'area.dart';

// Per-player depletion state of a single resource spot (row in
// resource_spot_states). Only the mutable stock + timestamp live here; how much
// a spot HOLDS and how fast it refills come from the per-resource dials
// (settlement/data/gather_defs.dart, Dev Mode → Resources). They used to sit on
// every ResourceSpotDef, i.e. once per spot per area, so "how much wood is in a
// wood spot" had a dozen different answers.
//
// Regeneration is applied lazily on read — a spot left alone slowly refills
// toward capacity.
class SpotState {
  final String spotId;
  final double stock;
  final DateTime lastUpdatedAt;

  const SpotState({
    required this.spotId,
    required this.stock,
    required this.lastUpdatedAt,
  });

  /// A spot with no saved row is treated as full.
  factory SpotState.full(ResourceSpotDef def, DateTime now) => SpotState(
    spotId: def.id,
    stock: gatherDefFor(def.resource).spotCapacity,
    lastUpdatedAt: now,
  );

  /// Stock regenerated forward to [now] against [def]'s resource dials, clamped
  /// to capacity.
  double currentStock(ResourceSpotDef def, DateTime now) {
    final dials = gatherDefFor(def.resource);
    final hours = now.difference(lastUpdatedAt).inSeconds / 3600.0;
    final regen = hours > 0 ? dials.regenPerHour * hours : 0.0;
    return (stock + regen).clamp(0.0, dials.spotCapacity);
  }

  /// A new state after [mined] units are removed at [now] (regen up to now is
  /// baked in first so mining doesn't lose accrued regeneration).
  SpotState afterMining(ResourceSpotDef def, double mined, DateTime now) {
    final current = currentStock(def, now);
    return SpotState(
      spotId: spotId,
      stock:
          (current - mined).clamp(0.0, gatherDefFor(def.resource).spotCapacity),
      lastUpdatedAt: now,
    );
  }

  factory SpotState.fromRow(Map<String, dynamic> row) => SpotState(
    spotId: row['spot_id'] as String,
    stock: (row['stock'] as num?)?.toDouble() ?? 0,
    lastUpdatedAt: DateTime.parse(row['last_updated_at'] as String).toLocal(),
  );

  Map<String, dynamic> toRow(String userId) => {
    'user_id': userId,
    'spot_id': spotId,
    'stock': stock,
    'last_updated_at': lastUpdatedAt.toUtc().toIso8601String(),
  };
}
