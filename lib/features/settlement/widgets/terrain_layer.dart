import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, compute, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;

import '../data/building_definitions.dart' show kGridCols, kGridRows;
import '../data/iso_grid.dart';
import '../data/water_cells.dart' show kWaterRuns;
import 'building_icon.dart'
    show castShadowImage, kShadowTint, kShadowOpacity;

/// The settlement map's ground (user 2026-09-07: "der Background muss
/// wirklich noch deutlich überarbeitet werden... genau gleich aufgelöst
/// [wie] die Gebäude", then "Bäume als Scatterterrain und Dreck/Erde", then
/// "eine richtige Landschaft bauen... aktuell sind diese 'wild' verteilt").
///
/// It used to be ONE baked image for the whole map. Matching the buildings'
/// own sharpness at that scale would need a ~117760×58880px source (measured:
/// buildings render at ~270 px per world unit, the old single bake at ~22) —
/// tens of gigabytes, decodable on no device. So this is built the way the
/// buildings themselves are: small, sharp, individually-authored pieces —
///
///  * a small TILEABLE grass swatch (render_ground_tile.py), repeated as a
///    shader fill instead of stretched as one soft image,
///  * water drawn straight from [kWaterRuns] — the SAME data buildability
///    already reads, so the coastline you see and the one you can't build on
///    can never drift apart (the old baked image was a second, independent
///    copy of that coastline that had no such guarantee), and
///  * trees, wildflowers and stones grouped into GROVES/PATCHES/OUTCROPS,
///    not scattered independently at uniform random — a real landscape grows
///    in clumps (a stand of trees, a flower patch, a rock outcrop) — see
///    [_TerrainPainter._scatterProps]. (Dirt patches under the groves were
///    tried and then removed again, user 2026-09-29: "entferne bitte alle
///    dirt patches".)
class TerrainLayer extends StatefulWidget {
  /// Cells the player can currently build on (the starting plot plus every
  /// finished Building Plot's footprint — the settlement controller's own
  /// `buildableRegion`). Trees, stones and flowers keep off these — a
  /// building placed there would otherwise collide with them visually (user
  /// 2026-09-08: "für alle Gebiete, welche von mir bereits freigeschalten
  /// wurden: keine Bäume, Steine oder Blumen haben -> d.h nur den
  /// Untergrund, damit es keine Kollisionen mit den Gebäuden gibt"). The
  /// forest itself still covers every OTHER dry cell regardless of
  /// buildability, including the canvas's off-map padding — only this
  /// claimed land is bare.
  final Set<int> buildableRegion;

  const TerrainLayer({super.key, required this.buildableRegion});

  @override
  State<TerrainLayer> createState() => _TerrainLayerState();

  /// Loads the ground art and works the terrain out for [buildableRegion]
  /// BEFORE the map is on screen — the settlement screen awaits this behind
  /// its loading screen. Without it the first paint of the map had to do all
  /// of it (a scan of ~150k cells, the shore search and ~50k tree placements)
  /// on the UI thread, a visible freeze right as the game appeared.
  ///
  /// Never throws: a terrain that fails to load simply is not there, exactly
  /// as before.
  static Future<void> preload(Set<int> buildableRegion) => _TerrainData.load(
    buildableRegion,
  ).then<void>((_) {}, onError: (Object _) {});

  /// The seam levelling the ground tile goes through (see [_TerrainData
  /// ._levelled]), reachable so a test can hand it a picture.
  /// Test hook: paint every prop on its own (the pre-2026-11-03 path) instead
  /// of through the batched sprite sheets, so a test can compare the two.
  @visibleForTesting
  static bool debugDrawOneByOne = false;

  /// Test hook: no wind, no drifting water — the picture stands still, so a
  /// test can compare it pixel for pixel.
  @visibleForTesting
  static bool debugAnimate = true;

  @visibleForTesting
  static Future<ui.Image> levelTile(ui.Image image) =>
      _TerrainData._levelled(image);
}

class _TerrainLayerState extends State<TerrainLayer>
    with SingleTickerProviderStateMixin {
  _TerrainData? _data;

  /// Seconds of wind and water, advanced about 15 times a second — the
  /// terrain's moving half repaints on it, its still half never does.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  /// The animals walk on their own, faster clock (about 30 fps) — their
  /// layer is small, so repainting it often is cheap.
  final ValueNotifier<double> _fauna = ValueNotifier<double>(0);
  Ticker? _ticker;
  Duration _last = Duration.zero;
  Duration _lastFauna = Duration.zero;

  @override
  void initState() {
    super.initState();
    _resolve();
    if (TerrainLayer.debugAnimate) {
      _ticker = createTicker((elapsed) {
        if ((elapsed - _lastFauna).inMilliseconds >= 33) {
          _lastFauna = elapsed;
          _fauna.value = elapsed.inMilliseconds / 1000.0;
        }
        if ((elapsed - _last).inMilliseconds < 66) return;
        _last = elapsed;
        _time.value = elapsed.inMilliseconds / 1000.0;
      })..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _time.dispose();
    _fauna.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TerrainLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // By CONTENT: the controller hands out a fresh Set whenever it recomputes
    // its caches, and a new-but-equal region must not throw the terrain away.
    if (!setEquals(oldWidget.buildableRegion, widget.buildableRegion)) {
      _resolve();
    }
  }

  /// Picks up the terrain for the current region: instantly when it has been
  /// worked out already, otherwise in the background — the previous terrain
  /// stays on screen until the new one is ready (a plot completing grows the
  /// region), rather than the map going bare for a moment.
  void _resolve() {
    final region = widget.buildableRegion;
    final ready = _TerrainData.cached(region);
    if (ready != null) {
      _data = ready;
      return;
    }
    _TerrainData.load(region).then((data) {
      if (!mounted || !setEquals(widget.buildableRegion, region)) return;
      setState(() => _data = data);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    // Nothing to paint yet (the assets load asynchronously) — a blank frame
    // for a few milliseconds beats guessing at a filler colour that would
    // itself have to be kept in sync with the tile.
    if (data == null || data.images[_kGrass] == null) {
      return const SizedBox.shrink();
    }
    // Two layers: the still ground (grass, sand, shadows) is drawn once and
    // cached; the moving one (water, props) is redrawn as the time ticks.
    return SizedBox.fromSize(
      size: isoCanvasSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _TerrainPainter(data)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _TerrainLivePainter(data, _time)),
          ),
          RepaintBoundary(
            child: CustomPaint(painter: _FaunaPainter(data, _fauna)),
          ),
        ],
      ),
    );
  }
}

// ── What a prop is, as a number ─────────────────────────────────
// The terrain is planned in a background isolate, and a ui.Image cannot cross
// that boundary — so the plan speaks in these kind ids and the painter looks
// the picture up by them.
//
// Every prop picture is rendered in the BUILDINGS' pipeline (tool/blender/
// make_prop.py) at the buildings' pixel density, and is drawn at its native
// size, never rescaled ([_kPropPx]) — so a block of a tree is a block of a
// house. Size variety comes from different pictures, not from stretching one.
const int _kStoneA = 0, // stones: pebble-sized .. big
    _kStoneB = 1,
    _kStoneC = 2,
    _kStoneD = 3,
    _kStoneE = 4,
    _kStoneF = 5, // a handful of pebbles
    _kFlowersA = 6, // flower patches
    _kFlowersD = 9,
    _kBushA = 10, // bushes
    _kBushD = 13,
    _kConiferS = 14, // trees: small, medium, large
    _kConiferL = 16,
    _kBroadleafS = 17,
    _kBroadleafL = 19,
    _kDriftwoodA = 20,
    _kShellA = 22,
    _kTuft = 24,
    _kFern = 25,
    _kStump = 26,
    _kLog = 27,
    _kReeds = 28,
    // Landmarks (user 2026-11-05: ruins, a stranded boat ... "alles was die
    // Spielwelt lebendig machen kann"), rendered by make_life.py.
    _kRuinWall = 29,
    _kRuinTower = 30,
    _kRuinArch = 31,
    _kRuinColumns = 32,
    _kMenhirs = 33,
    _kWagon = 34,
    _kCampfire = 35,
    _kWell = 36,
    _kBoatWreck = 37,
    _kBoatRow = 38,
    _kWhaleRibs = 39,
    _kFlotsam = 40,
    _kGrass = 41,
    _kSandTile = 42,
    _kWaterTile = 43,
    // Animal pictures, drawn by the moving fauna layer (see [_FaunaPainter]).
    _kFSheepSe = 44,
    _kFSheepNe = 45,
    _kFSheepGraze = 46,
    _kFDeerSe = 47,
    _kFDeerNe = 48,
    _kFDeerGraze = 49,
    _kFRabbitSe = 50,
    _kFRabbitNe = 51,
    _kFGullSe = 52,
    _kFGullNe = 53,
    _kFDuckSe = 54,
    _kFDuckNe = 55,
    _kFGullUpSe = 56,
    _kFGullDownSe = 57,
    _kFGullUpNe = 58,
    _kFGullDownNe = 59,
    _kFCrab = 60,
    _kFButterOpen = 61,
    _kFButterShut = 62,
    _kFFoxSe = 63,
    _kFFoxNe = 64,
    _kFBoarSe = 65,
    _kFBoarNe = 66,
    _kFCowSe = 67,
    _kFCowNe = 68,
    _kFCowGraze = 69,
    _kFFrog = 70,
    _kFCrowUpSe = 71,
    _kFCrowDownSe = 72,
    _kFCrowUpNe = 73,
    _kFCrowDownNe = 74,
    _kFHawkSe = 75,
    _kFHawkNe = 76;

/// Image pixels per canvas pixel, for every prop picture: the render scale
/// (5) times the shipping density (960 / 1227) — the same number the
/// buildings' art is drawn at.
const double _kPropPx = 5 * 960 / 1227;

/// Stones are drawn at this fraction of their picture size, and the bottom
/// [_kStoneSink] of each picture is cut off so the rock sits sunk in the ground.
const double _kStoneScale = 0.6;
const double _kStoneSink = 0.28;

/// The remaining picture is squashed to this fraction of its height.
const double _kStoneFlat = 0.6;

/// The props that STAND, and so cast a shadow on the ground (user 2026-09-22:
/// "den Schatten jetzt auch auf den Rest der Map"). Flat things — flowers,
/// tufts, shells, driftwood — lie in the ground and have none worth drawing.
bool _castsShadow(int kind) =>
    kind <= _kStoneF ||
    (kind >= _kBushA && kind <= _kBroadleafL) ||
    kind == _kStump ||
    kind == _kLog ||
    (kind >= _kRuinWall && kind <= _kFlotsam && kind != _kWhaleRibs);

/// How deep each caster's shadow lies on the ground, as a fraction of its
/// picture's width (see `castShadowMask`'s `groundDepth`). A crown covers a
/// patch, so trees get a wide, SHALLOW ellipse; stones are compact.
double _shadowDepth(int kind) {
  if (kind >= _kConiferS && kind <= _kBroadleafL) return 0.14;
  if (kind >= _kBushA && kind <= _kBushD) return 0.10;
  return 0.08;
}

final List<String> _kAssets = [
  'assets/images/terrain/prop_stone_a.webp',
  'assets/images/terrain/prop_stone_b.webp',
  'assets/images/terrain/prop_stone_c.webp',
  'assets/images/terrain/prop_stone_d.webp',
  'assets/images/terrain/prop_stone_e.webp',
  'assets/images/terrain/prop_stone_f.webp',
  'assets/images/terrain/prop_flowers_a.webp',
  'assets/images/terrain/prop_flowers_b.webp',
  'assets/images/terrain/prop_flowers_c.webp',
  'assets/images/terrain/prop_flowers_d.webp',
  'assets/images/terrain/prop_bush_a.webp',
  'assets/images/terrain/prop_bush_b.webp',
  'assets/images/terrain/prop_bush_c.webp',
  'assets/images/terrain/prop_bush_d.webp',
  'assets/images/terrain/prop_conifer_s.webp',
  'assets/images/terrain/prop_conifer_m.webp',
  'assets/images/terrain/prop_conifer_l.webp',
  'assets/images/terrain/prop_broadleaf_s.webp',
  'assets/images/terrain/prop_broadleaf_m.webp',
  'assets/images/terrain/prop_broadleaf_l.webp',
  // Beach-only detail (user 2026-09-14: "der Strand soll noch Holz und
  // kleine Muscheln haben").
  'assets/images/terrain/prop_driftwood_a.webp',
  'assets/images/terrain/prop_driftwood_b.webp',
  'assets/images/terrain/prop_shell_a.webp',
  'assets/images/terrain/prop_shell_b.webp',
  'assets/images/terrain/prop_tuft.webp',
  'assets/images/terrain/prop_fern.webp',
  'assets/images/terrain/prop_stump.webp',
  'assets/images/terrain/prop_log_a.webp',
  'assets/images/terrain/prop_reeds.webp',
  for (final n in _kLandmarkFiles) 'assets/images/terrain/life_$n.webp',
  'assets/images/terrain/grass_tile.webp', // _kGrass
  'assets/images/terrain/sand_tile.webp', // _kSandTile
  'assets/images/terrain/water_tile.webp', // _kWaterTile
  for (final n in _kFaunaFiles) 'assets/images/terrain/life_$n.webp',
];

const List<String> _kLandmarkFiles = [
  'ruin_wall', 'ruin_tower', 'ruin_arch', 'ruin_columns', 'menhirs', 'wagon',
  'campfire', 'well', 'boat_wreck', 'boat_row', 'whale_ribs', 'flotsam', // 29..40
];

// In the order of the [_kFSheepSe]… ids.
const List<String> _kFaunaFiles = [
  'sheep_se', 'sheep_ne', 'sheep_graze', 'deer_se', 'deer_ne', 'deer_graze',
  'rabbit_se', 'rabbit_ne', 'gull_se', 'gull_ne', 'duck_se', 'duck_ne',
  'gullfly_up', 'gullfly_down', 'gullfly_up_ne', 'gullfly_down_ne', 'crab',
  'butterfly_open', 'butterfly_shut', 'fox_se', 'fox_ne', 'boar_se', 'boar_ne',
  'cow_se', 'cow_ne', 'cow_graze', 'frog', 'crow_up_se', 'crow_down_se',
  'crow_up_ne', 'crow_down_ne', 'hawk_se', 'hawk_ne',
];

/// The ground art plus the worked-out terrain for one region.
///
/// Everything here is shared app-wide and computed at most once per region:
/// the painter used to recompute all of it inside `paint()` — and the map
/// repainted whenever the controller swapped in an equal-but-new region set.
class _TerrainData {
  final Set<int> region;
  final List<ui.Image?> images;
  final _TerrainPlan plan;

  /// Each standing prop's cast shadow, by kind (null where it casts none), in
  /// the picture's own pixel grid — see [castShadowImage].
  final List<ui.Image?> shadows;

