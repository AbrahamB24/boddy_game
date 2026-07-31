import '../../../core/ui/number_format.dart';
import '../../creatures/models/creature_enums.dart' show breedingTimeCut;
import '../services/trade_center.dart' show kMaxTradeDiscount;
import 'building_definitions.dart'
    show BuildingDef, WorkshopRole, effectiveSlots, kMaxBuildingLevel;

// What a WORKSHOP role's power actually does, in words (user 2026-07-26:
// "zeige, um wieviel Prozent das breeding beschleunigt wird, dann muss es
// nicht umgerechnet werden … dies überall so umsetzen").
//
// Only the stockpile roles produce "N units/h". The rest feed a SYSTEM: the
// same stat × mult × level figure is a cut off a duration, a cut off a price,
// or an expedition amplifier — and printing it as "+60/h 📦" (which every
// screen did) stated a number nobody could act on.
//
// One file because four readers need the same answer: the build menu, the
// upgrade sheet, the building dialog and the Dev-Mode effect preview. If a
// role's meaning changes at its call site (SettlementController.breedingPower /
// healReduction / tradeDiscount / expeditionBonuses), it changes HERE too.

// ── Output ORDER (user 2026-07-26) ──────────────────────────
// "Gold ist über housing bei effects, soll bei housing die gleiche Reihenfolge
// sein. Bitte bei allen Gebäude so übernehmen."
//
// The building dialog's current-level panel renders a production block and then
// a housing row — production first, structurally. Its upgrade panel built the
// same list by sorting the keys alphabetically, and the housing sentinel sorts
// before every letter, so one building read "Gold, Housing" above and
// "Housing, Gold" below. Both read [buildingOutputOrder] now.

/// Sentinel key for HOUSING inside an outputs map: a capacity count, not a
/// per-hour rate, so it cannot just be another resource id.
const String kHousingOutputKey = '__housing';

/// The order every panel lists a building's worker-free outputs in: production
/// keys in the order the DEF authors them, then housing last.
///
/// Authoring order rather than alphabetical on purpose — it is the order the
/// author sees in the effects editor, and it already governs the current-level
/// panel, so following it is what makes the two agree.
List<String> buildingOutputOrder(BuildingDef def, Iterable<String> keys) {
  final rest = keys.toSet();
  final ordered = <String>[];
  for (final res in def.effectKeys('production')) {
    if (rest.remove(res)) ordered.add(res);
  }
  // Defensive: a key from neither source gets a stable, predictable place
  // rather than an accidental one.
  final extra = rest.where((k) => k != kHousingOutputKey).toList()..sort();
  ordered.addAll(extra);
  if (rest.contains(kHousingOutputKey)) ordered.add(kHousingOutputKey);
  return ordered;
}

// ── What a LEVEL buys (user 2026-07-26) ─────────────────────
// "produktionsgebäude: zeige bei upgrade den Effekt, d.h plus 1 Worker
// meistens oder was das upgrade wirklich bringt."
//
// The upgrade panel listed only WORKER-FREE outputs, and a production building
// has none — everything it makes comes from the creatures posted in it. So a
// lumber camp's upgrade preview was blank, and the two numbers a level really
// moves were nowhere: how many can work here, and how much each one is worth.

/// One "now → next" line of an upgrade preview.
class UpgradeLine {
  final String label;
  final String emoji;
  final String now;
  final String next;

  /// A heading these lines sit under — "Storage" over its per-resource rows
  /// (user 2026-07-30: "«Ressource» zu «Storage» ändern, dafür überall sonst
  /// storage löschen"). Null for the lines that name themselves.
  final String? group;

  /// Print only the NEW value, not "now → next" (user 2026-07-30: "Unten nur
  /// das neue Max angeben"). For a ceiling the old number is the one on the
  /// card directly above; repeating it in every upgrade row is the same figure
  /// twice, four rows running.
  final bool onlyNext;

  const UpgradeLine({
    required this.label,
    required this.emoji,
    required this.now,
    required this.next,
    this.group,
    this.onlyNext = false,
  });

  /// Whether this level actually moves the number. A line that doesn't is
  /// still worth showing — "this upgrade does NOT add a worker" is an answer —
  /// but it must not be dressed up as a gain.
  bool get changed => now != next;
}

/// Effect types the runtime reads through `effectEntry × levelScaleExplicit` —
/// i.e. FLAT unless an explicit per-effect factor is authored.
///
/// The rest go through `effectAt(level:)`, which applies the global +50 %/level
/// curve. A preview that used one reader for all of them would quietly promise
/// growth the game does not grant.
const Set<String> kFlatEffectTypes = {
  'resource',
  'expeditionSlots',
  'caravanSlots',
  'huntOptions',
  'heal',
};

