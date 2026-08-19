import 'dart:math' as math;
import 'dart:ui';

// Matrix4 only — this file stays projection maths, and the one transform it
// hands out (mapTransform) is part of that: how a grid coordinate reaches the
// screen is exactly what iso_grid is for.
import 'package:flutter/widgets.dart' show Matrix4;

import 'building_definitions.dart' show kGridCols, kGridRows;

// ── Das Raster um 45° gedreht (user 2026-08-01) ──────────────
// "Ich will das Raster aber wie bei forge of empires nicht horizontal und
//  vertikal, sondern alles um 45° gedreht."
//
// ── The one thing to understand ──
// The GRID DOES NOT CHANGE. A building still sits at gridX/gridY and covers
// gridW × gridH cells; the economy, the placement rules, the road adjacency and
// every saved row stay exactly as they are. Isometric is a different way of
// PROJECTING those same numbers onto the screen, and it lives here so the map
// widget is the only thing that has to learn it.
//
// ── The projection ──
// 2:1 dimetric, the Forge of Empires shape: a cell is a diamond twice as wide
// as it is tall. Walking +x moves down-RIGHT on screen, +y moves down-LEFT.
//
//     screenX = (x − y) · tileW/2 + originX
//     screenY = (x + y) · tileH/2
//
// [gridToScreen] takes grid CORNERS, not cell centres: (0,0) is the north
// corner of the first cell, (1,1) its south corner. That is what makes a
// building's footprint the diamond between its own two corners, with no
// half-cell arithmetic at the call site.
//
// ── Why 2:1 and not a real 45° rotation ──
// A true rotation would make cells squares standing on a point, and every
// building's art would need to be drawn at 1:1 — taller than it is wide, which
// is the one proportion no isometric tile set uses. 2:1 is the ratio the whole
// genre draws for, so it is the ratio the art can be ordered in.

/// One cell's width on screen. The art contract hangs off this: a building's
/// base is exactly `gridW × kIsoTileW` pixels wide.
const double kIsoTileW = 64;

/// One cell's height — half the width, which is what makes the diamond read as
/// ground rather than as a floor tile seen from above.
const double kIsoTileH = kIsoTileW / 2;

/// The closest the map may be zoomed (user 2026-08-09: "Ich will nicht ganz so
/// nahe heranzoomen können wie aktuell", then a screenshot: "das soll der
/// maximal zoom in sein").
///
/// 0.8, measured off that screenshot rather than argued from the art: a road
/// cell came out about 50 px on a 432 px phone, and a cell is [kIsoTileW] = 64
/// px at scale 1.
///
/// It was 4.0 first, on the reasoning that 4 is where the sprites are drawn at
/// their own resolution (everything renders at SCALE = 4 in tool/blender). That
/// is a true fact about the ART and the wrong answer for the GAME: what decides
/// how close you may get is how much settlement has to stay on screen at once,
/// and five times too close is still five times too close even when every pixel
/// of it is real. Down here the art is simply downsampled, which is the safe
/// direction.
const double kMaxMapZoom = 0.8;

/// The map's view transform: [scale] about the origin, then a screen-space
/// shift of ([tx], [ty]).
///
/// ── The z axis is NOT decoration (user 2026-08-09) ──
/// This used to be `Matrix4.diagonal3Values(scale, scale, 1)`, leaving z at 1
/// because the map is flat and z cannot matter. It matters: [Matrix4
/// .getMaxScaleOnAxis] returns the LARGEST of the three axes, and this map's
/// scale is always well under 1 — 0.18 fills a phone. So every reader of that
/// matrix was told the zoom was 1.0 when it was 0.18, and two things broke at
/// once:
///
///   * InteractiveViewer clamped a pinch against a scale five times too big, so
///     you could zoom out until the map was a stamp in the corner ("ich kann
///     viel zu weit hinauszoomen. Es dürfte niemals der Rand sichtbar sein");
///   * and focusing a building rebuilt the transform at that phantom 1.0, which
///     is why picking one up zoomed in ("wenn ich ein gebäude anwähle zum
///     schieben, zoomt es hinein").
///
/// A uniform scale reports itself, whatever it is.
Matrix4 mapTransform(double scale, double tx, double ty) =>
    Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);

