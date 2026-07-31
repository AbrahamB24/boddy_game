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
    // Faceted means three things, and all three are properties of the tokens
    // rather than of any screen: corners are CUT, surfaces are ONE flat tone,
    // and a shadow is a hard offset rather than a blur.
    BeveledRectangleBorder shapeOf(ShapeDecoration d) =>
        d.shape as BeveledRectangleBorder;

    test('panels and buttons are flat — no decorative shadow', () {
      expect(FoE.panel().shadows, anyOf(isNull, isEmpty));
      expect(FoE.panel(glow: true).shadows, anyOf(isNull, isEmpty));
      expect(FoE.btn().shadows, anyOf(isNull, isEmpty));
      expect(FoE.btn(active: true).shadows, anyOf(isNull, isEmpty));
    });

    test('every corner is a CUT, not a curve', () {
      // The single most recognisable low-poly move — and the reason the radius
      // tokens could stay: a bevel takes the same number a round would.
      expect(FoE.panel().shape, isA<BeveledRectangleBorder>());
      expect(FoE.btn().shape, isA<BeveledRectangleBorder>());
      expect(FoE.facet(), isA<BeveledRectangleBorder>());
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

    test('the cut is sharp, and the default is the shared token', () {
      // Smaller than the rounded values they replaced: a 16-px CUT is a
      // dramatic chamfer where a 16-px round was a soft pill.
      expect(FoE.radius, lessThanOrEqualTo(12));
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
}
