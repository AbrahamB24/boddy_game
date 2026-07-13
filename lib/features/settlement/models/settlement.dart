class SettlementModel {
  final String id;
  final String userId;
  final String name;
  final int eraIndex;
  final int mainBuildingLevel;
  // Only one research can run at a time (no queue) — tracked directly here
  // rather than in a separate table. Null = no research currently active.
  final String? activeResearchId;
  final double researchSecondsBuilt;
  final DateTime createdAt;

  const SettlementModel({
    required this.id,
    required this.userId,
    required this.name,
    required this.eraIndex,
    required this.mainBuildingLevel,
    this.activeResearchId,
    this.researchSecondsBuilt = 0,
    required this.createdAt,
  });

  factory SettlementModel.fromMap(Map<String, dynamic> m) => SettlementModel(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    name: m['name'] as String,
    eraIndex: (m['era_index'] as num).toInt(),
    mainBuildingLevel: (m['main_building_level'] as num).toInt(),
    // Default to "no active research" pre-migration — see project notes.
    activeResearchId: m['active_research_id'] as String?,
    researchSecondsBuilt: ((m['research_seconds_built'] as num?) ?? 0)
        .toDouble(),
    createdAt: DateTime.parse(m['created_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'era_index': eraIndex,
    'main_building_level': mainBuildingLevel,
    'active_research_id': activeResearchId,
    'research_seconds_built': researchSecondsBuilt,
  };

  SettlementModel copyWith({
    String? name,
    int? eraIndex,
    int? mainBuildingLevel,
    String? activeResearchId,
    double? researchSecondsBuilt,
  }) => SettlementModel(
    id: id,
    userId: userId,
    name: name ?? this.name,
    eraIndex: eraIndex ?? this.eraIndex,
    mainBuildingLevel: mainBuildingLevel ?? this.mainBuildingLevel,
    activeResearchId: activeResearchId ?? this.activeResearchId,
    researchSecondsBuilt: researchSecondsBuilt ?? this.researchSecondsBuilt,
    createdAt: createdAt,
  );

  // copyWith can't null out activeResearchId (its `??` can't tell "clear" from
  // "not provided") — use this when a research finishes instead.
  SettlementModel clearActiveResearch() => SettlementModel(
    id: id,
    userId: userId,
    name: name,
    eraIndex: eraIndex,
    mainBuildingLevel: mainBuildingLevel,
    createdAt: createdAt,
  );
}
