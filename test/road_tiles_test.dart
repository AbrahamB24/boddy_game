import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart'
    show kGridCols, kGridRows;
import 'package:boddygame/features/settlement/data/road_tiles.dart';

// ── Strassen passen sich selbst an (user 2026-08-09) ─────────
// "mache bitte jetzt die Strassen, welche auch Kreuzungen und Kurven beinhalten
//  können. Diese sollen sich automatisch richtig anpassen."
//
// The whole feature is one number: which of a cell's four neighbours are roads.
// Everything else — the crossroads, the curve, the dead end — is a picture
// chosen by that number, and the picture is chosen by NAME. So there are
// exactly two things that can break it, and both are pinned here: the bit order
// (which bit means which direction) and the file names.
//
// The bit order is also a CONTRACT WITH BLENDER. tool/blender/roads.py builds
// each tile from the same four directions in the same order; swap two bits in
// either file and every curve on the map turns the wrong way, silently, because
// all sixteen pictures still exist and still load.
Set<int> _cells(List<(int, int)> xy) =>
    {for (final (x, y) in xy) roadCellKey(x, y)};

void main() {
  group('which bit is which direction', () {
    // Each direction on its own, against the screen direction it names.
    // iso_grid.dart: +x runs down-right and +y runs down-LEFT.
    test('+x is the neighbour one cell further along x', () {
      expect(roadMask(_cells([(6, 5)]), 5, 5), kRoadPlusX);
    });

    test('+y is the neighbour one cell further along y', () {
      expect(roadMask(_cells([(5, 6)]), 5, 5), kRoadPlusY);
    });

    test('-x and -y are the other two', () {
      expect(roadMask(_cells([(4, 5)]), 5, 5), kRoadMinusX);
      expect(roadMask(_cells([(5, 4)]), 5, 5), kRoadMinusY);
    });

    test('the four bits are distinct powers of two', () {
      final bits = [kRoadPlusX, kRoadPlusY, kRoadMinusX, kRoadMinusY];
      expect(bits.toSet(), hasLength(4));
      for (final b in bits) {
        expect(b & (b - 1), 0, reason: '$b is not a single bit');
      }
      expect(bits.reduce((a, b) => a | b), 15);
    });

    test('a diagonal neighbour is NOT a connection', () {
      // Roads join edge to edge — the same rule the road network uses for
      // reaching the hall. A diagonal that counted here would draw a junction
      // the pathfinding does not believe in.
      expect(roadMask(_cells([(6, 6), (4, 4), (6, 4), (4, 6)]), 5, 5), 0);
    });
  });

  group('the shapes fall out of the count', () {
    test('nothing around it is a lone patch', () {
      expect(roadMask(<int>{}, 5, 5), 0);
    });

    test('a straight run is the two OPPOSITE bits', () {
      expect(roadMask(_cells([(4, 5), (6, 5)]), 5, 5),
          kRoadPlusX | kRoadMinusX);
      expect(roadMask(_cells([(5, 4), (5, 6)]), 5, 5),
          kRoadPlusY | kRoadMinusY);
    });

    test('a curve is two bits at right angles', () {
      expect(roadMask(_cells([(6, 5), (5, 6)]), 5, 5),
          kRoadPlusX | kRoadPlusY);
    });

    test('a tee is three, a crossroads is four', () {
      expect(roadMask(_cells([(4, 5), (6, 5), (5, 6)]), 5, 5), 7);
      expect(roadMask(_cells([(4, 5), (6, 5), (5, 4), (5, 6)]), 5, 5), 15);
    });

    test('laying one more cell RE-SHAPES its neighbour', () {
      // The property the request is actually about: nothing is authored, so
      // adding a road turns the straight run beside it into a tee by itself.
      final before = _cells([(4, 5), (6, 5)]);
      expect(roadMask(before, 5, 5), kRoadPlusX | kRoadMinusX);
      final after = {...before, roadCellKey(5, 6)};
      expect(roadMask(after, 5, 5), kRoadPlusX | kRoadMinusX | kRoadPlusY);
    });
  });

  group('the edge of the world', () {
    test('a neighbour off the map does not count', () {
      // Not "wraps" and not "crashes": the road ends in a kerb. Reading
      // (-1, 0) as a cell key would land on the previous ROW, which is a real
      // cell somewhere else on the map — a wrap-around junction.
      expect(roadMask(_cells([(kGridCols - 2, 0)]), kGridCols - 1, 0),
          kRoadMinusX);
      expect(roadMask(_cells([(0, 1)]), 0, 0), kRoadPlusY);
      expect(roadMask(<int>{}, 0, 0), 0);
    });

    test('a cell key is unique per cell', () {
      final seen = <int>{};
      for (var y = 0; y < kGridRows; y++) {
        for (var x = 0; x < kGridCols; x++) {
          expect(seen.add(roadCellKey(x, y)), isTrue, reason: '($x, $y)');
        }
      }
    });
  });

  group('every mask has a picture', () {
    test('all sixteen files exist and carry an image', () {
      for (var mask = 0; mask < 16; mask++) {
        final f = File(roadAsset(mask));
        expect(f.existsSync(), isTrue, reason: '${f.path} is missing — '
            'render it with tool/blender/roads.py');
        // A 256x128 quantised render is a few KB; anything tiny is a truncated
        // or empty write, which would show on the map as a hole in the road.
        expect(f.lengthSync(), greaterThan(1024), reason: f.path);
      }
    });

    testWidgets('and all sixteen are IN THE BUNDLE, which is the real test',
        (tester) async {
      // On disk is not shipped. The map calls Image.asset, which reads the
      // bundle Flutter builds from pubspec — so a tile that exists as a file
      // and is missing from the bundle fails in exactly one place: the running
      // app, silently, with the flat-diamond fallback in its place. Loading
      // through rootBundle is the same path the app takes.
      for (var mask = 0; mask < 16; mask++) {
        final data = await rootBundle.load(roadAsset(mask));
        expect(data.lengthInBytes, greaterThan(1024),
            reason: '${roadAsset(mask)} is not in the asset bundle');
        // RIFF....WEBP, so a stray text file cannot pass for a picture.
        // WebP since 2026-08-12 — the cobbles have grain now and a palette
        // PNG dithers a continuous ramp into speckle. See tool/pack_art.py.
        final head = data.buffer.asUint8List(0, 12);
        expect(head.sublist(0, 4), [0x52, 0x49, 0x46, 0x46],
            reason: '${roadAsset(mask)} is not a RIFF container');
        expect(head.sublist(8, 12), [0x57, 0x45, 0x42, 0x50],
            reason: '${roadAsset(mask)} is not a WebP');
      }
    });

    test('the name is the mask, zero padded', () {
      expect(roadAsset(0), endsWith('road_00.webp'));
      expect(roadAsset(9), endsWith('road_09.webp'));
      expect(roadAsset(15), endsWith('road_15.webp'));
    });

    test('the assets folder is declared in pubspec', () {
      // A directory entry in pubspec is NOT recursive: without its own line the
      // sixteen tiles simply do not ship, and every road falls back to a flat
      // diamond in the release build only.
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('assets/images/roads/'));
    });
  });
}
