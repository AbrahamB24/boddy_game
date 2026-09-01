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
// Four things, and each one is a test below: the crew is its own view, a +
// opens the roster, the roster is ranked by THIS post's stat, and a monster
// posted somewhere else says where.

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

// The + tiles fill any empty seat, so the first one found always opens the
// plain "Add" roster (not a swap) as long as the post isn't already full.
Future<void> _tapAdd(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
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

  group('view 1 answers "who works here"', () {
    testWidgets('it lists ONLY the crew of this post', (tester) async {
      await _pump(tester);
      expect(find.text('worker'), findsOneWidget);
      // The other three are candidates, not crew — the old sheet showed all
      // four at once and made you hunt for the gold border.
      for (final id in ['ace', 'rookie', 'busy']) {
        expect(find.text(id), findsNothing, reason: id);
      }
    });

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

  group('a + tile opens the roster', () {
    testWidgets('it shows the candidates and hides the crew', (tester) async {
      await _pump(tester);
      await _tapAdd(tester);
      for (final id in ['ace', 'rookie', 'busy']) {
        expect(find.text(id), findsOneWidget, reason: id);
      }
      expect(find.text('worker'), findsNothing, reason: 'already posted');
    });

    testWidgets('it is ranked by THIS post\'s stat, best first',
        (tester) async {
      await _pump(tester);
      await _tapAdd(tester);
      // Tiles now, same grid as the crew's own seats (user 2026-08-30: "die
      // genau gleichen Kacheln verwenden") — three candidates fit one row, so
      // rank reads left to right instead of top to bottom.
      double x(String id) => tester.getTopLeft(find.text(id)).dx;
      // 40 > 25 > 5.
      expect(x('ace'), lessThan(x('busy')));
      expect(x('busy'), lessThan(x('rookie')));
    });

    testWidgets('back returns to the crew view', (tester) async {
      await _pump(tester);
      await _tapAdd(tester);
      // The app's own back icon now (2026-08-31 audit), not the bespoke
      // Icons.arrow_back this sheet used to draw by hand.
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
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
      // is still a real, pickable option.
      expect(find.text('worker'), findsOneWidget);
      expect(find.text('ace'), findsOneWidget);
    });

    testWidgets('picking a candidate replaces the seat, not adds to it',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ace'));
      await tester.pumpAndSettle();
      // Back on the crew view: still one seat filled, now by ace.
      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.text('ace'), findsOneWidget);
      expect(find.text('worker'), findsNothing);
    });

    testWidgets('Remove from post vacates the seat with no replacement',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('worker'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from post'));
      await tester.pumpAndSettle();
      expect(find.text('0 / 3'), findsOneWidget);
      expect(find.text('worker'), findsNothing);
    });

    testWidgets('an empty tile offers no Remove from post',
        (tester) async {
      await _pump(tester);
      await _tapAdd(tester);
      expect(find.text('Remove from post'), findsNothing);
    });
  });

  group('a monster working elsewhere is marked', () {
    testWidgets('by NAME, on a filled badge — taking it costs that building',
        (tester) async {
      await _pump(tester);
      await _tapAdd(tester);
      expect(find.text('Works in Saw Mill'), findsOneWidget);
      // …and a free monster carries no such badge.
      expect(find.textContaining('Works in'), findsOneWidget);
    });

    testWidgets('the action says TRANSFER, not add', (tester) async {
      // The green + would promise a free hire. Taking this monster empties a
      // post somewhere else, and the icon has to say so.
      await _pump(tester);
      await _tapAdd(tester);
      expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
      // ace + rookie are free hires; busy is the transfer.
      expect(find.byIcon(Icons.add), findsNWidgets(2));
    });

    testWidgets('being AWAY outranks the posting — it cannot work at all',
        (tester) async {
      CreaturesController().expeditionIds.add('busy');
      await _pump(tester);
      await _tapAdd(tester);
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
