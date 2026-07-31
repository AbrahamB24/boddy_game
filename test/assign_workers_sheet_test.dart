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

PlacedBuilding _placed(String id, String type) => PlacedBuilding(
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
  await tester.pumpWidget(
    MaterialApp(
      home: AssignWorkersSheet(
        ctrl: SettlementController(),
        building: _placed('b_camp', _camp),
        role: _role,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAdd(WidgetTester tester) async {
  await tester.tap(find.text('Add a monster'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    kBuildingDefs
      ..[_camp] = _def(_camp, 'Lumber Camp')
      ..[_mill] = _def(_mill, 'Saw Mill');
    SettlementController().buildings = [
      _placed('b_camp', _camp),
      _placed('b_mill', _mill),
    ];
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

    testWidgets('a full post offers no + button', (tester) async {
      CreaturesController().creatures
        ..clear()
        ..addAll([
          for (var i = 0; i < 3; i++)
            _mob('w$i', production: 10, postedTo: 'b_camp'),
        ]);
      await _pump(tester);
      expect(find.text('Add a monster'), findsNothing);
      expect(find.text('Every seat taken'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('the free seats read as a sub-line, like Upgrade\'s cost',
        (tester) async {
      // User 2026-07-26: "monster hinzufügen bitte genau gleich gestalten" —
      // the count belongs on the button's second line, not packed into its
      // label, exactly as the building dialog's Upgrade button does it.
      await _pump(tester);
      expect(find.text('Add a monster'), findsOneWidget);
      expect(find.text('2 seats free'), findsOneWidget);
    });

    testWidgets('one free seat is singular', (tester) async {
      CreaturesController().creatures.add(
            _mob('second', production: 9, postedTo: 'b_camp'),
          );
      await _pump(tester);
      expect(find.text('1 seat free'), findsOneWidget);
    });
  });

  group('the + button opens the roster', () {
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
      double y(String id) => tester.getTopLeft(find.text(id)).dy;
      // 40 > 25 > 5.
      expect(y('ace'), lessThan(y('busy')));
      expect(y('busy'), lessThan(y('rookie')));
      expect(find.textContaining('Ranked by'), findsOneWidget);
    });

    testWidgets('back returns to the crew view', (tester) async {
      await _pump(tester);
      await _tapAdd(tester);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
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
