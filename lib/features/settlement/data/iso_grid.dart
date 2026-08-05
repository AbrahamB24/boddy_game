import 'dart:ui';

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

// ── TURNING THE MAP (user 2026-08-04) ───────────────────────
// Same principle as the isometric change itself, one level further in: the
// GRID DOES NOT TURN. A building stays at gridX/gridY covering gridW × gridH
// for as long as it exists; what turns is the way those numbers are projected.
// Nothing is saved, nothing is migrated, and a rotation is not a game state —
// it is a camera.
//
// The whole rotation lives in [isoTurn], which every corner passes through on
// its way to the screen. That is why the functions below did not have to
// change: they were already written in terms of grid CORNERS, and a corner that
// has been turned projects exactly like a corner that has not.
//
// The two things that DO have to know are the two that cannot be expressed as a
// corner — the map's own dimensions (60 × 40 becomes 40 × 60 on an odd quarter)
// and the painter's depth order, which is about which footprint is nearer the
// viewer and therefore about the turned position.

/// Quarter turns clockwise, 0..3. A camera, not game state: never persisted.
int isoRotation = 0;

/// The grid as SEEN. Swapped on an odd quarter turn, because a 60 × 40 map
/// viewed from the side is 40 × 60.
int get isoViewCols => isoRotation.isEven ? kGridCols : kGridRows;
int get isoViewRows => isoRotation.isEven ? kGridRows : kGridCols;

/// A grid CORNER moved into view space. Corners, not cells: the whole
/// projection is written in corners, so the turn has to be too — turning cell
/// centres and then deriving corners is how a footprint ends up half a tile off
/// its own ground.
(double, double) isoTurn(double gx, double gy) => switch (isoRotation) {
  1 => (kGridRows - gy, gx),
  2 => (kGridCols - gx, kGridRows - gy),
  3 => (gy, kGridCols - gx),
  _ => (gx, gy),
};

/// A footprint's origin and extents in view space. On an odd quarter turn a
/// 3 × 4 building presents as 4 × 3 — ON SCREEN. In the data it is 3 × 4 for
/// ever, and mixing those two up is the single most likely way this breaks.
(int, int, int, int) isoViewRect(int x, int y, int w, int h) =>
    switch (isoRotation) {
      1 => (kGridRows - y - h, x, h, w),
      2 => (kGridCols - x - w, kGridRows - y - h, w, h),
      3 => (y, kGridCols - x - w, h, w),
      _ => (x, y, w, h),
    };

/// A footprint's extents as seen — the swap alone, for the local-space helpers.
(int, int) isoViewWH(int w, int h) =>
    isoRotation.isEven ? (w, h) : (h, w);

/// How far right the whole map has to be pushed so nothing lands at a negative
/// x: the westernmost point is the grid's south-west corner, at (0, rows).
double get isoOriginX => isoViewRows * kIsoTileW / 2;

/// The screen box the whole diamond needs.
///
/// Unchanged by rotation, and that is not luck: the diamond is
/// (cols + rows) tiles across, and cols + rows survives a quarter turn.
Size get isoCanvasSize => Size(
  (isoViewCols + isoViewRows) * kIsoTileW / 2,
  (isoViewCols + isoViewRows) * kIsoTileH / 2,
);

/// Grid CORNER (gx, gy) → its point on screen, through the current turn.
Offset gridToScreen(double gx, double gy) {
  final (vx, vy) = isoTurn(gx, gy);
  return Offset(
    (vx - vy) * kIsoTileW / 2 + isoOriginX,
    (vx + vy) * kIsoTileH / 2,
  );
}

/// Screen point → the CELL under it, clamped to the map.
///
/// The inverse of [gridToScreen], floored. Returns a cell even for a point
/// outside the diamond (clamped to the nearest edge) — a tap on the void beside
/// the map is a tap on the map's edge, not an error the caller has to handle.
(int, int) screenToGrid(Offset p) {
  final a = (p.dx - isoOriginX) / kIsoTileW; // (vx − vy) / 2
  final b = p.dy / kIsoTileH; // (vx + vy) / 2
  final vx = (b + a).floor();
  final vy = (b - a).floor();
  // Back out of the turn, in CELLS. The corner map turned inside out: for a
  // quarter clockwise, view cell (vx, vy) is grid cell (vy, rows − 1 − vx).
  final (gx, gy) = switch (isoRotation) {
    1 => (vy, kGridRows - 1 - vx),
    2 => (kGridCols - 1 - vx, kGridRows - 1 - vy),
    3 => (kGridCols - 1 - vy, vx),
    _ => (vx, vy),
  };
  return (gx.clamp(0, kGridCols - 1), gy.clamp(0, kGridRows - 1));
}

/// True when [p] is inside the map's diamond — what a tap has to pass before
/// [screenToGrid]'s clamping turns it into a real cell.
bool isoContains(Offset p) {
  final a = (p.dx - isoOriginX) / kIsoTileW;
  final b = p.dy / kIsoTileH;
  final vx = b + a;
  final vy = b - a;
  // Tested in VIEW space, against the turned dimensions — the diamond on
  // screen is the one the tap has to be inside of.
  return vx >= 0 && vy >= 0 && vx <= isoViewCols && vy <= isoViewRows;
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
  // From the MIN and MAX of the four projected corners, not from "west is the
  // left one". Which corner lands where depends on the turn, and naming them
  // was only ever true at rotation 0.
  final pts = [
    gridToScreen(x.toDouble(), y.toDouble()),
    gridToScreen((x + w).toDouble(), y.toDouble()),
    gridToScreen((x + w).toDouble(), (y + h).toDouble()),
    gridToScreen(x.toDouble(), (y + h).toDouble()),
  ];
  var l = pts.first.dx, r = pts.first.dx;
  var t = pts.first.dy, b = pts.first.dy;
  for (final p in pts) {
    if (p.dx < l) l = p.dx;
    if (p.dx > r) r = p.dx;
    if (p.dy < t) t = p.dy;
    if (p.dy > b) b = p.dy;
  }
  return Rect.fromLTRB(l, t, r, b);
}

/// The footprint's outline in the coordinates of its own [isoBounds] — what a
/// painter inside that box draws.
///
/// A w×h area is a RHOMBUS only when w == h; otherwise it is a parallelogram,
/// and a diamond drawn in its place covers the wrong tiles.
Path footprintPathLocal(int gw, int gh) {
  // The SWAP happens here rather than at the call sites. Every caller passes
  // def.gridW/gridH — the building's real footprint — and none of them should
  // have to remember that the picture of it turns.
  final (w, h) = isoViewWH(gw, gh);
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
List<(Offset, Offset)> footprintSeams(int gw, int gh) {
  final (w, h) = isoViewWH(gw, gh);
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
/// Unaffected by rotation — (w + h) is the same after a quarter turn — but
/// written through the swap anyway so it cannot drift from its siblings.
double spriteWidth(int gw, int gh) {
  final (w, h) = isoViewWH(gw, gh);
  return (w + h) * kIsoTileW / 2;
}

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
  // In VIEW space. Depth is about which footprint is nearer the VIEWER, so it
  // is the one thing here that genuinely has to know about the turn — leave it
  // in grid space and turning the map paints the far side of the village over
  // the near side.
  final (vax, vay, vaw, vah) = isoViewRect(ax, ay, aw, ah);
  final (vbx, vby, vbw, vbh) = isoViewRect(bx, by, bw, bh);
  final byDepth = (vax + vaw + vay + vah).compareTo(vbx + vbw + vby + vbh);
  return byDepth != 0 ? byDepth : vax.compareTo(vbx);
}
