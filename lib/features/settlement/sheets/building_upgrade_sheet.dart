import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../common/widgets/parchment_page.dart';
import '../../creatures/models/area.dart' show kResourceEmoji;
import '../../creatures/models/creature_enums.dart'
    show kTrainingXpPerHour, workXpPerHourAt;
import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/workshop_role_effects.dart';
import '../../../core/ui/game_text.dart';

/// Shows a building's EFFECTS at FULL UPGRADE — its highest reachable level
/// (user 2026-07-24). Opened from the build menu (before you commit to it) and
/// from the building detail sheet. Pure over the def, so it needs no placed
/// building.
///
/// A centred [Dialog] on [ParchmentPage.pageGradient] (user 2026-09-06: "alle
/// solchen Menüs wie der Gebäudedetailscreen in der Mitte des Screens mit dem
/// gleichen Hintergrund") — it used to be its own bottom sheet on a flat
/// [kParchmentMid] fill, which drifted the moment the building detail dialog
/// itself moved off that flat colour onto the real gradient; this sheet is
/// opened FROM that dialog and describes the very building it shows, so the
/// two materials have to match exactly, not merely resemble each other.
Future<void> showBuildingUpgradeSheet(BuildContext context, BuildingDef def) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BuildingUpgradeSheet(def: def),
  );
}

String _resEmoji(String res) => switch (res) {
  WorkshopRole.kConstruction => '🔨',
  WorkshopRole.kCrafting => '⚗️',
  WorkshopRole.kTraining => '🏋️',
  WorkshopRole.kLegendaryBoost => '⭐',
  _ => kResourceEmoji[res] ?? kGoodsDefs[res]?.emoji ?? '📦',
};

String _resName(String res) => switch (res) {
  WorkshopRole.kConstruction => 'Construction',
  WorkshopRole.kCrafting => 'Crafting',
  WorkshopRole.kTraining => 'Training',
  WorkshopRole.kLegendaryBoost => 'Legendary',
  _ =>
    kGoodsDefs[res]?.name ??
        (res.isEmpty ? 'Resource' : res[0].toUpperCase() + res.substring(1)),
};

