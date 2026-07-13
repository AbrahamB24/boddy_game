// ── Tech definition ────────────────────────────────────────
// Each tech belongs to exactly one era (`eraId`) — see EraDef in
// era_definitions.dart. research_screen.dart only shows/allows researching
// the settlement's current era's tech; advancing to the next era requires
// every tech of the current era to be researched first (advanceEra() in
// settlement_controller.dart).
class TechDef {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final int bpCost;
  // Real-time seconds of research work required (worker-driven, same
  // formula shape as BuildingDef.constructionSeconds — see the calibration
  // note above kTechDefs).
  final double researchSeconds;
  final int col; // horizontal position along the strand (0-based)
  final int row; // 0–2, one of 3 visual lanes
  final List<String> prerequisites;
  // Era this tech belongs to — only techs of the settlement's current era
  // are shown/researchable (see research_screen.dart), which is what makes
  // "advance once this era's tree is done" (EraDef/advanceEra) well-defined.
  // Nullable only for defensive/legacy safety; the dev-mode form always sets it.
  final String? eraId;
  // Production bonuses (additive, same convention as BuildingDef)
  final double woodBonus;
  final double stoneBonus;
  final double foodBonus;
  final double allBonus;
  final double buildSpeedBonus; // e.g. 0.25 = 25 % faster construction
  final double
  workoutBpBonus; // additive multiplier on kBaseWorkoutBp (0.5 = +50 %)
  final int buildSlots; // extra simultaneous build sites
  final int queueSlots; // extra queue slots
  // Building unlocked by this tech (null = bonus only)
  final String? unlocksBuilding;

