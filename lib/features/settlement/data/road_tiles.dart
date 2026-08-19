import 'building_definitions.dart' show kGridCols, kGridRows;

// ── Roads pick their own shape (user 2026-08-09) ─────────────
// "mache bitte jetzt die Strassen, welche auch Kreuzungen und Kurven beinhalten
//  können. Diese sollen sich automatisch richtig anpassen."
//
// A road cell has nothing of its own to say. What it looks like is entirely a
// question about its FOUR NEIGHBOURS — is there a road that way, or not — and
// four yes/no answers make sixteen shapes: a lone patch, four dead ends, two
// straights, four curves, four tees and a crossroads.
//
// So nothing is authored per junction and nothing can be laid the wrong way
// round. The player paints cells; the mask falls out of which cells exist, and
// the mask IS the file name. tool/blender/roads.py renders the same sixteen
// from the same bit order — the two files have to agree, and this comment is
// the only place that says so.

/// A road one cell further along +x — DOWN-RIGHT on screen (see iso_grid.dart).
const int kRoadPlusX = 1;

/// +y — down-LEFT. The axis that catches people out: it is not "south".
const int kRoadPlusY = 2;

/// −x — up-left.
const int kRoadMinusX = 4;

/// −y — up-right.
const int kRoadMinusY = 8;

/// The four directions, paired with the bit each one sets.
const List<(int, int, int)> kRoadNeighbours = [
  (1, 0, kRoadPlusX),
  (0, 1, kRoadPlusY),
  (-1, 0, kRoadMinusX),
  (0, -1, kRoadMinusY),
];

/// How a set of road cells is keyed: one int per cell, row-major — the same
/// packing `buildableRegion` uses, so the two can be built in one pass over the
/// buildings if that ever matters.
int roadCellKey(int x, int y) => y * kGridCols + x;

/// Which of (x, y)'s four neighbours are roads, as a bitmask.
///
/// Off-map neighbours count as ABSENT, which is what makes a road at the edge
/// of the world end in a kerb instead of running into nothing.
int roadMask(Set<int> roadCells, int x, int y) {
  var mask = 0;
  for (final (dx, dy, bit) in kRoadNeighbours) {
    final nx = x + dx, ny = y + dy;
    if (nx < 0 || ny < 0 || nx >= kGridCols || ny >= kGridRows) continue;
    if (roadCells.contains(roadCellKey(nx, ny))) mask |= bit;
  }
  return mask;
}

/// The picture for [mask]. Bundled, not an `image_url`: a building carries one
/// uploaded picture and a road needs sixteen, and roads are terrain rather than
/// authored content — no levels, no effects, no per-region variant.
String roadAsset(int mask) =>
    'assets/images/roads/road_${mask.toString().padLeft(2, '0')}.webp';
