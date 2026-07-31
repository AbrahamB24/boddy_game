import '../models/area.dart';

// ── What the Expeditions screen can send a group to ─────────
//
// The overworld map used to BE this list: you climbed the path and tapped a
// resource spot or a hunt node you passed. Access moved to the main screen
// (user 2026-07-25: "der Zugang zu den Expeditionen soll über den
// Hauptbildschirm sein und nicht über die Karte"), so the map is the campaign
// again — numbered battles only — and the targets need a home of their own.
//
// This file is that home, and it is deliberately pure: no widgets, no
// controller, so "which targets does a player with this much progress have"
// is answerable in a test rather than by driving a screen.

enum ExpeditionTargetKind {
  /// Mine one resource spot until the group's carry cap is full.
  gather,

  /// Hunt the area's species pool; finds are caught by hand on return.
  hunt,
}

/// One thing a group can be sent to: a specific resource spot, or an area's
/// hunt. Areas contribute every spot they define plus exactly one hunt.
class ExpeditionTarget {
  final ExpeditionTargetKind kind;
  final AreaDef area;

  /// The spot for [ExpeditionTargetKind.gather]; null for a hunt.
  final ResourceSpotDef? spot;

  const ExpeditionTarget({required this.kind, required this.area, this.spot});

  /// Stable id — a spot's own id, or one hunt per area.
  String get id => spot?.id ?? 'hunt_${area.id}';

  String get emoji => spot?.emoji ?? '🪤';

  /// Short name for a tile: the resource, or "Hunt".
  String get label => spot?.resource ?? 'Hunt';

  bool get isHunt => kind == ExpeditionTargetKind.hunt;
}

/// The areas a player who has cleared up to [dungeonMaxStage] may send trips
/// to, in map order. Unlock rides on the same gate as the map (AreaDef
/// .isUnlocked) — the screen never opens a region the campaign hasn't.
List<AreaDef> unlockedAreas(int dungeonMaxStage) =>
    areasInOrder().where((a) => a.isUnlocked(dungeonMaxStage)).toList();

/// Every target in [area]: one per resource spot, then its hunt.
///
/// The hunt comes LAST on purpose — gathering is the everyday trip, hunting the
/// occasional one, and a list that leads with the rare choice reads as if the
/// rare one were the default.
List<ExpeditionTarget> targetsIn(AreaDef area) => [
  for (final s in area.spots)
    ExpeditionTarget(kind: ExpeditionTargetKind.gather, area: area, spot: s),
  ExpeditionTarget(kind: ExpeditionTargetKind.hunt, area: area),
];

/// Every target across every unlocked area, in map order.
List<ExpeditionTarget> expeditionTargets(int dungeonMaxStage) => [
  for (final a in unlockedAreas(dungeonMaxStage)) ...targetsIn(a),
];
