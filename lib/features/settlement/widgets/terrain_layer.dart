import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/building_definitions.dart' show kGridCols, kGridRows;
import '../data/iso_grid.dart';
import '../data/water_cells.dart' show kWaterRuns;

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
///    in clumps (a stand of trees, a flower patch, a rock outcrop), and dirt
///    is bare ground trodden under a grove's canopy, not a free-floating
///    decal — see [_TerrainPainter._scatterProps].
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
}

class _TerrainLayerState extends State<TerrainLayer> {
  ui.Image? _grassTile;
  ui.Image? _stoneProp;
  ui.Image? _stoneFlatProp;
  ui.Image? _stoneBoulderProp;
  ui.Image? _wildflowerHeatherProp;
  ui.Image? _wildflowerGorseProp;
  ui.Image? _dirtProp;
  ui.Image? _treeConiferProp;
  ui.Image? _treeBroadleafProp;
  ui.Image? _driftwoodProp;
  ui.Image? _shellProp;

  @override
  void initState() {
    super.initState();
    _load('assets/images/terrain/grass_tile.webp', (im) => _grassTile = im);
    _load('assets/images/terrain/prop_stone.webp', (im) => _stoneProp = im);
    // Two more rock silhouettes (user 2026-09-14: "Die Steine bitte in
    // unterschiedlichen Grössen und Formen") — outcrops/beach pebbles pick
    // among all three instead of rescaling one shape.
    _load(
      'assets/images/terrain/prop_stone_flat.webp',
      (im) => _stoneFlatProp = im,
    );
    _load(
      'assets/images/terrain/prop_stone_boulder.webp',
      (im) => _stoneBoulderProp = im,
    );
    _load(
      'assets/images/terrain/prop_wildflower_heather.webp',
      (im) => _wildflowerHeatherProp = im,
    );
    _load(
      'assets/images/terrain/prop_wildflower_gorse.webp',
      (im) => _wildflowerGorseProp = im,
    );
    _load('assets/images/terrain/prop_dirt_patch.webp', (im) => _dirtProp = im);
    _load(
      'assets/images/terrain/prop_tree_conifer.webp',
      (im) => _treeConiferProp = im,
    );
    _load(
      'assets/images/terrain/prop_tree_broadleaf.webp',
      (im) => _treeBroadleafProp = im,
    );
    // Beach-only detail (user 2026-09-14: "der Strand soll noch Holz und
    // kleine Muscheln haben").
    _load(
      'assets/images/terrain/prop_driftwood.webp',
      (im) => _driftwoodProp = im,
    );
    _load('assets/images/terrain/prop_shell.webp', (im) => _shellProp = im);
  }

  Future<void> _load(String asset, void Function(ui.Image) set) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => set(frame.image));
  }

  @override
  Widget build(BuildContext context) {
    final grass = _grassTile;
    // Nothing to paint yet on the very first frame (the asset load is async)
    // — a blank frame here for a few milliseconds beats guessing at a filler
    // colour that would itself have to be kept in sync with the tile.
    if (grass == null) return const SizedBox.shrink();
    return CustomPaint(
      size: isoCanvasSize,
      painter: _TerrainPainter(
        buildableRegion: widget.buildableRegion,
        grassTile: grass,
        stoneProp: _stoneProp,
        stoneFlatProp: _stoneFlatProp,
        stoneBoulderProp: _stoneBoulderProp,
        wildflowerHeatherProp: _wildflowerHeatherProp,
        wildflowerGorseProp: _wildflowerGorseProp,
        dirtProp: _dirtProp,
        treeConiferProp: _treeConiferProp,
        treeBroadleafProp: _treeBroadleafProp,
        driftwoodProp: _driftwoodProp,
        shellProp: _shellProp,
      ),
    );
  }
}

/// One placed prop, ready to be depth-sorted against every other prop
/// regardless of which kind it is — a tree standing next to a stone must
/// still draw in the right order relative to it, not just within its own
/// type's pass.
class _PropPlacement {
  final ui.Image image;
  final int gx;
  final int gy;
  final double widthInTiles;