/// A [type]/[key] effect's value at building [level], read exactly the way the
/// runtime reads it.
double buildingEffectValueAt(
  BuildingDef def,
  String type,
  String key,
  int era,
  int level,
) {
  final e = def.effectEntry(type, key, era);
  if (e == null) return 0;
  if (!kFlatEffectTypes.contains(type)) return e.valueAtLevel(level);
  // Flat types still honour an explicit ladder — that is how the Scout Post
  // hands out one more hunt length at a chosen level.
  return e.levelSteps.isNotEmpty
      ? e.valueAtLevel(level)
      : e.value * e.levelScaleExplicit(level);
}

/// A per-era effect type's name, in the words the player reads.
String buildingEffectLabel(String type) => switch (type) {
  'production' => 'Production',
  'resource' => 'Production bonus',
  'expedition' => 'Expedition bonus',
  'expeditionSlots' => 'Expedition slots',
  'caravan' => 'Caravan bonus',
  'caravanSlots' => 'Caravan slots',
  'huntOptions' => 'Hunt lengths',
  'heal' => 'Healing cut',
  'healSlots' => 'Healing slots',
  'healQueue' => 'Waiting room',
  'housing' => 'Housing',
  'breeding' => 'Simultaneous matings',
  'hatching' => 'Simultaneous incubations',
  'queueSlots' => 'Queue slots',
  'buildSlots' => 'Build sites',
  'trade' => 'Trade bonus',
  'craftSlots' => 'Workbenches',
  'craftQueue' => 'Craft queue',
  'storage' => 'Storage',
  _ => type,
};

/// An effect value in ITS OWN unit — a percentage, a count, a rate.
String formatBuildingEffect(String type, String key, double v) => switch (type) {
  // Construction is the one production key that is NOT units/h.
  'production' => key == WorkshopRole.kConstruction
      ? '${_trim(v)} points'
      : '${_trim(v)}${key.isEmpty ? '' : ' $key/h'}',
  'resource' => '+${_trim(v * 100)} %',
  'expedition' || 'caravan' =>
    key == 'travel' ? '−${_trim(v * 100)} % travel' : '+${_trim(v * 100)} %',
  'heal' => '−${_trim(v * 100)} %',
  // Percentage POINTS off the spread — a reduction, so it gets the sign.
  'trade' => '−${_trim(v)} %',
  'housing' => '${v.round()} seats',
  // A ceiling is a bare figure (user 2026-07-30: "Gib nur die Zahl, ohne Max
  // und ohne Icon"). It sits under a "Storage" heading beside the resource it
  // belongs to, so "max" and a glyph would be the third and fourth way of
  // saying the same thing on one line.
  // A CEILING gets shortened (user 2026-07-30): an era-8 store holds 96 000, and
  // "96000" in a dialog next to a header reading "96k" is two renderings of one
  // number. Exact below 10 000, where the digits still tell you something.
  'storage' => shortNumberAbove(v),
  // The count-like ones the runtime rounds before using.
  _ => '${v.round()}',
};

/// The glyph an effect type wears in a preview row.
String buildingEffectEmoji(String type) => switch (type) {
  'housing' => '🏠',
  'queueSlots' => '⏳',
  'buildSlots' => '🏗',
  'expeditionSlots' => '🧭',
  'caravanSlots' => '🐫',
  'caravan' => '🐫',
  'huntOptions' => '🏕',
  'healSlots' => '🩺',
  'healQueue' => '⏳',
  'heal' => '🩹',
  'trade' => '💱',
  'craftSlots' => '⚗️',
  'craftQueue' => '⏳',
  'storage' => '🏚',
  'breeding' => '💞',
  'hatching' => '🐣',
  _ => '📦',
};

/// Types listed as EFFECT ROWS — in the upgrade preview, and in a building's
/// own Effects card (user 2026-07-29: "ich brauche einen effekt für den scout
/// post, wie viele Expeditionen gleichzeitig laufen können" — the effect had
/// existed since the post moved to era I, it was simply never PRINTED, so the
/// building said nothing about the one thing it is for).
///
/// `production` and `housing` are excluded because the outputs table already
/// carries them — listing them twice would be the "Housing 5 → 5" duplication
/// all over again.
const Set<String> kEffectRowTypes = {
  'resource',
  'expedition',
  'expeditionSlots',
  'caravan',
  'caravanSlots',
  'huntOptions',
  'heal',
  'healSlots',
  'healQueue',
  // NO 'xp' — the work XP rate is settlement-wide since 2026-07-30, not a
  // per-building effect. Every post states it on its own line instead (see
  // SettlementMap._productionSection), which is where it belongs: it is what a
  // MONSTER gets out of standing there, not what the building produces.
  'breeding',
  'hatching',
  'queueSlots',
  'buildSlots',
  'trade',
  'craftSlots',
  'craftQueue',
  'storage',
};

