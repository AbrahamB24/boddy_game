import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/settlement/build_menu_request.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';
import 'package:boddygame/features/settlement/work_screen.dart';

// The Work page has two halves (user 2026-09-20, "Variante 1, Zwei Reiter"):
// Work, and Housing — which used to be a page of its own.
void main() {
  PlacedBuilding castle() => PlacedBuilding(
    id: 'castle1',
    settlementId: 's',
    buildingTypeId: kFallbackBuildingDefs.values
        .firstWhere((d) => d.isMainBuilding)
        .id,
    gridX: 0,
    gridY: 0,
    level: 1,
    constructionSecondsRequired: 0,
    constructionSecondsBuilt: 0,
    isComplete: true,
    placedAt: DateTime(2026),
  );

  Future<void> open(
    WidgetTester t, {
    WorkTab startOn = WorkTab.work,
    bool withCastle = true,
  }) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = SettlementController();
    s.dungeonMaxStage = 1;
    s.resources = ResourceModel(
      settlementId: 's',
      wood: 0,
      stone: 0,
      lastUpdatedAt: DateTime(2026),
    );
    s.buildings = withCastle ? [castle()] : [];
    CreaturesController().creatures = [];
    await t.pumpWidget(MaterialApp(home: WorkScreen(startOn: startOn)));
    await t.pumpAndSettle();
  }

  testWidgets('opens on Work, with a Housing tab beside it', (t) async {
    await open(t);
    expect(find.text('Housing'), findsOneWidget); // the tab
    expect(find.text('housing used'), findsNothing);
    expect(find.textContaining('seats staffed'), findsOneWidget);
  });

  testWidgets('the Housing tab shows the budget and the dwellings', (t) async {
    await open(t);
    await t.tap(find.text('Housing'));
    await t.pumpAndSettle();
    expect(find.text('housing used'), findsOneWidget);
    expect(find.text('free rooms'), findsOneWidget);
    expect(find.text('Build a house'), findsOneWidget);
    expect(find.textContaining('HOUSES'), findsOneWidget);
    // The castle shelters, and says so is all there is.
    expect(find.textContaining('Only the Castle houses'), findsOneWidget);
  });

  testWidgets('a door to Housing (the header cell) opens that tab', (
    t,
  ) async {
    await open(t, startOn: WorkTab.housing);
    expect(find.text('housing used'), findsOneWidget);
  });

  testWidgets('with nothing sheltering it says to build a house', (t) async {
    await open(t, startOn: WorkTab.housing, withCastle: false);
    expect(find.textContaining('Nothing shelters monsters yet'), findsOneWidget);
  });

  testWidgets('Build a house asks the map for the Housing category', (
    t,
  ) async {
    await open(t, startOn: WorkTab.housing);
    final before = BuildMenuRequest.requests.value;
    await t.tap(find.text('Build a house'));
    await t.pumpAndSettle();
    expect(BuildMenuRequest.requests.value, before + 1);
    expect(BuildMenuRequest.category, BuildingCategory.housing);
  });
}
