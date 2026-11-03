import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show compute, setEquals, visibleForTesting;
import 'package:flutter/material.dart';
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

  @visibleForTesting
  static Future<ui.Image> levelTile(ui.Image image) =>
      _TerrainData._levelled(image);
}

class _TerrainLayerState extends State<TerrainLayer> {
  _TerrainData? _data;

  @override
  void initState() {
    super.initState();
    _resolve();
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
    return CustomPaint(size: isoCanvasSize, painter: _TerrainPainter(data));
  }
}

// ── What a prop is, as a number ─────────────────────────────────
// The terrain is planned in a background isolate, and a ui.Image cannot cross
// that boundary — so the plan speaks in these kind ids and the painter looks
// the picture up by them.
const int _kStone = 0,
    _kStoneFlat = 1,
    _kStoneBoulder = 2,
    _kHeather = 3,
    _kGorse = 4,
    _kConifer = 5,
    _kBroadleaf = 6,
    _kDriftwood = 7,
    _kShell = 8,
    _kGrass = 9;

/// The props that STAND, and so cast a shadow on the ground (user 2026-09-22:
/// "den Schatten jetzt auch auf den Rest der Map"): trees and stones. Flat
/// things — dirt, shells, driftwood, the little flowers — lie in the ground and
/// have none worth drawing.
const Set<int> _kShadowCasters = {
  _kStone,
  _kStoneFlat,
  _kStoneBoulder,
  _kConifer,
  _kBroadleaf,
};

/// How deep each caster's shadow lies on the ground, as a fraction of its
/// picture's width (see `castShadowMask`'s `groundDepth`). Without it a tree's
/// shadow is a hair-thin strip. A crown covers a patch, so trees get a wide,
/// SHALLOW ellipse (0.14 — 0.22 read too round); stones are compact, so theirs
/// is smaller and hugs the rock.
const Map<int, double> _kShadowDepth = {
  _kConifer: 0.14,
  _kBroadleaf: 0.14,
  _kStone: 0.08,
  _kStoneFlat: 0.08,
  _kStoneBoulder: 0.08,
};

const List<String> _kAssets = [
  'assets/images/terrain/prop_stone.webp', // _kStone
  // Two more rock silhouettes (user 2026-09-14: "Die Steine bitte in
  // unterschiedlichen Grössen und Formen") — outcrops/beach pebbles pick
  // among all three instead of rescaling one shape.
  'assets/images/terrain/prop_stone_flat.webp',
  'assets/images/terrain/prop_stone_boulder.webp',
  'assets/images/terrain/prop_wildflower_heather.webp',
  'assets/images/terrain/prop_wildflower_gorse.webp',
  'assets/images/terrain/prop_tree_conifer.webp',
  'assets/images/terrain/prop_tree_broadleaf.webp',
  // Beach-only detail (user 2026-09-14: "der Strand soll noch Holz und
  // kleine Muscheln haben").
  'assets/images/terrain/prop_driftwood.webp',
  'assets/images/terrain/prop_shell.webp',
  'assets/images/terrain/grass_tile.webp', // _kGrass
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
    var available = 0;
    for (var k = 0; k < _kGrass; k++) {
      if (images[k] != null) available |= 1 << k;
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
          if (_kShadowCasters.contains(k) && images[k] != null)
            castShadowImage(
              images[k]!,
              groundDepth: _kShadowDepth[k] ?? 0,
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
      return frame.image;
    } catch (_) {
      return null;
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
      final destW = kIsoTileW * props[o + 3];
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
      final destW = kIsoTileW * props[o + 3];
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
  final int available;
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

  const _TerrainPlan({
    required this.beachPositions,
    required this.beachColors,
    required this.waterPositions,
    required this.waterColors,
    required this.props,
  });
}

const int _propStride = 8;

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
    _TerrainPlanner(region, (1 << _kGrass) - 1).plan();

@visibleForTesting
Float64List propsOfPlanForTest(Object plan) => (plan as _TerrainPlan).props;

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

  /// Rotation in radians, purely cosmetic — real driftwood/pebbles never lie
  /// at the same angle twice.
  final double rotation;

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
    this.rotation = 0,
    this.flip = false,
  });
}

