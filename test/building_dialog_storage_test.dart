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

  PlacedBuilding store(int level, {String type = 'storehouse'}) =>
      PlacedBuilding(
        id: 'b_store',
        settlementId: 's',
        buildingTypeId: type,
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

  testWidgets('a store has a Crew card', (t) async {
    await open(t);
    expect(find.text('CREW'), findsOneWidget);
  });

  testWidgets('the Castle has no Crew card — its Effects take the row', (
    t,
  ) async {
    ctrl.buildings = [store(1, type: 'castle')];
    await open(t);
    expect(find.text('CREW'), findsNothing);
    expect(find.text('EFFECTS'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'a single-purpose post says what it improves, not just a bare number '
    '(user 2026-09-29)',
    (t) async {
      // Every OTHER building in this file has exactly one workshop role, so
      // its group header never shows (it only appears with a SECOND role) —
      // this caption is the only place the effect is named at all.
      ctrl.buildings = [store(1, type: 'healing_hut')];
      final c = CreatureInstance(
        id: 'medic',
        userId: 'u',
        speciesId: 'medic',
        gender: CreatureGender.male,
        statBase: {CreatureStat.medicine: 30},
        statSlope: const {},
      )..assignedBuildingId = 'b_store';
      c.assignedStat = CreatureStat.medicine;
      CreaturesController().creatures.add(c);
      await open(t);
      expect(find.textContaining('Improves'), findsOneWidget);
      expect(find.textContaining('Healing time'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('a plain production post says the exact rate per stat point '
      '(user 2026-09-29)', (t) async {
    ctrl.buildings = [store(1, type: 'small_wood_camp')];
    await open(t);
    // small_wood_camp's role mult is 2, flat at level 1. The Effects card's
    // own row (user 2026-09-29: "production pro Statpoint muss bei Effects
    // stehen, da dies der Haupteffekt des Gebäudes ist") — label and value
    // are separate Text widgets there, same as every other Effects row.
    expect(find.text('EFFECTS'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Wood Production'), findsOneWidget);
    expect(find.text('2 per Statpoint'), findsOneWidget);
    // The Crew card's own caption still says it too, as one line.
    expect(find.text('Wood Production per Statpoint   2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a tall picture keeps the hero on screen', (t) async {
    // The scout post's art is 2.2× as tall as wide: it has to be scaled into the
    // room above the hero, not left to rise past the top of the screen.
    ctrl.buildings = [store(1, type: 'scout_post')];
    await open(t);
    expect(t.takeException(), isNull);
    final hero = t.getTopLeft(find.byType(FittedBox).first);
    expect(hero.dy, greaterThanOrEqualTo(0));
  });
}
