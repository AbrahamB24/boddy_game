import 'creature_enums.dart';

/// One stat's species-level mean curve: a separate base ("Ausgangswert") per
/// evolution stage, plus ONE growth slope ("WertProLevel") shared across all
/// 3 stages (per the balance spec: evolving bumps the base/socket, the
/// growth rate itself never changes). `stageBase` is always length 3.
class StatCurve {
  final List<double> stageBase;
  final double growth;

  const StatCurve({required this.stageBase, required this.growth});

  double baseAt(int stage) => stageBase[stage.clamp(0, 2)];

  /// The species-mean evolution bonus added to an individual's own sampled
  /// base when it evolves FROM [fromStage] TO fromStage+1 — i.e. the delta
  /// between this species' stage means, not a re-roll.
  double evolutionBonus(int fromStage) =>
      baseAt(fromStage + 1) - baseAt(fromStage);

  Map<String, dynamic> toJson() => {'stage_base': stageBase, 'growth': growth};

  factory StatCurve.fromJson(Map<String, dynamic> j) {
    final raw = (j['stage_base'] as List?) ?? const [];
    final stages = raw.map((v) => (v as num).toDouble()).toList();
    while (stages.length < 3) {
      stages.add(stages.isEmpty ? 10.0 : stages.last);
    }
    return StatCurve(
      stageBase: stages,
      growth: (j['growth'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// One of the 3 evolution stages: its display name and uploaded PNG.
class SpeciesStage {
  final String name;
  final String? imageUrl;
  const SpeciesStage({required this.name, this.imageUrl});

  Map<String, dynamic> toJson() => {'name': name, 'image_url': imageUrl};

  factory SpeciesStage.fromJson(Map<String, dynamic> j) => SpeciesStage(
    name: j['name'] as String? ?? '',
    imageUrl: j['image_url'] as String?,
  );
}

/// A species' fixed ability (referencing kAbilityDefs) and the STAGE it
/// becomes usable in combat (0 = known from stage 1, 1 = gained on first
/// evolution, 2 = gained on second) — abilities accumulate, never replaced.
class SpeciesAbility {
  final String abilityId;
  final int unlockStage;
  const SpeciesAbility({required this.abilityId, this.unlockStage = 0});

  Map<String, dynamic> toJson() => {
    'id': abilityId,
    'unlock_stage': unlockStage,
  };

  factory SpeciesAbility.fromJson(Map<String, dynamic> j) => SpeciesAbility(
    abilityId: j['id'] as String,
    unlockStage: (j['unlock_stage'] as num?)?.toInt() ?? 0,
  );
}

// One collectable species: element, rarity, per-stat curves (3-stage base +
// shared growth), fixed per-species evolution levels, 3 evolution stages
// and its fixed ability set. Dev-mode-editable, stored in the species_defs
// table (same trusted-single-author model as building_defs).
class SpeciesDef {
  final String id;

  /// Species display name in lists (stage names are what shows in battle).
  final String name;
  final String description;
  final CreatureElement element;
  final CreatureRarity rarity;

  /// "Rolle" tag from the balance doc (e.g. "Glaskanone", "Tank") — flavor
  /// text only, no mechanical effect.
  final String role;

  /// Species-specific catch modifier on top of rarity.catchFactor (1.0 =
  /// normal; below 1 = extra hard). Kept separate so a "common but slippery"
  /// species is possible.
  final double catchRate;

  /// Levels at which stage 0->1 and 1->2 evolutions unlock — per-species
  /// (the balance doc fixes these individually, e.g. Flammkitz 23/48,
  /// Dornwald 30/55), replacing the old global 15/30.
  final int evoLevel1;
  final int evoLevel2;

  final Map<CreatureStat, StatCurve> stats;

  /// Always length 3 (base, evo 1, evo 2) — padded on load if the row has
  /// fewer entries so no consumer ever needs to bounds-check.
  final List<SpeciesStage> stages;

  final List<SpeciesAbility> abilities;

  const SpeciesDef({
    required this.id,
    required this.name,
    this.description = '',
    required this.element,
    required this.rarity,
    this.role = '',
    this.catchRate = 1.0,
    this.evoLevel1 = 25,
    this.evoLevel2 = 50,
    required this.stats,
    required this.stages,
    this.abilities = const [],
  });

  StatCurve statCurve(CreatureStat stat) =>
      stats[stat] ?? const StatCurve(stageBase: [10, 10, 10], growth: 1.0);

  SpeciesStage stageAt(int stage) => stages[stage.clamp(0, stages.length - 1)];

  /// Evolution level required to advance FROM [stage] (0 or 1).
  int evoLevelFrom(int stage) => stage == 0 ? evoLevel1 : evoLevel2;

  /// Abilities known at [stage] (accumulated — everything unlocked at this
  /// stage or earlier).
  List<SpeciesAbility> abilitiesAt(int stage) =>
      abilities.where((a) => a.unlockStage <= stage).toList();

  factory SpeciesDef.fromDefRow(Map<String, dynamic> row) {
    final statsJson = (row['stats'] as Map?) ?? const {};
    final stagesJson = (row['stages'] as List?) ?? const [];
    final abilitiesJson = (row['abilities'] as List?) ?? const [];

    final stages = stagesJson
        .map((s) => SpeciesStage.fromJson((s as Map).cast<String, dynamic>()))
        .toList();
    // Guarantee 3 stages so stage indexing is always safe.
    while (stages.length < 3) {
      stages.add(SpeciesStage(name: row['name'] as String? ?? ''));
    }

    return SpeciesDef(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      element: CreatureElement.fromName(row['element'] as String?),
      rarity: CreatureRarity.fromName(row['rarity'] as String?),
      role: row['role'] as String? ?? '',
      catchRate: (row['catch_rate'] as num?)?.toDouble() ?? 1.0,
      evoLevel1: (row['evo_level_1'] as num?)?.toInt() ?? 25,
      evoLevel2: (row['evo_level_2'] as num?)?.toInt() ?? 50,
      stats: {
        for (final stat in CreatureStat.values)
          if (statsJson[stat.name] != null)
            stat: StatCurve.fromJson(
              (statsJson[stat.name] as Map).cast<String, dynamic>(),
            ),
      },
      stages: stages,
      abilities: abilitiesJson
          .map(
            (a) => SpeciesAbility.fromJson((a as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }

  Map<String, dynamic> toDefRow() => {
    'id': id,
    'name': name,
    'description': description,
    'element': element.name,
    'rarity': rarity.name,
    'role': role,
    'catch_rate': catchRate,
    'evo_level_1': evoLevel1,
    'evo_level_2': evoLevel2,
    'stats': {for (final e in stats.entries) e.key.name: e.value.toJson()},
    'stages': stages.map((s) => s.toJson()).toList(),
    'abilities': abilities.map((a) => a.toJson()).toList(),
  };
}

/// Live species defs, loaded from Supabase by CreatureDefsController (same
/// in-place-overwrite pattern as kBuildingDefs). Empty until dev-mode content
/// exists — no bundled fallback.
final Map<String, SpeciesDef> kSpeciesDefs = {};
