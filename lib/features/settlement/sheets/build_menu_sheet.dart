import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../settlement_controller.dart';
import '../widgets/building_icon.dart';

String fmtDuration(double seconds) {
  if (seconds <= 0) return 'Instant';
  if (seconds < 60) return '${seconds.toInt()}s';
  final m = (seconds / 60).floor();
  final s = (seconds % 60).toInt();
  if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s';
  final h = (m / 60).floor();
  final rm = m % 60;
  if (h < 24) return '${h}h ${rm.toString().padLeft(2, '0')}m';
  final d = (h / 24).floor();
  return '${d}d ${(h % 24)}h';
}

class BuildMenuSheet extends StatelessWidget {
  final SettlementController ctrl;
  final void Function(String typeId) onSelect;
  final VoidCallback onEnterMoveMode;
  final VoidCallback onPaintRoads;

  const BuildMenuSheet({
    super.key,
    required this.ctrl,
    required this.onSelect,
    required this.onEnterMoveMode,
    required this.onPaintRoads,
  });

  @override
  Widget build(BuildContext context) {
    final currentEraId = ctrl.currentEra?.id ?? '';
    final stock = ctrl.resources?.asMap ?? {};
    final available = availableBuildings(currentEraId, ctrl.unlockedTechs);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: FoE.panelGradient,
            border: Border(top: BorderSide(color: FoE.borderGold, width: 1.5)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FoE.borderGold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text('Build', style: FoE.title(size: 16)),
                    const Spacer(),
                    // Road paint mode button
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onPaintRoads();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A2A16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.greenAccent.shade400,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🛤️', style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 5),
                            Text(
                              'Roads',
                              style: FoE.label(
                                size: 12,
                              ).copyWith(color: Colors.greenAccent),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Move mode button
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onEnterMoveMode();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2E4A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF4488FF),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.open_with,
                              color: Color(0xFF88BBFF),
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Move',
                              style: FoE.label(
                                size: 12,
                              ).copyWith(color: const Color(0xFF88BBFF)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      ctrl.currentEra?.name ??
                          'Era ${ctrl.settlement?.eraIndex ?? 1}',
                      style: FoE.dim().copyWith(color: FoE.textDim),
                    ),
                  ],
                ),
              ),
              // Build slot status
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _SlotStatusRow(ctrl: ctrl),
              ),
              FoE.divider(vPad: 8),
              // List
              Expanded(
                child: ListView.separated(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: available.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _BuildingRow(
                    def: available[i],
                    stock: stock,
                    ctrl: ctrl,
                    onTap: () {
                      Navigator.pop(context);
                      onSelect(available[i].id);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Slot status row ───────────────────────────────────────
class _SlotStatusRow extends StatelessWidget {
  final SettlementController ctrl;
  const _SlotStatusRow({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final active = ctrl.activeConstructionCount;
    final queued = ctrl.queuedConstructionCount;
    final maxSlots = ctrl.maxBuildSlots;
    final maxQueue = ctrl.maxQueueSlots;
    final slotsFull = active >= maxSlots;
    final queueFull = queued >= maxQueue;
    final freeHousing = ctrl.housingFree;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      // Wrap instead of Row — reflows to a 2nd line on narrow phones instead
      // of clipping if either chip's text grows.
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _chip('Active: $active/$maxSlots', slotsFull),
          _chip('Queue: $queued/$maxQueue', queueFull),
          _chip('Housing free: $freeHousing', freeHousing <= 0),
        ],
      ),
    );
  }

  Widget _chip(String label, bool full) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: full
          ? Colors.orange.shade900.withValues(alpha: 0.35)
          : FoE.panelDark,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: full ? Colors.orange.shade700 : FoE.border),
    ),
    child: Text(
      label,
      style: FoE.dim(
        size: 10,
      ).copyWith(color: full ? Colors.orange.shade300 : FoE.textDim),
    ),
  );
}

// ── Build row ─────────────────────────────────────────────
class _BuildingRow extends StatelessWidget {
  final BuildingDef def;
  final Map<String, double> stock;
  final SettlementController ctrl;
  final VoidCallback onTap;

