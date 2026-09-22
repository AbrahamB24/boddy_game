import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/creature_detail_screen.dart';
import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';

// The monster detail screen, "Glas auf Farbe" (user 2026-09-21, variant 11 with
// the tab rail of variant 3): the element colour over the whole page, the monster
// on the left, a rail of four tabs, and the tab's content as glass cards. Pumped at the game's own landscape size, so a column that does not fit
// (a RenderFlex overflow) fails here rather than on a phone.
void main() {
  final species = SpeciesDef(
    id: 'detail_test',
    name: 'Tidetest',
    element: CreatureElement.water,
    rarity: CreatureRarity.rare,
    description: 'A calm giant of the tides.',
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [
      SpeciesStage(name: 'Tiny'),
      SpeciesStage(name: 'Tidetest'),
      SpeciesStage(name: 'Big'),
    ],
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    kSpeciesDefs[species.id] = species;
    kAbilityDefs['attack'] = const AbilityDef(
      id: 'attack',
      name: 'Attack',
      element: CreatureElement.neutral,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 40,
    );
    kAbilityDefs['tide'] = const AbilityDef(
      id: 'tide',
      name: 'Tide Crash',
      description: 'A wave hits one enemy.',
      element: CreatureElement.water,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 60,
    );
  });

  CreatureInstance monster({
    int level = 12,
    List<String> equipped = const [],
  }) => CreatureInstance(
    id: 'm1',
    userId: 'u',
    speciesId: species.id,
    gender: CreatureGender.female,
    level: level,
    stage: 1,
    statBase: {for (final s in CreatureStat.values) s: 30.0},
    statSlope: {for (final s in CreatureStat.values) s: 1.5},
    currentHp: 40,
    learnedAbilityIds: equipped,
    equippedAbilityIds: equipped,
  );

  Future<void> show(WidgetTester t, CreatureInstance c) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(home: CreatureDetailScreen(previewCreature: c)),
    );
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the header carries name, level, power, rarity and element', (
    t,
  ) async {
    await show(t, monster());
    expect(find.text('Tidetest'), findsWidgets);
    expect(find.text('Lv 12'), findsOneWidget);
    expect(find.textContaining('⚡'), findsOneWidget);
    expect(find.text('Rare'), findsOneWidget);
    expect(find.textContaining('Water'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('General: Condition and About on the left, Work and Strengths '
      'on the right, both columns the same height', (t) async {
    await show(t, monster());
    expect(find.text('CONDITION'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.text('WORK'), findsOneWidget);
    expect(find.text('STRENGTHS'), findsOneWidget);
    expect(find.text('A calm giant of the tides.'), findsOneWidget);
    expect(find.text('Stage 2 of 3'), findsOneWidget);
    // Left column: Condition on top, About under it; right: Work on top.
    Rect box(String title) => t.getRect(
      find
          .ancestor(of: find.text(title), matching: find.byType(Container))
          .first,
    );
    final condition = box('CONDITION');
    final about = box('ABOUT');
    final work = box('WORK');
    final strengths = box('STRENGTHS');
    expect(condition.top, lessThan(about.top));
    expect(work.top, lessThan(strengths.top));
    expect(work.left, greaterThan(condition.right - 1));
    // Both columns end on the same line.
    expect(about.bottom, moreOrLessEquals(strengths.bottom, epsilon: 1));
    // Four strengths (statValue > 10 for every stat in the test species).
    expect(find.text('Attack'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Stats: the level and gene switches change what is shown', (
    t,
  ) async {
    await show(t, monster());
    await t.tap(find.text('Stats'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('COMBAT'), findsOneWidget);
    expect(find.text('WORK'), findsOneWidget);
    expect(find.text('EXPEDITION'), findsOneWidget);
    // Everything fits without scrolling (user 2026-09-21).
    expect(find.byType(SingleChildScrollView), findsNothing);
    // Level 12 at 30 base + 1.5 per level.
    expect(find.text('${30 + (1.5 * 11).round()}'), findsWidgets);
    await t.tap(find.text('Lv 1'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('30'), findsWidgets);
    await t.tap(find.text('Per level'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('+1.5'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'Abilities: six slots, Attack is one of them, empty ones are "+"',
    (t) async {
      await show(t, monster(equipped: ['tide']));
      await t.tap(find.text('Abilities'));
      await t.pump(const Duration(milliseconds: 200));
      // Slot 0 is Attack, slot 1 the equipped move, slots 2..5 are empty.
      expect(find.text('Attack'), findsOneWidget);
      expect(find.text('Tide Crash'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsNWidgets(4));
      expect(find.text('Empty slot'), findsNWidgets(4));
      // Three above each other on the left, three on the right.
      final attack = t.getTopLeft(find.text('Attack'));
      final tide = t.getTopLeft(find.text('Tide Crash'));
      expect(tide.dy, greaterThan(attack.dy));
      expect(tide.dx, moreOrLessEquals(attack.dx, epsilon: 1));
      final adds = find.byIcon(Icons.add);
      final xs = {
        for (var i = 0; i < 4; i++) t.getCenter(adds.at(i)).dx.round(),
      };
      expect(xs.length, 2, reason: 'two columns');
      // A preview creature is not owned, so nothing there can be changed and the
      // Combat School button is not offered.
      expect(find.textContaining('Learn new'), findsNothing);
      // Tapping the move shows what it does, without a swap list.
      await t.tap(find.text('Tide Crash'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('A wave hits one enemy.'), findsWidgets);
      expect(find.text('Empty this slot'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Evolution: the line uses the width, and a button waits for the '
      'level', (t) async {
    await show(t, monster(level: 1));
    await t.tap(find.text('Evolution'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.text('LINE'), findsOneWidget);
    expect(find.text('Level too low'), findsOneWidget);
    // A form you have not seen is blacked out and unnamed, like the Bestiary:
    // the monster is a preview at stage 2 of 3 and none of the species is owned,
    // so only its own form is named and the two others are "???".
    expect(find.text('Tidetest'), findsWidgets);
    expect(find.text('Tiny'), findsNothing);
    expect(find.text('Big'), findsNothing);
    final unseen = find.text('???');
    expect(unseen, findsNWidgets(2));
    // The three forms spread over the card: first and last far apart.
    expect(
      t.getCenter(unseen.at(1)).dx - t.getCenter(unseen.at(0)).dx,
      greaterThan(300),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('the tab rail is centred on the screen height', (t) async {
    await show(t, monster());
    // A key's symbol and word together sit at its centre.    double keyY(String symbol, String word) =>        (t.getCenter(find.text(symbol)).dy + t.getCenter(find.text(word)).dy) / 2;    final first = keyY('❤️', 'General');    final last = keyY('⚔️', 'Abilities');    expect((first + last) / 2, moreOrLessEquals(215, epsilon: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets('Stats: Combat and Expedition together are as tall as Work', (
    t,
  ) async {
    await show(t, monster());
    await t.tap(find.text('Stats'));
    await t.pump(const Duration(milliseconds: 200));
    Rect box(String title) => t.getRect(
      find
          .ancestor(of: find.text(title), matching: find.byType(Container))
          .first,
    );
    final combat = box('COMBAT');
    final expedition = box('EXPEDITION');
    final work = box('WORK');
    expect(combat.top, moreOrLessEquals(work.top, epsilon: 1));
    expect(expedition.bottom, moreOrLessEquals(work.bottom, epsilon: 1));
    expect(t.takeException(), isNull);
  });
}