/// The furthest the map may be zoomed OUT in a [viewport]: the scale at which
/// the map already covers it (user 2026-08-09: "Es darf niemals aus dem
/// Spielfeld hinausgezoomt/gescrollt werden. Das Spielfeld ist die Grenze").
///
/// The LARGER of the two ratios, and that is the whole rule. The smaller one
/// covers the tighter axis and leaves the other short, which is a viewport with
/// the void down one side — and it is the easy mistake, because either ratio
/// "fits the map to the screen" in the loose sense.
double minMapScale(Size viewport) => math.max(
  viewport.width / isoCanvasSize.width,
  viewport.height / isoCanvasSize.height,
);

/// The nearest transform to [m] that keeps the map over the whole [viewport].
///
/// The rule in one function, so it is a thing that can be TESTED rather than a
/// promise spread across a gesture handler, two camera moves and an edge
/// scroll. Whatever comes in — a pinch past the limit, a camera move computed
/// from a stale scale, a matrix from nowhere — what comes out shows map on
/// every pixel: "Es dürfte niemals der Rand sichtbar sein" (user 2026-08-09).
///
/// A clamped ZOOM is re-centred on the viewport's middle. Scaling about the
/// origin instead would drag the map sideways every time a pinch went one notch
/// too far, which reads as the map fighting you.
Matrix4 clampMapTransform(Matrix4 m, Size viewport) {
  final lo = minMapScale(viewport);
  final scale = m.getMaxScaleOnAxis();
  final want = scale.clamp(lo, math.max(lo, kMaxMapZoom)).toDouble();
  final t = m.getTranslation();
  var tx = t.x, ty = t.y;
  if (want != scale && scale > 0) {
    final k = want / scale;
    tx = viewport.width / 2 - (viewport.width / 2 - tx) * k;
    ty = viewport.height / 2 - (viewport.height / 2 - ty) * k;
  }
  // Never a gap: the map's near edge may not come inside the viewport, and its
  // far edge may not come short of it.
  tx = tx
      .clamp(math.min(0.0, viewport.width - isoCanvasSize.width * want), 0.0)
      .toDouble();
  ty = ty
      .clamp(math.min(0.0, viewport.height - isoCanvasSize.height * want), 0.0)
      .toDouble();
  return mapTransform(want, tx, ty);
}

/// How far right the whole map has to be pushed so nothing lands at a negative
/// x: the westernmost point is the grid's south-west corner, at (0, rows).
double get isoOriginX => kGridRows * kIsoTileW / 2;

/// The screen box the whole diamond needs.
Size get isoCanvasSize => Size(
  (kGridCols + kGridRows) * kIsoTileW / 2,
  (kGridCols + kGridRows) * kIsoTileH / 2,
);

/// Grid CORNER (gx, gy) → its point on screen.
Offset gridToScreen(double gx, double gy) => Offset(
  (gx - gy) * kIsoTileW / 2 + isoOriginX,
  (gx + gy) * kIsoTileH / 2,
);

/// Screen point → the CELL under it, clamped to the map.
///
/// The inverse of [gridToScreen], floored. Returns a cell even for a point
/// outside the diamond (clamped to the nearest edge) — a tap on the void beside
/// the map is a tap on the map's edge, not an error the caller has to handle.
(int, int) screenToGrid(Offset p) {
  final a = (p.dx - isoOriginX) / kIsoTileW; // (gx − gy) / 2
  final b = p.dy / kIsoTileH; // (gx + gy) / 2
  final gx = (b + a).floor();
  final gy = (b - a).floor();
  return (gx.clamp(0, kGridCols - 1), gy.clamp(0, kGridRows - 1));
}

/// True when [p] is inside the map's diamond — what a tap has to pass before
/// [screenToGrid]'s clamping turns it into a real cell.
bool isoContains(Offset p) {
  final a = (p.dx - isoOriginX) / kIsoTileW;
  final b = p.dy / kIsoTileH;
  final gx = b + a;
  final gy = b - a;
  return gx >= 0 && gy >= 0 && gx <= kGridCols && gy <= kGridRows;
}

/// The diamond a footprint covers, as a path — the ghost preview, the selection
/// outline and a build plot's border all draw this instead of a rectangle.
Path footprintPath(int x, int y, int w, int h) {
  final north = gridToScreen(x.toDouble(), y.toDouble());
  final east = gridToScreen((x + w).toDouble(), y.toDouble());
  final south = gridToScreen((x + w).toDouble(), (y + h).toDouble());
  final west = gridToScreen(x.toDouble(), (y + h).toDouble());
  return Path()
    ..moveTo(north.dx, north.dy)
    ..lineTo(east.dx, east.dy)
    ..lineTo(south.dx, south.dy)
    ..lineTo(west.dx, west.dy)
    ..close();
}

