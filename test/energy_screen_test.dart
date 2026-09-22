import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/energy_screen.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The Energy page ("Batterie", user 2026-09-22): the pool as a battery of 25 cells
// of 5 %, three figures under it, and a Steps card that says what you walked, what
// is missing and how the rules work.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> open(WidgetTester t, double pct, {int steps = 3200}) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SettlementController().energy = EnergyModel(
      settlementId: 's',
      energyPct: pct,
      stepsToday: steps,
      lastUpdatedAt: DateTime.now(),
    );
    await t.pumpWidget(const MaterialApp(home: EnergyScreen()));
    await t.pump(const Duration(milliseconds: 200));
  }

  test('steps to a target follow the same rules as energyAfterSteps', () {
    // Empty to 100 % is the full-steps dial; to the ceiling it is the boost part
    // on top (5 000 + 5 000 with the shipped dials).
    expect(stepsToReach(0, 100), kEnergyFullSteps.round());
    expect(stepsToReach(100, 100), 0);
    expect(stepsToReach(kEnergyMaxPercent, kEnergyMaxPercent), 0);
    for (final from in [0.0, 37.5, 100.0, 110.0]) {
      final n = stepsToReach(from, kEnergyMaxPercent);
      expect(
        energyAfterSteps(from, n),
        moreOrLessEquals(kEnergyMaxPercent, epsilon: 0.05),
        reason: 'from $from',
      );
      // One step fewer does not get there yet.
      expect(
        energyAfterSteps(from, n - 1),
        lessThan(kEnergyMaxPercent),
        reason: 'from $from',
      );
    }
  });

  test('a countdown is written the way a person says it', () {
    expect(hoursWords(18), '18 h');
    expect(hoursWords(5.5), '5 h 30 min');
    expect(hoursWords(0.75), '45 min');
    expect(hoursWords(0), '0 min');
    expect(hoursWords(double.infinity), '∞');
  });

  testWidgets('shows the battery, the figures and the step rules without '
      'overflow', (t) async {
    await open(t, 108);
    expect(find.text('⚡ Energy'), findsOneWidget);
    expect(find.text('ENERGY POOL'), findsOneWidget);
    expect(find.text('108 %'), findsWidgets);
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('until empty'), findsOneWidget);
    expect(find.text('production factor'), findsOneWidget);
    expect(find.text('×1.08'), findsOneWidget);
    // Steps card: what was walked, what is missing, the rules.
    expect(find.text('3 200'), findsOneWidget);
    expect(find.text('steps today'), findsOneWidget);
    expect(find.text('To 100 %'), findsOneWidget);
    expect(find.text('reached'), findsOneWidget);
    expect(find.textContaining('fill it from 0 to 100 %'), findsOneWidget);
    expect(find.textContaining('lost'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('the battery is FILLED: a full cell per 5 %, the rest partial', (
    t,
  ) async {
    await open(t, 106);
    // The fill of a cell is a FractionallySizedBox with a real width and height.
    final fills = find.byType(FractionallySizedBox);
    // 106 % = 21 full cells (105 %) + one cell 20 % full = 22 filled cells.
    expect(fills, findsNWidgets(22));
    for (var i = 0; i < 22; i++) {
      final size = t.getSize(fills.at(i));
      expect(size.width, greaterThan(3), reason: 'cell $i has no width');
      expect(size.height, greaterThan(1), reason: 'cell $i has no height');
    }
    // The partial cell is lower than a full one.
    expect(
      t.getSize(fills.at(21)).height,
      lessThan(t.getSize(fills.at(0)).height),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('a full pool says that steps are lost', (t) async {
    await open(t, kEnergyMaxPercent);
    expect(find.textContaining('Full — steps you take now are lost'), findsOne);
    expect(find.text('Top'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('an empty pool says what it still runs at', (t) async {
    await open(t, 0, steps: 0);
    expect(find.textContaining('Empty. Production and building'), findsOne);
    expect(find.text('×0.25'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