  /// The props, their shadows and the grass wash packed for batched drawing
  /// (see [_TerrainSheets]). Null only if building them failed — the painter
  /// then falls back to drawing every prop on its own.
  final _TerrainSheets? sheets;

  _TerrainData(
    this.region,
    this.images,
    this.plan, {
    this.shadows = const [],
    this.sheets,
  });

  /// Every prop as one sprite-sheet draw: an [RSTransform] and a source rect
  /// per prop, in the plan's own depth order. Worked out once per plan.
  /// The same props, re-posable every frame (see [_SwayBatch]).
  late final _SwayBatch? sway = sheets == null
      ? null
      : _SwayBatch.build(plan.props, images, sheets!.propSlots);

  /// Props that can stand in front of an animal (not rotated debris), as prop
  /// offsets sorted by their foot's screen y, with that y alongside and the
  /// tallest picture's height — the fauna layer redraws those over an animal
  /// that walks behind them.
  late final ({List<int> offsets, List<double> footY, double maxH}) occluders =
      () {
    final props = plan.props;
    final list = <(double, int)>[];
    var maxH = 0.0;
    for (var o = 0; o < props.length; o += _propStride) {
      final kind = props[o].toInt();
      final image = kind < images.length ? images[kind] : null;
      if (image == null || props[o + 6] != 0) continue;
      final destH = image.height / _kPropPx * props[o + 3];
      if (destH > maxH) maxH = destH;
      final foot = gridToScreen(
        props[o + 1] + 0.5 + props[o + 4],
        props[o + 2] + 0.5 + props[o + 5],
      );
      list.add((foot.dy, o));
    }
    list.sort((a, b) => a.$1.compareTo(b.$1));
    return (
      offsets: [for (final e in list) e.$2],
      footY: [for (final e in list) e.$1],
      maxH: maxH,
    );
  }();

  late final (Float32List, Float32List)? propBatch = sheets?.propBatch(
    plan.props,
    images,
  );

  /// The same for every standing prop's shadow.
  late final (Float32List, Float32List)? shadowBatch = sheets?.shadowBatch(
    plan.props,
    images,
    shadows,
  );

  // The two shore meshes, built on first paint and kept.
  late final ui.Vertices beachMesh = ui.Vertices.raw(
    ui.VertexMode.triangles,
    plan.beachPositions,
    colors: plan.beachColors,
  );
  late final ui.Vertices waterMesh = ui.Vertices.raw(
    ui.VertexMode.triangles,
    plan.waterPositions,
    colors: plan.waterColors,
  );

  static final List<_TerrainData> _cache = [];
  static final List<(Set<int>, Future<_TerrainData>)> _pending = [];
  static Future<List<ui.Image?>>? _imagesFuture;
  static Future<List<ui.Image?>>? _shadowsFuture;
  static Future<_TerrainSheets>? _sheetsFuture;

  static _TerrainData? cached(Set<int> region) {
    for (final d in _cache) {
      if (setEquals(d.region, region)) return d;
    }
    return null;
  }

  static Future<_TerrainData> load(Set<int> region) {
    final hit = cached(region);
    if (hit != null) return Future.value(hit);
    for (final (r, f) in _pending) {
      if (setEquals(r, region)) return f;
    }
    final snapshot = Set<int>.of(region);
    late final Future<_TerrainData> future;
    future = _build(snapshot).whenComplete(() {
      _pending.removeWhere((p) => identical(p.$2, future));
    });
    _pending.add((snapshot, future));
    return future;
  }

  static Future<_TerrainData> _build(Set<int> region) async {
    final images = await (_imagesFuture ??= _loadImages());
    final available = Uint8List(_kGrass);
    for (var k = 0; k < _kGrass; k++) {
      if (images[k] != null) available[k] = 1;
    }
    final plan = await compute(
      _planTerrain,
      _PlanRequest(region.toList(growable: false), available),
    );
    final shadows = await (_shadowsFuture ??= _loadShadows(images));
    _TerrainSheets? sheets;
    try {
      sheets = await (_sheetsFuture ??= _TerrainSheets.build(images, shadows));
    } catch (_) {
      _sheetsFuture = null;
    }
    final data = _TerrainData(
      region,
      images,
      plan,
      shadows: shadows,
      sheets: sheets,
    );
    _cache.insert(0, data);
    if (_cache.length > 3) _cache.removeLast();
    return data;
  }

  /// One shadow per standing kind, worked out once for the life of the app.
  static Future<List<ui.Image?>> _loadShadows(List<ui.Image?> images) =>
      Future.wait([
        for (var k = 0; k < images.length; k++)
          if (_castsShadow(k) && images[k] != null)
            castShadowImage(
              images[k]!,
              groundDepth: _shadowDepth(k),
            )
          else
            Future<ui.Image?>.value(null),
      ]);

  static Future<List<ui.Image?>> _loadImages() =>
      Future.wait([for (final asset in _kAssets) _loadImage(asset)]);

  static Future<ui.Image?> _loadImage(String asset) async {
    try {
      final data = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      // The ground tile is levelled so its repeat leaves no seam (see below).
      if (asset == _kAssets[_kGrass]) return await _levelled(frame.image);
      if (_kAssets.indexOf(asset) <= _kStoneF) return await _sunk(frame.image);
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// A stone picture with its bottom [_kStoneSink] cut off, so the foot (the
  /// picture's bottom edge) lands partway up the rock: it stands sunk in the
  /// ground. Falls back to the picture as it is.
  static Future<ui.Image> _sunk(ui.Image image) async {
    try {
      final w = image.width;
      final srcH = (image.height * (1 - _kStoneSink)).roundToDouble();
      // …and squashed flat: most rocks lie low, they are not round and tall.
      final h = math.max(1, (srcH * _kStoneFlat).round());
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(0, 0, w.toDouble(), srcH),
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(w, h);
      picture.dispose();
      return out;
    } catch (_) {
      return image;
    }
  }

  /// The grass tile with every ROW and COLUMN brought to the same average
  /// brightness (user 2026-09-28: "die Rasenstruktur ist nicht die genau
  /// gleiche"). The swatch repeats across the whole map, and its outermost rows
  /// are about two levels darker than its middle — invisible on one tile, but
  /// repeated every 512 px it is a faint dark line across the lawn, "besonders
  /// unten". Each line's gain is capped at ±4 %, so only a seam is removed and
  /// the grass's own texture is left alone. Falls back to the picture as it is.
  static Future<ui.Image> _levelled(ui.Image image) async {
    try {
      final w = image.width, h = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return image;
      final px = data.buffer.asUint8List();
      // Mean over R, G and B of one row / one column.
      double mean(bool row, int i) {
        var s = 0.0;
        final n = row ? w : h;
        for (var j = 0; j < n; j++) {
          final o = (row ? i * w + j : j * w + i) * 4;
          s += px[o] + px[o + 1] + px[o + 2];
        }
        return s / (n * 3);
      }

      final rows = [for (var y = 0; y < h; y++) mean(true, y)];
      final cols = [for (var x = 0; x < w; x++) mean(false, x)];
      final target = rows.fold(0.0, (a, b) => a + b) / h;
      double gain(double m) => (target / m).clamp(0.96, 1.04);
      final rg = [for (final m in rows) gain(m)];
      final cg = [for (final m in cols) gain(m)];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          final k = rg[y] * cg[x];
          for (var c = 0; c < 3; c++) {
            px[o + c] = (px[o + c] * k).round().clamp(0, 255);
          }
        }
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
      return await done.future;
    } catch (_) {
      return image;
    }
  }
}

/// The terrain's detail packed for BATCHED drawing (user 2026-11-03: "mache
/// alles, aber wirklich alles, damit die Performance besser läuft").
///
/// The forest alone is thousands of trees, and each one used to be its own
/// `drawImageRect` — plus a second one for its shadow, and a save/scale/
/// restore around every mirrored one. The map replays that picture on every
/// frame of a pan or a pinch (web has no raster cache at all, and a native
/// one misses whenever the zoom changes), so the GPU was handed ~20 000 draw
/// ops per frame for scenery that never moves. Now:
///
///  * [props] — every prop picture, upright AND mirrored, on one sheet, so the
///    whole forest is ONE `drawRawAtlas` call;
///  * [shadows] — every shadow mask, upright and mirrored, already tinted with
///    the building shadow's own colour and opacity, so all shadows are one
///    more call;
///  * [wash] — the grass's soft colour wash (thousands of large radial
///    gradients, see [_TerrainPainter.paintGrassWash]) rendered ONCE at an
///    eighth of the canvas's size. It is nothing but blurry blobs hundreds of
///    pixels across, so stretched back up with a smooth filter it is the same
///    picture, at the cost of a single image draw instead of ~2 000
///    full-overdraw gradient fills.
///
/// Built once for the life of the app; only the per-plan transforms
/// ([propBatch], [shadowBatch]) depend on the region.
class _TerrainSheets {
  final ui.Image props;
  final List<Rect?> propSlots;
  final ui.Image? shadows;
  final List<Rect?> shadowSlots;
  final ui.Image wash;

  _TerrainSheets._(
    this.props,
    this.propSlots,
    this.shadows,
    this.shadowSlots,
    this.wash,
  );

  /// The wash is baked at this fraction of the canvas's size.
  static const double washScale = 1 / 8;

  /// Transparent margin around each picture on a sheet. Wide on purpose: the
  /// map shows a tree at a twentieth of its picture's size when zoomed out,
  /// and the coarse mip levels the GPU samples there average across this many
  /// texels — a narrow gap would let a neighbour's edge bleed in.
  static const double _pad = 32;
  static const double _maxSheetWidth = 2048;

  static Future<_TerrainSheets> build(
    List<ui.Image?> images,
    List<ui.Image?> shadows,
  ) async {
    final props = await _sheet(images, kinds: _kGrass, paint: Paint());
    final shadowSheet = shadows.any((s) => s != null)
        ? await _sheet(
            shadows,
            kinds: math.min(_kGrass, shadows.length),
            paint: Paint()
              ..colorFilter = ColorFilter.mode(
                kShadowTint.withValues(alpha: kShadowOpacity),
                BlendMode.srcIn,
              ),
          )
        : null;
    final wash = await _bakeWash();
    return _TerrainSheets._(
      props.$1,
      props.$2,
      shadowSheet?.$1,
      shadowSheet?.$2 ?? const [],
      wash,
    );
  }

  /// Shelf-packs pictures `0..kinds-1` of [pictures], each upright then
  /// mirrored (slot `kind * 2 + flip`), onto one sheet.
  static Future<(ui.Image, List<Rect?>)> _sheet(
    List<ui.Image?> pictures, {
    required int kinds,
    required Paint paint,
  }) async {
    final slots = List<Rect?>.filled(kinds * 2, null);
    var x = _pad, y = _pad, rowH = 0.0, sheetW = 0.0;
    for (var k = 0; k < kinds; k++) {
      final p = k < pictures.length ? pictures[k] : null;
      if (p == null) continue;
      final w = p.width.toDouble(), h = p.height.toDouble();
      for (var flip = 0; flip < 2; flip++) {
        if (x + w + _pad > _maxSheetWidth && x > _pad) {
          x = _pad;
          y += rowH + _pad;
          rowH = 0;
        }
        slots[k * 2 + flip] = Rect.fromLTWH(x, y, w, h);
        x += w + _pad;
        sheetW = math.max(sheetW, x);
        rowH = math.max(rowH, h);
      }
    }
    final sheetH = y + rowH + _pad;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var k = 0; k < kinds; k++) {
      final p = k < pictures.length ? pictures[k] : null;
      if (p == null) continue;
      final up = slots[k * 2]!, mirrored = slots[k * 2 + 1]!;
      canvas.drawImage(p, up.topLeft, paint);
      canvas.save();
      canvas.translate(mirrored.right, mirrored.top);
      canvas.scale(-1, 1);
      canvas.drawImage(p, Offset.zero, paint);
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      math.max(1, sheetW.ceil()),
      math.max(1, sheetH.ceil()),
    );
    picture.dispose();
    return (image, slots);
  }

  static Future<ui.Image> _bakeWash() async {
    final size = isoCanvasSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(washScale);
    _TerrainPainter.paintGrassWash(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * washScale).ceil(),
      (size.height * washScale).ceil(),
    );
    picture.dispose();
    return image;
  }

  /// One [RSTransform] + source rect per drawable prop — exactly the rect
  /// the one-by-one painter used to draw it into (foot-anchored, mirrored
  /// about the foot, a rotated one turned about its own centre).
  (Float32List, Float32List) propBatch(
    Float64List props,
    List<ui.Image?> images,
  ) {
    final xf = <double>[];
    final src = <double>[];
    for (var o = 0; o < props.length; o += _propStride) {
      final kind = props[o].toInt();
      final image = kind < images.length ? images[kind] : null;
      final flip = props[o + 7] == 0 ? 0 : 1;
      final slot = kind * 2 + flip < propSlots.length
          ? propSlots[kind * 2 + flip]
          : null;
      if (image == null || slot == null) continue;
      final destW = image.width / _kPropPx * props[o + 3];
      final scale = destW / image.width;
      final destH = image.height * scale;
      final foot = gridToScreen(
        props[o + 1] + 0.5 + props[o + 4],
        props[o + 2] + 0.5 + props[o + 5],
      );
      final rotation = props[o + 6];
      final RSTransform t;
      if (rotation == 0) {
        t = RSTransform(scale, 0, foot.dx - destW / 2, foot.dy - destH);
      } else {
        t = RSTransform.fromComponents(
          rotation: rotation,
          scale: scale,
          anchorX: image.width / 2,
          anchorY: image.height / 2,
          translateX: foot.dx,
          translateY: foot.dy - destH / 2,
        );
      }
      xf.addAll([t.scos, t.ssin, t.tx, t.ty]);
      src.addAll([slot.left, slot.top, slot.right, slot.bottom]);
    }
    return (Float32List.fromList(xf), Float32List.fromList(src));
  }

  /// The shadows' counterpart of [propBatch] — same placement as the old
  /// `_paintShadows`: the mask shares the picture's top-left and scale, and a
  /// mirrored prop throws a mirrored shadow about the same foot.
  (Float32List, Float32List) shadowBatch(
    Float64List props,
    List<ui.Image?> images,
    List<ui.Image?> masks,
  ) {
    final xf = <double>[];
    final src = <double>[];
    for (var o = 0; o < props.length; o += _propStride) {
      final kind = props[o].toInt();
      if (kind >= masks.length || props[o + 6] != 0) continue;
      final mask = masks[kind];
      final image = images[kind];
      final flip = props[o + 7] == 0 ? 0 : 1;
      final slot = kind * 2 + flip < shadowSlots.length
          ? shadowSlots[kind * 2 + flip]
          : null;
      if (mask == null || image == null || slot == null) continue;
      final destW = image.width / _kPropPx * props[o + 3];
      final unit = destW / image.width;
      final foot = gridToScreen(
        props[o + 1] + 0.5 + props[o + 4],
        props[o + 2] + 0.5 + props[o + 5],
      );
      var left = foot.dx - destW / 2;
      if (flip == 1) left = 2 * foot.dx - left - mask.width * unit;
      final top = foot.dy - image.height * unit;
      xf.addAll([unit, 0, left, top]);
      src.addAll([slot.left, slot.top, slot.right, slot.bottom]);
    }
    return (Float32List.fromList(xf), Float32List.fromList(src));
  }
}

