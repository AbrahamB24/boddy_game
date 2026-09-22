import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart' show IntroStep;
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';
import 'package:boddygame/features/settlement/sheets/building_detail_dialog.dart';

// The Storehouse's dialog (user 2026-09-22): "Sobald Monster eingestellt sind,
// wird nicht mehr alles korrekt angezeigt, da es zu wenig Platz hat". Storage is
// a grid of small tiles now — the staff's share is a second line inside a tile,
// not a second line per good — so posting monsters cannot push the card past its
// height, and a card that still does not fit scrolls instead of shrinking.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  PlacedBuilding store(int level) => PlacedBuilding(
    id: 'b_store',
    settlementId: 's',
    buildingTypeId: 'storehouse',
    gridX: 0,
    gridY: 0,
    level: level,
    constructionSecondsRequired: 0,
    constructionSecondsBuilt: 0,
    isComplete: true,
    placedAt: DateTime.utc(2026),
  );

  CreatureInstance logistician(String id) {
    final c = CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: id,
      gender: CreatureGender.male,
      statBase: {CreatureStat.logistics: 30},
      statSlope: const {},
    );
    c.level = 1;
    c.assignedBuildingId = 'b_store';
    c.assignedStat = CreatureStat.logistics;
    return c;
  }

  late SettlementController ctrl;

  setUp(() {
    ctrl = SettlementController();
    ctrl.buildings = [store(2)];
    ctrl.introStep = IntroStep.firstNode; // every building counts as connected
    CreaturesController().creatures.clear();
  });

  tearDown(() {
    ctrl.buildings = [];
    ctrl.introStep = IntroStep.done;
    CreaturesController().creatures.clear();
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showBuildingDetailDialog(context, ctrl, ctrl.buildings.first),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a store with staff posted lays out without overflow and keeps '
      'its text at full size', (t) async {
    CreaturesController().creatures
      ..add(logistician('w1'))
      ..add(logistician('w2'));
    await open(t);
    // The staff's share is on the tiles.
    expect(find.textContaining('👷'), findsWidgets);
    expect(t.takeException(), isNull);
    // Not shrunk to fit: the 9.5 px share line keeps (at least) its own height.
    expect(t.getSize(find.textContaining('👷').first).height, greaterThan(9));
  });

  testWidgets('a paused building says so in a pill and greys its picture', (
    t,
  ) async {
    ctrl.buildings = [store(2).copyWith(isPaused: true)];
    await open(t);
    expect(find.text('⏸️ Paused'), findsOneWidget);
    expect(find.byType(ColorFiltered), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('a running building has no pill', (t) async {
    await open(t);
    expect(find.text('⏸️ Paused'), findsNothing);
  });

  testWidgets('an empty store shows the same tiles, one line each', (t) async {
    await open(t);
    expect(find.textContaining('👷'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
