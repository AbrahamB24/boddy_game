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

  testWidgets('the deck opens on Attack: actor, tiles, info, End turn', (
    t,
  ) async {
    await open(t);
    expect(find.text('Attack'), findsWidgets); // the tab and the basic tile
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('End turn'), findsOneWidget);
    // The type chart moved to a round key in the top bar (user 2026-09-21), so
    // the ability description has the room it used to take.
    expect(find.byTooltip('Type chart'), findsOneWidget);
    expect(find.text('Type chart'), findsNothing);
    // And the way to a description is said out loud, with an (i) on the tiles.
    expect(find.textContaining('Tap the (i)'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsWidgets);
    expect(find.text('Lv 5'), findsWidgets);
  });

  testWidgets('Items and Change are tabs, not sheets', (t) async {
    await open(t, team: 4);

    await t.tap(find.text('Items'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('USE AN ITEM'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('End turn'), findsNothing);

    await t.tap(find.text('Change'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('SWITCH MONSTER'), findsOneWidget);
    expect(find.text('Send in'), findsWidgets);
    expect(find.byType(BottomSheet), findsNothing);

    await t.tap(find.text('Attack').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('End turn'), findsOneWidget);
  });

  testWidgets('a lone monster has nobody to switch to', (t) async {
    await open(t, team: 1);
    await t.tap(find.text('Change'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('No reserves left.'), findsOneWidget);
  });

  testWidgets('the info box describes the picked ability', (t) async {
    await open(t);
    expect(find.textContaining('Power '), findsOneWidget);
    await t.longPress(find.text('Attack').last);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Power '), findsOneWidget);
  });

  testWidgets('the keys sit at the arena\'s top right, beside the deck', (
    t,
  ) async {
    await open(t);
    final flee = t.getRect(find.byTooltip('Flee'));
    final type = t.getRect(find.byTooltip('Type chart'));
    final auto = t.getRect(find.text('AUTO'));
    // In the top strip, left to right, and inside the arena (the deck is the
    // right-hand 317 px).
    expect(flee.top, lessThan(60));
    // Flee has the top LEFT corner of the arena to itself.
    expect(flee.left, lessThan(20));
    expect(flee.right, lessThan(type.left));
    expect(type.right, lessThan(auto.left));
    expect(auto.right, lessThan(932 - 317));
    // The deck runs to the top too: its first tab is near the screen's top edge.
    expect(t.getRect(find.text('Attack').first).top, lessThan(45));
  });

  testWidgets('the waiting monsters are small tiles down the left, mine under '
      'the log', (t) async {
    await open(t, team: 5);
    // Three fight, two wait: two "Lv 1" tiles in the left gutter, below the seam.
    final tiles = [
      for (final e in find.text('Lv 1').evaluate())
        t.getTopLeft(find.byWidget(e.widget)),
    ].where((p) => p.dx < 46).toList();
    expect(tiles, hasLength(2));
    for (final p in tiles) {
      expect(p.dy, greaterThan(215));
    }
    // The lone enemy has nobody waiting behind it.
    expect(t.takeException(), isNull);
  });

  testWidgets('two monsters stand apart, not shoulder to shoulder', (t) async {
    await open(t, team: 2);
    // The plates under the platforms (exact names, low on the screen) — the log
    // line may also carry a monster's name.
    Offset plate(String name) => [
      for (final e in find.text(name).evaluate())
        t.getCenter(find.byWidget(e.widget)),
    ].firstWhere((p) => p.dy > 380);
    final a = plate('Mine m0');
    final b = plate('Mine m1');
    // A slot is a third of the rank (~170 px); the two used to sit exactly one
    // slot apart, now there is a gap on top of that.
    expect((b.dx - a.dx).abs(), greaterThan(220));
  });
}