class _PlanRequest {
  final List<int> region;
  final Uint8List available;
  const _PlanRequest(this.region, this.available);
}

/// The terrain, worked out: what is painted where, as flat typed arrays that
/// cross the isolate boundary cheaply and go straight to the canvas.
class _TerrainPlan {
  /// Beach and water cells as triangle meshes — two triangles per cell, six
  /// vertices, one ARGB colour per vertex.
  final Float32List beachPositions;
  final Int32List beachColors;
  final Float32List waterPositions;
  final Int32List waterColors;

  /// Depth-sorted props, [_propStride] doubles each: kind, gx, gy,
  /// widthInTiles, offX, offY, rotation, flip.
  final Float64List props;

  /// The animals, [_faunaStride] doubles each (see [_TerrainPlanner._scatterFauna]).
  final Float64List fauna;

  const _TerrainPlan({
    required this.beachPositions,
    required this.beachColors,
    required this.waterPositions,
    required this.waterColors,
    required this.props,
    required this.fauna,
  });
}

const int _propStride = 8;
const int _faunaStride = 16;

/// FNV-1a, exactly like tool/blender/terrain.py's own `_hash01` — not because
/// the two ever need to agree on any SPECIFIC position (Dart picks its own
/// scatter, independently of whatever terrain.py last rolled), just because
/// it is a known-good, dependency-free way to turn a seed string into a
/// repeatable 0..1 float. Top-level (not a [_TerrainPlanner] method) so the
/// PAINTER can reuse it too — dirt's per-patch shade and its grass tufts are
/// derived straight from the prop's own (gx, gy) rather than threaded through
/// the plan as extra numbers (user 2026-09-29: "der Dreck hat unterschiedliche
/// Farbtöne").
double _hash01(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = (h ^ c) & 0xFFFFFFFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h / 0xFFFFFFFF;
}

_TerrainPlan _planTerrain(_PlanRequest request) =>
    _TerrainPlanner(Set<int>.of(request.region), request.available).plan();

/// Test hook: the plan for [region] with every prop kind available, computed
/// synchronously.
@visibleForTesting
Object planTerrainForTest(Set<int> region) =>
    _TerrainPlanner(region, Uint8List(_kGrass)..fillRange(0, _kGrass, 1)).plan();

@visibleForTesting
Float64List propsOfPlanForTest(Object plan) => (plan as _TerrainPlan).props;

/// Test hook: the animals of a plan, [faunaStrideForTest] doubles each —
/// species, speed, pause, phase, stop count, five (x, y) stops, salt.
@visibleForTesting
Float64List faunaOfPlanForTest(Object plan) => (plan as _TerrainPlan).fauna;

@visibleForTesting
const int faunaStrideForTest = _faunaStride;

/// Test hook: the first and last landmark kind.
@visibleForTesting
const (int, int) landmarkKindsForTest = (_kRuinWall, _kFlotsam);

/// One placed prop, ready to be depth-sorted against every other prop
/// regardless of which kind it is — a tree standing next to a stone must
/// still draw in the right order relative to it, not just within its own
/// type's pass.
class _PropPlacement {
  /// Which picture — one of the `_k…` ids above.
  final int kind;
  final int gx;
  final int gy;
  final double widthInTiles;

  /// Sub-tile drift from the cell's centre, in tile units (0 = dead centre).
  /// [_clusterScatter] derives this from the instance's own continuous
  /// scatter position (its angle+radius almost never lands on a whole grid
  /// cell) and [_beachDebris] draws it fresh per cell — both so nothing snaps
  /// onto a visible grid (user 2026-09-14: "nicht so mechanisch wie jetzt";
  /// 2026-09-29, the same complaint about stones: "viel zu uniform und
  /// gleichmässig verteilt"). Defaults to 0 for the few callers that place
  /// exactly one thing per centre and want it there.
  final double offX;
  final double offY;

  /// Scenery is never turned: the pictures are isometric renders, and a
  /// turned one would no longer sit on the grid. (Kept in the plan so the
  /// painters need no second code path.)
  double get rotation => 0;

  /// Mirrored left-right about its own foot — free shape variety from a
  /// single sprite (user 2026-09-29: trees "in unterschiedlichen Grössen und
  /// Formen", and there are only two tree pictures to draw from).
  final bool flip;

  const _PropPlacement(
    this.kind,
    this.gx,
    this.gy,
    this.widthInTiles, {
    this.offX = 0,
    this.offY = 0,
    this.flip = false,
  });
}

/// Decides the whole terrain — shore, sand, forest, flowers, stones — as pure
/// maths on cell coordinates. No canvas, no images: it runs in a background
/// isolate (see [_planTerrain]), and the result is deterministic, so two runs
/// over the same region are identical.
class _TerrainPlanner {
  final Set<int> buildableRegion;

  /// Entry k is 1 when prop kind k's picture loaded.
  final Uint8List available;

  _TerrainPlanner(this.buildableRegion, this.available);

  bool _has(int kind) => available[kind] == 1;

  /// The kinds [from]..[to] whose pictures are there.
  List<int> _kinds(int from, int to) => [
    for (var k = from; k <= to; k++)
      if (_has(k)) k,
  ];

  _TerrainPlan plan() {
    final bands = _shoreBands();
    // The sand also lies UNDER the shallow water: the water's edge is now a
    // smooth curve (see [_shoreMesh] `smoothRings`) that can pull back into
    // the outermost water cells, and the bank must show there, not grass.
    final underWater = {
      for (final e in bands.waterRing.entries)
        if (e.value <= _kWaterRingCap) e.key,
    };
    final beach = _shoreMesh({...bands.beach, ...underWater}, (k, gx, gy) {
      final ring = bands.water.contains(k)
          ? 0
          : (bands.beachRing[k] ?? _kBeachRingCap);
      final alpha = 1.0 - ring / (_kBeachRingCap + 1);
      // A TINT for the voxel sand tile (modulated, see paintBeach): a little
      // lighter or darker per cell, and damp-dark at the waterline.
      // Smooth noise, not a per-cell roll: a roll shows the tile grid.
      final v = 0.92 + 0.08 * _noise(gx / 7, gy / 7, 81);
      final damp = ring == 0 ? 0.86 : 1.0;
      return Color.from(
        alpha: alpha,
        red: v * damp,
        green: v * damp * 0.98,
        blue: v * damp * 0.95,
      );
    }, outside: (k, gx, gy) {
      // Water leaves the sand's colour alone; grass is where it fades out.
      if (bands.water.contains(k)) return null;
      final v = 0.92 + 0.08 * _noise(gx / 7, gy / 7, 81);
      return Color.from(alpha: 0, red: v, green: v * 0.98, blue: v * 0.95);
    });
    Color waterTint(int ring, int gx, int gy) {
      // The depth colour as a TINT for the voxel water tile, which is
      // rendered in the shallow colour: shallow water is the tile as it is,
      // deep water the tile darkened and pushed towards blue.
      final c = _jitter(_waterColorForRing(ring), _noise(gx / 7, gy / 7, 82));
      return Color.from(
        alpha: 1,
        red: (c.r / _waterShallow.r).clamp(0.0, 1.0),
        green: (c.g / _waterShallow.g).clamp(0.0, 1.0),
        blue: (c.b / _waterShallow.b).clamp(0.0, 1.0),
      );
    }
    final water = _shoreMesh(
      bands.water,
      (k, gx, gy) => waterTint(bands.waterRing[k] ?? _kWaterRingCap, gx, gy),
      // The smoothed edge bulges into land cells too: they take the shore tint.
      outside: (k, gx, gy) => waterTint(1, gx, gy),
      smoothRings: bands.waterRing,
    );
    final placements = _scatterProps();
    final props = Float64List(placements.length * _propStride);
    for (var i = 0; i < placements.length; i++) {
      final p = placements[i];
      final o = i * _propStride;
      props[o] = p.kind.toDouble();
      props[o + 1] = p.gx.toDouble();
      props[o + 2] = p.gy.toDouble();
      // Stones are drawn smaller than their pictures (user 2026-11-05: "die
      // Steine sind zu gross"); their lower part is cropped away on load.
      props[o + 3] = p.widthInTiles * (p.kind <= _kStoneF ? _kStoneScale : 1.0);
      props[o + 4] = p.offX;
      props[o + 5] = p.offY;
      props[o + 6] = p.rotation;
      props[o + 7] = p.flip ? 1.0 : 0.0;
    }
    return _TerrainPlan(
      beachPositions: beach.$1,
      beachColors: beach.$2,
      waterPositions: water.$1,
      waterColors: water.$2,
      props: props,
      fauna: _scatterFauna(),
    );
  }

