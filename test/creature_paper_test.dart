import 'package:flutter/painting.dart' show Color, HSLColor;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';

// ── Das Papier trägt das Element (user 2026-07-31) ──────────
// "Nimm anstelle des beigen hintergrunds, jeweils eine andere Ausprägung der
//  Farbe des Elements"
//
// The detail sheet is printed in the monster's own hue now. The rule that makes
// that safe is FIXED LIGHTNESS: the page must stay light enough for the same
// dark ink whatever colour the element is, and the game has both a shadow
// element and a light one. This pins the property the ink depends on, since the
// screen itself cannot be pumped without a loaded controller.
//
// Mirrors _paper in creature_detail_screen.dart. If that changes, this is the
// test that should stop you.
Color paper(Color element, double lightness) {
  final hsl = HSLColor.fromColor(element);
  if (hsl.saturation < 0.08) return const Color(0xFF1F262C);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.22, 0.48))
      .withLightness(lightness)
      .toColor();
}

void main() {
  test('every element yields a page the ink can sit on', () {
    // The whole reason lightness is FIXED here rather than blended from the raw
    // element colour: a light monster and a shadow monster must both end up on
    // a page the same cream ink reads on. Going dark (2026-07-31) moved the two
    // numbers and changed nothing else.
    const inkLuminance = 0.79; // kParchmentInk #EDE3CB
    for (final e in CreatureElement.values) {
      for (final l in [0.16, 0.10]) {
        final p = paper(e.color, l);
        final ratio = (inkLuminance + 0.05) / (p.computeLuminance() + 0.05);
        expect(ratio, greaterThan(4.5),
            reason: '${e.name} at $l is too light to read on');
      }
    }
  });

  test('each element gets its OWN page, not one shared tint', () {
    // "jeweils eine andere Ausprägung" — the whole point is that two monsters
    // of different types do not open the same beige screen.
    final pages = {
      for (final e in CreatureElement.values) paper(e.color, 0.16).toARGB32(),
    };
    expect(pages.length, greaterThan(CreatureElement.values.length ~/ 2),
        reason: 'elements are collapsing onto the same page colour');
  });

  test('the foot of the sheet is deeper than its head', () {
    for (final e in CreatureElement.values) {
      final top = paper(e.color, 0.16);
      final bottom = paper(e.color, 0.10);
      expect(bottom.computeLuminance(), lessThan(top.computeLuminance()),
          reason: '${e.name} has no gradient');
    }
  });

  test('a colourless element keeps the plain page', () {
    // Pushing saturation into something that has none would invent a colour the
    // monster does not have.
    expect(paper(const Color(0xFF808080), 0.16), const Color(0xFF1F262C));
  });
}