/// Decides the whole terrain — shore, sand, forest, flowers, stones — as pure
/// maths on cell coordinates. No canvas, no images: it runs in a background
/// isolate (see [_planTerrain]), and the result is deterministic, so two runs
/// over the same region are identical.
class _TerrainPlanner {
  final Set<int> buildableRegion;

  // A prop's kind id when its picture actually loaded, else null — the old
  // "is the image there yet" checks, unchanged.
  final int? stoneProp;
  final int? stoneFlatProp;
  final int? stoneBoulderProp;
  final int? wildflowerHeatherProp;
  final int? wildflowerGorseProp;
  final int? treeConiferProp;
  final int? treeBroadleafProp;
  final int? driftwoodProp;
  final int? shellProp;

  _TerrainPlanner(this.buildableRegion, int available)
    : stoneProp = _has(available, _kStone),
      stoneFlatProp = _has(available, _kStoneFlat),
      stoneBoulderProp = _has(available, _kStoneBoulder),
      wildflowerHeatherProp = _has(available, _kHeather),
      wildflowerGorseProp = _has(available, _kGorse),
      treeConiferProp = _has(available, _kConifer),
      treeBroadleafProp = _has(available, _kBroadleaf),
      driftwoodProp = _has(available, _kDriftwood),
      shellProp = _has(available, _kShell);

  static int? _has(int mask, int kind) => (mask >> kind) & 1 == 1 ? kind : null;

  _TerrainPlan plan() {
    final bands = _shoreBands();
    final beach = _shoreMesh(bands.beach, (k, gx, gy) {
      final ring = bands.beachRing[k] ?? _kBeachRingCap;
      final alpha = 1.0 - ring / (_kBeachRingCap + 1);
      return _jitter(
        _sand,
        _hash01('shoretone$gx,$gy'),
      ).withValues(alpha: alpha);
    });
    final water = _shoreMesh(bands.water, (k, gx, gy) {
      final ring = bands.waterRing[k] ?? _kWaterRingCap;
      return _jitter(_waterColorForRing(ring), _hash01('watertone$gx,$gy'));
    });
    final placements = _scatterProps();
    final props = Float64List(placements.length * _propStride);
    for (var i = 0; i < placements.length; i++) {
      final p = placements[i];
      final o = i * _propStride;
      props[o] = p.kind.toDouble();
      props[o + 1] = p.gx.toDouble();
      props[o + 2] = p.gy.toDouble();
      props[o + 3] = p.widthInTiles;
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
    );
  }

  /// One diamond per cell, as two triangles (north-east-south, north-south-west)
  /// with a per-vertex colour. See [_TerrainPainter.paintShore] for why a mesh
  /// and not a path per cell.
  (Float32List, Int32List) _shoreMesh(
    Set<int> cells,
    Color Function(int key, int gx, int gy) colorOf,
  ) {
    final positions = Float32List(cells.length * 12);
    final colors = Int32List(cells.length * 6);
    var i = 0;
    for (final k in cells) {
      final (gx, gy) = _cellFromKey(k);
      final n = gridToScreen(gx.toDouble(), gy.toDouble());
      final e = gridToScreen(gx + 1.0, gy.toDouble());
      final s = gridToScreen(gx + 1.0, gy + 1.0);
      final w = gridToScreen(gx.toDouble(), gy + 1.0);
      final p = i * 12;
      positions[p] = n.dx;
      positions[p + 1] = n.dy;
      positions[p + 2] = e.dx;
      positions[p + 3] = e.dy;
      positions[p + 4] = s.dx;
      positions[p + 5] = s.dy;
      positions[p + 6] = n.dx;
      positions[p + 7] = n.dy;
      positions[p + 8] = s.dx;
      positions[p + 9] = s.dy;
      positions[p + 10] = w.dx;
      positions[p + 11] = w.dy;
      final argb = colorOf(k, gx, gy).toARGB32();
      for (var v = 0; v < 6; v++) {
        colors[i * 6 + v] = argb;
      }
      i++;
    }
    return (positions, colors);
  }

  /// Every rendered stone shape available right now — outcrops and beach
  /// pebbles both pick from this instead of one shape rescaled (user
  /// 2026-09-14: "Die Steine bitte in unterschiedlichen Grössen und
  /// Formen").
  List<int> get _stoneVariants => [
    if (stoneProp != null) stoneProp!,
    if (stoneFlatProp != null) stoneFlatProp!,
    if (stoneBoulderProp != null) stoneBoulderProp!,
  ];

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
  static const Color _sand = Color(0xFFDCC48C);

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


