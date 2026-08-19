import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/widgets.dart' show Matrix4, MatrixUtils;

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

    test('a base WIDER than the picture shrinks the building', () {
      // User 2026-08-01: "base with muss mehr als bis 1 gehen". Above 1 the
      // base overshoots the image, so the picture is drawn smaller than the
      // footprint — the opposite direction, same one number.
      final a = artPlacement(bounds, baseWidth: 2);
      expect(a.width, bounds.width / 2);
      expect(a.left + a.width / 2, bounds.center.dx, reason: 'still centred');
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

  // ── Wohin ein Pfeil zeigt (user 2026-08-09) ────────────────
  // "mache an jeder Kante ein Pfeil, welcher die Richtung angibt"
  //
  // The placement arrows are the one bit of UI that has to SPEAK the
  // projection: on a 2:1 diamond +x runs down-right and +y down-left, so the
  // four buttons sit at four oblique angles and beside four slanted edges. Get
  // either wrong and the arrow labelled "this way" moves the building somewhere
  // else — the exact class of bug that put the old placement outline a tile off.
  group('direction arrows', () {
    test('an arrow points the way its direction actually travels', () {
      for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        // Where one step in that direction really lands, on screen.
        final travelled = gridToScreen(10.0 + dx, 10.0 + dy) -
            gridToScreen(10, 10);
        final angle = isoScreenAngle(dx, dy);
        final pointed = Offset(math.cos(angle), math.sin(angle));
        // Same heading: the unit vectors agree to within a rounding error.
        final unit = travelled / travelled.distance;
        expect(pointed.dx, closeTo(unit.dx, 0.001), reason: '($dx,$dy) x');
        expect(pointed.dy, closeTo(unit.dy, 0.001), reason: '($dx,$dy) y');
      }
    });

    test('no two directions share an angle — a square grid would fail this', () {
      final angles = [
        for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)])
          isoScreenAngle(dx, dy),
      ];
      // Nothing horizontal or vertical: on this grid every direction is oblique.
      for (final a in angles) {
        expect(math.sin(a).abs(), greaterThan(0.1), reason: 'not horizontal');
        expect(math.cos(a).abs(), greaterThan(0.1), reason: 'not vertical');
      }
      expect(angles.map((a) => a.toStringAsFixed(3)).toSet(), hasLength(4));
    });

    test('each arrow sits on the edge that faces its direction', () {
      // A 3x2 footprint, where "the right-hand side" is a slanted edge rather
      // than a corner — the shape that makes a rectangle's midpoints wrong.
      final (x, y, w, h) = (4, 6, 3, 2);
      final box = isoBounds(x, y, w, h);
      for (final (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final mid = isoEdgeMidpoint(x, y, w, h, dx, dy);
        // On the outline, and on the outward half of it.
        expect(box.inflate(0.001).contains(mid), isTrue, reason: '($dx,$dy)');
        final outward = mid - box.center;
        final angle = isoScreenAngle(dx, dy);
        expect(
          outward.dx * math.cos(angle) + outward.dy * math.sin(angle),
          greaterThan(0),
          reason: '($dx,$dy) faces the wrong way',
        );
      }
    });

    test('opposite edges are opposite — the footprint stays centred', () {
      final (x, y, w, h) = (4, 6, 3, 2);
      final centre = isoBounds(x, y, w, h).center;
      for (final (dx, dy) in [(1, 0), (0, 1)]) {
        final a = isoEdgeMidpoint(x, y, w, h, dx, dy) - centre;
        final b = isoEdgeMidpoint(x, y, w, h, -dx, -dy) - centre;
        expect(a.dx, closeTo(-b.dx, 0.001));
        expect(a.dy, closeTo(-b.dy, 0.001));
      }
    });
  });

  // ── Was ein Gebäude wirklich verdeckt (user 2026-08-09) ────
  // "Wenn ich das Gebäude hinter ein anderes schiebe, dann wird dieses
  //  transparent, damit ich die Platzierung besser sehe"
  //
  // Deciding WHICH building to fade is an overlap test, and the footprint is
  // the wrong shape for it: what hides a building being placed is the roof
  // leaning over the tiles in front of it, which its own ground never touches.
  group('the box the picture occupies', () {
    test('it reaches ABOVE the tile, because the art does', () {
      final tile = isoBounds(3, 3, 2, 2);
      final art = isoArtBounds(3, 3, 2, 2);
      expect(art.top, lessThan(tile.top));
      expect(art.bottom, closeTo(tile.bottom, 0.001), reason: 'feet on the ground');
    });

    test('it never gives up ground the footprint owns', () {
      // Art drawn narrow (a tower on a wide plot) must not shrink the box below
      // the tiles the building is standing on.
      final tile = isoBounds(3, 3, 4, 4);
      final art = isoArtBounds(3, 3, 4, 4, baseWidth: 2.0);
      expect(art.left, lessThanOrEqualTo(tile.left + 0.001));
      expect(art.right, greaterThanOrEqualTo(tile.right - 0.001));
      expect(art.bottom, greaterThanOrEqualTo(tile.bottom - 0.001));
    });

    test('a lifted building carries its box down with it', () {
      final flat = isoArtBounds(3, 3, 2, 2);
      final lifted = isoArtBounds(3, 3, 2, 2, lift: 0.1);
      expect(lifted.bottom, greaterThan(flat.bottom));
    });

    test('a tall building covers the one behind it, ground apart or not', () {
      // The whole reason the fade test cannot use footprints: these two tiles
      // do not touch anywhere on screen, and the front one's picture still
      // reaches back over the rear one.
      final frontTile = isoBounds(3, 3, 2, 2);
      final backTile = isoBounds(0, 0, 2, 2);
      expect(frontTile.overlaps(backTile), isFalse, reason: 'the GROUND is clear');
      expect(
        isoArtBounds(3, 3, 2, 2).overlaps(isoArtBounds(0, 0, 2, 2)),
        isTrue,
        reason: 'the PICTURES are not',
      );
    });
  });

  // ── Das Spielfeld ist die Grenze (user 2026-08-09) ─────────
  // "Ich will nicht ganz so nahe heranzoomen können wie aktuell. Es darf
  //  niemals aus dem Spielfeld hinausgezoomt/gescrollt werden."
  //
  // Panning is bounded by the transform clamp, which needs no help once the
  // SCALE is bounded — but if the minimum scale is a hair too small the map no
  // longer covers the viewport and there is nothing left to clamp against. So
  // the covering property is what is pinned, not the formula.
  group('the map is the boundary', () {
    test('at the minimum scale the map covers the viewport, every shape', () {
      for (final v in const [
        Size(430, 932),   // a phone, portrait
        Size(932, 430),   // the same phone, turned
        Size(1600, 900),  // a desktop window
        Size(300, 300),   // square, and small
        Size(2400, 400),  // absurdly wide — the case one ratio gets wrong
      ]) {
        final s = minMapScale(v);
        expect(isoCanvasSize.width * s, greaterThanOrEqualTo(v.width - 0.001),
            reason: '$v leaves a gap across');
        expect(isoCanvasSize.height * s, greaterThanOrEqualTo(v.height - 0.001),
            reason: '$v leaves a gap down');
      }
    });

    test('and it is the SMALLEST scale that does — no wasted zoom', () {
      for (final v in const [Size(430, 932), Size(1600, 900)]) {
        final s = minMapScale(v) * 0.98;
        final coversW = isoCanvasSize.width * s >= v.width;
        final coversH = isoCanvasSize.height * s >= v.height;
        expect(coversW && coversH, isFalse,
            reason: '$v could zoom out further and still be covered');
      }
    });

    test('zooming IN stops where the player asked it to', () {
      // Measured off a screenshot the user labelled "das soll der maximal zoom
      // in sein": a 1x1 road cell about 50 px wide on a 432 px phone.
      expect(kIsoTileW * kMaxMapZoom, closeTo(51.2, 0.001));
      // And it must still be a range worth having — a max below the min would
      // mean a map that cannot be zoomed at all on some screen.
      expect(kMaxMapZoom, greaterThan(minMapScale(const Size(430, 932))));
    });
  });

  // ── Die Matrix muss ihren eigenen Zoom kennen (user 2026-08-09) ──
  // "ich kann viel zu weit hinauszoomen" und "wenn ich ein gebäude anwähle zum
  //  schieben, zoomt es hinein" were ONE bug, and it lived in a single 1.
  group('the view transform reports its own zoom', () {
    test('a matrix below 1:1 does not claim to be 1:1', () {
      for (final s in [0.018, 0.18, 0.5, 1.0, 2.5, 4.0]) {
        expect(mapTransform(s, -710, 0).getMaxScaleOnAxis(), closeTo(s, 1e-9),
            reason: 'scale $s');
      }
    });

    test('the OLD construction is exactly what got it wrong', () {
      // Kept as the counter-example, because the mistake looks like tidiness:
      // the map is flat, so z "cannot matter" — except getMaxScaleOnAxis takes
      // the LARGEST axis, and every real map scale is below 1.
      expect(Matrix4.diagonal3Values(0.18, 0.18, 1).getMaxScaleOnAxis(), 1.0);
      expect(mapTransform(0.18, 0, 0).getMaxScaleOnAxis(), closeTo(0.18, 1e-9));
    });

    test('and every scale a phone reaches IS below 1', () {
      // Which is why it was invisible to read and total in play: the map is
      // 10240 px across, so filling a phone with it is a scale near 0.18.
      expect(minMapScale(const Size(430, 932)), lessThan(0.3));
      expect(minMapScale(const Size(2400, 1600)), lessThan(1.0));
    });

    test('it moves a point the way InteractiveViewer does', () {
      final m = mapTransform(0.25, 100, -40);
      final p = MatrixUtils.transformPoint(m, const Offset(200, 80));
      expect(p.dx, closeTo(200 * 0.25 + 100, 1e-9));
      expect(p.dy, closeTo(80 * 0.25 - 40, 1e-9));
    });
  });

  // ── Der Rand darf NIE sichtbar sein (user 2026-08-09) ──────
  // "diese leeren Stellen darf es nicht geben"
  //
  // Stated as a property over arbitrary input rather than as a list of cases:
  // whatever transform arrives — a pinch past the limit, a camera move built
  // from a stale scale, a matrix from nowhere — what comes back covers every
  // pixel of the viewport. The page under the map is a dark parchment, so a gap
  // reads as a black band, which is exactly what was reported.
  group('the clamp leaves no gap, whatever it is given', () {
    void coversEverything(Matrix4 m, Size v) {
      final f = clampMapTransform(m, v);
      final s = f.getMaxScaleOnAxis();
      final t = f.getTranslation();
      expect(t.x, lessThanOrEqualTo(1e-6), reason: 'gap on the left: $m in $v');
      expect(t.y, lessThanOrEqualTo(1e-6), reason: 'gap on top: $m in $v');
      expect(isoCanvasSize.width * s + t.x,
          greaterThanOrEqualTo(v.width - 1e-6),
          reason: 'gap on the right: $m in $v');
      expect(isoCanvasSize.height * s + t.y,
          greaterThanOrEqualTo(v.height - 1e-6),
          reason: 'gap at the bottom: $m in $v');
      expect(s, greaterThanOrEqualTo(minMapScale(v) - 1e-9));
      expect(s, lessThanOrEqualTo(kMaxMapZoom + 1e-9));
    }

    test('zoomed far out, panned to nowhere', () {
      const v = Size(430, 932);
      for (final s in [0.0005, 0.018, 0.1, 0.18, 1.0, 3.0, 40.0]) {
        for (final t in [
          const Offset(0, 0),
          const Offset(5000, 5000),
          const Offset(-99999, -99999),
          const Offset(300, -20),
        ]) {
          coversEverything(mapTransform(s, t.dx, t.dy), v);
        }
      }
    });

    test('and in any window shape', () {
      for (final v in const [
        Size(430, 932), Size(932, 430), Size(1600, 900),
        Size(300, 300), Size(2400, 400),
      ]) {
        coversEverything(mapTransform(0.001, 4000, 4000), v);
        coversEverything(mapTransform(99.0, -50000, -50000), v);
      }
    });

    test('a transform already inside is left alone', () {
      // Otherwise the listener that applies this would fight every gesture.
      const v = Size(430, 932);
      final good = clampMapTransform(mapTransform(0.5, -100, -80), v);
      final again = clampMapTransform(good, v);
      expect(again.getMaxScaleOnAxis(), closeTo(good.getMaxScaleOnAxis(), 1e-12));
      expect(again.getTranslation().x, closeTo(good.getTranslation().x, 1e-9));
      expect(again.getTranslation().y, closeTo(good.getTranslation().y, 1e-9));
    });

    test('a clamped ZOOM keeps the middle of the screen where it was', () {
      // Scaling about the origin instead would throw the map sideways every
      // time a pinch went one notch too far. Checked well away from the rims,
      // where the edge clamp has nothing to say — pinned against the rim it is
      // the EDGE that decides where you end up, and rightly so.
      const v = Size(430, 932);
      const s0 = 8.0; // past kMaxMapZoom, so the scale really is clamped
      const tx = -40000.0, ty = -20000.0;
      final f = clampMapTransform(mapTransform(s0, tx, ty), v);
      final s = f.getMaxScaleOnAxis();
      final t = f.getTranslation();
      expect(s, kMaxMapZoom, reason: 'the zoom was not clamped at all');
      // The scene point under the middle of the screen, before and after.
      Offset under(double scale, double x, double y) =>
          Offset((v.width / 2 - x) / scale, (v.height / 2 - y) / scale);
      final before = under(s0, tx, ty);
      final after = under(s, t.x, t.y);
      expect(after.dx, closeTo(before.dx, 1e-6));
      expect(after.dy, closeTo(before.dy, 1e-6));
    });
  });
}
