import '../services/crafting.dart';

/// One item on (or waiting for) a bench — see migration 0030.
///
/// Deliberately tiny: an item id and the seconds banked toward it. A craft job
/// has no identity worth persisting beyond that, which is why the whole list
/// rides in one jsonb column instead of a table of its own.
class CraftJob {
  final String itemId;
  final double secondsBuilt;

  const CraftJob(this.itemId, {this.secondsBuilt = 0});

  factory CraftJob.fromJson(Map<String, dynamic> m) => CraftJob(
    m['item'] as String,
    secondsBuilt: (m['seconds'] as num?)?.toDouble() ?? 0,
  );

  Map<String, dynamic> toJson() => {'item': itemId, 'seconds': secondsBuilt};

  CraftJob withSeconds(double s) => CraftJob(itemId, secondsBuilt: s);
}

class SettlementModel {
  final String id;
  final String userId;
  final String name;
  final int eraIndex;
  final int mainBuildingLevel;

  // ── Crafting (migration 0011) ─────────────────────────────
  // Only one recipe runs at a time (no queue) — tracked directly here rather
  // than in a separate table, the same shape the old research job had. Null =
  // the Workshop is idle.
  final String? activeCraftId;

  /// Crafting-seconds accrued toward [activeCraftId]. Reset to 0 when an item
  /// lands; the recipe stays selected so an untouched Workshop keeps producing.
  final double craftSecondsBuilt;

  /// EVERY craft job, in order (migration 0030). The first `craftSlots` are on
  /// a bench and accruing; the rest are queued. Order IS the queue.
  final List<CraftJob> craftJobs;

  /// The bag: itemId → count. Never holds a 0 — see crafting.dart's removeItem.
  final Map<String, int> items;

  final DateTime createdAt;

  const SettlementModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.eraIndex,
    required this.mainBuildingLevel,
    this.activeCraftId,
    this.craftSecondsBuilt = 0,
    this.craftJobs = const [],
    this.items = const {},
    required this.createdAt,
  });

  factory SettlementModel.fromMap(Map<String, dynamic> m) => SettlementModel(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    name: m['name'] as String,
    eraIndex: (m['era_index'] as num).toInt(),
    mainBuildingLevel: (m['main_building_level'] as num).toInt(),
    // Tolerates the crafting columns not existing yet (pre-0011): an idle
    // Workshop and an empty bag, rather than failing the whole load.
    activeCraftId: m['active_craft_id'] as String?,
    craftSecondsBuilt: (m['craft_seconds_built'] as num?)?.toDouble() ?? 0,
    craftJobs: _jobsFromMap(m),
    items: inventoryFromJson(m['items'] as Map?),
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  /// The job list, folding a PRE-0030 row into it: a settlement caught
  /// mid-craft keeps the recipe it had and the seconds it had banked, instead
  /// of quietly losing both the first time it loads.
  static List<CraftJob> _jobsFromMap(Map<String, dynamic> m) {
    final raw = m['craft_jobs'];
    if (raw is List && raw.isNotEmpty) {
      return [
        for (final e in raw)
          if (e is Map) CraftJob.fromJson(Map<String, dynamic>.from(e)),
      ];
    }
    final legacy = m['active_craft_id'] as String?;
    if (legacy == null) return const [];
    return [
      CraftJob(
        legacy,
        secondsBuilt: (m['craft_seconds_built'] as num?)?.toDouble() ?? 0,
      ),
    ];
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'era_index': eraIndex,
    'main_building_level': mainBuildingLevel,
    'active_craft_id': activeCraftId,
    'craft_seconds_built': craftSecondsBuilt,
    'craft_jobs': [for (final j in craftJobs) j.toJson()],
    'items': items,
  };

  SettlementModel copyWith({
    String? name,
    int? eraIndex,
    int? mainBuildingLevel,
    double? craftSecondsBuilt,
    List<CraftJob>? craftJobs,
    Map<String, int>? items,
  }) => SettlementModel(
    id: id,
    userId: userId,
    name: name ?? this.name,
    eraIndex: eraIndex ?? this.eraIndex,
    mainBuildingLevel: mainBuildingLevel ?? this.mainBuildingLevel,
    activeCraftId: activeCraftId,
    craftSecondsBuilt: craftSecondsBuilt ?? this.craftSecondsBuilt,
    craftJobs: craftJobs ?? this.craftJobs,
    items: items ?? this.items,
    createdAt: createdAt,
  );

  /// Sets (or, with null, clears) the recipe being made, always resetting
  /// progress.
  ///
  /// Separate from copyWith because its `??` can't tell "clear it" from "not
  /// provided" — the same reason the old research job needed its own
  /// clearActiveResearch. Progress resets by design: crafting-seconds belong to
  /// a recipe, so carrying them across would let a player bank work on a cheap
  /// potion and cash it in on an expensive one.
  SettlementModel withCraft(String? craftId) => SettlementModel(
    id: id,
    userId: userId,
    name: name,
    eraIndex: eraIndex,
    mainBuildingLevel: mainBuildingLevel,
    activeCraftId: craftId,
    craftSecondsBuilt: 0,
    craftJobs: craftJobs,
    items: items,
    createdAt: createdAt,
  );
}