  /// Picks [count] cluster centres on GRASS cells only (not water). A real
  /// landscape grows in clumps — a stand of trees, a flower patch, a rock
  /// outcrop — not as independent uniform noise, which is what a "wild"
  /// per-instance scatter reads as (user 2026-09-07).
  List<(int, int)> _clusterCenters(String seed, int count) {
    final out = <(int, int)>[];
    for (var c = 0; c < count; c++) {
      final cx = (_hash01('${seed}cx$c') * kGridCols).floor();
      final cy = (_hash01('${seed}cy$c') * kGridRows).floor();
      if (_isLegal(cx, cy)) out.add((cx, cy));
    }
    return out;
  }

  /// Scatters [perClusterMin]..[perClusterMax] instances of [images] (picked
  /// per-instance, for a mixed clump rather than a monoculture) around each
  /// of [centers], within [radius] grid cells.
  List<_PropPlacement> _clusterScatter({
    required List<(int, int)> centers,
    required String seed,
    required int perClusterMin,
    required int perClusterMax,
    required double radius,
    required List<int> images,
    required double widthInTiles,
    // A size RANGE rather than one fixed width, so a clump of (say) stones
    // reads as different-sized rocks, not one shape rescaled uniformly
    // (user 2026-09-14: "Die Steine bitte in unterschiedlichen Grössen und
    // Formen"). Defaults to no variation — every other caller is unaffected.
    double? widthMax,
    bool Function(int gx, int gy)? legal,
    // Half the instances mirrored left-right — free shape variety out of a
    // single sprite (user 2026-09-29). Off by default: flipping a rock or a
    // flower is invisible (both read symmetric at this size), so only a
    // caller with something worth mirroring turns it on.
    bool mirror = false,
  }) {
    if (images.isEmpty) return const [];
    final isLegal = legal ?? _isLegal;
    final wMax = widthMax ?? widthInTiles;
    final out = <_PropPlacement>[];
    for (var c = 0; c < centers.length; c++) {
      final (ccx, ccy) = centers[c];
      final span = perClusterMax - perClusterMin + 1;
      final n = perClusterMin + (_hash01('${seed}n$c') * span).floor();
      for (var i = 0; i < n; i++) {
        final a = _hash01('$seed a$c-$i') * 2 * math.pi;
        final r = _hash01('$seed r$c-$i') * radius;
        // The prop's TRUE continuous position — legality is still checked on
        // the grid cell it falls in (props stay off buildable land, water,
        // …), but the leftover fraction becomes its sub-tile drift instead
        // of being thrown away. Every instance used to snap dead-centre onto
        // its cell, which at this density reads as a planted grid rather
        // than a stand of trees or a scatter of stones (user 2026-09-29: "die
        // Steine sind viel zu uniform und gleichmässig verteilt" — the same
        // fix [_beachDebris] already got for driftwood/pebbles, 2026-09-14).
        final fx = ccx + math.cos(a) * r;
        final fy = ccy + math.sin(a) * r;
        final gx = fx.round();
        final gy = fy.round();
        if (!isLegal(gx, gy)) continue;
        final imgIdx = (_hash01('$seed i$c-$i') * images.length).floor().clamp(
          0,
          images.length - 1,
        );
        final w = wMax > widthInTiles
            ? widthInTiles + _hash01('$seed w$c-$i') * (wMax - widthInTiles)
            : widthInTiles;
        out.add(
          _PropPlacement(
            images[imgIdx],
            gx,
            gy,
            w,
            offX: fx - gx,
            offY: fy - gy,
            flip: mirror && _hash01('$seed flip$c-$i') < 0.5,
          ),
        );
      }
    }
    return out;
  }

  /// A few dozen clearings scattered through the wild field, each with its
  /// own radius — the "Lichtungen" that let sky and flowers interrupt the
  /// canopy instead of it reading as one solid green wall (user 2026-09-08:
  /// "gerne einige Lichtungen mit Blumen und Büschen einbauen").
  List<(int, int, double)> _clearingCenters(
    String seed,
    int count,
    double minRadius,
    double maxRadius,
  ) {
    final out = <(int, int, double)>[];
    for (var c = 0; c < count; c++) {
      final cx = (_hash01('${seed}cx$c') * kGridCols).floor();
      final cy = (_hash01('${seed}cy$c') * kGridRows).floor();
      if (!_isLegal(cx, cy)) continue;
      final r = minRadius + _hash01('${seed}r$c') * (maxRadius - minRadius);
      out.add((cx, cy, r));
    }
    return out;
  }

