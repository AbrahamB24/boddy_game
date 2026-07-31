import '../../core/ui/feel.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../../core/ui/duration_format.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/recess_bar.dart';
import '../creatures/services/creatures_controller.dart';
import 'data/building_definitions.dart';
import 'models/settlement.dart' show CraftJob;
import 'data/goods_definitions.dart';
import 'data/item_definitions.dart';
import 'settlement_controller.dart';
import 'widgets/scroll_paper.dart'
    show kParchmentInk, kParchmentLight, parchmentButton, parchmentButtonInk;

/// THE WORKBENCH, AS A SCREEN (user 2026-07-29: "workshop. Crafting ist ein
/// eigener screen und kann über den workshop geöffnet werden").
///
/// It used to be a strip of chips inside the Workshop's map dialog: every
/// recipe as a pill in a Wrap, a bar under them, one line of status. Which was
/// fine while there were three items — but a recipe has a cost, a duration, an
/// effect and a stock, and none of those fit on a chip. You picked things by
/// name and found out what they cost afterwards, if at all.
///
/// The Hatchery's plan, like every other building feature: what is on the bench
/// at the top, everything you could put there under it.
class CraftingScreen extends StatefulWidget {
  const CraftingScreen({super.key});

  @override
  State<CraftingScreen> createState() => _CraftingScreenState();
}

class _CraftingScreenState extends State<CraftingScreen> {
  final _ctrl = SettlementController();
  final _creatures = CreaturesController();
  Timer? _ticker;

