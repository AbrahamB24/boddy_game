import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart' show IntroStep;
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/resource_detail_screen.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The resource page's "Produced by" list must add up to the rate in its header
// (user 2026-09-22: "weshalb habe ich 471 und 942 pro Stunde? Das sollte doch das
// gleiche sein"). The list applied the GLOBAL level curve to every post while the
// header ([SettlementController.workshopPower]) used each post's OWN level factor,
// so a camp whose post authors a factor showed a different figure in each place.
// A paused building stays on the list, at 0/h.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const typeId = 'test_camp';

  PlacedBuilding camp(String id, {int level = 1, bool paused = false}) =>
      PlacedBuilding(
        id: id,
        settlementId: 's',
        buildingTypeId: typeId,
        gridX: 0,
        gridY: 0,
        level: level,
        constructionSecondsRequired: 0,
        constructionSecondsBuilt: 0,
        isComplete: true,
        isPaused: paused,
        placedAt: DateTime.utc(2026),
      );

  CreatureInstance worker(String id, double gathering, String postedTo) {
    final c = CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: id,
      gender: CreatureGender.male,
      statBase: {CreatureStat.gathering: gathering},
      statSlope: const {},
    );
    c.level = 1;
    c.assignedBuildingId = postedTo;
    c.assignedStat = CreatureStat.gathering;
    return c;
  }

  late SettlementController ctrl;

  setUp(() {
    // A camp whose post has a level factor of its own (1.5 per level, where the
    // global curve is +50 % of level 1 per level).
    kBuildingDefs[typeId] = BuildingDef(
      id: typeId,
      name: 'Test Camp',
      color: const Color(0xFF000000),
      gridW: 1,
      gridH: 1,
      workshops: const [
        WorkshopRole(
          stat: CreatureStat.gathering,
          resource: 'wood',
          mult: 0.1,
          slots: 3,
          levelFactor: 1.5,
        ),
      ],
    );
    ctrl = SettlementController();
    // The tutorial window counts every building as connected — cheaper than a
    // road network, same code path.
    ctrl.introStep = IntroStep.firstNode;
    ctrl.energy = EnergyModel(
      settlementId: 's',
      energyPct: 113,
      lastUpdatedAt: DateTime.now(),
    );
    CreaturesController().creatures.clear();
  });

  tearDown(() {
    kBuildingDefs.remove(typeId);
    ctrl.buildings = [];
    ctrl.introStep = IntroStep.done;
    ctrl.energy = null;
    CreaturesController().creatures.clear();
  });

  double listed() => ctrl
      .productionSourcesByBuilding('wood')
      .fold<double>(0, (a, s) => a + s.$3);

  test('the rows add up to the header rate, energy applied on top', () {
    ctrl.buildings = [camp('b1', level: 5)];
    CreaturesController().creatures.add(worker('w', 40, 'b1'));

    // 40 gathering × 0.1 × 1.5^4 — the post's own factor, not the global curve.
    expect(listed(), closeTo(40 * 0.1 * 5.0625, 1e-9));
    expect(
      ctrl.hourlyRates['wood'],
      closeTo(listed() * ctrl.energy!.multiplier, 1e-9),
    );
    // …and the by-type list agrees with the per-building one.
    expect(
      ctrl.productionSources('wood').fold<double>(0, (a, s) => a + s.amount),
      closeTo(listed(), 1e-9),
    );
  });

  test('a paused building is listed at 0/h and changes nothing else', () {
    ctrl.buildings = [camp('b1', level: 2), camp('b2', level: 3, paused: true)];
    CreaturesController().creatures.add(worker('w1', 30, 'b1'));
    CreaturesController().creatures.add(worker('w2', 30, 'b2'));

    final rows = ctrl.productionSourcesByBuilding('wood');
    expect(rows.map((r) => r.$1.id), containsAll(['b1', 'b2']));
    final paused = rows.firstWhere((r) => r.$1.id == 'b2');
    expect(paused.$1.isPaused, isTrue);
    expect(paused.$3, 0);
    // The header is the running camp alone.
    expect(
      ctrl.hourlyRates['wood'],
      closeTo(listed() * ctrl.energy!.multiplier, 1e-9),
    );
    // A paused building that could not make wood at all is not listed.
    ctrl.buildings = [camp('b1'), camp('b2', paused: true)];
    expect(ctrl.productionSourcesByBuilding('stone'), isEmpty);
  });

  testWidgets('the resource page shows the paused camp as 0/h', (t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ctrl.resources = ResourceModel(
      settlementId: 's',
      wood: 100,
      stone: 0,
      gold: 0,
      lastUpdatedAt: DateTime.now(),
    );
    ctrl.buildings = [camp('b1', level: 2), camp('b2', level: 3, paused: true)];
    CreaturesController().creatures.add(worker('w1', 30, 'b1'));
    await t.pumpWidget(
      const MaterialApp(
        home: ResourceDetailScreen(
          resourceId: 'wood',
          emoji: '🪵',
          title: 'Wood',
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('0/h'), findsOneWidget);
    expect(find.text('Lv 3 · Paused'), findsOneWidget);
    expect(find.text('Lv 2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
