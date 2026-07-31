import 'package:flutter/material.dart';

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

  /// 1..5 flavour+risk rating; higher areas can hurt/KO expedition members
  /// (risk math lands in a later phase).
  final int dangerLevel;

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
    this.dangerLevel = 1,
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
    dangerLevel: (row['danger_level'] as num?)?.toInt() ?? 1,
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
    'danger_level': dangerLevel,
    'spots': spots.map((s) => s.toJson()).toList(),
    'species_pool': speciesPoolIds,
    'boss_species_id': bossSpeciesId,
  };
}

/// Bundled fallback areas — the starting overworld before any Dev-Mode content
/// exists (mirrors kFallbackBuildingDefs etc.). Battle stages 1/2/3 so each
/// area unlocks as the previous area's boss is cleared. Numbers are first-pass
/// placeholders to be tuned once gathering is wired.
const List<AreaDef> kFallbackAreaDefs = [
  AreaDef(
    id: 'verdant_hollow',
    name: 'Verdant Hollow',
    emoji: '🌲',
    order: 1,
    description:
        'A sheltered woodland valley — the safest place to send a first '
        'expedition. Rich in timber, light on danger.',
    battleStage: 1,
    dangerLevel: 1,
    spots: [
      ResourceSpotDef(
        id: 'vh_grove',
        resource: 'wood',
      ),
      ResourceSpotDef(
        id: 'vh_stream',
        resource: 'fish',
      ),
      // Fur in region ONE (user decision 2026-07-17): era I bills its costs
      // in fish AND fur (goodsForEra), and the Hunter Lodge is era-I content
      // — so the era's own region must offer a fur source, or fur only
      // arrives after the region-1 boss. Deliberately under Stone Reach's
      // 10/h thicket, mirroring the vh_outcrop/sr_quarry split: the Reach
      // stays THE fur region; these are snare lines on the valley edge, not
      // a hunting ground.
      ResourceSpotDef(
        id: 'vh_snares',
        resource: 'fur',
      ),
      // Stone in region ONE, though Stone Ridge (region 2) is THE stone
      // region. Without this, Era I has no stone at all outside the quarry
      // building, so its intended ~60% "actively gathered" share was
      // unreachable and the era dragged to roughly 15 days instead of 5–7.
      // Kept to under half of sr_quarry's 30/h so the Ridge is still the
      // obvious place to go for stone — this is an outcrop, not a quarry.
      ResourceSpotDef(
        id: 'vh_outcrop',
        resource: 'stone',
      ),
      // Gold from region ONE on purpose: it's the accelerator currency (sell
      // surplus → skip a wait, see gold_economy.dart), and an accelerator you
      // can't reach until region 3 accelerates nothing. Deliberately thin —
      // trading a woodpile at the Trading Post is meant to be the main way to
      // get gold, and panning it out of a creek the trickle.
      ResourceSpotDef(
        id: 'vh_placer',
        resource: 'gold',
      ),
    ],
  ),
  AreaDef(
    id: 'stone_reach',
    name: 'Stone Reach',
    emoji: '⛰️',
    order: 2,
    description:
        'Wind-scoured foothills and open quarries. Good stone, tougher '
        'wildlife — bring a fighter or two.',
    battleStage: 2,
    dangerLevel: 2,
    spots: [
      ResourceSpotDef(
        id: 'sr_quarry',
        resource: 'stone',
      ),
      ResourceSpotDef(
        id: 'sr_thicket',
        resource: 'fur',
      ),
      // Replaces sr_shrine, the ⭐/BP spot that left with the currency. Without
      // a third spot this region would offer FEWER places to work than the
      // tutorial valley next door, which reads as the map getting poorer as
      // you push on. Upland pine: real wood, but clearly under Verdant
      // Hollow's 30/h — the Hollow stays the place you go for timber.
      ResourceSpotDef(
        id: 'sr_pines',
        resource: 'wood',
      ),
    ],
  ),
  AreaDef(
    id: 'emberwastes',
    name: 'Emberwastes',
    emoji: '🌋',
    order: 3,
    description:
        'Cracked volcanic flats hiding old gold veins. Dangerous — only '
        'well-armed expeditions come back full.',
    battleStage: 3,
    dangerLevel: 3,
    spots: [
      ResourceSpotDef(
        id: 'ew_vein',
        resource: 'gold',
      ),
      ResourceSpotDef(
        id: 'ew_ridge',
        resource: 'stone',
      ),
      // Replaces ew_obelisk (the other ⭐/BP spot). Fur, and the best of it:
      // what survives on volcanic flats is worth skinning, and this region's
      // whole pitch is "dangerous, but you come back full" (dangerLevel 3 —
      // expedition_risk taxes the haul here). It has to out-yield Stone
      // Reach's thicket or the risk buys the player nothing.
      ResourceSpotDef(
        id: 'ew_ashlands',
        resource: 'fur',
      ),
    ],
  ),
];

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

/// Tint for an area card by danger level (green → red).
Color dangerColor(int dangerLevel) => switch (dangerLevel.clamp(1, 5)) {
  1 => const Color(0xFF3BAE78),
  2 => const Color(0xFF9FB43B),
  3 => const Color(0xFFE0A32E),
  4 => const Color(0xFFE2661F),
  _ => const Color(0xFF8B2020),
};
