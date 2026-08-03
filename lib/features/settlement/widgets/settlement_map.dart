import '../../../core/ui/feel.dart';
import 'dart:async';
import 'dart:math' show max;
import 'dart:math' as math;
import '../../../core/ui/duration_format.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/number_format.dart';
import '../../../core/ui/snack.dart';
import '../../creatures/models/area.dart' show kResourceEmoji;
import '../../creatures/widgets/creature_sprite.dart';
import '../../creatures/battle_screen.dart';
import '../../creatures/breeding_screen.dart';
import '../../creatures/expeditions_screen.dart';
import '../crafting_screen.dart';
import '../../creatures/hatchery_screen.dart';
import '../../creatures/healing_hut_screen.dart';
import '../../creatures/overworld_screen.dart';
import '../../creatures/models/combatant.dart';
import '../../creatures/models/creature_enums.dart'
    show
        CreatureRarity,
        creatureLevelCap,
        kBuilderCampBuildingId,
        kScoutPostBuildingId,
        kWorkshopBuildingId,
        kDungeonPortalBuildingId,
        kBreedingHutBuildingId,
        kHatcheryBuildingId,
        kHealingHutBuildingId,
        kTradingPostBuildingId,
        kTrainingGroundsBuildingId,
        kTrainingXpPerHour,
        workXpPerHourAt;
import '../../creatures/models/creature_instance.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/services/creatures_controller.dart';
import 'assign_workers_sheet.dart';
import '../data/building_definitions.dart';
import '../data/iso_grid.dart';
import '../data/resource_icons.dart';
import '../data/era_definitions.dart' show EraDef;
import '../data/goods_definitions.dart';
import '../data/workshop_role_effects.dart';
import '../sheets/building_upgrade_sheet.dart';
import '../models/placed_building.dart';
import '../sheets/population_overview_sheet.dart';
import '../market_screen.dart';
import '../management_screen.dart';
import '../settlement_controller.dart';
import 'building_icon.dart';
import 'meander_strip.dart';
import '../../common/widgets/recess_bar.dart';
import 'scroll_paper.dart'
    show
        kActionGreen,
        kParchmentLight,
        kParchmentMid,
        kParchmentDeep,
        kParchmentInk,
        parchmentButton,
        parchmentButtonInk;

/// The warm accent for labels on the building dialog's parchment (user
/// 2026-07-23): a burnt amber that reads on the cream where the app's light
/// golds would vanish. File-level so the dialog state and the standalone
/// _BuildCountdown widget share the one value.
const Color _kDlgAccent = FoE.gold;

class SettlementMap extends StatefulWidget {
  final SettlementController ctrl;
  final String? pendingTypeId;
  final bool editMode;
  final bool roadMode;
  final VoidCallback? onPlacementDone;

  /// Long-pressing a building asks the screen to turn move mode ON (user
  /// 2026-07-20). The mode is the screen's state, and it stays on until
  /// [onExitEditMode] — so one long-press lets you rearrange several buildings.
  final VoidCallback? onEnterEditMode;
  final VoidCallback? onExitEditMode;
  final VoidCallback? onExitRoadMode;

  /// The Builder Camp's dialog opens the Build menu (user 2026-07-29) — and the
  /// menu is the SCREEN's business, not the map's: what it returns puts the map
  /// into placement or road mode, which is state the screen owns.
  final VoidCallback? onOpenBuildMenu;

  /// A building the map should show as SELECTED — what a just-built one is set
  /// to (user 2026-07-30), so the drag that positions it needs no extra tap to
  /// pick it up first. Changing this value selects; null leaves the selection
  /// alone.
  final String? selectBuildingId;

  const SettlementMap({
    super.key,
    required this.ctrl,
    this.pendingTypeId,
    this.editMode = false,
    this.roadMode = false,
    this.onPlacementDone,
    this.onEnterEditMode,
    this.onExitEditMode,
    this.onExitRoadMode,
    this.onOpenBuildMenu,
    this.selectBuildingId,
  });

  @override
  State<SettlementMap> createState() => SettlementMapState();
}

