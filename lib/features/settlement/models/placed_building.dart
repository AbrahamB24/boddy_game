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
    placedAt: placedAt,
  );
}
