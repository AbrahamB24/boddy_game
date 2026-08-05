import 'dart:ui';

import 'package:boddygame/features/settlement/data/building_definitions.dart'
    show kGridCols, kGridRows;
import 'package:boddygame/features/settlement/data/iso_grid.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Turning the map (user 2026-08-04) ──────────────────────
// The rotation is a CAMERA: the grid keeps its coordinates, the projection
// turns. Everything below is a way of asking "is that still true?", because the
// failure mode is not a crash — it is a building that can no longer be tapped,
// or one painted over its neighbour, and both look like art bugs.

void main() {
  tearDown(() => isoRotation = 0);

  group('the grid does not turn', () {
    test('every cell survives the round trip, at every rotation', () {
      // The one that matters. If a cell cannot be recovered from the point it
      // was drawn at, the map is untappable at that rotation — and a tap is
      // how every single thing on this screen is done.
      for (var r = 0; r < 4; r++) {
        isoRotation = r;
        for (var x = 0; x < kGridCols; x++) {
          for (var y = 0; y < kGridRows; y++) {
            // The middle of the cell, so floor() cannot land on a seam.
            final c = gridToScreen(x + 0.5, y + 0.5);
            expect(screenToGrid(c), (x, y),
                reason: 'rotation $r lost cell ($x, $y)');
          }
        }
      }
    });

    test('a footprint keeps its own w and h in the DATA', () {
      // isoViewRect turns the PICTURE. Nothing here may suggest the building
      // changed shape — the economy, placement and every saved row read gridW
      // and gridH, and those never move.
      for (var r = 0; r < 4; r++) {
        isoRotation = r;
        final (_, _, vw, vh) = isoViewRect(4, 7, 3, 4);
        expect({vw, vh}, {3, 4}, reason: 'rotation $r invented a size');
        expect(r.isEven ? vw == 3 : vw == 4, isTrue,
            reason: 'rotation $r did not swap on screen');
      }
    });
  });

  group('what the viewer sees', () {
    test('the canvas is the same size at every rotation', () {
      // (cols + rows) survives a quarter turn, so the diamond does. This is
      // what lets the map keep its scroll offset while turning instead of
      // jumping.
      final sizes = <Size>{};
      for (var r = 0; r < 4; r++) {
        isoRotation = r;
        sizes.add(isoCanvasSize);
      }
      expect(sizes, hasLength(1));
    });

    test('the whole map stays inside its canvas', () {
      for (var r = 0; r < 4; r++) {
        isoRotation = r;
        final size = isoCanvasSize;
        for (final (gx, gy) in [
          (0.0, 0.0),
          (kGridCols.toDouble(), 0.0),
          (kGridCols.toDouble(), kGridRows.toDouble()),
          (0.0, kGridRows.toDouble()),
        ]) {
          final p = gridToScreen(gx, gy);
          expect(p.dx, inInclusiveRange(-0.001, size.width + 0.001),
              reason: 'rotation $r pushed a corner off the canvas');
          expect(p.dy, inInclusiveRange(-0.001, size.height + 0.001));
        }
      }
    });

    test('depth follows the viewer, not the grid', () {
      // Two neighbours along +x. At rotation 0 the one at the larger x is
      // nearer; after two quarters it must be the other way round, or turning
      // the map paints the far side of the village over the near side.
      isoRotation = 0;
      expect(isoDrawOrder(10, 10, 1, 1, 12, 10, 1, 1), isNegative);
      isoRotation = 2;
      expect(isoDrawOrder(10, 10, 1, 1, 12, 10, 1, 1), isPositive);
    });

    test('a footprint sits where it is drawn, at every rotation', () {
      // isoBounds must agree with gridToScreen about where the tile is. It
      // used to name its corners west/north/east/south, which was only true at
      // rotation 0 — at a quarter turn the "west" corner is not the left one.
      for (var r = 0; r < 4; r++) {
        isoRotation = r;
        final b = isoBounds(5, 6, 3, 4);
        for (final (gx, gy) in [(5.0, 6.0), (8.0, 6.0), (8.0, 10.0),
          (5.0, 10.0)]) {
          final p = gridToScreen(gx, gy);
          expect(b.contains(p) || _onEdge(b, p), isTrue,
              reason: 'rotation $r drew a corner outside its own bounds');
        }
        // Always 2:1, whichever way round the footprint is standing.
        expect(b.width / b.height, closeTo(2.0, 0.001));
      }
    });

    test('the local helpers swap with the view', () {
      isoRotation = 0;
      final flat = footprintSeams(3, 1).length;
      isoRotation = 1;
      expect(footprintSeams(3, 1).length, flat,
          reason: 'a 3x1 has the same seams whichever way it faces');
      // …but they run the other way, which is the whole point — and the BOUNDS
      // cannot see that. A 3x1 and a 1x3 both fill a 128 x 64 box; only the
      // parallelogram inside it differs, so the seams are what to compare.
      isoRotation = 0;
      final flatSeams = footprintSeams(3, 1);
      isoRotation = 1;
      final turnedSeams = footprintSeams(3, 1);
      expect(turnedSeams.map((s) => s.$1),
          isNot(equals(flatSeams.map((s) => s.$1))),
          reason: 'the turned footprint drew the same parallelogram');
    });
  });
}

bool _onEdge(Rect r, Offset p) =>
    (p.dx - r.left).abs() < 0.001 ||
    (p.dx - r.right).abs() < 0.001 ||
    (p.dy - r.top).abs() < 0.001 ||
    (p.dy - r.bottom).abs() < 0.001;