  /// One diamond per cell, as two triangles (north-east-south, north-south-west)
  /// with a per-vertex colour. See [_TerrainPainter.paintShore] for why a mesh
  /// and not a path per cell.
  (Float32List, Int32List) _shoreMesh(
    Set<int> cells,
    Color Function(int key, int gx, int gy) colorOf, {
    Color? Function(int key, int gx, int gy)? outside,
    Map<int, int>? smoothRings,
  }) {
    final positions = <double>[];
    final colors = <int>[];
    // Colour per GRID CORNER, averaged over the cells meeting there, so the
    // colour blends smoothly across the cells instead of stepping at every
    // cell edge (user 2026-11-05: the diamonds were still visible).
    final corner = <int, Color>{};
    Color cornerAt(int vx, int vy) => corner.putIfAbsent(_cellKey(vx, vy), () {
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      var n = 0;
      for (final (dx, dy) in const [(-1, -1), (0, -1), (-1, 0), (0, 0)]) {
        final cx = vx + dx, cy = vy + dy;
        final ck = _cellKey(cx, cy);
        final c = cells.contains(ck)
            ? colorOf(ck, cx, cy)
            : outside?.call(ck, cx, cy);
        if (c == null) continue;
        r += c.r;
        g += c.g;
        b += c.b;
        a += c.a;
        n++;
      }
      if (n == 0) return const Color(0x00000000);
      return Color.from(alpha: a / n, red: r / n, green: g / n, blue: b / n);
    });
    // ── Smooth coastline (user 2026-11-05: the river/sea edge was still too
    // square). The water's cell mask is blurred, read bilinearly between cell
    // centres, and the mesh is cut along its 0.5 contour on a fine lattice —
    // the staircase of diamonds becomes a flowing curve. Only the outer water
    // cells (ring <= 2) are subdivided; deeper ones stay two triangles.
    const sub = 6;
    const blurR = 7;
    final blurW = () {
      final w = [
        for (var d = -blurR; d <= blurR; d++) math.exp(-d * d / (2 * 3.0 * 3.0)),
      ];
      final total = w.reduce((a, b) => a + b);
      return [for (final x in w) x / total];
    }();
    final blurMemo = <int, double>{};
    double raw(int x, int y, double def) =>
        !_inPicture(x, y) ? def : (cells.contains(_cellKey(x, y)) ? 1.0 : 0.0);
    double blurred(int cx, int cy) =>
        blurMemo.putIfAbsent(_cellKey(cx, cy), () {
          final def = cells.contains(_cellKey(cx, cy)) ? 1.0 : 0.0;
          // Gaussian, sigma 3 cells: the source coastline steps several cells
          // at a time, and only a wide blur turns those steps into a curve.
          var sum = 0.0;
          for (var dy = -blurR; dy <= blurR; dy++) {
            for (var dx = -blurR; dx <= blurR; dx++) {
              sum += blurW[dx + blurR] * blurW[dy + blurR] *
                  raw(cx + dx, cy + dy, def);
            }
          }
          return sum;
        });
    double field(double u, double v) {
      final fx = u - 0.5, fy = v - 0.5;
      final cx = fx.floor(), cy = fy.floor();
      final tx = fx - cx, ty = fy - cy;
      final a = blurred(cx, cy) * (1 - tx) + blurred(cx + 1, cy) * tx;
      final b = blurred(cx, cy + 1) * (1 - tx) + blurred(cx + 1, cy + 1) * tx;
      return a * (1 - ty) + b * ty;
    }

    void addVertex(double u, double v, int argb) {
      final p = gridToScreen(u, v);
      positions
        ..add(p.dx)
        ..add(p.dy);
      colors.add(argb);
    }

    int colorAtPoint(double u, double v) =>
        cornerAt(u.round(), v.round()).toARGB32();

    // One triangle of the fine lattice, clipped to field >= 0.5.
    void clipTri(List<(double, double)> p) {
      final f = [for (final q in p) field(q.$1, q.$2) - 0.5];
      final inside = [for (final x in f) x >= 0];
      final count = inside.where((b) => b).length;
      if (count == 0) return;
      (double, double) cut((double, double) a, double fa, (double, double) b,
          double fb) {
        final t = fa / (fa - fb);
        return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
      }

      final poly = <(double, double)>[];
      for (var j = 0; j < 3; j++) {
        final k2 = (j + 1) % 3;
        if (inside[j]) poly.add(p[j]);
        if (inside[j] != inside[k2]) poly.add(cut(p[j], f[j], p[k2], f[k2]));
      }
      for (var j = 1; j + 1 < poly.length; j++) {
        for (final q in [poly[0], poly[j], poly[j + 1]]) {
          addVertex(q.$1, q.$2, colorAtPoint(q.$1, q.$2));
        }
      }
    }

    // The smoothed edge can bulge up to a few cells into the land, so the
    // water cells alone are not enough to cover it.
    var loopCells = cells;
    if (smoothRings != null) {
      loopCells = {...cells};
      for (var pass = 0; pass < 3; pass++) {
        for (final k in loopCells.toList()) {
          final (cx, cy) = _cellFromKey(k);
          for (final (dx, dy) in _kNeighbors8) {
            if (_inPicture(cx + dx, cy + dy)) {
              loopCells.add(_cellKey(cx + dx, cy + dy));
            }
          }
        }
      }
    }
    for (final k in loopCells) {
      final (gx, gy) = _cellFromKey(k);
      var lo = 1.0, hi = 0.0;
      if (smoothRings != null) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final b = blurred(gx + dx, gy + dy);
            if (b < lo) lo = b;
            if (b > hi) hi = b;
          }
        }
        // Wholly outside the smoothed shore: the bank shows instead.
        if (hi < 0.5) continue;
      }
      if (smoothRings != null && lo < 0.5) {
        for (var j = 0; j < sub; j++) {
          for (var i2 = 0; i2 < sub; i2++) {
            final x0 = gx + i2 / sub, x1 = gx + (i2 + 1) / sub;
            final y0 = gy + j / sub, y1 = gy + (j + 1) / sub;
            clipTri([(x0, y0), (x1, y0), (x1, y1)]);
            clipTri([(x0, y0), (x1, y1), (x0, y1)]);
          }
        }
        continue;
      }
      final x0 = gx.toDouble(), y0 = gy.toDouble();
      final cn = cornerAt(gx, gy).toARGB32();
      final ce = cornerAt(gx + 1, gy).toARGB32();
      final cs = cornerAt(gx + 1, gy + 1).toARGB32();
      final cw = cornerAt(gx, gy + 1).toARGB32();
      addVertex(x0, y0, cn);
      addVertex(x0 + 1, y0, ce);
      addVertex(x0 + 1, y0 + 1, cs);
      addVertex(x0, y0, cn);
      addVertex(x0 + 1, y0 + 1, cs);
      addVertex(x0, y0 + 1, cw);
    }
    return (Float32List.fromList(positions), Int32List.fromList(colors));
  }

  // ── The water palette (user 2026-09-08: "das Wasser deutlich spannender
  // gestalten und es soll wieder ein Ufer geben") ── one flat colour read as
  // a painted pool with no bed and no edge. Banded light-to-dark from the
  // shore inward gives it a shape again, and a sandy ring on the LAND side
  // is the bank itself — both computed from [kWaterRuns], the same source
  // buildability reads, so neither can drift from the coastline you can
  // see.
  static const Color _waterDeep = Color(0xFF2A6188);
  static const Color _waterMid = Color(0xFF3E85B0);
  static const Color _waterShallow = Color(0xFF6FBBC4);

  // ── Beyond the real, buildable grid ──────────────────────────
  // The canvas is the grid's own diamond shape's BOUNDING BOX
  // ([isoCanvasSize] = (COLS+ROWS) tiles square), and a diamond does not
  // fill its own bounding box — a third of the canvas sits in the box's
  // four corners, outside the real map. Until now that padding painted as
  // bare grass: no water, no trees, a dead seam wherever the coastline or
  // the tree line met it (user 2026-09-08, pointing at exactly that seam:
  // "der ganze obere linke Bereich soll durch das Meer/See abgedeckt
  // werden... Unten Rechts soll der Fluss bis zum Bildschirmrand gehen...
  // Alle freien Flächen sollen auch durch den Wald besetzt werden"). This
  // range is the same padding tool/blender/terrain.py's own
  // EXT_X0/EXT_X1/EXT_Y0/EXT_Y1 used for its now-retired baked background,
  // sized the same way: about half the far dimension beyond each rim, which
  // is as far as a diamond's corner ever reaches past its own bounding box.
  static const int _extX0 = -80, _extX1 = kGridCols + 60;
  static const int _extY0 = -110, _extY1 = kGridRows + 110;
  static const int _extW = _extX1 - _extX0;

  /// Only cells actually inside the canvas's DIAMOND, not just its
  /// rectangular bounding box, are worth classifying — mirrors terrain.py's
  /// own `in_picture`.
  static bool _inPicture(int gx, int gy) {
    final u = gx - gy, v = gx + gy;
    return u >= -kGridRows &&
        u <= kGridCols &&
        v >= 0 &&
        v <= kGridCols + kGridRows;
  }

  static bool _isRealCell(int gx, int gy) =>
      gx >= 0 && gx < kGridCols && gy >= 0 && gy < kGridRows;

  /// Every cell key below is offset into the padded range first, so it stays
  /// non-negative even for a padding cell west or north of the real grid —
  /// `gy * kGridCols + gx` (the scheme used before padding existed) breaks
  /// the moment gx or gy goes negative.
  static int _cellKey(int gx, int gy) => (gy - _extY0) * _extW + (gx - _extX0);
  static (int, int) _cellFromKey(int k) =>
      (k % _extW + _extX0, k ~/ _extW + _extY0);

  // ── The coastline and river, continued past the real grid ──────
  // Exactly tool/blender/terrain.py's own `coast_at`/`river_spine`, ported
  // rather than shared — that file needs `bpy` to even import, and this one
  // must not. Only ever consulted OUTSIDE the real grid (see [_isWater]):
  // inside it, [kWaterRuns] stays the one authority, so gameplay
  // buildability can never disagree with what gets painted.
  /// [gy] is clamped to just past the real grid's own rows before it ever
  /// reaches the sine: this is meant as a SHORT continuation of the coast
  /// right at the real grid's north/south edge, not a function to be
  /// evaluated anywhere. The canvas's own corners (see [_inPicture]) push
  /// [gy] out to roughly ±100 at the diamond's top and bottom tips — far
  /// outside that intended range — and being periodic, the raw sine there
  /// cycles back through "land" every ~74 cells, which painted as a row of
  /// stray grass teeth poking up through open sea (user 2026-10-01: "ich
  /// sehe oben bei der Map den Übergang von Wasser und grün, dies sollte so
  /// nicht sein"). Clamping holds the coastline at its edge-of-grid value
  /// for every cell beyond that, so the sea reads as one continuous sheet
  /// all the way to the canvas corner instead of repeating itself.
  static double _coastAt(double gy) {
    final clamped = gy.clamp(-20.0, kGridRows + 20.0);
    return 12.0 +
        5.0 * math.sin(clamped * 0.085) +
        2.6 * math.sin(clamped * 0.031 + 1.1);
  }

  static const int _riverSpineN = 760;
  static (double, double, double) _riverSpineAt(double t) {
    final x = 6.0 + (kGridCols - 6.0) * t;
    final y = 58.0 + 26.0 * math.sin(t * math.pi * 1.9 + 0.35) + 10.0 * t;
    final w = 4.2 + 1.0 * math.sin(t * 7.0 + 0.6);
    return (x, y, w);
  }

  static final List<(double, double, double)> _riverSpine = [
    for (var i = 0; i <= _riverSpineN; i++)
      _riverSpineAt(-0.55 + 1.95 * i / _riverSpineN),
  ];
  static final double _riverSpineX0 = _riverSpine.first.$1;
  static final double _riverSpineDX =
      (_riverSpine.last.$1 - _riverSpineX0) / _riverSpineN;

  /// > 0 means inside the river, and the bigger it is the further from
  /// either bank — same windowed search as terrain.py's own `_river_depth`,
  /// so the padding cells this is ever called for cost a few dozen hypots
  /// each, not 760.
  static double _riverDepth(double gx, double gy) {
    final mid = ((gx - _riverSpineX0) / _riverSpineDX).round();
    final lo = math.max(0, mid - 30);
    final hi = math.min(_riverSpine.length, mid + 31);
    var best = -99.0;
    for (var i = lo; i < hi; i++) {
      final (sx, sy, sw) = _riverSpine[i];
      final d = sw - math.sqrt((gx - sx) * (gx - sx) + (gy - sy) * (gy - sy));
      if (d > best) best = d;
    }
    return best;
  }

  /// True for a padding cell that continues the sea or the river past the
  /// real grid's edge — never consulted for a real cell (see [_isWater]).
  static bool _isExtWater(int gx, int gy) {
    final cx = gx + 0.5, cy = gy + 0.5;
    return cx < _coastAt(cy) || _riverDepth(cx, cy) > 0;
  }

  static const List<(int, int)> _kNeighbors4 = [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
  ];
  static const List<(int, int)> _kNeighbors8 = [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (-1, -1),
    (1, -1),
    (-1, 1),
  ];

  bool _isWater(int gx, int gy) {
    if (_isRealCell(gx, gy)) {
      final runs = kWaterRuns[gy];
      for (var i = 0; i < runs.length; i += 2) {
        if (gx >= runs[i] && gx < runs[i + 1]) return true;
      }
      return false;
    }
    // Off the real grid: nothing in [kWaterRuns] to read, so the sea/river
    // continue by the same maths terrain.py drew them with in the first
    // place — see [_isExtWater].
    return _isExtWater(gx, gy);
  }

  static const int _kWaterRingCap = 4;
  static const int _kBeachRingCap = 2;

  /// Memoised: [_paintWater] reads all four fields and [_isLegal] also
  /// needs [beach] (scenery keeps off the sand — see its own doc comment),
  /// and this painter is fresh per frame, so computing it once and sharing
  /// it beats rebuilding the same rings twice. Scans the WHOLE padded
  /// picture, not just [kWaterRuns]'s real rows, so the sea/river/beach the
  /// player can see keep going right to the edge of the canvas instead of
  /// stopping dead at the real grid's own border.
  ///
  /// [waterRing]/[beachRing] are BFS distance rings (1.._kWaterRingCap for
  /// water — 1 touches land — and 0.._kBeachRingCap for the beach, 0
  /// touching water), used to blend colour smoothly instead of stepping
  /// between a few flat bands (user 2026-09-08: "die Übergangslinien im
  /// Wasser und Sand löschen, so dass ich nicht exakt sehe, wo die
  /// Häuschen sind"). A cell absent from the map is either open water
  /// beyond the cap (full deep) or, for beach, can't happen — every beach
  /// cell gets a ring by construction.
  ({
    Set<int> water,
    Set<int> beach,
    Map<int, int> waterRing,
    Map<int, int> beachRing,
  })?
  _shoreCache;

  ({
    Set<int> water,
    Set<int> beach,
    Map<int, int> waterRing,
    Map<int, int> beachRing,
  })
  _shoreBands() {
    final cached = _shoreCache;
    if (cached != null) return cached;

    final water = <int>{};
    for (var gy = _extY0; gy < _extY1; gy++) {
      for (var gx = _extX0; gx < _extX1; gx++) {
        if (!_inPicture(gx, gy)) continue;
        if (_isWater(gx, gy)) water.add(_cellKey(gx, gy));
      }
    }

    // Ring 1 (water, touches land) / ring 0 (beach, touches water).
    final waterRing = <int, int>{};
    final beachRing = <int, int>{};
    final beach = <int>{};
    var waterFrontier = <int>[];
    for (final k in water) {
      final (gx, gy) = _cellFromKey(k);
      for (final (dx, dy) in _kNeighbors4) {
        final nx = gx + dx, ny = gy + dy;
        if (!_inPicture(nx, ny)) continue;
        final nk = _cellKey(nx, ny);
        if (water.contains(nk)) continue;
        if (waterRing.putIfAbsent(k, () => 1) == 1) waterFrontier.add(k);
        if (beachRing.putIfAbsent(nk, () => 0) == 0) beach.add(nk);
      }
    }
    // Ring 2.._kWaterRingCap: BFS deeper into the water, one level at a
    // time, so it fades rather than stepping straight to the open-water
    // colour.
    var frontier = waterFrontier;
    for (var ring = 2; ring <= _kWaterRingCap && frontier.isNotEmpty; ring++) {
      final next = <int>[];
      for (final k in frontier) {
        final (gx, gy) = _cellFromKey(k);
        for (final (dx, dy) in _kNeighbors8) {
          final nx = gx + dx, ny = gy + dy;
          if (!_inPicture(nx, ny)) continue;
          final nk = _cellKey(nx, ny);
          if (water.contains(nk) && !waterRing.containsKey(nk)) {
            waterRing[nk] = ring;
            next.add(nk);
          }
        }
      }
      frontier = next;
    }
    // Ring 1.._kBeachRingCap: BFS further inland from the immediate bank,
    // so the sand dissolves into the grass instead of stopping on a line.
    var bfrontier = beach.toList();
    for (var ring = 1; ring <= _kBeachRingCap && bfrontier.isNotEmpty; ring++) {
      final next = <int>[];
      for (final k in bfrontier) {
        final (gx, gy) = _cellFromKey(k);
        for (final (dx, dy) in _kNeighbors8) {
          final nx = gx + dx, ny = gy + dy;
          if (!_inPicture(nx, ny)) continue;
          final nk = _cellKey(nx, ny);
          if (!water.contains(nk) && !beachRing.containsKey(nk)) {
            beachRing[nk] = ring;
            beach.add(nk);
            next.add(nk);
          }
        }
      }
      bfrontier = next;
    }
    return _shoreCache = (
      water: water,
      beach: beach,
      waterRing: waterRing,
      beachRing: beachRing,
    );
  }

  /// Ring 1 (shore) fades smoothly through the mid tone to ring
  /// [_kWaterRingCap] (open water) — a continuous blend rather than the
  /// three flat bands this used to be, so there is no hard edge to see.
  static Color _waterColorForRing(int ring) {
    final t = ((ring - 1) / (_kWaterRingCap - 1)).clamp(0.0, 1.0);
    return t < 0.5
        ? Color.lerp(_waterShallow, _waterMid, t / 0.5)!
        : Color.lerp(_waterMid, _waterDeep, (t - 0.5) / 0.5)!;
  }

  /// A small per-cell brightness nudge — the same job `vary_tones()` does
  /// for the (now-retired) baked background — so two neighbouring cells on
  /// the same ring are never bit-for-bit the same colour either. Without
  /// it the smooth ring blend above still reads as concentric bands from
  /// far enough away; the noise is what actually breaks the grid up.
  static Color _jitter(Color base, double seed) {
    final j = (seed - 0.5) * 2; // -1..1
    return Color.lerp(
      base,
      j > 0 ? Colors.white : Colors.black,
      j.abs() * 0.07,
    )!;
  }

  /// True for a cell the player could plant scenery on: inside the picture,
  /// dry, not the sand, and not the player's own claimed land.
  ///
  /// The forest covers every OTHER grass cell (user 2026-09-08: "die ganze
  /// Rasenfläche sollte mit dem Wald bedeckt sein"), including the canvas's
  /// off-map padding (see [_inPicture]) — a genuinely wild cell has no
  /// reason to hold back. [buildableRegion] is the one deliberate
  /// exception: a building placed there would collide with whatever prop
  /// was already standing on the tile, so the player's OWN territory stays
  /// bare ground (user 2026-09-08: "für alle Gebiete, welche von mir
  /// bereits freigeschalten wurden: keine Bäume, Steine oder Blumen haben
  /// ... damit es keine Kollisionen mit den Gebäuden gibt"). That set only
  /// ever holds real cells, so the plain `y * kGridCols + x` key it was
  /// built with is safe to look up directly, unlike the offset key
  /// [_cellKey] uses for the padded shore sets.
  bool _isLegal(int gx, int gy) {
    if (!_inPicture(gx, gy)) return false;
    if (_isWater(gx, gy)) return false;
    if (_isRealCell(gx, gy) && buildableRegion.contains(gy * kGridCols + gx)) {
      return false;
    }
    return !_shoreBands().beach.contains(_cellKey(gx, gy));
  }

  /// [buildableRegion] dilated by four rings, real cells only. Flowers and
  /// stones hug the ground and never poke past their own tile, so
  /// [_isLegal] alone is enough for them — but a tree sprite rises several
  /// tile-heights above its foot, tall enough to visually reach into a
  /// building a couple of cells away even though its own tile is outside
  /// [buildableRegion]. TerrainLayer paints as one flat layer BEHIND every
  /// building widget regardless of iso depth (buildings are interactive
  /// widgets, not canvas draws, so they can't be depth-interleaved with the
  /// terrain the cheap way), so a tree that is genuinely in FRONT of a
  /// building on the grid still loses to it and looks wrong (user
  /// 2026-09-08, pointing at exactly that: "Diese Bäume müssten wohl vor
  /// den Gebäuden sein"). This buffer keeps trees far enough back that
  /// their canopies don't reach the building in the first place — it
  /// narrows the problem, it doesn't fix the underlying layering.
  ///
  /// Widened from two rings to four (user 2026-09-29, spotting a tree
  /// clipped against the hatchery: "clipping Fehler von Baum und Hatchery")
  /// when trees themselves grew to up to 2.4 tiles wide — two rings was
  /// tuned for the old fixed 1.1-tile tree and a canopy roughly twice that
  /// size needs roughly twice the setback.
  Set<int>? _treeClearanceCache;
  Set<int> get _treeClearance {
    final cached = _treeClearanceCache;
    if (cached != null) return cached;
    final all = Set<int>.from(buildableRegion);
    var frontier = buildableRegion;
    for (var ring = 0; ring < 4; ring++) {
      final next = <int>{};
      for (final k in frontier) {
        final gx = k % kGridCols, gy = k ~/ kGridCols;
        for (final (dx, dy) in _kNeighbors8) {
          final nx = gx + dx, ny = gy + dy;
          if (nx < 0 || nx >= kGridCols || ny < 0 || ny >= kGridRows) continue;
          final nk = ny * kGridCols + nx;
          if (all.add(nk)) next.add(nk);
        }
      }
      frontier = next;
    }
    return _treeClearanceCache = all;
  }

  bool _isTreeLegal(int gx, int gy) {
    if (!_isLegal(gx, gy)) return false;
    return !(_isRealCell(gx, gy) &&
        _treeClearance.contains(gy * kGridCols + gx));
  }


  // ── Scenery that grows where it would grow ─────────────────────
  // (user 2026-11-05: "Die Verteilung der Gegenstände soll realistisch sein")
  //
  // Nothing here is scattered uniformly. A handful of smooth NOISE FIELDS says
  // what the land is like — how wooded, how wet, how rocky, how conifer-ish —
  // and every kind of prop reads them:
  //
  //  * forest: where the wood is dense the trees stand close and tall; where
  //    it thins they are young and small; where it breaks, there is a meadow;
  //  * undergrowth (ferns, grass, the odd stump or fallen log) lives under
  //    the trees; bushes stand along the forest edge and round the player's
  //    own land, like hedges;
  //  * meadow flowers drift in patches over the open ground, one colour
  //    family to a drift;
  //  * stones lie in outcrops, a big rock with smaller ones around it, mostly
  //    near water;
  //  * the shore has driftwood, shells, pebbles and reed beds.

  /// A cheap deterministic 0..1 hash of a point — sin-based, so the planner
  /// (which also runs on the web, where `compute` is not a real isolate and
  /// string hashing thousands of times would stall the loading screen) stays
  /// fast.
  static double _h(double x, double y, int salt) {
    final v = math.sin(x * 127.1 + y * 311.7 + salt * 74.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  /// Smooth value noise, 0..1, one lattice cell per unit.
  static double _noise(double x, double y, int salt) {
    final x0 = x.floorToDouble(), y0 = y.floorToDouble();
    final fx = x - x0, fy = y - y0;
    final u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
    final a = _h(x0, y0, salt), b = _h(x0 + 1, y0, salt);
    final c = _h(x0, y0 + 1, salt), d = _h(x0 + 1, y0 + 1, salt);
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
  }

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// How wooded the land is, ~0..1: broad stands, a mid-scale texture and a
  /// fine one, so the wood has clearings and a ragged edge.
  static double _forestAt(double x, double y) =>
      0.55 * _noise(x / 15, y / 15, 1) +
      0.30 * _noise(x / 6, y / 6, 2) +
      0.15 * _noise(x / 2.6, y / 2.6, 3);

  /// 0..1: water within a few cells, for the species that like wet feet and
  /// the rocks that wash up on a bank.
  double _wetness(int gx, int gy) {
    var n = 0;
    for (final (dx, dy) in _kNeighbors8) {
      if (_isWater(gx + dx * 4, gy + dy * 4)) n++;
      if (_isWater(gx + dx * 8, gy + dy * 8)) n++;
    }
    return n / 16.0;
  }

  /// Calls [visit] for one jittered point per [spacing] x [spacing] square of
  /// the whole padded canvas — a blue-noise-ish grid, so a scatter has no
  /// visible rows yet never piles up either.
  void _grid(
    double spacing,
    int salt,
    void Function(double fx, double fy) visit,
  ) {
    for (var fy = _extY0.toDouble(); fy < _extY1; fy += spacing) {
      for (var fx = _extX0.toDouble(); fx < _extX1; fx += spacing) {
        final jx = (_h(fx, fy, salt) - 0.5) * spacing * 0.9;
        final jy = (_h(fx, fy, salt + 1) - 0.5) * spacing * 0.9;
        visit(fx + jx, fy + jy);
      }
    }
  }

  /// Every prop, depth-sorted back to front.
  List<_PropPlacement> _scatterProps() {
    final out = <_PropPlacement>[];
    void add(int kind, double fx, double fy, {bool flip = false}) {
      final gx = fx.round(), gy = fy.round();
      out.add(
        _PropPlacement(
          kind,
          gx,
          gy,
          1.0,
          offX: fx - gx,
          offY: fy - gy,
          flip: flip,
        ),
      );
    }

    bool flipOf(double fx, double fy, int s) => _h(fx, fy, s) < 0.5;

    final conifers = _kinds(_kConiferS, _kConiferL);
    final broadleafs = _kinds(_kBroadleafS, _kBroadleafL);
    final bushes = _kinds(_kBushA, _kBushD);
    final flowers = _kinds(_kFlowersA, _kFlowersD);
    final stones = _kinds(_kStoneA, _kStoneE);

    // ── The wood, and what lives under it ───────────────────────
    if (conifers.isNotEmpty && broadleafs.isNotEmpty) {
      _grid(2.1, 21, (fx, fy) {
        final gx = fx.round(), gy = fy.round();
        if (!_isTreeLegal(gx, gy)) return;
        final f = _forestAt(fx, fy);
        if (_h(fx, fy, 31) > _smooth(0.43, 0.62, f) * 0.9) return;
        final wet = _wetness(gx, gy);
        // conifer country on one side of the map, mixed wood on the other,
        // and the wet ground is broadleaf
        final lean =
            0.3 + 0.6 * _smooth(0.35, 0.65, _noise(fx / 20, fy / 20, 4));
        final conifer = _h(fx, fy, 32) < lean * (1 - 0.6 * wet);
        final list = conifer ? conifers : broadleafs;
        // dense, old wood grows tall; the edge is young
        final age = 0.4 * _h(fx, fy, 33) + 0.6 * _smooth(0.45, 0.8, f);
        final idx = (age * list.length).floor().clamp(0, list.length - 1);
        add(list[idx], fx, fy, flip: flipOf(fx, fy, 35));

        final u = _h(fx, fy, 34);
        final ox = fx + (_h(fx, fy, 36) - 0.5) * 1.6;
        final oy = fy + (_h(fx, fy, 37) - 0.5) * 1.6;
        if (!_isLegal(ox.round(), oy.round())) return;
        if (u < 0.30 && _has(_kFern)) {
          add(_kFern, ox, oy, flip: flipOf(fx, fy, 38));
        } else if (u < 0.44 && _has(_kTuft)) {
          add(_kTuft, ox, oy, flip: flipOf(fx, fy, 38));
        } else if (u < 0.47 && _has(_kStump)) {
          add(_kStump, ox, oy);
        } else if (u < 0.49 && _has(_kLog)) {
          add(_kLog, ox, oy, flip: flipOf(fx, fy, 38));
        }
      });
    }

    // ── Bushes: the forest edge, and a hedge round the player's land ──
    if (bushes.isNotEmpty) {
      _grid(1.5, 41, (fx, fy) {
        final gx = fx.round(), gy = fy.round();
        if (!_isLegal(gx, gy)) return;
        final f = _forestAt(fx, fy);
        final edge = _smooth(0.30, 0.43, f) * (1 - _smooth(0.56, 0.70, f));
        final ring =
            _isRealCell(gx, gy) && _treeClearance.contains(gy * kGridCols + gx)
            ? 0.30
            : 0.0;
        if (_h(fx, fy, 43) > math.max(edge * 0.55, ring)) return;
        final flowering = _h(fx, fy, 44) < (f < 0.5 ? 0.65 : 0.25);
        final n = bushes.length;
        final kind = flowering && n > 1
            ? bushes[1 + (_h(fx, fy, 45) * (n - 1)).floor().clamp(0, n - 2)]
            : bushes[0];
        add(kind, fx, fy, flip: flipOf(fx, fy, 46));
      });
    }

    // ── Meadows: flowers drift in patches over the open ground ──
    _grid(1.1, 51, (fx, fy) {
      final gx = fx.round(), gy = fy.round();
      if (!_isLegal(gx, gy)) return;
      final open = 1 - _smooth(0.38, 0.55, _forestAt(fx, fy));
      if (open <= 0) return;
      final patch = _smooth(0.50, 0.75, _noise(fx / 6, fy / 6, 5));
      if (flowers.isNotEmpty && _h(fx, fy, 53) < open * patch * 0.6) {
        // one colour family to a drift, with the odd stranger in it
        final pick = _h(fx, fy, 54) < 0.25
            ? _h(fx, fy, 55)
            : _noise(fx / 9, fy / 9, 6);
        final idx = (pick * flowers.length).floor().clamp(
          0,
          flowers.length - 1,
        );
        add(flowers[idx], fx, fy, flip: flipOf(fx, fy, 56));
      } else if (_has(_kTuft) && _h(fx, fy, 57) < open * 0.16) {
        add(_kTuft, fx, fy, flip: flipOf(fx, fy, 58));
      }
    });

    // ── Outcrops: a big rock with smaller ones round it, near water ──
    if (stones.isNotEmpty) {
      _grid(0.9, 61, (fx, fy) {
        final gx = fx.round(), gy = fy.round();
        if (!_isLegal(gx, gy)) return;
        final r = _noise(fx / 9, fy / 9, 7) + 0.12 * _wetness(gx, gy);
        final zone = _smooth(0.68, 0.82, r);
        if (_h(fx, fy, 62) > zone * 0.6) return;
        final t = _h(fx, fy, 63);
        final coin = _h(fx, fy, 64) < 0.5;
        final kind = t < 0.06 + 0.10 * zone
            ? (coin ? _kStoneE : _kStoneD)
            : t < 0.30
            ? (coin ? _kStoneC : _kStoneB)
            : (coin ? _kStoneA : _kStoneB);
        if (_has(kind)) add(kind, fx, fy, flip: flipOf(fx, fy, 65));
      });
    }

    out.addAll(_shoreDecor(_shoreBands()));

    // Landmarks last: they clear a space round themselves of whatever the
    // other scatters put there, so no tree grows through a ruin.
    final marks = _scatterLandmarks();
    final blocked = <int>{};
    for (final m in marks) {
      final r = m.kind >= _kBoatWreck ? 3 : 4;
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          blocked.add(_cellKey(m.gx + dx, m.gy + dy));
        }
      }
    }
    out.removeWhere((p) => blocked.contains(_cellKey(p.gx, p.gy)));
    out.addAll(marks);
    for (final p in out) {
      final k = p.kind;
      if (k <= _kStoneE ||
          (k >= _kBushA && k <= _kBroadleafL) ||
          k == _kStump ||
          k == _kLog ||
          (k >= _kRuinWall && k <= _kFlotsam)) {
        _solid.add(_cellKey(p.gx, p.gy));
      }
    }

    // One shared depth sort across every kind — a tree standing next to a
    // stone or another tree must still land in front of/behind it
    // correctly, which a separate pass per prop type could never guarantee.
    out.sort((a, b) => isoDrawOrder(a.gx, a.gy, 1, 1, b.gx, b.gy, 1, 1));
    return out;
  }

  // ── Landmarks and fauna (user 2026-11-05: "mache mir einige Tiere, welche
  // sich auf der Karte bewegen und zusätzlich einige Ruinen, gestrandetes
  // Boot etc. ... Sobald der Gegenstand durch einen Building Plot berührt
  // wird, verschwindet es") ──
  //
  // Both are planned from [buildableRegion] like every other prop, and
  // deterministically (same hashes, same grid): a Building Plot growing the
  // region re-plans the terrain, and whatever now stands on or beside claimed
  // land simply is not placed any more — everything else comes out exactly
  // where it was.

  /// Cells (padded keys) a standing sprite occupies — trees, bushes, stones,
  /// landmarks. The animals keep a cell clear of them, so nothing walks
  /// through a trunk. Filled by [_scatterProps].
  final Set<int> _solid = {};

  static const List<(int, double)> _kInlandMarks = [
    (_kRuinWall, 0.14),
    (_kRuinTower, 0.12),
    (_kRuinArch, 0.10),
    (_kRuinColumns, 0.12),
    (_kMenhirs, 0.10),
    (_kWagon, 0.14),
    (_kCampfire, 0.14),
    (_kWell, 0.14),
  ];
  static const List<(int, double)> _kBeachMarks = [
    (_kBoatWreck, 0.30),
    (_kBoatRow, 0.25),
    (_kWhaleRibs, 0.15),
    (_kFlotsam, 0.30),
  ];

  static int _pick(List<(int, double)> table, double r) {
    var acc = 0.0;
    for (final (kind, w) in table) {
      acc += w;
      if (r < acc) return kind;
    }
    return table.last.$1;
  }

  /// Ruins, camps and wells in the clearings (more of them in some "old"
  /// regions of the map than others), wrecks and bones on the beach. Always
  /// outside the tree clearance of the player's land, so a landmark vanishes
  /// before a building's roof could clip it.
  List<_PropPlacement> _scatterLandmarks() {
    final out = <_PropPlacement>[];
    final taken = <(double, double)>[];
    bool far(double fx, double fy, double d) {
      for (final (x, y) in taken) {
        final dx = x - fx, dy = y - fy;
        if (dx * dx + dy * dy < d * d) return false;
      }
      return true;
    }

    void put(int kind, double fx, double fy) {
      if (!_has(kind)) return;
      taken.add((fx, fy));
      final gx = fx.round(), gy = fy.round();
      out.add(
        _PropPlacement(
          kind,
          gx,
          gy,
          1.0,
          offX: fx - gx,
          offY: fy - gy,
          flip: _h(fx, fy, 99) < 0.5,
        ),
      );
    }

    _grid(10, 91, (fx, fy) {
      final gx = fx.round(), gy = fy.round();
      if (!_isRealCell(gx, gy)) return;
      final zone =
          0.03 + 0.10 * _smooth(0.55, 0.78, _noise(fx / 22, fy / 22, 9));
      if (_h(fx, fy, 92) > zone) return;
      if (_forestAt(fx, fy) > 0.58) return;
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          if (!_isTreeLegal(gx + dx, gy + dy)) return;
        }
      }
      if (!far(fx, fy, 16)) return;
      put(_pick(_kInlandMarks, _h(fx, fy, 93)), fx, fy);
    });

    final bands = _shoreBands();
    final keys = bands.beach.toList()..sort();
    for (final k in keys) {
      final (gx, gy) = _cellFromKey(k);
      if (!_isRealCell(gx, gy)) continue;
      if (_treeClearance.contains(gy * kGridCols + gx)) continue;
      if (_h(gx.toDouble(), gy.toDouble(), 95) > 0.0025) continue;
      if (!far(gx.toDouble(), gy.toDouble(), 18)) continue;
      put(
        _pick(_kBeachMarks, _h(gx.toDouble(), gy.toDouble(), 96)),
        gx.toDouble(),
        gy.toDouble(),
      );
    }
    return out;
  }

  /// One animal's route, flat: species, speed (tiles/s), pause (s at each
  /// stop), phase (0..1 of the loop), stop count, up to five (x, y) stops,
  /// salt. The painter walks the loop as a pure function of time, so the plan
  /// holds no state and an animal whose route is cut by new land is just not
  /// in the next plan.
  Float64List _scatterFauna() {
    final out = <double>[];
    void emit(
      int species,
      double speed,
      double pause,
      double phase,
      List<(double, double)> stops,
    ) {
      out
        ..add(species.toDouble())
        ..add(speed)
        ..add(pause)
        ..add(phase)
        ..add(stops.length.toDouble());
      for (var i = 0; i < 5; i++) {
        out
          ..add(i < stops.length ? stops[i].$1 : 0)
          ..add(i < stops.length ? stops[i].$2 : 0);
      }
      out.add(_h(stops[0].$1, stops[0].$2, 199));
    }

    bool free(double fx, double fy) {
      final gx = fx.round(), gy = fy.round();
      if (!_isRealCell(gx, gy) || !_isLegal(gx, gy)) return false;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (_solid.contains(_cellKey(gx + dx, gy + dy))) return false;
        }
      }
      return true;
    }

    final bands = _shoreBands();
    bool sand(double fx, double fy) {
      final gx = fx.round(), gy = fy.round();
      return _isRealCell(gx, gy) &&
          bands.beach.contains(_cellKey(gx, gy)) &&
          !_treeClearance.contains(gy * kGridCols + gx);
    }

    // A bird flies over land and sea alike, but not over the player's land.
    bool air(double fx, double fy) {
      final gx = fx.round(), gy = fy.round();
      return !(_isRealCell(gx, gy) &&
          _treeClearance.contains(gy * kGridCols + gx));
    }

    bool pond(double fx, double fy) {
      final gx = fx.round(), gy = fy.round();
      return _isRealCell(gx, gy) && bands.water.contains(_cellKey(gx, gy));
    }

    bool route(List<(double, double)> w, bool Function(double, double) ok) {
      for (var i = 0; i < w.length; i++) {
        final a = w[i], b = w[(i + 1) % w.length];
        final len = math.sqrt(
          (b.$1 - a.$1) * (b.$1 - a.$1) + (b.$2 - a.$2) * (b.$2 - a.$2),
        );
        final steps = math.max(1, (len / 0.5).ceil());
        for (var s = 0; s <= steps; s++) {
          final u = s / steps;
          if (!ok(a.$1 + (b.$1 - a.$1) * u, a.$2 + (b.$2 - a.$2) * u)) {
            return false;
          }
        }
      }
      return true;
    }

    /// [count] animals ambling round loops of four stops near ([cx], [cy]).
    void group(
      double cx,
      double cy,
      int species,
      int count,
      double radius,
      double speed,
      double pause,
      int salt,
      bool Function(double, double) ok,
    ) {
      for (var i = 0; i < count; i++) {
        final hx = cx + (_h(cx, cy, salt + i * 3) - 0.5) * radius;
        final hy = cy + (_h(cx, cy, salt + i * 3 + 1) - 0.5) * radius;
        final stops = [
          for (var k = 0; k < 4; k++)
            (
              hx + (_h(hx, hy, salt + 20 + k * 2) - 0.5) * radius * 1.6,
              hy + (_h(hx, hy, salt + 21 + k * 2) - 0.5) * radius * 1.6,
            ),
        ];
        if (!route(stops, ok)) continue;
        emit(
          species,
          speed * (0.85 + 0.3 * _h(hx, hy, salt + 9)),
          pause * (0.6 + 0.8 * _h(hx, hy, salt + 10)),
          _h(hx, hy, salt + 11),
          stops,
        );
      }
    }

    double open(double fx, double fy) =>
        1 - _smooth(0.38, 0.55, _forestAt(fx, fy));

    // Flocks of sheep in the open meadows.
    _grid(8, 111, (fx, fy) {
      if (!free(fx, fy) || open(fx, fy) < 0.45 || _h(fx, fy, 112) > 0.8) return;
      group(fx, fy, 0, 4 + (_h(fx, fy, 114) * 5).floor(), 2.8, 0.22, 5, 113, free);
    });
    // Deer where the meadow meets the wood.
    _grid(10, 121, (fx, fy) {
      final f = _forestAt(fx, fy);
      if (!free(fx, fy) || f < 0.28 || f > 0.64 || _h(fx, fy, 122) > 0.8) return;
      group(fx, fy, 1, 2 + (_h(fx, fy, 124) * 3).floor(), 3.2, 0.45, 6, 123, free);
    });
    // Cattle on the greener, flatter meadows.
    _grid(14, 171, (fx, fy) {
      if (!free(fx, fy) || open(fx, fy) < 0.4 || _h(fx, fy, 172) > 0.8) return;
      group(fx, fy, 10, 2 + (_h(fx, fy, 174) * 3).floor(), 2.6, 0.16, 6, 173, free);
    });
    // Forest dwellers may pass between the trees: only the cell itself must be
    // clear of a trunk.
    bool loose(double fx, double fy) {
      final gx = fx.round(), gy = fy.round();
      return _isRealCell(gx, gy) &&
          _isLegal(gx, gy) &&
          !_solid.contains(_cellKey(gx, gy));
    }
    // Foxes at the wood's edge, boar deeper in.
    _grid(13, 181, (fx, fy) {
      final f = _forestAt(fx, fy);
      if (!loose(fx, fy) || f < 0.3 || f > 0.62 || _h(fx, fy, 182) > 0.6) return;
      group(fx, fy, 8, 1, 3.0, 0.7, 3, 183, loose);
    });
    _grid(11, 191, (fx, fy) {
      final f = _forestAt(fx, fy);
      if (!loose(fx, fy) || f < 0.34 || f > 0.78 || _h(fx, fy, 192) > 0.9) return;
      group(fx, fy, 9, 2 + (_h(fx, fy, 194) * 3).floor(), 2.6, 0.3, 5, 193, loose);
    });
    // Flocks of crows, and the odd hawk, high over everything but the
    // player's land: birds fly where they like.
    bool sky(double fx, double fy) {
      final gx = fx.round(), gy = fy.round();
      return !(_isRealCell(gx, gy) &&
          _treeClearance.contains(gy * kGridCols + gx));
    }
    _grid(16, 201, (fx, fy) {
      if (!_isRealCell(fx.round(), fy.round()) || _h(fx, fy, 202) > 0.28) return;
      final rad = 7 + _h(fx, fy, 203) * 8;
      final a0 = _h(fx, fy, 204) * math.pi * 2;
      final n = 3 + (_h(fx, fy, 205) * 5).floor();
      final base = _h(fx, fy, 206);
      for (var i = 0; i < n; i++) {
        final j = _h(fx, fy, 210 + i);
        final stops = [
          for (var k = 0; k < 5; k++)
            (
              fx + math.cos(a0 + k * 1.2566) * rad * 1.3 + (j - 0.5) * 1.6,
              fy + math.sin(a0 + k * 1.2566) * rad + (_h(fx, fy, 220 + i) - 0.5) * 1.6,
            ),
        ];
        if (route(stops, sky)) emit(12, 1.7, 0, base + i * 0.012, stops);
      }
    });
    _grid(26, 231, (fx, fy) {
      if (!_isRealCell(fx.round(), fy.round()) || _h(fx, fy, 232) > 0.85) return;
      final rad = 9 + _h(fx, fy, 233) * 8;
      final a0 = _h(fx, fy, 234) * math.pi * 2;
      final stops = [
        for (var k = 0; k < 5; k++)
          (
            fx + math.cos(a0 + k * 1.2566) * rad,
            fy + math.sin(a0 + k * 1.2566) * rad * 1.2,
          ),
      ];
      if (route(stops, sky)) emit(13, 0.9, 0, _h(fx, fy, 235), stops);
    });
    // Rabbits, singly.
    _grid(5, 131, (fx, fy) {
      if (!free(fx, fy) || open(fx, fy) < 0.3 || _h(fx, fy, 132) > 0.5) return;
      group(fx, fy, 2, 1, 1.5, 0.7, 2.5, 133, free);
    });
    // Butterflies over the flower patches.
    _grid(5, 161, (fx, fy) {
      final gx = fx.round(), gy = fy.round();
      if (!_isRealCell(gx, gy) || !_isLegal(gx, gy)) return;
      if (open(fx, fy) < 0.5) return;
      if (_smooth(0.50, 0.75, _noise(fx / 6, fy / 6, 5)) < 0.5) return;
      if (_h(fx, fy, 162) > 0.35) return;
      group(fx, fy, 7, 2, 1.4, 0.45, 0, 163, (x, y) {
        final cx = x.round(), cy = y.round();
        return _isRealCell(cx, cy) && _isLegal(cx, cy);
      });
    });
    // On the shore: gulls and crabs; ducks on the water; gulls in the air.
    final keys = bands.beach.toList()..sort();
    for (final k in keys) {
      final (gx, gy) = _cellFromKey(k);
      if (!_isRealCell(gx, gy)) continue;
      final x = gx.toDouble(), y = gy.toDouble();
      final ring = bands.beachRing[k] ?? 0;
      final r = _h(x, y, 141);
      if (ring <= 1 && r < 0.04) {
        group(x, y, 3, 1 + (_h(x, y, 142) * 2).floor(), 1.4, 0.3, 4, 143, sand);
      } else if (ring == 0 && r > 0.88) {
        group(x, y, 4, 1, 1.0, 0.18, 3, 144, sand);
      } else if (ring == 1 && r > 0.6 && r < 0.66) {
        group(x, y, 11, 1, 1.2, 0.5, 2, 145, sand);
      } else if (ring <= 1 && r > 0.7 && r < 0.73 && sand(x, y)) {
        // a loop of the sea gulls riding the wind off the coast
        final rad = 6 + _h(x, y, 145) * 6;
        final a0 = _h(x, y, 146) * math.pi * 2;
        final stops = [
          for (var i = 0; i < 5; i++)
            (
              x + math.cos(a0 + i * 1.2566) * rad * 1.3,
              y + math.sin(a0 + i * 1.2566) * rad,
            ),
        ];
        if (route(stops, air)) {
          emit(6, 1.3, 0, _h(x, y, 147), stops);
        }
      }
    }
    for (final e in bands.waterRing.entries) {
      if (e.value < 2 || e.value > 4) continue;
      final (gx, gy) = _cellFromKey(e.key);
      if (!_isRealCell(gx, gy)) continue;
      final x = gx.toDouble(), y = gy.toDouble();
      if (_h(x, y, 151) > 0.015) continue;
      group(x, y, 5, 2 + (_h(x, y, 152) * 2).floor(), 3.0, 0.2, 1.5, 153, pond);
    }
    return Float64List.fromList(out);
  }

  /// The shore's own scenery: driftwood, shells and pebbles on the sand's
  /// wet edge, dune grass behind it, and reed beds standing in the shallows
  /// and on the bank. One roll per cell (nothing lines up), and nothing on
  /// the player's own claimed sand.
  List<_PropPlacement> _shoreDecor(
    ({
      Set<int> water,
      Set<int> beach,
      Map<int, int> waterRing,
      Map<int, int> beachRing,
    })
    bands,
  ) {
    final out = <_PropPlacement>[];
    void add(int kind, int gx, int gy, double dx, double dy, bool flip) {
      if (!_has(kind)) return;
      out.add(
        _PropPlacement(kind, gx, gy, 1.0, offX: dx, offY: dy, flip: flip),
      );
    }

    for (final k in bands.beach) {
      final (gx, gy) = _cellFromKey(k);
      if (_isRealCell(gx, gy) && buildableRegion.contains(gy * kGridCols + gx)) {
        continue;
      }
      final x = gx.toDouble(), y = gy.toDouble();
      final ring = bands.beachRing[k] ?? 0;
      final roll = _h(x, y, 71);
      final dx = (_h(x, y, 72) - 0.5) * 0.7;
      final dy = (_h(x, y, 73) - 0.5) * 0.7;
      final flip = _h(x, y, 74) < 0.5;
      final which = _h(x, y, 75) < 0.5 ? 0 : 1;
      final reedBed = _noise(x / 5, y / 5, 8) > 0.58;
      if (ring == 0) {
        if (reedBed && roll < 0.5) {
          add(_kReeds, gx, gy, dx, dy, flip);
        } else if (roll < 0.05) {
          add(_kDriftwoodA + which, gx, gy, dx, dy, flip);
        } else if (roll < 0.12) {
          add(_kShellA + which, gx, gy, dx, dy, flip);
        } else if (roll < 0.20) {
          add(_kStoneF, gx, gy, dx, dy, flip);
        } else if (roll < 0.23) {
          add(_kStoneA, gx, gy, dx, dy, flip);
        }
      } else if (ring == 1) {
        if (roll < 0.03) {
          add(_kStoneB, gx, gy, dx, dy, flip);
        } else if (roll < 0.13) {
          add(_kTuft, gx, gy, dx, dy, flip);
        }
      }
    }
    // reeds standing in the shallows
    for (final entry in bands.waterRing.entries) {
      if (entry.value != 1) continue;
      final (gx, gy) = _cellFromKey(entry.key);
      final x = gx.toDouble(), y = gy.toDouble();
      if (_noise(x / 5, y / 5, 8) > 0.55 && _h(x, y, 76) < 0.4) {
        add(
          _kReeds,
          gx,
          gy,
          (_h(x, y, 77) - 0.5) * 0.7,
          (_h(x, y, 78) - 0.5) * 0.7,
          _h(x, y, 79) < 0.5,
        );
      }
    }
    return out;
  }
}