// Public (not underscored) so the settlement screen can hold a
// GlobalKey<SettlementMapState> and route the tutorial's CTAs straight into
// a building's dialog — see openBuildingByType.
class SettlementMapState extends State<SettlementMap>
    with SingleTickerProviderStateMixin {
  // Training battle vs. 1-3 random wild creatures near the team's level.
  // Lives at the Training Grounds (user decision 2026-07-17, moved off the
  // Monsters screen): the place you train is the place you spar.
  Future<void> _startTrainingBattle() async {
    final creatures = CreaturesController();
    final team = creatures.battleTeam();
    if (team.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No battle-ready creature — all K.O.!',
            style: FoE.label(size: 13),
          ),
          backgroundColor: FoE.panelDark,
        ),
      );
      return;
    }
    final species = kSpeciesDefs.values.toList();
    if (species.isEmpty) return;
    final rng = math.Random();
    final avgLevel = (team.fold(0, (s, c) => s + c.level) / team.length)
        .round();
    final enemies = List.generate(
      1 + rng.nextInt(math.min(3, species.length)),
      (i) => Combatant.fromSpecies(
        species[rng.nextInt(species.length)],
        level: math.max(1, avgLevel - 1 + rng.nextInt(3)),
        id: 'e_$i',
        rng: rng,
      ),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: team,
          enemies: enemies,
          title: 'Training Battle',
        ),
      ),
    );
  }

  /// Opens the detail dialog of the first placed building of [typeId], as if
  /// the player had tapped it. The guided intro's cards use this so "tap the
  /// Tribal Center" is a lit button, not a search across the map.
  void openBuildingByType(String typeId) {
    for (final b in widget.ctrl.buildings) {
      if (b.buildingTypeId == typeId) {
        _showDetail(b);
        return;
      }
    }
  }

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

  // ── Bringing something into view (user 2026-07-30) ──────────
  // A building you just BUILT is placed for you, and the map is pannable and
  // zoomable — so it could easily land off-screen, leaving a "placed — drag it
  // where you want it" message pointing at nothing. The camera goes to it.
  late final AnimationController _panCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Animation<Matrix4>? _panAnim;

  /// The last viewport the map was laid out in — the focus maths needs it, and
  /// only [build] knows it.
  Size? _viewport;

  /// Pans (never zooms) so [b] sits in the middle, clamped to the map's edges so
  /// the move can never reveal the void beyond it. Keeping the zoom is
  /// deliberate: a camera that also re-scaled would take away the view the player
  /// had chosen.
  void focusBuilding(PlacedBuilding b) {
    final view = _viewport;
    final def = kBuildingDefs[b.buildingTypeId];
    if (view == null || def == null) return;
    final scale = _txCtrl.value.getMaxScaleOnAxis();
    final mapW = isoCanvasSize.width * scale;
    final mapH = isoCanvasSize.height * scale;
    // The building's own point on the diamond, not the middle of a rectangle.
    final centre = gridToScreen(
      b.gridX + def.gridW / 2,
      b.gridY + def.gridH / 2,
    );
    final cx = centre.dx * scale;
    final cy = centre.dy * scale;
    final tx = (view.width / 2 - cx)
        .clamp(math.min(0.0, view.width - mapW), 0.0)
        .toDouble();
    final ty = (view.height / 2 - cy)
        .clamp(math.min(0.0, view.height - mapH), 0.0)
        .toDouble();
    final target = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(tx, ty, 0);
    _panAnim = Matrix4Tween(begin: _txCtrl.value, end: target).animate(
      CurvedAnimation(parent: _panCtrl, curve: Curves.easeOutCubic),
    );
    _panCtrl
      ..reset()
      ..forward();
  }

  @override
  void didUpdateWidget(SettlementMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear edit selection when leaving edit mode
    if (!widget.editMode && oldWidget.editMode) {
      _selectedId = null;
      _selectedType = null;
      _isDragging = false;
      _movingId = null;
      _movingType = null;
      _ghostX = null;
      _ghostY = null;
    }
    if (!widget.roadMode && oldWidget.roadMode) {
      _lastRoadKey = null;
    }
    // A JUST-BUILT building arrives selected (user 2026-07-30), so the very next
    // gesture can drag it where you want it. Only on CHANGE: re-selecting on
    // every rebuild would fight the player's own taps.
    final fresh = widget.selectBuildingId;
    if (fresh != null && fresh != oldWidget.selectBuildingId) {
      for (final b in widget.ctrl.buildings) {
        if (b.id != fresh) continue;
        _selectedId = b.id;
        _selectedType = b.buildingTypeId;
        // …and BRING IT INTO VIEW. The map is pannable and zoomable, so a
        // building placed for you can be well off-screen; "drag it where you
        // want it" then points at nothing. After the frame, because the focus
        // maths needs the viewport this build is about to report.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) focusBuilding(b);
        });
        break;
      }
    }
  }

  @override
  void dispose() {
    _panCtrl.dispose();
    _txCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The tween writes straight into the transform controller, so the pan runs
    // through the same matrix the player's own gestures use.
    _panCtrl.addListener(() {
      final anim = _panAnim;
      if (anim != null) _txCtrl.value = anim.value;
    });
  }

  // ── Tap inside InteractiveViewer (normal + edit-idle) ─────
  void _handleTap(Offset local) {
    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(local);

    if (_inMoveMode) {
      final def = kBuildingDefs[_movingType!]!;
      final x = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      final y = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
      _confirmMove(x, y);
      return;
    }

    if (_inPlaceMode) {
      final def = kBuildingDefs[widget.pendingTypeId!]!;
      var x = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      var y = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
      (x, y) = widget.ctrl.snapPlacement(widget.pendingTypeId!, x, y);
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

    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(local);
    final hit = _hitTest(col, row);
    if (hit == null) return;
    // Build plots are permanent — no move (see settlement_controller).
    if (kBuildingDefs[hit.buildingTypeId]?.isBuildPlot ?? false) return;
    // Open the PERSISTENT move mode with this building already selected (user
    // 2026-07-20). It used to start a one-shot move that ended the moment the
    // building was dropped; now the mode belongs to the screen and stays up
    // until Done, so you can rearrange several in a row.
    setState(() {
      _selectedId = hit.id;
      _selectedType = hit.buildingTypeId;
    });
    widget.onEnterEditMode?.call();
  }

  void _handleHover(Offset local) {
    if (!_inMoveMode && !_inPlaceMode) return;
    final typeId = _inMoveMode ? _movingType! : widget.pendingTypeId!;
    final def = kBuildingDefs[typeId]!;
    final (col, row) = screenToGrid(local);
    var gx = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
    var gy = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
    // Build plots snap the ghost to the 5×5 grid so the preview sits exactly
    // where placement will land.
    (gx, gy) = widget.ctrl.snapPlacement(typeId, gx, gy);
    setState(() {
      _ghostX = gx;
      _ghostY = gy;
    });
  }

  // ── Road paint mode (screen-space coordinates) ─────────────
  // Tapping/dragging over an empty cell paints a road; over an existing
  // road it erases it; over any other building it's a no-op. Free, instant.
  void _paintRoadAt(Offset screenLocal) {
    final scene = _txCtrl.toScene(screenLocal);
    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(scene);
    final key = row * kGridCols + col;
    if (key == _lastRoadKey) return;
    _lastRoadKey = key;

    final hit = _hitTest(col, row);
    if (hit != null && hit.buildingTypeId == 'road') {
      // Errors were dropped on the floor here, which is why "roads can't be
      // deleted" looked like nothing happening at all rather than a refusal.
      _report(widget.ctrl.deleteBuilding(hit.id));
    } else if (hit == null) {
      _report(widget.ctrl.placeBuilding('road', col, row));
    }
  }

  /// Surfaces a controller error, if any. Painting fires on every dragged
  /// cell, so this stays quiet on success — only a refusal speaks.
  Future<void> _report(Future<String?> action) async {
    final err = await action;
    if (err == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err, style: FoE.label(size: 12)),
        backgroundColor: FoE.danger,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Edit-mode overlay handlers (screen-space coordinates) ──
  void _handleOverlayTap(Offset screenLocal) {
    final scene = _txCtrl.toScene(screenLocal);
    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(scene);
    final hit = _hitTest(col, row);
    setState(() {
      _selectedId = hit?.id;
      _selectedType = hit?.buildingTypeId;
    });
  }

  void _handleDragStart(Offset screenLocal) {
    if (_selectedId == null) return;
    final scene = _txCtrl.toScene(screenLocal);
    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(scene);
    final hit = _hitTest(col, row);
    if (hit?.id != _selectedId) {
      return; // drag didn't start on selected building
    }
    // Build plots are permanent — no drag-to-move.
    if (kBuildingDefs[hit!.buildingTypeId]?.isBuildPlot ?? false) return;
    setState(() {
      _isDragging = true;
      _movingId = _selectedId;
      _movingType = _selectedType;
      _ghostX = hit.gridX;
      _ghostY = hit.gridY;
    });
  }

  void _handleDragUpdate(Offset screenLocal) {
    if (!_isDragging || _movingType == null) return;
    final scene = _txCtrl.toScene(screenLocal);
    final def = kBuildingDefs[_movingType!]!;
    final (col, row) = screenToGrid(scene);
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
    Feel.place();
    widget.ctrl.moveBuilding(id, x, y).then((err) {
      if (err != null && mounted) {
        Feel.deny();
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
          decoration: ShapeDecoration(color: danger
                ? Colors.red.shade900.withValues(alpha: 0.4)
                : FoE.panelMid, shape: FoE.facet(radius: 6, side: BorderSide(color: danger ? Colors.red.shade700 : FoE.border))),
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
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 24,
            ),
            child: Stack(
              // Clip.none twice over (here and in the scroll view): the art is
              // bottom-anchored in its slot and must be free to rise past the
              // dialog's top edge, the way the build-menu cards do.
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 400,
                  // The build menu's PARCHMENT is the dialog surface too (user
                  // 2026-07-23) — one warm visual language for both places you
                  // look at a building.
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [kParchmentLight, kParchmentMid],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Ornament FIRST — it is wallpaper, so it belongs behind
                      // the content and never over a line of text (user
                      // 2026-07-22).
                      Positioned(
                        left: 14,
                        top: 0,
                        bottom: 0,
                        width: 16,
                        child: MeanderStrip(color: _dlgOrnament),
                      ),
                      Positioned(
                        right: 14,
                        top: 0,
                        bottom: 0,
                        width: 16,
                        child: MeanderStrip(color: _dlgOrnament, flip: true),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              clipBehavior: Clip.none,
                              // Wide side padding: the meander bands live in that
                              // margin, so the text must keep clear of it.
                              padding: const EdgeInsets.fromLTRB(
                                36,
                                14,
                                36,
                                14,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // ── Hero: art (rising out of the card), name, level
                                  //    pill, what it does ───────────────────────────
                                  // Footprint + level + XP/state now live in the hero masthead
                                  // (user 2026-07-24) — the separate stat-chip box is gone.
                                  _heroRow(liveB, def, functional),
                                  const SizedBox(height: 10),
                                  // Under construction: the countdown replaces the
                                  // production card entirely — nothing is produced yet.
                                  if (!liveB.isComplete)
                                    _sectionCard(
                                      title: 'Under construction',
                                      child: _BuildCountdown(
                                        ctrl: widget.ctrl,
                                        buildingId: liveB.id,
                                      ),
                                    )
                                  else
                                    // ── Effects: base output, housing, who works here, total ──
                                    // (user 2026-07-24: a house's gold + housing are EFFECTS, so
                                    // the card is "Effects", not just "Production".)
                                    _sectionCard(
                                      title: 'Effects',
                                      child: _productionSection(
                                        liveB,
                                        def,
                                        functional,
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  // Crafting recipe + the notes that belong to a staffed
                                  // building (the workers themselves live in the production
                                  // card above).
                                  if (liveB.isComplete &&
                                      def.workshops.isNotEmpty) ...[
                                    _workshopExtras(liveB, def, functional),
                                    const SizedBox(height: 8),
                                  ],
                                  // ── Upgrade: what it buys, cost inside the button ──
                                  if (liveB.isComplete &&
                                      widget.ctrl.isUpgradable(def)) ...[
                                    _sectionCard(
                                      title: 'Upgrade',
                                      // Small right-aligned peek at the effects at MAX level
                                      // (user 2026-07-24) — replaces the big bottom button.
                                      //
                                      // In a GREEN CIRCLE (user 2026-07-26: "damit man sieht,
                                      // dass es ein Button ist"). A bare glyph on parchment
                                      // reads as decoration next to a heading; the settlement's
                                      // action green is what everything tappable already wears,
                                      // so the circle is the whole affordance.
                                      trailing: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => showBuildingUpgradeSheet(
                                          context,
                                          def,
                                        ),
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: const BoxDecoration(
                                            color: kActionGreen,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.query_stats,
                                            size: 15,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      child: _upgradeSection(liveB, def),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  // Housing lives HERE, not in the top bar (user decision
                                  // 2026-07-17): the Tribal Center is the settlement's
                                  // administrative heart, so its dialog owns the population
                                  // overview. isMainBuilding, not connectivity — the hall IS
                                  // the road network's root and never needs a connection.
                                  // Era ascension (user 2026-07-22): unlocked by the region
                                  // boss, performed and PAID here — the hall is where the
                                  // settlement itself levels up.
                                  if (liveB.isComplete &&
                                      def.isMainBuilding &&
                                      widget.ctrl.ascendableEra != null) ...[
                                    const SizedBox(height: 4),
                                    _ascendButton(
                                      context,
                                      widget.ctrl.ascendableEra!,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  // ── What this building lets you DO ─────────────
                                  _actionArea(context, liveB, def, functional),
                                  // THE thing it is for, LAST (user 2026-07-27):
                                  // the biggest button on the card, at the foot
                                  // of it, so the dialog ends on the way in
                                  // rather than on a row of numbers.
                                  for (final action in _primaryActions(
                                    context,
                                    liveB,
                                    def,
                                    functional,
                                  )) ...[
                                    const SizedBox(height: 12),
                                    action,
                                  ],
                                  const SizedBox(height: 2),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // No ✕ (user 2026-07-22) — the level sits where it used to
                // be; tapping outside the dialog closes it.
              ],
            ),
          );
        },
      ),
    );
  }

  /// The era-ascension action (user 2026-07-22): names the target era, shows
  /// the full cost, refuses with the reason. Gold accent — this is the biggest
  /// button the settlement has.
  Widget _ascendButton(BuildContext context, EraDef nextEra) {
    final cost = widget.ctrl.eraAscensionCost(nextEra.order);
    final stock = widget.ctrl.resources?.asMap ?? const {};
    final afford = cost.entries.every((e) => (stock[e.key] ?? 0) >= e.value);
    final costLabel = cost.entries
        .map(
          (e) =>
              '${kGoodsDefs[e.key]?.emoji ?? kResourceEmoji[e.key] ?? e.key} '
              '${e.value.toInt()}',
        )
        .join('  ');
    return GestureDetector(
      onTap: () async {
        final err = await widget.ctrl.ascendEra();
        if (!context.mounted) return;
        if (err != null) {
          context.snack(err, error: true);
        } else {
          Navigator.pop(context);
          context.snack(
            '🏛 Welcome to ${nextEra.name}! Monsters can now reach '
            'Lv ${creatureLevelCap(nextEra.order)}.',
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: parchmentButton(active: afford),
        child: Column(
          children: [
            Text(
              // "Chapter", not a date: eras are stages of this settlement's
              // rise, not centuries (see era_definitions.dart).
              '${nextEra.emoji} Begin Chapter ${nextEra.order} · '
              '${nextEra.name}',
              style: FoE.label(size: 13).copyWith(
                color: parchmentButtonInk(active: afford),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Cost: $costLabel · monsters up to '
              'Lv ${creatureLevelCap(nextEra.order)}',
              style: FoE.dim(size: 10).copyWith(
                color: afford ? parchmentButtonInk(active: true) : FoE.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Detail dialog pieces (reference layout, user 2026-07-22) ─
  /// The recess a section sits in — a shade sunk into the parchment (user
  /// 2026-07-23), so a grouped block reads as a pressed panel rather than a
  /// second colour.
  static final Color _dlgInset = kParchmentDeep.withValues(alpha: 0.55);

  /// One grouped block of the dialog (user 2026-07-22, modern pass): a titled
  /// recess. Grouping is what turned a long run of loose rows into something
  /// scannable — production, upgrade and construction each own a card.
  Widget _sectionCard({
    required Widget child,
    String? title,
    Widget? trailing,
  }) => Container(
    padding: EdgeInsets.fromLTRB(12, title == null ? 12 : 9, 12, 12),
    decoration: ShapeDecoration(color: _dlgInset, shape: FoE.facet(radius: 14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: FoE.dim(size: 9).copyWith(
                    color: _dlgInkFaint,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // A small right-aligned action for the section (e.g. the Upgrade
              // card's "effects at full upgrade" peek, user 2026-07-24).
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
        ],
        child,
      ],
    ),
  );

  /// Art, name, what the building does, level and footprint — the card's
  /// masthead. The footprint (2×2) and the XP/state sit UNDER the level (user
  /// 2026-07-24), which retired the separate stat-chip box; the description
  /// reads BETWEEN the art and that column (user 2026-07-26) rather than as a
  /// full-width line beneath both.
  Widget _heroRow(PlacedBuilding b, BuildingDef def, bool functional) {
    final lines = _effectLines(def).join(' · ');
    // XP/h a worker earns here: the training rate, else the settlement-wide
    // work rate — EVERY building that stations monsters pays it (user
    // 2026-07-30), so this pill is now on every staffed building instead of the
    // eleven that happened to carry an `xp` effect.
    final xpRate = def.workshops.isEmpty
        ? 0.0
        : def.workshops.any((w) => w.resource == WorkshopRole.kTraining)
        ? kTrainingXpPerHour
        : workXpPerHourAt(b.level);
    final (String, Color)? status = !b.isComplete
        ? ('Building', _dlgAccent)
        : !functional
        ? ('No road', FoE.danger)
        : xpRate > 0
        ? ('${xpRate.toStringAsFixed(0)} XP/h', _dlgInk)
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _artPanel(def),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          def.name,
                          style: FoE.title(size: 16).copyWith(color: _dlgInk),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // WHAT IT DOES sits here — between the art and the
                        // size column (user 2026-07-26) — rather than as a
                        // full-width line under the whole masthead. Two lines
                        // at most: it is a caption for the picture, and a
                        // third line pushed the size/level block out of view.
                        Text(
                          lines.isEmpty
                              ? 'A building of your settlement.'
                              : lines,
                          style: FoE.dim(size: 10).copyWith(color: _dlgInkSoft),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Level, then footprint, then XP/state — right-aligned.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // The hall shows its level too (user 2026-07-25): it
                      // isn't upgradable by hand, but it gains a level with
                      // every era — i.e. every region boss — so the number is
                      // real progress the player earned.
                      if (widget.ctrl.isUpgradable(def) || def.isMainBuilding)
                        _levelPill(b.level),
                      // The FOOTPRINT, smaller and with its own icon (user
                      // 2026-07-26). At the level pill's size a bare "4×4"
                      // competed with the level for the eye; shrunk and
                      // labelled, it reads as the aside it is.
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.grid_on, size: 10, color: _dlgInkSoft),
                            const SizedBox(width: 3),
                            Text(
                              '${def.gridW}×${def.gridH}',
                              style: FoE.dim(
                                size: 9,
                              ).copyWith(color: _dlgInkSoft),
                            ),
                          ],
                        ),
                      ),
                      if (status != null)
                        Text(
                          status.$1,
                          style: FoE.value(size: 11).copyWith(color: status.$2),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Just the level, no box (user 2026-07-23) — plain accent text.
  Widget _levelPill(int level) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      'Lv $level',
      style: FoE.label(
        size: 12,
      ).copyWith(color: _dlgAccent, fontWeight: FontWeight.w800),
    ),
  );

  /// Everything this building lets you DO, in one place at the foot of the
  /// card (user 2026-07-22, modern pass). The features are compact PILLS in a
  /// wrap — a stack of full-width buttons made a Tribal Center dialog scroll
  /// for no reason. The two that carry live numbers (healing's price, the
  /// build-skip toll) stay full width, because that number is the decision.
  /// A building can be paused when it RUNS something: a work post, or a
  /// worker-free `production` effect. Everything else has nothing to stop.
  bool _canPause(BuildingDef def) =>
      def.workshops.isNotEmpty || def.effectKeys('production').isNotEmpty;

  Widget _actionArea(
    BuildContext context,
    PlacedBuilding b,
    BuildingDef def,
    bool functional,
  ) {
    final pills = <Widget>[
      // ── PAUSE (user 2026-08-01: "ich will gebäude pausieren können") ──
      // Only for buildings that actually RUN something. Pausing a house or a
      // store would be a switch with nothing behind it: housing and storage are
      // what a building is, not what it does, and they keep counting either way.
      if (b.isComplete && _canPause(def))
        _actionPill(
          b.isPaused ? '▶' : '⏸',
          b.isPaused ? 'Resume' : 'Pause',
          () => widget.ctrl.setPaused(b.id, !b.isPaused),
        ),
      if (b.isComplete && def.isMainBuilding)
        _actionPill(
          '🏠',
          'Population ${widget.ctrl.housingUsed}/${widget.ctrl.housingCapacity}',
          () {
            Navigator.pop(context);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => PopulationOverviewSheet(ctrl: widget.ctrl),
            );
          },
        ),
      // The building's OWN feature is not here any more (user 2026-07-27: "der
      // Breeding button muss viel prominenter sein, da dies die hauptfunktion
      // ist") — it leads the dialog instead, see [_primaryAction].
    ];
    final wide = <Widget>[
      // Any building still under construction can be bought out.
      if (!b.isComplete) _skipBuildButton(context, b),
    ];
    if (pills.isEmpty && wide.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pills.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: pills),
        for (final w in wide) ...[
          SizedBox(height: pills.isEmpty && w == wide.first ? 0 : 10),
          w,
        ],
      ],
    );
  }

  Widget _actionPill(String emoji, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: parchmentButton(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                label,
                style: FoE.label(
                  size: 12,
                ).copyWith(color: parchmentButtonInk()),
              ),
            ],
          ),
        ),
      );

  /// THE thing this building is FOR — one big green button at the head of the
  /// dialog (user 2026-07-27: "der Breeding button muss viel prominenter sein,
  /// da dies die hauptfunktion ist. Bitte für andere Gebäude mit ähnlichen
  /// Funktionen übernehmen").
  ///
  /// It used to be a small pill in a wrap at the very bottom, under Effects and
  /// Upgrade — so the Breeding Hut's dialog opened with its worker roster and
  /// buried the one control the building exists for. Every building whose whole
  /// point is a screen or a sheet now leads with it, in the same green the
  /// Upgrade button wears.
  ///
  /// Returns null for a building with no such feature (a plain producer), and
  /// for one that is not [functional] yet — an unfinished or unconnected
  /// building cannot open anything.
  /// A LIST since 2026-07-30 (user: "Worker Verwaltung über Tribal Center und
  /// Population über jedes Haus aufrufbar machen"): a building can lead to more
  /// than one thing — the Tribal Center shelters monsters AND runs the workforce
  /// — and the old single-return shape could only ever offer the first of them.
  List<Widget> _primaryActions(
    BuildContext context,
    PlacedBuilding b,
    BuildingDef def,
    bool functional,
  ) {
    if (!functional) return const [];
    final (String, VoidCallback)? action = switch (def.id) {
      // A SCREEN now, like every other building feature (user 2026-07-27: "ich
      // will alle verletzten Monster angezeigt bekommen und einzelne heilen
      // können"). It was a live widget right here, because "heal everybody for
      // one price" fits on a button — a list of the wounded with a price each
      // does not.
      kHealingHutBuildingId => (
        'Healing Hut',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HealingHutScreen()),
        ),
      ),
      kDungeonPortalBuildingId => (
        'Overworld',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OverworldScreen()),
        ),
      ),
      kBreedingHutBuildingId => (
        'Breeding',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BreedingScreen()),
        ),
      ),
      // Incubating and hatching belong to the HATCHERY (user 2026-07-26: "ein
      // ei ausbrüten muss zu der hatchery"), so the building opens them the
      // same way the Breeding Hut opens mating.
      kHatcheryBuildingId => (
        'Hatchery',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HatcheryScreen()),
        ),
      ),
      // A SCREEN, like the Hatchery and the Breeding Hut (user 2026-07-27) —
      // the Market was the last building feature that still opened as a sheet.
      kTradingPostBuildingId => (
        'Market',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MarketScreen()),
        ),
      ),
      // The place you train is the place you spar (user decision 2026-07-17:
      // moved off the Monsters screen).
      kTrainingGroundsBuildingId => ('Training battle', _startTrainingBattle),
      // The camp houses the builders, so it is a door to the Build menu (user
      // 2026-07-29: "das build menü soll auch durch das build camp aufrufbar
      // sein") — the same menu the corner pad opens, not a second one.
      kBuilderCampBuildingId when widget.onOpenBuildMenu != null => (
        'Build',
        widget.onOpenBuildMenu!,
      ),
      // The post grants the expedition slots and shortens every trip, so it is
      // where the trips live (user 2026-07-29: "Trips soll über den Scoutpost
      // erreichbar sein").
      // The workbench is a SCREEN now (user 2026-07-29) — a recipe has a cost,
      // a duration, an effect and a stock, and none of those fit on the chip
      // the dialog used to offer it as.
      kWorkshopBuildingId => (
        'Crafting',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CraftingScreen()),
        ),
      ),
      kScoutPostBuildingId => (
        'Expeditions',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExpeditionsScreen()),
        ),
      ),
      _ => null,
    };
    final actions = <(String, VoidCallback)>[if (action != null) action];
    void open(int tab) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ManagementScreen(initialTab: tab)),
    );
    // THE TRIBAL CENTER RUNS THE WORKFORCE (user 2026-07-30). Who works where was
    // reachable only from the Manage screen's second tab — a settlement-wide
    // decision with no door in the settlement. The hall is where that door
    // belongs: it is the one building that is about the whole place.
    if (def.isMainBuilding) actions.add(('Workers', () => open(1)));
    // AND EVERY HOUSE OPENS THE POPULATION BUDGET. Keyed on what a building DOES
    // — shelters monsters — not on a list of ids, so a new dwelling in a later
    // era gets the door by being a dwelling (the same rule housingCapacity
    // counts by). The Tribal Center shelters too, so it offers both.
    if (def.sheltersMonsters(widget.ctrl.settlement?.eraIndex ?? 1)) {
      actions.add(('Population', () => open(2)));
    }
    return [
      for (final (label, onTap) in actions)
        _primaryActionButton(label, () {
          Navigator.pop(context);
          onTap();
        }),
    ];
  }


  /// The prominent form: full width, tall, the settlement's action green, with
  /// a chevron so it reads as "this opens something".
  ///
  /// NO emoji (user 2026-07-27) — the label names the feature, and the chevron
  /// is the whole affordance.
  Widget _primaryActionButton(String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: parchmentButton(),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: FoE.title(
                    size: 16,
                  ).copyWith(color: parchmentButtonInk()),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 22,
                color: parchmentButtonInk().withValues(alpha: 0.85),
              ),
            ],
          ),
        ),
      );

  /// The building art, free-standing — no tile box behind it (user
  /// 2026-07-22). Bottom-anchored in a fixed slot so taller art rises out of
  /// the dialog's top edge, exactly like the build-menu cards.
  Widget _artPanel(BuildingDef def) => SizedBox(
    width: 140,
    // Deliberately much shorter than the art is wide: the sprite is
    // bottom-anchored, so a short slot is what PUSHES it up and out over the
    // dialog's top edge (user 2026-07-22).
    height: 72,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // Standing on its cast shadow — the same look as the build-menu
          // card (user 2026-07-23), one definition in ShadowedBuildingIcon.
          child: Center(
            child: ShadowedBuildingIcon(imageUrl: def.imageUrl, width: 140),
          ),
        ),
      ],
    ),
  );

  // ── Ink on the detail dialog's PARCHMENT surface ──────────
  // The dialog wears the build menu's parchment now (user 2026-07-23), so its
  // ink is the paper's own dark brown in three weights — the app's white would
  // vanish on it, exactly the reverse of the old blue tile.
  static const Color _dlgInk = kParchmentInk;
  static final Color _dlgInkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _dlgInkFaint = kParchmentInk.withValues(alpha: 0.55);

  /// Ornament ink (the meander bands) — a shade you notice only when you look
  /// for it. Anything stronger and the frame competes with the content.
  static final Color _dlgOrnament = kParchmentInk.withValues(alpha: 0.22);

  /// The warm ACCENT for labels on the parchment (user 2026-07-23) — see
  /// [_kDlgAccent]. Buttons keep goldBright: they wear the dark FoE.btn
  /// surface, so the light gold still pops there.
  static const Color _dlgAccent = _kDlgAccent;

  /// A system role's contribution. The wording lives in
  /// workshop_role_effects.dart, shared with the build menu, the upgrade sheet
  /// and the Dev-Mode preview.
  ///
  /// NO GLYPH unless the value needs one to say WHICH system it belongs to
  /// (user 2026-07-27: "icon bei der Reduktion löschen (−n%)"). On a worker's
  /// row the post above already names the role, and on a single-role building
  /// so does the whole dialog — there the 🩹 beside "−25 %" was decoration.
  /// Only the Total line of a building with SEVERAL system roles (the Scout
  /// Post's travel/carry/goods) keeps it, because there three bare percentages
  /// would sit side by side with nothing to tell them apart.
  static String _systemRoleValue(
    String res,
    double power, {
    bool withGlyph = false,
  }) =>
      withGlyph
          ? '${workshopRoleEffect(res, power)} ${workshopRoleEmoji(res)}'
          : workshopRoleEffect(res, power);

  /// One resource/role glyph — kResourceEmoji is the app-wide source, goods
  /// bring their own, and the three non-resource role keys get their own icon.
  String _resEmoji(String res) => switch (res) {
    WorkshopRole.kConstruction => '🔨',
    WorkshopRole.kCrafting => '⚗️',
    WorkshopRole.kTraining => '🏋️',
    WorkshopRole.kLegendaryBoost => '⭐',
    // ONE table decides (user 2026-07-30) — see resource_icons.dart for why
    // this used to disagree with the header for `fur`.
    _ => resourceEmoji(res),
  };

  /// A resource key's display NAME (for the row label): a good's own name, the
  /// capitalised raw, or a friendly name for the pseudo outputs.
  /// Role keys are named by what they DO (shared vocabulary); anything else is
  /// a real resource and keeps its own name.
  String _resLabel(String res) =>
      workshopRoleName(res) ??
      kGoodsDefs[res]?.name ??
      (res.isEmpty ? 'Resource' : res[0].toUpperCase() + res.substring(1));

  /// Production block (user 2026-07-22): the worker-independent BASE line
  /// first, then one row per stationed monster with what THAT monster adds on
  /// the right, and a "+" under the last worker to post another.
  Widget _productionSection(
    PlacedBuilding b,
    BuildingDef def,
    bool functional,
  ) {
    final ctrl = CreaturesController();
    // Same math workshopPower uses, scoped to one building: level yield.
    final f = buildingYieldFactor(b.level);
    final rows = <Widget>[];

    // Running per-resource tally: base first, every present worker on top —
    // what the Total line at the foot reports.
    final total = <String, double>{};
    void add(String res, double v) => total[res] = (total[res] ?? 0) + v;

    /// The civil-service / breeder posts, tallied apart from the stockpile:
    /// their power is a fraction or a time cut, so it can neither be added to
    /// nor printed like a resource (see [_systemRoleValue]).
    final systemPower = <String, double>{};

    /// "+4.5/h 🪵" per produced resource — the icon sits AFTER the value (user
    /// 2026-07-24), ONE LINE EACH (user 2026-07-27: several outputs on a single
    /// row ran the card's whole width and read as one long number).
    ///
    /// Construction is counted in BUILD POINTS, not units per hour — the unit
    /// it is authored in and the one a builder's stat is measured in (user
    /// 2026-07-26). Printing it "/h" made a builder's 30 look like 30 wood.
    List<String> amounts(Map<String, double> m) => m.entries
        .where((e) => e.value > 0)
        .map(
          (e) => e.key == WorkshopRole.kConstruction
              ? '+${e.value.toStringAsFixed(0)} points ${_resEmoji(e.key)}'
              : '+${e.value.toStringAsFixed(1)}/h ${_resEmoji(e.key)}',
        )
        .toList();

    /// Label left, value(s) right — stacked, right-aligned, one per line. With
    /// more than one line the label rides at the TOP of the stack so it still
    /// reads as that block's heading.
    Widget headline(String label, List<String> values, {Color? color}) => Row(
      crossAxisAlignment: values.length > 1
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(label, style: FoE.label(size: 12).copyWith(color: _dlgAccent)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in values)
                Text(
                  v,
                  textAlign: TextAlign.end,
                  style: FoE.value(size: 12).copyWith(color: color ?? _dlgInk),
                ),
            ],
          ),
        ),
      ],
    );

    // PAUSED SAYS SO FIRST (user 2026-08-01). The figures below stay — they are
    // what the building WOULD make — and this line is why none of it is
    // happening, in the same place the empty-tank warning lands.
    if (b.isPaused) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '⏸ Paused — producing and consuming nothing. Housing and storage '
            'still count.',
            style: FoE.dim(size: 11).copyWith(color: FoE.danger),
          ),
        ),
      );
    }

    // ── Base: what it makes with nobody stationed ──
    // ONLY its authored `production` effects (user 2026-07-25) — the code-side
    // base table, the hall's automatic build points and the house-gold curve
    // are gone, so this panel and the economy read the same numbers.
    final era = widget.ctrl.settlement?.eraIndex ?? 1;
    final base = <String, double>{};
    for (final res in def.effectKeys('production')) {
      final v = def.effectAt('production', res, era, level: b.level);
      if (v != 0) base[res] = (base[res] ?? 0) + v;
    }
    base.forEach(add);
    // Label the row by WHAT it makes: the single resource's name ("Gold",
    // "Wood"), else the generic "Resource" (user 2026-07-24, was "Base").
    final baseLabel = base.length == 1
        ? _resLabel(base.keys.first)
        : 'Resource';
    // A STORE makes nothing, so "Resource —" was a row saying so, directly
    // above the four rows that are the building's entire point (user
    // 2026-07-30). Suppressed for exactly that case: nothing produced, and a
    // ceiling to show instead.
    final storageKeys = def.effectKeys('storage').toList();
    if (!(base.isEmpty && functional && storageKeys.isNotEmpty)) {
      rows.add(
        headline(
          baseLabel,
          !functional
              ? const ['offline']
              : base.isEmpty
              ? const ['—']
              : amounts(base),
          color: !functional
              ? FoE.danger
              : base.isEmpty
              ? _dlgInkFaint
              : _dlgInk,
        ),
      );
    }
    // ── What it can HOLD ──
    // One heading, then the resource and the bare number (user 2026-07-30:
    // "«Ressource» zu «Storage» ändern, dafür überall sonst storage löschen" +
    // "Gib nur die Zahl, ohne Max und ohne Icon"). It used to repeat
    // "Storage · " on every row and add "max" and a glyph to every value —
    // four ways of saying the same thing, four times over.
    if (storageKeys.isNotEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: Text(
            buildingEffectLabel('storage'),
            style: FoE.label(size: 12).copyWith(color: _dlgAccent),
          ),
        ),
      );
      // The staff's room is part of the ceiling this store actually has (user
      // 2026-07-30), so it is part of the number on the row — with the split
      // spelled out, because one of the two halves is a decision you can make
      // right now. PER RESOURCE, because the post's dials are: the same worker
      // can be worth more room in timber than in fur. Only when somebody is
      // really working: the same rule storageCapacity applies (an unconnected
      // store counts for nothing).
      for (final key in storageKeys) {
        if (def.effectEntry('storage', key, era) == null) continue;
        final v = buildingEffectValueAt(def, 'storage', key, era, b.level);
        final posted =
            functional ? widget.ctrl.storageRoomPosted(b, key) : 0.0;
        rows.add(
          headline(
            _resLabel(key),
            [
              formatBuildingEffect('storage', key, v + posted),
              if (posted > 0)
                '${formatBuildingEffect('storage', key, v)} + '
                    '${shortNumberAbove(posted)} 👷',
            ],
            color: functional ? _dlgInk : _dlgInkFaint,
          ),
        );
      }
    }
    // A production key authored but worth NOTHING at this level is missing from
    // the base row above (it lists amounts, and there is no amount). It is still
    // one of the building's effects, so it gets the same "from Lv N" row every
    // other pending effect gets (user 2026-07-30).
    for (final res in def.effectKeys('production')) {
      if (def.effectEntry('production', res, era) == null) continue;
      if (def.effectAt('production', res, era, level: b.level) != 0) continue;
      final at = firstLevelWithEffect(def, 'production', res, era);
      rows.add(
        headline(
          _resLabel(res),
          [at != null ? 'from Lv $at ${_resEmoji(res)}' : '—'],
          color: _dlgInkFaint,
        ),
      );
    }
    // Housing capacity (a count, not a /h rate — its own row; icon after the
    // value, user 2026-07-24). A housing effect that starts at 0 and arrives at
    // a level says so, rather than being dropped.
    final housing = def.hasEffect('housing', era)
        ? def.effectAt('housing', '', era, level: b.level)
        : def.housingCapacity * f;
    if (housing > 0) {
      rows.add(headline('Housing', ['${housing.round()} 🏠']));
    } else if (def.hasEffect('housing', era)) {
      final at = firstLevelWithEffect(def, 'housing', '', era);
      rows.add(
        headline(
          'Housing',
          [at != null ? 'from Lv $at 🏠' : '0 🏠'],
          color: _dlgInkFaint,
        ),
      );
    }

    // ── EVERY OTHER AUTHORED EFFECT, IN ITS OWN UNIT ──
    // The card printed production and housing and stopped. So a Scout Post —
    // whose entire job is granting expedition slots and hunt lengths — had an
    // Effects card that listed nothing, and the Caravanserai, the Builder Camp
    // and the Healing Hut were all in the same position: the effect worked, it
    // was simply never said out loud.
    //
    // Read through buildingEffectValueAt so a row cannot promise a curve the
    // runtime does not apply, and named/formatted from the shared vocabulary,
    // so a slot count reads "1 🧭" and a travel cut reads "−10 % travel".
    // Storage has its own grouped block above, so it is left out here.
    for (final row in buildingEffectCardRows(def, era, b.level)) {
      rows.add(
        headline(
          row.label,
          [row.value],
          color: !functional || row.pending ? _dlgInkFaint : _dlgInk,
        ),
      );
    }

    // ── Workers: who is posted here and what each one adds ──
    //
    // The section heading only exists to TOTAL several posts. With one post it
    // said exactly what that post's own header says, one line apart — "Workers
    // 1/2" twice over (user 2026-07-26: "doppelt gemoppelt"). A building with
    // one post gets the per-post row alone, and that row is the heading.
    if (def.workshops.length > 1) {
      final totalSlots = def.workshops.fold<int>(
        0,
        (sum, role) => sum + effectiveSlots(role, b.level),
      );
      final totalStaffed = ctrl.creatures
          .where((c) => c.assignedBuildingId == b.id)
          .length;
      rows
        ..add(const SizedBox(height: 10))
        ..add(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workers',
                  style: FoE.label(size: 12).copyWith(color: _dlgAccent),
                ),
              ),
              Text(
                '$totalStaffed/$totalSlots',
                style: FoE.value(
                  size: 11,
                ).copyWith(color: functional ? _dlgInk : _dlgInkFaint),
              ),
            ],
          ),
        );
    }
    var trainees = 0;
    for (final role in def.workshops) {
      final assigned = ctrl.creatures
          .where(
            (c) => c.assignedBuildingId == b.id && c.assignedStat == role.stat,
          )
          .toList();
      final slotCap = effectiveSlots(role, b.level);
      final training = role.resource == WorkshopRole.kTraining;
      // A legendary-boost slot: a stationed legendary multiplies the building's
      // production by (1 + mult), regardless of its stats (user 2026-07-24).
      final boost = role.resource == WorkshopRole.kLegendaryBoost;
      rows.add(const SizedBox(height: 8));
      // The post's header: what it is, how full it is, and the way IN. Editing
      // used to be a separate centred button under the worker list (user
      // 2026-07-26: "das edit menü für die workers soll irgendwie und irgendwo
      // auf die Zeile von Workers und n/n kommen") — the count and the control
      // that changes it belong together, and it saves a whole row per post.
      //
      // It renders for a single-post building too now. It used to be hidden
      // there because the label only repeated the description; carrying the
      // seat count and the edit affordance, it earns its line.
      //
      // And it NAMES the post even when there is only one (user 2026-07-30:
      // every effect a building has must be readable off this card). A bare
      // "Workers 0/1" was the one place the card said nothing: an empty Scout
      // Post never mentioned travel or carrying, an empty Healing Hut never
      // mentioned healing time. What the post feeds is a fact about the
      // BUILDING, so it does not wait for somebody to be posted in it.
      rows.add(
        _workerHeaderRow(
          b: b,
          role: role,
          // JUST THE STAT (user 2026-07-30: "Production -> Fur bitte nur
          // Production schreiben. Bei allen Gebäuden übernehmen"). The row
          // already carries what it makes, twice over: the value on the right
          // ends in the resource's own glyph, and the whole block sits under the
          // heading that names it. "Production → Fur  1/1  +3.5/h 🦫" said "fur"
          // three times on one line.
          //
          // Training and the legendary slot keep their arrow: neither is a
          // stat→resource pair, and their left side alone would name nothing.
          label: training
              ? 'Training → XP'
              : boost
              ? '⭐ Legendary → ×${(1 + role.mult).toStringAsFixed(1)}'
              : role.stat.label,
          count: '${assigned.length}/$slotCap',
          enabled: functional,
        ),
      );
      // A COMBINED post feeds several systems at once, and its name can only be
      // the trip as a whole ("Expedition", "Caravan"). So it spells the parts
      // out — with no monster posted there is nothing else on the card that
      // would (user 2026-07-30). Parts dialled to zero are left out: they do
      // nothing, and the row is about what this post actually improves.
      if (role.isCombined) {
        final parts = [
          for (final p in role.parts.entries)
            if ((role.mults[p.key] ?? 0) != 0)
              '${workshopRoleEmoji(p.value)} '
              '${workshopRoleName(p.value) ?? p.value}',
        ];
        if (parts.isNotEmpty) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'Improves ${parts.join(' · ')}',
                style: FoE.dim(size: 10).copyWith(color: _dlgInkSoft),
              ),
            ),
          );
        }
      }
      // WHAT A MONSTER GETS OUT OF STANDING HERE (user 2026-07-26: "bei den
      // Production gebäude werden die xp für die Monster noch nicht
      // angezeigt"). The building-wide XP pill in the masthead only appears
      // when SOMETHING pays, so a production post said nothing at all — and
      // "nothing shown" and "nothing paid" looked identical.
      //
      // Same rule the runtime uses (CreaturesController.xpRatePerHour): the
      // training rate in a training post, else the settlement-wide work rate.
      // It shows on the LEGENDARY-BOOST post too (user 2026-07-30: "jedes
      // Gebäude, welches Monster anstellt soll EP geben") — a legendary parked
      // in a special building is stationed like anyone else and earns like
      // anyone else, and this row was the one that used to deny it.
      final postXp = training
          ? kTrainingXpPerHour
          : workXpPerHourAt(b.level);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            postXp > 0
                ? '✨ ${postXp.toStringAsFixed(0)} XP/h each'
                : '✨ No XP — this post does not level anyone',
            style: FoE.dim(
              size: 10,
            ).copyWith(color: postXp > 0 ? _dlgInkSoft : _dlgInkFaint),
          ),
        ),
      );
      if (!functional) {
        rows.add(
          Text(
            'Connect to a road to staff this workshop',
            style: FoE.dim(size: 10).copyWith(color: FoE.danger),
          ),
        );
        continue;
      }
      for (final c in assigned) {
        rows.add(_workerRow(c, role, b.level, training, boost, storageKeys));
        // Only monsters that are actually HERE contribute — same rule
        // _workerRow shows and workshopPower applies.
        // Same predicate the economy uses — the row and the total can no longer
        // disagree about who is working (user 2026-07-30).
        if (!ctrl.isWorkingNow(c)) continue;
        // A STORE post is already fully stated by the Storage rows above (base
        // + 👷, per resource), and its room has no single figure to total — one
        // dial per resource is the point (user 2026-07-30). Repeating it under
        // "Total" would be the same numbers a second time, and a wrong one: the
        // flat mult is only the fallback.
        if (role.resource == WorkshopRole.kStorageRoom) continue;
        // The runtime's own per-worker formula, including its per-role level
        // scaling — so the displayed output is what banks, and a COMBINED post
        // lands in all three of its buckets here exactly as it does in
        // workshopPower (user 2026-07-29).
        final contribution = role.contribution(
          (s) => c.statValue(s).toDouble(),
          b.level,
        );
        if (training || boost) {
          // Training pays XP; a legendary boost multiplies the building's
          // production — neither adds a resource line here.
          if (training) trainees++;
        } else if (workshopRoleFeedsSystem(role.resource)) {
          // Feeds a SYSTEM, not the storehouse: summed apart so the Total line
          // never reports "+60/h 📦" for a breeder post (user 2026-07-26).
          for (final out in contribution.entries) {
            systemPower[out.key] = (systemPower[out.key] ?? 0) + out.value;
          }
        } else {
          // One formula for every post (2026-07-26). Construction differs only
          // in its UNIT — build points, the same unit the building's passive
          // `production`/`construction` is authored in, so the two share this
          // tally.
          add(role.resource, contribution[role.resource] ?? 0);
        }
      }
      // (The way in moved UP to this post's header row — user 2026-07-26.)
    }

    // ── Was dafür verbrannt wird (user 2026-07-31) ──
    // "clay rafinery soll anzeigen, welche Ressourcen verbraucht werden, um die
    // neue herzustellen"
    //
    // Read off the SAME tally the Total prints, so the two halves of the trade
    // can never drift apart: 7 Timber Frame an hour is 14 wood and 14 stone an
    // hour, and if the rate changes the burn changes with it.
    final recipes = refiningRecipes([
      ...def.effectKeys('production'),
      for (final r in def.workshops) r.resource,
    ]);
    final burn = refiningInputsPerHour({
      for (final id in recipes.keys) id: total[id] ?? 0,
    });
    // AN EMPTY INPUT STOCK PRODUCES NOTHING — the same rule the tick applies
    // (GameEngine._tickGoods caps output at what the inputs cover), and the same
    // lie the energy fix removed: a card promising +7/h with no wood in the yard.
    final res = widget.ctrl.resources;
    final starved = <String>[
      if (res != null)
        for (final input in {for (final r in recipes.values) ...r.keys})
          if (res.amountOf(input) <= 0) input,
    ];

    // ── Total: base + everyone working, the number the settlement banks ──
    if (def.workshops.isNotEmpty) {
      final parts = <String>[
        if (functional && total.isNotEmpty) ...amounts(total),
        if (functional && trainees > 0)
          '🏋️ +${(trainees * kTrainingXpPerHour).toStringAsFixed(0)} XP/h',
        // The system roles' SUMMED power, which is the figure the game really
        // uses — one breeder's 25 % and another's 25 % are not 50 %.
        if (functional)
          for (final e in systemPower.entries)
            _systemRoleValue(
              e.key,
              e.value,
              withGlyph: systemPower.length > 1,
            ),
      ];
      // AN EMPTY TANK PRODUCES NOTHING (user 2026-07-30: "fur lodge produziert
      // 3.5 pro Stunde, oben wird mir dies aber nicht angezeigt").
      //
      // The header was right and this card was the one lying: with the energy at
      // zero every rate the settlement banks is multiplied by the "Produktion bei
      // leerem Tank" dial, which is 0 — so the top bar read +0.0/h while this
      // card promised +3.5/h and never mentioned why the two disagreed. The
      // figures above stay (they are what the building CAN do); the Total says
      // what it currently banks, which is nothing.
      final halted = functional && parts.isNotEmpty &&
          (b.isPaused || !widget.ctrl.hasEnergy || starved.isNotEmpty);
      final haltReason = b.isPaused
          ? '0/h · paused'
          : !widget.ctrl.hasEnergy
              ? '0/h · no energy'
              : '0/h · no ${starved.map(_resLabel).join(' / ')}';
      rows
        ..add(const SizedBox(height: 8))
        ..add(
          headline(
            'Total',
            !functional
                ? const ['offline']
                : halted
                ? [haltReason]
                : parts.isEmpty
                ? const ['—']
                : parts,
            color: !functional || halted
                ? FoE.danger
                : parts.isEmpty
                ? _dlgInkFaint
                : _dlgInk,
          ),
        );
    }

    if (recipes.isNotEmpty) {
      rows
        ..add(const SizedBox(height: 8))
        ..add(
          headline(
            'Consumes',
            burn.isEmpty
                // Nothing is being made, so nothing is being burned — the RULE
                // is still the point of the building, and it is on the line
                // below.
                ? const ['—']
                : [
                    for (final e in burn.entries)
                      '−${e.value.toStringAsFixed(1)}/h ${_resEmoji(e.key)}',
                  ],
            color: burn.isEmpty ? _dlgInkFaint : _dlgInk,
          ),
        );
      // The recipe itself, per unit — what the burn above is derived from, and
      // the only line that is true whether or not anybody is posted here.
      for (final e in recipes.entries) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${e.value.entries.map((i) => '${_num(i.value)} '
                  '${_resEmoji(i.key)}').join(' + ')}'
                  ' → 1 ${_resEmoji(e.key)}',
              textAlign: TextAlign.end,
              style: FoE.dim(size: 11),
            ),
          ),
        );
      }
      if (starved.isNotEmpty && functional) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Out of ${starved.map(_resLabel).join(' and ')} — nothing is '
                  'being refined.',
              style: FoE.dim(size: 11).copyWith(color: FoE.danger),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  /// A recipe amount: "2", not "2.0".
  String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// One stationed monster: sprite + name left, ITS hourly contribution right.
  /// Read-only — posting and un-posting both happen in the Edit sheet below
  /// (user 2026-07-22, the ✕ per row is gone).
  Widget _workerRow(
    CreatureInstance c,
    WorkshopRole role,
    int level,
    bool training, [
    bool boost = false,
    /// The resources this building STORES — what a store post's per-resource
    /// dials are read for (user 2026-07-30). Empty for every other post.
    List<String> storageKeys = const [],
  ]) {
    final ctrl = CreaturesController();
    // WHY it is not working, in its own words (user 2026-07-30: "wie kann ein
    // Monster als idle angestellt sein? Entweder arbeitet es hier, oder ist nicht
    // in diesem Gebäude").
    //
    // The row said "💤 idle" for two completely different situations — knocked
    // out, and away in the Breeding Hut — which reads as a monster that is
    // employed and lazy. It is neither: it holds the post and cannot man it right
    // now, and WHICH of those it is decides what you would do about it.
    //
    // The post is held ON PURPOSE (the same rule as an expedition, see
    // SettlementController._postedRole): a K.O. lasts minutes and a mating hours,
    // and dropping the job would mean re-staffing every building in the
    // settlement after every lost fight. So the honest fix is to say the reason,
    // not to invent a third state.
    final absence = c.isKo
        ? '💀 K.O. — heal it'
        : ctrl.isBreeding(c.id)
        ? '🥚 in the Breeding Hut'
        : ctrl.isOnExpedition(c.id)
        ? '🎒 away on a trip'
        : c.isHealing
        ? '🩺 under treatment'
        : null;
    final absent = absence != null;
    // Only a LEGENDARY actually boosts; a lesser creature parked here is inert.
    final legendary = c.species?.rarity == CreatureRarity.legendary;
    // Construction is shown in POINTS, not in the build-seconds they convert to
    // (2026-07-26); the formula itself is the same as every other post's.
    final construction = role.resource == WorkshopRole.kConstruction;
    // Everything this one monster is worth here — one entry for an ordinary
    // post, three for the Scout Post's combined one.
    final contribution = role.contribution(
      (s) => c.statValue(s).toDouble(),
      level,
    );
    final contrib = contribution[role.resource] ?? 0;
    // A STORE post is worth a different amount of room in each good it holds
    // (user 2026-07-30), so "the" figure for this worker does not exist — it is
    // one line per resource, named by the resource's own glyph. Read through the
    // role's own formula, so the row cannot disagree with the ceiling above it.
    final storeRoom = role.resource == WorkshopRole.kStorageRoom
        ? [
            for (final key in storageKeys)
              '+${role.storageRoomFor(key, c.statValue(role.stat).toDouble(), level).round()} '
                  '${_resEmoji(key)}',
          ]
        : const <String>[];
    final value = absence ??
        (storeRoom.isNotEmpty
        ? storeRoom.first
        : boost
        ? (legendary
              ? '⭐ ×${(1 + role.mult).toStringAsFixed(1)}'
              : '⚠ not legendary')
        : training
        ? '+${kTrainingXpPerHour.toStringAsFixed(0)} XP/h'
        : construction
        ? '+${contrib.toStringAsFixed(0)} points 🔨'
        // A system role's contribution is a cut or a bonus, not an hourly
        // amount — and it is only meaningful TOGETHER with its colleagues'
        // (the cut is soft-capped over the summed power), so the row shows
        // what this one monster is worth ALONE and the Total line adds them up.
        : workshopRoleFeedsSystem(role.resource)
        // A combined post says all three of its parts, each with its glyph —
        // that IS the row's content, and one bare percentage could only be one
        // of the three (user 2026-07-29). They are STACKED below, not joined.
        ? workshopPowerLabel(contribution, withGlyph: role.isCombined)
        // Icon after the value (user 2026-07-24).
        : '+${contrib.toStringAsFixed(1)}/h ${_resEmoji(role.resource)}');
    // The stacked form of that same value. A combined post and a STORE post have
    // more than one line; every other row keeps its single [value] string.
    final lines = absent || training || boost || construction
        ? const <String>[]
        : storeRoom.isNotEmpty
        ? storeRoom
        : workshopRoleFeedsSystem(role.resource)
        ? workshopPowerParts(contribution, withGlyph: role.isCombined)
        : const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: c.imageUrl == null
                ? Icon(Icons.pets, size: 18, color: _dlgAccent)
                : CreatureSprite(
                    url: c.imageUrl!,
                    fallback: Icon(Icons.pets, size: 18, color: _dlgAccent),
                  ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              training ? '${c.displayName} · Lv ${c.level}' : c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 12).copyWith(color: _dlgInk),
            ),
          ),
          // Stacked when the post feeds several systems at once, so each
          // amplifier is its own line instead of one long run-on figure
          // (user 2026-07-29). Right-aligned, so the numbers line up under
          // each other rather than drifting with the glyph widths.
          if (lines.length > 1)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final l in lines)
                  Text(
                    l,
                    style: FoE.value(size: 11).copyWith(color: _dlgInk),
                  ),
              ],
            )
          else
            Text(
              value,
              style: FoE.value(
                size: 11,
              ).copyWith(color: absent ? _dlgInkFaint : _dlgInk),
            ),
        ],
      ),
    );
  }

  /// Buy out the rest of a construction. Priced on the REAL remaining wait
  /// (see SettlementController.buildSkipCost), so a nearly-finished building
  /// is nearly free and one with nobody working on it is not.
  Widget _skipBuildButton(BuildContext context, PlacedBuilding b) {
    final ctrl = SettlementController();
    final cost = ctrl.buildSkipCost(b);
    final canPay = ctrl.gold >= cost;
    return _functionBtn(
      canPay
          ? '🪙 Finish now · $cost'
          : '🪙 $cost (you have ${ctrl.gold.toInt()})',
      () async {
        if (!canPay) return;
        Navigator.pop(context);
        final err = await ctrl.skipBuildWithGold(b);
        if (!context.mounted || err == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(err, style: FoE.label(size: 13)),
            backgroundColor: FoE.danger,
          ),
        );
      },
    );
  }

  /// The building's worker-INDEPENDENT outputs at [level] — its `production`
  /// effects plus housing capacity: the numbers an upgrade actually moves (user
  /// 2026-07-24). Housing uses the sentinel key '__housing' (a count, not a /h
  /// rate).
  ///
  /// `construction` STAYS (user 2026-07-26: "das soll die passive Construction
  /// sein") — it is real, level-scaled build power, just measured in points; it
  /// is only the truly inert keys (crafting/training/legendary slots, which
  /// nothing reads worker-free) that are dropped.
  Map<String, double> _passiveOutputs(BuildingDef def, int level) {
    final era = widget.ctrl.settlement?.eraIndex ?? 1;
    final f = buildingYieldFactor(level);
    final m = <String, double>{};
    for (final res in def.effectKeys('production')) {
      final v = def.effectAt('production', res, era, level: level);
      if (v != 0) m[res] = (m[res] ?? 0) + v;
    }
    final housing = def.hasEffect('housing', era)
        ? def.effectAt('housing', '', era, level: level)
        : def.housingCapacity * f;
    if (housing > 0) m[kHousingOutputKey] = housing;
    m.removeWhere(
      (k, v) =>
          v <= 0 ||
          k == WorkshopRole.kCrafting ||
          k == WorkshopRole.kTraining ||
          k == WorkshopRole.kLegendaryBoost,
    );
    return m;
  }

  // ── Level upgrade ─────────────────────────────────────────
  /// One "label … now → next 🏠" row of the upgrade table.
  ///
  /// Only ever built for a number the level actually MOVES (user 2026-07-26:
  /// "nur anzeigen, wenn es effektiv auch etwas ändert, Stats die gleich
  /// bleiben, sollen nicht angezeigt werden") — the caller filters. At max
  /// level there is no next value, so the row states the current one.
  Widget _upgradeLineRow({
    required String label,
    required String emoji,
    required String now,
    required String next,
    required bool atMax,
    bool onlyNext = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      children: [
        Text(label, style: FoE.label(size: 12).copyWith(color: _dlgAccent)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            // [emoji] may be empty — the worker/effect rows name themselves on
            // the left and carry no icon (user 2026-07-27).
            (atMax || onlyNext
                    ? '${onlyNext && !atMax ? next : now} $emoji'
                    : '$now  →  $next $emoji')
                .trimRight(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: FoE.value(size: 12).copyWith(color: _dlgInk),
          ),
        ),
      ],
    ),
  );

  /// Shows what this level yields, what the next one does to it, the cost and
  /// build time, and the upgrade button. See building_definitions' level
  /// scaling for the curves behind the numbers.
  Widget _upgradeSection(PlacedBuilding b, BuildingDef def) {
    final atMax =
        b.level >=
        maxBuildingLevelFor(def, widget.ctrl.settlement?.eraIndex ?? 1);
    final target = b.level + 1;
    final stock = widget.ctrl.resources?.asMap ?? {};
    final afford = !atMax && def.canAffordAt(target, stock);

    // The EFFECTIVE outputs this level vs the next (user 2026-07-24: show the
    // concrete numbers, not a % increase). Housing rides the '__housing' key.
    final now = _passiveOutputs(def, b.level);
    final next = _passiveOutputs(def, target);
    final outKeys = buildingOutputOrder(def, {...now.keys, ...next.keys});
    String fmtOut(String k, double? v) {
      final val = v ?? 0;
      if (k == kHousingOutputKey) return val.round().toString();
      // Passive construction is points, like a builder's stat (2026-07-26).
      if (k == WorkshopRole.kConstruction) {
        return '${val.toStringAsFixed(0)} points';
      }
      return '${val.toStringAsFixed(1)}/h';
    }

    // What a level does to the WORK POSTS (a production building's whole
    // output rides on these) AND to every other authored effect — a Builder
    // Camp's "+1 build site at level 3" used to be nowhere in this panel, so a
    // level whose entire point was that bonus looked like it bought nothing
    // (user 2026-07-26).
    final era = widget.ctrl.settlement?.eraIndex ?? 1;
    final workLines = [
      ...workshopUpgradeLines(def, b.level, target),
      ...buildingEffectUpgradeLines(def, b.level, target, era),
    ];

    // ONLY what the level moves (user 2026-07-26: "nur anzeigen, wenn es
    // effektiv auch etwas ändert, Stats die gleich bleiben, sollen nicht
    // angezeigt werden"). A "5 → 5" row costs a line of the panel to say
    // nothing, and three of them bury the one number that did change.
    //
    // At MAX level there is no next value to compare against, so the panel
    // keeps stating what the building currently yields.
    final movedKeys = atMax
        ? outKeys
        : [
            for (final k in outKeys)
              if ((now[k] ?? 0) != (next[k] ?? 0)) k,
          ];
    final movedWork = atMax
        ? const <UpgradeLine>[]
        : workLines.where((l) => l.changed).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One row per output, current → next, in the same table shape as the
          // Base/Total lines above ("Output %" removed, user 2026-07-24).
          // Same shape as the Effects card (user 2026-07-24): the resource/
          // effect label on the LEFT, the numbers (now → next) then the icon on
          // the far RIGHT.
          for (final k in movedKeys)
            _upgradeLineRow(
              label: k == kHousingOutputKey ? 'Housing' : _resLabel(k),
              emoji: k == kHousingOutputKey ? '🏠' : _resEmoji(k),
              now: fmtOut(k, now[k]),
              next: fmtOut(k, next[k]),
              atMax: atMax,
            ),
          // Worker slots and per-worker yield, after the outputs: the outputs
          // are WHAT it makes, these are what makes them.
          for (var i = 0; i < movedWork.length; i++) ...[
            // The group heading, printed once when it changes — "Storage" over
            // its per-resource rows (user 2026-07-30).
            if (movedWork[i].group != null &&
                (i == 0 || movedWork[i - 1].group != movedWork[i].group))
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 3),
                child: Text(
                  movedWork[i].group!,
                  style: FoE.label(size: 12).copyWith(color: _dlgAccent),
                ),
              ),
            _upgradeLineRow(
              label: movedWork[i].label,
              // NO trailing icon here (user 2026-07-27: "icons rechts entfernen
              // für xp und workers"). A resource row needs its emoji — that is
              // what says WHICH resource — but "Workers" and "XP" already say
              // what they are on the left, so the glyph was decoration.
              emoji: '',
              now: movedWork[i].now,
              next: movedWork[i].next,
              atMax: false,
              onlyNext: movedWork[i].onlyNext,
            ),
          ],
          // With everything filtered out the panel would be a bare button, and
          // "no rows" reads as a rendering fault rather than as an answer.
          if (!atMax && movedKeys.isEmpty && movedWork.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                'This level changes no values — only the cost.',
                style: FoE.dim(size: 11).copyWith(color: _dlgInkSoft),
              ),
            ),
          const SizedBox(height: 8),
          if (atMax)
            Text(
              'Maximum level reached.',
              style: FoE.dim(size: 11).copyWith(color: _dlgInkSoft),
            )
          else
            // Cost and build time live INSIDE the button (user 2026-07-22) —
            // the price is part of the offer, not a caption above it.
            GestureDetector(
              onTap: afford ? () => _doUpgrade(b.id) : null,
              child: Opacity(
                opacity: afford ? 1 : 0.5,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: parchmentButton(active: afford),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Upgrade',
                        style: FoE.label(
                          size: 13,
                        ).copyWith(color: parchmentButtonInk(active: afford)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_resCostLabel(def.resourceCostAt(target))}   '
                        '⏱ ${fmtDuration(def.constructionSecondsAt(target))}',
                        textAlign: TextAlign.center,
                        style: FoE.dim(size: 10).copyWith(
                          color: afford
                              ? parchmentButtonInk(active: true)
                              : FoE.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _doUpgrade(String buildingId) async {
    final messenger = ScaffoldMessenger.of(context);
    final err = await widget.ctrl.upgradeBuilding(buildingId);
    if (!mounted) return;
    if (err != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(err), backgroundColor: FoE.danger),
      );
    } else {
      Navigator.pop(context); // close dialog; the building is now rebuilding
    }
  }

  /// "🪵 320  🪨 96" — resource cost with emojis (wood/stone/gold + goods).
  String _resCostLabel(Map<String, double> cost) => cost.entries
      .map((e) {
        const base = {'wood': '🪵', 'stone': '🪨', 'gold': '🪙'};
        final emoji = base[e.key] ?? kGoodsDefs[e.key]?.emoji ?? e.key;
        return '$emoji ${e.value.ceil()}';
      })
      .join('  ');

  Widget _functionBtn(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: parchmentButton(),
        alignment: Alignment.center,
        child: Text(
          label,
          style: FoE.label(size: 13).copyWith(color: parchmentButtonInk()),
        ),
      ),
    ),
  );

  // ── Worker assignment (creature economy) ──────────────────
  // Each workshop role is staffed by SPECIFIC creatures; a role's output is
  // the sum of its workers' civilian stat, so the player picks who works where.
  // The roster itself lives in _productionSection now — what's left here is the
  // recipe picker and the notes about the crew as a whole.
  Widget _workshopExtras(PlacedBuilding b, BuildingDef def, bool functional) {
    final ctrl = CreaturesController();
    final posted = ctrl.creatures.where((c) => c.assignedBuildingId == b.id);
    // Counts who's actually HERE — away creatures earn no XP either
    // (accruePassiveXp uses the same rule).
    final stationed = posted.where(ctrl.isWorkingNow).length;
    final away = posted.length - stationed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The recipe picker used to live here as a Wrap of chips. It is the
        // Crafting screen now, opened by this dialog's own primary action —
        // see _primaryAction (user 2026-07-29).
        // The XP rate itself now sits next to the Workers heading; only the
        // "nobody is earning it" case still needs saying.
        if (stationed > 0 && !functional)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'No road connection — nobody here is working, or earning XP.',
              style: FoE.dim(size: 11).copyWith(color: FoE.danger),
            ),
          ),
        if (away > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '🎒 $away on expedition — post${away > 1 ? 's' : ''} held, '
              'no output until they return',
              style: FoE.dim(size: 10).copyWith(color: _dlgAccent),
            ),
          ),
      ],
    );
  }

  /// A work post's header: what it is, how full it is, and the way in.
  ///
  /// The WHOLE row opens the assign sheet (user 2026-07-26) — the seat count
  /// and the control that changes it were a row apart, with a centred "Edit"
  /// button under the worker list. Tapping the count is what anyone tries
  /// first anyway, and every post gets a row back.
  ///
  /// [enabled] is false for an unconnected building: there is nothing to edit
  /// until it has a road, so the row says the count and stays inert.
  Widget _workerHeaderRow({
    required PlacedBuilding b,
    required WorkshopRole role,
    required String label,
    required String count,
    required bool enabled,
  }) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: FoE.label(
                size: 11,
              ).copyWith(color: enabled ? _dlgAccent : _dlgInkFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count,
            style: FoE.value(
              size: 12,
            ).copyWith(color: enabled ? _dlgInk : _dlgInkFaint),
          ),
          if (enabled) ...[
            const SizedBox(width: 8),
            // A PLUS in a green circle (user 2026-07-26), not a pencil: the
            // thing you come here to do is add somebody, and green is already
            // this settlement's "do it" colour (the buttons, the land).
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: kActionGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 14, color: Colors.white),
            ),
          ],
        ],
      ),
    );
    if (!enabled) return row;
    return GestureDetector(
      // Opaque: the row is mostly whitespace between the label and the count,
      // and deferToChild would drop every tap that lands in the gap.
      behavior: HitTestBehavior.opaque,
      onTap: () => _openAssignPicker(b, role),
      child: row,
    );
  }

  void _openAssignPicker(PlacedBuilding b, WorkshopRole role) => showDialog(
    context: context,
    builder: (_) =>
        AssignWorkersSheet(ctrl: widget.ctrl, building: b, role: role),
  );

  /// What this Workshop is making. Settlement-wide rather than per-building:
  /// there is one recipe at a time (SettlementModel.activeCraftId), so showing
  /// a per-building choice would promise independence that doesn't exist.
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
    final queueSlots = def.effectAt('queueSlots', '', 99);
    if (queueSlots > 0) lines.add('+${queueSlots.round()} build queue slot');
    final buildSlots = def.effectAt('buildSlots', '', 99);
    if (buildSlots > 0) lines.add('+${buildSlots.round()} build site');
    final healSlots = def.effectAt('healSlots', '', 99);
    if (healSlots > 0) lines.add('🩺 Heals ${healSlots.round()} at once');
    if (lines.isEmpty && def.workshops.isEmpty) {
      lines.add('Decorative building');
    }
    return lines;
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // The diamond's bounding box — wider and flatter than the grid it holds.
    final mapW = isoCanvasSize.width;
    final mapH = isoCanvasSize.height;
    final ghostTypeId = _inMoveMode ? _movingType! : widget.pendingTypeId;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minScale = max(
          constraints.maxWidth / mapW,
          constraints.maxHeight / mapH,
        );
        final maxScale = max(minScale, 6.0);
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);

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
                          child: RepaintBoundary(
                            child: Image.asset(
                              'assets/images/map_background.png',
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                            ),
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
                        // BACK TO FRONT (2026-08-01). Drawn in list order, a
                        // tower behind a hut lands on top of it — the single
                        // most obvious way an isometric map looks broken.
                        ...(widget.ctrl.buildings.toList()
                              ..sort((a, b) => isoDrawOrder(
                                    a.gridX,
                                    a.gridY,
                                    b.gridX,
                                    b.gridY,
                                  )))
                            .map((b) => _buildingTile(b)),
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

            // ── Mode banners ──────────────────────────────────
            // Pinned to the BOTTOM, not `top: 54`. That offset was tuned to a
            // 44px header; the header is two rows plus a safe area now (~100px
            // on a phone), so the banners — and the "Done" button that leaves
            // the mode — were buried underneath it. Reported as "I can't close
            // the road menu".
            //
            // Bottom is also simply the right place: it's in thumb reach, and
            // the settlement screen hides its quick menu while a mode is
            // active, so nothing else is competing for the space.
            if (widget.roadMode)
              _bottomBanner(_roadBanner())
            else if (widget.editMode && !_inMoveMode)
              _bottomBanner(_editIdleBanner())
            else if (_inMoveMode)
              _bottomBanner(_moveBanner()),

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
    // ── ISOMETRIC PLACEMENT (2026-08-01) ──
    // The box is the footprint's own bounding rectangle (isoBounds), and the
    // art fills its width and hangs from its bottom, running upward as far as
    // it likes. A tall building is tall; nothing about its footprint says so,
    // so the box may not clip (Clip.none below, and BuildingIcon's
    // anchorBottomOverflowTop).
    //
    // The bounds, not "the south corner minus half the width": those two are
    // the same thing only for a square footprint, and a 2×1 building placed
    // that way sits half a tile off its own ground.
    final iso = isoBounds(b.gridX, b.gridY, def.gridW, def.gridH);
    return Positioned(
      left: iso.left,
      top: iso.top,
      width: iso.width,
      height: iso.height,
      child: Opacity(
        opacity: isGhostSrc ? 0.3 : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Isolated raster: the whole buildings layer rebuilds on every 5s
            // tick, but a tile's art only changes when the building does, so a
            // RepaintBoundary keeps the tick from repainting all ~200 tiles.
            RepaintBoundary(
              child: _BuildingTile(def: def, building: b),
            ),
            // SELECTED = ITS CELLS, LIT (user 2026-08-01: "jetzt noch den
            // grünen Rahmen entfernen. Wenn das gebäude markiert ist, will ich
            // nur die gehighlighteten Kachel sehen").
            //
            // It was a rectangle around the sprite's bounding box — a shape the
            // map no longer has, drawn around ground the building does not
            // stand on. What is lit now is the footprint itself, cell by cell,
            // so selecting a 2×2 shows you four tiles rather than a frame.
            if (isSelected)
              Positioned.fill(
                child: CustomPaint(
                  painter: _FootprintPainter(
                    w: def.gridW,
                    h: def.gridH,
                    color: FoE.accentBlue,
                    outline: false,
                  ),
                ),
              ),
            if (isDisconnected)
              Positioned.fill(
                child: CustomPaint(
                  painter: _FootprintPainter(
                    w: def.gridW,
                    h: def.gridH,
                    color: FoE.danger,
                    outline: false,
                  ),
                ),
              ),
            if (isDisconnected)
              const Positioned(
                top: 1,
                left: 1,
                child: Text('🚫', style: TextStyle(fontSize: 12)),
              ),
            // PAUSED, on the map (user 2026-08-01): a switch you cannot see
            // from the outside is one you forget you flipped — and a building
            // that has quietly produced nothing for a week looks exactly like a
            // building that is working.
            if (b.isPaused && b.isComplete) ...[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: FoE.bg.withValues(alpha: 0.45),
                  ),
                ),
              ),
              const Positioned(
                bottom: 1,
                right: 1,
                child: Text('⏸', style: TextStyle(fontSize: 12)),
              ),
            ],
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
    final iso = isoBounds(gx, gy, def.gridW, def.gridH);
    return Positioned(
      left: iso.left,
      top: iso.top,
      width: iso.width,
      height: iso.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The validity mark is the footprint's own diamond — a rectangle here
          // would promise a shape the placement rules do not use.
          Positioned.fill(
            child: CustomPaint(
              painter: _FootprintPainter(
                w: def.gridW,
                h: def.gridH,
                color: free ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
          // A Build Plot is a free area — no art, just the validity box.
          if (!def.isBuildPlot)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BuildingIcon(
                imageUrl: def.imageUrl,
                width: iso.width,
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
    // Main building and build plots are permanent — no delete X.
    if (def.isMainBuilding || def.isBuildPlot) return null;

    // The diamond's EAST corner: the right-hand point of the footprint, which
    // is where a button beside the building belongs on an isometric map.
    Offset east(int gx, int gy) =>
        gridToScreen((gx + def.gridW).toDouble(), gy.toDouble());
    final Offset anchor;
    if (_isDragging && _ghostX != null && _ghostY != null) {
      anchor = east(_ghostX!, _ghostY!);
    } else {
      final building = widget.ctrl.buildings
          .where((b) => b.id == _selectedId)
          .firstOrNull;
      if (building == null) return null;
      anchor = east(building.gridX, building.gridY);
    }
    final mapX = anchor.dx;
    final mapY = anchor.dy;

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
          ),
          child: const Icon(Icons.close, color: Colors.white, size: 14),
        ),
      ),
    );
  }

  // ── Banners ───────────────────────────────────────────────
  /// Places a mode banner at the bottom of the map, clear of the header and
  /// inside the device's safe area.
  Widget _bottomBanner(Widget child) => Positioned(
    left: 10,
    right: 10,
    bottom: 10 + MediaQuery.of(context).viewPadding.bottom,
    child: child,
  );

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
            decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 5, side: BorderSide(color: Colors.greenAccent.shade400))),
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
    decoration: FoE.panel(radius: 8, overrideBorder: FoE.accentBlue),
    child: Row(
      children: [
        const Icon(Icons.open_with, color: FoE.accentBlue, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _selectedId != null
                ? 'Drag to move  ·  tap another or empty to change'
                : 'Tap a building to select it',
            style: FoE.label().copyWith(color: FoE.accentBlue),
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
            decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 5, side: BorderSide(color: FoE.accentBlue))),
            child: Text(
              'Done',
              style: FoE.label(size: 11).copyWith(color: FoE.accentBlue),
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
      decoration: FoE.panel(radius: 8, overrideBorder: FoE.accentBlue),
      child: Row(
        children: [
          BuildingIcon(imageUrl: def.imageUrl, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tap to place ${def.name}  ·  Hold to cancel',
              style: FoE.label().copyWith(color: FoE.accentBlue),
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
    if (e != null) {
      // buildRatePerHour already includes buildSpeedMultiplier — applying it
      // again here squared the bonus (25x under the jumpstart). An empty tank
      // builds at the floor rate now, not zero (energy boosts, doesn't gate).
      //
      // NO /activeCount either: every site builds at the full rate (user
      // 2026-07-24), which is what tick() and the build menu both do. This
      // countdown was the last place still splitting, so a second site made
      // the first one's ETA silently double.
      rate =
          (widget.ctrl.buildRatePerHour / 3600.0) *
          (e.currentEnergy > 0 ? 1.0 : kEnergyFloorRate);
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
        style: FoE.dim(size: 11).copyWith(color: _kDlgAccent),
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
        RecessBar(value: pct / 100.0, color: _kDlgAccent, height: 12),
        const SizedBox(height: 6),
        Text(
          _queued
              ? 'In build queue — waiting for a free slot'
              : secondsLeft == null
              ? '$pct% — no build energy'
              : '$pct%  ·  ${fmtDuration(secondsLeft)} remaining',
          // On the dialog's parchment recess — the warm accent reads, the app's
          // light gold does not.
          style: FoE.dim(size: 11).copyWith(color: _kDlgAccent),
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
      // Dev-uploaded road art fills its cell edge-to-edge (BoxFit.cover, no
      // margin/border): roads tile into continuous paths, and a margin would
      // draw a visible grid across every one.
      //
      // The cell is a DIAMOND now (2026-08-01), so the art is clipped to it and
      // the plain-colour fallback is painted as one — a square road on an
      // isometric grid is a tile that refuses to join its neighbours.
      if (def.imageUrl != null && def.imageUrl!.isNotEmpty) {
        return ClipPath(
          clipper: _CellDiamondClipper(),
          child: BuildingIcon(
            imageUrl: def.imageUrl,
            width: kIsoTileW,
            height: kIsoTileH,
            fit: BoxFit.cover,
          ),
        );
      }
      return CustomPaint(
        size: const Size(kIsoTileW, kIsoTileH),
        painter: _RoadDiamondPainter(color: def.color),
      );
    }

    if (def.isBuildPlot) {
      // A Build Plot is a free AREA, not a structure — no art, no box. Its real
      // effect is turning its cells buildable (shown by the grid highlight), so
      // a finished plot is just a faint tint; while it's being cleared it shows
      // a dashed outline + the usual construction status.
      final ready = building.isComplete;
      return Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: def.color.withValues(alpha: ready ? 0.10 : 0.16),
            ),
          ),
          ..._statusOverlays(done: ready, queued: building.isQueued),
        ],
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
              // The BASE spans the whole diamond, so the art is as wide as the
              // footprint's two axes together — see docs/building_art_prompt.md.
              width: spriteWidth(def.gridW, def.gridH),
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
        child: ClipPath(
      clipper: ShapeBorderClipper(shape: FoE.facet(radius: 2)),
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
      // A cell is a diamond now, so the grid marks are too — a square here
      // would draw a lattice that has nothing to do with where you can build.
      canvas.drawPath(footprintPath(x, y, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.buildableRegion != buildableRegion;
}

/// The footprint diamond, filled and outlined — the ghost preview's "can I
/// build here" mark (2026-08-01).
class _FootprintPainter extends CustomPainter {
  final int w;
  final int h;
  final Color color;

  /// The crisp edge a PLACEMENT preview needs. Off for a selected building:
  /// there the answer is which cells it stands on, and an outline around them
  /// is the frame the user asked to be rid of.
  final bool outline;

  const _FootprintPainter({
    required this.w,
    required this.h,
    required this.color,
    this.outline = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // LOCAL coordinates. It used to draw footprintPath(0, 0, …), which is in
    // MAP space and therefore landed a whole map-origin away from the box it
    // was painting in — the outline the user saw beside the building rather
    // than under it (2026-08-01).
    final fill = Paint()..color = color.withValues(alpha: 0.24);
    canvas.drawPath(footprintPathLocal(w, h), fill);
    // CELL BY CELL: the seams between the tiles, so a 2×2 reads as four of
    // them. One flat wash would say "an area", and the question a selected
    // building answers is "how much of the grid is this".
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.55);
    for (final (from, to) in footprintSeams(w, h)) {
      canvas.drawLine(from, to, seam);
    }
    if (outline) {
      canvas.drawPath(
        footprintPathLocal(w, h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_FootprintPainter old) =>
      old.w != w || old.h != h || old.color != color || old.outline != outline;
}

/// One cell's diamond, for clipping road art to its tile.
class _CellDiamondClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width / 2, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width / 2, size.height)
    ..lineTo(0, size.height / 2)
    ..close();

  @override
  bool shouldReclip(CustomClipper<Path> old) => false;
}

/// A road without art: its cell, filled flat, with the lit near edge every
/// surface in this app wears.
class _RoadDiamondPainter extends CustomPainter {
  final Color color;
  const _RoadDiamondPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = color)
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = FoE.shade(color),
      );
  }

  @override
  bool shouldRepaint(_RoadDiamondPainter old) => old.color != color;
}
