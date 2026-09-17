import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/placed_building.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';
import 'package:boddygame/features/settlement/widgets/assign_workers_sheet.dart';

// The work-post sheet, rebuilt on 2026-07-26: "Ich brauche sicher eine Anzeige,
// welche bereits hier arbeiten und einen Plus Button um hinzuzufügen. Die
// Monster werden dann nach ihrem entsprechenden Stat geordnet angezeigt, wobei
// diese, welche am Arbeiten sind an einem anderen Ort speziell markiert werden."
//
// Four things, and each one is a test below: the crew is its own section, the
// roster (everyone else) is ranked by THIS post's stat and always on screen
// beneath it, and a monster posted somewhere else says where.
//
// ONE CONTINUOUS LIST since 2026-09-06 ("sehe ich aktuell noch zu wenig,
// welche Monster aktuell im Gebäude arbeiten, welche frei sind, welche
// anderso arbeiten und welchen Stat sie haben") — the roster used to be its
// own view behind an "Add" tap; it is a dense list of rows under the crew
// grid now, with no tap needed to see it.

const _camp = 'camp';
const _mill = 'mill';

PlacedBuilding _placed(String id, String type, {int gridX = 0, int gridY = 0}) =>
    PlacedBuilding(
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
  final rx = hx + hallDef.gridW, ry = hy;
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
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final camp =
      SettlementController().buildings.firstWhere((b) => b.id == 'b_camp');
  await tester.pumpWidget(
    MaterialApp(
      // A Scaffold, not the sheet bare (2026-08-31): the real app only ever
      // opens this via showModalBottomSheet, whose route wraps the builder
      // in a Material — which the sort pill's PopupMenuButton needs and a
      // bare `home:` does not provide.
      home: Scaffold(
        body: AssignWorkersSheet(
          ctrl: SettlementController(),
          building: camp,
          role: _role,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// The roster (everyone else) sits below the crew grid now, always on screen
// — a helper for the handful of tests that still need to scroll a row into
// view before tapping it (the sheet is a fixed-height DraggableScrollableSheet
// in test, so a row past the crew grid + section header can start off the
// visible viewport).
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

  group('the crew section shows only who works here', () {
    testWidgets('the seat count is the headline', (tester) async {
      await _pump(tester);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('an empty post says what that costs', (tester) async {
      CreaturesController().creatures.removeWhere((c) => c.id == 'worker');
      await _pump(tester);
      expect(find.textContaining('produces nothing'), findsOneWidget);
    });

    testWidgets('a full post offers no + tile', (tester) async {
      CreaturesController().creatures
        ..clear()
        ..addAll([
          for (var i = 0; i < 3; i++)
            _mob('w$i', production: 10, postedTo: 'b_camp'),
        ]);
      await _pump(tester);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      expect(find.text('3 / 3'), findsOneWidget);
    });

    // User 2026-08-30: "'+ Kacheln' angezeigt werden in der Anzahl der
    // Plätze" — one tile per seat, not one button for however many are free.
    testWidgets('there is one + tile per FREE seat', (tester) async {
      await _pump(tester);
      // 1 posted of 3 → 2 free tiles.
      expect(find.byIcon(Icons.add_circle_outline), findsNWidgets(2));
    });

    testWidgets('a filled seat is its own tile, named', (tester) async {
      await _pump(tester);
      expect(find.text('worker'), findsOneWidget);
    });
  });

  group('the roster (everyone else) is always visible', () {
    testWidgets('it lists every other monster without any tap',
        (tester) async {
      await _pump(tester);
      for (final id in ['ace', 'rookie', 'busy']) {
        expect(find.text(id), findsOneWidget, reason: id);
      }
      // The crew's own tile is unaffected — still on screen too.
      expect(find.text('worker'), findsOneWidget);
    });

    testWidgets('it is ranked by THIS post\'s stat, best first',
        (tester) async {
      await _pump(tester);
      // Dense ROWS now, stacked top to bottom (user 2026-09-06), not tiles
      // in a row — rank reads top to bottom instead of left to right.
      double y(String id) => tester.getTopLeft(find.text(id)).dy;
      // 40 > 25 > 5.
      expect(y('ace'), lessThan(y('busy')));
      expect(y('busy'), lessThan(y('rookie')));
    });
  });

  group('a filled tile opens the roster to swap', () {
    testWidgets('tapping the posted monster opens Swap, named', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      expect(find.text('Swap worker'), findsOneWidget);
      // The roster lists every available monster, including the one just
      // tapped off the seat (user 2026-08-30: "inkl. dem abgewählten") — it
      // is still a real, pickable option, so "worker" shows TWICE now that
      // the crew grid stays on screen too: the still-filled seat tile, and
      // its own roster row (2026-09-06's merged list — the old two-view
      // sheet hid the crew grid behind the roster, so it only ever showed
      // once).
      expect(find.text('worker'), findsNWidgets(2));
      expect(find.text('ace'), findsOneWidget);
    });

    testWidgets('picking a candidate replaces the seat, not adds to it',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('ace'));
      // One seat filled, now by ace — and worker is back to being a plain
      // roster row (unposted, so exactly once, not the crew tile any more).
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('ace'), findsOneWidget);
      expect(find.text('worker'), findsOneWidget);
    });

    testWidgets('Remove from post vacates the seat with no replacement',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Remove from post'));
      expect(find.text('0 / 3'), findsOneWidget);
      // Unposted now, so it is a plain roster row — present once, not as a
      // crew tile.
      expect(find.text('worker'), findsOneWidget);
    });

    testWidgets('tapping an empty tile clears a pending swap instead',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      expect(find.text('Remove from post'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_circle_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('Remove from post'), findsNothing);
    });
  });

  group('a monster working elsewhere is marked', () {
    testWidgets('by NAME, on a filled badge — taking it costs that building',
        (tester) async {
      await _pump(tester);
      expect(find.text('Works in Saw Mill'), findsOneWidget);
      // …and a free monster carries no such badge.
      expect(find.textContaining('Works in'), findsOneWidget);
    });

    testWidgets('the action says TRANSFER, not add', (tester) async {
      // The green + would promise a free hire. Taking this monster empties a
      // post somewhere else, and the icon has to say so.
      await _pump(tester);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      // ace + rookie are free hires; busy is the transfer.
      expect(find.byIcon(Icons.add), findsNWidgets(2));
    });

    testWidgets('being AWAY outranks the posting — it cannot work at all',
        (tester) async {
      CreaturesController().expeditionIds.add('busy');
      await _pump(tester);
      expect(find.text('🎒 Away'), findsOneWidget);
      expect(find.textContaining('Works in'), findsNothing);
    });

    testWidgets('a posted monster that is away is flagged in the CREW view too',
        (tester) async {
      // The failure this catches: the post looks staffed and yields nothing.
      CreaturesController().expeditionIds.add('worker');
      await _pump(tester);
      expect(find.textContaining('no output'), findsOneWidget);
    });
  });
}
