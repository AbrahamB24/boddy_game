import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/widgets/meander_strip.dart';

// The page's bordure is drawn rather than shipped as an image, so it has to
// survive whatever height the page happens to have. The one rule that keeps it
// from looking broken: only WHOLE motifs are drawn — a shape cut in half at the
// bottom edge reads as a rendering bug.
//
// The motif itself changed four times — a Greek-key spiral became a facet
// triangle with the 2026-07-31 low-poly pass, then a plain zigzag on
// 2026-08-30, then (same day, against a reference photo: "sehr subtil und
// schlicht") a guessed single-coil spiral, then (2026-08-31, "ist noch nicht
// identisch mit dem Bild") a version measured pixel-for-pixel off that same
// reference — this rule survived all four, which is exactly why it is tested
// as a rule and not as a picture.
void main() {
  group('MeanderStrip.repeatCount', () {
    // Width 45 → one motif is (57/45) × 45 = 57pt tall exactly — the
    // reference photo's own 45px repeat over its 57px cross-section.
    test('only whole motifs count; the remainder becomes margin', () {
      expect(MeanderStrip.repeatCount(45, 56), 0);
      expect(MeanderStrip.repeatCount(45, 57), 1);
      expect(MeanderStrip.repeatCount(45, 113), 1);
      expect(MeanderStrip.repeatCount(45, 114), 2);
    });

    test('a taller dialog simply fits more of them', () {
      expect(
        MeanderStrip.repeatCount(16, 400),
        greaterThan(MeanderStrip.repeatCount(16, 200)),
      );
    });

    test('degenerate sizes draw nothing instead of a fragment', () {
      expect(MeanderStrip.repeatCount(0, 500), 0);
      expect(MeanderStrip.repeatCount(16, 0), 0);
      expect(MeanderStrip.repeatCount(-4, 500), 0);
    });
  });
}
