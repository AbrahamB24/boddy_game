import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/settlement/crafting_screen.dart';
import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/models/settlement.dart';
import 'package:boddygame/features/settlement/services/crafting.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The Crafting page (user 2026-09-20, "Variante 4, Kategorien + Detail"): a rail
// of groups, the recipes of the chosen group, and the chosen recipe in full —
// with an ask-first dialog when the store falls short.
void main() {
  // The first recipe of the first rail button, with named ingredients so its
  // cost does not depend on what happens to be in store.
  final def = kItemDefs.values.firstWhere(
    (d) => craftGroupOf(d.kind) == CraftGroup.heal && d.ingredients.isNotEmpty,
  );

  Future<void> open(
    WidgetTester t, {
    required double stockOfEach,
    int stage = 3,
  }) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = SettlementController();
    s.dungeonMaxStage = stage;
    s.resources = ResourceModel(
      settlementId: 's',
      wood: 100,
      stone: 100,
      gold: 100,
      goods: {for (final id in def.ingredients.keys) id: stockOfEach},
      lastUpdatedAt: DateTime(2026),
    );
    s.settlement = SettlementModel(
      id: 's',
      userId: 'u',
      name: 'S',
      eraIndex: 1,
      mainBuildingLevel: 1,
      createdAt: DateTime(2026),
    );
    CreaturesController().creatures = [];
    await t.pumpWidget(const MaterialApp(home: CraftingScreen()));
    await t.pump();
    // Choose the recipe in the list (its name is also in the detail card).
    await t.tap(find.text(def.name).first);
    await t.pumpAndSettle();
  }

  testWidgets('shows the rail, the recipes and the chosen one in full', (
    t,
  ) async {
    await open(t, stockOfEach: 1000);
    expect(find.text('Heal'), findsWidgets);
    expect(find.text('INGREDIENTS'), findsOneWidget);
    expect(find.text('You can make'), findsOneWidget);
    expect(find.text('Craft'), findsOneWidget);
  });

  testWidgets('with nobody at the benches it says so and offers Work', (
    t,
  ) async {
    await open(t, stockOfEach: 1000);
    expect(find.textContaining('Nobody is at the benches'), findsOneWidget);
    expect(find.text('Open Work'), findsOneWidget);
    expect(find.textContaining('0 crafters'), findsOneWidget);
  });

  testWidgets('Craft queues one when the store covers it — no question', (
    t,
  ) async {
    await open(t, stockOfEach: 1000);
    await t.tap(find.text('Craft'));
    await t.pumpAndSettle();
    expect(find.textContaining('Not enough'), findsNothing);
    expect(SettlementController().craftJobs.map((j) => j.itemId), [def.id]);
  });

  testWidgets('the stepper orders several at once', (t) async {
    await open(t, stockOfEach: 1000);
    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    await t.tap(find.text('Craft ×3'));
    await t.pumpAndSettle();
    expect(SettlementController().craftJobs, hasLength(3));
  });

  testWidgets('when the store falls short it asks first, then can queue', (
    t,
  ) async {
    await open(t, stockOfEach: 0);
    await t.tap(find.text('Craft'));
    await t.pumpAndSettle();
    expect(find.textContaining('Not enough'), findsOneWidget);
    expect(SettlementController().craftJobs, isEmpty);

    // Cancel changes nothing.
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(SettlementController().craftJobs, isEmpty);

    // Queue anyway puts it in the line.
    await t.tap(find.text('Craft'));
    await t.pumpAndSettle();
    await t.tap(find.text('Queue it'));
    await t.pumpAndSettle();
    expect(SettlementController().craftJobs.map((j) => j.itemId), [def.id]);
  });
}
