import 'dart:typed_data';
import 'package:boddygame/features/settlement/data/building_definitions.dart'
    show kGridCols, kGridRows;
import 'package:boddygame/features/settlement/services/game_engine.dart';
import 'package:boddygame/features/settlement/widgets/terrain_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// The terrain is planned once per buildable region (in a background isolate at
// runtime) instead of inside every paint. This pins the properties the painter
// and the map rely on: the plan is deterministic, non-empty, and keeps trees off
// the player's own land.
final region = GameEngine.buildableRegionCells(const []);

void main() {
  pipelineTest();
  lifeTests();

  test('the plan is deterministic and populated', () {
    final a = propsOfPlanForTest(planTerrainForTest(region));
    final b = propsOfPlanForTest(planTerrainForTest(region));
    expect(a.length, greaterThan(0));
    expect(a.length % 8, 0);
    expect(a, orderedEquals(b));
  });

  test('no tree stands on the buildable region', () {
    final props = propsOfPlanForTest(planTerrainForTest(region));
    const firstTree = 14, lastTree = 19; // conifers 14-16, broadleafs 17-19
    var trees = 0;
    for (var o = 0; o < props.length; o += 8) {
      final kind = props[o].toInt();
      if (kind < firstTree || kind > lastTree) continue;
      trees++;
      final gx = props[o + 1].toInt(), gy = props[o + 2].toInt();
      // The region only holds real cells; the padded canvas around the grid
      // has no entry (and would alias a real key).
      if (gx < 0 || gx >= kGridCols || gy < 0 || gy >= kGridRows) continue;
      expect(
        region.contains(gy * kGridCols + gx),
        isFalse,
        reason: 'tree at $gx,$gy',
      );
    }
    expect(trees, greaterThan(0));
  });
}

// The real pipeline: assets decoded, the plan computed in a background isolate
// (`compute`), the meshes and props painted through a real raster.
void pipelineTest() {
  testWidgets('preload + paint works end to end', (tester) async {
    final key = GlobalKey();
    await tester.runAsync(() => TerrainLayer.preload(region));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 400,
            height: 200,
            child: RepaintBoundary(
              key: key,
              child: FittedBox(
                fit: BoxFit.none,
                alignment: Alignment.topLeft,
                clipBehavior: Clip.hardEdge,
                child: TerrainLayer(buildableRegion: region),
              ),
            ),
          ),
        ),
      ),
    );
    // Already resolved by preload — the very first frame has the terrain.
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null),
      findsNWidgets(3), // the still ground, the moving half and the animals
    );
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      expect(image.width, greaterThan(0));
    });
    expect(tester.takeException(), isNull);
  });
}

// Life on the map (user 2026-11-05): animals and landmarks (ruins, a stranded
// boat ...) that disappear as soon as a Building Plot touches them.
void lifeTests() {
  group('map life', () {
    final plan = planTerrainForTest(region);
    final fauna = faunaOfPlanForTest(plan);
    final props = propsOfPlanForTest(plan);
    final (firstMark, lastMark) = landmarkKindsForTest;

    List<(int, int, int)> marks(Float64List p) => [
      for (var o = 0; o < p.length; o += 8)
        if (p[o] >= firstMark && p[o] <= lastMark)
          (p[o].toInt(), p[o + 1].toInt(), p[o + 2].toInt()),
    ];

    test('there are landmarks and animals', () {
      expect(marks(props).length, greaterThanOrEqualTo(3));
      final species = <int>{
        for (var o = 0; o < fauna.length; o += faunaStrideForTest)
          fauna[o].toInt(),
      };
      expect(fauna.length % faunaStrideForTest, 0);
      expect(species.length, greaterThanOrEqualTo(4));
    });

    test('nothing of it stands on or beside the player\'s land', () {
      for (final (_, gx, gy) in marks(props)) {
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            expect(region.contains((gy + dy) * kGridCols + gx + dx), isFalse);
          }
        }
      }
      for (var o = 0; o < fauna.length; o += faunaStrideForTest) {
        for (var i = 0; i < fauna[o + 4].toInt(); i++) {
          final gx = fauna[o + 5 + i * 2].round();
          final gy = fauna[o + 6 + i * 2].round();
          if (gx < 0 || gx >= kGridCols || gy < 0 || gy >= kGridRows) continue;
          expect(region.contains(gy * kGridCols + gx), isFalse);
        }
      }
    });

    test('a plot growing over a landmark or an animal removes it', () {
      final (kind, gx, gy) = marks(props).first;
      final grown = Set<int>.of(region);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          grown.add((gy + dy) * kGridCols + gx + dx);
        }
      }
      final after = planTerrainForTest(grown);
      expect(
        marks(propsOfPlanForTest(after)).where((m) => m == (kind, gx, gy)),
        isEmpty,
      );

      // the first animal, claimed at its first stop
      final ax = fauna[5].round(), ay = fauna[6].round();
      final claimed = Set<int>.of(region)..add(ay * kGridCols + ax);
      final left = faunaOfPlanForTest(planTerrainForTest(claimed));
      expect(left.length, lessThan(fauna.length));
    });
  });
}
