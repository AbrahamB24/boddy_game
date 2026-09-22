class PlacedBuilding {
  final String id;
  final String settlementId;
  final String buildingTypeId;
  final int gridX;
  final int gridY;
  final int level;
  final double constructionSecondsRequired;
  final double constructionSecondsBuilt;
  final bool isComplete;
  final bool isQueued; // waiting for an active build slot to free up

  /// PAUSED (user 2026-08-01: "ich will gebäude pausieren können").
  ///
  /// A paused building produces nothing and therefore consumes nothing — the
  /// switch you want when a refinery is eating wood faster than you can cut it
  /// and un-staffing it would cost you the posting.
  ///
  /// It keeps its workers, its level and its place. Housing and storage keep
  /// counting: those are what the building IS, not what it does, and pausing a
  /// full storehouse would spill its contents to save nothing.
  final bool isPaused;

  /// IN STORAGE (user 2026-09-22: "ich kann alle Gebäude 'zurücknehmen' und
  /// dann einzeln frei platzieren" — the FoE-style rearrange tool).
  ///
  /// A stored building keeps its id, level, workers and construction
  /// progress; it simply is not standing anywhere on the grid right now, so
  /// [gridX]/[gridY] are stale and must never be read while this is true.
  /// [GameEngine.connectedBuildingIds] skips it exactly the way it already
  /// skips an incomplete building, which is what pauses its housing/
  /// production the same way disconnecting it by road already would — no
  /// separate effect-suppression logic needed. See
  /// SettlementController.recallAllBuildings/moveBuilding.
  final bool isStored;
  final DateTime placedAt;

  const PlacedBuilding({
    required this.id,
    required this.settlementId,
    required this.buildingTypeId,
    required this.gridX,
    required this.gridY,
    required this.level,
    required this.constructionSecondsRequired,
    required this.constructionSecondsBuilt,
    required this.isComplete,
    this.isQueued = false,
    this.isPaused = false,
    this.isStored = false,
    required this.placedAt,
  });

  factory PlacedBuilding.fromMap(Map<String, dynamic> m) => PlacedBuilding(
    id: m['id'] as String,
    settlementId: m['settlement_id'] as String,
    buildingTypeId: m['building_type_id'] as String,
    gridX: (m['grid_x'] as num).toInt(),
    gridY: (m['grid_y'] as num).toInt(),
    level: (m['level'] as num).toInt(),
    constructionSecondsRequired: (m['construction_seconds_required'] as num)
        .toDouble(),
    constructionSecondsBuilt: (m['construction_seconds_built'] as num)
        .toDouble(),
    isComplete: m['is_complete'] as bool,
    isQueued: (m['is_queued'] as bool?) ?? false,
    isPaused: (m['is_paused'] as bool?) ?? false,
    isStored: (m['is_stored'] as bool?) ?? false,
    placedAt: DateTime.parse(m['placed_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'settlement_id': settlementId,
    'building_type_id': buildingTypeId,
    'grid_x': gridX,
    'grid_y': gridY,
    'level': level,
    'construction_seconds_required': constructionSecondsRequired,
    'construction_seconds_built': constructionSecondsBuilt,
    'is_complete': isComplete,
    'is_queued': isQueued,
    'is_paused': isPaused,
    'is_stored': isStored,
  };

  double get constructionProgress => constructionSecondsRequired <= 0
      ? 1.0
      : (constructionSecondsBuilt / constructionSecondsRequired).clamp(
          0.0,
          1.0,
        );

  PlacedBuilding copyWith({
    int? gridX,
    int? gridY,
    double? constructionSecondsRequired,
    double? constructionSecondsBuilt,
    bool? isComplete,
    bool? isQueued,
    bool? isPaused,
    bool? isStored,
    int? level,
  }) => PlacedBuilding(
    id: id,
    settlementId: settlementId,
    buildingTypeId: buildingTypeId,
    gridX: gridX ?? this.gridX,
    gridY: gridY ?? this.gridY,
    level: level ?? this.level,
    constructionSecondsRequired:
        constructionSecondsRequired ?? this.constructionSecondsRequired,
    constructionSecondsBuilt:
        constructionSecondsBuilt ?? this.constructionSecondsBuilt,
    isComplete: isComplete ?? this.isComplete,
    isQueued: isQueued ?? this.isQueued,
    isPaused: isPaused ?? this.isPaused,
    isStored: isStored ?? this.isStored,
    placedAt: placedAt,
  );
}