  /// Sub-tile drift from the cell's centre, in tile units (0 = dead centre).
  /// Every OTHER scatter already lands off-centre by construction — a
  /// cluster's own random angle+radius — so this defaults to 0 for them.
  /// [_beachDebris] is the one caller that places one item per cell on a
  /// fixed grid and needs this to avoid looking planted (user 2026-09-14:
  /// "nicht so mechanisch wie jetzt").
  final double offX;
  final double offY;

  /// Rotation in radians, purely cosmetic — real driftwood/pebbles never lie
  /// at the same angle twice.
  final double rotation;

  const _PropPlacement(
    this.image,
    this.gx,
    this.gy,
    this.widthInTiles, {
    this.offX = 0,
    this.offY = 0,
    this.rotation = 0,
  });
}

class _TerrainPainter extends CustomPainter {
  final Set<int> buildableRegion;
  final ui.Image grassTile;
  final ui.Image? stoneProp;
  final ui.Image? stoneFlatProp;
  final ui.Image? stoneBoulderProp;
  final ui.Image? wildflowerHeatherProp;
  final ui.Image? wildflowerGorseProp;
  final ui.Image? dirtProp;
  final ui.Image? treeConiferProp;
  final ui.Image? treeBroadleafProp;
  final ui.Image? driftwoodProp;
  final ui.Image? shellProp;

  _TerrainPainter({
    required this.buildableRegion,
    required this.grassTile,
    required this.stoneProp,
    required this.stoneFlatProp,
    required this.stoneBoulderProp,
    required this.wildflowerHeatherProp,
    required this.wildflowerGorseProp,
    required this.dirtProp,
    required this.treeConiferProp,
    required this.treeBroadleafProp,
    required this.driftwoodProp,
    required this.shellProp,
  });

