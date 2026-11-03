import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_art.dart';

// ── The map ran CanvasKit out of memory (user 2026-08-12) ────
// A wall of "RuntimeError: memory access out of bounds" and "Bad state: Cannot
// dispose picture" out of canvaskit.wasm, thrown from a hit test and from the
// image cache's finalizer. Not a Dart bug: the texture budget.
//
// The bundled renders are 1024-1372 px across because that is the size they
// are AUTHORED at, and the map draws a building about 200 logical px wide.
//
// SHIPPED width raised from 640 to 960 (user 2026-09-06, for 3x displays) —
// tool/pack_art.py's own APP_MAX_WIDTH — which is why main.dart now raises
// PaintingBinding's own image cache from Flutter's 100 MB default to 200 MB:
// the twenty-odd bundled assets alone decode to ~92 MB at 960, which left
// almost no headroom under the old default before other art (roads,
// creatures, UI chrome) started evicting a building mid-frame.
//
// Two invariants, because the failure needs both halves to come back:
//
//   1. every bundled picture is DECODED at the size it is drawn (cacheWidth),
//      which is what makes the source resolution stop mattering; and
//   2. the source resolution stays sane anyway, so that a future render at
//      4K cannot quietly put it back.
//
// Neither can be checked by running the app in a test — CanvasKit is not
// there — so both are checked at the source.

/// Width and height out of a WebP header, without decoding it.
({int w, int h})? _webpSize(File f) {
  final b = f.readAsBytesSync();
  if (b.length < 30) return null;
  String tag(int i) => String.fromCharCodes(b.sublist(i, i + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WEBP') return null;
  final chunk = tag(12);
  final d = ByteData.sublistView(Uint8List.fromList(b));
  if (chunk == 'VP8X') {
    // 24-bit width-1 / height-1, little endian, at 24 and 27.
    final w = (b[24] | b[25] << 8 | b[26] << 16) + 1;
    final h = (b[27] | b[28] << 8 | b[29] << 16) + 1;
    return (w: w, h: h);
  }
  if (chunk == 'VP8 ') {
    // Key-frame start code, then two 14-bit dimensions.
    if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) return null;
    return (
      w: d.getUint16(26, Endian.little) & 0x3FFF,
      h: d.getUint16(28, Endian.little) & 0x3FFF,
    );
  }
  if (chunk == 'VP8L') {
    final bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
    return (w: (bits & 0x3FFF) + 1, h: ((bits >> 14) & 0x3FFF) + 1);
  }
  return null;
}

/// The Castle ships wider (user 2026-11-03): it spans 20 tile-widths where a
/// house spans 4, and at 960 px it would be half as sharp as everything
/// around it. One building, placed once.
const _wide = {'castle'};
int _maxW(String id) => _wide.contains(id) ? 2048 : 960;
int _maxBytes(String id) => _wide.contains(id) ? 16 << 20 : 5 << 20;

/// A turned picture (`<id>_r1`..`_r3`) is not decoded alongside its
/// building's other turns: a building stands one way at a time.
bool _isTurn(String id) => RegExp(r'_r[1-3]$').hasMatch(id);

void main() {
  group('bundled art fits in the texture budget', () {
    test('nothing ships wider than pack_art caps it', () {
      for (final id in kBundledBuildingArt) {
        final s = _webpSize(File(buildingAsset(id)!));
        expect(s!.w, lessThanOrEqualTo(_maxW(id)),
            reason: '$id ships at ${s.w} px; tool/pack_art.py -w 960 is what '
                'keeps the map inside the image cache');
      }
    });

    test('every bundled picture parses and reports its size', () {
      for (final id in kBundledBuildingArt) {
        final f = File(buildingAsset(id)!);
        expect(f.existsSync(), isTrue, reason: '${f.path} is missing');
        expect(_webpSize(f), isNotNull,
            reason: '${f.path}: cannot read the WebP header, so the budget '
                'below is not actually being checked');
      }
    });

    test('decoded at source resolution they stay under 150 MB', () {
      var bytes = 0;
      final worst = <String, int>{};
      for (final id in kBundledBuildingArt) {
        if (_isTurn(id)) continue;
        final s = _webpSize(File(buildingAsset(id)!));
        if (s == null) continue;
        final b = s.w * s.h * 4;
        bytes += b;
        worst[id] = b;
      }
      final mb = bytes / (1024 * 1024);
      final biggest = worst.entries.reduce((a, b) => a.value > b.value ? a : b);
      // 150, not 48 (user 2026-09-06's 640→960 bump) — ~92 MB today, and
      // main.dart's own image cache is 200 MB now (raised alongside the same
      // change) rather than Flutter's 100 MB default, so this still leaves
      // real headroom for roads/creatures/UI chrome above the bundled set
      // without silently creeping back to zero slack.
      expect(mb, lessThan(150),
          reason: 'the bundled renders would decode to '
              '${mb.toStringAsFixed(0)} MB — biggest is ${biggest.key} at '
              '${(biggest.value / 1024 / 1024).toStringAsFixed(1)} MB. The '
              'image cache holds 200 MB (main.dart); past that it evicts and '
              're-decodes on every pan.');
    });

    test('no single picture decodes to more than 5 MB', () {
      for (final id in kBundledBuildingArt) {
        final s = _webpSize(File(buildingAsset(id)!));
        if (s == null) continue;
        // 5, not 4 MB (user 2026-09-06's 640→960 bump) — the widest current
        // picture is ~4.3 MB at 960 px wide.
        expect(s.w * s.h * 4, lessThan(_maxBytes(id)),
            reason: '$id is ${s.w}x${s.h}');
      }
    });
  });

  group('and they are decoded at the size they are drawn', () {
    // cacheWidth is the half of the fix that makes the source resolution stop
    // mattering. Without it, an asset that grows puts the crash straight back.
    test('BuildingIcon passes cacheWidth to every Image.asset', () {
      final src = File('lib/features/settlement/widgets/building_icon.dart')
          .readAsStringSync();
      final calls = 'Image.asset('.allMatches(src).length;
      expect(calls, greaterThan(0), reason: 'the asset path has moved');
      expect('cacheWidth:'.allMatches(src).length, calls,
          reason: 'one Image.asset in BuildingIcon decodes at full size');
    });

    test('the map decodes its background and its road tiles small', () {
      final src = File('lib/features/settlement/widgets/settlement_map.dart')
          .readAsStringSync();
      final calls = 'Image.asset('.allMatches(src).length;
      expect(calls, greaterThan(0));
      expect('cacheWidth:'.allMatches(src).length, calls,
          reason: 'an Image.asset on the map decodes at full size — the '
              'background alone is 8192 x 4096');
    });
  });
}
