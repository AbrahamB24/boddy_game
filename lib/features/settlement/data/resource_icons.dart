import 'package:flutter/material.dart';

import '../../creatures/models/area.dart' show kResourceEmoji;
import 'goods_definitions.dart';

// ── ONE glyph per resource (user 2026-07-30) ─────────────────
// "Zudem ist das Icon nicht das gleiche."
//
// `meat` (renamed from `fur`, user 2026-08-31) was once defined TWICE and
// differently: one glyph in kResourceEmoji (area.dart, the five gatherable
// basics) and another in kGoodsDefs (goods_definitions.dart, every good in the
// game). Both tables are legitimate — wood/stone/gold are not goods and only
// exist in the first — but each screen picked its own order, so the resource
// header showed one icon and the building card another for the same pile.
//
// This is the single lookup. GOODS WIN: kGoodsDefs is the content table that
// covers fish, meat and every later era's wares, so it decides what a good
// looks like; kResourceEmoji only fills in wood/stone/gold, which it alone
// knows.
String resourceEmoji(String id) =>
    kGoodsDefs[id]?.emoji ?? kResourceEmoji[id] ?? '📦';

/// A resource's display NAME, from the same two tables in the same order.
String resourceName(String id) =>
    kGoodsDefs[id]?.name ??
    (id.isEmpty ? id : id[0].toUpperCase() + id.substring(1));

/// A resource's ACCENT colour — the Trips screen's target cards use it as
/// their backdrop (user 2026-08-30: "die Ressource... mit den entsprechenden
/// Farben"). Thematic, not read off any def: wood, stone and gold have no
/// colour of their own anywhere else in the content, and a good's own emoji
/// doesn't imply one either. Anything not listed (a later era's raw or luxury
/// good) falls back to a neutral slate rather than erroring.
Color resourceColor(String id) => switch (id) {
  'wood' => const Color(0xFF8B5A2B),
  'stone' => const Color(0xFF7C8591),
  'gold' => const Color(0xFFD4A017),
  'fish' => const Color(0xFF2E86AB),
  'meat' => const Color(0xFFC97B3D),
  // Not goods, but the header strip's other two standing totals — same
  // treatment (user 2026-08-31: "die Icons passend einfärben").
  'energy' => const Color(0xFFD9A441),
  'housing' => const Color(0xFF5F8B6E),
  _ => const Color(0xFF8B95A5),
};
