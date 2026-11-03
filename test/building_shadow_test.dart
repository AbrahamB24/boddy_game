import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/widgets/building_icon.dart';

// The ground shadow of a building (user 2026-09-22: "der Schatten ist unterhalb
// des Gebäudes und nicht am richtigen Ort"): every standing thing casts from ITS
// OWN foot. A house with a fence round its yard has its lowest pixel on the
// fence, and a shadow hinged there hung a yard's depth below the walls.
void main() {
  /// A [w] x [h] picture with solid rectangles (x0, y0, x1, y1 inclusive).
  Uint8List picture(int w, int h, List<List<int>> boxes) {
    final rgba = Uint8List(w * h * 4);
    for (final b in boxes) {
      for (var y = b[1]; y <= b[3]; y++) {
        for (var x = b[0]; x <= b[2]; x++) {
          rgba[(y * w + x) * 4 + 3] = 255;
        }
      }
    }
    return rgba;
  }

  int rowsWithShadow(ShadowMask m, {required int fromX, required int toX}) {
    var first = -1;
    for (var y = 0; y < m.height && first < 0; y++) {
      for (var x = fromX; x <= toX; x++) {
        if (m.alpha[y * m.width + x] != 0) {
          first = y;
          break;
        }
      }
    }
    return first;
  }

  test('a shadow starts on the row below the foot, never above it', () {
    // A 10 x 40 wall standing on row 60.
    final m = castShadowMask(
      picture(60, 80, [
        [10, 21, 19, 60],
      ]),
      60,
      80,
    );
    final first = rowsWithShadow(m, fromX: 0, toX: m.width - 1);
    expect(first, 61);
    // Nothing above the foot, anywhere.
    for (var y = 0; y <= 60; y++) {
      for (var x = 0; x < m.width; x++) {
        expect(m.alpha[y * m.width + x], 0, reason: 'pixel $x,$y');
      }
    }
  });

  test('it falls to the RIGHT and forward: the top of the wall lands furthest '
      'right', () {
    final m = castShadowMask(
      picture(60, 80, [
        [10, 21, 19, 60],
      ]),
      60,
      80,
    );
    var rightmost = -1;
    for (var y = 0; y < m.height; y++) {
      for (var x = 0; x < m.width; x++) {
        if (m.alpha[y * m.width + x] != 0 && x > rightmost) rightmost = x;
      }
    }
    // 19 + 0.34 x 39 px of height ≈ 32.
    expect(rightmost, inInclusiveRange(31, 33));
  });

  test('the house casts from ITS base even with a fence far below it', () {
    // The wall stands on row 40; a thin fence post reaches down to row 75.
    final m = castShadowMask(
      picture(60, 80, [
        [10, 10, 30, 40], // the house
        [12, 70, 13, 75], // a fence post in front of it
      ]),
      60,
      80,
    );
    // Under the house's own columns (away from the post) the shadow begins
    // right below the wall (row 41) — not down at the fence.
    final under = rowsWithShadow(m, fromX: 18, toX: 30);
    expect(under, 41);
  });

  test('a taller thing throws a longer shadow than a short one', () {
    final tall = castShadowMask(
      picture(60, 90, [
        [10, 10, 14, 60],
      ]),
      60,
      90,
    );
    final short = castShadowMask(
      picture(60, 90, [
        [10, 45, 14, 60],
      ]),
      60,
      90,
    );
    int reach(ShadowMask m) {
      var r = 0;
      for (var y = 0; y < m.height; y++) {
        for (var x = 0; x < m.width; x++) {
          if (m.alpha[y * m.width + x] != 0 && x > r) r = x;
        }
      }
      return r;
    }

    expect(reach(tall), greaterThan(reach(short) + 5));
  });

  test('a single standing thing (tree) casts from ONE foot: no second shadow '
      'from its overhanging canopy', () {
    // A wide canopy (rows 10-30) on a narrow trunk (rows 31-60).
    final tree = picture(60, 80, [
      [8, 10, 31, 30],
      [18, 31, 21, 60],
    ]);
    final one = castShadowMask(tree, 60, 80, perRun: false);
    // Nothing above the trunk's foot, anywhere — the canopy's underside (row 30)
    // is not the ground.
    for (var y = 0; y <= 60; y++) {
      for (var x = 0; x < one.width; x++) {
        expect(one.alpha[y * one.width + x], 0, reason: 'pixel $x,$y');
      }
    }
    expect(rowsWithShadow(one, fromX: 0, toX: one.width - 1), 61);
    // Per run (the buildings' mode) would start a second shadow at row 31, under
    // the canopy's edge columns — the bug the mode exists to avoid.
    final many = castShadowMask(tree, 60, 80);
    expect(rowsWithShadow(many, fromX: 0, toX: many.width - 1), 31);
  });

  test('a ground depth turns the thin strip into an ellipse (trees, stones)', () {
    // The same canopy on a trunk: thrown at the 2:1 slope its shadow is a strip
    // a few rows deep; with a depth it becomes a patch as deep as a fraction of
    // the picture's width — widest in the middle, tapering to nothing at the ends.
    final tree = picture(60, 80, [
      [8, 10, 31, 30],
      [18, 31, 21, 60],
    ]);
    final flat = castShadowMask(tree, 60, 80, perRun: false);
    final deep = castShadowMask(tree, 60, 80, perRun: false, groundDepth: 0.25);
    int thickness(ShadowMask m, int x) {
      var n = 0;
      for (var y = 0; y < m.height; y++) {
        if (m.alpha[y * m.width + x] != 0) n++;
      }
      return n;
    }

    // Find the shadow's horizontal extent, then compare its middle and its ends.
    var x0 = -1, x1 = -1;
    for (var x = 0; x < deep.width; x++) {
      if (thickness(deep, x) > 0) {
        if (x0 < 0) x0 = x;
        x1 = x;
      }
    }
    final mid = (x0 + x1) ~/ 2;
    expect(thickness(deep, mid), greaterThan(thickness(flat, mid) + 8));
    expect(thickness(deep, mid), greaterThan(thickness(deep, x0 + 1)));
    // A depth of 0 is the plain projection, so buildings are untouched.
    final same = castShadowMask(tree, 60, 80, perRun: false, groundDepth: 0);
    expect(same.alpha, flat.alpha);
  });


  testWidgets('a real building throws a shadow with no single-pixel holes '
      '(the "stitches" in the grass)', (t) async {
    // The healing hut, at the size the map works its shadow out at: its foot
    // runs on the iso diagonal, which left a dotted line of unshaded pixels
    // through the shadow (user 2026-09-28: "Trennstriche im Rasen").
    await t.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File('assets/images/buildings/healing_hut.webp').readAsBytesSync(),
        targetWidth: 128,
      );
      final image = (await codec.getNextFrame()).image;
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final m = castShadowMask(
        data.buffer.asUint8List(),
        image.width,
        image.height,
      );
      var holes = 0;
      for (var y = 1; y < m.height - 1; y++) {
        for (var x = 1; x < m.width - 1; x++) {
          final i = y * m.width + x;
          if (m.alpha[i] != 0) continue;
          final sideways = m.alpha[i - 1] != 0 && m.alpha[i + 1] != 0;
          final upDown =
              m.alpha[i - m.width] != 0 && m.alpha[i + m.width] != 0;
          if (sideways || upDown) holes++;
        }
      }
      expect(holes, 0);
    });
  });
  test('a fully transparent picture casts nothing', () {
    final m = castShadowMask(Uint8List(40 * 40 * 4), 40, 40);
    expect(m.alpha.any((a) => a != 0), isFalse);
  });

  test('a one-pixel hole inside a wall does not split it in two', () {
    // The wall has a transparent row at y=30; both halves must still cast from
    // the wall's real foot (row 60), not from the hole.
    final m = castShadowMask(
      picture(60, 80, [
        [10, 10, 19, 29],
        [10, 31, 19, 60],
      ]),
      60,
      80,
    );
    expect(rowsWithShadow(m, fromX: 0, toX: m.width - 1), 61);
  });

  testWidgets('a decoded picture becomes a ready-to-paint shadow image (trees, '
      'stones)', (t) async {
    await t.runAsync(() async {
      Future<ui.Image> image(Uint8List rgba, int w, int h) {
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          rgba,
          w,
          h,
          ui.PixelFormat.rgba8888,
          c.complete,
        );
        return c.future;
      }

      // A 20 x 30 "tree trunk" standing on row 40 of a 40 x 50 picture.
      final rgba = Uint8List(40 * 50 * 4);
      for (var y = 10; y <= 40; y++) {
        for (var x = 10; x < 20; x++) {
          final i = (y * 40 + x) * 4;
          rgba[i] = 20;
          rgba[i + 1] = 90;
          rgba[i + 2] = 30;
          rgba[i + 3] = 255;
        }
      }
      final shadow = await castShadowImage(await image(rgba, 40, 50));
      expect(shadow, isNotNull);
      // It reaches past the picture's right and bottom edges, where it falls.
      expect(shadow!.width, greaterThan(40));
      expect(shadow.height, greaterThan(50));
      // No colour is baked in any more (user 2026-09-29: a tree's shadow used
      // to bake its OWN copy of the tint, which is how it drifted from a
      // building's — see [kShadowTint]/[kShadowOpacity]) — only the alpha
      // channel carries the silhouette, RGB stays 0.
      final raw = (await shadow.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();
      var checked = 0;
      for (var i = 0; i < raw.length; i += 4) {
        expect(raw[i], 0);
        expect(raw[i + 1], 0);
        expect(raw[i + 2], 0);
        if (raw[i + 3] > 0) checked++;
      }
      expect(checked, greaterThan(0));
      // Tinted through the SAME filter a building's own ground shadow uses
      // (`BuildingGroundShadow`'s `_ShadowPainter`), it reads back the exact
      // near-black #06170F a building's shadow wears — one colour for both,
      // not two independently-tuned ones.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final full = ui.Rect.fromLTWH(
        0,
        0,
        shadow.width.toDouble(),
        shadow.height.toDouble(),
      );
      canvas.drawImageRect(
        shadow,
        full,
        full,
        ui.Paint()
          ..colorFilter = ui.ColorFilter.mode(
            kShadowTint.withValues(alpha: kShadowOpacity),
            ui.BlendMode.srcIn,
          ),
      );
      final tinted = await recorder
          .endRecording()
          .toImage(shadow.width, shadow.height);
      final tintedPx = (await tinted.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!.buffer.asUint8List();
      var tintedChecked = 0;
      for (var i = 0; i < tintedPx.length; i += 4) {
        if (tintedPx[i + 3] < 30) continue; // too faint to read the colour back
        expect(tintedPx[i], closeTo(0x06, 3));
        expect(tintedPx[i + 1], closeTo(0x17, 3));
        expect(tintedPx[i + 2], closeTo(0x0F, 3));
        tintedChecked++;
      }
      expect(tintedChecked, greaterThan(0));
      // A picture with nothing in it casts nothing.
      expect(
        await castShadowImage(await image(Uint8List(16 * 16 * 4), 16, 16)),
        isNull,
      );
    });
  });
}
