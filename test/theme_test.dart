import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/core/ui/phone_frame.dart';

void main() {
  // The design direction is "modern chrome, pixel sprites" (see foe_theme.dart).
  // These pin the rules that a future restyle keeps tripping over — the pixel
  // pass left hard offset shadows and 12px tap targets behind, and they only
  // showed up on a device.
  group('design tokens', () {
    // ── LOW POLY (user 2026-07-31) ──
    // "alles soll im low poly flatdesign sein, so wie dieses Monster"
    //
    // Faceted meant three things: corners CUT, surfaces ONE flat tone, and a
    // shadow a hard offset rather than a blur.
    //
    // ── The corners went back to curves (user 2026-08-04) ──
    // "Bringe wieder mehr Rundungen ins UI, so ist es zu extrem." The other two
    // properties are untouched and still pinned below — flat fills and hard
    // shadows were never the problem. What did not survive was the chamfer at
    // panel scale: on a monster it is one facet among dozens, on a full-width
    // card it is two long diagonals repeated down the screen.
    RoundedRectangleBorder shapeOf(ShapeDecoration d) =>
        d.shape as RoundedRectangleBorder;

    test('panels and buttons are flat — no decorative shadow', () {
      expect(FoE.panel().shadows, anyOf(isNull, isEmpty));
      expect(FoE.panel(glow: true).shadows, anyOf(isNull, isEmpty));
      expect(FoE.btn().shadows, anyOf(isNull, isEmpty));
      expect(FoE.btn(active: true).shadows, anyOf(isNull, isEmpty));
    });

    test('every corner is a CURVE, not a cut', () {
      // One shape for the whole app, whichever shape that is. The value of
      // pinning it has never been the bevel — it is that a single screen
      // cannot quietly pick a different corner from everything around it.
      expect(FoE.panel().shape, isA<RoundedRectangleBorder>());
      expect(FoE.btn().shape, isA<RoundedRectangleBorder>());
      expect(FoE.facet(), isA<RoundedRectangleBorder>());
    });

    test('a panel is ONE tone — a gradient cannot be flat shading', () {
      expect(FoE.panel().gradient, isNull);
      expect(FoE.panel().color, FoE.panelMid);
      // The gradient tokens that survive for compatibility are flat in value.
      expect(FoE.panelGradient.colors.toSet(), hasLength(1));
      expect(FoE.topBarGradient.colors.toSet(), hasLength(1));
      expect(FoE.goldGradient.colors.toSet(), hasLength(1));
    });

    test('a shadow is an offset facet, never a blur', () {
      for (final s in FoE.drop()) {
        expect(s.blurRadius, 0);
        expect(s.offset, isNot(Offset.zero));
      }
    });

    test('panel() honours the radius it is given', () {
      final r = shapeOf(FoE.panel(radius: 18)).borderRadius as BorderRadius;
      expect(r.topLeft.x, 18);
    });

    test('the curve is generous, and the default is the shared token', () {
      // The radii went back UP with the shape. A 10-px cut is a dramatic
      // chamfer; a 10-px round is barely visible, so carrying the bevel's
      // numbers over would have read as square rather than as soft.
      expect(FoE.radius, greaterThanOrEqualTo(14));
      expect(FoE.radiusSmall, lessThan(FoE.radius));
      final r = shapeOf(FoE.panel()).borderRadius as BorderRadius;
      expect(r.topLeft.x, FoE.radius);
    });

    test('touch targets are thumb-sized', () {
      expect(FoE.tapTarget, greaterThanOrEqualTo(44));
    });

    test('body text stays legible against the background', () {
      // Cheap luminance check, not a full WCAG pass: textDim on bg was the
      // exact bug reported from the first playtest ("cannot be read"). Absolute
      // contrast, since the app is a LIGHT theme now (dark ink on parchment) —
      // the sign flipped, the requirement did not.
      double lum(Color c) => c.computeLuminance();
      expect((lum(FoE.parchment) - lum(FoE.bg)).abs(), greaterThan(0.4));
      expect((lum(FoE.textDim) - lum(FoE.bg)).abs(), greaterThan(0.15));
    });

    test('the accent reads as an accent, not as body text', () {
      expect(FoE.gold, isNot(FoE.parchment));
      expect(FoE.goldBright.computeLuminance(),
          greaterThan(FoE.gold.computeLuminance()));
    });
  });

  group('PhoneFrame', () {
    testWidgets('is a no-op at phone width — no letterboxing on a device',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        const MaterialApp(home: PhoneFrame(child: SizedBox.expand())),
      );
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('frames a desktop window to phone width', (tester) async {
      tester.view.physicalSize = const Size(2500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late Size seen;
      await tester.pumpWidget(
        MaterialApp(
          home: PhoneFrame(
            child: Builder(
              builder: (context) {
                seen = MediaQuery.of(context).size;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      // The app must BELIEVE it is phone-sized: code reading MediaQuery.size
      // would otherwise lay out for a 2500px window that no player has.
      expect(seen.width, FoE.phoneMaxWidth);
      expect(seen.height, lessThanOrEqualTo(932));
      expect(find.byType(ClipRRect), findsOneWidget);
    });
  });

  // ── Die Facetten-Stufen (user 2026-07-31) ──
  // A faceted object is shaded by its NEIGHBOURS: one plane catches the light,
  // the next turns away, and the edge between them is the whole effect. These
  // two make that edge from any colour — and they have to be blunt enough to
  // read, or the app quietly goes back to looking airbrushed.
  group('facet steps', () {
    test('lit is lighter, shade is darker, and both by a visible amount', () {
      for (final c in [FoE.panelMid, FoE.bg, FoE.gold, FoE.positive]) {
        expect(FoE.lit(c).computeLuminance(), greaterThan(c.computeLuminance()));
        expect(FoE.shade(c).computeLuminance(), lessThan(c.computeLuminance()));
        // A 4 % lift is a gradient's idea of a facet; this has to be a step.
        final spread =
            FoE.lit(c).computeLuminance() - FoE.shade(c).computeLuminance();
        expect(spread, greaterThan(0.02), reason: '$c has no facet edge');
      }
    });

    test('black and white stay put rather than overflowing', () {
      expect(FoE.shade(const Color(0xFF000000)), const Color(0xFF000000));
      expect(FoE.lit(const Color(0xFFFFFFFF)), const Color(0xFFFFFFFF));
    });
  });
}
