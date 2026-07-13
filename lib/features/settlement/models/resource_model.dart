class ResourceModel {
  final String settlementId;
  final double wood;
  final double stone;
  final double gold;
  // Goods produced by buildings and consumed by population/buildings (fish, fur …)
  final Map<String, double> goods;
  final DateTime lastUpdatedAt;

  const ResourceModel({
    required this.settlementId,
    required this.wood,
    required this.stone,
    this.gold = 0,
    this.goods = const {},
    required this.lastUpdatedAt,
  });

  factory ResourceModel.fromMap(Map<String, dynamic> m) => ResourceModel(
    settlementId: m['settlement_id'] as String,
    wood: (m['wood'] as num).toDouble(),
    stone: (m['stone'] as num).toDouble(),
    gold: (m['gold'] as num?)?.toDouble() ?? 0,
    goods: {
      for (final key in ['fish', 'fur'])
        if (m[key] != null) key: (m[key] as num).toDouble(),
    },
    lastUpdatedAt: DateTime.parse(m['last_updated_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'settlement_id': settlementId,
    'wood': wood,
    'stone': stone,
    'gold': gold,
    'fish': goods['fish'] ?? 0.0,
    'fur': goods['fur'] ?? 0.0,
    'last_updated_at': lastUpdatedAt.toIso8601String(),
  };

  ResourceModel copyWith({
    double? wood,
    double? stone,
    double? gold,
    Map<String, double>? goods,
    DateTime? lastUpdatedAt,
  }) => ResourceModel(
    settlementId: settlementId,
    wood: wood ?? this.wood,
    stone: stone ?? this.stone,
    gold: gold ?? this.gold,
    goods: goods ?? this.goods,
    lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
  );

  // All resources as a flat map — used for affordability checks.
  Map<String, double> get asMap => {
    'wood': wood,
    'stone': stone,
    'gold': gold,
    ...goods,
  };

  // Deduct a cost map. 'wood', 'stone' and 'gold' deduct from their fields;
  // anything else deducts from the goods map.
  ResourceModel deduct(Map<String, double> cost) {
    final newGoods = Map<String, double>.from(goods);
    for (final e in cost.entries) {
      if (e.key == 'wood' || e.key == 'stone' || e.key == 'gold') continue;
      newGoods[e.key] = (newGoods[e.key] ?? 0) - e.value;
    }
    return copyWith(
      wood: wood - (cost['wood'] ?? 0),
      stone: stone - (cost['stone'] ?? 0),
      gold: gold - (cost['gold'] ?? 0),
      goods: newGoods,
    );
  }

  // Mirrors deduct() (same wood/stone/gold-or-goods routing) but adds
  // instead of subtracting — used for one-time era-advancement grants.
  ResourceModel grant(Map<String, double> amounts) {
    final newGoods = Map<String, double>.from(goods);
    for (final e in amounts.entries) {
      if (e.key == 'wood' || e.key == 'stone' || e.key == 'gold') continue;
      newGoods[e.key] = (newGoods[e.key] ?? 0) + e.value;
    }
    return copyWith(
      wood: wood + (amounts['wood'] ?? 0),
      stone: stone + (amounts['stone'] ?? 0),
      gold: gold + (amounts['gold'] ?? 0),
      goods: newGoods,
    );
  }
}
