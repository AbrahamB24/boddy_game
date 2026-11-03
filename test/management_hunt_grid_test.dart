import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/expedition_launch_sheet.dart';
import 'package:boddygame/features/creatures/expeditions_screen.dart';
import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/creatures/services/expedition_controller.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart' show IntroStep;
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The Management page's composer (user 2026-10-02, "Konzept 24" of ten
// full-hub proposals: creating an expedition is the screen's whole job now).
// A type switch picks Gather vs Hunt, a chip row picks the specific target,
// and the SAME [ExpeditionLaunchPanel] every tile used to open as a sheet
// renders right below it, inline — see expedition_launch_sheet.dart's own
// doc comment. "Out now" only shows up once something IS out.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  AreaDef area(String id, int stage, {int order = 1}) => AreaDef(
    id: id,
    name: 'Region $id',
    emoji: '🌲',
    order: order,
    battleStage: stage,
    spots: [
      ResourceSpotDef(id: '${id}_wood', resource: 'wood'),
      ResourceSpotDef(id: '${id}_stone', resource: 'stone'),
      ResourceSpotDef(id: '${id}_fish', resource: 'fish'),
    ],
  );

  PlacedBuilding built(String id, String type) => PlacedBuilding(
    id: id,
    settlementId: 's',
    buildingTypeId: type,
    gridX: 0,
    gridY: 0,
    level: 1,
    constructionSecondsRequired: 0,
    constructionSecondsBuilt: 0,
    isComplete: true,
    placedAt: DateTime.utc(2026),
  );

  late SettlementController ctrl;

  setUp(() {
    ctrl = SettlementController();
    ctrl.dungeonMaxStage = 1;
    ctrl.introStep = IntroStep.firstNode; // every building counts as connected
    ctrl.buildings = [
      built('b1', 'small_wood_camp'),
      built('b2', 'small_quarry'),
      built('b3', 'fish_shop'),
      // A level-1 Scout Post already grants 1 expedition slot and 1 hunt
      // option (its own levelSteps start at level 3) — exactly "one open,
      // five locked", and a slot to actually send with.
      built('b4', 'scout_post'),
    ];
  });

  tearDown(() {
    kAreaDefs.clear();
    ctrl.buildings = [];
    ctrl.dungeonMaxStage = 1;
    ctrl.introStep = IntroStep.done;
    ExpeditionController().expeditions = [];
  });

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpeditionsBody())),
    );
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
    'with a resource unlocked, the composer opens on Gather — its chips, '
    'and a live preview panel, both show',
    (t) async {
      kAreaDefs['a1'] = area('a1', 1);
      await pump(t);
      expect(find.text('NEW EXPEDITION'), findsOneWidget);
      expect(find.text('⛏️ Gather'), findsOneWidget);
      expect(find.text('🪤 Hunt'), findsOneWidget);
      expect(find.textContaining('Wood'), findsOneWidget);
      expect(find.textContaining('Stone'), findsOneWidget);
      expect(find.textContaining('Fish'), findsOneWidget);
      // The same panel every chip used to open as a sheet is already here,
      // inline, with no tap needed.
      expect(find.byType(ExpeditionLaunchPanel), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'switching to Hunt: a level-1 Scout Post opens the first two tiers, the '
    'rest are locked',
    (t) async {
      kAreaDefs['a1'] = area('a1', 1);
      await pump(t);
      await t.tap(find.text('🪤 Hunt'));
      await t.pumpAndSettle();

      // The 5 real step tiers.
      expect(find.text('500 Schritte'), findsOneWidget);
      expect(find.text('1.000 Schritte'), findsOneWidget);
      expect(find.text('2.000 Schritte'), findsOneWidget);
      expect(find.text('5.000 Schritte'), findsOneWidget);
      expect(find.text('10.000 Schritte'), findsOneWidget);
      // maxHuntOptionCount adds a base of 1 to the Scout Post's own count (1
      // at level 1), so 2 are open and 3 are locked.
      expect(find.text('Locked'), findsNWidgets(3));
      // The inline panel is already showing the first (open) tier — no
      // second sheet to open or dismiss any more.
      expect(find.byType(ExpeditionLaunchPanel), findsOneWidget);

      // A locked tier does nothing — the chip already says why.
      await t.tap(find.text('10.000 Schritte'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(ExpeditionLaunchPanel), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'many regions worth of gather targets still render without overflowing',
    (t) async {
      for (var i = 0; i < 6; i++) {
        kAreaDefs['a$i'] = area('a$i', 1, order: i + 1);
      }
      await pump(t);
      expect(find.byType(ExpeditionLaunchPanel), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'nothing out: the composer gets the whole card, no "Out now" rail',
    (t) async {
      kAreaDefs['a1'] = area('a1', 1);
      await pump(t);
      expect(find.text('OUT NOW'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'one trip out: a slim "Out now" rail appears beside the composer',
    (t) async {
      kAreaDefs['a1'] = area('a1', 1);
      ExpeditionController().expeditions = [
        Expedition(
          id: 'e1',
          userId: 'u',
          type: ExpeditionType.gather,
          areaId: 'a1',
          targetId: 'a1_wood',
          startedAt: DateTime.now().toUtc(),
          duration: const Duration(minutes: 30),
          payload: const {'resource': 'wood', 'amount': 40.0},
        ),
      ];
      await pump(t);
      expect(find.text('OUT NOW'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      // The composer is still here too — it never disappears, the rail just
      // joins it.
      expect(find.text('NEW EXPEDITION'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
