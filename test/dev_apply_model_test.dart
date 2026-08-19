import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_art.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

// ── Dev Mode pushes the MODEL's numbers into a live row (user 2026-08-12) ────
// "jetzt bitte den dev mode so anpassen, dass du direkt die Render korrekt
//  einfügst und die Grösse der Gebäude anpasst."
//
// Until now the only route from the renderer's measurements to a live Supabase
// was building_roster.sql, which deletes all 89 rows and rewrites them from
// code — so correcting one footprint also threw away every value tuned in the
// editor. withModelArt() is the narrow alternative, and what it must NOT touch
// is the whole point of it.

BuildingDef _tuned() => const BuildingDef(
  id: 'gold_vault',
  name: 'Meine Schatzkammer',      // renamed in Dev Mode
  imageUrl: 'https://example.test/old-upload.png',
  artBaseWidth: 0.42,              // dialled in by hand, and wrong
  artAnchorX: 0.31,
  artLift: 0.19,
  color: Color(0xFF123456),
  gridW: 2,                        // the OLD footprint
  gridH: 3,
  resourceCost: {'wood': 123},     // tuned
  constructionHours: 7.5,
  eraIds: ['era_1'],
  population: 4,
  maxCount: 2,
  maxLevelPerEra: {1: 9},
  costFactor: 1.9,
  timeFactor: 1.4,
);

void main() {
  group('withModelArt', () {
    final live = _tuned();
    final model = kFallbackBuildingDefs['gold_vault']!;
    final box = kBundledArtBox['gold_vault']!;
    final out = live.withModelArt(
      gridW: model.gridW,
      gridH: model.gridH,
      artBaseWidth: box.$1,
      artAnchorX: box.$2,
      artLift: box.$3,
    );

    test('takes the footprint and the placement the renderer measured', () {
      expect((out.gridW, out.gridH), (model.gridW, model.gridH));
      expect(out.artBaseWidth, box.$1);
      expect(out.artAnchorX, box.$2);
      expect(out.artLift, box.$3);
    });

    test('drops the upload, because the bundled picture already beats it', () {
      // A URL left behind is a value that looks live, previews in the form,
      // and is never drawn on the map again.
      expect(out.imageUrl, isNull);
      expect(buildingAsset(out.id), isNotNull);
    });

    test('touches NOTHING else — that is the whole reason it exists', () {
      expect(out.id, live.id);
      expect(out.name, live.name, reason: 'a Dev Mode rename must survive');
      expect(out.color, live.color);
      expect(out.resourceCost, live.resourceCost);
      expect(out.constructionHours, live.constructionHours);
      expect(out.eraIds, live.eraIds);
      expect(out.population, live.population);
      expect(out.maxCount, live.maxCount);
      expect(out.maxLevelPerEra, live.maxLevelPerEra);
      expect(out.costFactor, live.costFactor);
      expect(out.timeFactor, live.timeFactor);
      expect(out.isMainBuilding, live.isMainBuilding);
      expect(out.isUnique, live.isUnique);
      expect(out.isRoad, live.isRoad);
      expect(out.isBuildPlot, live.isBuildPlot);
      expect(out.category, live.category);
    });

    test('it survives the round trip through a Supabase row', () {
      // The editor writes rows, not objects. A field that serialises wrong is
      // a field that reverts on the next reload and looks like a lost save.
      final back = BuildingDef.fromDefRow(out.toDefRow());
      expect((back.gridW, back.gridH), (model.gridW, model.gridH));
      expect(back.artBaseWidth, closeTo(box.$1, 1e-9));
      expect(back.artAnchorX, closeTo(box.$2, 1e-9));
      expect(back.artLift, closeTo(box.$3, 1e-9));
      expect(back.imageUrl, anyOf(isNull, ''));
      expect(back.name, live.name);
    });
  });

  test('every bundled building can be applied at all', () {
    // The bulk button walks kBundledBuildingArt; a missing fallback or a
    // missing box would make it skip a building silently.
    for (final id in kBundledBuildingArt) {
      expect(kFallbackBuildingDefs[id], isNotNull, reason: '$id has no def');
      expect(kBundledArtBox[id], isNotNull, reason: '$id has no measured box');
    }
  });
}
