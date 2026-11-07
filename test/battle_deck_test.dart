import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/battle_screen.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// The battle screen's command deck (user 2026-09-20, "Variante 7 — Reiter"):
// Attack | Items | Change are TABS of one cream card, not bottom sheets. Layout
// smoke tests at the landscape size — an overflow fails a widget test.
void main() {
  final species = SpeciesDef(
    id: 'deck_test',
    name: 'Testling',
    element: CreatureElement.fire,
    rarity: CreatureRarity.common,
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [SpeciesStage(name: 'Kit')],
  );
  setUpAll(() => kSpeciesDefs[species.id] = species);

  CreatureInstance mine(String id) => CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: species.id,
    nickname: 'Mine $id',
    gender: CreatureGender.male,
    statBase: {for (final s in CreatureStat.values) s: 20},
    statSlope: const {},
  );

  Future<void> open(WidgetTester t, {int team = 2}) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final party = [for (var i = 0; i < team; i++) mine('m$i')];
    CreaturesController().creatures = party;
    await t.pumpWidget(
      MaterialApp(
        home: BattleScreen(
          team: party,
          enemies: [Combatant.fromSpecies(species, level: 5, id: 'e0')],
        ),
      ),
    );
    // The fighters slide on before the deck accepts input; the idle bob never
    // stops, so step the clock instead of settling.
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the command bar always shows the abilities, with Items and Change', (
    t,
  ) async {
    await open(t);
    expect(find.text('Attack'), findsOneWidget); // the basic tile; no Attack tab
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('End turn'), findsOneWidget);
    expect(find.byTooltip('Type chart'), findsOneWidget);
    expect(find.text('Type chart'), findsNothing);
    // The plates carry the level now (the podium that carried the HP is gone).
    expect(find.text('L5'), findsWidgets);
    // The bar lies along the bottom edge.
    expect(t.getRect(find.text('End turn')).bottom, greaterThan(430 - 70));
  });

  testWidgets('Items and Change open their page above the bar', (t) async {
    await open(t, team: 4);

    await t.tap(find.text('Items'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('USE AN ITEM'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    // The bar stays: End turn is always one tap away.
    expect(find.text('End turn'), findsOneWidget);

    await t.tap(find.text('Change'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('SWITCH MONSTER'), findsOneWidget);
    expect(find.text('Send in'), findsWidgets);
    expect(find.byType(BottomSheet), findsNothing);

    await t.tap(find.text('Change')); // a second tap closes the page
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('USE AN ITEM'), findsNothing);
    expect(find.text('SWITCH MONSTER'), findsNothing);
    expect(find.text('End turn'), findsOneWidget);
  });

  testWidgets('a lone monster has nobody to switch to', (t) async {
    await open(t, team: 1);
    await t.tap(find.text('Change'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('No reserves left.'), findsOneWidget);
  });

  testWidgets('the (i) on a tile opens the description, a tap closes it', (
    t,
  ) async {
    await open(t);
    expect(find.textContaining('Power '), findsNothing);
    await t.tap(find.byIcon(Icons.info_outline).first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Power '), findsOneWidget);
    await t.tap(find.textContaining('Power '));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Power '), findsNothing);
  });

  testWidgets('the keys sit along the top of the field', (t) async {
    await open(t);
    final flee = t.getRect(find.byTooltip('Flee'));
    final type = t.getRect(find.byTooltip('Type chart'));
    final auto = t.getRect(find.text('AUTO'));
    // In the top strip, left to right; the field runs the full width now.
    expect(flee.top, lessThan(60));
    expect(flee.left, lessThan(20));
    expect(flee.right, lessThan(type.left));
    expect(type.right, lessThan(auto.left));
    expect(auto.right, lessThanOrEqualTo(932));
  });

  testWidgets('the waiting monsters are small tiles down the left edge', (
    t,
  ) async {
    await open(t, team: 5);
    // Three fight, two wait: two "Lv 1" tiles in the left gutter.
    final tiles = [
      for (final e in find.text('Lv 1').evaluate())
        t.getTopLeft(find.byWidget(e.widget)),
    ].where((p) => p.dx < 46).toList();
    expect(tiles, hasLength(2));
    expect(t.takeException(), isNull);
  });

  testWidgets('my side stands at the left, the enemy\'s at the right', (
    t,
  ) async {
    await open(t, team: 2);
    Offset plate(String name) => t.getCenter(find.text(name));
    final a = plate('Mine m0');
    final b = plate('Mine m1');
    final enemy = plate('Kit');
    // Side view: both of mine left of the middle, the enemy right of it, and
    // two of mine stand apart rather than shoulder to shoulder.
    expect(a.dx, lessThan(932 / 2));
    expect(b.dx, lessThan(932 / 2));
    expect(enemy.dx, greaterThan(932 / 2));
    expect((b.dx - a.dx).abs(), greaterThan(80));
  });
}
