import 'dart:async';
import 'dart:math' show max;
import '../sheets/build_menu_sheet.dart' show fmtDuration;
import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/breeding_screen.dart';
import '../../creatures/dungeon_map_screen.dart';
import '../../creatures/models/creature_enums.dart'
    show
        CreatureStat,
        kDungeonPortalBuildingId,
        kBreedingHutBuildingId,
        kHealingHutBuildingId;
import '../../creatures/models/creature_instance.dart';
import '../../creatures/services/creatures_controller.dart';
import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import 'building_icon.dart';

class SettlementMap extends StatefulWidget {
  final SettlementController ctrl;
  final String? pendingTypeId;
  final bool editMode;
  final bool roadMode;
  final VoidCallback? onPlacementDone;
  final VoidCallback? onExitEditMode;
  final VoidCallback? onExitRoadMode;

  const SettlementMap({
    super.key,
    required this.ctrl,
    this.pendingTypeId,
    this.editMode = false,
    this.roadMode = false,
    this.onPlacementDone,
    this.onExitEditMode,
    this.onExitRoadMode,
  });

  @override
  State<SettlementMap> createState() => _SettlementMapState();
}

class _SettlementMapState extends State<SettlementMap> {
  // Normal long-press move (outside edit mode)
  int? _ghostX, _ghostY;
  String? _movingId;
  String? _movingType;

  // Edit mode
  String? _selectedId;
  String? _selectedType;
  bool _isDragging = false;

  // Road paint mode — tracks the last cell touched during a drag stroke so
  // each cell is only toggled once per continuous gesture.
  int? _lastRoadKey;

  bool get _inMoveMode => _movingId != null;
  bool get _inPlaceMode => widget.pendingTypeId != null;

  final _txCtrl = TransformationController();
  bool _txInitialized = false;

  @override
  void didUpdateWidget(SettlementMap old) {
    super.didUpdateWidget(old);
    // Clear edit selection when leaving edit mode
    if (!widget.editMode && old.editMode) {
      _selectedId = null;
      _selectedType = null;
      _isDragging = false;
      _movingId = null;
      _movingType = null;
      _ghostX = null;
      _ghostY = null;
    }
    if (!widget.roadMode && old.roadMode) {
      _lastRoadKey = null;
    }
  }

  @override
  void dispose() {
    _txCtrl.dispose();
    super.dispose();
  }

  // ── Tap inside InteractiveViewer (normal + edit-idle) ─────
  void _handleTap(Offset local) {
    final col = (local.dx / kCellSize).floor().clamp(0, kGridCols - 1);
    final row = (local.dy / kCellSize).floor().clamp(0, kGridRows - 1);

    if (_inMoveMode) {
      final def = kBuildingDefs[_movingType!]!;
      final x = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      final y = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
      _confirmMove(x, y);
      return;
    }

    if (_inPlaceMode) {
      final def = kBuildingDefs[widget.pendingTypeId!]!;
      final x = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      final y = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
      _confirmPlacement(x, y, def);
      return;
    }

    if (widget.editMode) {
      // Overlay is inactive (no selection yet) — tap selects
      final hit = _hitTest(col, row);
      setState(() {
        _selectedId = hit?.id;
        _selectedType = hit?.buildingTypeId;
      });
      return;
    }

    final hit = _hitTest(col, row);
    if (hit != null) _showDetail(hit);
  }

  // ── Long-press inside InteractiveViewer (normal mode only) ─
  void _handleLongPress(Offset local) {
    if (widget.editMode) return;
    if (_inMoveMode) {
      _cancelMove();
      return;
    }
    if (_inPlaceMode) return;

    final col = (local.dx / kCellSize).floor().clamp(0, kGridCols - 1);
    final row = (local.dy / kCellSize).floor().clamp(0, kGridRows - 1);
    final hit = _hitTest(col, row);
    if (hit == null) return;
    setState(() {
      _movingId = hit.id;
      _movingType = hit.buildingTypeId;
      _ghostX = hit.gridX;
      _ghostY = hit.gridY;
    });
  }

  void _handleHover(Offset local) {
    if (!_inMoveMode && !_inPlaceMode) return;
    final typeId = _inMoveMode ? _movingType! : widget.pendingTypeId!;
    final def = kBuildingDefs[typeId]!;
    final col = (local.dx / kCellSize).floor();
    final row = (local.dy / kCellSize).floor();
    setState(() {
      _ghostX = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      _ghostY = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
    });
  }

