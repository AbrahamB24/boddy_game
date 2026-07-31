import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/area.dart' show kResourceEmoji;
import '../../creatures/models/creature_enums.dart'
    show kTrainingXpPerHour, workXpPerHourAt;
import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/workshop_role_effects.dart';
import '../widgets/meander_strip.dart';
import '../widgets/scroll_paper.dart'
    show
        kParchmentInk,
        kParchmentMid,
        parchmentButton,
        parchmentButtonInk;

/// Shows a building's EFFECTS at FULL UPGRADE — its highest reachable level
/// (user 2026-07-24). Opened from the build menu (before you commit to it) and
/// from the building detail sheet. Pure over the def, so it needs no placed
/// building.
Future<void> showBuildingUpgradeSheet(BuildContext context, BuildingDef def) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
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
  _ => kGoodsDefs[res]?.name ??
      (res.isEmpty ? 'Resource' : res[0].toUpperCase() + res.substring(1)),
};

class _BuildingUpgradeSheet extends StatelessWidget {
  final BuildingDef def;
  const _BuildingUpgradeSheet({required this.def});

  // ── Ink on parchment ──
  // The same surface and the same three ink strengths as the building dialog
  // and the worker sheet (user 2026-07-26: "gestalte diese Vorschau auch wie
  // die anderen Screens"). This sheet is opened FROM those two and describes
  // the very building they show — a dark panel in between read as another app.
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static const Color _accent = FoE.gold;
  static final Color _ornament = kParchmentInk.withValues(alpha: 0.22);

  // A reference worker stat, so a per-worker output reads as a concrete number
  // rather than a per-stat multiplier.
  static const int _refStat = 40;

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
    prod.removeWhere((k, v) =>
        v <= 0 ||
        k == WorkshopRole.kCrafting ||
        k == WorkshopRole.kTraining ||
        k == WorkshopRole.kLegendaryBoost);

    final housing = def.hasEffect('housing', era)
        ? def.effectAt('housing', '', era, level: maxLevel)
        : def.housingCapacity * f;

