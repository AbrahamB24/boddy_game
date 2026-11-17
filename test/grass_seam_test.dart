import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/widgets/terrain_layer.dart';

// The grass swatch repeats across the whole map, so a slightly darker first and
// last row is a faint dark line every 512 px (user 2026-09-28: "Trennstriche im
// Rasen … die Rasenstruktur ist nicht die genau gleiche"). Levelling removes it.
void main() {
  Future<ui.Image> tile(int w, int h, int Function(int y) value) {
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        px[o] = value(y);
        px[o + 1] = value(y);
        px[o + 2] = value(y);
        px[o + 3] = 255;
      }
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  Future<double> rowMean(ui.Image img, int y) async {
    final d = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final b = d.buffer.asUint8List();
    var s = 0;
    for (var x = 0; x < img.width; x++) {
      s += b[(y * img.width + x) * 4 + 1];
    }
    return s / img.width;
  }

  // levelTile once laid a per-block speckle over the grass (user
  // 2026-11-13), so rows are no longer flat. The seam is judged against the
  // SAME tile without a seam: both get the identical speckle, so what is left
  // of a difference is the seam itself.
  testWidgets('darker seam rows are brought up to the rest', (t) async {
    await t.runAsync(() async {
      // 150 everywhere, 146 on the first and last two rows (a ~2.7 % dip).
      final seam = await tile(32, 32, (y) => (y < 2 || y > 29) ? 146 : 150);
      final even = await tile(32, 32, (y) => 150);
      expect(await rowMean(seam, 0), lessThan(147));
      final out = await TerrainLayer.levelTile(seam);
      final ref = await TerrainLayer.levelTile(even);
      for (final y in [0, 1, 16, 30, 31]) {
        expect(await rowMean(out, y), closeTo(await rowMean(ref, y), 1.5));
      }
    });
  });

  testWidgets('an even tile keeps its overall brightness', (t) async {
    await t.runAsync(() async {
      final src = await tile(32, 32, (y) => 150);
      final out = await TerrainLayer.levelTile(src);
      var sum = 0.0;
      for (var y = 0; y < 32; y++) {
        sum += await rowMean(out, y);
      }
      expect(sum / 32, closeTo(150, 4));
    });
  });
}
