import '../../../core/ui/feel.dart';
import 'dart:async';
import 'dart:math' show max;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/strategy_theme.dart'
    show chunkyDecoration, strategyDarken;
import '../../../core/ui/duration_format.dart';
import '../../../core/ui/snack.dart';
import '../../creatures/models/creature_enums.dart' show kHealingHutBuildingId;
import '../../onboarding/intro_flow.dart';
import '../../onboarding/intro_spotlight.dart';
import '../data/building_art.dart';
import '../data/building_model.dart';
import '../data/building_definitions.dart';
import '../data/iso_grid.dart';
import '../data/resource_icons.dart';
import '../data/road_tiles.dart';
import '../sheets/building_detail_dialog.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import '../../social/social_actions.dart' show confirmDialog;
import 'building_carousel.dart' show buildingCarouselHeight;
import 'animated_building_art.dart';
import 'building_icon.dart';
import 'building_life.dart';
import 'road_walkers.dart';
import 'terrain_layer.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import '../../creatures/services/creatures_controller.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';

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

  /// Distinguishes the TWO doors into edit mode (user 2026-09-22: "wenn ich
  /// lange auf ein Gebäude drücke, [soll] ich nur dieses [verschieben] …
  /// Dafür gibt es ja jetzt den Bearbeitungsmodus"):
  ///
  /// * `false` — a long-press picked this building up. It is a single
  ///   errand: [_confirmAim] leaves edit mode again the moment this ONE move
  ///   lands, exactly like moving it used to work before Umbaumodus existed.
  /// * `true` — opened explicitly (the Build menu's own right-edge button),
  ///   for a session that rearranges as many buildings as the player likes
  ///   and also offers "Alle Gebäude zurücknehmen" (see
  ///   SettlementController.recallAllBuildings) — the FoE-style tool that
  ///   takes the whole city off the map at once so a full replan never has
  ///   to shuffle around whatever is still standing in the way.
  ///
  /// Tapping a building directly ON THE MAP moves just that one exactly as
  /// before either way — this only changes what happens to the SESSION once
  /// that move confirms.
  final bool persistentEditMode;

  /// A building the map should show as SELECTED — what a just-built one is set
  /// to (user 2026-07-30), so the drag that positions it needs no extra tap to
  /// pick it up first. Changing this value selects; null leaves the selection
  /// alone.
  final String? selectBuildingId;

  /// Fires true the moment something starts being aimed (a fresh purchase, a
  /// direct move, or [selectBuildingId] handing one over) and false the
  /// moment that session's ghost is gone — confirmed OR cancelled (user
  /// 2026-09-22): the screen's own Umbaumodus tray carousel has to get out
  /// of the way while the player is actually positioning a ghost, the same
  /// way it already hides while a brand-new purchase is being aimed. Fired
  /// from a post-frame callback, never mid-build — see [_notifyAiming].
  final ValueChanged<bool>? onAimingChanged;

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
    this.persistentEditMode = false,
    this.selectBuildingId,
    this.onAimingChanged,
  });

  @override
  State<SettlementMap> createState() => SettlementMapState();
}