/// One row of a building's own Effects card — what it grants RIGHT NOW, in its
/// own unit.
class EffectCardRow {
  /// "Build sites", "Expedition bonus · carry" — the effect, named.
  final String label;

  /// Its value in its own unit, glyph included: "2 🏗", "−5 % 💱".
  final String value;

  /// True when the effect is authored but worth nothing at this level, and
  /// [value] therefore says WHEN it starts ("from Lv 3 🏗") instead of what it
  /// gives. Renders faint.
  final bool pending;

  const EffectCardRow({
    required this.label,
    required this.value,
    this.pending = false,
  });
}

/// The first building level at which [type]/[key] is worth something, or null if
/// it never is. Scans the whole authored ladder, every era band — an effect may
/// arrive in a later era's levels.
int? firstLevelWithEffect(BuildingDef def, String type, String key, int era) {
  final top = def.maxLevelPerEra.isEmpty
      ? kMaxBuildingLevel
      : def.maxLevelPerEra.values.reduce((a, b) => a > b ? a : b);
  for (var l = 2; l <= top; l++) {
    if (buildingEffectValueAt(def, type, key, era, l) != 0) return l;
  }
  return null;
}

/// EVERY effect [def] grants at [level] in era [era], as the building dialog
/// lists them (user 2026-07-30: "schaue, dass jedes Gebäude wirklich jeden
/// Effekt abdeckt im Gebäudedetailscreen").
///
/// A ZERO IS STILL AN EFFECT — that is the whole reason this is a function with
/// a test rather than a loop inside the widget. The card skipped any effect
/// worth nothing at the current level, and the Builder Camp's build site and
/// queue slot both START at zero and arrive at a level: its Effects card listed
/// nothing at all until Lv 3, while the Upgrade panel right below it was already
/// promising both. Those rows now say the level they arrive at.
///
/// `production` and `housing` are the caller's business (they have dedicated
/// rows above), and so is `storage` when [includeStorage] is false — the dialog
/// groups its ceilings under one heading.
List<EffectCardRow> buildingEffectCardRows(
  BuildingDef def,
  int era,
  int level, {
  bool includeStorage = false,
}) {
  final rows = <EffectCardRow>[];
  for (final type in kEffectRowTypes) {
    if (type == 'storage' && !includeStorage) continue;
    for (final key in def.effectKeys(type)) {
      // Not authored for this era YET — a later era's effect is not this
      // building's effect today, so it is not a row today either.
      if (def.effectEntry(type, key, era) == null) continue;
      final v = buildingEffectValueAt(def, type, key, era, level);
      final at = v == 0 ? firstLevelWithEffect(def, type, key, era) : null;
      rows.add(EffectCardRow(
        label: key.isEmpty
            ? buildingEffectLabel(type)
            : '${buildingEffectLabel(type)} · $key',
        value: at != null
            ? 'from Lv $at ${buildingEffectEmoji(type)}'
            : '${formatBuildingEffect(type, key, v)} '
                '${buildingEffectEmoji(type)}',
        pending: v == 0,
      ));
    }
  }
  return rows;
}

/// EVERY per-level bonus a level buys, for any building (user 2026-07-26:
/// "buildercamp hat bei lvl 3 z.b einen weiteren build slot. Solche Boni sollen
/// über alle Gebäude hinweg bei den upgrades … angezeigt werden").
///
/// The upgrade panel only ever showed worker-free OUTPUTS and the work posts, so
/// a level whose whole point was "+1 build site" looked like it bought nothing.
/// Every authored effect type is read here — through [buildingEffectValueAt], so
/// the row cannot promise a curve the runtime does not apply.
List<UpgradeLine> buildingEffectUpgradeLines(
  BuildingDef def,
  int from,
  int to,
  int era,
) {
  final lines = <UpgradeLine>[];
  for (final type in kEffectRowTypes) {
    for (final key in def.effectKeys(type)) {
      if (def.effectEntry(type, key, era) == null) continue;
      final now = buildingEffectValueAt(def, type, key, era, from);
      final next = buildingEffectValueAt(def, type, key, era, to);
      // A CEILING is grouped and bare: one "Storage" heading, then the
      // resource, then the new number. Everything else names itself on the row
      // and shows the move (user 2026-07-30).
      final isStorage = type == 'storage';
      lines.add(UpgradeLine(
        label: isStorage
            // Name the key when the type has more than one (resource/expedition).
            ? key
            : key.isEmpty
                ? buildingEffectLabel(type)
                : '${buildingEffectLabel(type)} · $key',
        emoji: isStorage ? '' : buildingEffectEmoji(type),
        now: formatBuildingEffect(type, key, now),
        next: formatBuildingEffect(type, key, next),
        group: isStorage ? buildingEffectLabel(type) : null,
        onlyNext: isStorage,
      ));
    }
  }
  // NO alphabetical sort (user 2026-07-30: "unten die gleiche Reihenfolge wie
  // oben"). It used to sort by label, which put a store's ceilings in
  // fish/fur/stone/wood order under a card that listed them wood/stone/fish/
  // fur — the same four rows, shuffled, one panel apart. Authoring order is
  // what the card above already uses, and what the author sees in the editor.
  return lines;
}

