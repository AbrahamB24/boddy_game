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

  /// What the settlement holds of [id], whichever table it lives in — wood,
  /// stone and gold are columns, everything else is a good.
  ///
  /// The same split [GameEngine._tickGoods] makes when it charges a refinery for
  /// its inputs, so a screen asking "is there anything to refine" and the tick
  /// that refuses to refine read the same number.
  double amountOf(String id) => switch (id) {
    'wood' => wood,
    'stone' => stone,
    'gold' => gold,
    _ => goods[id] ?? 0,
  };

  /// Goods live in a single `goods` jsonb column (migration 0006), NOT one
  /// column per good. That's what lets a later era introduce a resource
  /// without a schema change — the old shape hardcoded `fish`/`fur` here and
  /// in the DB, so "add a resource next era" meant a migration plus edits in
  /// this file. See goods_definitions.dart.
  ///
  /// Falls back to the legacy per-good columns when `goods` is absent, so a
  /// client reading a pre-migration row still sees its fish and fur.
  factory ResourceModel.fromMap(Map<String, dynamic> m) => ResourceModel(
    settlementId: m['settlement_id'] as String,
    wood: (m['wood'] as num).toDouble(),
    stone: (m['stone'] as num).toDouble(),
    gold: (m['gold'] as num?)?.toDouble() ?? 0,
    goods: _goodsFromMap(m),
    lastUpdatedAt: DateTime.parse(m['last_updated_at'] as String),
  );

  static Map<String, double> _goodsFromMap(Map<String, dynamic> m) {
    final raw = m['goods'];
    if (raw is Map) {
      return {
        for (final e in raw.entries)
          if (e.value is num) e.key as String: (e.value as num).toDouble(),
      };
    }
    // Pre-migration row: read the legacy columns.
    return {
      for (final key in const ['fish', 'fur'])
        if (m[key] is num) key: (m[key] as num).toDouble(),
    };
  }

  Map<String, dynamic> toMap() => {
    'settlement_id': settlementId,
    'wood': wood,
    'stone': stone,
    'gold': gold,
    'goods': goods,
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

  /// Everything clamped to what the settlement can actually STORE (user
  /// 2026-07-30: "ein Lager … welches alle Produktion und Luxusressourcen
  /// lagern kann" + "Produktion stoppt", capacity per resource).
  ///
  /// Clamping the RESULT is what makes "production stops" true without a second
  /// code path in the tick: work above the ceiling is never banked, so nothing
  /// is silently lost — there was never anything to lose. A resource with no
  /// entry in [caps] is unlimited, which is what keeps a half-authored roster
  /// playable instead of pinning some good to zero.
  ///
  /// It is also what TRIMS a save made before the ceilings existed (the user's
  /// choice: "auf die Grenze gekürzt"), so the number on screen is one the
  /// settlement can really hold.
  ResourceModel capped(Map<String, double> caps) {
    double clamp(String key, double v) {
      final cap = caps[key];
      return cap == null || v <= cap ? v : cap;
    }

    return copyWith(
      wood: clamp('wood', wood),
      stone: clamp('stone', stone),
      gold: clamp('gold', gold),
      goods: {
        for (final e in goods.entries) e.key: clamp(e.key, e.value),
      },
    );
  }

  /// Whether anything is sitting at its ceiling — what a "your stores are full"
  /// notice reads.
  Iterable<String> atCapacity(Map<String, double> caps) sync* {
    for (final e in asMap.entries) {
      final cap = caps[e.key];
      if (cap != null && e.value >= cap) yield e.key;
    }
  }

  // Mirrors deduct() (same wood/stone/gold-or-goods routing) but adds
  // instead of subtracting — used for one-time era-advancement grants.
  /// This model, advanced to [produced], but with PRODUCTION never pushing a
  /// resource above its ceiling (user 2026-07-30: "Werden diese eingelöst, kann
  /// das Lagermaximum überstiegen werden, aber in dieser Zeit wird nicht
  /// produziert").
  ///
  /// Replaces trimming the result with [capped]. The two look the same while
  /// nothing can exceed the ceiling — and stop being the same the moment
  /// something can: a redeemed resource pack may overfill a store deliberately,
  /// and a tick that trimmed the total would simply delete it seconds later.
  ///
  /// Per resource:
  ///  • already AT or ABOVE the ceiling → produces nothing. That is the price of
  ///    the overflow, and it is why the pack is a decision rather than free.
  ///  • below it → produces at most up to the ceiling.
  ///  • a NEGATIVE change (a refinery eating its input) always applies in full —
  ///    consumption is not production and must never be blocked by a full store.
  ResourceModel withProductionCapped(
    ResourceModel produced,
    Map<String, double> caps,
  ) {
    double allow(String key, double before, double after) {
      final delta = after - before;
      if (delta <= 0) return after;
      final cap = caps[key];
      if (cap == null) return after;
      final room = cap - before;
      if (room <= 0) return before;
      return delta <= room ? after : before + room;
    }

    final keys = {...goods.keys, ...produced.goods.keys};
    return produced.copyWith(
      wood: allow('wood', wood, produced.wood),
      stone: allow('stone', stone, produced.stone),
      gold: allow('gold', gold, produced.gold),
      goods: {
        for (final k in keys)
          k: allow(k, goods[k] ?? 0, produced.goods[k] ?? 0),
      },
    );
  }

  /// Resource ids currently sitting ABOVE their ceiling — an overflow the player
  /// created on purpose by redeeming a pack. Production of these is paused until
  /// they drain back under (see [withProductionCapped]).
  List<String> overCapacity(Map<String, double> caps) => [
    for (final e in caps.entries)
      if ((asMap[e.key] ?? 0) > e.value) e.key,
  ];

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
