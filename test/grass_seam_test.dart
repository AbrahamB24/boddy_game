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

  testWidgets('darker seam rows are brought up to the rest', (t) async {
    await t.runAsync(() async {
      // 150 everywhere, 146 on the first and last two rows (a ~2.7 % dip).
      final src = await tile(32, 32, (y) => (y < 2 || y > 29) ? 146 : 150);
      expect(await rowMean(src, 0), lessThan(147));
      final out = await TerrainLayer.levelTile(src);
      expect(await rowMean(out, 0), closeTo(await rowMean(out, 16), 1.0));
      expect(await rowMean(out, 31), closeTo(await rowMean(out, 16), 1.0));
    });
  });

  testWidgets('an even tile is left as it is', (t) async {
    await t.runAsync(() async {
      final src = await tile(32, 32, (y) => 150);
      final out = await TerrainLayer.levelTile(src);
      expect(await rowMean(out, 0), closeTo(150, 0.5));
      expect(await rowMean(out, 20), closeTo(150, 0.5));
    });
  });
}