  /// Every rendered stone shape available right now — outcrops and beach
  /// pebbles both pick from this instead of one shape rescaled (user
  /// 2026-09-14: "Die Steine bitte in unterschiedlichen Grössen und
  /// Formen").
  List<ui.Image> get _stoneVariants => [
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
  static double _coastAt(double gy) =>
      12.0 + 5.0 * math.sin(gy * 0.085) + 2.6 * math.sin(gy * 0.031 + 1.1);

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

  @override
  void paint(Canvas canvas, Size size) {
    // ── The ground: one shader fill, not thousands of Image widgets ──
    // ImageShader tiles in hardware, the same way a game engine's ground
    // material repeats — a single draw call regardless of how many times
    // the 1024×512 swatch actually repeats across the map.
    final shader = ImageShader(
      grassTile,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);

    _paintWater(canvas);
    _scatterProps(canvas);
  }

  static const List<(int, int)> _kNeighbors4 = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  static const List<(int, int)> _kNeighbors8 = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (1, 1), (-1, -1), (1, -1), (-1, 1),
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
  })? _shoreCache;

  ({
    Set<int> water,
    Set<int> beach,
    Map<int, int> waterRing,
    Map<int, int> beachRing,
  }) _shoreBands() {
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
    return Color.lerp(base, j > 0 ? Colors.white : Colors.black, j.abs() * 0.07)!;
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
  void _paintWater(Canvas canvas) {
    final bands = _shoreBands();
    final fillPaint = Paint()..isAntiAlias = false;

    for (final k in bands.beach) {
      final (gx, gy) = _cellFromKey(k);
      final ring = bands.beachRing[k] ?? _kBeachRingCap;
      final alpha = 1.0 - ring / (_kBeachRingCap + 1);
      final color =
          _jitter(_sand, _hash01('shoretone$gx,$gy')).withOpacity(alpha);
      canvas.drawPath(
        footprintPath(gx, gy, 1, 1),
        fillPaint..color = color,
      );
    }

    for (final k in bands.water) {
      final (gx, gy) = _cellFromKey(k);
      final ring = bands.waterRing[k] ?? _kWaterRingCap;
      final color = _jitter(_waterColorForRing(ring), _hash01('watertone$gx,$gy'));
      canvas.drawPath(
        footprintPath(gx, gy, 1, 1),
        fillPaint..color = color,
      );
    }
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

  /// [buildableRegion] dilated by two rings, real cells only. Flowers and
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
  Set<int>? _treeClearanceCache;
  Set<int> get _treeClearance {
    final cached = _treeClearanceCache;
    if (cached != null) return cached;
    final all = Set<int>.from(buildableRegion);
    var frontier = buildableRegion;
    for (var ring = 0; ring < 2; ring++) {
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
    return !(_isRealCell(gx, gy) && _treeClearance.contains(gy * kGridCols + gx));
  }

  /// FNV-1a, exactly like tool/blender/terrain.py's own `_hash01` — not
  /// because the two ever need to agree on any SPECIFIC position (Dart
  /// picks its own scatter, independently of whatever terrain.py last
  /// rolled), just because it is a known-good, dependency-free way to turn
  /// a seed string into a repeatable 0..1 float.
  double _hash01(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = (h ^ c) & 0xFFFFFFFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h / 0xFFFFFFFF;
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
    required List<ui.Image> images,
    required double widthInTiles,
    // A size RANGE rather than one fixed width, so a clump of (say) stones
    // reads as different-sized rocks, not one shape rescaled uniformly
    // (user 2026-09-14: "Die Steine bitte in unterschiedlichen Grössen und
    // Formen"). Defaults to no variation — every other caller is unaffected.
    double? widthMax,
    bool Function(int gx, int gy)? legal,
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
        final gx = (ccx + math.cos(a) * r).round();
        final gy = (ccy + math.sin(a) * r).round();
        if (!isLegal(gx, gy)) continue;
        final imgIdx =
            (_hash01('$seed i$c-$i') * images.length).floor().clamp(
                  0,
                  images.length - 1,
                );
        final w = wMax > widthInTiles
            ? widthInTiles + _hash01('$seed w$c-$i') * (wMax - widthInTiles)
            : widthInTiles;
        out.add(_PropPlacement(images[imgIdx], gx, gy, w));
      }
    }
    return out;
  }

  /// A patch of bare, trodden ground close to each grove's own centre — the
  /// dirt a stand of trees casts underneath it, not a free-floating decal
  /// out in the open grass.
  List<_PropPlacement> _dirtNearGroves(
    List<(int, int)> groveCenters, {
    bool Function(int gx, int gy)? legal,
  }) {
    final dirt = dirtProp;
    if (dirt == null) return const [];
    final isLegal = legal ?? _isLegal;
    final out = <_PropPlacement>[];
    for (var c = 0; c < groveCenters.length; c++) {
      final (ccx, ccy) = groveCenters[c];
      for (var i = 0; i < 2; i++) {
        final a = _hash01('terrain_dirt a$c-$i') * 2 * math.pi;
        final r = _hash01('terrain_dirt r$c-$i') * 2.2;
        final gx = (ccx + math.cos(a) * r).round();
        final gy = (ccy + math.sin(a) * r).round();
        if (!isLegal(gx, gy)) continue;
        out.add(_PropPlacement(dirt, gx, gy, 1.0));
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
    const spacing = 3.1;
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
        final img =
            _hash01('terrain_clearing i$c-$i') < 0.55 ? heather : gorse;
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
      if (_isRealCell(gx, gy) && buildableRegion.contains(gy * kGridCols + gx)) {
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
        final w = 0.26 + _hash01('beachStoneW$gx,$gy') * 0.34;
        out.add(_PropPlacement(stones[idx], gx, gy, w,
            offX: offX, offY: offY, rotation: rotation));
      } else if (roll < 0.14 && wood != null) {
        final w = 0.5 + _hash01('beachWoodW$gx,$gy') * 0.25;
        out.add(_PropPlacement(wood, gx, gy, w,
            offX: offX, offY: offY, rotation: rotation));
      } else if (roll < 0.18 && shell != null) {
        final w = 0.22 + _hash01('beachShellW$gx,$gy') * 0.12;
        out.add(_PropPlacement(shell, gx, gy, w,
            offX: offX, offY: offY, rotation: rotation));
      }
    }
    return out;
  }

  void _scatterProps(Canvas canvas) {
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
      placements.addAll(_clusterScatter(
        centers: forestCenters,
        seed: 'terrain_forest_trees',
        perClusterMin: 7,
        perClusterMax: 12,
        radius: 2.7,
        images: [conifer, conifer, conifer, broadleaf],
        widthInTiles: 1.1,
        legal: _isTreeLegal,
      ));
      placements.addAll(_dirtNearGroves(forestCenters, legal: _isTreeLegal));
    }

    placements.addAll(_clearingDecor(clearings));

    // Wildflower patches under the canopy itself, elsewhere in the wild
    // field — ground cover, not just what fills a clearing.
    final heather = wildflowerHeatherProp;
    final gorse = wildflowerGorseProp;
    if (heather != null && gorse != null) {
      placements.addAll(_clusterScatter(
        centers: _clusterCenters('terrain_flower_patch', 65),
        seed: 'terrain_flower',
        perClusterMin: 3,
        perClusterMax: 8,
        radius: 1.6,
        images: [heather, gorse],
        widthInTiles: 0.55,
      ));
    }

    // Rock outcrops: a smaller, sparser clumping — a few stones together,
    // not a field of gravel. Every rendered shape (small/flat/boulder) is
    // in play, at a genuine size range, not one shape rescaled.
    final stones = _stoneVariants;
    if (stones.isNotEmpty) {
      placements.addAll(_clusterScatter(
        centers: _clusterCenters('terrain_outcrop', 32),
        seed: 'terrain_stone',
        perClusterMin: 2,
        perClusterMax: 5,
        radius: 1.8,
        images: stones,
        widthInTiles: 0.4,
        widthMax: 0.85,
      ));
    }
    placements.addAll(_beachDebris(_shoreBands().beach));

    // One shared depth sort across every kind — a tree standing next to a
    // stone or another tree must still land in front of/behind it
    // correctly, which a separate pass per prop type could never guarantee.
    placements.sort(
      (a, b) => isoDrawOrder(a.gx, a.gy, 1, 1, b.gx, b.gy, 1, 1),
    );
    for (final p in placements) {
      _drawProp(canvas, p);
    }
  }

  /// Anchored by its FOOT, like a building's own art — the sprite rises UP
  /// from the ground point rather than being centred through it. A rotated
  /// prop turns around its own centre instead (fine for small ground-hugging
  /// debris — driftwood/pebbles/shells have no strong "up" the way a
  /// standing tree does).
  void _drawProp(Canvas canvas, _PropPlacement p) {
    final destW = kIsoTileW * p.widthInTiles;
    final destH = destW * p.image.height / p.image.width;
    final foot = gridToScreen(p.gx + 0.5 + p.offX, p.gy + 0.5 + p.offY);
    final srcRect =
        Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (p.rotation == 0) {
      final rect =
          Rect.fromLTWH(foot.dx - destW / 2, foot.dy - destH, destW, destH);
      canvas.drawImageRect(p.image, srcRect, rect, paint);
      return;
    }
    final center = Offset(foot.dx, foot.dy - destH / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(p.rotation);
    canvas.drawImageRect(
      p.image,
      srcRect,
      Rect.fromCenter(center: Offset.zero, width: destW, height: destH),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter old) =>
      old.buildableRegion != buildableRegion ||
      old.grassTile != grassTile ||
      old.stoneProp != stoneProp ||
      old.stoneFlatProp != stoneFlatProp ||
      old.stoneBoulderProp != stoneBoulderProp ||
      old.wildflowerHeatherProp != wildflowerHeatherProp ||
      old.wildflowerGorseProp != wildflowerGorseProp ||
      old.dirtProp != dirtProp ||
      old.treeConiferProp != treeConiferProp ||
      old.treeBroadleafProp != treeBroadleafProp ||
      old.driftwoodProp != driftwoodProp ||
      old.shellProp != shellProp;
}
