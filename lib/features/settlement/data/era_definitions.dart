// ── Era definition ────────────────────────────────────────
// Eras are the settlement's overall progression track — advancing consumes
// resources (like a building) and, unlike buildings/tech, can also grant a
// one-time resource/BP gift plus a permanent, cumulative production bonus
// the moment you reach it. See SettlementController.advanceEra().
class EraDef {
  final String id;
  final String name;
  final String emoji;
  // 1-based, matches SettlementModel.eraIndex directly (Era I = order 1) —
  // no off-by-one translation needed anywhere this is compared against it.
  final int order;
  // Resources required to advance TO this era (paid once, like a building).
  final Map<String, double> advancementCost;
  // One-time grant applied exactly once at the moment of advancing. The
  // 'bp' key is special-cased by the controller (profile BP, not a
  // ResourceModel field) — every other key routes through
  // ResourceModel.grant() the same way advancementCost routes through
  // ResourceModel.deduct().
  final Map<String, double> grantResources;
  // Permanent, cumulative bonuses — same vocabulary/targets as TechDef's,
  // active for every era with order <= the settlement's current era once
  // reached (see eraBonusTotals below), summed alongside tech bonuses at
  // the GameEngine call sites in settlement_controller.dart.
  final double woodBonus;
  final double stoneBonus;
  final double foodBonus;
  final double allBonus;
  final double buildSpeedBonus;
  final double workoutBpBonus;

  const EraDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.order,
    this.advancementCost = const {},
    this.grantResources = const {},
    this.woodBonus = 0,
    this.stoneBonus = 0,
    this.foodBonus = 0,
    this.allBonus = 0,
    this.buildSpeedBonus = 0,
    this.workoutBpBonus = 0,
  });

  // ── Dev Mode: DB row <-> EraDef ──────────────────────────
  // Same translation-layer pattern as BuildingDef/TechDef.fromDefRow — see
  // building_definitions.dart for the sibling implementation.
  factory EraDef.fromDefRow(Map<String, dynamic> row) {
    double woodBonus = 0, stoneBonus = 0, foodBonus = 0, allBonus = 0;
    double buildSpeedBonus = 0, workoutBpBonus = 0;

    final effects = (row['effects'] as List?) ?? const [];
    for (final raw in effects) {
      final e = Map<String, dynamic>.from(raw as Map);
      if (e['type'] != 'bonus') continue;
      final value = (e['value'] as num?)?.toDouble() ?? 0;
      final target = e['target'] as String?;
      if (target == 'wood') {
        woodBonus += value;
      } else if (target == 'stone') {
        stoneBonus += value;
      } else if (target == 'food') {
        foodBonus += value;
      } else if (target == 'all') {
        allBonus += value;
      } else if (target == 'buildSpeed') {
        buildSpeedBonus += value;
      } else if (target == 'workoutBp') {
        workoutBpBonus += value;
      }
    }

    return EraDef(
      id: row['id'] as String,
      name: row['name'] as String,
      emoji: row['emoji'] as String? ?? '',
      order: (row['era_order'] as num).toInt(),
      advancementCost: {
        for (final e in ((row['advancement_cost'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
      grantResources: {
        for (final e in ((row['grant_resources'] as Map?) ?? const {}).entries)
          e.key as String: (e.value as num).toDouble(),
      },
      woodBonus: woodBonus,
      stoneBonus: stoneBonus,
      foodBonus: foodBonus,
      allBonus: allBonus,
      buildSpeedBonus: buildSpeedBonus,
      workoutBpBonus: workoutBpBonus,
    );
  }

  Map<String, dynamic> toDefRow() {
    final effects = <Map<String, dynamic>>[];
    if (woodBonus != 0) {
      effects.add({'type': 'bonus', 'target': 'wood', 'value': woodBonus});
    }
    if (stoneBonus != 0) {
      effects.add({'type': 'bonus', 'target': 'stone', 'value': stoneBonus});
    }
    if (foodBonus != 0) {
      effects.add({'type': 'bonus', 'target': 'food', 'value': foodBonus});
    }
    if (allBonus != 0) {
      effects.add({'type': 'bonus', 'target': 'all', 'value': allBonus});
    }
    if (buildSpeedBonus != 0) {
      effects.add({
        'type': 'bonus',
        'target': 'buildSpeed',
        'value': buildSpeedBonus,
      });
    }
    if (workoutBpBonus != 0) {
      effects.add({
        'type': 'bonus',
        'target': 'workoutBp',
        'value': workoutBpBonus,
      });
    }

    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'era_order': order,
      'advancement_cost': advancementCost,
      'grant_resources': grantResources,
      'effects': effects,
    };
  }
}

// Bundled fallback content — see the matching note above kBuildingDefs in
// building_definitions.dart. Era I is the starting era (no advancement
// cost — the player is already in it); Era II's cost is migrated from the
// old kMainHallUpgradeCost[0]. Grants/bonuses are left empty here
// deliberately — tune them via Dev Mode rather than inventing numbers.
// Public (not `_`-prefixed) so GameDefsService.seedFromFallback() can push
// this exact content rather than whatever the live kEraDefs map currently
// holds (see that function's note for why that distinction matters).
const kFallbackEraDefs = <String, EraDef>{
  'era_1': EraDef(id: 'era_1', name: 'Era I', emoji: '🏘️', order: 1),
  'era_2': EraDef(
    id: 'era_2',
    name: 'Era II',
    emoji: '🌅',
    order: 2,
    advancementCost: {'wood': 1000, 'stone': 800},
  ),
};

// Live, mutable roster — see the matching note above kBuildingDefs in
// building_definitions.dart.
final Map<String, EraDef> kEraDefs = Map.of(kFallbackEraDefs);

// Sum of every reached era's permanent bonus (order <= currentEraOrder) —
// mirrors techBonusTotals in tech_definitions.dart. Summed together with
// that function's result at the GameEngine call sites in
// settlement_controller.dart; GameEngine itself never reads kEraDefs.
({
  double wood,
  double stone,
  double food,
  double all,
  double buildSpeed,
  double workoutBp,
})
eraBonusTotals(int currentEraOrder) {
  double w = 0, s = 0, f = 0, a = 0, b = 0, wx = 0;
  for (final era in kEraDefs.values) {
    if (era.order > currentEraOrder) continue;
    w += era.woodBonus;
    s += era.stoneBonus;
    f += era.foodBonus;
    a += era.allBonus;
    b += era.buildSpeedBonus;
    wx += era.workoutBpBonus;
  }
  return (wood: w, stone: s, food: f, all: a, buildSpeed: b, workoutBp: wx);
}
