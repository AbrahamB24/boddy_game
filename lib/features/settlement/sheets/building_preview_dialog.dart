import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/duration_format.dart';
import '../../../core/ui/pressable.dart';
import '../data/building_definitions.dart';
import '../data/goods_definitions.dart' show kGoodsDefs;
import '../data/resource_icons.dart';
import '../data/workshop_role_effects.dart';
import '../settlement_controller.dart';
import '../widgets/building_icon.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

/// Whether [def] can be built right now, and if not, why — ONE answer for the
/// build strip's cards and for the preview dialog's Build button, so the two can
/// never disagree about what a tap will do.
class BuildStatus {
  /// How many of it stand on the map already.
  final int placed;

  /// The cap, or null when there is none (roads and most buildings).
  final int? max;
  final bool atMax;
  final bool queueFull;
  final bool poor;

  const BuildStatus({
    required this.placed,
    required this.max,
    required this.atMax,
    required this.queueFull,
    required this.poor,
  });

  bool get enabled => !atMax && !queueFull && !poor;

  /// The word on a refused card; null when the only problem is money (the cost
  /// row turns red for that).
  String? get reason => atMax ? 'MAX' : (queueFull ? 'QUEUE' : null);

  /// The same, in a sentence, for the dialog's button.
  String? get sentence => atMax
      ? 'You have built the most of these you can.'
      : queueFull
      ? 'The build queue is full.'
      : poor
      ? 'You cannot afford it yet.'
      : null;

  factory BuildStatus.of(
    SettlementController ctrl,
    BuildingDef def,
    Map<String, double> stock,
  ) {
    final placed = ctrl.buildings
        .where((b) => b.buildingTypeId == def.id)
        .length;
    final effectiveMax = def.isBuildPlot ? ctrl.buildPlotLimit : def.maxCount;
    final capped = def.isBuildPlot || def.maxCount > 0;
    return BuildStatus(
      placed: placed,
      max: capped ? effectiveMax : null,
      atMax: capped && placed >= effectiveMax,
      queueFull:
          def.constructionSeconds > 0 &&
          ctrl.activeConstructionCount >= ctrl.maxBuildSlots &&
          ctrl.queuedConstructionCount >= ctrl.maxQueueSlots,
      poor: !def.canAfford(stock),
    );
  }
}

/// WHAT A BUILDING DOES, BEFORE YOU BUILD IT (user 2026-09-20: "ich muss noch
/// eine Möglichkeit haben, die Werte für ein Gebäude zu sehen … bevor ich das
/// Gebäude baue. Sonst weiss ich gar nicht, was das Gebäude macht und ich kann
/// sie nicht vergleichen").
///
/// Opened from the (i) on a build-strip card. It wears the building dialog's
/// template — hero card, Effects card, crew card — but is a plain read of the
/// DEFINITION: nothing is placed, so nothing here is live. A level stepper lets
/// you look ahead at what upgrades will bring (the numbers come through the same
/// [buildingEffectValueAt] the real dialog uses, so they cannot promise more than
/// the game grants), and the Build button hands the building to the map exactly
/// as tapping its card does.
Future<void> showBuildingPreview(
  BuildContext context,
  SettlementController ctrl,
  BuildingDef def, {
  required VoidCallback onBuild,
}) => showDialog<void>(
  context: context,
  barrierColor: CreamPalette.dim,
  builder: (_) => _BuildingPreview(ctrl: ctrl, def: def, onBuild: onBuild),
);

class _BuildingPreview extends StatefulWidget {
  final SettlementController ctrl;
  final BuildingDef def;
  final VoidCallback onBuild;

  const _BuildingPreview({
    required this.ctrl,
    required this.def,
    required this.onBuild,
  });

  @override
  State<_BuildingPreview> createState() => _BuildingPreviewState();
}

class _BuildingPreviewState extends State<_BuildingPreview> {
  int _level = 1;