/// What levelling [def] from [from] to [to] does to its WORK POSTS: the slot
/// count, and the multiplier on every posted worker's output.
///
/// Stated as a factor rather than as units/h on purpose — output per worker is
/// `stat × mult × factor`, and the stat belongs to whichever creature is posted
/// there. A factor is exact for every one of them; a rate would need a
/// reference monster the player never chose.
List<UpgradeLine> workshopUpgradeLines(BuildingDef def, int from, int to) {
  final lines = <UpgradeLine>[];
  final many = def.workshops.length > 1;
  for (final role in def.workshops) {
    // Name the post only when there is more than one to tell apart.
    final suffix = many
        ? ' · ${workshopRoleName(role.resource) ?? role.resource}'
        : '';
    final slotsNow = effectiveSlots(role, from);
    final slotsNext = effectiveSlots(role, to);
    lines.add(UpgradeLine(
      label: 'Workers$suffix',
      emoji: '👷',
      now: '$slotsNow',
      next: '$slotsNext',
    ));
    String factor(int level) => '×${_trim(role.levelScale(level))}';
    lines.add(UpgradeLine(
      label: 'Per worker$suffix',
      emoji: workshopRoleFeedsSystem(role.resource)
          ? workshopRoleEmoji(role.resource)
          : '⚒',
      now: factor(from),
      next: factor(to),
    ));
  }
  return lines;
}

/// 1.5 → "1.5", 2.0 → "2" — a trailing ".0" on a multiplier is just noise.
String _trim(double v) {
  final r = (v * 10).round() / 10;
  return r == r.roundToDouble() ? r.round().toString() : r.toString();
}

/// Whether [resource] is a system output rather than a stockpile one.
bool workshopRoleFeedsSystem(String resource) =>
    resource == WorkshopRole.kBreeding ||
    resource == WorkshopRole.kHatching ||
    resource == WorkshopRole.kHealSpeed ||
    resource == WorkshopRole.kTradeRate ||
    resource == WorkshopRole.kExpCarry ||
    resource == WorkshopRole.kExpTravel ||
    resource == WorkshopRole.kExpGoods ||
    resource == WorkshopRole.kExpedition ||
    resource == WorkshopRole.kCaravan ||
    resource == WorkshopRole.kCarCarry ||
    resource == WorkshopRole.kCarTravel ||
    // Room, not goods (user 2026-07-30) — a store's post raises that store's
    // ceilings, so printing it "+190/h 📦" would read as production it isn't.
    resource == WorkshopRole.kStorageRoom;

/// A role's name in terms of what it DOES, or null for a plain resource (the
/// caller names those from kResourceEmoji / kGoodsDefs).
String? workshopRoleName(String resource) => switch (resource) {
  WorkshopRole.kConstruction => 'Construction',
  WorkshopRole.kCrafting => 'Crafting',
  WorkshopRole.kTraining => 'Training',
  WorkshopRole.kLegendaryBoost => 'Legendary bonus',
  WorkshopRole.kBreeding => 'Mating time',
  WorkshopRole.kHatching => 'Incubation time',
  WorkshopRole.kHealSpeed => 'Healing time',
  WorkshopRole.kTradeRate => 'Trade spread',
  WorkshopRole.kExpCarry => 'Carrying capacity',
  WorkshopRole.kExpTravel => 'Travel time',
  WorkshopRole.kExpGoods => 'Goods yield',
  // The combined post is named for the WHOLE trip, because that is what it
  // improves — the three parts are spelled out on its value line.
  WorkshopRole.kExpedition => 'Expedition',
  // The combined caravan post — named for the whole run, like its twin.
  WorkshopRole.kCaravan => 'Caravan',
  WorkshopRole.kCarCarry => 'Caravan cargo',
  WorkshopRole.kCarTravel => 'Caravan road time',
  // Named for what it buys, like every other system post: the store's room.
  WorkshopRole.kStorageRoom => 'Storage room',
  _ => null,
};

