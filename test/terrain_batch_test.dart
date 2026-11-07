import 'dart:ui' as ui;

import 'package:boddygame/features/settlement/services/game_engine.dart';
import 'package:boddygame/features/settlement/widgets/terrain_layer.dart';
import 'package:boddygame/features/settlement/data/iso_grid.dart' show isoCanvasSize;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// The terrain draws its thousands of props, their shadows and the grass wash
// through baked sprite sheets in a handful of batched calls (2026-11-03). This
// pins that the batched picture matches the old one-draw-per-prop picture.
final region = GameEngine.buildableRegionCells(const []);

Future<List<int>> _render(WidgetTester tester, double scale, Offset origin,
    Size window) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: window,
          child: RepaintBoundary(
            key: key,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform(
                  transform: Matrix4.identity()
                    ..scaleByDouble(scale, scale, 1, 1)
                    ..translateByDouble(-origin.dx, -origin.dy, 0, 1),
                  child: SizedBox.fromSize(
                    size: isoCanvasSize,
                    child: TerrainLayer(buildableRegion: region),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  late List<int> px;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    px = raw!.buffer.asUint8List().toList();
  });
  return px;
}

void main() {
  // No wind, no drifting water: the two pictures must be pixel-comparable.
  setUp(() => TerrainLayer.debugAnimate = false);
  tearDown(() {
    TerrainLayer.debugDrawOneByOne = false;
    TerrainLayer.debugAnimate = true;
  });

  testWidgets('batched terrain matches the one-by-one picture', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    await tester.runAsync(() => TerrainLayer.preload(region));
    for (final (scale, origin) in [
      (1.0, const Offset(1200, 2600)), // close: single trees
      (0.2, Offset.zero), // far: the whole forest at once
    ]) {
      const window = Size(900, 500);
      TerrainLayer.debugDrawOneByOne = true;
      final a = await _render(tester, scale, origin, window);
      TerrainLayer.debugDrawOneByOne = false;
      final b = await _render(tester, scale, origin, window);
      expect(b.where((v) => v != 0).length, greaterThan(a.length ~/ 2));
      // Real terrain was drawn, not two equal blanks.
      expect(a.toSet().length, greaterThan(100));
      var sum = 0;
      for (var i = 0; i < a.length; i++) {
        sum += (a[i] - b[i]).abs();
      }
      // Measured 1.9 (close) / 3.8 (far) of 255: sub-pixel sampling only.
      expect(sum / a.length, lessThan(6), reason: 'scale $scale');
    }
  });
}
