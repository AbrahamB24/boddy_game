import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boddygame/core/theme/cream_kit.dart' show EmptySeat;

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/settlement/assign_workers_screen.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The work-post page ("Sitze + Liste", user 2026-09-22 — a bottom sheet before),
// first rebuilt on 2026-07-26: "Ich brauche sicher eine Anzeige, welche bereits
// hier arbeiten und einen Plus Button um hinzuzufügen. Die Monster werden dann
// nach ihrem entsprechenden Stat geordnet angezeigt, wobei diese, welche am
// Arbeiten sind an einem anderen Ort speziell markiert werden."
//
// Four things, and each one is a test below: the seats are their own card, the
// roster (everyone else) is ranked by THIS post's stat and always on screen
// beneath it, a monster posted somewhere else says where, and a seat says what
// its monster makes here per hour.

const _camp = 'camp';
const _mill = 'mill';

PlacedBuilding _placed(
  String id,
  String type, {
  int gridX = 0,
  int gridY = 0,
}) => PlacedBuilding(
  id: id,
  settlementId: 's',
  buildingTypeId: type,
  gridX: gridX,
  gridY: gridY,
  level: 1,
  constructionSecondsRequired: 0,
  constructionSecondsBuilt: 0,
  isComplete: true,
  placedAt: DateTime.utc(2026),
);

// A swap actually PERSISTS an assignment (not just pre-seeded test fixture
// state), and assignCreatureToWorkshop refuses that unless the building is
// connected to the Main Hall by road — same layout pattern as
// heal_direct_to_treatment_test.dart. Camp sits right of the road, mill below
// it, both touching the same road cell.
List<PlacedBuilding> _connectedLayout() {
  final hallDef = kBuildingDefs.values.firstWhere((d) => d.isMainBuilding);
  final roadDef = kBuildingDefs.values.firstWhere((d) => d.isRoad);
  const hx = 10, hy = 10;
  // in front of the hall's EAST GATE, four cells down its side (the road
  // network starts at the gates, user 2026-11-03)
  final rx = hx + hallDef.gridW, ry = hy + 4;
  return [
    _placed('hall', hallDef.id, gridX: hx, gridY: hy),
    _placed('road', roadDef.id, gridX: rx, gridY: ry),
    _placed('b_camp', _camp, gridX: rx + 1, gridY: ry),
    _placed('b_mill', _mill, gridX: rx, gridY: ry + 1),
  ];
}

CreatureInstance _mob(
  String id, {
  required int production,
  int level = 5,
  String? postedTo,
}) {
  final c = CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: id,
    gender: CreatureGender.male,
    statBase: {CreatureStat.production: production.toDouble()},
    statSlope: const {},
  );
  c.level = level;
  if (postedTo != null) {
    c.assignedBuildingId = postedTo;
    c.assignedStat = CreatureStat.production;
  }
  return c;
}

const _role = WorkshopRole(
  stat: CreatureStat.production,
  resource: 'wood',
  slots: 3,
);