  bool _inClearing(int gx, int gy, List<(int, int, double)> clearings) {
    for (final (cx, cy, r) in clearings) {
      final dx = (gx - cx).toDouble(), dy = (gy - cy).toDouble();
      if (dx * dx + dy * dy <= r * r) return true;
    }
    return false;
  }

  /// Dense, closely-packed grove centres covering the ENTIRE picture — every
  /// dry cell, buildable or not, real grid or the canvas's off-map padding
  /// alike — with a gap left around each of [clearings]. ONE pass, ONE
  /// spacing, no seam (user 2026-09-14: "das Spielfeld überall, auch an den
  /// Kanten genau gleich dicht mit dem Wald bedecken" — an earlier version
  /// ran the padding at a coarser spacing than the real grid "since it's
  /// scenery nobody stands on", and the density STEP right at the real
  /// grid's own edge was exactly what that read as). [_isTreeLegal] (not the
  /// plain [_isLegal]) screens every point, so the river is free to run
  /// through the wood exactly as it does anywhere else on the map, and so is
  /// the buffer around the player's own buildings.
  List<(int, int)> _forestGrid(
    String seed,
    List<(int, int, double)> clearings,
  ) {
    // Widened alongside the per-grove count (user 2026-09-29, three rounds
    // of "weniger Bäume"): thinning only the CLUMPS while leaving the same
    // number of clumps everywhere eventually just makes each one look
    // sparse rather than the wood as a whole feeling less dense. Still ONE
    // spacing for the real grid and the off-map padding alike — see the
    // doc comment above on why that matters.
    // 3.6 → 4.2 (user 2026-11-03: "etwas weniger Bäume") — together with
    // the per-grove count below, about a third fewer trees overall.
    const spacing = 4.2;
    final out = <(int, int)>[];
    var i = 0;
    for (var fy = _extY0.toDouble(); fy < _extY1; fy += spacing) {
      for (var fx = _extX0.toDouble(); fx < _extX1; fx += spacing) {
        final jx = (_hash01('${seed}jx$i') - 0.5) * spacing * 0.7;
        final jy = (_hash01('${seed}jy$i') - 0.5) * spacing * 0.7;
        i++;
        final gx = (fx + jx).round();
        final gy = (fy + jy).round();
        if (!_isTreeLegal(gx, gy)) continue;
        if (_inClearing(gx, gy, clearings)) continue;
        out.add((gx, gy));
      }
    }
    return out;
  }

  /// Flowers and flowering bushes filling each clearing, denser than the
  /// stray patches under the canopy elsewhere — the open ground a Lichtung
  /// actually is. Gorse is a genuine shrub as well as a bloom, so it stands
  /// in for both the "Blumen" and the "Büsche" asked for; there is no
  /// separate bush prop to draw.
  List<_PropPlacement> _clearingDecor(List<(int, int, double)> clearings) {
    final heather = wildflowerHeatherProp;
    final gorse = wildflowerGorseProp;
    if (heather == null || gorse == null) return const [];
    final out = <_PropPlacement>[];
    for (var c = 0; c < clearings.length; c++) {
      final (ccx, ccy, r) = clearings[c];
      final n = (r * r * 0.85).round();
      for (var i = 0; i < n; i++) {
        final a = _hash01('terrain_clearing a$c-$i') * 2 * math.pi;
        // sqrt of a uniform draw spreads points evenly over the DISC area
        // rather than bunching them near the centre.
        final rr = math.sqrt(_hash01('terrain_clearing r$c-$i')) * r * 0.92;
        final gx = (ccx + math.cos(a) * rr).round();
        final gy = (ccy + math.sin(a) * rr).round();
        if (!_isLegal(gx, gy)) continue;
        final img = _hash01('terrain_clearing i$c-$i') < 0.55 ? heather : gorse;
        out.add(_PropPlacement(img, gx, gy, 0.55));
      }
    }
    return out;
  }

