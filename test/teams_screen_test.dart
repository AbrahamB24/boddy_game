import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/saved_team.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';
import 'package:boddygame/features/creatures/teams_screen.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The Teams page ("Kompakte Zeilen", user 2026-09-22): one row per team, a banner
// with the team size and what it takes to get another seat. Seats per team come
// from the map alone; the number of saved teams is not limited.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('the next seat', () {
    test(
      'at 9 battles cleared the party holds 2 and seat 3 opens at battle 15',
      () {
        final next = nextPartySeat(9)!;
        expect(partySizeForBattle(10), 2);
        expect(next.size, 3);
        expect(next.battle, 15);
        // Clearing battle 14 is what lets battle 15 take three.
        expect(next.winsToGo, 5);
        expect(partySizeForBattle(9 + 1 + next.winsToGo), 3);
        expect(partySizeForBattle(9 + next.winsToGo), 2);
      },
    );

    test('a fresh player needs five wins for seat 2 at battle 6', () {
      final next = nextPartySeat(0)!;
      expect(next.size, 2);
      expect(next.battle, 6);
      expect(next.winsToGo, 5);
    });

    test('at the largest party there is no next seat', () {
      expect(nextPartySeat(10000), isNull);
    });
  });

  group('the page', () {
    CreatureInstance mob(String id, String name) => CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: 's',
      gender: CreatureGender.male,
      nickname: name,
      statBase: const {CreatureStat.hp: 50},
      statSlope: const {},
    );

    SavedTeam team(
      String id,
      String name,
      List<String> members, {
      bool active = false,
    }) => SavedTeam(
      id: id,
      userId: 'u',
      name: name,
      memberIds: members,
      isActive: active,
    );

    final creatures = CreaturesController();
    final settlement = SettlementController();

    Future<void> open(WidgetTester t, {int cleared = 9}) async {
      t.view.physicalSize = const Size(932, 430);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      settlement.battlesCleared = cleared;
      creatures.creatures
        ..clear()
        ..addAll([mob('a', 'Ash'), mob('b', 'Bea'), mob('c', 'Cy')]);
      creatures.savedTeams
        ..clear()
        ..addAll([
          team('t1', 'Steinteam', ['a', 'b'], active: true),
          team('t2', 'Boss team', ['a', 'b', 'c']),
          team('t3', 'Sprinter', ['c']),
        ]);
      addTearDown(() {
        creatures.creatures.clear();
        creatures.savedTeams.clear();
        settlement.battlesCleared = 0;
      });
      await t.pumpWidget(const MaterialApp(home: TeamsScreen()));
      await t.pump(const Duration(milliseconds: 200));
    }

    testWidgets(
      'a row per team and the New team button — nothing else on top',
      (t) async {
        await open(t);
        expect(find.text('Steinteam'), findsOneWidget);
        expect(find.text('Boss team'), findsOneWidget);
        expect(find.text('Sprinter'), findsOneWidget);
        expect(find.text('New team'), findsOneWidget);
        // The banner (team size, pips, countdown, "?") is gone.
        expect(find.text('TEAM SIZE'), findsNothing);
        expect(find.text('?'), findsNothing);
        // A locked seat on every row still says where the next one comes from.
        expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('a team past the cap says how many sit out, one under it its '
        'seats', (t) async {
      await open(t);
      expect(
        find.text('1 sits out'),
        findsOneWidget,
      ); // Boss team: 3 in 2 seats
      expect(find.text('2/2 seats'), findsOneWidget); // Steinteam
      expect(find.text('1/2 seats'), findsOneWidget); // Sprinter
      expect(t.takeException(), isNull);
    });

    testWidgets('at the largest party there is no lock and no countdown', (
      t,
    ) async {
      await open(t, cleared: 10000);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('many teams scroll instead of overflowing', (t) async {
      await open(t);
      for (var i = 0; i < 12; i++) {
        creatures.savedTeams.add(team('x$i', 'Team $i', ['a']));
      }
      creatures.notifyListeners();
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
      await t.drag(find.text('Steinteam'), const Offset(0, -400));
      await t.pump(const Duration(milliseconds: 100));
      expect(t.takeException(), isNull);
    });
  });
}
