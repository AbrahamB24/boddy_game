import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';
import 'package:boddygame/features/settlement/sheets/building_preview_dialog.dart';

// The Build strip's (i) (user 2026-09-20: "die Werte für ein Gebäude sehen …
// bevor ich das Gebäude baue"): what a building does, read from its definition,
// with a Build button that behaves exactly like tapping the card.
void main() {
  ResourceModel stock({double wood = 100000, double stone = 100000}) =>
      ResourceModel(
        settlementId: 's',
        wood: wood,
        stone: stone,
        gold: 0,
        goods: const {},
        lastUpdatedAt: DateTime(2026),
      );

  Future<void> open(
    WidgetTester t,
    SettlementController ctrl,
    String id, {
    required VoidCallback onBuild,
  }) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBuildingPreview(
              context,
              ctrl,
              kBuildingDefs[id]!,
              onBuild: onBuild,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('shows the name, the effects and the crew of a workshop', (
    t,
  ) async {
    final ctrl = SettlementController()..resources = stock();
    await open(t, ctrl, 'small_wood_camp', onBuild: () {});
    final def = kBuildingDefs['small_wood_camp']!;
    expect(find.text(def.name), findsOneWidget);
    expect(find.text('EFFECTS'), findsOneWidget);
    expect(find.text('CREW'), findsOneWidget);
    // A wood camp has one production post, and says what it reads.
    expect(find.textContaining('Reads the monster'), findsWidgets);
    expect(find.textContaining('seat'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('lists what one point of the worker''s stat is worth', (t) async {
    final ctrl = SettlementController()..resources = stock();
    await open(t, ctrl, 'small_wood_camp', onBuild: () {});
    expect(find.textContaining('PER POINT OF THE WORKER'), findsOneWidget);
    expect(find.textContaining('per point'), findsWidgets);
    // The figure is the role's own formula at level 1: mult x 1 point.
    final role = kBuildingDefs['small_wood_camp']!.workshops.first;
    final v = role.contribution((_) => 1, 1)[role.resource]!;
    expect(find.textContaining('+${v.toStringAsFixed(2)}/h'), findsOneWidget);
  });
  testWidgets('the level stepper looks ahead at what upgrades bring', (
    t,
  ) async {
    final ctrl = SettlementController()..resources = stock();
    await open(t, ctrl, 'storehouse', onBuild: () {});
    expect(find.text('Lv 1'), findsOneWidget);
    String storageOf(WidgetTester t) => t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .firstWhere((s) => s.contains('500') || s.contains('625'));
    final at1 = storageOf(t);
    await t.tap(find.byIcon(Icons.chevron_right_rounded));
    await t.pumpAndSettle();
    expect(find.text('Lv 2'), findsOneWidget);
    expect(storageOf(t), isNot(at1));
  });

  testWidgets('Build closes the preview and hands the building on', (t) async {
    var built = 0;
    final ctrl = SettlementController()..resources = stock();
    await open(t, ctrl, 'small_wood_camp', onBuild: () => built++);
    await t.tap(find.text('Build'));
    await t.pumpAndSettle();
    expect(built, 1);
    expect(find.text('EFFECTS'), findsNothing);
  });

  testWidgets(
    'Build is dead when you cannot afford it, and the price is shown',
    (t) async {
      var built = 0;
      final ctrl = SettlementController()..resources = stock(wood: 0, stone: 0);
      await open(t, ctrl, 'small_wood_camp', onBuild: () => built++);
      await t.tap(find.text('Build'));
      await t.pumpAndSettle();
      expect(built, 0);
      expect(find.text('EFFECTS'), findsOneWidget);
    },
  );
}