  /// The beach's own loose detail, one independent roll per cell rather than
  /// [_clusterScatter]'s clumping — a real strand has stray pebbles and
  /// driftwood, not clumps of them: small stones ("kleine Steine im Sand",
  /// user 2026-09-08, now in several shapes/sizes — see [_stoneVariants]
  /// and 2026-09-14's "unterschiedlichen Grössen und Formen"), driftwood and
  /// seashells (user 2026-09-14: "der Strand soll noch Holz und kleine
  /// Muscheln haben"). Mutually exclusive per cell — a beach scattered with
  /// all three at once would clutter rather than decorate. [_isLegal]
  /// excludes beach cells on purpose (keeps it clear of forest clutter — see
  /// its own doc comment), so this checks [buildableRegion] directly
  /// instead: the only thing beach debris needs to stay off is a building
  /// actually standing on that stretch of sand.
  ///
  /// Drifted off the cell's dead centre and spun to a random angle (user
  /// 2026-09-14: "zufälliger am Strand verteilen und nicht so mechanisch wie
  /// jetzt") — one item per eligible cell still decides WHERE debris lands,
  /// but every earlier version then planted it exactly on the grid point,
  /// which is what read as mechanical: a real strand has nothing lining up.
  List<_PropPlacement> _beachDebris(Set<int> beach) {
    final stones = _stoneVariants;
    final wood = driftwoodProp;
    final shell = shellProp;
    final out = <_PropPlacement>[];
    for (final k in beach) {
      final (gx, gy) = _cellFromKey(k);
      if (_isRealCell(gx, gy) &&
          buildableRegion.contains(gy * kGridCols + gx)) {
        continue;
      }
      final roll = _hash01('beach$gx,$gy');
      // Up to two-thirds of a tile off centre — enough to drift past the
      // cell's own boundary and break the grid alignment, not so far it
      // reads as belonging to the neighbouring cell instead.
      final offX = (_hash01('beachOffX$gx,$gy') - 0.5) * 0.65;
      final offY = (_hash01('beachOffY$gx,$gy') - 0.5) * 0.65;
      final rotation = _hash01('beachRot$gx,$gy') * 2 * math.pi;
      if (roll < 0.10 && stones.isNotEmpty) {
        final idx = (_hash01('beachStoneI$gx,$gy') * stones.length)
            .floor()
            .clamp(0, stones.length - 1);
        // Widened (user 2026-09-29: "auch das Holz am Strand" — the same
        // "too uniform" complaint applied to every stray pebble): a strand
        // has both gravel-sized chips and a genuine rock washed up on it.
        final w = 0.2 + _hash01('beachStoneW$gx,$gy') * 0.55;
        out.add(
          _PropPlacement(
            stones[idx],
            gx,
            gy,
            w,
            offX: offX,
            offY: offY,
            rotation: rotation,
          ),
        );
      } else if (roll < 0.14 && wood != null) {
        final w = 0.35 + _hash01('beachWoodW$gx,$gy') * 0.55;
        out.add(
          _PropPlacement(
            wood,
            gx,
            gy,
            w,
            offX: offX,
            offY: offY,
            rotation: rotation,
          ),
        );
      } else if (roll < 0.18 && shell != null) {
        final w = 0.22 + _hash01('beachShellW$gx,$gy') * 0.12;
        out.add(
          _PropPlacement(
            shell,
            gx,
            gy,
            w,
            offX: offX,
            offY: offY,
            rotation: rotation,
          ),
        );
      }
    }
    return out;
  }