/// Paints a [_TerrainData]: the grass, the shore meshes and the props. Pure
/// drawing — every decision was made by [_TerrainPlanner].
class _TerrainPainter extends CustomPainter {
  final _TerrainData data;

  _TerrainPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    // ── The ground: one shader fill, not thousands of Image widgets ──
    // ImageShader tiles in hardware, the same way a game engine's ground
    // material repeats — a single draw call regardless of how many times
    // the 1024×512 swatch actually repeats across the map.
    final shader = ImageShader(
      data.images[_kGrass]!,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.diagonal3Values(_kGrassTileScale, _kGrassTileScale, 1).storage,
      filterQuality: FilterQuality.medium,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);

    final sheets = data.sheets;
    final propBatch = data.propBatch;
    final shadowBatch = data.shadowBatch;
    if (!TerrainLayer.debugDrawOneByOne &&
        sheets != null &&
        propBatch != null &&
        shadowBatch != null) {
      // The batched path — see [_TerrainSheets]. Same picture, ~6 draw ops.
      final wash = sheets.wash;
      canvas.drawImageRect(
        wash,
        Rect.fromLTWH(0, 0, wash.width.toDouble(), wash.height.toDouble()),
        Offset.zero & isoCanvasSize,
        Paint()..filterQuality = FilterQuality.medium,
      );
      paintBeach(canvas);
      final shadowSheet = sheets.shadows;
      if (shadowSheet != null && shadowBatch.$1.isNotEmpty) {
        canvas.drawRawAtlas(
          shadowSheet,
          shadowBatch.$1,
          shadowBatch.$2,
          null,
          null,
          null,
          Paint()..filterQuality = FilterQuality.low,
        );
      }
      // Water and props: the moving half ([_TerrainLivePainter]).
      return;
    }