BuildingDef _def(String id, String name) => BuildingDef(
  id: id,
  name: name,
  color: const Color(0xFF000000),
  gridW: 1,
  gridH: 1,
  workshops: const [_role],
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(932, 430);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final camp = SettlementController().buildings.firstWhere(
    (b) => b.id == 'b_camp',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: AssignWorkersScreen(
        ctrl: SettlementController(),
        building: camp,
        role: _role,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// A row past the seats card can start below the visible list; scroll it into view
// before tapping it.
Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    kBuildingDefs
      ..[_camp] = _def(_camp, 'Lumber Camp')
      ..[_mill] = _def(_mill, 'Saw Mill');
    SettlementController().buildings = _connectedLayout();
    CreaturesController().creatures
      ..clear()
      ..addAll([
        _mob('worker', production: 18, postedTo: 'b_camp'),
        _mob('ace', production: 40),
        _mob('rookie', production: 5),
        _mob('busy', production: 25, postedTo: 'b_mill'),
      ]);
    CreaturesController().expeditionIds.clear();
  });

  tearDown(() {
    CreaturesController().creatures.clear();
    CreaturesController().expeditionIds.clear();
    SettlementController().buildings = [];
    kBuildingDefs
      ..remove(_camp)
      ..remove(_mill);
  });

  group('the seats show only who works here', () {
    testWidgets('the seat count is the headline', (tester) async {
      await _pump(tester);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty post says what that costs', (tester) async {
      CreaturesController().creatures.removeWhere((c) => c.id == 'worker');
      await _pump(tester);
      expect(find.textContaining('produces nothing'), findsOneWidget);
    });

    testWidgets('a full post offers no free seat', (tester) async {
      CreaturesController().creatures
        ..clear()
        ..addAll([
          for (var i = 0; i < 3; i++)
            _mob('w$i', production: 10, postedTo: 'b_camp'),
        ]);
      await _pump(tester);
      expect(find.byType(EmptySeat), findsNothing);
      expect(find.text('3 / 3'), findsOneWidget);
    });

    // User 2026-08-30: one seat per place, not one button for however many are
    // free.
    testWidgets('there is one free seat per FREE seat', (tester) async {
      await _pump(tester);
      expect(find.byType(EmptySeat), findsNWidgets(2));
    });

    testWidgets('a filled seat is named and says what it makes here', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('worker'), findsOneWidget);
      // The post's total and the seat's own figure are per-hour, wood.
      expect(find.text('TOTAL HERE'), findsOneWidget);
      expect(find.textContaining('/h 🪵'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the roster (everyone else) is always visible', () {
    testWidgets('it lists every other monster without any tap', (tester) async {
      await _pump(tester);
      for (final id in ['ace', 'rookie', 'busy']) {
        expect(find.text(id), findsOneWidget, reason: id);
      }
      // The seat's own monster is unaffected — still on screen too.
      expect(find.text('worker'), findsOneWidget);
    });

    testWidgets('it is ranked by THIS post\'s stat, best first', (
      tester,
    ) async {
      await _pump(tester);
      double y(String id) => tester.getTopLeft(find.text(id)).dy;
      // 40 > 25 > 5.
      expect(y('ace'), lessThan(y('busy')));
      expect(y('busy'), lessThan(y('rookie')));
    });
  });

  group('a filled seat opens the roster to swap', () {
    testWidgets('tapping the posted monster starts a swap, named', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Swapping worker'), findsOneWidget);
      // The roster lists every available monster, including the one just
      // tapped off the seat (user 2026-08-30: "inkl. dem abgewählten") — so
      // "worker" shows TWICE: the still-filled seat and its own roster row.
      expect(find.text('worker'), findsNWidgets(2));
      expect(find.text('ace'), findsOneWidget);
    });

    testWidgets('picking a candidate replaces the seat, not adds to it', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('ace'));
      // Preview-then-confirm (2026-10-05): the row tap only previews ace in
      // the detail panel; its gold button is what performs the swap.
      await _tapVisible(tester, find.text('Swap in'));
      // One seat filled, now by ace — and worker is back to being a plain
      // roster row (unposted, so exactly once, not the seat any more).
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('ace'), findsOneWidget);
      expect(find.text('worker'), findsOneWidget);
    });

    testWidgets('the seat\'s ✕ vacates it with no replacement', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('remove-worker')));
      await tester.pumpAndSettle();
      expect(find.text('0 / 3'), findsOneWidget);
      // Unposted now, so it is a plain roster row — present once, not a seat.
      expect(find.text('worker'), findsOneWidget);
    });

    testWidgets('tapping an empty seat clears a pending swap instead', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Swapping worker'), findsOneWidget);
      await tester.tap(find.byType(EmptySeat).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Swapping'), findsNothing);
    });
  });

  group('a monster working elsewhere is marked', () {
    testWidgets('by NAME, on a pill — taking it costs that building', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('At Saw Mill'), findsOneWidget);
      // …and a free monster says so.
      expect(find.text('Free'), findsWidgets);
    });

    testWidgets('the action says TRANSFER, not add', (tester) async {
      // A plain plus would promise a free hire. Taking this monster empties a
      // post somewhere else, and the icon has to say so.
      await _pump(tester);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      // ace + rookie are free hires; busy is the transfer. (The two free seats
      // wear a + of their own, so four in all.)
      expect(find.byType(EmptySeat), findsNWidgets(2));
      expect(find.byIcon(Icons.add), findsNWidgets(4));
    });

    testWidgets('being AWAY outranks the posting — it cannot work at all', (
      tester,
    ) async {
      CreaturesController().expeditionIds.add('busy');
      await _pump(tester);
      expect(find.text('🎒 Away'), findsOneWidget);
      expect(find.text('At Saw Mill'), findsNothing);
    });

    testWidgets('a posted monster that is away is flagged on its SEAT too', (
      tester,
    ) async {
      // The failure this catches: the post looks staffed and yields nothing.
      CreaturesController().expeditionIds.add('worker');
      await _pump(tester);
      expect(find.textContaining('no output'), findsOneWidget);
    });
  });
}