  const TechDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.bpCost,
    required this.researchSeconds,
    required this.col,
    required this.row,
    this.prerequisites = const [],
    this.eraId,
    this.woodBonus = 0,
    this.stoneBonus = 0,
    this.foodBonus = 0,
    this.allBonus = 0,
    this.buildSpeedBonus = 0,
    this.workoutBpBonus = 0,
    this.buildSlots = 0,
    this.queueSlots = 0,
    this.unlocksBuilding,
  });

  List<String> get effectLines {
    final lines = <String>[];
    if (woodBonus > 0) {
      lines.add('+${(woodBonus * 100).toInt()}% Wood production');
    }
    if (stoneBonus > 0) {
      lines.add('+${(stoneBonus * 100).toInt()}% Stone production');
    }
    if (foodBonus > 0) {
      lines.add('+${(foodBonus * 100).toInt()}% Goods production');
    }
    if (allBonus > 0) lines.add('+${(allBonus * 100).toInt()}% All production');
    if (buildSpeedBonus > 0) {
      lines.add('+${(buildSpeedBonus * 100).toInt()}% Build speed');
    }
    if (workoutBpBonus > 0) {
      lines.add('+${(workoutBpBonus * 100).toInt()}% Workout BP cap');
    }
    if (buildSlots > 0) {
      lines.add('+$buildSlots build slot${buildSlots > 1 ? 's' : ''}');
    }
    if (queueSlots > 0) {
      lines.add('+$queueSlots queue slot${queueSlots > 1 ? 's' : ''}');
    }
    if (unlocksBuilding != null) lines.add('Unlocks building');
    return lines;
  }

  // ── Dev Mode: DB row <-> TechDef ─────────────────────────────
  // `col`/`row` are never stored in the DB — they're computed from
  // `prerequisites` topology by GameDefsController and injected here. See
  // BuildingDef.fromDefRow in building_definitions.dart for the sibling
  // pattern and lib/features/settlement/services/game_defs_controller.dart
  // for the layout algorithm.
  factory TechDef.fromDefRow(
    Map<String, dynamic> dbRow, {
    required int col,
    required int row,
  }) {
    double woodBonus = 0, stoneBonus = 0, foodBonus = 0, allBonus = 0;
    double buildSpeedBonus = 0, workoutBpBonus = 0;
    int buildSlots = 0, queueSlots = 0;

    final effects = (dbRow['effects'] as List?) ?? const [];
    for (final raw in effects) {
      final e = Map<String, dynamic>.from(raw as Map);
      final type = e['type'] as String?;
      if (type == 'bonus') {
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
      } else if (type == 'slots') {
        final amount = (e['amount'] as num?)?.toInt() ?? 0;
        final target = e['target'] as String?;
        if (target == 'build') {
          buildSlots += amount;
        } else if (target == 'queue') {
          queueSlots += amount;
        }
      }
    }

    return TechDef(
      id: dbRow['id'] as String,
      name: dbRow['name'] as String,
      emoji: dbRow['emoji'] as String? ?? '',
      description: dbRow['description'] as String? ?? '',
      bpCost: (dbRow['bp_cost'] as num?)?.toInt() ?? 0,
      researchSeconds: (dbRow['research_seconds'] as num?)?.toDouble() ?? 0,
      col: col,
      row: row,
      prerequisites: ((dbRow['prerequisites'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      eraId: dbRow['era_id'] as String?,
      woodBonus: woodBonus,
      stoneBonus: stoneBonus,
      foodBonus: foodBonus,
      allBonus: allBonus,
      buildSpeedBonus: buildSpeedBonus,
      workoutBpBonus: workoutBpBonus,
      buildSlots: buildSlots,
      queueSlots: queueSlots,
      unlocksBuilding: dbRow['unlocks_building'] as String?,
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
    if (buildSlots != 0) {
      effects.add({'type': 'slots', 'target': 'build', 'amount': buildSlots});
    }
    if (queueSlots != 0) {
      effects.add({'type': 'slots', 'target': 'queue', 'amount': queueSlots});
    }

    return {
      'id': id,
      'name': name,
      'emoji': emoji,
      'description': description,
      'bp_cost': bpCost,
      'research_seconds': researchSeconds,
      'prerequisites': prerequisites,
      'era_id': eraId,
      'unlocks_building': unlocksBuilding,
      'effects': effects,
    };
  }
}

// Era I research budget is now ~1938 BP — sourced wholesale from
// Balancing/Research.xlsx (checksum row confirms the 11 new techs total
// 2300 BP; `expansion`'s two "+25 Building Tiles" entries in that sheet are
// deliberately NOT added here — see plan's flagged decision #3 — so the
// total below is 2300 minus those two, plus the pre-existing
// physical_training/expansion kept from the old tree). If new Era I techs
// are added later, ask the user how to handle the budget rather than
// picking silently.
//
// researchSeconds = bpCost * 72 — this IS the real time a tech takes now
// (research has no rate/building gate at all, see game_engine.dart's tick;
// a %-bonus from Thinker Circle etc. can only reduce it, never require it).
// tribal_knowledge is 0 BP / 0 seconds so it completes the instant it's
// started, matching its role as the natural first pick.
// Bundled fallback content — see the matching note above
// kFallbackBuildingDefs in building_definitions.dart. Public (not
// `_`-prefixed) for the same reason: GameDefsService.seedFromFallback() needs
// this exact content, not whatever the live kTechDefs map currently holds.
const kFallbackTechDefs = <String, TechDef>{
  // ── Tier 0 — root ──────────────────────────────────────────
  'tribal_knowledge': TechDef(
    id: 'tribal_knowledge',
    name: 'Tribal Knowledge',
    emoji: '🧠',
    description:
        'Create a place where knowledge is shared. Unlocks the Thinker '
        'Circle (speeds up research once built).',
    bpCost: 0,
    researchSeconds: 0,
    col: 0,
    row: 0,
    eraId: 'era_1',
    unlocksBuilding: 'thinker_circle',
  ),
  'physical_training': TechDef(
    id: 'physical_training',
    name: 'Physical Training',
    emoji: '💪',
    description:
        'Structured training programmes raise the daily workout '
        'BP cap from 200 to 300.',
    bpCost: 14,
    researchSeconds: 1008,
    col: 0,
    row: 1,
    eraId: 'era_1',
    workoutBpBonus: 0.5,
  ),
  'expansion': TechDef(
    id: 'expansion',
    name: 'Expansion',
    emoji: '🗺️',
    description:
        'Survey and clear new land. Unlocks the Building Plot '
        '(+6×6 buildable area).',
    bpCost: 24,
    researchSeconds: 1728,
    col: 0,
    row: 2,
    eraId: 'era_1',
    unlocksBuilding: 'building_plot',
  ),

  // ── Tier 1 — no prerequisites ──────────────────────────────
  'primitive_woodworking': TechDef(
    id: 'primitive_woodworking',
    name: 'Primitive Woodworking',
    emoji: '🪓',
    description:
        'Organized logging techniques and improved tools. Unlocks the '
        'Lumber Camp (2 Wood/h base + 3 Wood/h per laborer).',
    bpCost: 50,
    researchSeconds: 3600,
    col: 1,
    row: 0,
    eraId: 'era_1',
    unlocksBuilding: 'lumber_camp',
  ),
  'primitive_masonry': TechDef(
    id: 'primitive_masonry',
    name: 'Primitive Masonry',
    emoji: '🧱',
    description:
        'Better stone extraction and coordinated quarry operations. '
        'Unlocks the Large Quarry (3 Stone/h base + 3 Stone/h per laborer).',
    bpCost: 50,
    researchSeconds: 3600,
    col: 1,
    row: 1,
    eraId: 'era_1',
    unlocksBuilding: 'large_quarry',
  ),
  'fishing': TechDef(
    id: 'fishing',
    name: 'Fishing',
    emoji: '🎣',
    description:
        'Advanced fishing techniques. Unlocks the Fishing Hut '
        '(2 Fish/h base + 2 Fish/h per laborer) — Fish is needed by Huts.',
    bpCost: 100,
    researchSeconds: 7200,
    col: 1,
    row: 2,
    eraId: 'era_1',
    unlocksBuilding: 'fishing_hut',
  ),
  'hunting': TechDef(
    id: 'hunting',
    name: 'Hunting',
    emoji: '🏹',
    description:
        'Organized hunting parties. Unlocks the Hunter Lodge '
        '(1 Fur/h base + 1 Fur/h per laborer) — Fur is needed by Longhouses.',
    bpCost: 100,
    researchSeconds: 7200,
    col: 1,
    row: 3,
    eraId: 'era_1',
    unlocksBuilding: 'hunter_lodge',
  ),

  // ── Tier 2 ─────────────────────────────────────────────────
  'longhouse_construction': TechDef(
    id: 'longhouse_construction',
    name: 'Longhouse Construction',
    emoji: '🏠',
    description:
        'Larger communal homes. Unlocks the Longhouse (15 population, '
        '4 Gold/h, consumes 1 Fur/h, +20% Stone production while stocked).',
    bpCost: 150,
    researchSeconds: 10800,
    col: 2,
    row: 0,
    prerequisites: ['primitive_woodworking', 'fishing', 'hunting'],
    eraId: 'era_1',
    unlocksBuilding: 'house',
  ),
  'construction_planning': TechDef(
    id: 'construction_planning',
    name: 'Construction Planning',
    emoji: '📋',
    description:
        'Organized building practices. Unlocks the Builder Camp — adds a '
        'build queue slot, -2% build time per laborer assigned.',
    bpCost: 200,
    researchSeconds: 14400,
    col: 2,
    row: 1,
    prerequisites: ['primitive_woodworking', 'primitive_masonry'],
    eraId: 'era_1',
    unlocksBuilding: 'builder_camp',
  ),
  'exploration': TechDef(
    id: 'exploration',
    name: 'Exploration',
    emoji: '🧭',
    description:
        'Train explorers to travel beyond known territory. Unlocks the '
        'Explorer Camp.',
    bpCost: 200,
    researchSeconds: 14400,
    col: 2,
    row: 2,
    prerequisites: ['fishing', 'hunting'],
    eraId: 'era_1',
    unlocksBuilding: 'explorer_camp',
  ),
  'barter_trade': TechDef(
    id: 'barter_trade',
    name: 'Barter Trade',
    emoji: '🏪',
    description:
        'Establish trade routes with neighboring tribes. Unlocks the '
        'Trading Post.',
    bpCost: 250,
    researchSeconds: 18000,
    col: 2,
    row: 3,
    prerequisites: ['tribal_knowledge'],
    eraId: 'era_1',
    unlocksBuilding: 'trading_post',
  ),

  // ── Tier 3 ─────────────────────────────────────────────────
  'warrior_training': TechDef(
    id: 'warrior_training',
    name: 'Warrior Training',
    emoji: '⚔️',
    description: 'Structured combat training. Unlocks the Warrior Grounds.',
    bpCost: 300,
    researchSeconds: 21600,
    col: 3,
    row: 0,
    prerequisites: ['exploration'],
    eraId: 'era_1',
    unlocksBuilding: 'warrior_grounds',
  ),
  'bronze_age_preparation': TechDef(
    id: 'bronze_age_preparation',
    name: 'Bronze Age Preparation',
    emoji: '🥉',
    description:
        'Gather the knowledge and organization required to enter the '
        'Bronze Age. Capstone — completes the Era I tree.',
    bpCost: 500,
    researchSeconds: 36000,
    col: 3,
    row: 1,
    prerequisites: ['longhouse_construction', 'tribal_knowledge'],
    eraId: 'era_1',
  ),
};

// Live, mutable roster — see the matching note above kBuildingDefs in
// building_definitions.dart. Tree edges are drawn directly from each def's
// `prerequisites` (research_screen.dart's _LinePainter) rather than a
// separate edge list, so logic and visualization can never drift apart.
final Map<String, TechDef> kTechDefs = Map.of(kFallbackTechDefs);

// Sum of all tech bonuses for a set of unlocked tech IDs
({
  double wood,
  double stone,
  double food,
  double all,
  double buildSpeed,
  double workoutBp,
  int buildSlots,
  int queueSlots,
})
techBonusTotals(Set<String> unlocked) {
  double w = 0, s = 0, f = 0, a = 0, b = 0, wx = 0;
  int bs = 0, qs = 0;
  for (final id in unlocked) {
    final def = kTechDefs[id];
    if (def == null) continue;
    w += def.woodBonus;
    s += def.stoneBonus;
    f += def.foodBonus;
    a += def.allBonus;
    b += def.buildSpeedBonus;
    wx += def.workoutBpBonus;
    bs += def.buildSlots;
    qs += def.queueSlots;
  }
  return (
    wood: w,
    stone: s,
    food: f,
    all: a,
    buildSpeed: b,
    workoutBp: wx,
    buildSlots: bs,
    queueSlots: qs,
  );
}