    paintGrassWash(canvas, size);
    paintBeach(canvas);
    _paintShadows(canvas);
    paintWater(canvas, 0);
    _paintProps(canvas);
  }

  /// The grass's soft colour wash, both layers. Drawn live only on the
  /// fallback path; normally baked once into [_TerrainSheets.wash].
  static void paintGrassWash(Canvas canvas, Size size) {
    // TWO layers, coarse then fine (user 2026-09-29, after the first pass
    // still read as flat: "Das Gras hat mir noch zu wenig Tiefe... auch
    // etwas grössere Bereiche in dunkleren oder helleren Grün- und
    // Brauntönen gestalten, damit es auch herausgezoomt wirkt"). The coarse
    // one is what a zoomed-OUT view actually sees — whole meadow-sized
    // zones running lighter or darker — the fine one is the close-up
    // mottling from the first pass, kept for when the camera is in close.
    // Toned down again (user 2026-09-29: "die Kanten sind besser geworden,
    // aber noch immer schwach sichtbar") — lower alpha both layers, and
    // denser overlap (spacing shrunk further below each layer's own radius)
    // so any one blob's contribution to a given pixel is smaller still.
    _paintGrassBlobs(
      canvas,
      size,
      seed: 'grassregion',
      spacing: 1300,
      jitterFactor: 1.5,
      minRadius: 900,
      maxRadius: 1300,
      minAlpha: 0.025,
      maxAlpha: 0.05,
      blobsMin: 2,
      blobsMax: 3,
    );
    _paintGrassBlobs(
      canvas,
      size,
      seed: 'grassblob',
      spacing: 340,
      jitterFactor: 1.5,
      minRadius: 200,
      maxRadius: 380,
      minAlpha: 0.012,
      maxAlpha: 0.03,
      blobsMin: 3,
      blobsMax: 4,
    );
  }

  /// The greens and browns every grass blob (coarse region or fine mottle)
  /// is drawn from — see [_paintGrassBlobs].
  static const List<Color> _kGrassTones = [
    Color(0xFF4C7A26), // shaded green (the buildings' leaf family, 2026-11-05)
    Color(0xFF6F9B30), // sunlit green
    Color(0xFF86A63A), // pale yellow-green
    Color(0xFF7E7A3C), // dry olive
    Color(0xFF6A5A30), // damp brown
  ];

  /// A blob's alpha across its own radius, as (position, fraction-of-peak)
  /// pairs approximating an ease-out curve rather than a straight line down
  /// to zero. A plain two-stop gradient (peak → transparent) is still an
  /// EDGE in disguise: its alpha keeps falling at a constant rate right up
  /// to the boundary and then stops dead at exactly zero — a discontinuity
  /// in the SLOPE, not the colour, which is precisely what a Mach band is
  /// (the eye exaggerates contrast at a slope change, not just at a colour
  /// change) — and at the size these blobs are drawn, a large circle's
  /// boundary is close to straight within any one screenful, which is
  /// exactly the "Kante" the user kept finding lowering alpha alone never
  /// removed (user 2026-09-29, after two rounds of "weniger Alpha" still:
  /// "Kante ist noch da"). Tapering the LAST stretch gradually instead of
  /// dropping straight to 0 removes that slope-jump, not just the colour.
  static const List<double> _kFalloffStops = [0, 0.55, 0.75, 0.9, 1.0];
  static const List<double> _kFalloff = [1.0, 0.7, 0.4, 0.15, 0.0];

  /// A soft wash of extra greens and browns over the flat tiled swatch —
  /// which repeats bit-for-bit everywhere, and reads as flat and lifeless
  /// next to the buildings' own hand-shaded art without it (user 2026-09-29:
  /// "die Textur des Grases anpassen, damit es noch mehr Leben gibt"). Called
  /// once per SCALE (see [paint]) with a different [seed] each time, so the
  /// two layers' random draws never line up and repeat the same pattern
  /// twice at two sizes.
  ///
  /// Each blob is a RADIAL GRADIENT easing out to transparent (see
  /// [_kFalloff]) — not a flat-filled circle softened with [MaskFilter.blur]
  /// (the first cut at this): a blurred hard-edged disc still has a
  /// perceptible rim once its colour is strong enough to notice at all, and
  /// at the spacing this used, that rim repeated as an actual grid of
  /// visible circles (user 2026-09-29: "ich sehe Kreise im Rasen, solche
  /// Muster sollten nicht sichtbar sein"). Neighbours also overlap heavily
  /// (spacing well under the blob's own radius) so no single one is ever
  /// isolated enough to read as a shape.
  static void _paintGrassBlobs(
    Canvas canvas,
    Size size, {
    required String seed,
    required double spacing,
    required double jitterFactor,
    required double minRadius,
    required double maxRadius,
    required double minAlpha,
    required double maxAlpha,
    required int blobsMin,
    required int blobsMax,
  }) {
    var i = 0;
    for (var y = -spacing; y < size.height + spacing; y += spacing) {
      for (var x = -spacing; x < size.width + spacing; x += spacing) {
        final span = blobsMax - blobsMin + 1;
        final n = blobsMin + (_hash01('$seed n$i') * span).floor();
        for (var k = 0; k < n; k++) {
          final jx = (_hash01('$seed x$i,$k') - 0.5) * spacing * jitterFactor;
          final jy = (_hash01('$seed y$i,$k') - 0.5) * spacing * jitterFactor;
          final r =
              minRadius + _hash01('$seed r$i,$k') * (maxRadius - minRadius);
          final tone = _kGrassTones[(_hash01('$seed c$i,$k') *
                  _kGrassTones.length)
              .floor()
              .clamp(0, _kGrassTones.length - 1)];
          final alpha =
              minAlpha + _hash01('$seed a$i,$k') * (maxAlpha - minAlpha);
          final center = Offset(x + jx, y + jy);
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..shader = ui.Gradient.radial(
                center,
                r,
                [for (final f in _kFalloff) tone.withValues(alpha: alpha * f)],
                _kFalloffStops,
              ),
          );
        }
        i++;
      }
    }
  }

  /// The beach, banded smoothly from sand at the waterline to fully
  /// transparent (pure grass) at its outer ring, then the water banded
  /// from shallow to deep the same way — both per-cell rather than
  /// per-run, since the colour now varies cell to cell (user 2026-09-08:
  /// "das Wasser deutlich spannender gestalten und es soll wieder ein
  /// Ufer geben... Übergangslinien... löschen"). Beach pebbles are ordinary
  /// props drawn later in [_scatterProps] so they depth-sort with
  /// everything else.
  ///
  /// `isAntiAlias: false` on both fills (user 2026-09-14: visible seam lines
  /// between tiles) — each cell is its own [footprintPath], and two
  /// independently anti-aliased polygons whose edges land on the same
  /// floating-point line still rasterise a faint translucent seam where they
  /// meet, most visible against water's fairly uniform colour. Snapping the
  /// fill to whole pixels closes the gap; the tiles are small enough at this
  /// zoom that the loss of edge smoothing is not visible.
  ///
  /// ONE drawVertices call per band instead of a path per cell (tens of
  /// thousands of them): the picture stays small to record, and the GPU
  /// replays a single mesh each frame instead of a draw op per diamond. Two
  /// triangles per cell with `isAntiAlias: false` cover exactly the pixels the
  /// old per-cell diamond did — shared edges still land on the same pixel
  /// grid, so no seams.
  @visibleForTesting
  void paintShore(Canvas canvas) {
    paintBeach(canvas);
    paintWater(canvas, 0);
  }

  /// The sand: the VOXEL sand tile (the same block size as the grass and the
  /// buildings) through the beach mesh, whose per-vertex colour is a tint
  /// and, towards the grass, an alpha — `modulate` multiplies the two.
  void paintBeach(Canvas canvas) {
    final tile = data.images.length > _kSandTile ? data.images[_kSandTile] : null;
    if (tile == null) return;
    canvas.drawVertices(
      data.beachMesh,
      BlendMode.modulate,
      Paint()
        ..isAntiAlias = false
        ..shader = _tileShader(tile, 0, 0),
    );
  }

  /// The water: the voxel water tile, its ripples drifting slowly along the
  /// ground's own diagonal as [t] runs, tinted by depth per vertex.
  void paintWater(Canvas canvas, double t) {
    final tile =
        data.images.length > _kWaterTile ? data.images[_kWaterTile] : null;
    if (tile == null) return;
    canvas.drawVertices(
      data.waterMesh,
      BlendMode.modulate,
      Paint()
        ..isAntiAlias = false
        ..shader = _tileShader(tile, t * 5.0, t * 2.5),
    );
  }

  static Shader _tileShader(ui.Image tile, double dx, double dy) => ImageShader(
    tile,
    TileMode.repeated,
    TileMode.repeated,
    (Matrix4.translationValues(dx, dy, 0)
          ..scaleByDouble(_kGrassTileScale, _kGrassTileScale, 1, 1))
        .storage,
    filterQuality: FilterQuality.medium,
  );

  /// Every standing prop's shadow, ALL before any prop: a shadow lies on the
  /// ground, so it belongs under trees and stones, never over one. Each is the
  /// silhouette thrown from the prop's own foot (see [castShadowMask]) and is
  /// placed exactly where the prop's picture goes, at the picture's scale.
  void _paintShadows(Canvas canvas) {
    final shadows = data.shadows;
    if (shadows.isEmpty) return;
    final props = data.plan.props;
    // Tinted HERE, at paint time, with the exact same colour+opacity a
    // building's own shadow uses (`BuildingGroundShadow._ShadowPainter`) —
    // [castShadowImage] now hands back a plain alpha mask, not a pre-baked
    // colour, so the two can never drift apart again (user 2026-09-29).
    final paint = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(
        kShadowTint.withValues(alpha: kShadowOpacity),
        BlendMode.srcIn,
      );
    for (var o = 0; o < props.length; o += _propStride) {
      final kind = props[o].toInt();
      if (kind >= shadows.length) continue;
      final mask = shadows[kind];
      final image = data.images[kind];
      // A turned prop (beach debris) has no upright shadow to throw.
      if (mask == null || image == null || props[o + 6] != 0) continue;
      final destW = image.width / _kPropPx * props[o + 3];
      final unit = destW / image.width;
      final foot = gridToScreen(
        props[o + 1] + 0.5 + props[o + 4],
        props[o + 2] + 0.5 + props[o + 5],
      );
      final dest = Rect.fromLTWH(
        foot.dx - destW / 2,
        foot.dy - image.height * unit,
        mask.width * unit,
        mask.height * unit,
      );
      final src = Rect.fromLTWH(
        0,
        0,
        mask.width.toDouble(),
        mask.height.toDouble(),
      );
      // A mirrored tree throws a mirrored shadow too, or the ground patch
      // would lean the wrong way relative to the crown standing over it.
      if (props[o + 7] == 0) {
        canvas.drawImageRect(mask, src, dest, paint);
      } else {
        canvas.save();
        canvas.translate(foot.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-foot.dx, 0);
        canvas.drawImageRect(mask, src, dest, paint);
        canvas.restore();
      }
    }
  }

  /// Anchored by its FOOT, like a building's own art — the sprite rises UP
  /// from the ground point rather than being centred through it. A rotated
  /// prop turns around its own centre instead (fine for small ground-hugging
  /// debris — driftwood/pebbles/shells have no strong "up" the way a
  /// standing tree does).
  void _paintProps(Canvas canvas) {
    final props = data.plan.props;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (var o = 0; o < props.length; o += _propStride) {
      final kind = props[o].toInt();
      final image = data.images[kind];
      if (image == null) continue;
      final gx = props[o + 1], gy = props[o + 2];
      final destW = image.width / _kPropPx * props[o + 3];
      final destH = destW * image.height / image.width;
      final foot = gridToScreen(
        gx + 0.5 + props[o + 4],
        gy + 0.5 + props[o + 5],
      );
      final srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final rotation = props[o + 6];
      if (rotation == 0) {
        final rect = Rect.fromLTWH(
          foot.dx - destW / 2,
          foot.dy - destH,
          destW,
          destH,
        );
        if (props[o + 7] == 0) {
          canvas.drawImageRect(image, srcRect, rect, paint);
        } else {
          // Mirrored about the foot, not the picture's own centre — the
          // trunk stays planted on the same spot it was scattered at.
          canvas.save();
          canvas.translate(foot.dx, 0);
          canvas.scale(-1, 1);
          canvas.translate(-foot.dx, 0);
          canvas.drawImageRect(image, srcRect, rect, paint);
          canvas.restore();
        }
        continue;
      }
      final center = Offset(foot.dx, foot.dy - destH / 2);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      canvas.drawImageRect(
        image,
        srcRect,
        Rect.fromCenter(center: Offset.zero, width: destW, height: destH),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter old) =>
      !identical(old.data, data);
}

/// The terrain's MOVING half (user 2026-11-05: "die Gebäude bewegen sich … das
/// gleiche gilt auch für die Bäume"): the water, whose ripples drift, and
/// every prop, those that grow swaying about their foot like the plants on the
/// buildings do. Repainted by [time] at a modest frame rate, over the static
/// half ([_TerrainPainter]) that never changes.
class _TerrainLivePainter extends CustomPainter {
  final _TerrainData data;
  final ValueListenable<double> time;

  _TerrainLivePainter(this.data, this.time) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final sheets = data.sheets;
    final sway = data.sway;
    if (TerrainLayer.debugDrawOneByOne || sheets == null || sway == null) {
      return; // the static painter drew everything
    }
    final t = time.value;
    _TerrainPainter(data).paintWater(canvas, t);
    if (sway.count == 0) return;
    canvas.drawRawAtlas(
      sheets.props,
      sway.transforms(t),
      sway.src,
      null,
      null,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _TerrainLivePainter old) =>
      !identical(old.data, data);
}

/// Every drawable prop as an atlas entry that can be re-posed each frame:
/// its source rect, its resting transform and, for the plants, a sway.
class _SwayBatch {
  final int count;
  final Float32List src;

  /// Per prop: scale, foot x, foot y, anchor x (image width / 2), anchor y
  /// (image height).
  final Float32List _geom;

  /// Per prop: sway amplitude in radians (0 = stands still) and phase.
  final Float32List _amp;
  final Float32List _phase;

  _SwayBatch._(this.count, this.src, this._geom, this._amp, this._phase);

  /// How far each kind leans in the wind, in radians. Trees barely, grass a
  /// lot — the same ordering as the amplitudes on the buildings' own plants.
  static double ampOf(int kind) {
    if (kind >= _kConiferS && kind <= _kConiferL) return 0.011;
    if (kind >= _kBroadleafS && kind <= _kBroadleafL) return 0.017;
    if (kind >= _kBushA && kind <= _kBushD) return 0.022;
    if (kind >= _kFlowersA && kind <= _kFlowersD) return 0.035;
    if (kind == _kTuft) return 0.04;
    if (kind == _kFern) return 0.03;
    if (kind == _kReeds) return 0.05;
    return 0.0;
  }

  static _SwayBatch build(
    Float64List props,
    List<ui.Image?> images,
    List<Rect?> slots,
  ) {
    final src = <double>[];
    final geom = <double>[];
    final amp = <double>[];
    final phase = <double>[];
    for (var o = 0; o < props.length; o += _propStride) {
      final kind = props[o].toInt();
      final image = kind < images.length ? images[kind] : null;
      final flip = props[o + 7] == 0 ? 0 : 1;
      final slot = kind * 2 + flip < slots.length ? slots[kind * 2 + flip] : null;
      if (image == null || slot == null) continue;
      final scale = props[o + 3] / _kPropPx;
      final foot = gridToScreen(
        props[o + 1] + 0.5 + props[o + 4],
        props[o + 2] + 0.5 + props[o + 5],
      );
      src.addAll([slot.left, slot.top, slot.right, slot.bottom]);
      geom.addAll([
        scale,
        foot.dx,
        foot.dy,
        image.width / 2,
        image.height.toDouble(),
      ]);
      amp.add(ampOf(kind));
      // A wave of wind crossing the map: neighbours lean together, far
      // plants are out of step.
      phase.add(
        (props[o + 1] * 0.34 + props[o + 2] * 0.21) +
            (_hash01('sway${props[o + 1]},${props[o + 2]}') - 0.5) * 0.8,
      );
    }
    return _SwayBatch._(
      amp.length,
      Float32List.fromList(src),
      Float32List.fromList(geom),
      Float32List.fromList(amp),
      Float32List.fromList(phase),
    );
  }

  /// The [RSTransform]s (scos, ssin, tx, ty each) at time [t] seconds: every
  /// prop turned about its foot by its own share of the wind.
  Float32List transforms(double t) {
    final out = Float32List(count * 4);
    final gust = 0.7 + 0.3 * math.sin(t * 0.45);
    for (var i = 0; i < count; i++) {
      final g = i * 5;
      final scale = _geom[g];
      final amp = _amp[i];
      final a = amp == 0
          ? 0.0
          : amp * gust * math.sin(t * 1.7 - _phase[i]);
      final scos = scale * math.cos(a), ssin = scale * math.sin(a);
      final o = i * 4;
      out[o] = scos;
      out[o + 1] = ssin;
      out[o + 2] = _geom[g + 1] - scos * _geom[g + 3] + ssin * _geom[g + 4];
      out[o + 3] = _geom[g + 2] - ssin * _geom[g + 3] - scos * _geom[g + 4];
    }
    return out;
  }
}

/// Test hook: paints the shore meshes of [plan] onto [canvas].
@visibleForTesting
void paintShoreForTest(Canvas canvas, Object plan) => _TerrainPainter(
  _TerrainData(const {}, const [], plan as _TerrainPlan),
).paintShore(canvas);

/// The grass tile is rendered at 4x the canvas (terrain_voxel.py TILE_SCALE: one
/// cell = 256 px, the canvas draws a cell 64 px wide), exactly the way the
/// buildings' art is 4x the canvas — so a ground block is a building block.
/// (It was drawn four times too coarse until 2026-11-05.)
const double _kGrassTileScale = 1 / _kPropPx;

// ── The animals ──────────────────────────────────────────────────
/// Draws every animal of the plan at time [time]. Their routes are loops of
/// stops ([_TerrainPlanner._scatterFauna]); where an animal is, which way it
/// faces and what it is doing is a pure function of the clock, so there is no
/// state to keep and nothing to reset when the terrain is re-planned.
///
/// The pictures face down-right (`_Se`) or up-right (`_Ne`) on screen and are
/// mirrored for the left-hand directions. Walking is a bob, a rabbit hops, a
/// gull's two flying pictures alternate.
class _FaunaPainter extends CustomPainter {
  final _TerrainData data;
  final ValueListenable<double> time;

  _FaunaPainter(this.data, this.time) : super(repaint: time);

  static const int _sheep = 0,
      _deer = 1,
      _rabbit = 2,
      _gull = 3,
      _crab = 4,
      _duck = 5,
      _gullFly = 6,
      _butterfly = 7,
      _fox = 8,
      _boar = 9,
      _cow = 10,
      _frog = 11,
      _crow = 12,
      _hawk = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final f = data.plan.fauna;
    if (f.isEmpty) return;
    final t = time.value;
    final view = canvas.getDestinationClipBounds().inflate(160);
    final poses = <_FaunaPose>[];
    for (var o = 0; o + _faunaStride <= f.length; o += _faunaStride) {
      final pose = _pose(f, o, t);
      if (pose != null && view.contains(pose.foot)) poses.add(pose);
    }
    poses.sort((a, b) => a.foot.dy.compareTo(b.foot.dy));
    final shadow = Paint()..color = const Color(0x2E000000);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final p in poses) {
      final image = p.image < data.images.length ? data.images[p.image] : null;
      if (image == null) continue;
      final w = image.width / _kPropPx, h = image.height / _kPropPx;
      if (p.shadow > 0) {
        canvas.drawOval(
          Rect.fromCenter(
            center: p.foot,
            width: w * p.shadow,
            height: w * p.shadow * 0.3,
          ),
          shadow,
        );
      }
      final rect = Rect.fromLTWH(
        p.foot.dx - w / 2,
        p.foot.dy - p.lift - h,
        w,
        h,
      );
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      if (!p.flip) {
        canvas.drawImageRect(image, src, rect, paint);
      } else {
        canvas.save();
        canvas.translate(p.foot.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-p.foot.dx, 0);
        canvas.drawImageRect(image, src, rect, paint);
        canvas.restore();
      }
      _redrawInFront(canvas, p.foot, rect, paint);
    }
  }

  /// The animals live on a layer above the props, so a tree, ruin or bush
  /// that stands in FRONT of an animal (its foot lower on screen) is drawn
  /// again over it, clipped to the animal's own box.
  void _redrawInFront(Canvas canvas, Offset foot, Rect box, Paint paint) {
    final occ = data.occluders;
    final ys = occ.footY;
    if (ys.isEmpty) return;
    // first prop whose foot is below the animal's
    var lo = 0, hi = ys.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ys[mid] <= foot.dy + 0.5) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final hits = <int>[];
    for (var i = lo; i < ys.length && ys[i] < foot.dy + occ.maxH; i++) {
      hits.add(i);
    }
    if (hits.isEmpty) return;
    final props = data.plan.props;
    var clipped = false;
    // back to front among themselves: the plan's own depth order
    final order = [for (final i in hits) occ.offsets[i]]..sort();
    for (final o in order) {
      final kind = props[o].toInt();
      final image = data.images[kind];
      if (image == null) continue;
      final destW = image.width / _kPropPx * props[o + 3];
      final destH = destW * image.height / image.width;
      final pf = gridToScreen(
        props[o + 1] + 0.5 + props[o + 4],
        props[o + 2] + 0.5 + props[o + 5],
      );
      final rect = Rect.fromLTWH(pf.dx - destW / 2, pf.dy - destH, destW, destH);
      if (!rect.overlaps(box)) continue;
      if (!clipped) {
        canvas.save();
        canvas.clipRect(box);
        clipped = true;
      }
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      if (props[o + 7] == 0) {
        canvas.drawImageRect(image, src, rect, paint);
      } else {
        canvas.save();
        canvas.translate(pf.dx, 0);
        canvas.scale(-1, 1);
        canvas.translate(-pf.dx, 0);
        canvas.drawImageRect(image, src, rect, paint);
        canvas.restore();
      }
    }
    if (clipped) canvas.restore();
  }

  /// Where animal [o] is at [t] and what picture it shows.
  _FaunaPose? _pose(Float64List f, int o, double t) {
    final species = f[o].toInt();
    final speed = f[o + 1], pause = f[o + 2], phase = f[o + 3];
    final n = f[o + 4].toInt();
    final salt = f[o + 15];
    if (n < 2 || speed <= 0) return null;
    double sx(int i) => f[o + 5 + i * 2];
    double sy(int i) => f[o + 6 + i * 2];

    var total = 0.0;
    final lens = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      lens[i] = math.sqrt(
        (sx(j) - sx(i)) * (sx(j) - sx(i)) + (sy(j) - sy(i)) * (sy(j) - sy(i)),
      );
      total += lens[i] / speed + pause;
    }
    if (total <= 0) return null;
    var u = (t + phase * total) % total;
    var x = sx(0), y = sy(0), dx = 1.0, dy = 0.0;
    var moving = true;
    var stop = 0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final len = math.max(lens[i], 1e-6);
      dx = (sx(j) - sx(i)) / len;
      dy = (sy(j) - sy(i)) / len;
      final d = lens[i] / speed;
      if (u < d) {
        final k = u / d;
        x = sx(i) + (sx(j) - sx(i)) * k;
        y = sy(i) + (sy(j) - sy(i)) * k;
        break;
      }
      u -= d;
      x = sx(j);
      y = sy(j);
      if (u < pause) {
        moving = false;
        stop = i;
        break;
      }
      u -= pause;
    }

    // Direction on screen: +x runs down-right, +y down-left.
    final screenX = dx - dy, screenY = dx + dy;
    final up = screenY < 0;
    final flip = screenX < 0;
    final foot = gridToScreen(x + 0.5, y + 0.5);
    final beat = t * 7 + salt * 6.28;

    switch (species) {
      case _sheep:
      case _deer:
        final sheep = species == _sheep;
        final se = sheep ? _kFSheepSe : _kFDeerSe;
        final ne = sheep ? _kFSheepNe : _kFDeerNe;
        final graze = sheep ? _kFSheepGraze : _kFDeerGraze;
        if (!moving) {
          // at each stop it either grazes or stands and looks about
          final grazing = ((stop + (salt * 7).floor()) & 1) == 0;
          return _FaunaPose(foot, grazing ? graze : (up ? ne : se), flip, 0, 0.7);
        }
        return _FaunaPose(
          foot,
          up ? ne : se,
          flip,
          math.sin(beat).abs() * 1.4,
          0.7,
        );
      case _rabbit:
        return _FaunaPose(
          foot,
          up ? _kFRabbitNe : _kFRabbitSe,
          flip,
          moving ? math.sin(t * 5 + salt * 6.28).abs() * 7 : 0,
          0.6,
        );
      case _gull:
        return _FaunaPose(
          foot,
          up ? _kFGullNe : _kFGullSe,
          flip,
          moving ? math.sin(beat * 1.3).abs() * 1.0 : 0,
          0.6,
        );
      case _crab:
        return _FaunaPose(
          foot,
          _kFCrab,
          flip,
          0,
          0.6,
        );
      case _duck:
        return _FaunaPose(
          foot,
          up ? _kFDuckNe : _kFDuckSe,
          flip,
          math.sin(t * 1.6 + salt * 6.28) * 0.8,
          0,
        );
      case _gullFly:
        final flap = ((t * 5 + salt * 10).floor() & 1) == 0;
        final image = up
            ? (flap ? _kFGullUpNe : _kFGullDownNe)
            : (flap ? _kFGullUpSe : _kFGullDownSe);
        return _FaunaPose(
          foot,
          image,
          flip,
          46 + math.sin(t * 1.3 + salt * 6.28) * 4,
          0.5,
        );
      case _fox:
      case _boar:
        final fox = species == _fox;
        return _FaunaPose(
          foot,
          fox ? (up ? _kFFoxNe : _kFFoxSe) : (up ? _kFBoarNe : _kFBoarSe),
          flip,
          moving ? math.sin(beat * (fox ? 1.4 : 1.0)).abs() * 1.4 : 0,
          0.7,
        );
      case _cow:
        if (!moving) {
          final grazing = ((stop + (salt * 7).floor()) & 1) == 0;
          return _FaunaPose(foot, grazing ? _kFCowGraze : (up ? _kFCowNe : _kFCowSe), flip, 0, 0.7);
        }
        return _FaunaPose(foot, up ? _kFCowNe : _kFCowSe, flip, math.sin(beat * 0.7).abs() * 1.0, 0.7);
      case _frog:
        return _FaunaPose(
          foot,
          _kFFrog,
          flip,
          moving ? math.sin(t * 6 + salt * 6.28).abs() * 4 : 0,
          0.5,
        );
      case _crow:
        final flap = ((t * 7 + salt * 10).floor() & 1) == 0;
        return _FaunaPose(
          foot,
          up ? (flap ? _kFCrowUpNe : _kFCrowDownNe) : (flap ? _kFCrowUpSe : _kFCrowDownSe),
          flip,
          80 + math.sin(t * 1.7 + salt * 6.28) * 6,
          0.4,
        );
      case _hawk:
        return _FaunaPose(
          foot,
          up ? _kFHawkNe : _kFHawkSe,
          flip,
          125 + math.sin(t * 0.8 + salt * 6.28) * 5,
          0.45,
        );
      case _butterfly:
        final open = ((t * 9 + salt * 10).floor() & 1) == 0;
        return _FaunaPose(
          foot + Offset(math.sin(t * 3 + salt * 9) * 3, 0),
          open ? _kFButterOpen : _kFButterShut,
          flip,
          12 + math.sin(t * 4 + salt * 6.28) * 5,
          0.5,
        );
    }
    return null;
  }

  @override
  bool shouldRepaint(covariant _FaunaPainter old) =>
      !identical(old.data, data);
}

class _FaunaPose {
  final Offset foot;
  final int image;
  final bool flip;

  /// Pixels the picture hovers above [foot] (a hop, a flying bird).
  final double lift;

  /// Width of the ground shadow as a fraction of the picture's; 0 for none.
  final double shadow;

  const _FaunaPose(this.foot, this.image, this.flip, this.lift, this.shadow);
}
