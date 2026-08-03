// ── Era definition ────────────────────────────────────────
// Eras are the settlement's overall progression track — advancing consumes
// resources (like a building) and, unlike buildings/tech, can also grant a
// one-time resource gift plus a permanent, cumulative production bonus
// the moment you reach it. See SettlementController.advanceEra().
//
// ── They are AGES after all (user 2026-08-03) ──
// This reverses the chapter rule of 2026-07-22, knowingly and on request: "ich
// will dennoch zeitalter wählen, auch wenn dies keinen Sinn ergibt". Era I is
// the Stone Age.
//
// The tension the old rule protected against is real — a settlement crossing
// millennia while the monsters you caught on day one are still on the team —
// and naming the eras does not resolve it. What keeps it survivable is that an
// age here names a BUILDING STYLE, not a span of time: what your walls are made
// of and what the place looks like. Nothing else in the game measures years,
// and monsters still do not age (see the breeding/hatching design).
//
// So: name eras for their material and craft, never for a date or a dynasty,
// and never write elapsed time into UI copy ("centuries later", "generations
// passed"). "Ascend" stays the verb — you are still climbing, not waiting.
//
// Only era I is named this way so far (user: "wir machen nur das stone age,
// sonst noch nichts"). Eras II–VIII keep their settlement names below until
// they are done one at a time.
class EraDef {
  final String id;
  final String name;
  final String emoji;
  // 1-based, matches SettlementModel.eraIndex directly (Era I = order 1) —
  // no off-by-one translation needed anywhere this is compared against it.
  final int order;
  // Resources required to advance TO this era (paid once, like a building).
  final Map<String, double> advancementCost;
  // One-time grant applied exactly once at the moment of advancing. Every key
  // routes through ResourceModel.grant(), the same way advancementCost routes
  // through ResourceModel.deduct(). ('bp' used to be special-cased here — it
  // went to the profile rather than ResourceModel. BP no longer exists.)
  final Map<String, double> grantResources;
  // Permanent, cumulative bonuses — the vocabulary the deleted TechDef shared,
  // active for every era with order <= the settlement's current era once
  // reached (see eraBonusTotals below), summed alongside tech bonuses at
  // the GameEngine call sites in settlement_controller.dart.
  final double woodBonus;
  final double stoneBonus;
  final double foodBonus;
  final double allBonus;
  final double buildSpeedBonus;

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
  });

  // ── Dev Mode: DB row <-> EraDef ──────────────────────────
  // Same translation-layer pattern as BuildingDef.fromDefRow — see
  // building_definitions.dart for the sibling implementation. (TechDef was the
  // third; technologies are PLACES on the map now and its file is gone.)
  factory EraDef.fromDefRow(Map<String, dynamic> row) {
    double woodBonus = 0, stoneBonus = 0, foodBonus = 0, allBonus = 0;
    double buildSpeedBonus = 0;

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
// Public (not `_`-prefixed) because GameDefsController reads it directly as
// the base the DB rows are layered onto.
const kFallbackEraDefs = <String, EraDef>{
  // The starting age. Wood lashed to stone, thatch, no metal and no mortar —
  // which is exactly what era I already builds with (wood and stone raw, no
  // element; see kGoodsDefs). The name finally says out loud what the costs
  // have said all along.
  'era_1': EraDef(id: 'era_1', name: 'Stone Age', emoji: '🪨', order: 1),
  'era_2': EraDef(
    id: 'era_2',
    name: 'The Sawmill Vale',
    emoji: '🌅',
    order: 2,
    advancementCost: {'wood': 1000, 'stone': 800},
  ),
  // Eras III–VIII (user 2026-07-24). Named for what the SETTLEMENT becomes, not
  // a point in history (chapter, not century — see the note at the top). Only
  // id/name/emoji/order: the ascension TOLL is formula-based in
  // SettlementController.eraAscensionCost(order), and grants/bonuses are left
  // for Dev Mode rather than invented here — same policy as era_2 above.
  'era_3': EraDef(id: 'era_3', name: 'The Kiln Quarter', emoji: '🏺', order: 3),
  'era_4': EraDef(id: 'era_4', name: 'The Plaster Rows', emoji: '🏛️', order: 4),
  'era_5': EraDef(id: 'era_5', name: 'The Ironworks', emoji: '⚒️', order: 5),
  'era_6': EraDef(
    id: 'era_6',
    name: 'The Furnace District',
    emoji: '🏭',
    order: 6,
  ),
  'era_7': EraDef(id: 'era_7', name: 'The Glass Spires', emoji: '🔷', order: 7),
  'era_8': EraDef(
    id: 'era_8',
    name: 'The Crystal Heights',
    emoji: '💠',
    order: 8,
  ),
};

// Live, mutable roster — see the matching note above kBuildingDefs in
// building_definitions.dart.
final Map<String, EraDef> kEraDefs = Map.of(kFallbackEraDefs);

// Sum of every reached era's permanent bonus (order <= currentEraOrder) —
// This is now the ONLY source of those bonuses: it mirrored techBonusTotals
// until technologies became places on the map and tech_definitions.dart was
// deleted. Read at the GameEngine call sites in settlement_controller.dart;
// GameEngine itself never reads kEraDefs.
({double wood, double stone, double food, double all, double buildSpeed})
eraBonusTotals(int currentEraOrder) {
  double w = 0, s = 0, f = 0, a = 0, b = 0;
  for (final era in kEraDefs.values) {
    if (era.order > currentEraOrder) continue;
    w += era.woodBonus;
    s += era.stoneBonus;
    f += era.foodBonus;
    a += era.allBonus;
    b += era.buildSpeedBonus;
  }
  return (wood: w, stone: s, food: f, all: a, buildSpeed: b);
}