/// The point of the footprint nearest the viewer — its south corner.
///
/// NOT the middle of [isoBounds]: for a footprint that is not square the two
/// differ, because a w×h area projects to a PARALLELOGRAM whose near corner
/// sits off to one side. Anchoring art "bottom-centre" here is exactly the bug
/// that put the placement outline a tile off (user 2026-08-01: "Dieser
/// entspricht aber nicht den Kacheln").
Offset spriteAnchor(int x, int y, int w, int h) =>
    gridToScreen((x + w).toDouble(), (y + h).toDouble());

/// The screen box a footprint occupies: the bounding rectangle of its four
/// corners. This is where a building's tile and its art go.
///
/// Always 2:1 — (w + h) tiles wide and half that tall — whatever the footprint's
/// own proportions are.
Rect isoBounds(int x, int y, int w, int h) {
  final north = gridToScreen(x.toDouble(), y.toDouble());
  final east = gridToScreen((x + w).toDouble(), y.toDouble());
  final south = gridToScreen((x + w).toDouble(), (y + h).toDouble());
  final west = gridToScreen(x.toDouble(), (y + h).toDouble());
  return Rect.fromLTRB(west.dx, north.dy, east.dx, south.dy);
}

/// The footprint's outline in the coordinates of its own [isoBounds] — what a
/// painter inside that box draws.
///
/// A w×h area is a RHOMBUS only when w == h; otherwise it is a parallelogram,
/// and a diamond drawn in its place covers the wrong tiles.
Path footprintPathLocal(int w, int h) {
  final a = kIsoTileW / 2;
  final b = kIsoTileH / 2;
  // Local corners, derived from the bounds: west sits at the left edge, north
  // at the top, east at the right, south at the bottom.
  return Path()
    ..moveTo(h * a, 0) // north
    ..lineTo((h + w) * a, w * b) // east
    ..lineTo(w * a, (w + h) * b) // south
    ..lineTo(0, h * b) // west
    ..close();
}

/// The seams BETWEEN the cells of a footprint, in the coordinates of its own
/// [isoBounds] — so a highlighted 2×2 reads as four tiles rather than as one
/// wash the size of four.
///
/// Each entry is a line from one edge of the footprint to the other.
List<(Offset, Offset)> footprintSeams(int w, int h) {
  final a = kIsoTileW / 2;
  final b = kIsoTileH / 2;
  Offset corner(int gx, int gy) =>
      Offset((h + gx - gy) * a, (gx + gy) * b);
  return [
    for (var i = 1; i < w; i++) (corner(i, 0), corner(i, h)),
    for (var j = 1; j < h; j++) (corner(0, j), corner(w, j)),
  ];
}

/// The width a building's art is drawn at: the full width of [isoBounds].
double spriteWidth(int w, int h) => (w + h) * kIsoTileW / 2;

/// A footprint's box in ITS OWN coordinates — origin at (0, 0).
///
/// [isoBounds] is in MAP space and carries [isoOriginX] with it, which is right
/// for placing a tile on the map and wrong for anything drawn INSIDE that tile.
/// Mixing the two shifted every sprite half a map to the right and left taps
/// landing on ground the building had never stood on (user 2026-08-01:
/// "gebäude und strassen sind verschoben. Gebäude können nicht mehr angewählt
/// werden").
Rect isoLocalBounds(int w, int h) =>
    Rect.fromLTWH(0, 0, spriteWidth(w, h), spriteWidth(w, h) / 2);

/// Where to draw a building's PICTURE so that its BASE lands on [bounds].
///
/// The image is placed by its base, not by its own edges (user 2026-08-01: "So
/// ist das Gebäude zu weit hinten"). Generated art comes back square with the
/// building somewhere inside it and air all round, so matching the IMAGE to the
/// tiles puts the BUILDING wherever the generator happened to leave it.
///
///  • [baseWidth] — how much of the image's width the ground base spans.
///  • [anchorX] — where the base's bottom point sits across the image.
///  • [lift] — how far that point sits ABOVE the image's bottom edge, in
///    fractions of the image's WIDTH.
///
/// Measured in widths rather than heights on purpose: the art is drawn
/// width-first (natural height, overflowing upward), so the height is not known
/// until the picture has loaded. For the square images a generator returns the
/// two are the same number anyway.
///
/// The defaults describe art drawn exactly to the contract — base full width,
/// touching the bottom edge — and then this returns `bounds`' own width and
/// foot, unchanged.
({double left, double width, double bottom}) artPlacement(
  Rect bounds, {
  double baseWidth = 1.0,
  double anchorX = 0.5,
  double lift = 0.0,
}) {
  final w = bounds.width / (baseWidth <= 0 ? 1.0 : baseWidth);
  return (
    left: bounds.center.dx - w * anchorX,
    width: w,
    bottom: bounds.bottom + w * lift,
  );
}

