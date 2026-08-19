import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_art.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

// ── The art SHIPS with the app (user 2026-08-12) ─────────────
// "baue die Gebäude einmal in das Game ein oder muss ich was bei supabase
//  machen?"
//
// Nothing at Supabase — the twenty modelled buildings are bundled. That turns
// three separate things into one contract, and all three can break silently:
//
//   1. the id in kBundledBuildingArt must be a real building, or the picture
//      is never asked for;
//   2. the FILE must exist under that exact name, or the tile falls back to
//      the placeholder box and looks like the art was never made. WebP
//      since 2026-08-12: the materials have grain now, and a palette PNG
//      dithers a continuous ramp into speckle (see tool/pack_art.py);
//   3. the Blender preset must be rendered at the footprint the def declares,
//      or the picture is framed for a base that is not the tile it stands on.
//
// (3) is not hypothetical: castle was 6 x 6 in PRESETS and 5 x 5 in the
// roster, and it did not matter for as long as the render was only ever looked
// at. The moment it was bundled and placed, the castle was framed a whole cell
// too wide. Nothing in the app could have caught that — the mismatch lives
// across two languages — so it is pinned here.

/// The `PRESETS` table in the Blender script, as {id: (w, h)}.
Map<String, (int, int)> _presets() {
  final src = File('tool/blender/render_building.py').readAsStringSync();
  // No expect() here: this runs while the group is being DECLARED, and
  // matchers outside a test throw OutsideTestException.
  final start = src.indexOf('PRESETS = {');
  if (start < 0) return const {};
  final body = src.substring(start, src.indexOf('\n}', start));
  final out = <String, (int, int)>{};
  for (final m in RegExp(
    r"^\s*'([a-z0-9_]+)':\s*\(\s*\w+\s*,\s*(\d+)\s*,\s*(\d+)\s*\)",
    multiLine: true,
  ).allMatches(body)) {
    out[m.group(1)!] = (int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
  return out;
}

void main() {
  group('bundled building art', () {
    test('every bundled id is a building in the roster', () {
      for (final id in kBundledBuildingArt) {
        expect(
          kFallbackBuildingDefs.containsKey(id),
          isTrue,
          reason: '$id has a picture but no def — the art is unreachable',
        );
      }
    });

    test('every bundled id has its file', () {
      for (final id in kBundledBuildingArt) {
        final path = buildingAsset(id)!;
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is missing; the tile falls back to the grey box',
        );
      }
    });

    test('pubspec ships the directory', () {
      // A directory entry is NOT recursive — assets/images/ alone would leave
      // every one of these out of the build, and only on a real device.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/images/buildings/'));
    });

    test('nothing bundled that is not declared', () {
      final onDisk = Directory('assets/images/buildings')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.webp'))
          .map((n) => n.substring(0, n.length - 5))
          .toSet();
      expect(
        onDisk.difference(kBundledBuildingArt),
        isEmpty,
        reason: 'files nobody will ever load — declare them or delete them',
      );
    });

    test('every bundled id has a measured placement box', () {
      for (final id in kBundledBuildingArt) {
        expect(
          kBundledArtBox.containsKey(id),
          isTrue,
          reason: '$id has a picture but no box — it would be placed by the '
              "def's defaults, which assume the picture IS the footprint",
        );
        final (baseWidth, anchorX, lift) = kBundledArtBox[id]!;
        // A base wider than the picture, or anchored outside it, is a
        // generator bug that would only show as art sliding off its tile.
        expect(baseWidth, greaterThan(0.5));
        expect(baseWidth, lessThanOrEqualTo(1.0));
        expect(anchorX, inInclusiveRange(0.0, 1.0));
        expect(lift, inInclusiveRange(0.0, 0.5));
      }
    });

    test('buildingAsset says no to everything else', () {
      expect(buildingAsset(null), isNull);
      expect(buildingAsset('road'), isNull);
      expect(buildingAsset('building_plot'), isNull);
      expect(buildingAsset('not_a_building'), isNull);
    });
  });

  group('the render is framed for the tile it stands on', () {
    final presets = _presets();

    test('the preset table was found at all', () {
      expect(presets, isNotEmpty, reason: 'PRESETS table not parsed');
    });

    test('every bundled building has a preset', () {
      for (final id in kBundledBuildingArt) {
        expect(
          presets.containsKey(id),
          isTrue,
          reason: '$id is bundled but nothing in PRESETS renders it',
        );
      }
    });

    test('the preset footprint is the def footprint', () {
      for (final id in kBundledBuildingArt) {
        final def = kFallbackBuildingDefs[id]!;
        final preset = presets[id];
        if (preset == null) continue; // reported by the test above
        expect(
          preset,
          (def.gridW, def.gridH),
          reason:
              '$id renders at ${preset.$1}x${preset.$2} but the def is '
              '${def.gridW}x${def.gridH} — the art would be framed for a base '
              'that is not its tile',
        );
      }
    });
  });
}