  // ── Road paint mode (screen-space coordinates) ─────────────
  // Tapping/dragging over an empty cell paints a road; over an existing
  // road it erases it; over any other building it's a no-op. Free, instant.
  void _paintRoadAt(Offset screenLocal) {
    final scene = _txCtrl.toScene(screenLocal);
    final col = (scene.dx / kCellSize).floor().clamp(0, kGridCols - 1);
    final row = (scene.dy / kCellSize).floor().clamp(0, kGridRows - 1);
    final key = row * kGridCols + col;
    if (key == _lastRoadKey) return;
    _lastRoadKey = key;

    final hit = _hitTest(col, row);
    if (hit != null && hit.buildingTypeId == 'road') {
      widget.ctrl.deleteBuilding(hit.id);
    } else if (hit == null) {
      widget.ctrl.placeBuilding('road', col, row);
    }
  }

  // ── Edit-mode overlay handlers (screen-space coordinates) ──
  void _handleOverlayTap(Offset screenLocal) {
    final scene = _txCtrl.toScene(screenLocal);
    final col = (scene.dx / kCellSize).floor().clamp(0, kGridCols - 1);
    final row = (scene.dy / kCellSize).floor().clamp(0, kGridRows - 1);
    final hit = _hitTest(col, row);
    setState(() {
      _selectedId = hit?.id;
      _selectedType = hit?.buildingTypeId;
    });
  }

  void _handleDragStart(Offset screenLocal) {
    if (_selectedId == null) return;
    final scene = _txCtrl.toScene(screenLocal);
    final col = (scene.dx / kCellSize).floor().clamp(0, kGridCols - 1);
    final row = (scene.dy / kCellSize).floor().clamp(0, kGridRows - 1);
    final hit = _hitTest(col, row);
    if (hit?.id != _selectedId) {
      return; // drag didn't start on selected building
    }
    setState(() {
      _isDragging = true;
      _movingId = _selectedId;
      _movingType = _selectedType;
      _ghostX = hit!.gridX;
      _ghostY = hit.gridY;
    });
  }

  void _handleDragUpdate(Offset screenLocal) {
    if (!_isDragging || _movingType == null) return;
    final scene = _txCtrl.toScene(screenLocal);
    final def = kBuildingDefs[_movingType!]!;
    final col = (scene.dx / kCellSize).floor();
    final row = (scene.dy / kCellSize).floor();
    setState(() {
      _ghostX = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      _ghostY = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
    });
  }