/// The screen angle a grid direction runs at, in radians, for [Transform.rotate]
/// (0 points right, angles grow clockwise because screen y grows downward).
///
/// The placement arrows need this and could not guess it: +x runs down-RIGHT
/// and +y down-LEFT on a 2:1 diamond, so the four directions sit at ±26.6° and
/// its supplements — nowhere near the up/down/left/right a square grid would
/// have drawn.
double isoScreenAngle(int dx, int dy) {
  final a = math.atan2(kIsoTileH, kIsoTileW); // ≈ 26.57°
  return switch ((dx, dy)) {
    (1, 0) => a,
    (-1, 0) => math.pi + a,
    (0, 1) => math.pi - a,
    _ => -a,
  };
}

/// The middle of the footprint edge that FACES (dx, dy) — where an arrow for
/// that direction belongs.
///
/// Not a corner and not the centre: on a diamond the "right-hand side" of a
/// footprint is an edge running north-east to south-east, and its midpoint is
/// the only point on it that stays put as the footprint changes shape.
Offset isoEdgeMidpoint(int x, int y, int w, int h, int dx, int dy) =>
    switch ((dx, dy)) {
      (1, 0) => gridToScreen((x + w).toDouble(), y + h / 2),
      (-1, 0) => gridToScreen(x.toDouble(), y + h / 2),
      (0, 1) => gridToScreen(x + w / 2, (y + h).toDouble()),
      _ => gridToScreen(x + w / 2, y.toDouble()),
    };

/// The box a building's PICTURE occupies in map space: its tile plus the height
/// the art rises above it.
///
/// [isoBounds] is only the GROUND. What hides a building being placed is a roof
/// leaning over the tiles in front of it, and what a finger reaches for is the
/// wall rather than the grass — both are questions about the picture, and both
/// got the wrong answer from the footprint alone.
///
/// The height is taken as the art's own WIDTH: generated art comes back square,
/// and the map never learns the real height because the picture is drawn
/// width-first and allowed to overflow upward (see [artPlacement]).
Rect isoArtBounds(
  int x,
  int y,
  int w,
  int h, {
  double baseWidth = 1.0,
  double anchorX = 0.5,
  double lift = 0.0,
}) {
  final iso = isoBounds(x, y, w, h);
  final art = artPlacement(
    isoLocalBounds(w, h),
    baseWidth: baseWidth,
    anchorX: anchorX,
    lift: lift,
  );
  final left = iso.left + art.left;
  final foot = iso.top + art.bottom;
  // Union with the tile: art narrower than its footprint must not shrink the
  // ground the building is standing on out of the box.
  return Rect.fromLTRB(
    math.min(iso.left, left),
    math.min(iso.top, foot - art.width),
    math.max(iso.right, left + art.width),
    math.max(iso.bottom, foot),
  );
}

/// PAINTER'S ORDER. Sorts back to front, so a building nearer the viewer is
/// drawn over the one behind it.
///
/// Without this the map is drawn in list order and a tower behind a hut is
/// painted on top of it — the single most obvious way an isometric map looks
/// broken.
///
/// The key is the footprint's LAST cell, not its first (user 2026-08-01, with
/// the roads). A 2×2 building starting at (4,4) reaches to (5,5), and a
/// neighbour at (5,4) is beside it, not behind it — keyed on the north corner
/// the big building would sort as though it stood a tile and a half further
/// back than it does, and its neighbour would paint over its wall.
///
/// Ties go to the one further east, so the order is total and therefore stable:
/// an unstable sort makes two neighbours swap between frames and flicker.
int isoDrawOrder(int ax, int ay, int aw, int ah, int bx, int by, int bw,
    int bh) {
  final byDepth = (ax + aw + ay + ah).compareTo(bx + bw + by + bh);
  return byDepth != 0 ? byDepth : ax.compareTo(bx);
}