// Public (not underscored) so the settlement screen can hold a
// GlobalKey<SettlementMapState> and route the tutorial's CTAs straight into
// a building's dialog — see openBuildingByType.
class SettlementMapState extends State<SettlementMap>
    with TickerProviderStateMixin {
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
  /// The ghost's quarter turns (user 2026-11-03: "Gebäude um 90° drehen").
  int _aimRotation = 0;

  /// The aimed building's def, turned the way the ghost is.
  BuildingDef? _aimDefOf(String? type) =>
      type == null ? null : defRotated(type, _aimRotation);
  String? _aimMoveId; // set when the ghost IS a building already on the map
  int? _aimX, _aimY; // the cell the ghost's north-west corner sits on

  bool get _aiming => _aimType != null;

  /// True while the ghost being aimed must not move — the tutorial's own
  /// Healing Hut and the one road tile that has to connect it to the Castle
  /// (user 2026-09-30: "gib die Position ... vor, so dass ich immer genau am
  /// gleichen Ort bauen muss und es auch nicht schieben kann", same ask for
  /// the road). Only the road's FIRST tile — once it is confirmed, the
  /// session becomes a chain the player extends with the arrow brush, not a
  /// draggable ghost any more.
  bool get _tutorialPlacementLocked {
    final step = widget.ctrl.introStep;
    if (_aimType == kHealingHutBuildingId) {
      return step == IntroStep.buildHealingHut;
    }
    if (_aimType == 'road' && !_chaining) return step == IntroStep.buildRoad;
    return false;
  }

  /// The fixed cell [typeId] must open on while [_tutorialPlacementLocked]
  /// would apply to it, or null outside those two cases.
  (int, int)? _lockedSpotFor(String typeId) => switch (typeId) {
    kHealingHutBuildingId when widget.ctrl.introStep == IntroStep.buildHealingHut =>
      (kTutorialHealingHutX, kTutorialHealingHutY),
    'road' when widget.ctrl.introStep == IntroStep.buildRoad =>
      (kTutorialRoadX, kTutorialRoadY),
    _ => null,
  };

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

  // ── Pinch-to-zoom THROUGH the grab box (user 2026-09-17: "der zoom
  // funktioniert während des Platzierens eines Gebäudes nicht") ──
  // The grab box below has to win single-finger gestures outright — a plain
  // pan/drag recognizer sitting over the ghost is what stops a finger
  // grabbing the building from also panning the map underneath it (see the
  // box's own comment). But a plain pan recognizer, once it owns a pointer,
  // never lets a SECOND finger that lands mid-gesture reach
  // InteractiveViewer's own scale recognizer underneath — Flutter routes
  // that second pointer's arena to whatever already claimed the first, not
  // to a sibling. A `ScaleGestureRecognizer` (onScale*, not onPan*) is the
  // one recognizer that natively keeps tracking a gesture as MORE fingers
  // join it, so it is what has to own the box either way; pinch then simply
  // needs its own arithmetic here, since InteractiveViewer's recognizer
  // never gets the chance to supply it.
  //
  // Anchored to the matrix/focal point from the moment the SECOND finger
  // joined ([_pinchBaseMatrix]/[_pinchBaseFocal]), not updated frame to
  // frame — so the map point first pinched stays under the fingers for the
  // whole gesture instead of drifting from compounding per-frame rounding.
  Matrix4? _pinchBaseMatrix;
  double? _pinchBaseGestureScale;
  Offset? _pinchBaseFocal;

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

  /// The camera's starting pose: fully zoomed out, looking at the STARTING PLOT.
  ///
  /// It used to be the middle of the whole map, but the plot sits near the map's
  /// top edge (user 2026-09-18: "ich sollte ... die ganze Baufläche sehen
  /// können") — so a phone opened onto empty ground with the settlement half
  /// out of frame. Clamped like every other camera move, so it can never show
  /// the void beyond the map.
  Matrix4 _homeTransform(double scale, Size view) {
    final home = gridToScreen(
      kInitialPlotX + kInitialPlotSize / 2,
      kInitialPlotY + kInitialPlotSize / 2,
    );
    return clampMapTransform(
      mapTransform(
        scale,
        view.width / 2 - home.dx * scale,
        view.height / 2 - home.dy * scale,
      ),
      view,
    );
  }

  /// Pans so [b] — its full ART, not just the ground tile — sits in the
  /// middle, clamped to the map's edges so the move can never reveal the void
  /// beyond it. Keeps whatever zoom the player already had unless
  /// [targetScale] says otherwise — a camera that also re-scaled on its own
  /// would ordinarily take away the view the player had chosen; the guided
  /// intro is the one caller that overrides it (see its own call site).
  ///
  /// Centers [isoArtBounds], not [isoBounds] (user 2026-10-01, "noch mehr
  /// schieben" on a screenshot of the Healing Hut's roof still hidden under
  /// the tutorial card even after the camera WAS centering on it): a
  /// building's picture rises above its own ground tile — that is the whole
  /// point of [isoArtBounds] vs. the footprint alone, see its doc comment —
  /// so centering the FOOTPRINT leaves the art's top edge sitting however far
  /// above the centre line its own height happens to be, which for a
  /// roofed building is well past halfway into whatever chrome sits above
  /// the view. Roads/plots have no art above their tile, so they fall back to
  /// the ground box, same as the non-art branch [_artRect] already uses for
  /// them.
  void focusBuilding(
    PlacedBuilding b, {
    double? targetScale,
    double topInset = 0,
    double bottomInset = 0,
  }) {
    final def = placedDefOf(b);
    if (def == null) return;
    final bounds = _artRect(def, b.gridX, b.gridY);
    _focusPoint(
      bounds.center,
      targetScale: targetScale,
      topInset: topInset,
      bottomInset: bottomInset,
    );
  }

  /// Zooms AND pans onto the Healing Hut the moment the map opens fresh on
  /// assignHealer/healStarter — whatever the home transform just picked (user
  /// 2026-10-01, screenshot of a zoomed-right-out map: "hier kann ich das
  /// healing hut gar nicht anwählen wegen der Kameraperspektive, bitte auf
  /// das Healing Hut einzoomen"). [isHealAnchor] already spotlights the hut
  /// wherever it sits, but a hole drawn off-screen at [minMapScale] is just
  /// as unreachable as no hole at all. The one caller of [focusBuilding] that
  /// overrides the player's own zoom on purpose — see its own doc comment.

  /// Which intro step [_focusHealAnchorForTutorial] has already zoomed the
  /// camera for — sticky per STEP rather than per initial layout. The first
  /// version of this fix only ever tried once, from the `!_txInitialized`
  /// block below: on an account where [widget.ctrl.buildings] was still
  /// mid-load on that very first frame, the Healing Hut wasn't in the list
  /// yet, [_focusHealAnchorForTutorial] no-opped, and nothing ever asked
  /// again — the camera was stuck on the zoomed-right-out home transform for
  /// the rest of the step (user 2026-10-01, a second screenshot of exactly
  /// that: "jetzt wieder auf das healing hut zoomen"). Calling it again on
  /// every build (see the unconditional postFrameCallback below) costs one
  /// cheap list scan and this guard, and keeps the one-shot "zoom once, then
  /// leave the player's own pan/zoom alone" behaviour once it DOES find the
  /// hut.
  IntroStep? _healFocusedStep;

  void _focusHealAnchorForTutorial() {
    final step = widget.ctrl.introStep;
    if (step != IntroStep.assignHealer && step != IntroStep.healStarter) {
      return;
    }
    if (_healFocusedStep == step) return;
    final hut = widget.ctrl.buildings
        .where((b) => b.buildingTypeId == kHealingHutBuildingId)
        .firstOrNull;
    if (hut == null) return;
    _healFocusedStep = step;
    focusBuilding(
      hut,
      targetScale: kFocusZoom,
      topInset: _introTopCardInset(),
      bottomInset: buildingCarouselHeight(context),
    );
  }

  /// How much of THIS widget's own top the pinned narration card covers right
  /// now, in the map's own local coordinates — measured off the card's real
  /// render box ([SettlementScreen] keys it with the same
  /// [IntroSpotlightAnchors] registry the map's own anchors use) rather than a
  /// guessed constant, since the card's height follows its body text (user
  /// 2026-10-01, screenshot of the Healing Hut hidden behind the card: "bitte
  /// die kamera so schieben, dass ich mehr von dem Healing hut sehe"). Falls
  /// back to a conservative estimate for the one frame before the card has
  /// been laid out.
  double _introTopCardInset() {
    const fallback = 190.0;
    final cardBox =
        IntroSpotlightAnchors.of('intro-top-card').currentContext
                ?.findRenderObject()
            as RenderBox?;
    final mapBox = context.findRenderObject() as RenderBox?;
    if (cardBox == null || mapBox == null || !cardBox.hasSize) {
      return fallback;
    }
    final bottomLocal = mapBox.globalToLocal(
      cardBox.localToGlobal(Offset(0, cardBox.size.height)),
    );
    return bottomLocal.dy.clamp(0.0, double.infinity);
  }

  /// [focusBuilding] for a footprint that is not (yet) a building — the
  /// ghost, which has no art loaded to measure, only its own diamond.
  void _focusCell(
    int gx,
    int gy,
    int w,
    int h, {
    double? targetScale,
    double topInset = 0,
    double bottomInset = 0,
  }) {
    // The footprint's own point on the diamond, not the middle of a rectangle.
    _focusPoint(
      gridToScreen(gx + w / 2, gy + h / 2),
      targetScale: targetScale,
      topInset: topInset,
      bottomInset: bottomInset,
    );
  }

  /// Pans/zooms so map-space point [centre] lands in the middle of the free
  /// band between [topInset] and [bottomInset] — the shared maths behind
  /// [_focusCell] (a footprint's own centre) and [focusBuilding] (a real
  /// building's full art bounds).
  ///
  /// [topInset]/[bottomInset] carve chrome that floats OVER the map (the
  /// tutorial's pinned narration card, the build tray) out of the vertical
  /// centering: without them this centers on the full viewport, which is not
  /// what the player can actually SEE when a card or tray covers part of it
  /// (user 2026-10-01: "bitte die kamera so schieben, dass ich mehr von dem
  /// Healing hut sehe").
  void _focusPoint(
    Offset centre, {
    double? targetScale,
    double topInset = 0,
    double bottomInset = 0,
  }) {
    final view = _viewport;
    if (view == null) return;
    final scale = targetScale ?? _txCtrl.value.getMaxScaleOnAxis();
    final mapW = isoCanvasSize.width * scale;
    final mapH = isoCanvasSize.height * scale;
    final cx = centre.dx * scale;
    final cy = centre.dy * scale;
    // The free band left between the chrome, clamped so a tutorial step on a
    // very short viewport never inverts it (insets this big would leave no
    // room at all).
    final freeTop = math.min(topInset, view.height / 2);
    final freeBottom = math.min(bottomInset, view.height / 2);
    final targetCy = freeTop + (view.height - freeTop - freeBottom) / 2;
    final tx = (view.width / 2 - cx)
        .clamp(math.min(0.0, view.width - mapW), 0.0)
        .toDouble();
    final ty = (targetCy - cy)
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

  // ── Monsters on the roads (user 2026-11-03) — see road_walkers.dart ──
  final RoadWalkers _walkers = RoadWalkers();
  late final Ticker _walkTicker = createTicker(_onWalkTick);
  Duration _walkLast = Duration.zero;

  void _onWalkTick(Duration elapsed) {
    final dt = (elapsed - _walkLast).inMicroseconds / 1e6;
    _walkLast = elapsed;
    // A long gap (the route was covered, the app was away) is not a sprint.
    _walkers.step(dt.clamp(0.0, 0.1));
  }

  /// Runs the walkers' clock only while there is someone to walk and the
  /// map is in its plain viewing state — while a building or road is being
  /// placed, a monster crossing the cursor would only get in the way.
  void _syncWalkers(bool show) {
    if (show) {
      _walkers.sync(
        widget.ctrl.roadCells,
        CreaturesController().battleReadyCreatures,
      );
    }
    final run = show && _walkers.walkers.isNotEmpty;
    if (run && !_walkTicker.isActive) {
      _walkLast = Duration.zero;
      _walkTicker.start();
    } else if (!run && _walkTicker.isActive) {
      _walkTicker.stop();
    }
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    _panCtrl.dispose();
    _txCtrl.dispose();
    _walkTicker.dispose();
    _walkers.dispose();
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
    // A building coming OUT OF THE UMBAUMODUS TRAY (user 2026-09-22) has no
    // real position to focus — its gridX/gridY are stale (see
    // PlacedBuilding.isStored) and may already sit under whatever else was
    // placed since it was recalled. Treated like a brand-new purchase
    // instead: dropped wherever the camera already is, exactly the "mittig
    // im Screen" promise below gives a fresh building.
    final fromStorage = b?.isStored ?? false;
    _stopDrag();
    setState(() {
      _dropChainState();
      _aimType = typeId;
      _aimMoveId = moveId;
      // A building being moved keeps the way it faces until turned.
      _aimRotation = b?.rotation ?? 0;
      _aimX = fromStorage ? null : b?.gridX;
      _aimY = fromStorage ? null : b?.gridY;
    });
    // "…dann erscheint es mittig im Screen." For something already standing
    // that means bringing the CAMERA to it; for something new — or something
    // coming out of storage — it means dropping it on whatever the camera is
    // already looking at. After the frame, because both need the viewport
    // this build is about to report.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _aimType != typeId || _aimMoveId != moveId) return;
      final locked = moveId == null ? _lockedSpotFor(typeId) : null;
      if (locked != null) {
        setState(() {
          _aimX = locked.$1;
          _aimY = locked.$2;
        });
        _focusCell(locked.$1, locked.$2, def.gridW, def.gridH);
      } else if (b != null && !fromStorage) {
        focusBuilding(b);
      } else {
        _dropGhostAtCentre(def);
      }
    });
    _notifyAiming(true);
  }

  /// See [SettlementMap.onAimingChanged]. Deferred to a post-frame callback
  /// — never called mid-build — because it can end up asking an ANCESTOR
  /// (the settlement screen) to [State.setState] of its own, which a widget
  /// still inside [_startAim]/[_clearAim]'s own `setState` call has no
  /// business triggering synchronously.
  void _notifyAiming(bool aiming) {
    final cb = widget.onAimingChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(aiming);
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
    if (!widget.ctrl.isPlacementValid(def.id, gx, gy, rotation: def.rotation)) {
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
      _aimRotation = 0;
      _aimX = null;
      _aimY = null;
    });
    _notifyAiming(false);
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
        ? await widget.ctrl.placeBuilding(type, x, y, rotation: _aimRotation)
        : await widget.ctrl.moveBuilding(moveId, x, y, rotation: _aimRotation);
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
    // Captured before advanceIntro moves the step past buildRoad (user
    // 2026-10-01: "wenn ich die Strasse baue, dann bitte nur eine bauen
    // lassen und mit dem Bestätigen wird diese sofort gebaut, das
    // Weiterziehmenü bleibt beim Tutorial aus") — the tutorial's one road
    // tile places and the session closes outright, with no hand-off to the
    // chain brush below.
    final isTutorialRoad =
        isNewRoad && widget.ctrl.introStep == IntroStep.buildRoad;
    if (isNewRoad) {
      unawaited(widget.ctrl.advanceIntro(IntroStep.buildRoad));
    }
    final chainHead = widget.ctrl.lastPlacedId;
    _clearAim();
    if (isNewRoad && chainHead != null && !isTutorialRoad) {
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
    // Edit mode STAYS on after a move in a PERSISTENT session (user
    // 2026-07-20/2026-09-22: opened from the Build menu's own right-edge
    // button), so several buildings — or the whole Umbaumodus tray — can be rearranged
    // in one visit. A single-shot session (a long-press picked this
    // building up outside any mode) is one errand: it closes the moment
    // this ONE move lands, exactly like a plain move used to work before
    // Umbaumodus existed.
    if (moveId != null && !widget.persistentEditMode) {
      widget.onExitEditMode?.call();
    }
    // Guided tutorial (user 2026-09-06): straight from a fresh Healing Hut
    // placement into its own detail dialog — instant-build-with-gold is one
    // tap away there, rather than leaving the player back on the bare map to
    // find the building again themselves.
    if (moveId == null &&
        type == kHealingHutBuildingId &&
        widget.ctrl.introStep == IntroStep.buildHealingHut) {
      openBuildingByType(type);
    }
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
          !(placedDefOf(hit)?.isRoad ?? false)) {
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
    if (_tutorialPlacementLocked) return;
    final type = _aimType;
    final def = _aimDefOf(type);
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

  void _ghostDragStart(Offset globalPosition) {
    if (_tutorialPlacementLocked) return;
    final type = _aimType;
    final def = _aimDefOf(type);
    if (def == null || _aimX == null || _aimY == null) return;
    final local = _mapLocal(globalPosition);
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

  void _ghostDragUpdate(Offset globalPosition) {
    if (!_dragging) return;
    final local = _mapLocal(globalPosition);
    _dragAt = local;
    _moveGhostTo(local);
  }

  void _stopDrag() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _dragAt = null;
    if (_dragging && mounted) setState(() => _dragging = false);
  }

  /// The grab box's own [GestureDetector.onScaleStart] — see the fields'
  /// doc comment for why this has to be scale-based rather than pan-based.
  /// A gesture starting with two fingers already down (rare, but possible)
  /// skips straight to pinch instead of grabbing the building with a
  /// meaningless single-finger position.
  void _ghostScaleStart(ScaleStartDetails d) {
    if (d.pointerCount >= 2) {
      _beginPinch(d.focalPoint);
      return;
    }
    _ghostDragStart(d.focalPoint);
  }

  void _ghostScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      if (_pinchBaseMatrix == null) {
        _stopDrag(); // a second finger joined mid-drag — hand off to pinch
        _beginPinch(d.focalPoint, gestureScale: d.scale);
        return;
      }
      _applyPinch(d.focalPoint, d.scale);
      return;
    }
    // Down to one finger — either it always was, or the other one just
    // lifted mid-pinch. Either way there is no live pinch any more; falling
    // through into a resumed drag from an unrelated position would jump the
    // building, so this only ever starts a FRESH drag, never resumes one.
    if (_pinchBaseMatrix != null) {
      _pinchBaseMatrix = null;
      _pinchBaseGestureScale = null;
      _pinchBaseFocal = null;
      return;
    }
    _ghostDragUpdate(d.focalPoint);
  }

  void _ghostScaleEnd(ScaleEndDetails d) {
    _pinchBaseMatrix = null;
    _pinchBaseGestureScale = null;
    _pinchBaseFocal = null;
    _stopDrag();
  }

  void _beginPinch(Offset focal, {double gestureScale = 1}) {
    _stopDrag();
    _pinchBaseMatrix = _txCtrl.value.clone();
    _pinchBaseGestureScale = gestureScale;
    _pinchBaseFocal = focal;
  }

  /// Re-derives the map transform from the PINCH'S OWN baseline each call
  /// (not incrementally from the last frame) — see the fields' doc comment.
  /// [_enforceBounds] (registered on [_txCtrl]) clamps whatever comes out of
  /// this to the same scale/pan bounds every other writer of the transform
  /// already honours, so an out-of-range pinch is corrected there rather
  /// than needing its own clamping here.
  void _applyPinch(Offset focal, double gestureScale) {
    final base = _pinchBaseMatrix!;
    final baseFocal = _pinchBaseFocal!;
    final baseScale = base.getMaxScaleOnAxis();
    final baseTranslation = base.getTranslation();
    final newScale = baseScale * (gestureScale / _pinchBaseGestureScale!);
    // The map-space point that sat under the fingers when the pinch began —
    // keeping IT under the (moving) focal point is what makes the zoom feel
    // anchored to the fingers instead of to the map's corner.
    final anchorX = (baseFocal.dx - baseTranslation.x) / baseScale;
    final anchorY = (baseFocal.dy - baseTranslation.y) / baseScale;
    _txCtrl.value = mapTransform(
      newScale,
      focal.dx - anchorX * newScale,
      focal.dy - anchorY * newScale,
    );
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
      final def = _aimDefOf(_aimType);
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
    // A road has no detail screen (user 2026-09-22) — it's ground, not a
    // building with stats/upgrades to show.
    if (hit != null && !(placedDefOf(hit)?.isRoad ?? false)) {
      _showDetail(hit);
    }
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
    if (placedDefOf(hit)?.isBuildPlot ?? false) return;
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
      // The map behind goes brown with the kit.
      barrierColor: CreamPalette.dim,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        // A cream card on the live map, like the building detail dialog it
        // confirms deleting FROM.
        child: SizedBox(
          width: 280,
          child: creamCard(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BuildingIcon(
                      imageUrl: def.imageUrl,
                      defId: def.id,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Delete ${def.name}?',
                        style: FoE.title(size: 15).copyWith(color: kBoxInk),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This cannot be undone.',
                  style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                ),
                const SizedBox(height: 18),
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

  /// The dialog's two buttons: Cancel raised cream, Delete in the warning
  /// colour with paper-coloured ink.
  Widget _dialogBtn(String label, VoidCallback onTap, {bool danger = false}) =>
      Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          decoration: danger
              ? chunkyDecoration(
                  fill: CreamPalette.warn,
                  deep: strategyDarken(CreamPalette.warn, 0.35),
                  radius: 14,
                  shadowOffset: 3,
                )
              : raisedTile(radius: 14),
          child: Text(
            label,
            style: FoE.label(size: 14).copyWith(
              color: danger ? CreamPalette.paperTop : kBoxInk,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );

  // ── Hit test ─────────────────────────────────────────────
  PlacedBuilding? _hitTest(int col, int row) {
    for (final b in widget.ctrl.buildings) {
      final def = placedDefOf(b);
      if (def == null) continue;
      // A finished Building Plot has already vanished visually (see
      // _BuildingTile) — it must stop catching taps too, or "empty" ground
      // would still pop up its detail sheet instead of doing nothing / letting
      // the tap reach whatever real building sits on that same tile.
      if (def.isBuildPlot && b.isComplete) continue;
      // A STORED building (Umbaumodus tray) isn't standing anywhere — its
      // gridX/gridY are stale and must never catch a tap.
      if (b.isStored) continue;
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
  void _showDetail(PlacedBuilding b) =>
      showBuildingDetailDialog(context, widget.ctrl, b, onMap: true);

  /// The buildings to paint, in order. [roads] picks the ground layer or the
  /// things standing on it.
  ///
  /// A def that has gone missing counts as NOT a road: it draws nothing either
  /// way, and guessing "ground" for something unknown is how a hole in the map
  /// ends up under everything.
  ///
  /// Sorted once per `buildings` list, not once per build: the settlement
  /// screen rebuilds this map on every controller notification (the 10 s tick,
  /// a chat message, a resource change …) and the sort — with a def lookup per
  /// comparison — is the heaviest part of a build. The controller replaces the
  /// list on every real change, so its identity is a sound key.
  List<PlacedBuilding> _sortedForPainting({required bool roads}) {
    final source = widget.ctrl.buildings;
    if (!identical(_sortedFor, source)) {
      _sortedFor = source;
      _sortedRoads = _sortLayer(source, roads: true);
      _sortedStanding = _sortLayer(source, roads: false);
      // Demolished buildings must not linger in the tile cache.
      if (_tileCache.length > source.length) {
        final live = {for (final b in source) b.id};
        _tileCache.removeWhere((id, _) => !live.contains(id));
      }
    }
    return roads ? _sortedRoads : _sortedStanding;
  }

  List<PlacedBuilding>? _sortedFor;
  List<PlacedBuilding> _sortedRoads = const [];
  List<PlacedBuilding> _sortedStanding = const [];

  /// Built tiles, reused while their building and the few things a tile
  /// depends on besides it are unchanged — see [_buildingTile]. A tile is a
  /// pure function of (the building, [_tileSignature]); handing Flutter the
  /// SAME widget instance lets it skip that whole subtree instead of
  /// re-running ~200 tile builds on every notification.
  final Map<
    String,
    ({PlacedBuilding building, BuildingDef def, int signature, Widget tile})
  >
  _tileCache = {};

  List<PlacedBuilding> _sortLayer(
    List<PlacedBuilding> source, {
    required bool roads,
  }) {
    final out = [
      for (final b in source)
        // A STORED building (Umbaumodus tray) isn't standing anywhere — it
        // paints in neither layer.
        if (!b.isStored &&
            (placedDefOf(b)?.isRoad ?? false) == roads)
          b,
    ];
    out.sort((a, b) {
      final ad = placedDefOf(a);
      final bd = placedDefOf(b);
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
    List<RoadWalker> walkers = const [],
  }) {
    // A ROAD ghost rides on TOP of the buildings layer, not in the roads layer
    // under it (user 2026-09-28: "wenn ein Gebäude davor ist, sehe ich die
    // Strasse kaum, auch wenn das Gebäude transparent wird"). Down there it sat
    // beneath everything that stands in front of it — a building faded to 30 %
    // still covers it. A road has no height to be hidden BEHIND anything, so it
    // is judged against the whole town.
    final roadOnTop = ghostDef != null && ghostDef.isRoad;
    final withGhost =
        ghostDef != null &&
        gx != null &&
        gy != null &&
        (roadOnTop ? !roads : ghostDef.isRoad == roads);
    final out = <Widget>[];
    var pending = withGhost;
    // Walkers, back to front, each slotted in before the first building that
    // stands in front of its cell — the same rule the ghost uses below.
    final queue = [...walkers]
      ..sort((a, b) {
        final (ax, ay) = a.drawCell;
        final (bx, by) = b.drawCell;
        return isoDrawOrder(ax, ay, 1, 1, bx, by, 1, 1);
      });
    var wi = 0;
    for (final b in _sortedForPainting(roads: roads)) {
      final d = placedDefOf(b);
      while (wi < queue.length) {
        final (wx, wy) = queue[wi].drawCell;
        if (isoDrawOrder(
              wx,
              wy,
              1,
              1,
              b.gridX,
              b.gridY,
              d?.gridW ?? 1,
              d?.gridH ?? 1,
            ) >=
            0) {
          break;
        }
        out.add(_walkerView(queue[wi++]));
      }
      if (pending &&
          !roadOnTop &&
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
        out.add(
          KeyedSubtree(
            key: const ValueKey('ghost'),
            child: _ghost(ghostDef.id, gx, gy),
          ),
        );
        pending = false;
      }
      // KEYED by building, so a walker slotting in between two tiles MOVES
      // the tiles after it instead of handing every one of them its
      // neighbour's widget (which would rebuild and repaint the whole town
      // each time a monster stepped onto a new cell).
      out.add(
        KeyedSubtree(
          key: ValueKey(b.id),
          child: _buildingTile(b, faded: faded.contains(b.id)),
        ),
      );
    }
    while (wi < queue.length) {
      out.add(_walkerView(queue[wi++]));
    }
    if (pending) {
      out.add(
        KeyedSubtree(
          key: const ValueKey('ghost'),
          child: _ghost(ghostDef!.id, gx!, gy!),
        ),
      );
    }
    return out;
  }

  Widget _walkerView(RoadWalker w) => RoadWalkerView(
    key: ValueKey('walker:${w.creature.id}'),
    walker: w,
    walkers: _walkers,
  );

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
      final d = placedDefOf(b);
      if (d == null || d.isRoad || d.isBuildPlot || b.isStored) continue;
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
    final ghostDef = _aimDefOf(_aimType);
    final gx = _aimX, gy = _aimY;
    final showGhost = ghostDef != null && gx != null && gy != null;
    final faded = showGhost
        ? _fadedBehindGhost(ghostDef, gx, gy)
        : const <String>{};
    final walkersShown =
        !showGhost && !_chaining && !widget.editMode && !widget.roadMode;
    _syncWalkers(walkersShown);

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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _txCtrl.value = _homeTransform(minScale, view);
            _focusHealAnchorForTutorial();
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
            _txCtrl.value = _homeTransform(minScale, view);
          });
        }

        // Retried every build, not just the first one — see
        // [_healFocusedStep]'s own doc comment on why the one-shot attempt
        // above is not enough by itself.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusHealAnchorForTutorial();
        });

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
                      // Replaced the single baked map_background.png (user
                      // 2026-09-07: "der Background muss wirklich noch
                      // deutlich überarbeitet werden... genau gleich
                      // aufgelöst [wie] die Gebäude") — matching the
                      // buildings' own sharpness across the WHOLE map in one
                      // image would need a ~117760×58880px source (measured:
                      // ~270 px/world-unit for a building vs ~22 for the old
                      // whole-map bake), tens of gigabytes. TerrainLayer
                      // tiles a small, sharp ground swatch and places detail
                      // props individually instead — see its own doc comment.
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: TerrainLayer(
                            buildableRegion: widget.ctrl.buildableRegion,
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
                      // BACK TO FRONT among themselves — and the monsters
                      // walking the roads among them (user 2026-11-03), so a
                      // building in front of a walker hides it. Its own
                      // Stack under a listener: a walker stepping onto a new
                      // cell re-sorts THIS layer only, not the whole map.
                      Positioned.fill(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _walkers.order,
                          builder: (context, _, _) => Stack(
                            clipBehavior: Clip.none,
                            children: _layer(
                              roads: false,
                              ghostDef: ghostDef,
                              gx: gx,
                              gy: gy,
                              faded: faded,
                              walkers: walkersShown
                                  ? _walkers.walkers
                                  : const [],
                            ),
                          ),
                        ),
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
            if (!_chaining && !showGhost && widget.editMode)
              _bottomBanner(_editIdleBanner(), maxWidth: 620),
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
    final def = placedDefOf(b);
    if (def == null) return const SizedBox.shrink();
    // Everything a tile looks like, other than the building itself, folded
    // into one int. `PlacedBuilding` is immutable (every change is a copyWith
    // into a new list), so an unchanged building is the SAME object from one
    // tick to the next and (building identity, signature) is a complete cache
    // key.
    final isGhostSrc = b.id == _aimMoveId;
    final isDisconnected =
        b.isComplete &&
        !def.isRoad &&
        !def.isMainBuilding &&
        !widget.ctrl.connectedBuildingIds.contains(b.id);
    final roadMask = def.isRoad ? _roadMaskOf(b) : 0;
    final isHealAnchor =
        b.buildingTypeId == kHealingHutBuildingId &&
        widget.ctrl.introStep == IntroStep.assignHealer;
    final signature =
        (faded ? 1 : 0) |
        (isGhostSrc ? 2 : 0) |
        (isDisconnected ? 4 : 0) |
        (isHealAnchor ? 8 : 0) |
        (roadMask << 4);
    final hit = _tileCache[b.id];
    // The def is part of the key: Dev Mode replaces defs (art, footprint)
    // without touching the placed buildings.
    if (hit != null &&
        identical(hit.building, b) &&
        identical(hit.def, def) &&
        hit.signature == signature) {
      return hit.tile;
    }
    final tile = _composeTile(
      b,
      def,
      faded: faded,
      isGhostSrc: isGhostSrc,
      isDisconnected: isDisconnected,
      isHealAnchor: isHealAnchor,
      roadMask: roadMask,
    );
    _tileCache[b.id] = (
      building: b,
      def: def,
      signature: signature,
      tile: tile,
    );
    return tile;
  }

  int _roadMaskOf(PlacedBuilding b) =>
      roadMask(widget.ctrl.roadCells, b.gridX, b.gridY);

  Widget _composeTile(
    PlacedBuilding b,
    BuildingDef def, {
    required bool faded,
    required bool isGhostSrc,
    required bool isDisconnected,
    required bool isHealAnchor,
    required int roadMask,
  }) {
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
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        // Isolated raster: the whole buildings layer rebuilds on every 5s
        // tick, but a tile's art only changes when the building does, so a
        // RepaintBoundary keeps the tick from repainting all ~200 tiles.
        // Doubles as the guided tutorial's spotlight anchor for this ONE
        // building during assignHealer (user 2026-09-06: "lass mich das
        // Gebäude anklicken") — see SettlementScreen._soloQuickPadAnchor.
        RepaintBoundary(
          key: isHealAnchor
              ? IntroSpotlightAnchors.of('map-healing-hut')
              : null,
          child: _BuildingTile(
            def: def,
            building: b,
            // Which junction this road is. Computed by the map rather than
            // the tile because only the map can see the neighbours, and it
            // has the controller's cached cell set to see them cheaply.
            roadMask: roadMask,
            isDisconnected: isDisconnected,
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
        // DISCONNECTED (user 2026-09-30: "sieht man dies noch nicht gut"):
        // the ground-footprint wash this used to be dropped — now that the
        // art itself is tinted red (see [_BuildingTile]), a second red wash
        // under it added noise, not clarity. A white-backed badge instead,
        // big enough to read at map scale and visible against ground OR
        // the now-red art alike. A crossed-out road (user 2026-09-30: "den
        // Badge durch eine durchgestrichene Strasse ersetzen"), not a generic
        // no-entry sign — [Icons.remove_road] already names exactly what's
        // missing, and it's the same glyph the chain-erase button uses.
        if (isDisconnected)
          Positioned(
            top: 1,
            left: 1,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.rectangle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Color(0x99000000), blurRadius: 2),
                ],
              ),
              child: const PixelIcon(Icons.remove_road, size: 11, color: FoE.danger),
            ),
          ),
        // PAUSED, on the map (user 2026-08-01): a switch you cannot see
        // from the outside is one you forget you flipped — and a building
        // that has quietly produced nothing for a week looks exactly like a
        // building that is working. "Schlaf-Z mit der Graustufe von 1" (user
        // 2026-09-22): the art itself is greyed (see [_BuildingTile]) and sleepy
        // Zs rise where the smoke would — the dark rectangle over the whole field
        // (the ground included) and the 12 px ⏸ are gone.
        if (b.isPaused && b.isComplete && !def.isRoad && !def.isBuildPlot)
          Positioned.fill(
            child: _SleepOverlay(def: def, seed: b.id.hashCode),
          ),
      ],
    );
    return Positioned(
      left: iso.left,
      top: iso.top,
      width: iso.width,
      height: iso.height,
      // Only when it actually IS see-through. RenderOpacity is a repaint
      // boundary that composites through an OpacityLayer at ANY alpha above
      // zero — 1.0 included — so wrapping every tile unconditionally cost a
      // pointless layer per building, ~200 of them, on every frame.
      child: isGhostSrc || faded
          ? Opacity(opacity: 0.3, child: content)
          : content,
    );
  }

  Widget _ghost(String typeId, int gx, int gy) {
    final def = _aimDefOf(typeId)!;
    final free = widget.ctrl.isPlacementValid(
      typeId,
      gx,
      gy,
      excludeId: _aimMoveId,
      rotation: _aimRotation,
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
                    defId: def.artId,
                    width: art.width,
                    anchorBottomOverflowTop: true,
                  ),
                );
              },
            ),
          // THE ENTRANCE, over the art (user 2026-11-03: "Dieser Punkt soll
          // beim Bauen speziell markiert sein und betrifft immer eine ganze
          // Kachel"). Over, not under: the picture covers most of its own
          // footprint, and a mark you cannot see while aiming is no mark.
          if (entranceFor(def.artId, def.gridW, def.gridH) case final e?)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _EntrancePainter(
                    w: def.gridW,
                    h: def.gridH,
                    entrance: e,
                    hasRoad: () {
                      final (rx, ry) = entranceRoadCell(e, gx, gy);
                      return widget.ctrl.roadCells.contains(
                        roadCellKey(rx, ry),
                      );
                    }(),
                  ),
                ),
              ),
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
  /// pointing the way it would move things. Amber while laying road, the
  /// warning colour while tearing it up (the kit's own colours).
  Widget _arrowButton({
    required Offset at,
    required int dx,
    required int dy,
    required double size,
    required bool erase,
    required VoidCallback onTap,
  }) {
    final angle = isoScreenAngle(dx, dy);
    final centre =
        at + Offset(math.cos(angle), math.sin(angle)) * (size * 0.55);
    final fill = erase ? CreamPalette.warn : CreamPalette.gold;
    return Positioned(
      left: centre.dx - size / 2,
      top: centre.dy - size / 2,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.rectangle,
            boxShadow: [
              BoxShadow(
                color: erase
                    ? strategyDarken(fill, 0.35)
                    : CreamPalette.goldDeep,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Transform.rotate(
            angle: angle,
            child: PixelIcon(
              Icons.arrow_forward_rounded,
              size: size * 0.58,
              color: erase ? CreamPalette.paperTop : CreamPalette.ink,
            ),
          ),
        ),
      ),
    );
  }

  /// A round kit button inside the tag: raised cream (cancel, delete) or amber
  /// (confirm). A disabled one is the grey a card you cannot afford wears.
  Widget _tagButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    Color? ink,
  }) {
    final enabled = onTap != null;
    const size = 40.0;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            gradient: primary && enabled
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: enabled
                        ? const [CreamPalette.tileTop, CreamPalette.tileBottom]
                        : const [
                            CreamPalette.lockedTop,
                            CreamPalette.lockedBottom,
                          ],
                  ),
            color: primary && enabled ? CreamPalette.gold : null,
            boxShadow: [
              BoxShadow(
                color: !enabled
                    ? CreamPalette.lockedShadow
                    : primary
                    ? CreamPalette.goldDeep
                    : CreamPalette.tanShadow,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: PixelIcon(
            icon,
            size: 22,
            color: !enabled
                ? CreamPalette.ink.withValues(alpha: 0.4)
                : (ink ?? CreamPalette.ink),
          ),
        ),
      ),
    );
  }

  // The tag's little facts: a glyph and a figure, in the card's own ink.
  Widget _tagFact(IconData icon, String text, {Color? colour}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PixelIcon(icon, size: 12, color: colour ?? kBoxInkSoft),
      const SizedBox(width: 3),
      Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colour ?? kBoxInkSoft,
        ),
      ),
    ],
  );

  /// One cost, its glyph and its figure — the figure in the warning colour when
  /// the stock falls short of it.
  Widget _tagCost(String key, double value, Map<String, double> stock) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(resourceEmoji(key), style: const TextStyle(fontSize: 12)),
      const SizedBox(width: 2),
      Text(
        '${value.ceil()}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: (stock[key] ?? 0) >= value ? kBoxInk : CreamPalette.warn,
        ),
      ),
    ],
  );

  /// THE NAME TAG (user 2026-09-19, "Namensschild"): one cream card hanging on
  /// whatever is being aimed — its name, the facts that decide whether to build
  /// it (footprint, time, cost), a line saying whether it fits and, when it does
  /// not, WHY, and the ✗ / ✓ (and 🗑 for a building that already stands). It
  /// replaces the loose round buttons and the banner along the bottom.
  ///
  /// It floats above the anchor and always on screen — a confirm button that has
  /// slid off the top edge is a session you cannot leave (which is how the road
  /// banner got buried once already): when there is no room above it hangs
  /// BELOW instead. A disabled ✓ (no [onOk]) is a spot the game would refuse.
  ///
  /// [gap] is how far the tag floats clear of the anchor — the chain needs the
  /// bigger one to clear its arrows.
  Widget _nameTag({
    required Rect anchor,
    required String title,
    required List<Widget> facts,
    required String? status,
    required bool ok,
    required VoidCallback? onOk,
    // Null hides the button entirely rather than just disabling it (user
    // 2026-09-30, the tutorial's locked Healing Hut/road placement: "nur
    // den ok Button ist drückbar, der X wird hier gar nicht angezeigt") —
    // there is nothing to cancel BACK to once the spot is fixed, so
    // offering the choice at all would be a dead end wearing a live button.
    VoidCallback? onCancel,
    String cancelLabel = 'Cancel',
    VoidCallback? onDelete,
    VoidCallback? onRotate,
    double gap = 14,
  }) {
    final view = _viewport ?? const Size(400, 800);
    final w = math.min(344.0, view.width - 16);
    // Shorter when there is no status line to show.
    final h = status == null ? 64.0 : 84.0;
    final left = (anchor.center.dx - w / 2)
        .clamp(8.0, math.max(8.0, view.width - w - 8))
        .toDouble();
    final above = anchor.top - gap - h >= 8;
    final top = (above ? anchor.top - gap - h : anchor.bottom + gap)
        .clamp(8.0, math.max(8.0, view.height - h - 8))
        .toDouble();
    // The notch points at the anchor, and stays inside the card's own width.
    final notchX = (anchor.center.dx - left).clamp(24.0, w - 24).toDouble();
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: notchX - 8,
            top: above ? h - 9 : -7,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: above
                      ? CreamPalette.paperBottom
                      : CreamPalette.paperTop,
                  borderRadius: vr(3),
                  boxShadow: [
                    BoxShadow(
                      color: CreamPalette.tanShadow,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: creamCard(
              padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.title(size: 14.5).copyWith(color: kBoxInk),
                        ),
                        const SizedBox(height: 3),
                        // ONE line, always (user 2026-09-19: "immer die drei
                        // Ressourcen nebeneinander"): footprint, time and every
                        // cost side by side, scaled down rather than wrapped onto
                        // a second line the tag has no height for.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < facts.length; i++) ...[
                                if (i > 0) const SizedBox(width: 10),
                                facts[i],
                              ],
                            ],
                          ),
                        ),
                        // A line only when there is something to say — a spot
                        // that fits says nothing, and a footprint on top of a
                        // building is already red (user 2026-09-19: "damit
                        // alles kleiner wird").
                        if (status != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.rectangle,
                                  color: ok
                                      ? CreamPalette.better
                                      : CreamPalette.warn,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  status,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: ok
                                        ? CreamPalette.better
                                        : CreamPalette.warn,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (onRotate != null) ...[
                    _tagButton(
                      icon: Icons.rotate_90_degrees_cw_rounded,
                      label: 'Rotate',
                      onTap: onRotate,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (onDelete != null) ...[
                    _tagButton(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      onTap: onDelete,
                      ink: CreamPalette.warn,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (onCancel != null) ...[
                    _tagButton(
                      icon: Icons.close_rounded,
                      label: cancelLabel,
                      onTap: onCancel,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _tagButton(
                    icon: Icons.check_rounded,
                    label: 'Confirm',
                    onTap: onOk,
                    primary: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Whether the aimed spot is good, and if not why — the words the tag's status
  /// line shows. Placement rules first (the footprint), then what a NEW building
  /// still needs: its cost, and a free slot in the build queue. A building being
  /// moved costs nothing.
  ({String? text, bool ok}) _aimStatus(BuildingDef def, int gx, int gy) {
    final problem = widget.ctrl.placementProblem(
      def.id,
      gx,
      gy,
      excludeId: _aimMoveId,
      rotation: def.rotation,
    );
    // On top of another building has no words: the footprint is red already.
    if (problem != null) return (text: problem.label, ok: false);
    if (_aimMoveId == null) {
      final stock = widget.ctrl.resources?.asMap ?? const <String, double>{};
      final missing = [
        for (final e in def.resourceCost.entries)
          if ((stock[e.key] ?? 0) < e.value)
            '${resourceEmoji(e.key)} ${(e.value - (stock[e.key] ?? 0)).ceil()}',
      ];
      if (missing.isNotEmpty) {
        return (text: 'Missing ${missing.join('  ')}', ok: false);
      }
      final queueFull =
          def.constructionSeconds > 0 &&
          widget.ctrl.activeConstructionCount >= widget.ctrl.maxBuildSlots &&
          widget.ctrl.queuedConstructionCount >= widget.ctrl.maxQueueSlots;
      if (queueFull) return (text: 'The build queue is full', ok: false);
    }
    // A spot that fits says nothing.
    return (text: null, ok: true);
  }

  /// Everything that hangs off the ghost: the box you grab it by and the name
  /// tag with its ✗ / ✓ (and 🗑 when the ghost is a building that already
  /// stands).
  ///
  /// No nudge arrows here any more (user 2026-09-17: "brauche ich die Pfeile
  /// fürs verschieben nicht, da ich es mit drag n drop mache") — the grab box
  /// below already IS the move gesture; [_chainControls] keeps its own
  /// arrows, since laying a road has no drag to replace them with.
  List<Widget> _aimControls(BuildingDef def, int gx, int gy) {
    final rect = MatrixUtils.transformRect(
      _txCtrl.value,
      _artRect(def, gx, gy),
    );
    final moving = _aimMoveId != null;
    final canDelete = moving && !def.isMainBuilding && !def.isBuildPlot;
    final status = _aimStatus(def, gx, gy);
    final stock = widget.ctrl.resources?.asMap ?? const <String, double>{};
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
          onScaleStart: _ghostScaleStart,
          onScaleUpdate: _ghostScaleUpdate,
          onScaleEnd: _ghostScaleEnd,
        ),
      ),
      _nameTag(
        anchor: rect,
        title: def.name,
        facts: [
          _tagFact(Icons.crop_square, '${def.gridW}×${def.gridH}'),
          if (moving)
            _tagFact(Icons.open_with, 'Moving')
          else ...[
            if (def.constructionSeconds > 0)
              _tagFact(Icons.schedule, fmtDuration(def.constructionSeconds)),
            if (def.resourceCost.isEmpty)
              _tagFact(Icons.sell_outlined, 'Free')
            else
              for (final e in def.resourceCost.entries)
                _tagCost(e.key, e.value, stock),
          ],
        ],
        status: status.text,
        ok: status.ok,
        // A spot the game would refuse gets a grey ✓ — pressing it would only
        // bring up the reason the tag already states.
        onOk: status.ok ? _confirmAim : null,
        onCancel: _tutorialPlacementLocked ? null : _cancelAim,
        onDelete: canDelete ? _deleteAimed : null,
        onRotate: def.canRotate && !_tutorialPlacementLocked ? _rotateAim : null,
      ),
    ];
  }

  /// A quarter turn clockwise (user 2026-11-03). The ghost keeps its spot;
  /// where the turned footprint would hang off the map it slides back on.
  void _rotateAim() {
    final type = _aimType;
    if (type == null) return;
    Feel.tap();
    setState(() {
      _aimRotation = (_aimRotation + 1) % 4;
      final def = _aimDefOf(type);
      if (def != null && _aimX != null && _aimY != null) {
        _aimX = _aimX!.clamp(0, kGridCols - def.gridW);
        _aimY = _aimY!.clamp(0, kGridRows - def.gridH);
      }
    });
  }

  /// While erasing, an arrow toward empty ground or a non-road building has
  /// nothing left to pull up — leaving it on screen (user 2026-09-22: "wenn
  /// die letzte angrenzende Strasse gelöscht wurde, sollen die Pfeile
  /// verschwinden") would only invite a tap that just buzzes, see
  /// [_chainStep]'s own guard. Laying has no such restriction: any in-bounds
  /// tile is a legal next tile.
  bool _chainCanStep(int dx, int dy) {
    final nx = _chainX + dx, ny = _chainY + dy;
    if (nx < 0 || ny < 0 || nx >= kGridCols || ny >= kGridRows) return false;
    if (!_chainErase) return true;
    final hit = _hitTest(nx, ny);
    return hit != null && (placedDefOf(hit)?.isRoad ?? false);
  }

  /// The chain's arrows: bigger than the aiming ones ("dann werden die Pfeile
  /// aktiv (grösser)"), amber while laying road and red while tearing it up. The
  /// tag follows the head of the chain, so the way out is always beside the
  /// tile you just touched rather than back where you started.
  List<Widget> _chainControls() {
    final rect = MatrixUtils.transformRect(
      _txCtrl.value,
      isoBounds(_chainX, _chainY, 1, 1),
    );
    final laying = widget.ctrl.introStep == IntroStep.buildRoad;
    return [
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)])
        if (_chainCanStep(dx, dy))
          _arrowButton(
            at: _edgeAnchor(_chainX, _chainY, 1, 1, dx, dy),
            dx: dx,
            dy: dy,
            size: 40,
            erase: _chainErase,
            onTap: () => _chainStep(dx, dy),
          ),
      _nameTag(
        anchor: rect,
        // Clears the arrow above the head tile.
        gap: 64,
        title: _chainErase ? 'Removing road' : 'Road',
        facts: [
          _tagFact(
            _chainErase ? Icons.remove_road : Icons.add_road,
            _chainErase
                ? '${_chainRemoved.length} removed'
                : '${_chainBuilt.length} laid',
          ),
          _tagFact(Icons.sell_outlined, 'Free'),
        ],
        status: _chainErase
            ? 'Tap an arrow to pull up the next road'
            : laying
            // Reminds the player WHERE, not just how (user 2026-09-06).
            ? 'Keep going until it reaches the Healing Hut'
            : 'Tap an arrow to lay the next road',
        ok: true,
        onOk: _endChain,
        // ✗ takes the WHOLE run back — see [_undoChain].
        cancelLabel: 'Take the whole run back',
        onCancel: _undoChain,
      ),
    ];
  }

  // ── The move mode's bar ───────────────────────────────────
  /// Places a bar at the bottom of the map, clear of the header and inside the
  /// device's safe area, capped in width so it is not a banner across a wide
  /// screen.
  Widget _bottomBanner(Widget child, {double maxWidth = 520}) => Positioned(
    left: 10,
    right: 10,
    bottom: 10 + MediaQuery.of(context).viewPadding.bottom,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );

  /// Edit mode with nothing picked up: what to do, and the way out.
  ///
  /// Two tools live here now (user 2026-09-22): moving one building at a
  /// time, unchanged, and — in a PERSISTENT session only, see
  /// [SettlementMap.persistentEditMode] — "Alle Gebäude/Straßen
  /// zurücknehmen", the FoE-style tool that takes the whole city off the map
  /// into a tray. The TRAY ITSELF is no longer shown here (2026-09-22, "das
  /// Baumenü soll geöffnet werden… genau gleiche Oberfläche, aber nur mit
  /// den gespeicherten Gebäuden") — the settlement screen puts the Build
  /// carousel itself up in its place (see SettlementScreen._showTrayCarousel
  /// and BuildingCarousel's `trayBuildings`), so this banner has nothing left
  /// to draw while the tray is non-empty.
  Widget _editIdleBanner() {
    if (widget.ctrl.hasStoredBuildings) return const SizedBox.shrink();
    final canRecallBuildings =
        widget.persistentEditMode && widget.ctrl.recallableBuildings.isNotEmpty;
    final canRecallRoads =
        widget.persistentEditMode && widget.ctrl.recallableRoads.isNotEmpty;
    return creamCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PixelIcon(Icons.open_with, size: 18, color: kBoxAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tap a building to pick it up',
                  style: FoE.label(size: 13).copyWith(color: kBoxInk),
                ),
              ),
              if (!widget.persistentEditMode) ...[
                const SizedBox(width: 8),
                _doneButton(),
              ],
            ],
          ),
          // The bulk tools are only on offer in a real Umbaumodus session —
          // a long-press's single-shot errand has no use for them, and no
          // "Fertig" to gate anyway (it closes itself on its own move).
          if (canRecallBuildings) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _recallAllButton()),
                if (!canRecallRoads) ...[
                  const SizedBox(width: 8),
                  _doneButton(),
                ],
              ],
            ),
          ],
          if (canRecallRoads) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _recallAllRoadsButton()),
                const SizedBox(width: 8),
                _doneButton(),
              ],
            ),
          ],
          if (widget.persistentEditMode &&
              !canRecallBuildings &&
              !canRecallRoads) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: _doneButton()),
          ],
        ],
      ),
    );
  }

  /// "Recall all buildings" — asks first, since it visibly upends the whole
  /// town at once. The dialog is the one confirmation this tool gets;
  /// backing out afterwards (the tray carousel's own Cancel button, see
  /// SettlementScreen._cancelUmbaumodus) needs none, because it only ever
  /// puts things back the way they already were.
  Widget _recallAllButton() => _recallButton(
    icon: Icons.inventory_2_outlined,
    label: 'Recall all buildings',
    dialogTitle: 'Recall every building?',
    dialogBody:
        'Everything except the Castle, roads and Building Plots comes '
        'off the map and waits in the Build menu until you place it '
        'again. Closing before you place everything undoes the whole '
        'thing, so nothing is ever lost either way.',
    onConfirmed: widget.ctrl.recallAllBuildings,
  );

  /// "Recall all roads" (user 2026-09-22: "es braucht auch noch einen
  /// Button, um alle Strassen aufzuheben") — its OWN button, since roads
  /// were deliberately left out of [_recallAllButton] (their own erase-chain
  /// tool already covers reworking a network, and thirty tiny road tiles
  /// would drown out the real buildings in the tray). Shares the same tray
  /// and the same undo-on-close as the buildings tool.
  Widget _recallAllRoadsButton() => _recallButton(
    icon: Icons.route,
    label: 'Recall all roads',
    dialogTitle: 'Recall every road?',
    dialogBody:
        'Every road tile comes off the map and waits in the Build menu '
        'until you place it again. Closing before you place everything '
        'undoes the whole thing, so nothing is ever lost either way.',
    onConfirmed: widget.ctrl.recallAllRoads,
  );

  Widget _recallButton({
    required IconData icon,
    required String label,
    required String dialogTitle,
    required String dialogBody,
    required Future<void> Function() onConfirmed,
  }) => Pressable(
    onTap: () async {
      final ok = await confirmDialog(
        context,
        title: dialogTitle,
        body: dialogBody,
        confirmLabel: 'Recall all',
      );
      if (!ok || !mounted) return;
      Feel.tap();
      await onConfirmed();
    },
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: raisedTile(radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PixelIcon(icon, size: 15, color: kBoxAccent),
          const SizedBox(width: 6),
          Text(label, style: FoE.label(size: 12).copyWith(color: kBoxInk)),
        ],
      ),
    ),
  );

  Widget _doneButton() => Pressable(
    onTap: () => widget.onExitEditMode?.call(),
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.center,
      decoration: goldButton(),
      child: Text(
        'Done',
        style: FoE.title(size: 14).copyWith(color: goldButtonInk()),
      ),
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

  /// Not reached by any road (user 2026-09-30) — tints the art itself red,
  /// see [kDisconnectedFilter]. Paused wins when both apply: only one filter
  /// can draw the picture, and "asleep" is the building's own decision while
  /// "disconnected" is just a fact about the road network around it.
  final bool isDisconnected;

  const _BuildingTile({
    required this.def,
    required this.building,
    this.roadMask = 0,
    this.isDisconnected = false,
  });

  /// The picture of a FINISHED building: moving where its model has moving
  /// parts (see [AnimatedBuildingArt]), the still render otherwise. A site
  /// under construction stays still — nobody hangs washing on a scaffold.
  Widget _livingArt(double width, bool done) {
    final spec = animFor(def.artId, def.gridW, def.gridH);
    if (done && spec != null && buildingAsset(def.artId) != null) {
      return AnimatedBuildingArt(
        defId: def.artId,
        spec: spec,
        width: width,
        phaseSeed: building.id.hashCode,
      );
    }
    return BuildingIcon(
      imageUrl: def.imageUrl,
      defId: def.artId,
      width: width,
      anchorBottomOverflowTop: true,
      dimmed: !done,
    );
  }

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
        buildingAsset(def.artId) != null ||
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
          // Its shadow on the ground, UNDER the art — see
          // [BuildingGroundShadow]. A survey marker (an unbuilt plot) is not a
          // thing that stands, so it casts none.
          if (!def.isBuildPlot)
            Positioned(
              left: art.left,
              width: art.width,
              bottom: bounds.height - art.bottom,
              child: BuildingGroundShadow(
                imageUrl: def.imageUrl,
                defId: def.artId,
                width: art.width,
                dimmed: !done,
              ),
            ),
          Positioned(
            left: art.left,
            width: art.width,
            // The box is the footprint's; the picture may sit lower than its
            // foot when the art has air under the base.
            bottom: bounds.height - art.bottom,
            child: building.isPaused && building.isComplete
                // PAUSED (user 2026-09-22, "Schlaf-Z mit der Graustufe"): the art
                // loses its colour and a little of its light — see [kPausedFilter].
                ? ColorFiltered(
                    colorFilter: kPausedFilter,
                    child: BuildingIcon(
                      imageUrl: def.imageUrl,
                      defId: def.artId,
                      width: art.width,
                      anchorBottomOverflowTop: true,
                      dimmed: !done,
                    ),
                  )
                // DISCONNECTED (user 2026-09-30): the whole sprite goes red,
                // not just the ground tile under it — see [kDisconnectedFilter].
                : isDisconnected
                ? ColorFiltered(
                    colorFilter: kDisconnectedFilter,
                    child: _livingArt(art.width, done),
                  )
                : _livingArt(art.width, done),
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
    final chimney = kChimneyAnchor[def.artId];
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
          // ONE widget, not a Stack of two (2026-09-21): the glow and the
          // smoke share this box and the same clock, so they share a painter
          // and a repaint layer — see [BuildingLife].
          child: BuildingLife(chimney: chimney, phaseSeed: seed),
        ),
      ],
    );
  }
}