  static const _ink = kParchmentInk;
  static final _inkSoft = kParchmentInk.withValues(alpha: 0.72);
  static final _inkFaint = kParchmentInk.withValues(alpha: 0.5);
  static const _accent = FoE.gold;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_rebuild);
    // The ETA counts down in real time; the controller only ticks when the
    // economy does.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// How many monsters are actually standing at a crafting post right now. The
  /// one number that decides whether anything on this page moves.
  ///
  /// An assignment is (building, stat), not (role) — so the crafting posts have
  /// to be resolved through each building's def, and a monster only counts if
  /// it is actually HERE (an assigned creature away on a trip crafts nothing,
  /// which is the same rule accruePassiveXp uses).
  int get _crafters {
    var n = 0;
    for (final b in _ctrl.buildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      final stats = {
        for (final w in def.workshops)
          if (w.resource == WorkshopRole.kCrafting) w.stat,
      };
      if (stats.isEmpty) continue;
      n += _creatures.creatures
          .where(
            (c) =>
                c.assignedBuildingId == b.id &&
                stats.contains(c.assignedStat) &&
                _creatures.isWorkingNow(c),
          )
          .length;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: 'Crafting',
    trailing: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kParchmentInk.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kParchmentInk.withValues(alpha: 0.2)),
      ),
      child: Text(
        '⚒️ $_crafters',
        style: FoE.value(size: 12).copyWith(
          color: _crafters == 0 ? FoE.danger : _ink,
        ),
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(
        ParchmentPage.kParchmentPagePad,
        12,
        ParchmentPage.kParchmentPagePad,
        24,
      ),
      children: [
        _benchPanel(),
        const SizedBox(height: 18),
        Text(
          'Recipes',
          style: FoE.title(size: 14).copyWith(color: _ink),
        ),
        const SizedBox(height: 8),
        _recipeList(),
      ],
    ),
  );

  // ── What is on the benches, and what is in line ──────────────────────
  // The Workshop held ONE recipe and repeated it forever (user 2026-07-30:
  // benches + a queue). So this panel is a LIST now: one row per bench with its
  // own bar, then the line underneath, in the order it will be worked.
  Widget _benchPanel() {
    final active = _ctrl.activeCraftJobs;
    final queued = _ctrl.queuedCraftJobs;
    final benches = _ctrl.craftCapacity;
    final eta = _ctrl.craftEtaSeconds;

    if (active.isEmpty) {
      return _card(
        child: Row(
          children: [
            Text('⚒️', style: TextStyle(fontSize: 24, color: _inkFaint)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _crafters == 0
                    ? 'The benches are empty, and nobody is at them — post a '
                          'monster in the Workshop, then pick a recipe.'
                    : 'The benches are empty. Pick a recipe and your crafters '
                          'start on it.',
                style: FoE.dim(size: 12).copyWith(color: _inkSoft),
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                benches == 1 ? 'On the bench' : 'On the benches',
                style: FoE.dim(size: 10).copyWith(color: _inkFaint),
              ),
              const Spacer(),
              Text(
                '${active.length}/$benches',
                style: FoE.value(size: 11).copyWith(color: _accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < active.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _benchRow(active[i], i),
          ],
          const SizedBox(height: 8),
          Text(
            // A motionless bar reads as a bug, so the one case that produces
            // one says so in words instead of leaving you to guess.
            eta == null
                ? 'Nobody is crafting — post a monster in the Workshop.'
                : 'Next ready in ${fmtDuration(eta)}',
            style: FoE.dim(size: 11).copyWith(
              color: eta == null ? FoE.danger : _inkSoft,
            ),
          ),
          if (queued.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'In line',
                  style: FoE.dim(size: 10).copyWith(color: _inkFaint),
                ),
                const Spacer(),
                Text(
                  // Naming the ceiling is what makes a full line actionable —
                  // it is a per-level effect, so the answer is "level it".
                  _ctrl.craftQueueCapacity == null
                      ? '${queued.length}'
                      : '${queued.length}/${_ctrl.craftQueueCapacity}',
                  style: FoE.value(size: 11).copyWith(color: _inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < queued.length; i++)
              _queuedRow(queued[i], benches + i),
          ],
        ],
      ),
    );
  }

  /// One bench: what is on it, how far along, and the way to take it off.
  Widget _benchRow(CraftJob job, int index) {
    final def = kItemDefs[job.itemId];
    if (def == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(def.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                def.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.title(size: 14).copyWith(color: _ink),
              ),
            ),
            _dropButton(index),
          ],
        ),
        const SizedBox(height: 8),
        RecessBar(
          value: _ctrl.craftJobProgress(job),
          color: _accent,
          height: 12,
        ),
      ],
    );
  }

  /// One waiting item — no bar, because nothing is happening to it yet.
  Widget _queuedRow(CraftJob job, int index) {
    final def = kItemDefs[job.itemId];
    if (def == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(def.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              def.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 12).copyWith(color: _inkSoft),
            ),
          ),
          _dropButton(index),
        ],
      ),
    );
  }

  Widget _dropButton(int index) => GestureDetector(
    onTap: () => _ctrl.cancelCraft(index),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Icon(
        Icons.close,
        size: 16,
        color: kParchmentInk.withValues(alpha: 0.45),
      ),
    ),
  );

  // ── Everything you could put on it ───────────────────────────────────
  Widget _recipeList() {
    final items = kItemDefs.values.toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kParchmentLight.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kParchmentInk.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                color: kParchmentInk.withValues(alpha: 0.12),
              ),
            _recipeRow(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _recipeRow(ItemDef def) {
    // Adding is the same gesture whatever is already in — one tap puts one
    // more in (user 2026-07-30). It stops when benches AND line are full.
    final room = _ctrl.canQueueCraft;
    final making =
        _ctrl.craftJobs.where((j) => j.itemId == def.id).length;
    final owned = _ctrl.items[def.id] ?? 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final err = await _ctrl.queueCraft(def.id);
        if (!mounted) return;
        if (err != null) {
          Feel.deny();
          context.snack(err);
        } else {
          Feel.success();
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        // A recipe already in the Workshop is tinted, so a long list still
        // shows at a glance what has been ordered.
        color: making > 0 ? _accent.withValues(alpha: 0.10) : null,
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Text(def.emoji, style: const TextStyle(fontSize: 21)),
                  if (owned > 0)
                    Positioned(
                      right: -6,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '$owned',
                          style: FoE.value(size: 9).copyWith(
                            color: kParchmentLight,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 12.5).copyWith(color: _ink),
                  ),
                  Text(
                    def.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.dim(size: 10).copyWith(color: _inkSoft),
                  ),
                  const SizedBox(height: 3),
                  // WHAT IT COSTS, on the row. The chips in the dialog never
                  // said, so the cost only turned up as goods that had left
                  // the storehouse.
                  Text(
                    _costLine(def),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.dim(size: 10).copyWith(color: _inkFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: parchmentButton(active: room),
              child: Text(
                // The COUNT already in, so "how many did I order" is answered
                // on the row that orders them.
                making > 0 ? '+ Craft ($making)' : 'Craft',
                style: FoE.label(size: 11).copyWith(
                  color: parchmentButtonInk(active: room),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A recipe's price in the goods it actually charges — the named ingredients
  /// when it has them, else the abstract supply bill.
  String _costLine(ItemDef def) {
    if (def.ingredients.isNotEmpty) {
      return def.ingredients.entries
          .map(
            (e) =>
                '${kGoodsDefs[e.key]?.emoji ?? ''} ${e.value.toStringAsFixed(0)} '
                '${kGoodsDefs[e.key]?.name ?? e.key}',
          )
          .join(' · ');
    }
    return '${def.supplyCost.toStringAsFixed(0)} supplies';
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: kParchmentLight.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kParchmentInk.withValues(alpha: 0.16)),
    ),
    child: child,
  );
}
