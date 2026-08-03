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

  // ── Der Rand muss auf den Kacheln liegen (user 2026-08-01) ──
  // "jetzt habe ich einen grünen Rand um das Gebäude. Dieser entspricht aber
  //  nicht den Kacheln."
  //
  // Two bugs made that outline miss: the box was centred on the footprint's
  // SOUTH corner (only correct for a square footprint), and the path was drawn
  // in map coordinates inside a local box. Both are geometry, so both are
  // pinned here.
  group('a footprint sits exactly on its cells', () {
    test('the bounds hold all four corners, for any shape', () {
      for (final (w, h) in [(1, 1), (2, 2), (2, 1), (1, 3), (3, 2)]) {
        final b = isoBounds(4, 6, w, h);
        for (final c in [
          gridToScreen(4, 6),
          gridToScreen((4 + w).toDouble(), 6),
          gridToScreen((4 + w).toDouble(), (6 + h).toDouble()),
          gridToScreen(4, (6 + h).toDouble()),
        ]) {
          expect(b.contains(c) || b.inflate(0.001).contains(c), isTrue,
              reason: '$w x $h loses corner $c');
        }
        expect(b.width, spriteWidth(w, h), reason: '$w x $h width');
        expect(b.width / b.height, 2.0, reason: '$w x $h is not 2:1');
      }
    });

    test('the south corner is NOT the middle — except when square', () {
      // The assumption that broke it. A 2x1 area is a parallelogram, and its
      // near corner sits off to one side.
      final square = isoBounds(0, 0, 2, 2);
      expect(spriteAnchor(0, 0, 2, 2).dx, square.center.dx);
      final oblong = isoBounds(0, 0, 2, 1);
      expect(spriteAnchor(0, 0, 2, 1).dx, isNot(oblong.center.dx));
    });

    test('the local outline matches the real corners, shifted', () {
      for (final (w, h) in [(1, 1), (2, 1), (3, 2)]) {
        final b = isoBounds(5, 2, w, h);
        final local = footprintPathLocal(w, h).getBounds();
        expect(local.width, closeTo(b.width, 0.001), reason: '$w x $h');
        expect(local.height, closeTo(b.height, 0.001), reason: '$w x $h');
        expect(local.left, closeTo(0, 0.001),
            reason: 'the local path must start at the box origin');
        expect(local.top, closeTo(0, 0.001));
      }
    });
  });

  // ── Markiert heisst: die Kacheln leuchten (user 2026-08-01) ──
  // "Wenn das gebäude markiert ist, will ich nur die gehighlighteten Kachel
  //  sehen"
  //
  // So the highlight has to show the CELLS, not an area the size of them — a
  // 2×2 that lights up as one wash says nothing about how much grid it eats.
  group('the footprint seams', () {
    test('a single cell has none', () {
      expect(footprintSeams(1, 1), isEmpty);
    });

    test('a w x h footprint has (w-1) + (h-1) of them', () {
      expect(footprintSeams(2, 2), hasLength(2));
      expect(footprintSeams(3, 2), hasLength(3));
      expect(footprintSeams(1, 4), hasLength(3));
    });

    test('every seam runs edge to edge, inside the bounds', () {
      for (final (w, h) in [(2, 2), (3, 2), (1, 3), (4, 4)]) {
        final bounds = footprintPathLocal(w, h).getBounds().inflate(0.001);
        for (final (from, to) in footprintSeams(w, h)) {
          expect(bounds.contains(from), isTrue, reason: '$w x $h from $from');
          expect(bounds.contains(to), isTrue, reason: '$w x $h to $to');
          expect(from, isNot(to));
        }
      }
    });

    test('a seam is parallel to the footprint edge it divides', () {
      // Both families run along a grid axis: half a tile across per half tile
      // down. A seam at any other angle would cut across the cells instead of
      // between them.
      for (final (from, to) in footprintSeams(3, 3)) {
        final dx = (to.dx - from.dx).abs();
        final dy = (to.dy - from.dy).abs();
        expect(dx / dy, closeTo(kIsoTileW / kIsoTileH, 0.0001));
      }
    });
  });
}