/// A paused building's Zs, in the same box the smoke has (see [_LifeOverlay]) —
/// from the chimney where the building has one, over the roof otherwise.
class _SleepOverlay extends StatelessWidget {
  final BuildingDef def;
  final int seed;

  const _SleepOverlay({required this.def, required this.seed});

  @override
  Widget build(BuildContext context) {
    final anchor = kChimneyAnchor[def.artId] ?? (0.58, 0.16);
    final local = isoLocalBounds(def.gridW, def.gridH);
    final box = artBoxOf(def);
    final art = artPlacement(
      local,
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
          height: art.width * 1.25,
          bottom: local.height - art.bottom,
          child: SleepZ(
            anchorX: anchor.$1,
            anchorY: anchor.$2,
            phaseSeed: seed,
          ),
        ),
      ],
    );
  }
}

/// The footprint diamond, filled and outlined — the ghost preview's "can I
/// build here" mark (2026-08-01). The disconnected-building wash this used to
/// double as (no outline, so it read as a flat area rather than a frame) is
/// gone now that a disconnected building's own art carries the warning — see
/// [kDisconnectedFilter] — so this is back to its one remaining job and the
/// outline is no longer optional.
class _FootprintPainter extends CustomPainter {
  final int w;
  final int h;
  final Color color;

