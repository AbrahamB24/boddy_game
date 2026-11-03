import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/breeding_screen.dart';
import 'package:boddygame/features/creatures/hatchery_screen.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/common/widgets/recess_bar.dart';

// "New Pair" with both parents chosen (user 2026-09-29: "New Pair kann nicht
// mehr gelesen werden, da alles viel zu klein ist"). The panel used to stack
// the tiles ABOVE a 14-row table, which forced a scale-to-fit step down to
// under half size on the app's real 932×430 screen. Now the tiles sit beside
// a two-column, 7-row table instead — this pins that it renders at a legible
// size, not shrunk, and every row still fits (no horizontal overflow either).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final def = SpeciesDef(
    id: 'pair_layout_test',
    name: 'Pairling',
    element: CreatureElement.water,
    rarity: CreatureRarity.common,
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [SpeciesStage(name: 'Kit')],
  );
  setUp(() => kSpeciesDefs[def.id] = def);
  tearDown(() => kSpeciesDefs.remove(def.id));

  CreatureInstance mon(String id, CreatureGender g) {
    final c = CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: def.id,
      nickname: id,
      gender: g,
      statBase: {for (final s in CreatureStat.values) s: 20},
      statSlope: {for (final s in CreatureStat.values) s: 2},
    );
    c.level = 10;
    return c;
  }

  testWidgets('both parents chosen: no overflow, no scale-down, real bars', (
    t,
  ) async {
    final a = mon('ParentA', CreatureGender.male);
    final b = mon('ParentB', CreatureGender.female);
    CreaturesController().creatures = [a, b];
    addTearDown(() => CreaturesController().creatures = []);

    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: BreedingPane())));
    await t.pump(const Duration(milliseconds: 200));

    // Fill slot A, then slot B.
    await t.tap(find.text('Choose').first);
    await t.pumpAndSettle();
    await t.tap(find.text('ParentA'));
    await t.pumpAndSettle();
    // Preview-then-confirm (2026-10-05 picker unification).
    await t.tap(find.text('Choose this parent'));
    await t.pumpAndSettle();

    await t.tap(find.text('Choose').first);
    await t.pumpAndSettle();
    await t.tap(find.text('ParentB'));
    await t.pumpAndSettle();
    // Preview-then-confirm (2026-10-05 picker unification).
    await t.tap(find.text('Choose this parent'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    // The table is on screen — bars actually render with real width, not
    // squeezed to nothing by a too-narrow split.
    final bars = find.byType(RecessBar);
    expect(bars, findsWidgets);
    for (final bar in bars.evaluate()) {
      expect(t.getSize(find.byWidget(bar.widget)).width, greaterThan(8));
    }
    // A gene value is readable — not scaled down past legible size the way
    // the old stacked layout forced it to be. Both parents share the same
    // base/slope, so every stat reads 20 + 2×9 = 38 at level 10.
    final geneValue = find.text('38');
    expect(geneValue, findsWidgets);
    expect(t.getSize(geneValue.first).height, greaterThan(9));
  });

  testWidgets(
    'the REAL nested context (title bar + tab switcher chrome, not a bare '
    'Scaffold) still renders at full size',
    (t) async {
      // The bare-Scaffold test above gives the panel more height than it
      // actually gets in the app — HatcheryScreen's own title card and tab
      // switcher both eat into it first. This is what the player really sees.
      final a = mon('ParentA', CreatureGender.male);
      final b = mon('ParentB', CreatureGender.female);
      CreaturesController().creatures = [a, b];
      addTearDown(() => CreaturesController().creatures = []);

      t.view.physicalSize = const Size(932, 430);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        const MaterialApp(home: HatcheryScreen(startOn: NurseryTab.breeding)),
      );
      await t.pump(const Duration(milliseconds: 200));

      await t.tap(find.text('Choose').first);
      await t.pumpAndSettle();
      await t.tap(find.text('ParentA'));
      await t.pumpAndSettle();
      // Preview-then-confirm (2026-10-05 picker unification).
      await t.tap(find.text('Choose this parent'));
      await t.pumpAndSettle();
      await t.tap(find.text('Choose').first);
      await t.pumpAndSettle();
      await t.tap(find.text('ParentB'));
      await t.pumpAndSettle();
      // Preview-then-confirm (2026-10-05 picker unification).
      await t.tap(find.text('Choose this parent'));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      final geneValue = find.text('38');
      expect(geneValue, findsWidgets);
      // FoE.value(size: 12) renders a 12 px font at a ~16 px line height —
      // this is that exact height, i.e. NOT scaled down at the app's own
      // landscape size.
      expect(
        t.getSize(geneValue.first).height,
        moreOrLessEquals(16, epsilon: 1),
      );
    },
  );
}
