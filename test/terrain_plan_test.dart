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

  test('the plan is deterministic and populated', () {
    final a = propsOfPlanForTest(planTerrainForTest(region));
    final b = propsOfPlanForTest(planTerrainForTest(region));
    expect(a.length, greaterThan(0));
    expect(a.length % 8, 0);
    expect(a, orderedEquals(b));
  });

  test('no tree stands on the buildable region', () {
    final props = propsOfPlanForTest(planTerrainForTest(region));
    const conifer = 5, broadleaf = 6;
    var trees = 0;
    for (var o = 0; o < props.length; o += 8) {
      final kind = props[o].toInt();
      if (kind != conifer && kind != broadleaf) continue;
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
      findsOneWidget,
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
