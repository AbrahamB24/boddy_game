class EnergyModel {
  final String settlementId;
  final double currentEnergy;
  final DateTime lastUpdatedAt;

  const EnergyModel({
    required this.settlementId,
    required this.currentEnergy,
    required this.lastUpdatedAt,
  });

  factory EnergyModel.fromMap(Map<String, dynamic> m) => EnergyModel(
    settlementId: m['settlement_id'] as String,
    currentEnergy: (m['current_energy'] as num).toDouble(),
    lastUpdatedAt: DateTime.parse(m['last_updated_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'settlement_id': settlementId,
    'current_energy': currentEnergy,
    'last_updated_at': lastUpdatedAt.toIso8601String(),
  };

  EnergyModel copyWith({double? currentEnergy, DateTime? lastUpdatedAt}) =>
      EnergyModel(
        settlementId: settlementId,
        currentEnergy: currentEnergy ?? this.currentEnergy,
        lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      );

  // Returns 0–1 fraction of energy
  double get fraction => currentEnergy / 100.0;
}