/// "2", not "2.0" — a whole per-point rate reads oddly with a trailing
/// decimal; a fractional one (0.1/Stat Point) keeps its one place.
String _trimRate(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

class _BuildingUpgradeSheet extends StatelessWidget {
  final BuildingDef def;
  const _BuildingUpgradeSheet({required this.def});

  // ── Ink on parchment ──
  // The same surface and the same three ink strengths as the building dialog
  // and the worker sheet (user 2026-07-26: "gestalte diese Vorschau auch wie
  // die anderen Screens"). This sheet is opened FROM those two and describes
  // the very building they show — a dark panel in between read as another app.
  static const Color _ink = kBoxInk;
  static final Color _inkSoft = kBoxInkSoft;
  static final Color _inkFaint = kBoxInkFaint;
  static const Color _accent = kBoxAccent;
  // The Effects card's own inset (user 2026-09-01: "schreibe es genau so
  // wie im Gebäudedetailscreen mit der Effects box") — the exact same
  // background building_detail_dialog.dart's _sectionCard uses.

  @override
  Widget build(BuildContext context) {
    // Full upgrade = the highest reachable level and the latest-era variant of
    // every per-era effect (era 99 wins the effect ladder either way).
    final maxLevel = def.maxLevelPerEra.isEmpty
        ? kMaxBuildingLevel
        : def.maxLevelPerEra.values.reduce(math.max);
    const era = 99;
    final f = buildingYieldFactor(maxLevel);

    // ── Passive production /h ──
    // Authored `production` effects only — there is no code-side base or
    // house-gold curve any more (user 2026-07-25).
    final prod = <String, double>{};
    for (final res in def.effectKeys('production')) {
      final v = def.effectAt('production', res, era, level: maxLevel);
      if (v != 0) prod[res] = (prod[res] ?? 0) + v;
    }
    // `construction` is kept: it is the building's PASSIVE build power (user
    // 2026-07-26), authored in the same points a builder's stat is measured in.
    prod.removeWhere(
      (k, v) =>
          v <= 0 ||
          k == WorkshopRole.kCrafting ||
          k == WorkshopRole.kTraining ||
          k == WorkshopRole.kLegendaryBoost,
    );

    final housing = def.hasEffect('housing', era)
        ? def.effectAt('housing', '', era, level: maxLevel)
        : def.housingCapacity * f;

    final rows = <Widget>[];
    // The Effects card's own row shape, EXACTLY (user 2026-09-01: "schreibe
    // es genau so wie im Gebäudedetailscreen mit der Effects box") — lifted
    // straight from building_detail_dialog.dart's own `headline()`: the
    // label on the left in the accent colour, the value(s) right-aligned
    // with the glyph in its own reserved slot AFTER the number rather than
    // leading the row. [values] holds one line per figure — a combined post
    // has three, and they stack instead of running together on one line
    // (user 2026-07-29).
    // [labelColor]/[indent]: a SUB-category row nested under its own
    // "Production" heading rather than reading as one itself (user 2026-
    // 09-01, carried here from building_detail_dialog.dart's own
    // headline(): "Wood, stone gold, housing etc. etwas nach innen versetzt
    // und in weiss"). Null/0 keeps the accent-gold, flush label every other
    // row here still uses.
    // [subtitle]: a small caption under the LABEL, not the value (user
    // 2026-09-01: "bei Produktion als Untertitel schreiben Bsp: Wood
    // 1/Stat Point") — the REAL per-point rate (role.mult × its level
    // scale), a formula constant rather than the hypothetical "at stat 40"
    // output this sheet dropped earlier.
    void rowLines(
      String? emoji,
      String label,
      List<String> values, {
      Color? labelColor,
      double indent = 0,
      String? subtitle,
    }) => rows.add(
      Padding(
        padding: EdgeInsets.only(left: indent, top: 4, bottom: 4),
        child: Row(
          crossAxisAlignment: values.length > 1 || subtitle != null
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: FoE.label(
                    size: 12,
                  ).copyWith(color: labelColor ?? _accent),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: FoE.dim(size: 9).copyWith(
                      color: (labelColor ?? _accent).withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in values)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Flexible, not bare (2026-09-01 crash: "A RenderFlex
                        // overflowed") — this sheet's own Effects card is
                        // narrower than the building detail dialog's, so a
                        // value string that fit fine over there could run
                        // past the space left for it here. Shrinks to an
                        // ellipsis rather than overflow.
                        Flexible(
                          child: Text(
                            v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FoE.value(size: 12).copyWith(color: _ink),
                          ),
                        ),
                        SizedBox(
                          width: 18,
                          // Icons only for the resource-carrying rows (2026-
                          // 08-27 rule the real Effects card follows) — a
                          // generic effect (slots, %, bonuses) reserves the
                          // same slot empty rather than inventing a glyph
                          // building_detail_dialog.dart doesn't show either.
                          child: emoji == null
                              ? null
                              : Center(
                                  child: Text(
                                    emoji,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    void row(
      String emoji,
      String label,
      String value, {
      Color? labelColor,
      double indent = 0,
      String? subtitle,
    }) => rowLines(
      emoji,
      label,
      [value],
      labelColor: labelColor,
      indent: indent,
      subtitle: subtitle,
    );
    // A GROUP heading (user 2026-09-01: "Production und Storage etc. wie
    // eine Art Überschrift sind und Wood, Stone, Gold etc. nicht gleich
    // geschrieben werden") — the same faint, small-caps treatment this
    // sheet's own "EFFECTS" title wears, deliberately NOT the accent gold
    // a row's own label reads in: "Production" over "Wood"/"Stone"/"Gold"
    // has to look like a heading over its rows, not another row.
    void heading(String text) => rows.add(
      Padding(
        padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 10, bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: FoE.dim(size: 9).copyWith(
            color: _inkFaint,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );

    // Production — "Production", not the generic "Resource" the building
    // detail dialog falls back to for a multi-resource row (user 2026-09-
    // 01: "Resource durch Production ersetzen"). Here every resource gets
    // its OWN row rather than being merged into one multi-value line, so
    // the heading is what ties them together instead.
    if (prod.isNotEmpty) heading('Production');
    // Highest producer first (user 2026-09-01: "nach Produktion ordnen,
    // höchste Produktion immer oben").
    final prodEntries = prod.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in prodEntries) {
      row(
        _resEmoji(e.key),
        _resName(e.key),
        e.key == WorkshopRole.kConstruction
            ? buildPointsLabel(e.value)
            : '+${e.value.toStringAsFixed(1)}/h',
        labelColor: _ink,
        indent: 12,
      );
    }
    // Housing — same sub-row treatment (user 2026-09-01: "jetzt auf alle
    // Gebäude so umsetzen").
    if (housing > 0) {
      row(
        '🏠',
        'Housing',
        housing.round().toString(),
        labelColor: _ink,
        indent: 12,
      );
    }
    // Worker posts + per-worker output.
    for (final role in def.workshops) {
      final slots = effectiveSlots(role, maxLevel);
      if (role.resource == WorkshopRole.kLegendaryBoost) {
        row(
          '⭐',
          'Legendary boost · $slots slot${slots == 1 ? '' : 's'}',
          '×${(1 + role.mult).toStringAsFixed(1)}',
        );
        continue;
      }
      if (role.resource == WorkshopRole.kTraining) {
        row(
          '🏋️',
          'Training · $slots slot${slots == 1 ? '' : 's'}',
          '+${kTrainingXpPerHour.toStringAsFixed(0)} XP/h',
        );
        continue;
      }
      // Every remaining post: the REAL fact (slots), not a hypothetical
      // figure computed off a made-up reference worker (user 2026-09-01:
      // "genau so auf andere Gebäude übertragen" — the same fix as the
      // plain production row above, carried to Construction, the Store and
      // every combined post). None of these has a real posted creature to
      // read a stat from in this preview, so the honest answer is how many
      // seats the level buys, not an invented output.
      if (role.resource == WorkshopRole.kConstruction) {
        row('🔨', 'Construction', '$slots slot${slots == 1 ? '' : 's'}');
        continue;
      }
      if (role.resource == WorkshopRole.kStorageRoom) {
        row(
          workshopRoleEmoji(role.resource),
          '${workshopRoleName(role.resource)} ${role.stat.label}',
          '$slots slot${slots == 1 ? '' : 's'}',
        );
        continue;
      }
      if (workshopRoleFeedsSystem(role.resource)) {
        row(
          workshopRoleEmoji(role.resource),
          '${workshopRoleName(role.resource)} ${role.stat.label}',
          '$slots slot${slots == 1 ? '' : 's'}',
        );
        continue;
      }
      // The REAL fact, not a hypothetical per-worker rate (user 2026-09-01:
      // "ich will keine hypothetischen Werte, sondern das was real
      // vorhanden ist und das sind 10 slots") — "+X/h each" was computed
      // off [_refStat], a made-up reference worker nobody has actually
      // posted. The slot count is the one thing this preview (no real
      // building, no real workers) can state as fact. The RATE itself is
      // fine to show though (user 2026-09-01: "als Untertitel schreiben
      // Bsp: Wood 1/Stat Point") — role.mult × its level scale is a
      // formula constant, true for every worker regardless of their own
      // stat, not an assumption about one that doesn't exist.
      row(
        _resEmoji(role.resource),
        '${_resName(role.resource)} ${role.stat.label}',
        '$slots slot${slots == 1 ? '' : 's'}',
        subtitle:
            '${_trimRate(role.mult * role.levelScale(maxLevel))}'
            '/Stat Point',
      );
    }
    // Flat, settlement-wide bonuses.
    if (def.buildSpeedBonus > 0) {
      row('🔨', 'Build speed', '+${(def.buildSpeedBonus * f * 100).round()}%');
    }
    if (def.populationBonus > 0) {
      row(
        '🏠',
        'Housing bonus',
        '+${(def.populationBonus * f * 100).round()}%',
      );
    }
    if (def.queueSlotsBonus > 0) {
      row('📋', 'Build queue', '+${def.queueSlotsBonus}');
    }
    // XP a post pays at the top level — the settlement-wide work rate, on every
    // building that stations monsters (user 2026-07-30). It used to read a
    // per-building `xp` effect, so this line appeared on eleven buildings and
    // nowhere else; the Training Grounds says its own rate with its post above.
    if (def.workshops.isNotEmpty &&
        !def.workshops.any((w) => w.resource == WorkshopRole.kTraining)) {
      row(
        '✨',
        'XP per worker',
        '+${workXpPerHourAt(maxLevel).toStringAsFixed(0)}/h',
      );
    }
    // EVERY OTHER effect, read through the SAME function the building
    // detail screen's own Effects card uses (user 2026-09-01: "Zeige die
    // Effekte genau so an, wie sie bei der Gebäudevorschau angezeigt
    // werden" — "Healing slots 20", not this sheet's own former "Concurrent
    // heals"). This used to hand-roll a label per effect type
    // (resource/expedition/heal/breeding/hatching/healSlots/queueSlots/
    // buildSlots), drifting from [buildingEffectLabel]'s names one by one;
    // now it reads the shared vocabulary directly, so the two can never
    // disagree again. No icon, matching the real card's own rule (2026-08-
    // 27: icons stay reserved for resources) — [rowLines] leaves the slot
    // empty when passed null.
    for (final r in buildingEffectCardRows(
      def,
      era,
      maxLevel,
      withEmoji: false,
    )) {
      if (r.pending) continue;
      rowLines(null, r.label, [r.value]);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        width: 440,
        // The building dialog's card, its "Effects" card inside it (user
        // 2026-09-18: the whole UI takes that dialog as its template).
        child: creamCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          corner: const KitCloseButton(),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The level number is the headline fact this card states.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        def.name,
                        style: FoE.title(size: 15).copyWith(color: _ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Lv $maxLevel',
                      style: FoE.title(
                        size: 22,
                      ).copyWith(color: _accent, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                sectionCard(
                  title: 'Effects',
                  icon: Icons.bolt,
                  child: rows.isEmpty
                      ? Text(
                          'No scaling effects — a purely decorative building.',
                          style: FoE.dim(size: 12).copyWith(color: _inkSoft),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: rows,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