  const _FootprintPainter({required this.w, required this.h, required this.color});

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
    canvas.drawPath(
      footprintPathLocal(w, h),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FootprintPainter old) =>
      old.w != w || old.h != h || old.color != color;
}

/// A building's entrance on its placement ghost: the entrance CELL of the
/// footprint as a gold tile, the cell in front of it — where the road has to
/// be — outlined (green when a road already lies there), and an arrow from
/// one to the other, so the question "where does my road have to go" is
/// answered while aiming rather than after placing.
class _EntrancePainter extends CustomPainter {
  final int w;
  final int h;
  final BuildingEntrance entrance;
  final bool hasRoad;

  const _EntrancePainter({
    required this.w,
    required this.h,
    required this.entrance,
    required this.hasRoad,
  });

  /// Grid point (gx, gy), relative to the footprint, in the footprint's own
  /// box — the same frame footprintPathLocal draws in.
  Offset _pt(double gx, double gy) =>
      Offset((h + gx - gy) * kIsoTileW / 2, (gx + gy) * kIsoTileH / 2);

  Path _cell(int cx, int cy) => Path()
    ..moveTo(_pt(cx.toDouble(), cy.toDouble()).dx, _pt(cx.toDouble(), cy.toDouble()).dy)
    ..lineTo(_pt(cx + 1.0, cy.toDouble()).dx, _pt(cx + 1.0, cy.toDouble()).dy)
    ..lineTo(_pt(cx + 1.0, cy + 1.0).dx, _pt(cx + 1.0, cy + 1.0).dy)
    ..lineTo(_pt(cx.toDouble(), cy + 1.0).dx, _pt(cx.toDouble(), cy + 1.0).dy)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final (cx, cy, dx, dy) = entrance;
    const gold = Color(0xFFFFC83D);
    final cell = _cell(cx, cy);
    canvas
      ..drawPath(cell, Paint()..color = gold.withValues(alpha: 0.45))
      ..drawPath(
        cell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = gold,
      );
    final road = _cell(cx + dx, cy + dy);
    final roadColor = hasRoad ? Colors.greenAccent : Colors.white;
    canvas
      ..drawPath(road, Paint()..color = roadColor.withValues(alpha: 0.22))
      ..drawPath(
        road,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = roadColor,
      );
    // The arrow: from the entrance cell's centre to the road cell's.
    final from = _pt(cx + 0.5, cy + 0.5);
    final to = _pt(cx + dx + 0.5, cy + dy + 0.5);
    final dir = to - from;
    final len = dir.distance;
    if (len <= 0) return;
    final u = dir / len;
    final n = Offset(-u.dy, u.dx);
    final tip = from + u * (len * 0.85);
    final tail = from + u * (len * 0.1);
    final head = len * 0.22;
    final arrow = Paint()
      ..color = gold
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(tail, tip, arrow)
      ..drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((tip - u * head + n * head * 0.6).dx, (tip - u * head + n * head * 0.6).dy)
          ..lineTo((tip - u * head - n * head * 0.6).dx, (tip - u * head - n * head * 0.6).dy)
          ..close(),
        Paint()..color = gold,
      );
  }

  @override
  bool shouldRepaint(_EntrancePainter old) =>
      old.w != w || old.h != h || old.entrance != entrance || old.hasRoad != hasRoad;
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
