import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/widgets/type_chart_screen.dart';

// The type chart ("Ring, auswählbar", user 2026-09-22): the ring of the eight real
// types with the arrows of ONE selected type, and a card that says the same in
// words — all of it read off CreatureElement.multiplierVs.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> open(WidgetTester t, {CreatureElement? initial}) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: TypeChartScreen(initial: initial)));
    await t.pump(const Duration(milliseconds: 200));
  }

  Finder heading(String name) => find.byWidgetPredicate(
    (w) => w is Text && w.data == name && w.style?.fontSize == 23,
  );

  test('the chart holds the eight real types, never Neutral', () {
    expect(kChartTypes, hasLength(8));
    expect(kChartTypes, isNot(contains(CreatureElement.neutral)));
  });

  test('the lists are the matrix, strongest first', () {
    const f = CreatureElement.fire;
    expect(typesHitHard(f), [
      CreatureElement.plant, // ×1.5
      CreatureElement.ice, // ×1.25
      CreatureElement.shadow, // ×1.25
    ]);
    expect(typesHitWeak(f), [
      CreatureElement.stone, // ×0.75
      CreatureElement.water, // ×0.5
    ]);
    expect(typesHittingHard(f), [
      CreatureElement.water, // ×1.5
      CreatureElement.stone, // ×1.25
    ]);
    // Every listed pair really is an advantage / a disadvantage.
    for (final a in kChartTypes) {
      for (final b in typesHitHard(a)) {
        expect(a.multiplierVs(b), greaterThan(1));
      }
      for (final b in typesHitWeak(a)) {
        expect(a.multiplierVs(b), lessThan(1));
      }
      for (final b in typesHittingHard(a)) {
        expect(b.multiplierVs(a), greaterThan(1));
      }
    }
  });

  testWidgets('opens on Fire with its three lists, without overflow', (
    t,
  ) async {
    await open(t);
    expect(find.text('🛡 Type chart'), findsOneWidget);
    expect(heading('Fire'), findsOneWidget);
    expect(find.text('HITS HARD'), findsOneWidget);
    expect(find.text('HITS WEAK'), findsOneWidget);
    expect(find.text('IS HIT HARD BY'), findsOneWidget);
    // Plant is Fire's ×1.5 target.
    expect(find.text('×1.5'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('in a fight it opens on the enemy\'s own type', (t) async {
    await open(t, initial: CreatureElement.water);
    expect(heading('Water'), findsOneWidget);
    expect(heading('Fire'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a type in the ring selects it', (t) async {
    await open(t);
    // The ring is the left card, so its emoji come first in the tree.
    await t.tap(find.text('💧').first);
    await t.pump(const Duration(milliseconds: 400));
    expect(heading('Water'), findsOneWidget);
    expect(heading('Fire'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('every type fits the page', (t) async {
    for (final e in kChartTypes) {
      // A fresh page each time — the same widget type would keep its state.
      await t.pumpWidget(const SizedBox());
      await open(t, initial: e);
      expect(heading(e.label), findsOneWidget, reason: e.label);
      expect(t.takeException(), isNull, reason: e.label);
    }
  });
}
