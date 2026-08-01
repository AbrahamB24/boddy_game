import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/features/creatures/battle_screen.dart';

// ── Der Kampfscreen, neu (user 2026-08-01) ──────────────────
// "designe den Kampfscreen komplett neu, so dass er modern wirkt, aber trotzdem
//  den gleichen Stil verfolgt"
//
// The screen cannot be pumped here (it builds a live CombatEngine from a team),
// so what is pinned is the thing that made it stop having a style in the first
// place: it carried TWO designs behind a flag, and half of every decision was
// made twice.
void main() {
  test('there is one look — the polished/classic flag is gone', () {
    // A static toggle on the widget was how the second design stayed alive. If
    // it ever comes back, this fails to compile rather than rotting quietly.
    expect(
      BattleScreen.new,
      isA<Function>(),
      reason: 'the constructor still exists; only the skin flag went',
    );
  });

  test('the chrome takes its shapes from the app, not its own', () {
    // Everything the redesign draws — tiles, plates, queue cards, AP chips —
    // is cut with FoE.facet and lifted with FoE.drop. Pinning the tokens is
    // what keeps the battle screen from drifting into a private style again.
    expect(FoE.facet(), isA<BeveledRectangleBorder>());
    for (final s in FoE.drop()) {
      expect(s.blurRadius, 0, reason: 'a faceted world casts no fog');
    }
    expect(FoE.lit(FoE.panelMid).computeLuminance(),
        greaterThan(FoE.panelMid.computeLuminance()));
  });
}
