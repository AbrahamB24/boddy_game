import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/services/overworld_layout.dart'
    show OverworldNodeState;
import 'package:boddygame/features/creatures/services/star_overview.dart';
import 'package:boddygame/features/creatures/widgets/overworld_card.dart';
import 'package:boddygame/features/creatures/widgets/star_row.dart';
import 'package:boddygame/features/creatures/widgets/stars_overview.dart';

// The star pieces at the landscape size (932 x 430): none of them may overflow.
void main() {
  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await t.pump();
  }

  Icon star(WidgetTester t, int i) => t.widget<Icon>(
    find.descendant(
      of: find.byType(StarRow).first,
      matching: find.byWidgetPredicate((w) => w is Icon),
    ).at(i),
  );

  testWidgets('a star row lights exactly as many stars as it is given', (
    t,
  ) async {
    await pump(t, const Center(child: StarRow(count: 2)));
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
    final lit = [for (var i = 0; i < 3; i++) star(t, i).color];
    expect(lit[0], lit[1]);
    expect(lit[2], isNot(lit[0]));
  });

  testWidgets('the fight card shows the best stars of a cleared battle', (
    t,
  ) async {
    await pump(
      t,
      SizedBox(
        width: 330,
        height: 400,
        child: OverworldFightCard(
          battleNumber: 7,
          isBoss: false,
          state: OverworldNodeState.done,
          stars: 2,
          enemies: null,
          rewards: const [],
          onFight: () {},
        ),
      ),
    );
    expect(find.byType(StarRow), findsOneWidget);
    expect(find.textContaining('★★★'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a locked battle shows no stars', (t) async {
    await pump(
      t,
      SizedBox(
        width: 330,
        height: 400,
        child: OverworldFightCard(
          battleNumber: 9,
          isBoss: false,
          state: OverworldNodeState.locked,
          enemies: null,
          rewards: const [],
          onFight: null,
        ),
      ),
    );
    expect(find.byType(StarRow), findsNothing);
  });

  testWidgets('the overview lays out its regions and the rules', (t) async {
    final regions = [
      RegionStars(
        region: 1,
        name: 'Green Hollow',
        earned: 7,
        max: 15,
        reached: true,
        battles: [
          for (var i = 1; i <= 5; i++)
            BattleStarsEntry(
              battle: i,
              stars: i <= 3 ? 3 - (i % 2) : 0,
              isBoss: i == 5,
              cleared: i <= 3,
            ),
        ],
      ),
      const RegionStars(
        region: 2,
        name: 'Stone Reach',
        earned: 0,
        max: 18,
        reached: false,
        battles: [],
      ),
    ];
    await pump(
      t,
      Padding(
        padding: const EdgeInsets.all(16),
        child: StarsOverviewBody(regions: regions),
      ),
    );
    expect(find.text('Green Hollow'), findsOneWidget);
    expect(find.textContaining('7 / 15'), findsOneWidget);
    expect(find.textContaining('not reached yet'), findsOneWidget);
    expect(find.textContaining('★★★'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
