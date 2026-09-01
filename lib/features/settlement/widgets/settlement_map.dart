import '../../../core/ui/feel.dart';
import 'dart:async';
import 'dart:math' show max;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/snack.dart';
import '../../onboarding/intro_flow.dart';
import '../data/building_art.dart';
import '../data/building_definitions.dart';
import '../data/iso_grid.dart';
import '../data/road_tiles.dart';
import '../sheets/building_detail_dialog.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import 'building_icon.dart';
import 'building_life.dart';
import 'scroll_paper.dart' show kActionGreen, kParchmentDeep;

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
  /// Opens the detail dialog of the first placed building of [typeId], as if
  /// the player had tapped it. The guided intro's cards use this so "tap the
  /// Castle" is a lit button, not a search across the map.
  void openBuildingByType(String typeId) {
    for (final b in widget.ctrl.buildings) {
      if (b.buildingTypeId == typeId) {
        _showDetail(b);
        return;
      }
    }
  }

  // ── AIMING (user 2026-08-09) ────────────────────────────────
  // "Wenn ich ein Gebäude ausgewählt habe, dann erscheint es mittig im Screen.
  //  Wenn ich es berühre, kann ich es verschieben … Wenn ich daneben mit dem
  //  Finger bin, dann kann ich scrollen. […] Über dem Gebäude gibt es ein
  //  gutzeichen und ein X […]. Genau gleich funktioniert der
  //  Bearbeitungs/movemodus."
  //
  // ONE session covers both jobs the map used to do differently. Placing
  // something new and moving something that already stands are the same
  // gesture: a ghost you push around and then accept. Nothing is written until
  // the ✓ — so a cancelled placement costs nothing, and a cancelled move never
  // touched the building in the first place.
  //
  // The old flow bought the building, dropped it somewhere near the hall and
  // left you to drag it: every mis-tap was a purchase, and the drag fought the
  // map's own pan because a full-screen overlay had to swallow every gesture to
  // get at it. Here the only thing that swallows gestures is the ghost's own
  // box, which is exactly what "beside it I can scroll" means.
  String? _aimType; // the ghost's building type — null when no session
  String? _aimMoveId; // set when the ghost IS a building already on the map
  int? _aimX, _aimY; // the cell the ghost's north-west corner sits on

  bool get _aiming => _aimType != null;

  // ── ROAD CHAINS ─────────────────────────────────────────────
  // "Wenn ich eine Strasse Platziere und auf bestätigen drücke, dann werden die
  //  Pfeile aktiv (grösser) und ich kann diese antippen um an dieser Stelle eine
  //  neue Strasse zu bauen."
  //
  // A road is never one tile, so confirming one does not end the job — it turns
  // the four arrows into a brush and leaves the ✓/✗ hovering over whichever
  // tile you laid last. Deleting works the same way with red arrows, which is
  // what replaced dragging a finger over the map and hoping.
  bool _chaining = false;
  bool _chainErase = false;
  int _chainX = 0, _chainY = 0;
  final List<String> _chainBuilt = [];
  final List<(int, int)> _chainRemoved = [];

  // ── Dragging the ghost ──────────────────────────────────────
  bool _dragging = false;
  // Where inside its own footprint the finger grabbed it, so the building does
  // not jump its own half-width the moment you touch it.
  int _grabDx = 0, _grabDy = 0;
  Offset? _dragAt; // last pointer position, in the map widget's coordinates
  Timer? _edgeTimer;

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
    final def = kBuildingDefs[b.buildingTypeId];
    if (def == null) return;
    _focusCell(b.gridX, b.gridY, def.gridW, def.gridH);
  }

  /// [focusBuilding] for a footprint that is not (yet) a building — the ghost.
  void _focusCell(int gx, int gy, int w, int h) {
    final view = _viewport;
    if (view == null) return;
    final scale = _txCtrl.value.getMaxScaleOnAxis();
    final mapW = isoCanvasSize.width * scale;
    final mapH = isoCanvasSize.height * scale;
    // The footprint's own point on the diamond, not the middle of a rectangle.
    final centre = gridToScreen(gx + w / 2, gy + h / 2);
    final cx = centre.dx * scale;
    final cy = centre.dy * scale;
    final tx = (view.width / 2 - cx)
        .clamp(math.min(0.0, view.width - mapW), 0.0)
        .toDouble();
    final ty = (view.height / 2 - cy)
        .clamp(math.min(0.0, view.height - mapH), 0.0)
        .toDouble();
    final target = mapTransform(scale, tx, ty);
    _panAnim = Matrix4Tween(
      begin: _txCtrl.value,
      end: target,
    ).animate(CurvedAnimation(parent: _panCtrl, curve: Curves.easeOutCubic));
    _panCtrl
      ..reset()
      ..forward();
  }

  @override
  void didUpdateWidget(SettlementMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving a mode drops whatever was being aimed in it. Nothing was written,
    // so there is nothing to undo.
    if (!widget.editMode && oldWidget.editMode && _aimMoveId != null) {
      _clearAim();
    }
    // A type arriving from the build menu OPENS a session (and a type going
    // away — the screen's own ✗ — closes it).
    final pending = widget.pendingTypeId;
    if (pending != null && pending != oldWidget.pendingTypeId) {
      _startAim(pending);
    } else if (pending == null &&
        oldWidget.pendingTypeId != null &&
        _aimMoveId == null) {
      _clearAim();
    }
    // Roads come in through the same door: the Build menu's "Roads" is just a
    // session whose type is `road`, and the ✓ hands it on to the chain.
    if (widget.roadMode && !oldWidget.roadMode) {
      _startAim('road');
    } else if (!widget.roadMode && oldWidget.roadMode) {
      _clearAim();
      if (_chaining) setState(_dropChainState);
    }
    // A building the SCREEN wants aimed (the tutorial, and anything that builds
    // on the player's behalf). Only on CHANGE: re-opening on every rebuild
    // would fight the player's own taps.
    final fresh = widget.selectBuildingId;
    if (fresh != null && fresh != oldWidget.selectBuildingId) {
      for (final b in widget.ctrl.buildings) {
        if (b.id != fresh) continue;
        _startAim(b.buildingTypeId, moveId: b.id);
        break;
      }
    }
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
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
    // Every write to the transform is checked, whoever made it.
    _txCtrl.addListener(_enforceBounds);
  }

  // ── Opening and closing a session ─────────────────────────
  /// Puts [typeId] under the player's thumb. [moveId] names a building that is
  /// already standing — then the session MOVES it instead of placing a new one.
  void _startAim(String typeId, {String? moveId}) {
    final def = kBuildingDefs[typeId];
    if (def == null) return;
    // Build plots are permanent (settlement_controller refuses to move one), so
    // there is nothing for a move session to do with one.
    if (moveId != null && def.isBuildPlot) return;
    final b = moveId == null
        ? null
        : widget.ctrl.buildings.where((x) => x.id == moveId).firstOrNull;
    if (moveId != null && b == null) return;
    _stopDrag();
    setState(() {
      _dropChainState();
      _aimType = typeId;
      _aimMoveId = moveId;
      _aimX = b?.gridX;
      _aimY = b?.gridY;
    });
    // "…dann erscheint es mittig im Screen." For something already on the map
    // that means bringing the CAMERA to it; for something new it means dropping
    // it on whatever the camera is already looking at. After the frame, because
    // both need the viewport this build is about to report.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _aimType != typeId || _aimMoveId != moveId) return;
      if (b != null) {
        focusBuilding(b);
      } else {
        _dropGhostAtCentre(def);
      }
    });
  }

  /// Opens a new building on the cell in the middle of the view.
  void _dropGhostAtCentre(BuildingDef def) {
    final view = _viewport;
    if (view == null) return;
    final (col, row) = _cellAt(Offset(view.width / 2, view.height / 2));
    var gx = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
    var gy = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
    (gx, gy) = widget.ctrl.snapPlacement(def.id, gx, gy);
    if (!widget.ctrl.isPlacementValid(def.id, gx, gy)) {
      // The middle of the view can be locked ground or somebody's wall. Opening
      // on a red outline reads as a refusal rather than an invitation, so fall
      // back to a spot the game WOULD accept and take the camera there —
      // "mittig im Screen" is about what you are looking at, not about which
      // cell happens to be under the crosshair.
      final spot = widget.ctrl.firstFreeSpotFor(def.id);
      if (spot != null) {
        gx = spot.$1;
        gy = spot.$2;
        _focusCell(gx, gy, def.gridW, def.gridH);
      }
    }
    setState(() {
      _aimX = gx;
      _aimY = gy;
    });
  }

  /// Drops the ghost without writing anything. Nothing was ever committed, so
  /// there is nothing to roll back.
  void _clearAim() {
    _stopDrag();
    if (!_aiming) return;
    setState(() {
      _aimType = null;
      _aimMoveId = null;
      _aimX = null;
      _aimY = null;
    });
  }

  /// The ✗. Also tells the SCREEN, whose `pendingTypeId` / `roadMode` opened
  /// the session in the first place and would otherwise re-open it.
  void _cancelAim() {
    Feel.tap();
    _clearAim();
    _closeSessionMode();
  }

  /// The ✓ — the one place a building is bought or moved.
  Future<void> _confirmAim() async {
    final type = _aimType, x = _aimX, y = _aimY;
    if (type == null || x == null || y == null) return;
    final moveId = _aimMoveId;
    final err = moveId == null
        ? await widget.ctrl.placeBuilding(type, x, y)
        : await widget.ctrl.moveBuilding(moveId, x, y);
    if (!mounted) return;
    if (err != null) {
      // STAYS OPEN. The spot is the only thing wrong, and dropping the session
      // would make the player start the whole placement again to fix it.
      Feel.deny();
      context.snack(err, error: true);
      return;
    }
    Feel.place();
    final isNewRoad = moveId == null && (kBuildingDefs[type]?.isRoad ?? false);
    if (isNewRoad) {
      unawaited(widget.ctrl.advanceIntro(IntroStep.buildRoad));
    }
    final chainHead = widget.ctrl.lastPlacedId;
    _clearAim();
    if (isNewRoad && chainHead != null) {
      // Hand straight over to the chain — the session does NOT close, it
      // changes shape (user 2026-08-09).
      setState(() {
        _chaining = true;
        _chainErase = false;
        _chainX = x;
        _chainY = y;
        _chainBuilt
          ..clear()
          ..add(chainHead);
        _chainRemoved.clear();
      });
      return;
    }
    _closeSessionMode();
    // Edit mode deliberately STAYS on after a move (user 2026-07-20), so
    // several buildings can be rearranged in one visit.
  }

  // ── Road chains ───────────────────────────────────────────
  void _dropChainState() {
    _chaining = false;
    _chainErase = false;
    _chainBuilt.clear();
    _chainRemoved.clear();
  }

  /// One arrow tap during a chain: lays the next road, or takes the next one
  /// away, and moves the chain's head onto it.
  Future<void> _chainStep(int dx, int dy) async {
    final nx = _chainX + dx, ny = _chainY + dy;
    if (nx < 0 || ny < 0 || nx >= kGridCols || ny >= kGridRows) {
      Feel.deny();
      return;
    }
    if (_chainErase) {
      final hit = _hitTest(nx, ny);
      if (hit == null ||
          !(kBuildingDefs[hit.buildingTypeId]?.isRoad ?? false)) {
        Feel.deny();
        return;
      }
      final err = await widget.ctrl.deleteBuilding(hit.id);
      if (!mounted) return;
      if (err != null) {
        Feel.deny();
        context.snack(err, error: true);
        return;
      }
      Feel.tap();
      setState(() {
        _chainX = nx;
        _chainY = ny;
        _chainRemoved.add((nx, ny));
      });
      return;
    }
    final err = await widget.ctrl.placeBuilding('road', nx, ny);
    if (!mounted) return;
    if (err != null) {
      Feel.deny();
      context.snack(err, error: true);
      return;
    }
    final id = widget.ctrl.lastPlacedId;
    Feel.place();
    setState(() {
      _chainX = nx;
      _chainY = ny;
      if (id != null) _chainBuilt.add(id);
    });
  }

  /// Whichever mode the SCREEN opened this session in has to be told the job is
  /// over, or it hands the map the same type straight back.
  void _closeSessionMode() {
    if (widget.pendingTypeId != null) widget.onPlacementDone?.call();
    if (widget.roadMode) widget.onExitRoadMode?.call();
  }

  /// The chain's ✓ — keep everything laid (or everything torn out) and stop.
  void _endChain() {
    Feel.tap();
    setState(_dropChainState);
    _closeSessionMode();
  }

  /// The chain's ✗ — the whole stroke goes back the way it was. A chain is
  /// built one tap at a time, so undoing only the last tap would leave the
  /// player pressing ✗ twenty times to get out of a mistake.
  Future<void> _undoChain() async {
    final built = [..._chainBuilt];
    final removed = [..._chainRemoved];
    final erasing = _chainErase;
    Feel.tap();
    setState(_dropChainState);
    _closeSessionMode();
    if (erasing) {
      for (final (x, y) in removed) {
        await widget.ctrl.placeBuilding('road', x, y);
      }
    } else {
      for (final id in built) {
        await widget.ctrl.deleteBuilding(id);
      }
    }
  }

  // ── Moving the ghost ──────────────────────────────────────
  /// A pointer's position in the MAP WIDGET's own coordinates — the space the
  /// screen-side controls and [TransformationController.toScene] both live in.
  /// Gesture-local coordinates would be relative to whichever little button was
  /// touched, which is not a place on the map.
  Offset _mapLocal(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  /// The cell under a map-local point.
  (int, int) _cellAt(Offset local) => screenToGrid(_txCtrl.toScene(local));

  void _moveGhostTo(Offset local) {
    final type = _aimType;
    final def = type == null ? null : kBuildingDefs[type];
    if (def == null) return;
    final (col, row) = _cellAt(local);
    var gx = (col - _grabDx).clamp(0, kGridCols - def.gridW);
    var gy = (row - _grabDy).clamp(0, kGridRows - def.gridH);
    (gx, gy) = widget.ctrl.snapPlacement(type!, gx, gy);
    if (gx == _aimX && gy == _aimY) return;
    setState(() {
      _aimX = gx;
      _aimY = gy;
    });
  }

  void _ghostDragStart(DragStartDetails d) {
    final type = _aimType;
    final def = type == null ? null : kBuildingDefs[type];
    if (def == null || _aimX == null || _aimY == null) return;
    final local = _mapLocal(d.globalPosition);
    final (col, row) = _cellAt(local);
    setState(() {
      _dragging = true;
      // Clamped INTO the footprint: the touch box reaches up over the art, and
      // a grab taken up there would otherwise offset the building by however
      // tall its picture happens to be.
      _grabDx = (col - _aimX!).clamp(0, def.gridW - 1);
      _grabDy = (row - _aimY!).clamp(0, def.gridH - 1);
    });
    _dragAt = local;
    _edgeTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickEdgeScroll(),
    );
  }

  void _ghostDragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final local = _mapLocal(d.globalPosition);
    _dragAt = local;
    _moveGhostTo(local);
  }

  void _stopDrag() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _dragAt = null;
    if (_dragging && mounted) setState(() => _dragging = false);
  }

  // ── Scrolling the map under the ghost ─────────────────────
  // "Das geht auch, wenn ich das Gebäude an den Rand des Screens bewege."
  //
  // Without this the map is only as big as one screenful for placement
  // purposes: you can drag a building to the edge and then have nowhere to put
  // it, because the hand holding the building is the hand that would have
  // panned. The band is generous (a thumb is wide) and the speed ramps with how
  // far in you are, so grazing the edge nudges and pinning to it runs.
  static const double _kEdgeBand = 76;
  static const double _kEdgeSpeed = 13;

  void _tickEdgeScroll() {
    final at = _dragAt;
    final view = _viewport;
    if (!_dragging || at == null || view == null) return;
    double push(double d) =>
        d >= _kEdgeBand ? 0 : (1 - math.max(d, 0) / _kEdgeBand) * _kEdgeSpeed;
    // Near the LEFT edge the content slides right, which is what reveals what
    // lies further left.
    final dx = push(at.dx) - push(view.width - at.dx);
    final dy = push(at.dy) - push(view.height - at.dy);
    if (dx == 0 && dy == 0) return;
    _panScreen(Offset(dx, dy));
    // The finger has not moved, but the ground under it has.
    _moveGhostTo(at);
  }

  /// Slides the view by [delta] screen pixels. The bounds listener is what
  /// keeps it inside the map, so this does not clamp a second time.
  void _panScreen(Offset delta) {
    final m = _txCtrl.value.clone();
    final t = m.getTranslation();
    m.setTranslationRaw(t.x + delta.dx, t.y + delta.dy, 0);
    _txCtrl.value = m;
  }

  // ── The boundary, enforced on every write ─────────────────
  // "Es darf niemals aus dem Spielfeld hinausgezoomt/gescrollt werden … Es
  //  dürfte niemals der Rand sichtbar sein" (user 2026-08-09).
  //
  // NIEMALS is a strong word, and the way to honour it is not to ask each
  // writer of the transform to remember: it is to check the invariant on the
  // controller itself. InteractiveViewer's gestures, the camera moves, the
  // edge-scroll and anything added later all go through this one listener.
  //
  // The z-scale bug (see mapTransform) is fixed at the source, so this is no
  // longer load-bearing for that case — but it is what makes the rule true
  // rather than merely intended.
  bool _fixingBounds = false;

  void _enforceBounds() {
    if (_fixingBounds || !_txInitialized) return;
    final view = _viewport;
    if (view == null) return;
    final m = _txCtrl.value;
    final fixed = clampMapTransform(m, view);
    if (_sameTransform(fixed, m)) return;
    _fixingBounds = true;
    _txCtrl.value = fixed;
    _fixingBounds = false;
  }

  static bool _sameTransform(Matrix4 a, Matrix4 b) {
    if ((a.getMaxScaleOnAxis() - b.getMaxScaleOnAxis()).abs() > 1e-9) {
      return false;
    }
    final ta = a.getTranslation(), tb = b.getTranslation();
    return (ta.x - tb.x).abs() < 1e-6 && (ta.y - tb.y).abs() < 1e-6;
  }

  /// One arrow tap outside a chain: a single cell in that direction. Plots move
  /// by their own 5-cell snap, so their arrow does something visible.
  void _nudge(int dx, int dy) {
    final type = _aimType;
    final def = type == null ? null : kBuildingDefs[type];
    if (def == null || _aimX == null || _aimY == null) return;
    final step = def.isBuildPlot ? 5 : 1;
    final gx = (_aimX! + dx * step).clamp(0, kGridCols - def.gridW);
    final gy = (_aimY! + dy * step).clamp(0, kGridRows - def.gridH);
    if (gx == _aimX && gy == _aimY) {
      Feel.deny();
      return;
    }
    Feel.tap();
    setState(() {
      _aimX = gx;
      _aimY = gy;
    });
  }

  // ── Tap inside InteractiveViewer ──────────────────────────
  void _handleTap(Offset local) {
    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(local);

    // A chain is driven by its arrows alone; a stray tap on the map must not
    // move the head somewhere the road cannot reach.
    if (_chaining) return;

    if (_aiming) {
      // A tap on open ground is a long drag in one go — the arrows are for
      // nudging, the drag for aiming, and this for crossing the map.
      final def = kBuildingDefs[_aimType!];
      if (def == null) return;
      var gx = (col - def.gridW ~/ 2).clamp(0, kGridCols - def.gridW);
      var gy = (row - def.gridH ~/ 2).clamp(0, kGridRows - def.gridH);
      (gx, gy) = widget.ctrl.snapPlacement(_aimType!, gx, gy);
      setState(() {
        _aimX = gx;
        _aimY = gy;
      });
      return;
    }

    final hit = _hitTest(col, row);
    if (widget.editMode) {
      // Tapping a building in edit mode IS picking it up (user 2026-08-09):
      // selection and move are the same act now, so there is no idle
      // "selected but doing nothing" state to explain.
      if (hit != null) _startAim(hit.buildingTypeId, moveId: hit.id);
      return;
    }
    if (hit != null) _showDetail(hit);
  }

  // ── Long-press inside InteractiveViewer (normal mode only) ─
  void _handleLongPress(Offset local) {
    if (widget.editMode || _aiming || _chaining) return;

    // ISOMETRIC (2026-08-01): the inverse projection, not a division — see
    // iso_grid.dart. It clamps to the map the way the old floor+clamp did.
    final (col, row) = screenToGrid(local);
    final hit = _hitTest(col, row);
    if (hit == null) return;
    // Build plots are permanent — no move (see settlement_controller).
    if (kBuildingDefs[hit.buildingTypeId]?.isBuildPlot ?? false) return;
    // Open the PERSISTENT move mode with this building already in hand (user
    // 2026-07-20) — it stays up until Done, so you can rearrange several in a
    // row.
    widget.onEnterEditMode?.call();
    _startAim(hit.buildingTypeId, moveId: hit.id);
  }

  // ── Delete ────────────────────────────────────────────────
  /// The 🗑 beside the building being aimed.
  ///
  /// A ROAD skips the dialog and opens an ERASE CHAIN instead (user
  /// 2026-08-09: "aber die Pfeile sind rot, um das Löschen zu signalisieren").
  /// Roads cost nothing and are laid by the dozen, so a modal per tile would be
  /// the whole job; the chain's own ✗ is the undo that dialog was standing in
  /// for.
  Future<void> _deleteAimed() async {
    final id = _aimMoveId;
    final type = _aimType;
    if (id == null || type == null) return;
    final def = kBuildingDefs[type];
    if (def == null) return;
    if (def.isRoad) {
      final b = widget.ctrl.buildings.where((x) => x.id == id).firstOrNull;
      if (b == null) return;
      final (x, y) = (b.gridX, b.gridY);
      final err = await widget.ctrl.deleteBuilding(id);
      if (!mounted) return;
      if (err != null) {
        Feel.deny();
        context.snack(err, error: true);
        return;
      }
      Feel.tap();
      _clearAim();
      setState(() {
        _chaining = true;
        _chainErase = true;
        _chainX = x;
        _chainY = y;
        _chainBuilt.clear();
        _chainRemoved
          ..clear()
          ..add((x, y));
      });
      return;
    }
    _showDeleteConfirmation(id, def);
  }

  void _showDeleteConfirmation(String id, BuildingDef def) {
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
                  BuildingIcon(imageUrl: def.imageUrl, defId: def.id, size: 18),
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
      _clearAim();
      final err = await widget.ctrl.deleteBuilding(id);
      if (err != null && mounted) {
        Feel.deny();
        context.snack(err, error: true);
      }
    });
  }

  Widget _dialogBtn(String label, VoidCallback onTap, {bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: ShapeDecoration(
            color: danger
                ? Colors.red.shade900.withValues(alpha: 0.4)
                : FoE.panelMid,
            shape: FoE.facet(
              radius: 6,
              side: BorderSide(
                color: danger ? Colors.red.shade700 : FoE.border,
              ),
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
      // A finished Building Plot has already vanished visually (see
      // _BuildingTile) — it must stop catching taps too, or "empty" ground
      // would still pop up its detail sheet instead of doing nothing / letting
      // the tap reach whatever real building sits on that same tile.
      if (def.isBuildPlot && b.isComplete) continue;
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
  void _showDetail(PlacedBuilding b) => showBuildingDetailDialog(
    context,
    widget.ctrl,
    b,
    onOpenBuildMenu: widget.onOpenBuildMenu,
  );

  /// The buildings to paint, in order. [roads] picks the ground layer or the
  /// things standing on it.
  ///
  /// A def that has gone missing counts as NOT a road: it draws nothing either
  /// way, and guessing "ground" for something unknown is how a hole in the map
  /// ends up under everything.
  List<PlacedBuilding> _sortedForPainting({required bool roads}) {
    final out = [
      for (final b in widget.ctrl.buildings)
        if ((kBuildingDefs[b.buildingTypeId]?.isRoad ?? false) == roads) b,
    ];
    out.sort((a, b) {
      final ad = kBuildingDefs[a.buildingTypeId];
      final bd = kBuildingDefs[b.buildingTypeId];
      return isoDrawOrder(
        a.gridX,
        a.gridY,
        ad?.gridW ?? 1,
        ad?.gridH ?? 1,
        b.gridX,
        b.gridY,
        bd?.gridW ?? 1,
        bd?.gridH ?? 1,
      );
    });
    return out;
  }

  /// One painting layer, with the ghost dropped into it at ITS OWN DEPTH.
  ///
  /// The ghost used to be painted last, on top of the whole map — which reads
  /// as a cut-out floating over the town and, worse, hides the very thing the
  /// player is judging: whether the new building fits BETWEEN the ones already
  /// there. In its proper place it can be covered by something in front of it,
  /// which is exactly why [_fadedBehindGhost] exists.
  List<Widget> _layer({
    required bool roads,
    BuildingDef? ghostDef,
    int? gx,
    int? gy,
    required Set<String> faded,
  }) {
    final withGhost =
        ghostDef != null &&
        gx != null &&
        gy != null &&
        ghostDef.isRoad == roads;
    final out = <Widget>[];
    var pending = withGhost;
    for (final b in _sortedForPainting(roads: roads)) {
      final d = kBuildingDefs[b.buildingTypeId];
      if (pending &&
          isoDrawOrder(
                gx!,
                gy!,
                ghostDef!.gridW,
                ghostDef.gridH,
                b.gridX,
                b.gridY,
                d?.gridW ?? 1,
                d?.gridH ?? 1,
              ) <
              0) {
        out.add(_ghost(ghostDef.id, gx, gy));
        pending = false;
      }
      out.add(_buildingTile(b, faded: faded.contains(b.id)));
    }
    if (pending) out.add(_ghost(ghostDef!.id, gx!, gy!));
    return out;
  }

  /// Buildings that STAND IN FRONT of the ghost and overlap it on screen.
  ///
  /// "Wenn ich das Gebäude hinter ein anderes schiebe, dann wird dieses
  /// transparent, damit ich die Platzierung besser sehe" (user 2026-08-09).
  /// Only while aiming — a permanently see-through town would be a much worse
  /// map than an occasionally occluded one.
  ///
  /// The test is against the SPRITE's box, not the footprint's: what hides the
  /// ghost is a tall roof leaning over the tiles in front of it, and those tiles
  /// are not part of the building's own ground.
  Set<String> _fadedBehindGhost(BuildingDef ghostDef, int gx, int gy) {
    final ghostBox = _artRect(ghostDef, gx, gy);
    final out = <String>{};
    for (final b in widget.ctrl.buildings) {
      final d = kBuildingDefs[b.buildingTypeId];
      if (d == null || d.isRoad || d.isBuildPlot) continue;
      if (b.id == _aimMoveId) continue;
      // In front of the ghost, not behind it — anything behind is already
      // hidden BY the ghost, and fading it would reveal nothing.
      if (isoDrawOrder(
            gx,
            gy,
            ghostDef.gridW,
            ghostDef.gridH,
            b.gridX,
            b.gridY,
            d.gridW,
            d.gridH,
          ) >=
          0) {
        continue;
      }
      if (_artRect(d, b.gridX, b.gridY).overlaps(ghostBox)) out.add(b.id);
    }
    return out;
  }

  /// The box a building's PICTURE occupies in map space. A road and a build
  /// plot ARE their ground and have no art above it, so for those the tile is
  /// the whole story.
  Rect _artRect(BuildingDef def, int gx, int gy) =>
      def.isRoad || def.isBuildPlot
      ? isoBounds(gx, gy, def.gridW, def.gridH)
      : isoArtBounds(
          gx,
          gy,
          def.gridW,
          def.gridH,
          baseWidth: artBoxOf(def).baseWidth,
          anchorX: artBoxOf(def).anchorX,
          lift: artBoxOf(def).lift,
        );

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // The diamond's bounding box — wider and flatter than the grid it holds.
    final mapW = isoCanvasSize.width;
    final mapH = isoCanvasSize.height;
    final ghostDef = _aimType == null ? null : kBuildingDefs[_aimType!];
    final gx = _aimX, gy = _aimY;
    final showGhost = ghostDef != null && gx != null && gy != null;
    final faded = showGhost
        ? _fadedBehindGhost(ghostDef, gx, gy)
        : const <String>{};

    return LayoutBuilder(
      builder: (context, constraints) {
        // ── THE MAP IS THE BOUNDARY (user 2026-08-09) ──
        // "Es darf niemals aus dem Spielfeld hinausgezoomt/gescrollt werden."
        //
        // Zooming out is bounded by making the smallest allowed scale the one
        // at which the map already covers the viewport — the LARGER of the two
        // ratios, so it covers both axes and not just the tighter one. Panning
        // is bounded by _clampedToMap, which every write to the matrix goes
        // through, including the ones that bypass InteractiveViewer (the camera
        // moves and the edge-scroll).
        final minScale = minMapScale(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final maxScale = max(minScale, kMaxMapZoom);
        final view = Size(constraints.maxWidth, constraints.maxHeight);
        final resized = _viewport != null && _viewport != view;
        _viewport = view;

        if (!_txInitialized) {
          _txInitialized = true;
          final tx = (constraints.maxWidth - mapW * minScale) / 2;
          final ty = (constraints.maxHeight - mapH * minScale) / 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _txCtrl.value = mapTransform(minScale, tx, ty);
          });
        } else if (resized) {
          // The viewport can change under a transform that was legal when it
          // was set — a rotation, a keyboard, a resized desktop window — and
          // minScale changes with it. InteractiveViewer only re-clamps on the
          // next gesture, so until the player touches the map they would be
          // looking at the void beside it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final scale = _txCtrl.value.getMaxScaleOnAxis();
            if (scale >= minScale) {
              _txCtrl.value = clampMapTransform(_txCtrl.value, view);
              return;
            }
            _txCtrl.value = clampMapTransform(
              mapTransform(
                minScale,
                (view.width - mapW * minScale) / 2,
                (view.height - mapH * minScale) / 2,
              ),
              view,
            );
          });
        }

        return Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              minScale: minScale,
              maxScale: maxScale,
              // Explicit, though it is the default: zero margin is what stops a
              // pan from bringing the map's edge inside the viewport, and it is
              // half of the boundary rule above. A reader should not have to
              // know the default to know the rule is being kept.
              boundaryMargin: EdgeInsets.zero,
              transformationController: _txCtrl,
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
                            // Raised from 2048 (user 2026-08-27: "den
                            // Hintergrund genau gleich scharf auflösen wie
                            // die Gebäude") — kMaxMapZoom went from 0.8 to
                            // 1.0 the same day, and at 1.0 this single image,
                            // stretched over the WHOLE map canvas
                            // (isoCanvasSize, several times the image's own
                            // 4096 x 2048), is what a player is now actually
                            // looking at up close rather than glancing past.
                            //
                            // 2026-08-28 (user: "der Hintergrund muss noch
                            // deutlich besser aufgelöst sein"): the source
                            // was re-rendered at 8192 x 4096 (terrain.py
                            // --scale 0.8) specifically so the decode target
                            // could move too — a bigger source file alone
                            // changes nothing, since cacheWidth is what
                            // actually caps the pixels a player sees. Split
                            // by platform because the ceiling that matters is
                            // the canvaskit web decode that OOM'd at 4096
                            // (32 MB) last time; native has no such budget
                            // and gets the sharper decode.
                            cacheWidth: kIsWeb ? 3072 : 6144,
                          ),
                        ),
                      ),
                      if (showGhost ||
                          _chaining ||
                          widget.editMode ||
                          widget.roadMode)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridPainter(
                              buildableRegion: widget.ctrl.buildableRegion,
                            ),
                          ),
                        ),
                      // ── GROUND FIRST, THEN WHAT STANDS ON IT ──
                      // (user 2026-08-01: "die Strasse ist jetzt über dem
                      // Gebäude").
                      //
                      // Depth alone cannot fix that. A road one tile in FRONT
                      // of a building is genuinely nearer the viewer, so it
                      // sorts later — and then its flat tile paints over the
                      // wall that leans into that space, because a tall sprite
                      // occupies tiles its footprint does not.
                      //
                      // So roads are a LAYER, not a competitor: they are
                      // ground, and nothing that lies on the ground may cover
                      // something standing on it.
                      ..._layer(
                        roads: true,
                        ghostDef: ghostDef,
                        gx: gx,
                        gy: gy,
                        faded: faded,
                      ),
                      // BACK TO FRONT among themselves.
                      ..._layer(
                        roads: false,
                        ghostDef: ghostDef,
                        gx: gx,
                        gy: gy,
                        faded: faded,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── The controls, in SCREEN space ─────────────────
            // They ride above the InteractiveViewer but cover only the ghost
            // and its handles — everything else falls through to the viewer,
            // which is what makes "beside it I can scroll" true without a mode
            // switch. The AnimatedBuilder is what keeps them pinned while the
            // map moves under them.
            if (showGhost || _chaining)
              // Positioned.fill, because a bare Stack whose children are ALL
              // positioned collapses to nothing and takes every control with it.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _txCtrl,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (showGhost) ..._aimControls(ghostDef, gx, gy),
                      if (_chaining) ..._chainControls(),
                    ],
                  ),
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
            if (_chaining)
              _bottomBanner(_chainBanner())
            else if (showGhost)
              _bottomBanner(_aimBanner(ghostDef))
            else if (widget.editMode)
              _bottomBanner(_editIdleBanner()),
          ],
        );
      },
    );
  }

  // ── Building tile ─────────────────────────────────────────
  /// [faded] is set for a building STANDING IN FRONT of the ghost — see
  /// [_fadedBehindGhost]. It is not a state the building is in; it is a state
  /// the CAMERA is in, and it lasts exactly as long as the placement.
  Widget _buildingTile(PlacedBuilding b, {bool faded = false}) {
    final def = kBuildingDefs[b.buildingTypeId];
    if (def == null) return const SizedBox.shrink();
    // The building being moved keeps standing where it was, ghosted: the ✗ is
    // still on the table, so "where it came from" is live information.
    final isGhostSrc = b.id == _aimMoveId;
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
        opacity: isGhostSrc
            ? 0.3
            : faded
            ? 0.3
            : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Isolated raster: the whole buildings layer rebuilds on every 5s
            // tick, but a tile's art only changes when the building does, so a
            // RepaintBoundary keeps the tick from repainting all ~200 tiles.
            RepaintBoundary(
              child: _BuildingTile(
                def: def,
                building: b,
                // Which junction this road is. Computed here rather than in the
                // tile because only the map can see the neighbours, and it has
                // the controller's cached cell set to see them cheaply.
                roadMask: def.isRoad
                    ? roadMask(widget.ctrl.roadCells, b.gridX, b.gridY)
                    : 0,
              ),
            ),
            // ── SIGNS OF LIFE (user 2026-08-04) ──
            // Smoke and lamplight, over the sprite and inside its own box.
            // Only on a FINISHED, RUNNING building: a site under construction
            // has nobody in it, and a paused one has been told to stop — a
            // chimney still smoking would say the opposite of what the pause
            // overlay says, and the player would believe the smoke.
            if (b.isComplete && !b.isPaused && !def.isRoad && !def.isBuildPlot)
              Positioned.fill(
                child: _LifeOverlay(def: def, seed: b.id.hashCode),
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
                child: Text('⏸️', style: TextStyle(fontSize: 12)),
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
      excludeId: _aimMoveId,
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
          // A ROAD GHOST SHOWS THE JUNCTION IT WOULD MAKE. Counting the cell
          // being aimed as already laid is the point: dragging a road up to a
          // straight run turns the preview into a tee before you commit, which
          // is the whole question you are asking while you aim it.
          if (def.isRoad)
            Positioned.fill(
              child: Opacity(
                opacity: 0.75,
                child: Image.asset(
                  roadAsset(
                    roadMask(
                      {...widget.ctrl.roadCells, roadCellKey(gx, gy)},
                      gx,
                      gy,
                    ),
                  ),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  cacheWidth: 256,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            )
          else
            Builder(
              builder: (_) {
                final local = isoLocalBounds(def.gridW, def.gridH);
                final box = artBoxOf(def);
                final art = artPlacement(
                  local,
                  baseWidth: box.baseWidth,
                  anchorX: box.anchorX,
                  lift: box.lift,
                );
                return Positioned(
                  left: art.left,
                  width: art.width,
                  bottom: local.height - art.bottom,
                  child: BuildingIcon(
                    imageUrl: def.imageUrl,
                    defId: def.id,
                    width: art.width,
                    anchorBottomOverflowTop: true,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── Screen-space controls ─────────────────────────────────
  // Everything below is drawn in the VIEWPORT's coordinates rather than the
  // map's, so a button stays thumb-sized however far the map is zoomed out. The
  // map's own matrix is applied by hand ([MatrixUtils]) to work out where each
  // one belongs.

  /// The midpoint of the footprint edge that faces (dx, dy), after the map's
  /// own transform — where that direction's arrow belongs on screen.
  Offset _edgeAnchor(int gx, int gy, int w, int h, int dx, int dy) =>
      MatrixUtils.transformPoint(
        _txCtrl.value,
        isoEdgeMidpoint(gx, gy, w, h, dx, dy),
      );

  /// One direction arrow, sitting just outside the edge it belongs to and
  /// pointing the way it would move things.
  Widget _arrowButton({
    required Offset at,
    required int dx,
    required int dy,
    required double size,
    required Color color,
    required VoidCallback onTap,
  }) {
    final angle = isoScreenAngle(dx, dy);
    final centre =
        at + Offset(math.cos(angle), math.sin(angle)) * (size * 0.55);
    return Positioned(
      left: centre.dx - size / 2,
      top: centre.dy - size / 2,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Transform.rotate(
            angle: angle,
            child: Icon(
              Icons.arrow_forward_rounded,
              size: size * 0.58,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required double size,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    ),
  );

  /// The ✓/✗ pair, ABOVE whatever is being aimed and always on screen — a
  /// confirm button that has slid off the top edge is a session you cannot
  /// leave (which is how the road banner got buried once already).
  Widget _confirmBar({
    required Rect anchor,
    required VoidCallback onOk,
    required VoidCallback onCancel,
  }) {
    final view = _viewport ?? const Size(400, 800);
    const barW = 108.0;
    // math.max on the upper bound: clamp() throws when the two ends cross, and
    // on a viewport narrower than the bar itself they would.
    final left = (anchor.center.dx - barW / 2)
        .clamp(8.0, math.max(8.0, view.width - barW - 8))
        .toDouble();
    // 80, not "just above": the up-and-right arrow reaches ~30px over the
    // footprint's north corner, and on a ROAD — whose box IS one tile — a
    // tighter gap puts the ✓ under the arrow the player is tapping.
    final top = (anchor.top - 80)
        .clamp(8.0, math.max(8.0, view.height - 100))
        .toDouble();
    return Positioned(
      left: left,
      top: top,
      width: barW,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _roundButton(
            icon: Icons.close_rounded,
            color: kParchmentDeep,
            size: 40,
            onTap: onCancel,
          ),
          _roundButton(
            icon: Icons.check_rounded,
            color: kActionGreen,
            size: 40,
            onTap: onOk,
          ),
        ],
      ),
    );
  }

  /// Everything that hangs off the ghost: the box you grab it by, the four
  /// arrows, the ✓/✗ and — when the ghost is a building that already stands —
  /// the 🗑.
  List<Widget> _aimControls(BuildingDef def, int gx, int gy) {
    final rect = MatrixUtils.transformRect(
      _txCtrl.value,
      _artRect(def, gx, gy),
    );
    final canDelete =
        _aimMoveId != null && !def.isMainBuilding && !def.isBuildPlot;
    return [
      // THE GRAB BOX, and nothing wider. It covers the building alone, so a
      // finger set down beside it reaches the InteractiveViewer underneath and
      // pans the map — "wenn ich daneben mit dem Finger bin, dann kann ich
      // scrollen", with no mode to switch between the two.
      Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _ghostDragStart,
          onPanUpdate: _ghostDragUpdate,
          onPanEnd: (_) => _stopDrag(),
          onPanCancel: _stopDrag,
        ),
      ),
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
        _arrowButton(
          at: _edgeAnchor(gx, gy, def.gridW, def.gridH, dx, dy),
          dx: dx,
          dy: dy,
          size: 28,
          color: FoE.accentBlue,
          onTap: () => _nudge(dx, dy),
        ),
      if (canDelete)
        Positioned(
          left: rect.right + 2,
          top: rect.bottom - 34,
          child: _roundButton(
            icon: Icons.delete_outline_rounded,
            color: Colors.red.shade700,
            size: 32,
            onTap: _deleteAimed,
          ),
        ),
      _confirmBar(anchor: rect, onOk: _confirmAim, onCancel: _cancelAim),
    ];
  }

  /// The chain's arrows: bigger than the aiming ones ("dann werden die Pfeile
  /// aktiv (grösser)"), green while laying road and RED while tearing it up.
  List<Widget> _chainControls() {
    final colour = _chainErase ? Colors.red.shade700 : kActionGreen;
    final rect = MatrixUtils.transformRect(
      _txCtrl.value,
      isoBounds(_chainX, _chainY, 1, 1),
    );
    return [
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
        _arrowButton(
          at: _edgeAnchor(_chainX, _chainY, 1, 1, dx, dy),
          dx: dx,
          dy: dy,
          size: 40,
          color: colour,
          onTap: () => _chainStep(dx, dy),
        ),
      // The ✓/✗ follow the head of the chain, so the way out is always beside
      // the tile you just touched rather than back where you started.
      _confirmBar(anchor: rect, onOk: _endChain, onCancel: _undoChain),
    ];
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

  Widget _bannerShell({
    required Widget leading,
    required String text,
    required Color colour,
    Widget? trailing,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: FoE.panel(radius: 8, overrideBorder: colour),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: FoE.label().copyWith(color: colour)),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );

  Widget _doneButton(String label, Color colour, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: ShapeDecoration(
            color: FoE.panelDark,
            shape: FoE.facet(radius: 5, side: BorderSide(color: colour)),
          ),
          child: Text(
            label,
            style: FoE.label(size: 11).copyWith(color: colour),
          ),
        ),
      );

  Widget _aimBanner(BuildingDef def) => _bannerShell(
    leading: BuildingIcon(imageUrl: def.imageUrl, defId: def.id, size: 16),
    colour: FoE.accentBlue,
    text: def.isRoad
        ? 'Drag the road into place, then ✓ to keep going'
        : _aimMoveId != null
        ? 'Drag ${def.name} where you want it  ·  ✓ to keep, ✗ to leave it'
        : 'Drag ${def.name} where you want it  ·  ✓ to build it here',
  );

  Widget _chainBanner() => _bannerShell(
    leading: Text(
      _chainErase ? '⛏️' : '🛤️',
      style: const TextStyle(fontSize: 16),
    ),
    colour: _chainErase ? FoE.danger : Colors.greenAccent,
    text: _chainErase
        ? 'Tap a red arrow to pull up the next road  ·  ✗ puts them all back'
        : 'Tap an arrow to lay the next road  ·  ✗ takes the whole run back',
  );

  Widget _editIdleBanner() => _bannerShell(
    leading: const Icon(Icons.open_with, color: FoE.accentBlue, size: 16),
    colour: FoE.accentBlue,
    text: 'Tap a building to pick it up',
    trailing: _doneButton(
      'Done',
      FoE.accentBlue,
      () => widget.onExitEditMode?.call(),
    ),
  );
}

// ── Building tile widget ──────────────────────────────────
class _BuildingTile extends StatelessWidget {
  final BuildingDef def;
  final PlacedBuilding building;

  /// For a road: which of its four neighbours are roads (see road_tiles.dart).
  /// Ignored for anything else.
  final int roadMask;

  const _BuildingTile({
    required this.def,
    required this.building,
    this.roadMask = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (def.isRoad) {
      // ── A ROAD PICKS ITS OWN PIECE (user 2026-08-09) ──
      // Sixteen bundled tiles, one per neighbour combination, so a crossroads
      // is a crossroads and a corner is a curve without anyone choosing. The
      // art is rendered to exactly the cell's diamond, so it needs no clip and
      // no fit: filling the box IS lining up with the grid, and a tile scaled
      // by anything else would leave a seam at every junction.
      //
      // ── image_url IS IGNORED HERE, and that is the point ──
      // It was honoured first, as an escape hatch, and it turned the feature
      // off for the only person who had ever used it: the live road def carried
      // an uploaded picture, so the map went on drawing one flat tile at every
      // junction and the whole thing looked like it had not shipped (user
      // 2026-08-09: "es sind noch die alten Strassen").
      //
      // There is no version of that escape hatch worth having. One picture per
      // def is exactly the thing a road cannot use — a road's whole job is to
      // be a different shape depending on what is next to it, and no single URL
      // can be sixteen shapes. Honouring the column meant honouring a value
      // that contradicts the requirement.
      return Image.asset(
        roadAsset(roadMask),
        width: kIsoTileW,
        height: kIsoTileH,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        // A road cell is 64 x 32 on screen. Decoding the tile at its source
        // size and then drawing it at a tenth of that is the same texture
        // waste the buildings had — and there are far more road cells than
        // buildings. 256 keeps it sharp at the map's maximum zoom.
        cacheWidth: 256,
        // The flat diamond is still the floor under this: an asset that failed
        // to load must not leave a hole where a road is, because the road is
        // what the player just paid for and placed.
        errorBuilder: (_, _, _) => CustomPaint(
          size: const Size(kIsoTileW, kIsoTileH),
          painter: _RoadDiamondPainter(color: def.color),
        ),
      );
    }

    if (def.isBuildPlot && building.isComplete) {
      // The stakes-and-rope survey marker is there to show WHERE the plot
      // is while it's still just a reward waiting to be placed — once it's
      // actually built, it has done its job. A build plot IS its ground
      // (user 2026-08-31: "soll das asset verschwinden, damit eine freie
      // Fläche vorherrscht"), so a finished one draws nothing here and the
      // plain buildable tile underneath is the whole picture again.
      return const SizedBox.shrink();
    }

    final done = building.isComplete;
    final queued = building.isQueued;
    // Bundled art counts as having a picture — otherwise the twenty buildings
    // that ship with one would still draw the decorative placeholder box on a
    // database that has never had an upload, which is every fresh install.
    final hasImage =
        buildingAsset(def.id) != null ||
        (def.imageUrl != null && def.imageUrl!.isNotEmpty);

    // The PNG is shown completely bare — no border, no background,
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
      // PLACED BY ITS BASE (user 2026-08-01: "So ist das Gebäude zu weit
      // hinten"). The picture is scaled so its GROUND BASE is as wide as the
      // footprint and slid so that base's foot sits on the footprint's — which
      // is not the same as fitting the image to the tile, because generated art
      // comes back square with the building somewhere inside it.
      // LOCAL: this is drawn inside the tile, so the map's origin must not be
      // in it. isoBounds would carry it and push the art a map-width sideways.
      final bounds = isoLocalBounds(def.gridW, def.gridH);
      final box = artBoxOf(def);
      final art = artPlacement(
        bounds,
        baseWidth: box.baseWidth,
        anchorX: box.anchorX,
        lift: box.lift,
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: art.left,
            width: art.width,
            // The box is the footprint's; the picture may sit lower than its
            // foot when the art has air under the base.
            bottom: bounds.height - art.bottom,
            child: BuildingIcon(
              imageUrl: def.imageUrl,
              defId: def.id,
              width: art.width,
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

/// Smoke and lamplight over one building, placed in the SPRITE's box rather
/// than the tile's (2026-08-04).
///
/// That distinction is the whole widget. The tile's box is the footprint's
/// bounding rectangle; the art hangs from its bottom edge and runs upward as
/// far as it likes, so a chimney measured as a fraction of the PICTURE lands
/// nowhere near the same fraction of the tile. Reusing [artPlacement] here is
/// what keeps the smoke on the chimney when a building's three art numbers are
/// retuned in Dev Mode.
class _LifeOverlay extends StatelessWidget {
  final BuildingDef def;
  final int seed;

  const _LifeOverlay({required this.def, required this.seed});

  @override
  Widget build(BuildContext context) {
    final chimney = kChimneyAnchor[def.id];
    final local = isoLocalBounds(def.gridW, def.gridH);
    final box = artBoxOf(def);
    final art = artPlacement(
      local,
      baseWidth: box.baseWidth,
      anchorX: box.anchorX,
      lift: box.lift,
    );
    // The sprite is scaled to art.width and keeps its aspect; the map does not
    // know the image's true height, so the overlay box uses the same square-ish
    // reach the art gets and anchors to the art's bottom. Smoke sized off the
    // WIDTH (see the painter) is unaffected by that approximation.
    final h = art.width * 1.25;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: art.left,
          width: art.width,
          height: h,
          bottom: local.height - art.bottom,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              LampGlow(phaseSeed: seed),
              if (chimney != null)
                ChimneySmoke(
                  anchorX: chimney.$1,
                  anchorY: chimney.$2,
                  phaseSeed: seed,
                ),
            ],
          ),
        ),
      ],
    );
  }
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
