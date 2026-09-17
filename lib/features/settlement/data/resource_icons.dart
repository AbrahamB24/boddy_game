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
