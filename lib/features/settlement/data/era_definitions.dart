import '../../creatures/models/area.dart';

// ── Era definition ────────────────────────────────────────
// Eras are the settlement's overall progression track — advancing consumes
// resources (like a building) and, unlike buildings/tech, can also grant a
// one-time resource gift plus a permanent, cumulative production bonus
// the moment you reach it. See SettlementController.advanceEra().
//
// ── There is no time here, only DISTANCE (user 2026-08-03) ──
// "Es gibt nicht Äras oder Zeit, es gibt nur Fortschritt." This supersedes both
// earlier rules — the chapters of 2026-07-22 and the ages of earlier the same
// day. What a tier measures is HOW FAR YOU HAVE PUSHED, and that is a fact
// about the map, not about a calendar.
//
// The class keeps the name EraDef because renaming it would mean renaming a DB
// column that no player will ever see. Everywhere a player CAN see it, the word
// is "region", the verb is "push on", and the number is the region you have
// reached. Do not write "era", "age", "chapter" or any unit of time into UI
// copy — the whole point is that nothing in this game elapses.
//
// ── Why this dissolves the problem the other two rules only managed ──
// Both earlier rules were trying to explain why your first monster is still on
// the team after eight tiers. Distance does not need the excuse: you walked
// further, that is all. It also explains what neither could — why a later tier
// has a resource an earlier one does not. Not because it was invented later.
// Because the clay is in the hill country, and you had not reached the hill
// country yet. Every resource in the game coexists; you are simply not
// standing next to all of it yet.
//
// ── ONE name per tier, and it is the region's ──
// There used to be two: the area was "Verdant Hollow" while the same tier was
// "The Clearing". Two names for one thing is what made the tiers read as a
// separate axis running alongside the map. [displayName] resolves to the AREA
// of the same order, so the settlement header and the overworld can no longer
// disagree; [name] is only the fallback for a tier whose region is not
// authored yet.
/// The overworld region a tier corresponds to, or null when that region has
/// not been authored yet. Order is the join: region N is tier N.
AreaDef? _regionForOrder(int order) {
  for (final a in kAreaDefs.values) {
    if (a.order == order) return a;
  }
  return null;
}

class EraDef {
  final String id;

  /// The AUTHORED name. Only a fallback — read [displayName] in UI.
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

  /// What the player is told this tier is called: the REGION's name, because
  /// the tier IS the region. Falls back to [name] for a tier whose area has
  /// not been authored yet (today: orders 4–8).
  ///
  /// Read this in UI, never [name] — that is the whole guarantee that the
  /// settlement header and the overworld can no longer disagree.
  String get displayName => _regionForOrder(order)?.name ?? name;

  /// The region's glyph, same rule as [displayName].
  String get displayEmoji => _regionForOrder(order)?.emoji ?? emoji;

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
  // ── Orders 1–3 mirror the authored regions ──
  // Verdant Hollow / Stone Reach / Emberwastes (see kFallbackAreaDefs). These
  // strings are only a fallback — [displayName] reads the region itself, so
  // renaming a region renames its tier and the two cannot drift. They are kept
  // in step by hand purely so Dev Mode shows the right thing while editing.
  //
  // "Stone Age" stood here for about an hour on 2026-08-03 and is gone with the
  // ages themselves: an age is a span of time, and there is no time here.
  'era_1': EraDef(id: 'era_1', name: 'Verdant Hollow', emoji: '🌲', order: 1),
  'era_2': EraDef(
    id: 'era_2',
    name: 'Stone Reach',
    emoji: '⛰️',
    order: 2,
    advancementCost: {'wood': 1000, 'stone': 800},
  ),
  // Orders 4–8 have NO region authored yet, so these names are what the player
  // still sees. They are placeholders and they read like settlements-over-time
  // ("The Plaster Rows", "The Furnace District") — the exact thing that is being
  // undone. Replace each with a PLACE as its region is written; the tier will
  // pick the name up on its own.
  // Only id/name/emoji/order is needed: the toll is formula-based in
  // SettlementController.eraAscensionCost(order), and grants/bonuses are left
  // for Dev Mode rather than invented here.
  'era_3': EraDef(id: 'era_3', name: 'Emberwastes', emoji: '🌋', order: 3),
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
