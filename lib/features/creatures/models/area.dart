import '../../settlement/data/goods_definitions.dart';

// ── Overworld areas ─────────────────────────────────────────
// The overworld is a sequence of AREAS (see [[expedition-overworld-redesign]]).
// Each area is a destination for expeditions: it holds typed resource spots to
// gather from, a pool of wild species to capture, and a boss to fight. Beating
// the boss unlocks the next area.
//
// Progression rides on the EXISTING dungeon ladder to avoid a schema change:
// an area's [battleStage] is the dungeon stage its combat uses, and the area
// counts as unlocked once that stage is reached (SettlementController
// .dungeonMaxStage). Clearing an area's boss already advances that counter
// (DungeonMapScreen → unlockDungeonStage), so it also unlocks the next area.
//
// Content-side (spots/pool/boss/balance) is bundled fallback for now; a
// Dev-Mode editor + DB table come in a later phase, mirroring building/tech/
// era/species defs.

/// The gatherable resources and their icons. Every key matches a
/// ResourceModel.asMap key. Which STAT mines them is no longer a per-resource
/// question — one `gathering` stat covers every spot (2026-07-25).
///
/// 'bp' used to live here too — the profile's research currency, mined at
/// ruin/shrine spots. BP is gone (research is unlocked by winning a tech's
/// trial, nothing is spent), so its spots left with it.
/// The three resources that are NOT goods — wood, stone and gold live on
/// ResourceModel's own fields, so no other table knows what they look like.
///
/// `fish` and `fur` USED to be here as well, with `fur` as 🦊 while
/// kGoodsDefs called it 🦫 (user 2026-07-30: "Zudem ist das Icon nicht das
/// gleiche"). Two tables defining one resource is two answers to one question,
/// and each screen picked whichever it happened to consult first. Every good
/// now has exactly one definition, in kGoodsDefs; use
/// settlement/data/resource_icons.dart, which reads both in a fixed order.
const Map<String, String> kResourceEmoji = {
  'wood': '🪵',
  'stone': '🪨',
  'gold': '🪙',
};

/// One typed resource spot inside an area: WHERE a resource can be gathered.
///
/// It carries no numbers any more (user 2026-07-25). Capacity, regeneration and
/// mining speed used to sit on every single spot, so "how much wood does a wood
/// spot hold" had to be answered once per area and drifted between them. Those
/// dials live once per resource in Dev Mode → Resources now
/// (settlement/data/gather_defs.dart); a spot only says which resource is here.
///
/// Legacy `yield_per_hour` / `capacity` / `regen_per_hour` keys in stored JSON
/// are simply ignored on read.
class ResourceSpotDef {
  final String id;

  /// Resource key produced — one of kResourceEmoji's keys.
  final String resource;

  const ResourceSpotDef({required this.id, required this.resource});

  /// The spot's glyph. Reads goods first, then the three base resources — the
  /// same order settlement/data/resource_icons.dart uses, spelled out here
  /// because that file imports this one (user 2026-07-30).
  String get emoji =>
      kGoodsDefs[resource]?.emoji ?? kResourceEmoji[resource] ?? '📦';

  factory ResourceSpotDef.fromJson(Map<String, dynamic> j) => ResourceSpotDef(
    id: j['id'] as String,
    resource: j['resource'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'resource': resource};
}

class AreaDef {
  final String id;
  final String name;
  final String emoji;

  /// The battlefield's own art — a scene PNG for fights that happen here (user
  /// 2026-07-31). Null falls back to the era's painted gradient, so a region
  /// with no artwork still looks like a place rather than an empty box.
  ///
  /// Uploaded from Dev Mode ▸ Areas into the same public bucket the buildings
  /// use, under `area_<id>.png`.
  final String? imageUrl;

  /// 1-based position in the overworld sequence.
  final int order;
  final String description;

  /// Dungeon stage used for this area's combat AND its unlock gate — an area
  /// is unlocked once SettlementController.dungeonMaxStage reaches this.
  final int battleStage;

  final List<ResourceSpotDef> spots;

  /// Species ids catchable here (may reference species not yet defined in
  /// Dev Mode — callers guard on kSpeciesDefs lookups).
  final List<String> speciesPoolIds;

  /// The area boss' species id (null = use the dungeon's rolled boss).
  final String? bossSpeciesId;

  const AreaDef({
    required this.id,
    required this.name,
    required this.emoji,
    this.imageUrl,
    required this.order,
    this.description = '',
    required this.battleStage,
    this.spots = const [],
    this.speciesPoolIds = const [],
    this.bossSpeciesId,
  });

  /// Unlocked once the dungeon ladder has reached this area's battle stage.
  bool isUnlocked(int dungeonMaxStage) => battleStage <= dungeonMaxStage;

  factory AreaDef.fromDefRow(Map<String, dynamic> row) => AreaDef(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    emoji: row['emoji'] as String? ?? '🗺️',
    imageUrl: row['image_url'] as String?,
    order: (row['area_order'] as num?)?.toInt() ?? 1,
    description: row['description'] as String? ?? '',
    battleStage: (row['battle_stage'] as num?)?.toInt() ?? 1,
    spots: ((row['spots'] as List?) ?? const [])
        .map((s) => ResourceSpotDef.fromJson((s as Map).cast<String, dynamic>()))
        .toList(),
    speciesPoolIds: ((row['species_pool'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    bossSpeciesId: row['boss_species_id'] as String?,
  );

  Map<String, dynamic> toDefRow() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'image_url': imageUrl,
    'area_order': order,
    'description': description,
    'battle_stage': battleStage,
    'spots': spots.map((s) => s.toJson()).toList(),
    'species_pool': speciesPoolIds,
    'boss_species_id': bossSpeciesId,
  };
}

/// Bundled fallback areas — the starting overworld before any Dev-Mode content
/// exists (mirrors kFallbackBuildingDefs etc.). Emptied out (user 2026-09-08:
/// "verdant hallow etc kann gelöscht werden" — the three placeholder regions,
/// Verdant Hollow / Stone Reach / Emberwastes, all confirmed for removal). A
/// fresh install now has NO region until Dev Mode ▸ Areas (or its DB rows)
/// defines one — [_buildFallbackPath] and everything downstream already
/// handles an empty area list (a `for` over nothing), and the Expeditions hub
/// already has its own "No region is open yet" copy for that state.
const List<AreaDef> kFallbackAreaDefs = [];

/// Live, mutable roster (keyed by id) — same in-place pattern as kBuildingDefs.
/// Seeded from the bundled fallback; a Dev-Mode/DB source can overwrite later.
final Map<String, AreaDef> kAreaDefs = {
  for (final a in kFallbackAreaDefs) a.id: a,
};

/// Areas in overworld order.
List<AreaDef> areasInOrder() {
  final list = kAreaDefs.values.toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  return list;
}

AreaDef? areaById(String id) => kAreaDefs[id];

/// Finds a resource spot by id across every area (spot ids are globally
/// unique in the content).
ResourceSpotDef? findSpot(String spotId) {
  for (final a in kAreaDefs.values) {
    for (final s in a.spots) {
      if (s.id == spotId) return s;
    }
  }
  return null;
}
