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

/// Where a building's SPRITE hangs: the south corner of its footprint, i.e. the
/// point of the diamond nearest the viewer.
///
/// Art is anchored bottom-centre here and allowed to run upward as far as it
/// likes — a tower is tall, and nothing about its footprint says so.
Offset spriteAnchor(int x, int y, int w, int h) =>
    gridToScreen((x + w).toDouble(), (y + h).toDouble());

/// The width a building's art is drawn at: its base spans the full diamond.
double spriteWidth(int w, int h) => (w + h) * kIsoTileW / 2;

/// PAINTER'S ORDER. Sorts back to front, so a building nearer the viewer is
/// drawn over the one behind it.
///
/// Without this the map is drawn in list order and a tower behind a hut is
/// painted on top of it — the single most obvious way an isometric map looks
/// broken. The key is the footprint's FAR corner (x + y), because that is what
/// decides which of two overlapping buildings is in front; ties go to the one
/// further east so the order is total and therefore stable.
int isoDrawOrder(int ax, int ay, int bx, int by) {
  final byDepth = (ax + ay).compareTo(bx + by);
  return byDepth != 0 ? byDepth : ax.compareTo(bx);
}