  void _handleDragEnd() {
    if (!_isDragging ||
        _movingId == null ||
        _ghostX == null ||
        _ghostY == null) {
      setState(() {
        _isDragging = false;
      });
      return;
    }
    final id = _movingId!;
    final x = _ghostX!;
    final y = _ghostY!;
    setState(() {
      _isDragging = false;
      _movingId = null;
      _movingType = null;
      _ghostX = null;
      _ghostY = null;
      // _selectedId stays so the building remains selected after drop
    });
    widget.ctrl.moveBuilding(id, x, y).then((err) {
      if (err != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: FoE.danger),
        );
      }
    });
  }

  // ── Normal move helpers ───────────────────────────────────
  Future<void> _confirmPlacement(int x, int y, BuildingDef def) async {
    final err = await widget.ctrl.placeBuilding(widget.pendingTypeId!, x, y);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: FoE.danger));
    } else {
      widget.onPlacementDone?.call();
    }
    setState(() {
      _ghostX = null;
      _ghostY = null;
    });
  }

  Future<void> _confirmMove(int x, int y) async {
    final err = await widget.ctrl.moveBuilding(_movingId!, x, y);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: FoE.danger));
    }
    setState(() {
      _movingId = null;
      _movingType = null;
      _ghostX = null;
      _ghostY = null;
    });
  }

  void _cancelMove() => setState(() {
    _movingId = null;
    _movingType = null;
    _ghostX = null;
    _ghostY = null;
  });

  // ── Delete ────────────────────────────────────────────────
  void _showDeleteConfirmation() {
    final id = _selectedId;
    final type = _selectedType;
    if (id == null || type == null) return;
    final def = kBuildingDefs[type]!;
    showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 260,
          decoration: FoE.panel(radius: 12),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BuildingIcon(imageUrl: def.imageUrl, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Delete ${def.name}?',
                      style: FoE.title(size: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'This cannot be undone.',
                style: FoE.dim().copyWith(color: FoE.textDim),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _dialogBtn('Cancel', () => Navigator.pop(context, false)),
                  _dialogBtn(
                    'Delete',
                    () => Navigator.pop(context, true),
                    danger: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((confirmed) async {
      if (confirmed != true) return;
      setState(() {
        _selectedId = null;
        _selectedType = null;
        _isDragging = false;
        _movingId = null;
        _movingType = null;
        _ghostX = null;
        _ghostY = null;
      });
      await widget.ctrl.deleteBuilding(id);
    });
  }

  Widget _dialogBtn(String label, VoidCallback onTap, {bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: danger
                ? Colors.red.shade900.withValues(alpha: 0.4)
                : FoE.panelMid,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: danger ? Colors.red.shade700 : FoE.border,
            ),
          ),
          child: Text(
            label,
            style: FoE.label().copyWith(
              color: danger ? Colors.red.shade300 : FoE.textDim,
            ),
          ),
        ),
      );

  // ── Hit test ─────────────────────────────────────────────
  PlacedBuilding? _hitTest(int col, int row) {
    for (final b in widget.ctrl.buildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      if (col >= b.gridX &&
          col < b.gridX + def.gridW &&
          row >= b.gridY &&
          row < b.gridY + def.gridH) {
        return b;
      }
    }
    return null;
  }

  // ── Detail dialog (normal mode) ───────────────────────────
  void _showDetail(PlacedBuilding b) {
    final def = kBuildingDefs[b.buildingTypeId]!;
    showDialog(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: widget.ctrl,
        builder: (context, _) {
          // Re-derive the live building each rebuild — the `b` captured above
          // is a snapshot and goes stale the moment laborers are (re)assigned.
          final liveB = widget.ctrl.buildings.firstWhere(
            (x) => x.id == b.id,
            orElse: () => b,
          );
          final connected = widget.ctrl.connectedBuildingIds.contains(liveB.id);
          final functional = liveB.isComplete && connected;
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 260,
              decoration: FoE.panel(radius: 12),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BuildingIcon(imageUrl: def.imageUrl, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(def.name, style: FoE.title(size: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!liveB.isComplete) ...[
                    _BuildCountdown(ctrl: widget.ctrl, buildingId: liveB.id),
                    const SizedBox(height: 8),
                  ],
                  if (liveB.isComplete &&
                      !def.isRoad &&
                      !def.isMainBuilding &&
                      !connected) ...[
                    Row(
                      children: [
                        const Text('🚫', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Not connected to a road — not producing',
                            style: FoE.label().copyWith(
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (def.workshops.isNotEmpty) ...[
                    _workshopSection(liveB, def, functional),
                    const SizedBox(height: 8),
                  ],
                  ..._effectLines(def).map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.chevron_right,
                            color: FoE.gold,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Expanded(child: Text(l, style: FoE.label())),
                        ],
                      ),
                    ),
                  ),
                  // Creature-system buildings (Verzahnung): a finished,
                  // road-connected portal/breeding hut opens its feature
                  // right from the map.
                  if (functional && def.id == kDungeonPortalBuildingId) ...[
                    const SizedBox(height: 4),
                    _functionBtn('🏰 Enter Dungeon', () {
                      Navigator.pop(context);
                      showDungeonEntrySheet(context);
                    }),
                    const SizedBox(height: 8),
                  ],
                  if (functional && def.id == kBreedingHutBuildingId) ...[
                    const SizedBox(height: 4),
                    _functionBtn('🥚 Open Breeding', () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BreedingScreen(),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                  if (functional && def.id == kHealingHutBuildingId) ...[
                    const SizedBox(height: 4),
                    _functionBtn('❤️‍🩹 Heal all creatures', () async {
                      Navigator.pop(context);
                      await CreaturesController().healAll();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'All creatures fully healed!',
                              style: FoE.label(size: 13),
                            ),
                            backgroundColor: FoE.panelDark,
                          ),
                        );
                      }
                    }),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  Text('Hold to move', style: FoE.dim()),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 8,
                      ),
                      decoration: FoE.btn(),
                      child: Text('Close', style: FoE.label()),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Prominent gold action button for function buildings (portal/breeding).
  Widget _functionBtn(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: FoE.btn(active: true),
        alignment: Alignment.center,
        child: Text(
          label,
          style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
        ),
      ),
    ),
  );

  // ── Worker assignment (creature economy) ──────────────────
  // Each workshop role is staffed by SPECIFIC creatures; a role's output is
  // the sum of its workers' civilian stat, so the player picks who works where.
  Widget _workshopSection(PlacedBuilding b, BuildingDef def, bool functional) {
    final creatures = CreaturesController().creatures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final role in def.workshops)
          _workshopRole(b, role, functional, creatures),
      ],
    );
  }

  Widget _workshopRole(
    PlacedBuilding b,
    WorkshopRole role,
    bool functional,
    List<CreatureInstance> creatures,
  ) {
    final assigned = creatures
        .where((c) => c.assignedBuildingId == b.id && c.assignedStat == role.stat)
        .toList();
    final free = role.slots - assigned.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${role.stat.label} → ${role.resource}',
                  style: FoE.label(size: 12).copyWith(color: FoE.gold),
                ),
              ),
              Text('${assigned.length}/${role.slots}', style: FoE.dim(size: 11)),
            ],
          ),
          const SizedBox(height: 6),
          if (!functional)
            Text(
              'Connect to a road to staff this workshop',
              style: FoE.dim(size: 10).copyWith(color: Colors.redAccent),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in assigned) _workerChip(c, role.stat),
                if (free > 0) _addWorkerBtn(b, role),
              ],
            ),
        ],
      ),
    );
  }

  Widget _workerChip(CreatureInstance c, CreatureStat stat) {
    final idle = c.isKo || c.energy <= 0 || CreaturesController().isBreeding(c.id);
    return GestureDetector(
      onTap: () async {
        await widget.ctrl.assignCreatureToWorkshop(c.id, null, null);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: FoE.panelDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: idle ? Colors.redAccent : FoE.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${idle ? '💤 ' : ''}${c.displayName} · ${c.statValue(stat)}',
              style: FoE.label(size: 11).copyWith(
                color: idle ? Colors.redAccent : FoE.parchment,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.close, size: 12, color: FoE.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _addWorkerBtn(PlacedBuilding b, WorkshopRole role) => GestureDetector(
    onTap: () => _openAssignPicker(b, role),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: FoE.btn(active: true),
      child: Text(
        '+ Assign',
        style: FoE.label(size: 11).copyWith(color: FoE.goldBright),
      ),
    ),
  );

  // Picker: every creature, ranked by its aptitude for this role's stat, with
  // its current posting noted. Tapping (re)assigns it here.
  void _openAssignPicker(PlacedBuilding b, WorkshopRole role) {
    showDialog(
      context: context,
      builder: (_) => AnimatedBuilder(
        animation: widget.ctrl,
        builder: (context, _) {
          final creatures = [...CreaturesController().creatures]
            ..sort((x, y) =>
                y.statValue(role.stat).compareTo(x.statValue(role.stat)));
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 300,
              constraints: const BoxConstraints(maxHeight: 460),
              decoration: FoE.panel(radius: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Assign to ${role.stat.label}',
                    style: FoE.title(size: 15),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: creatures.isEmpty
                        ? Text('No creatures yet.', style: FoE.dim(size: 12))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final c in creatures) _pickerRow(b, role, c),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: FoE.btn(),
                      alignment: Alignment.center,
                      child: Text('Close', style: FoE.label(size: 12)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pickerRow(PlacedBuilding b, WorkshopRole role, CreatureInstance c) {
    final hereAlready =
        c.assignedBuildingId == b.id && c.assignedStat == role.stat;
    final elsewhere = c.isAssigned && !hereAlready;
    final idle = c.isKo || c.energy <= 0 || CreaturesController().isBreeding(c.id);
    return GestureDetector(
      onTap: hereAlready
          ? null
          : () async {
              final messenger = ScaffoldMessenger.of(context);
              final err =
                  await widget.ctrl.assignCreatureToWorkshop(c.id, b.id, role.stat);
              if (err != null) {
                messenger.showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: FoE.danger),
                );
              }
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hereAlready ? FoE.panelMid : FoE.panelDark,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hereAlready ? FoE.goldBright : FoE.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${idle ? '💤 ' : ''}${c.displayName}',
                    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                  ),
                  if (hereAlready)
                    Text('Working here', style: FoE.dim(size: 9))
                  else if (elsewhere)
                    Text('Reassign from elsewhere', style: FoE.dim(size: 9)),
                ],
              ),
            ),
            Text(
              '${role.stat.label} ${c.statValue(role.stat)}',
              style: FoE.value(size: 12).copyWith(color: FoE.goldBright),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _effectLines(BuildingDef def) {
    if (def.isRoad) return ['Connects buildings to the Main Hall'];
    if (def.isBuildPlot) {
      return ['Expanded your buildable territory by ${def.gridW}×${def.gridH}'];
    }
    final lines = <String>[];
    if (def.housingCapacity > 0) {
      lines.add('🏠 Shelters ${def.housingCapacity} creatures');
    }
    if (def.buildSpeedBonus > 0) {
      lines.add('+${(def.buildSpeedBonus * 100).toInt()}% Build speed');
    }
    if (def.populationBonus > 0) {
      lines.add('+${(def.populationBonus * 100).toInt()}% Housing capacity');
    }
    if (def.queueSlotsBonus > 0) {
      lines.add('+${def.queueSlotsBonus} build queue slot');
    }
    if (def.needGoodId != null) lines.add(_needLine(def));
    if (lines.isEmpty && def.workshops.isEmpty) {
      lines.add('Decorative building');
    }
    return lines;
  }

  // Describes a house's need + bonus and whether it's currently fulfilled.
  String _needLine(BuildingDef def) {
    final gDef = kGoodsDefs[def.needGoodId];
    final stock = widget.ctrl.resources?.goods[def.needGoodId] ?? 0;
    final fulfilled = stock > 0;
    final bonusParts = <String>[
      if (def.needPopulationBonus > 0)
        '+${(def.needPopulationBonus * 100).toInt()}% population',
      if (def.needWoodBonus > 0) '+${(def.needWoodBonus * 100).toInt()}% wood',
      if (def.needStoneBonus > 0)
        '+${(def.needStoneBonus * 100).toInt()}% stone',
      if (def.needGoldBonus > 0) '+${(def.needGoldBonus * 100).toInt()}% gold',
    ];
    final good = gDef != null ? '${gDef.emoji} ${gDef.name}' : def.needGoodId!;
    final consumption = def.needConsumptionPerHour > 0
        ? ' (drinks ${def.needConsumptionPerHour.toStringAsFixed(0)}/h)'
        : '';
    return '${fulfilled ? '✅' : '❌'} Needs $good in stock$consumption → ${bonusParts.join(', ')}';
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mapW = kGridCols * kCellSize;
    final mapH = kGridRows * kCellSize;
    final ghostTypeId = _inMoveMode ? _movingType! : widget.pendingTypeId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minScale = max(
          constraints.maxWidth / mapW,
          constraints.maxHeight / mapH,
        );
        final maxScale = max(minScale, 6.0);

        if (!_txInitialized) {
          _txInitialized = true;
          final tx = (constraints.maxWidth - mapW * minScale) / 2;
          final ty = (constraints.maxHeight - mapH * minScale) / 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _txCtrl.value = Matrix4.diagonal3Values(minScale, minScale, 1)
              ..setTranslationRaw(tx, ty, 0);
          });
        }

        // Overlay is active in edit mode whenever a building is selected (or being
        // dragged), and for the whole duration of road paint mode. It sits above
        // the InteractiveViewer and intercepts pan/tap for drag-and-drop / painting.
        // Without it, InteractiveViewer consumes pan events for scrolling.
        final showOverlay =
            (widget.editMode && (_selectedId != null || _isDragging)) ||
            widget.roadMode;

        return Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              minScale: minScale,
              maxScale: maxScale,
              transformationController: _txCtrl,
              child: MouseRegion(
                onHover: (e) => _handleHover(e.localPosition),
                child: GestureDetector(
                  onTapUp: (d) => _handleTap(d.localPosition),
                  onLongPressStart: (d) => _handleLongPress(d.localPosition),
                  child: SizedBox(
                    width: mapW,
                    height: mapH,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/images/map_background.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (_inMoveMode ||
                            _inPlaceMode ||
                            widget.editMode ||
                            widget.roadMode)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _GridPainter(
                                buildableRegion: widget.ctrl.buildableRegion,
                              ),
                            ),
                          ),
                        ...widget.ctrl.buildings.map((b) => _buildingTile(b)),
                        if (ghostTypeId != null &&
                            _ghostX != null &&
                            _ghostY != null)
                          _ghost(ghostTypeId, _ghostX!, _ghostY!),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Drag-and-drop / road-paint overlay — blocks InteractiveViewer pan
            if (showOverlay)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) {
                    if (widget.roadMode) {
                      _lastRoadKey = null;
                      _paintRoadAt(d.localPosition);
                    } else {
                      _handleOverlayTap(d.localPosition);
                    }
                  },
                  onPanStart: (d) {
                    if (widget.roadMode) {
                      _lastRoadKey = null;
                      _paintRoadAt(d.localPosition);
                    } else {
                      _handleDragStart(d.localPosition);
                    }
                  },
                  onPanUpdate: (d) {
                    if (widget.roadMode) {
                      _paintRoadAt(d.localPosition);
                    } else {
                      _handleDragUpdate(d.localPosition);
                    }
                  },
                  onPanEnd: (_) {
                    if (widget.roadMode) {
                      _lastRoadKey = null;
                    } else {
                      _handleDragEnd();
                    }
                  },
                  child: const SizedBox.expand(),
                ),
              ),

            // Road paint banner
            if (widget.roadMode)
              Positioned(top: 54, left: 10, right: 170, child: _roadBanner()),

            // Edit idle banner
            if (widget.editMode && !_inMoveMode)
              Positioned(
                top: 54,
                left: 10,
                right: 170,
                child: _editIdleBanner(),
              ),

            // Normal move banner
            if (_inMoveMode)
              Positioned(top: 54, left: 10, right: 170, child: _moveBanner()),

            // Delete X — pinned to selected building in screen space
            ?_buildDeleteButton(),
          ],
        );
      },
    );
  }

  // ── Building tile ─────────────────────────────────────────
  Widget _buildingTile(PlacedBuilding b) {
    final def = kBuildingDefs[b.buildingTypeId];
    if (def == null) return const SizedBox.shrink();
    final isSelected = widget.editMode && b.id == _selectedId && !_isDragging;
    final isGhostSrc = b.id == _movingId;
    final isDisconnected =
        b.isComplete &&
        !def.isRoad &&
        !def.isMainBuilding &&
        !widget.ctrl.connectedBuildingIds.contains(b.id);
    return Positioned(
      left: b.gridX * kCellSize,
      top: b.gridY * kCellSize,
      width: def.gridW * kCellSize,
      height: def.gridH * kCellSize,
      child: Opacity(
        opacity: isGhostSrc ? 0.3 : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _BuildingTile(def: def, building: b),
            if (isSelected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF4488FF),
                      width: 2,
                    ),
                    color: const Color(0x224488FF),
                  ),
                ),
              ),
            if (isDisconnected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent, width: 1.5),
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ),
            if (isDisconnected)
              const Positioned(
                top: 1,
                left: 1,
                child: Text('🚫', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ghost(String typeId, int gx, int gy) {
    final def = kBuildingDefs[typeId]!;
    final free = widget.ctrl.isPlacementValid(
      typeId,
      gx,
      gy,
      excludeId: _movingId,
    );
    return Positioned(
      left: gx * kCellSize,
      top: gy * kCellSize,
      width: def.gridW * kCellSize,
      height: def.gridH * kCellSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: (free ? Colors.greenAccent : Colors.redAccent).withValues(
                alpha: 0.22,
              ),
              border: Border.all(
                color: free ? Colors.greenAccent : Colors.redAccent,
                width: 2,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BuildingIcon(
              imageUrl: def.imageUrl,
              width: def.gridW * kCellSize,
              anchorBottomOverflowTop: true,
            ),
          ),
        ],
      ),
    );
  }

  // ── Delete button — screen-space, next to selected building ─
  Widget? _buildDeleteButton() {
    if (_selectedId == null || _selectedType == null) return null;
    final def = kBuildingDefs[_selectedType!]!;
    if (def.isMainBuilding) return null;

    double mapX, mapY;
    if (_isDragging && _ghostX != null && _ghostY != null) {
      mapX = (_ghostX! + def.gridW) * kCellSize;
      mapY = (_ghostY! + def.gridH / 2) * kCellSize;
    } else {
      final building = widget.ctrl.buildings
          .where((b) => b.id == _selectedId)
          .firstOrNull;
      if (building == null) return null;
      mapX = (building.gridX + def.gridW) * kCellSize;
      mapY = (building.gridY + def.gridH / 2) * kCellSize;
    }

    final screen = MatrixUtils.transformPoint(
      _txCtrl.value,
      Offset(mapX, mapY),
    );
    return Positioned(
      left: screen.dx + 4,
      top: screen.dy - 13,
      child: GestureDetector(
        onTap: _showDeleteConfirmation,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.red.shade700,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4)],
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 14),
        ),
      ),
    );
  }

  // ── Banners ───────────────────────────────────────────────
  Widget _roadBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: FoE.panel(
      radius: 8,
      overrideBorder: Colors.greenAccent.shade400,
    ),
    child: Row(
      children: [
        const Text('🛤️', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Drag to paint roads  ·  tap a road to remove it',
            style: FoE.label().copyWith(color: Colors.greenAccent),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: widget.onExitRoadMode,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0A2A16),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: Colors.greenAccent.shade400),
            ),
            child: Text(
              'Done',
              style: FoE.label(size: 11).copyWith(color: Colors.greenAccent),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _editIdleBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: FoE.panel(radius: 8, overrideBorder: const Color(0xFF4488FF)),
    child: Row(
      children: [
        const Icon(Icons.open_with, color: Color(0xFF88BBFF), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _selectedId != null
                ? 'Drag to move  ·  tap another or empty to change'
                : 'Tap a building to select it',
            style: FoE.label().copyWith(color: const Color(0xFF88BBFF)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedId = null;
              _selectedType = null;
            });
            widget.onExitEditMode?.call();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2E4A),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF4488FF)),
            ),
            child: Text(
              'Done',
              style: FoE.label(
                size: 11,
              ).copyWith(color: const Color(0xFF88BBFF)),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _moveBanner() {
    final def = kBuildingDefs[_movingType!]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: FoE.panel(radius: 8, overrideBorder: const Color(0xFF4488FF)),
      child: Row(
        children: [
          BuildingIcon(imageUrl: def.imageUrl, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tap to place ${def.name}  ·  Hold to cancel',
              style: FoE.label().copyWith(color: const Color(0xFF88BBFF)),
            ),
          ),
          GestureDetector(
            onTap: _cancelMove,
            child: const Icon(Icons.close, color: FoE.textDim, size: 16),
          ),
        ],
      ),
    );
  }
}

