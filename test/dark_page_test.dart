import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/features/common/widgets/filter_pills.dart';
import 'package:boddygame/features/common/widgets/parchment_page.dart';
import 'package:boddygame/features/settlement/widgets/scroll_paper.dart'
    show kPageShadow, kParchmentDeep, kParchmentInk, kParchmentLight,
        kParchmentMid, kParchmentShade;

// ── Die ganze App im Dark Mode (user 2026-07-31) ────────────
// "setzte das ganze app in den darkmode"
//
// Flipped in the PALETTE, not screen by screen: every name in it carries a role
// (bg, panelMid, border, textDim, "the ink"), so a screen that asked for the
// card surface got the dark card surface without knowing anything changed. What
// that leans on — and what is pinned here — is that the roles stayed coherent
// after the flip. A palette where "ink" is darker than the page it is written on
// compiles perfectly and is unreadable.
double contrast(Color fg, Color bg) {
  final a = fg.computeLuminance() + 0.05;
  final b = bg.computeLuminance() + 0.05;
  return a > b ? a / b : b / a;
}

void main() {
  test('the surfaces are dark, and stepped in the right order', () {
    for (final c in [FoE.bg, FoE.panelDark, FoE.panelMid, FoE.panelLight]) {
      expect(c.computeLuminance(), lessThan(0.1), reason: '$c is not dark');
    }
    // The ladder the whole chrome rests on: the page is deepest, a card sits on
    // it, a raised/active thing sits on that.
    expect(FoE.panelMid.computeLuminance(),
        greaterThan(FoE.bg.computeLuminance()));
    expect(FoE.panelLight.computeLuminance(),
        greaterThan(FoE.panelMid.computeLuminance()));
  });

  test('text reads on every surface it can land on', () {
    for (final surface in [FoE.bg, FoE.panelDark, FoE.panelMid, FoE.panelLight]) {
      expect(contrast(FoE.parchment, surface), greaterThan(7),
          reason: 'body text on $surface');
      expect(contrast(FoE.textDim, surface), greaterThan(3.5),
          reason: 'secondary text on $surface');
      expect(contrast(FoE.goldBright, surface), greaterThan(4.5),
          reason: 'the accent on $surface');
      expect(contrast(FoE.danger, surface), greaterThan(3),
          reason: 'danger on $surface');
    }
  });

  test('the page stock is dark and its ink is light', () {
    // The flip that carries most of the app: kParchmentInk is a ROLE ("what you
    // write with"), and screens use it both as text and as a wash.
    for (final c in [
      kParchmentLight,
      kParchmentMid,
      kParchmentDeep,
      kParchmentShade,
    ]) {
      expect(c.computeLuminance(), lessThan(0.1), reason: '$c is not dark');
    }
    expect(contrast(kParchmentInk, kParchmentLight), greaterThan(7));
  });

  test('a shadow is still darker than what it falls on', () {
    // Every cast shadow in the app used to be the ink at a low alpha. With the
    // ink now cream, that would have painted a pale halo under every card —
    // hence kPageShadow.
    expect(kPageShadow.computeLuminance(),
        lessThan(FoE.bg.computeLuminance()));
  });

  testWidgets('the page is one page again — no light/dark branch', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ParchmentPage(title: 'Monsters', child: SizedBox.expand()),
      ),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, kParchmentMid);
    expect(find.byType(ParchmentHeader), findsOneWidget);
    expect(find.text('Monsters'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the pills read on the page they sit on', () {
    final p = PillPalette.parchment;
    // The fill is the ink at 6 %, so it is TRANSLUCENT: measured on its own it
    // is the same colour as the text and reads as 1:1 contrast. What a player
    // sees is the fill composited over the page, which is what this composes.
    final fill = Color.alphaBlend(p.fill, kParchmentLight);
    expect(contrast(p.ink, fill), greaterThan(4.5));
    expect(contrast(p.accent, p.menuSurface), greaterThan(3));
  });
}