  /// Every prop, depth-sorted back to front.
  List<_PropPlacement> _scatterProps() {
    final placements = <_PropPlacement>[];

    // Clearings first: their centres are used both to carve gaps out of the
    // forest grid below and to seed the flower/bush fill inside them.
    final clearings = _clearingCenters('terrain_clearing', 28, 3.0, 5.5);

    // The forest: the whole wild field, packed densely enough that
    // neighbouring canopies overlap into one continuous wood rather than
    // reading as scattered groves.
    final conifer = treeConiferProp;
    final broadleaf = treeBroadleafProp;
    if (conifer != null && broadleaf != null) {
      final forestCenters = _forestGrid('terrain_forest', clearings);
      placements.addAll(
        _clusterScatter(
          centers: forestCenters,
          seed: 'terrain_forest_trees',
          // Fewer still per grove (user 2026-09-29, a third pass: "du kannst
          // noch mehr Bäume löschen") — was 7-12, then 5-9, then 4-7, then
          // 3-5 (user 2026-11-03: "etwas weniger Bäume").
          perClusterMin: 3,
          perClusterMax: 4,
          radius: 2.7,
          images: [conifer, conifer, conifer, broadleaf],
          // Bigger, and a real size RANGE (user 2026-09-29: "die Bäume sind
          // im Verhältnis zu den Gebäuden noch zu klein... auch in
          // unterschiedlichen Grössen und Formen darstellen") — 1.1 read as a
          // shrub next to a two-storey building's own art. A young tree at
          // the low end of the range and an old one at the high end read as
          // different specimens, not one sprite copy-pasted everywhere.
          widthInTiles: 1.5,
          widthMax: 2.4,
          legal: _isTreeLegal,
          mirror: true,
        ),
      );
    }

    placements.addAll(_clearingDecor(clearings));

    // Wildflower patches under the canopy itself, elsewhere in the wild
    // field — ground cover, not just what fills a clearing.
    final heather = wildflowerHeatherProp;
    final gorse = wildflowerGorseProp;
    if (heather != null && gorse != null) {
      placements.addAll(
        _clusterScatter(
          centers: _clusterCenters('terrain_flower_patch', 65),
          seed: 'terrain_flower',
          perClusterMin: 3,
          perClusterMax: 8,
          radius: 1.6,
          images: [heather, gorse],
          widthInTiles: 0.55,
        ),
      );
    }

    // Rock outcrops: a smaller, sparser clumping — a few stones together,
    // not a field of gravel. Every rendered shape (small/flat/boulder) is
    // in play, at a genuine size range, not one shape rescaled.
    //
    // Count AND size both widened (user 2026-09-29: "die Steine sind viel zu
    // uniform und gleichmässig verteilt"): 2-5 stones of near-identical size
    // at every one of 32 evenly-seeded centres reads as a catalogue, not a
    // landscape. Some outcrops are now a single boulder, others a proper
    // scree of seven, and a stone within one can be a third the size of its
    // neighbour — the sub-tile drift [_clusterScatter] now also applies
    // keeps them from lining up even within a cluster.
    final stones = _stoneVariants;
    if (stones.isNotEmpty) {
      placements.addAll(
        _clusterScatter(
          centers: _clusterCenters('terrain_outcrop', 32),
          seed: 'terrain_stone',
          perClusterMin: 1,
          perClusterMax: 7,
          radius: 2.1,
          images: stones,
          widthInTiles: 0.3,
          widthMax: 1.15,
          mirror: true,
        ),
      );
    }
    placements.addAll(_beachDebris(_shoreBands().beach));

    // One shared depth sort across every kind — a tree standing next to a
    // stone or another tree must still land in front of/behind it
    // correctly, which a separate pass per prop type could never guarantee.
    placements.sort((a, b) => isoDrawOrder(a.gx, a.gy, 1, 1, b.gx, b.gy, 1, 1));
    return placements;
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
      Matrix4.identity().storage,
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
      paintShore(canvas);
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
      if (propBatch.$1.isNotEmpty) {
        canvas.drawRawAtlas(
          sheets.props,
          propBatch.$1,
          propBatch.$2,
          null,
          null,
          null,
          Paint()..filterQuality = FilterQuality.medium,
        );
      }
      return;
    }

    paintGrassWash(canvas, size);
    paintShore(canvas);
    _paintShadows(canvas);
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
    Color(0xFF5E7F38), // shaded green
    Color(0xFF8FAE5C), // sunlit green
    Color(0xFFB9CC7E), // pale yellow-green
    Color(0xFF8A7A46), // dry olive
    Color(0xFF6E5A34), // damp brown
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
    final paint = Paint()..isAntiAlias = false;
    canvas.drawVertices(data.beachMesh, BlendMode.dst, paint);
    canvas.drawVertices(data.waterMesh, BlendMode.dst, paint);
  }

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
      final destW = kIsoTileW * props[o + 3];
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
      final destW = kIsoTileW * props[o + 3];
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

/// Test hook: paints the shore meshes of [plan] onto [canvas].
@visibleForTesting
void paintShoreForTest(Canvas canvas, Object plan) => _TerrainPainter(
  _TerrainData(const {}, const [], plan as _TerrainPlan),
).paintShore(canvas);