// ── Live build countdown ───────────────────────────────────
// showDialog builds its content once — the Dialog's own subtree never
// rebuilds on the controller's periodic ticks, so a plain Text would freeze
// at whatever the progress was when the dialog opened.
//
// Rather than decrementing a local counter once per second (which drifts
// against the controller's own 5s-authoritative tick — Dart's Timer.periodic
// can fire late under jank, and each resync would then have to "catch up",
// visibly jumping), this widget anchors to an absolute point in time
// (constructionSecondsBuilt as of energy.lastUpdatedAt) and recomputes the
// displayed value fresh from elapsed wall-clock time on every repaint. A 1s
// Timer only forces a repaint; it never mutates the displayed number itself.
// Resyncing (via ctrl.addListener) just moves the anchor to a newer snapshot
// — since both the anchor and the per-frame formula agree by construction,
// a resync only changes what's on screen if the real rate actually changed.
class _BuildCountdown extends StatefulWidget {
  final SettlementController ctrl;
  final String buildingId;
  const _BuildCountdown({required this.ctrl, required this.buildingId});

  @override
  State<_BuildCountdown> createState() => _BuildCountdownState();
}

class _BuildCountdownState extends State<_BuildCountdown> {
  Timer? _timer;
  bool _queued = false;
  bool _done = false;
  double _requiredGameSeconds = 0;
  // Anchor: authoritative built-seconds + real-worker rate as of _anchorTime.
  double _anchorBuiltGameSeconds = 0;
  double _rateGamePerRealSecond = 0; // 0 = stalled (no build energy)
  DateTime _anchorTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_resync);
    _resync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_resync);
    _timer?.cancel();
    super.dispose();
  }

  PlacedBuilding? get _building {
    for (final b in widget.ctrl.buildings) {
      if (b.id == widget.buildingId) return b;
    }
    return null;
  }

  void _resync() {
    final b = _building;
    if (b == null || b.isComplete) {
      _timer?.cancel();
      if (mounted) setState(() => _done = true);
      return;
    }
    if (b.isQueued) {
      setState(() => _queued = true);
      return;
    }
    final e = widget.ctrl.energy;
    double rate = 0;
    if (e != null && e.currentEnergy > 0) {
      final active = widget.ctrl.activeConstructionCount;
      rate =
          (widget.ctrl.buildRatePerHour / 3600.0) *
          widget.ctrl.buildSpeedMultiplier /
          (active > 0 ? active : 1);
    }
    setState(() {
      _queued = false;
      _requiredGameSeconds = b.constructionSecondsRequired;
      _anchorBuiltGameSeconds = b.constructionSecondsBuilt;
      _rateGamePerRealSecond = rate;
      _anchorTime = e?.lastUpdatedAt ?? DateTime.now().toUtc();
    });
  }

  // Extrapolates built-seconds forward from the anchor using real elapsed
  // time — the same linear formula GameEngine.tick() uses internally, so
  // this always agrees with the next authoritative tick (up to real rate
  // changes), never an accumulated drift.
  double get _builtNowGameSeconds {
    final elapsed =
        DateTime.now().toUtc().difference(_anchorTime).inMilliseconds / 1000.0;
    final built = _anchorBuiltGameSeconds + _rateGamePerRealSecond * elapsed;
    return built.clamp(0.0, _requiredGameSeconds);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return Text(
        'Complete!',
        style: FoE.dim(size: 11).copyWith(color: FoE.gold),
      );
    }
    final builtNow = _builtNowGameSeconds;
    final pct = _requiredGameSeconds <= 0
        ? 100
        : ((builtNow / _requiredGameSeconds) * 100).toInt();
    final remainingGameSeconds = _requiredGameSeconds - builtNow;
    final secondsLeft = _rateGamePerRealSecond > 0
        ? remainingGameSeconds / _rateGamePerRealSecond
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100.0,
            minHeight: 8,
            color: FoE.gold,
            backgroundColor: FoE.panelDark,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _queued
              ? 'In build queue — waiting for a free slot'
              : secondsLeft == null
              ? '$pct% — no build energy'
              : '$pct%  ·  ${fmtDuration(secondsLeft)} remaining',
          style: FoE.dim(size: 11).copyWith(color: FoE.gold),
        ),
      ],
    );
  }
}