/// The glyph that goes with [workshopRoleEffect].
String workshopRoleEmoji(String resource) => switch (resource) {
  WorkshopRole.kBreeding => '💞',
  WorkshopRole.kHatching => '🐣',
  WorkshopRole.kHealSpeed => '🩹',
  WorkshopRole.kTradeRate => '💱',
  WorkshopRole.kExpTravel => '🥾',
  WorkshopRole.kExpCarry => '🎒',
  WorkshopRole.kExpGoods => '📦',
  WorkshopRole.kExpedition => '🧭',
  WorkshopRole.kCaravan => '🐫',
  WorkshopRole.kCarTravel => '🐫',
  WorkshopRole.kCarCarry => '🛒',
  // The same glyph the `storage` EFFECT wears — the post and the ceiling it
  // raises are the same fact, so they must not wear different icons.
  WorkshopRole.kStorageRoom => '🏚',
  _ => '📦',
};

/// What a whole CONTRIBUTION MAP is worth, in words — one clause per output,
/// joined: "+3 % 🎒 · +3 % 📦 · −5 % 🥾".
///
/// A plain post has exactly one entry and reads as it always did; a COMBINED
/// post (WorkshopRole.kExpedition) has three, which is the only reason this
/// exists. Every clause goes through [workshopRoleEffect], so the combined post
/// can never state its parts differently from the buildings that grant them
/// singly. Parts worth nothing are dropped — a dial turned to zero should not
/// print "+0 %" forever.
String workshopPowerLabel(Map<String, double> power, {bool withGlyph = true}) {
  final parts = workshopPowerParts(power, withGlyph: withGlyph);
  return parts.isEmpty ? '—' : parts.join(' · ');
}

/// The same clauses, UNJOINED — for the places that stack them instead of
/// running them together (user 2026-07-29: "diese Effekte sollen übereinander
/// stehen nicht nebeneinander"). Three amplifiers on one line read as one
/// long number; on three lines each is its own fact.
List<String> workshopPowerParts(
  Map<String, double> power, {
  bool withGlyph = true,
}) => [
  for (final e in power.entries)
    if (e.value != 0)
      withGlyph
          ? '${workshopRoleEffect(e.key, e.value)} ${workshopRoleEmoji(e.key)}'
          : workshopRoleEffect(e.key, e.value),
];

/// What [power] on a SINGLE system output is worth, e.g. "−25 %". Each branch
/// applies the SAME shape and ceiling the runtime does, so the screens never
/// promise more than the game grants.
///
/// [resource] is an OUTPUT key, not necessarily a role key — a combined post's
/// parts are named by the single-purpose key each one feeds
/// (WorkshopRole.kCombinedParts), which is why kExpedition/kCaravan have no
/// branch here: they have several powers, not one, and callers reach them via
/// [workshopPowerLabel].
String workshopRoleEffect(String resource, double power) {
  String pct(double v) => '${(v * 100).toStringAsFixed(0)} %';
  return switch (resource) {
    // Both breeder posts read the same curve — only the clock they shorten
    // differs (mating vs. incubation).
    WorkshopRole.kBreeding ||
    WorkshopRole.kHatching =>
      '−${pct(breedingTimeCut(power))}',
    WorkshopRole.kHealSpeed => '−${pct(power.clamp(0.0, 0.9))}',
    WorkshopRole.kTradeRate => '−${pct(power.clamp(0.0, kMaxTradeDiscount))}',
    // Uncapped since 2026-07-29 — the runtime's own hyperbola, so the post
    // never promises the −60 % wall that no longer exists.
    WorkshopRole.kExpTravel ||
    WorkshopRole.kCarTravel =>
      '−${pct(power <= 0 ? 0 : power / (1 + power))}',
    WorkshopRole.kExpCarry ||
    WorkshopRole.kExpGoods ||
    WorkshopRole.kCarCarry =>
      '+${pct(power)}',
    // A COUNT of units, not a fraction and not a rate (user 2026-07-30): this
    // many more wood/stone/… the store can hold, per resource it stores. Rounded
    // because a ceiling of 190.4 is a ceiling of 190.
    WorkshopRole.kStorageRoom => '+${power.round()} room',
    _ => '+${power.toStringAsFixed(1)}/h',
  };
}
