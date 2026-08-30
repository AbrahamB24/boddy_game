import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/widgets/meander_strip.dart';

// The page's bordure is drawn rather than shipped as an image, so it has to
// survive whatever height the page happens to have. The one rule that keeps it
// from looking broken: only WHOLE motifs are drawn — a shape cut in half at the
// bottom edge reads as a rendering bug.
//
// The motif itself changed twice — a Greek-key spiral became a facet triangle
// with the 2026-07-31 low-poly pass, then back to a (redrawn) Greek-key square
// spiral on 2026-08-30 ("das dreieck mäander durch das ursprüngliche viereckige
// spiralenmäander ersetzen"); this rule survived both, which is exactly why it
// is tested as a rule and not as a picture.
void main() {
  group('MeanderStrip.repeatCount', () {
    // Width 10 → one motif is 1.4 × 10 = 14pt tall.
    test('only whole motifs count; the remainder becomes margin', () {
      expect(MeanderStrip.repeatCount(10, 13), 0);
      expect(MeanderStrip.repeatCount(10, 14), 1);
      expect(MeanderStrip.repeatCount(10, 27), 1);
      expect(MeanderStrip.repeatCount(10, 28), 2);
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