  BuildingDef get def => widget.def;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final era = ctrl.dungeonMaxStage;
    final maxLevel = maxBuildingLevelFor(def, era);
    final size = MediaQuery.sizeOf(context);
    final stock = ctrl.resources?.asMap ?? {};
    final status = BuildStatus.of(ctrl, def, stock);
    // The two cards under the hero take what the screen leaves; 24 (inset) + 18
    // (padding) + the hero + a gap.
    final middleH = (size.height - 24 - 18 - _kHeroH - 10 - 8).clamp(
      120.0,
      260.0,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        width: (size.width - 28).clamp(320.0, 660.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          // ONE card for the whole dialog now, hero included (user
          // 2026-09-29: "überall ist noch der Header abgetrennt, dieser
          // soll aber auch in den gleichen Kasten. Resp. diese Kasten gibt
          // es nicht mehr" — the hero is chrome-like, but the rule turned
          // out to mean EVERY header, not just MenuScaffold's). A hairline
          // marks it off from Effects/Crew below; those two stay just a
          // plain [vHairline] apart from each other, being both facets of
          // "what this building does".
          child: pageCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(context, status, stock),
                hairline(),
                SizedBox(
                  height: middleH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sectionLabel(
                              'Effects',
                              icon: Icons.bolt,
                              trailing: maxLevel > 1
                                  ? _levelStepper(maxLevel)
                                  : null,
                            ),
                            const SizedBox(height: 10),
                            Expanded(child: _effects(era)),
                          ],
                        ),
                      ),
                      vHairline(),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            sectionLabel(
                              'Crew',
                              icon: Icons.groups_2_outlined,
                            ),
                            const SizedBox(height: 10),
                            Expanded(child: _crew()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const double _kHeroH = 92;

  // ── Hero: art, name, facts, the Build button ─────────────────────────

  Widget _hero(
    BuildContext context,
    BuildStatus status,
    Map<String, double> stock,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: SizedBox(
      height: _kHeroH - 16,
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Center(
              child: BuildingIcon(
                imageUrl: def.imageUrl,
                defId: def.id,
                size: 76,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.title(size: 16).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _fact(
                      Icons.schedule,
                      def.constructionSeconds <= 0
                          ? 'instant'
                          : fmtDuration(def.constructionSeconds),
                    ),
                    _fact(Icons.crop_square, '${def.gridW}×${def.gridH}'),
                    if (!def.isRoad)
                      _fact(
                        Icons.home_work,
                        status.max == null
                            ? '${status.placed} built'
                            : '${status.placed}/${status.max} built',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _buildButton(context, status, stock),
        ],
      ),
    ),
  );

  Widget _fact(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixelIcon(icon, size: 12, color: kBoxInkSoft),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: kBoxInk,
          ),
        ),
      ],
    ),
  );

  /// The gold Build button with its price on it — grey, and saying why, when the
  /// card in the strip would refuse the tap.
  Widget _buildButton(
    BuildContext context,
    BuildStatus status,
    Map<String, double> stock,
  ) {
    final enabled = status.enabled;
    return SizedBox(
      width: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Pressable(
            onTap: enabled
                ? () {
                    Navigator.pop(context);
                    widget.onBuild();
                  }
                : null,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: goldButton(active: enabled),
              child: Text(
                'Build',
                style: FoE.label(
                  size: 14,
                ).copyWith(color: goldButtonInk(active: enabled)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Money alone shows as the red price; a hard stop says why in words.
          if (status.atMax || status.queueFull)
            Text(
              status.sentence!,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: CreamPalette.warn,
              ),
            )
          else
            _costLine(stock),
        ],
      ),
    );
  }

  /// What building it costs; only the resource you are SHORT of turns red, the
  /// same rule the strip's cards use.
  Widget _costLine(Map<String, double> stock) {
    final cost = def.resourceCost;
    if (cost.isEmpty) {
      return const Text(
        'Free',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: kBoxInk,
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in cost.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '${resourceEmoji(e.key)} ${e.value.toInt()}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: (stock[e.key] ?? 0) >= e.value
                      ? kBoxInk
                      : CreamPalette.warn,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Effects at the chosen level ──────────────────────────────────────

  Widget _levelStepper(int maxLevel) {
    Widget arrow(IconData icon, bool on, VoidCallback tap) => Pressable(
      onTap: on ? tap : null,
      child: Container(
        width: 26,
        height: 26,
        decoration: raisedTile(radius: 9),
        child: PixelIcon(icon, size: 18, color: on ? kBoxInk : kBoxInkFaint),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(
          Icons.chevron_left_rounded,
          _level > 1,
          () => setState(() => _level--),
        ),
        SizedBox(
          width: 44,
          child: Text(
            'Lv $_level',
            textAlign: TextAlign.center,
            style: FoE.value(size: 12).copyWith(color: kBoxAccent),
          ),
        ),
        arrow(
          Icons.chevron_right_rounded,
          _level < maxLevel,
          () => setState(() => _level++),
        ),
      ],
    );
  }

  Widget _effects(int era) {
    final rows = <({String label, String value, bool faint, bool heading})>[];
    void add(
      String label,
      String value, {
      bool faint = false,
      bool heading = false,
    }) =>
        rows.add((label: label, value: value, faint: faint, heading: heading));

    for (final key in def.effectKeys('production')) {
      if (def.effectEntry('production', key, era) == null) continue;
      final v = def.effectAt('production', key, era, level: _level);
      add(
        'Production · ${_resLabel(key)}',
        // Build points read as the time they take off, for the player.
        key == WorkshopRole.kConstruction
            ? '${buildPointsLabel(v)} ${_resEmoji(key)}'
            : '${formatBuildingEffect('production', key, v)} ${_resEmoji(key)}',
        faint: v == 0,
      );
    }
    for (final key in def.effectKeys('storage')) {
      if (def.effectEntry('storage', key, era) == null) continue;
      final v = buildingEffectValueAt(def, 'storage', key, era, _level);
      add(
        'Storage · ${_resLabel(key)}',
        '${formatBuildingEffect('storage', key, v)} ${_resEmoji(key)}',
      );
    }
    final housing = def.hasEffect('housing', era)
        ? def.effectAt('housing', '', era, level: _level)
        : def.housingCapacity * buildingYieldFactor(_level);
    if (housing > 0) add('Housing', '${housing.round()}');
    for (final r in buildingEffectCardRows(
      def,
      era,
      _level,
      withEmoji: false,
    )) {
      add(r.label, r.value, faint: r.pending);
    }
    _addPerPoint(add);

    if (rows.isEmpty) {
      return Text(
        def.isRoad
            ? 'Roads connect your buildings — a building only works while a '
                  'road reaches it.'
            : 'It has no effect of its own${def.workshops.isEmpty ? '' : ' — '
                        'its crew does the work'}.',
        style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final r in rows)
          if (r.heading)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(
                r.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.9,
                  color: kBoxAccent,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(
                        size: 12,
                      ).copyWith(color: r.faint ? kBoxInkFaint : kBoxInk),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    r.value,
                    maxLines: 1,
                    style: FoE.value(
                      size: 12,
                    ).copyWith(color: r.faint ? kBoxInkFaint : kBoxInk),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  // ── Crew: the posts a monster can fill ───────────────────────────────

  /// WHAT ONE POINT OF THE WORKER'S STAT IS WORTH at the level being looked at
  /// (user 2026-09-20: "Effekte können die Produktion pro Punkt aufgelistet
  /// werden"). A monster's figure is its stat times this, so the rows let you
  /// compare two buildings before either has a worker: [WorkshopRole.contribution]
  /// with a reference stat of 1 — the same formula the economy runs.
  ///
  /// Posts that are not a straight rate say it in their own words instead: a
  /// travel cut or a healing speed is a percentage on a curve, so it is quoted
  /// for 10 points (through the runtime's own shape, never a made-up linear
  /// one), and a training or legendary post does not read a stat at all.
  void _addPerPoint(
    void Function(String, String, {bool faint, bool heading}) add,
  ) {
    final lines = <(String, String)>[];
    for (final role in def.workshops) {
      final res = role.resource;
      if (res == WorkshopRole.kTraining) {
        continue;
      }
      if (res == WorkshopRole.kStorageRoom) {
        for (final key in def.effectKeys('storage')) {
          lines.add((
            '${_resLabel(key)} room per point',
            '+${_num(role.storageRoomFor(key, 1, _level))} ${_resEmoji(key)}',
          ));
        }
      } else if (workshopRoleFeedsSystem(res)) {
        final label = workshopPowerLabel(role.contribution((_) => 10, _level));
        lines.add(('${_resLabel(res)} per 10 points', label));
      } else {
        final v = role.contribution((_) => 1, _level)[res] ?? 0;
        lines.add((
          '${_resLabel(res)} per point',
          res == WorkshopRole.kConstruction
              ? buildPointsLabel(v)
              : '+${_num(v)}/h ${_resEmoji(res)}',
        ));
      }
    }
    if (lines.isEmpty) return;
    add('Per point of the worker’s stat', '', heading: true);
    for (final (label, value) in lines) {
      add(label, value);
    }
  }

  /// Small figures keep their decimals ("0.20"), larger ones do not ("12").
  String _num(double v) =>
      v >= 10 ? v.round().toString() : v.toStringAsFixed(2);

  Widget _crew() {
    if (def.workshops.isEmpty) {
      return Text(
        'Nobody works here — it does its job on its own.',
        style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final role in def.workshops)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  workshopRoleFeedsSystem(role.resource)
                      ? workshopRoleEmoji(role.resource)
                      : _resEmoji(role.resource),
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _resLabel(role.resource),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.label(size: 12).copyWith(color: kBoxInk),
                      ),
                      Text(
                        'Reads the monster’s ${role.stat.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${math.max(effectiveSlots(role, _level), 0)} seat'
                  '${effectiveSlots(role, _level) == 1 ? '' : 's'}',
                  style: FoE.value(size: 12).copyWith(color: kBoxAccent),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _resEmoji(String res) => switch (res) {
    WorkshopRole.kConstruction => '🔨',
    WorkshopRole.kCrafting => '⚗️',
    WorkshopRole.kTraining => '🏋️',
    _ => resourceEmoji(res),
  };

  String _resLabel(String res) =>
      workshopRoleName(res) ??
      kGoodsDefs[res]?.name ??
      (res.isEmpty ? 'Resource' : res[0].toUpperCase() + res.substring(1));
}
