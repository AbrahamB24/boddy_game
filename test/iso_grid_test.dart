import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart'
    show kGridCols, kGridRows;
import 'package:boddygame/features/settlement/data/iso_grid.dart';

// ── Das Raster um 45° gedreht (user 2026-08-01) ─────────────
// "Ich will das Raster aber wie bei forge of empires nicht horizontal und
//  vertikal, sondern alles um 45° gedreht."
//
// The grid itself does not change — this is a projection. Which means the one
// property everything else rests on is that the projection and its inverse
// agree: tap a building, get that building. A map where a tap lands one cell
// off is unusable, and it fails silently at the edges first.
void main() {
  test('a cell is twice as wide as it is tall', () {
    expect(kIsoTileW / kIsoTileH, 2.0);
  });

  test('walking the grid walks the diamond', () {
    final origin = gridToScreen(0, 0);
    // +x goes down-RIGHT, +y goes down-LEFT — half a tile across, half down.
    final east = gridToScreen(1, 0);
    expect(east.dx - origin.dx, kIsoTileW / 2);
    expect(east.dy - origin.dy, kIsoTileH / 2);
    final west = gridToScreen(0, 1);
    expect(west.dx - origin.dx, -kIsoTileW / 2);
    expect(west.dy - origin.dy, kIsoTileH / 2);
  });

  test('nothing lands at a negative x', () {
    // The westernmost point of the map is its south-west corner; the origin
    // offset exists to push exactly that onto the canvas.
    expect(gridToScreen(0, kGridRows.toDouble()).dx, 0);
    expect(gridToScreen(kGridCols.toDouble(), 0).dx, isoCanvasSize.width);
  });

  test('screen → grid → screen comes back to the same cell', () {
    // Every cell, not a sample: an off-by-one that only shows up in one corner
    // of a 60x40 map is exactly the bug this guards.
    for (var x = 0; x < kGridCols; x++) {
      for (var y = 0; y < kGridRows; y++) {
        // The centre of a cell is the midpoint of its diagonal.
        final centre = gridToScreen(x + 0.5, y + 0.5);
        expect(screenToGrid(centre), (x, y), reason: 'cell ($x, $y)');
      }
    }
  });

  test('a point outside the diamond is not on the map', () {
    expect(isoContains(gridToScreen(1, 1)), isTrue);
    // Straight above the north corner: inside the bounding box, off the map.
    expect(isoContains(const Offset(0, 0)), isFalse);
    expect(isoContains(Offset(isoCanvasSize.width, 0)), isFalse);
  });

  test('a footprint is the diamond between its own corners', () {
    final path = footprintPath(2, 3, 2, 2);
    // Its bounds are the same box the four corners span.
    final north = gridToScreen(2, 3);
    final south = gridToScreen(4, 5);
    final b = path.getBounds();
    expect(b.top, north.dy);
    expect(b.bottom, south.dy);
    expect(b.width, (2 + 2) * kIsoTileW / 2);
  });

  test('the sprite hangs at the corner nearest the viewer', () {
    // Bottom-centre anchoring: the art grows upward from here, however tall the
    // building is.
    expect(spriteAnchor(0, 0, 1, 1), gridToScreen(1, 1));
    expect(spriteWidth(2, 2), 2 * kIsoTileW);
    expect(spriteWidth(1, 1), kIsoTileW);
  });

  group('painter order', () {
    test('nearer the viewer is drawn later', () {
      // (2,2) is in FRONT of (0,0): bigger x+y, so it sorts after it.
      expect(isoDrawOrder(0, 0, 2, 2), lessThan(0));
      expect(isoDrawOrder(2, 2, 0, 0), greaterThan(0));
    });

    test('equal depth is broken consistently, never left equal', () {
      // A total order matters: an unstable sort on ties makes two neighbours
      // swap places between frames and flicker.
      expect(isoDrawOrder(3, 1, 1, 3), greaterThan(0));
      expect(isoDrawOrder(1, 3, 3, 1), lessThan(0));
      expect(isoDrawOrder(2, 2, 2, 2), 0);
    });

    test('sorting a row of buildings puts the front one last', () {
      final cells = [(5, 5), (0, 0), (2, 1), (1, 2)];
      cells.sort((a, b) => isoDrawOrder(a.$1, a.$2, b.$1, b.$2));
      expect(cells.first, (0, 0));
      expect(cells.last, (5, 5));
    });
  });
}