// ── Building tile widget ──────────────────────────────────
class _BuildingTile extends StatelessWidget {
  final BuildingDef def;
  final PlacedBuilding building;
  const _BuildingTile({required this.def, required this.building});

  @override
  Widget build(BuildContext context) {
    if (def.isRoad) {
      return Container(
        margin: const EdgeInsets.all(0.5),
        decoration: BoxDecoration(
          color: def.color,
          border: Border.all(color: const Color(0xFF4A4438), width: 0.5),
        ),
      );
    }

    final done = building.isComplete;
    final queued = building.isQueued;
    final hasImage = def.imageUrl != null && def.imageUrl!.isNotEmpty;

    // An uploaded PNG is shown completely bare — no border, no background,
    // no inset — scaled so it touches the tile's left/right edges exactly
    // and sits flush against the bottom edge; if the art is taller than the
    // footprint it's allowed to overflow upward past the top (that's just
    // visual, matches the isometric-ish angle the art is drawn at).
    // clipBehavior: Clip.none on both this Stack and the one wrapping it in
    // _buildingTile() is what lets that overflow actually show instead of
    // being cut off. Buildings without an image yet keep the original
    // decorative box (a bare emoji/placeholder needs one to read well at
    // map scale).
    if (hasImage) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BuildingIcon(
              imageUrl: def.imageUrl,
              width: def.gridW * kCellSize,
              anchorBottomOverflowTop: true,
              dimmed: !done,
            ),
          ),
          ..._statusOverlays(done: done, queued: queued),
        ],
      );
    }

    final statusColor = done
        ? FoE.borderGold
        : (queued ? const Color(0xFFFF8C00) : FoE.border);
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: done
              ? [const Color(0xCC3C2E16), const Color(0xCC241A0A)]
              : [const Color(0xCC261E0E), const Color(0xCC181208)],
        ),
        border: Border(
          top: BorderSide(color: statusColor, width: 1.5),
          left: BorderSide(color: statusColor, width: 1.5),
          right: BorderSide(color: FoE.border, width: 1),
          bottom: BorderSide(color: FoE.border, width: 1),
        ),
        boxShadow: done
            ? [
                BoxShadow(
                  color: FoE.gold.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: BuildingIcon(size: 20, dimmed: !done),
            ),
          ),
          ..._statusOverlays(done: done, queued: queued),
        ],
      ),
    );
  }

  // Queued/in-progress indicators shared by both the bare-image and the
  // decorative-box rendering above.
  List<Widget> _statusOverlays({required bool done, required bool queued}) => [
    if (queued)
      const Positioned(
        top: 1,
        right: 1,
        child: Text('⏳', style: TextStyle(fontSize: 12)),
      ),
    if (!done && !queued)
      Positioned(
        bottom: 2,
        left: 2,
        right: 2,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: building.constructionProgress,
            minHeight: 3,
            color: FoE.gold,
            backgroundColor: FoE.panelDark,
          ),
        ),
      ),
  ];
}

// ── Grid painter ──────────────────────────────────────────
// Only draws over buildable cells — locked territory shows no grid marks
// at all, just the plain background.
class _GridPainter extends CustomPainter {
  final Set<int> buildableRegion;
  const _GridPainter({required this.buildableRegion});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (final key in buildableRegion) {
      final x = key % kGridCols, y = key ~/ kGridCols;
      canvas.drawRect(
        Rect.fromLTWH(x * kCellSize, y * kCellSize, kCellSize, kCellSize),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.buildableRegion != buildableRegion;
}