    final rows = <Widget>[];
    // [values] holds one line per figure — a combined post has three, and they
    // stack instead of running together on one line (user 2026-07-29).
    void rowLines(String emoji, String label, List<String> values) => rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: values.length > 1
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: FoE.label(size: 13).copyWith(color: FoE.parchment)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final v in values)
                  Text(v,
                      textAlign: TextAlign.end,
                      style:
                          FoE.value(size: 13).copyWith(color: FoE.goldBright)),
              ],
            ),
          ],
        ),
      ),
    );
    void row(String emoji, String label, String value) =>
        rowLines(emoji, label, [value]);

    // Production.
    for (final e in prod.entries) {
      row(
        _resEmoji(e.key),
        _resName(e.key),
        e.key == WorkshopRole.kConstruction
            ? '+${e.value.toStringAsFixed(0)} points'
            : '+${e.value.toStringAsFixed(1)}/h',
      );
    }
    // Housing.
    if (housing > 0) row('🏠', 'Housing', housing.round().toString());
    // Worker posts + per-worker output.
    for (final role in def.workshops) {
      final slots = effectiveSlots(role, maxLevel);
      if (role.resource == WorkshopRole.kLegendaryBoost) {
        row('⭐', 'Legendary boost · $slots slot${slots == 1 ? '' : 's'}',
            '×${(1 + role.mult).toStringAsFixed(1)}');
        continue;
      }
      if (role.resource == WorkshopRole.kTraining) {
        row('🏋️', 'Training · $slots slot${slots == 1 ? '' : 's'}',
            '+${kTrainingXpPerHour.toStringAsFixed(0)} XP/h');
        continue;
      }
      final perWorker = _refStat * role.mult * role.levelScale(maxLevel);
      // Same formula as every post — only the unit is points (2026-07-26).
      if (role.resource == WorkshopRole.kConstruction) {
        row(
          '🔨',
          'Construction · $slots slot${slots == 1 ? '' : 's'} '
              '(${role.stat.label})',
          '+${perWorker.toStringAsFixed(0)} points each',
        );
        continue;
      }
      // A system post's worth is a cut or a bonus, not units per hour — and
      // "each" would be a lie there, since the cut is soft-capped over the
      // SUMMED power of everyone posted (user 2026-07-26).
      // A STORE post is one figure PER RESOURCE (user 2026-07-30) — its dials
      // are per resource, so `contribution` (which knows only the flat fallback
      // mult) would have printed the same number for every good this store
      // holds, contradicting both the ceiling and the building card.
      if (role.resource == WorkshopRole.kStorageRoom) {
        final stored = def.effectKeys('storage');
        rowLines(
          workshopRoleEmoji(role.resource),
          '${workshopRoleName(role.resource)} · $slots slot'
              '${slots == 1 ? '' : 's'} (${role.stat.label})',
          stored.isEmpty
              ? const ['—']
              : [
                  for (final res in stored)
                    '+${(role.storageRoomFor(res, _refStat.toDouble(), maxLevel) * slots).round()} '
                        '${kGoodsDefs[res]?.name ?? res}',
                ],
        );
        continue;
      }
      if (workshopRoleFeedsSystem(role.resource)) {
        // A COMBINED post is three figures, not one (user 2026-07-29) — read
        // through the role's own formula so each part uses its own dial, and
        // stated part by part on the value line.
        final full = {
          for (final e in role
              .contribution((_) => _refStat.toDouble(), maxLevel)
              .entries)
            e.key: e.value * slots,
        };
        final parts = workshopPowerParts(full, withGlyph: role.isCombined);
        rowLines(
          workshopRoleEmoji(role.resource),
          '${workshopRoleName(role.resource)} · $slots slot'
              '${slots == 1 ? '' : 's'} (${role.stat.label})',
          parts.isEmpty
              ? const ['—']
              // "voll besetzt" belongs to the whole block, so it sits on the
              // last line rather than being repeated on each.
              : [
                  for (var i = 0; i < parts.length; i++)
                    i == parts.length - 1
                        ? '${parts[i]} voll besetzt'
                        : parts[i],
                ],
        );
        continue;
      }
      row(
        _resEmoji(role.resource),
        '${_resName(role.resource)} · $slots slot${slots == 1 ? '' : 's'} '
            '(${role.stat.label})',
        '+${perWorker.toStringAsFixed(1)}/h each',
      );
    }
    // Flat, settlement-wide bonuses.
    if (def.buildSpeedBonus > 0) {
      row('🔨', 'Build speed', '+${(def.buildSpeedBonus * f * 100).round()}%');
    }
    if (def.populationBonus > 0) {
      row('🏠', 'Housing bonus', '+${(def.populationBonus * f * 100).round()}%');
    }
    if (def.queueSlotsBonus > 0) {
      row('📋', 'Build queue', '+${def.queueSlotsBonus}');
    }
    // Per-era palette effects.
    for (final k in def.effectKeys('resource')) {
      final v = def.effectAt('resource', k, era, level: maxLevel);
      if (v != 0) row('📈', '${_resName(k)} production', '+${(v * 100).round()}%');
    }
    for (final k in def.effectKeys('expedition')) {
      final v = def.effectAt('expedition', k, era, level: maxLevel);
      if (v != 0) row('🧭', 'Expedition $k', '+${(v * 100).round()}%');
    }
    final expSlots = def.effectAt('expeditionSlots', '', era, level: maxLevel);
    if (expSlots != 0) {
      row('🎒', 'Expedition slots', '+${expSlots.round()}');
    }
    for (final k in def.effectKeys('heal')) {
      final v = def.effectAt('heal', k, era, level: maxLevel);
      if (v != 0) row('🩹', 'Heal $k', '−${(v * 100).round()}%');
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
    // Matings and incubations are separate caps in separate buildings (user
    // 2026-07-26), so each gets its own line rather than one "jobs" total.
    final matings = def.effectAt('breeding', '', era, level: maxLevel);
    if (matings != 0) {
      row('💞', 'Concurrent matings', matings.round().toString());
    }
    final hatchings = def.effectAt('hatching', '', era, level: maxLevel);
    if (hatchings != 0) {
      row('🐣', 'Concurrent hatchings', hatchings.round().toString());
    }
    final healSlots = def.effectAt('healSlots', '', era, level: maxLevel);
    if (healSlots != 0) {
      row('🩺', 'Concurrent heals', healSlots.round().toString());
    }
    final queueSlots = def.effectAt('queueSlots', '', era, level: maxLevel);
    if (queueSlots != 0) row('📋', 'Build queue', '+${queueSlots.round()}');
    final buildSlots = def.effectAt('buildSlots', '', era, level: maxLevel);
    if (buildSlots != 0) row('🏗️', 'Build sites', '+${buildSlots.round()}');

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: kParchmentMid,
        ),
        child: Stack(
          children: [
            // Wallpaper first, so it never lands over a line of text.
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              width: 14,
              child: MeanderStrip(color: _ornament),
            ),
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              width: 14,
              child: MeanderStrip(color: _ornament, flip: true),
            ),
            Padding(
              // Wide sides: the meander bands live in that margin.
              padding: const EdgeInsets.fromLTRB(34, 16, 34, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('${def.name} — fully upgraded',
                            style: FoE.title(size: 15).copyWith(color: _ink)),
                      ),
                      const SizedBox(width: 8),
                      // Bare, like every other readout on this paper: a boxed number
                      // reads as a button (user 2026-07-26).
                      Text('Lv $maxLevel',
                          style: FoE.value(size: 13).copyWith(color: _accent)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Effects when built up to its maximum level.',
                      style: FoE.dim(size: 11).copyWith(color: _inkSoft)),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    Text('No scaling effects — a purely decorative building.',
                        style: FoE.dim(size: 12).copyWith(color: _inkSoft))
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: rows,
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: parchmentButton(),
                      child: Text('Close',
                          style: FoE.label(size: 14)
                              .copyWith(color: parchmentButtonInk())),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