  const _BuildingRow({
    required this.def,
    required this.stock,
    required this.ctrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placed = ctrl.buildings
        .where((b) => b.buildingTypeId == def.id)
        .length;
    final atMax = def.maxCount > 0 && placed >= def.maxCount;
    final queueFull =
        def.constructionSeconds > 0 &&
        ctrl.activeConstructionCount >= ctrl.maxBuildSlots &&
        ctrl.queuedConstructionCount >= ctrl.maxQueueSlots;
    final canAfford = !atMax && !queueFull && def.canAfford(stock);

    return GestureDetector(
      onTap: canAfford ? onTap : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: canAfford
                ? [FoE.panelMid, FoE.panelDark]
                : [FoE.panelDark, FoE.bg],
          ),
          border: Border(
            top: BorderSide(
              color: canAfford ? FoE.borderGold : FoE.border,
              width: 1.5,
            ),
            left: BorderSide(
              color: canAfford ? FoE.borderGold : FoE.border,
              width: 1.5,
            ),
            right: BorderSide(color: FoE.border, width: 1),
            bottom: BorderSide(color: FoE.border, width: 1),
          ),
        ),
        child: Row(
          children: [
            // Icon box
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A2E16), Color(0xFF221A08)],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: canAfford ? FoE.borderGold : FoE.border,
                ),
              ),
              child: Center(
                child: BuildingIcon(
                  imageUrl: def.imageUrl,
                  size: 20,
                  dimmed: !canAfford,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.name,
                    style: FoE.label(size: 13).copyWith(
                      color: canAfford ? FoE.parchment : FoE.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _bonusText(def),
                        style: FoE.dim(
                          size: 10,
                        ).copyWith(color: const Color(0xFF5A8A3A)),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '⏱ ${_buildTimeText()}',
                            style: FoE.dim(
                              size: 10,
                            ).copyWith(color: FoE.textDim),
                          ),
                          if (_minBuildTimeText() != _buildTimeText())
                            Text(
                              'min: ${_minBuildTimeText()}',
                              style: FoE.dim(size: 9).copyWith(
                                color: FoE.textDim.withValues(alpha: 0.55),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _costRow(def.resourceCost, stock),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Size + count chips
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: FoE.panelDark,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: FoE.border),
                  ),
                  child: Text(
                    '${def.gridW}×${def.gridH}',
                    style: FoE.dim(size: 9).copyWith(color: FoE.textDim),
                  ),
                ),
                if (def.maxCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: atMax
                          ? Colors.red.shade900.withValues(alpha: 0.4)
                          : FoE.panelDark,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: atMax ? Colors.red.shade700 : FoE.border,
                      ),
                    ),
                    child: Text(
                      '$placed/${def.maxCount}',
                      style: FoE.dim(size: 9).copyWith(
                        color: atMax ? Colors.red.shade300 : FoE.textDim,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Rate/duration formulas here must mirror GameEngine.tick()'s construction
  // math exactly (same buildRatePerHour, same buildSpeedMultiplier, same
  // activeCount divisor) — energy only gates whether production runs at all
  // (full rate while currentEnergy > 0) between one hard stop, never a
  // fractional slowdown, so `energy.fraction` must NOT appear in these rates.
  String _buildTimeText() {
    if (def.constructionSeconds <= 0) return 'Instant';
    final e = ctrl.energy;
    if (e == null) return fmtDuration(def.constructionSeconds);
    final active = ctrl.activeConstructionCount;
    final maxSlots = ctrl.maxBuildSlots;
    final baseRate = e.currentEnergy > 0
        ? (ctrl.buildRatePerHour / 3600.0) * ctrl.buildSpeedMultiplier
        : 0.0;
    if (active >= maxSlots) {
      if (baseRate <= 0) return 'Queued (∞)';
      return 'Queued (~${fmtDuration(def.constructionSeconds / baseRate)})';
    }
    final rate = baseRate / (active + 1);
    if (rate <= 0) return '∞';
    return fmtDuration(def.constructionSeconds / rate);
  }

  // Best case: this were the only active build site (divide by 1, no queue
  // wait) — the achievable-today equivalent of the old "100% of population on
  // build" hint, now that build speed no longer comes from a population
  // allocation lever.
  String _minBuildTimeText() {
    if (def.constructionSeconds <= 0) return 'Instant';
    final e = ctrl.energy;
    if (e == null) return fmtDuration(def.constructionSeconds);
    if (e.currentEnergy <= 0) return '∞';
    final rate = (ctrl.buildRatePerHour / 3600.0) * ctrl.buildSpeedMultiplier;
    if (rate <= 0) return '∞';
    return fmtDuration(def.constructionSeconds / rate);
  }

  String _bonusText(BuildingDef def) {
    if (def.isBuildPlot) {
      return 'Expands buildable area by ${def.gridW}×${def.gridH}';
    }
    final parts = <String>[];
    if (def.housingCapacity > 0) parts.add('🏠 houses ${def.housingCapacity}');
    for (final w in def.workshops) {
      parts.add('${w.stat.label} → ${w.resource} (${w.slots} slots)');
    }
    if (def.buildSpeedBonus > 0) {
      parts.add('+${(def.buildSpeedBonus * 100).toInt()}% build speed');
    }
    if (def.queueSlotsBonus > 0) {
      parts.add('+${def.queueSlotsBonus} queue slot');
    }
    return parts.isEmpty ? 'No bonus' : parts.join('  ·  ');
  }

  Widget _costRow(Map<String, double> cost, Map<String, double> stock) {
    final chips = cost.entries.map((e) {
      final have = stock[e.key] ?? 0;
      final ok = have >= e.value;
      final em = e.key == 'wood'
          ? '🪵'
          : e.key == 'stone'
          ? '🪨'
          : e.key;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          '$em ${e.value.toInt()}',
          style: FoE.dim(
            size: 10,
          ).copyWith(color: ok ? FoE.parchment : Colors.redAccent.shade200),
        ),
      );
    }).toList();
    if (chips.isEmpty) {
      return Text(
        'Free',
        style: FoE.dim(size: 10).copyWith(color: const Color(0xFF5A8A3A)),
      );
    }
    return Row(children: chips);
  }
}
