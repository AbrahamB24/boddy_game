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
    int order((int, int, int, int) a, (int, int, int, int) b) =>
        isoDrawOrder(a.$1, a.$2, a.$3, a.$4, b.$1, b.$2, b.$3, b.$4);

    test('nearer the viewer is drawn later', () {
      // (2,2) is in FRONT of (0,0): deeper, so it sorts after it.
      expect(order((0, 0, 1, 1), (2, 2, 1, 1)), lessThan(0));
      expect(order((2, 2, 1, 1), (0, 0, 1, 1)), greaterThan(0));
    });

    test('a big footprint is judged by where it REACHES', () {
      // The bug the roads found: a 2x2 at (4,4) reaches to (5,5), so a 1x1
      // neighbour at (5,4) is BESIDE it, not behind it. Keyed on the north
      // corner the big building sorts as though it stood further back, and the
      // neighbour paints over its wall.
      expect(order((4, 4, 2, 2), (5, 4, 1, 1)), greaterThan(0),
          reason: 'the 2x2 reaches deeper and must draw later');
      expect(order((4, 4, 2, 2), (6, 6, 1, 1)), lessThan(0),
          reason: '…but a tile genuinely in front still wins');
    });

    test('equal depth is broken consistently, never left equal', () {
      // A total order matters: an unstable sort on ties makes two neighbours
      // swap places between frames and flicker.
      expect(order((3, 1, 1, 1), (1, 3, 1, 1)), greaterThan(0));
      expect(order((1, 3, 1, 1), (3, 1, 1, 1)), lessThan(0));
      expect(order((2, 2, 1, 1), (2, 2, 1, 1)), 0);
    });

    test('sorting a row of buildings puts the front one last', () {
      final cells = [(5, 5, 1, 1), (0, 0, 1, 1), (2, 1, 1, 1), (1, 2, 1, 1)];
      cells.sort(order);
      expect(cells.first, (0, 0, 1, 1));
      expect(cells.last, (5, 5, 1, 1));
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

  // ── Das Bild sitzt auf seiner Grundfläche (user 2026-08-01) ──
  // "Ich habe das Bild jetzt als Quadrat, aber die Grundfläche ist natürlich
  //  kleiner und weiter vorne … So ist das Gebäude zu weit hinten"
  //
  // The map used to fit the IMAGE to the tiles. Generated art is square with the
  // building somewhere inside it, so that put the building wherever the
  // generator left it. artPlacement matches the BASE instead.
  group('art placement', () {
    final bounds = isoBounds(3, 4, 2, 2);

    test('art drawn to the contract is placed exactly on the footprint', () {
      // base full width, touching the bottom edge — the defaults.
      final a = artPlacement(bounds);
      expect(a.width, bounds.width);
      expect(a.left, bounds.left);
      expect(a.bottom, bounds.bottom);
    });

    test('a base that fills half the picture doubles the picture', () {
      final a = artPlacement(bounds, baseWidth: 0.5);
      expect(a.width, bounds.width * 2);
      // …and stays centred on the footprint, so the extra air is shared.
      expect(a.left + a.width / 2, bounds.center.dx);
    });

    test('the lift pushes the picture DOWN, in fractions of its width', () {
      // The base sits above the image's bottom edge, so the image has to hang
      // lower for that base to land on the ground.
      final a = artPlacement(bounds, lift: 0.1);
      expect(a.bottom, bounds.bottom + a.width * 0.1);
    });

    test('an off-centre base slides the picture across', () {
      final a = artPlacement(bounds, anchorX: 0.25);
      expect(a.left + a.width * 0.25, bounds.center.dx);
    });

    test('a nonsense base width does not divide by zero', () {
      // Dev Mode clamps to 0.05, but a hand-written row can say anything.
      expect(artPlacement(bounds, baseWidth: 0).width, bounds.width);
      expect(artPlacement(bounds, baseWidth: -1).width, bounds.width);
    });
  });

  // ── Kartenraum ist nicht Kachelraum (user 2026-08-01) ──────
  // "gebäude und strassen sind verschoben. Gebäude können nicht mehr angewählt
  //  werden"
  //
  // isoBounds carries the map's origin; anything drawn INSIDE a tile must not.
  // Mixing them shifted every sprite a map-width sideways, so a tap landed on
  // ground the building had never stood on — the projection was right and the
  // picture was somewhere else entirely.
  group('local vs map coordinates', () {
    test('a local box starts at the origin, whatever the footprint', () {
      for (final (w, h) in [(1, 1), (2, 2), (3, 2), (5, 5)]) {
        final local = isoLocalBounds(w, h);
        expect(local.left, 0, reason: '$w x $h');
        expect(local.top, 0, reason: '$w x $h');
      }
    });

    test('it is the same SIZE as the map box it stands in', () {
      for (final (w, h) in [(1, 1), (2, 2), (3, 2)]) {
        final map = isoBounds(7, 9, w, h);
        final local = isoLocalBounds(w, h);
        expect(local.width, map.width, reason: '$w x $h width');
        expect(local.height, map.height, reason: '$w x $h height');
      }
    });

    test('the map box is NOT at the origin — which is the trap', () {
      // If this ever became 0 the bug would look fixed while the two boxes
      // silently meant the same thing again.
      expect(isoBounds(0, 0, 2, 2).left, isNot(0));
      expect(isoOriginX, greaterThan(0));
    });

    test('the local outline fits the local box exactly', () {
      for (final (w, h) in [(1, 1), (3, 2), (2, 4)]) {
        final local = isoLocalBounds(w, h);
        final path = footprintPathLocal(w, h).getBounds();
        expect(path.left, closeTo(local.left, 0.001));
        expect(path.top, closeTo(local.top, 0.001));
        expect(path.width, closeTo(local.width, 0.001));
        expect(path.height, closeTo(local.height, 0.001));
      }
    });
  });
}
