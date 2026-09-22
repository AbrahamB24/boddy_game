import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/battle_rewards.dart';
import 'package:boddygame/features/creatures/services/overworld_layout.dart'
    show OverworldNodeState;
import 'package:boddygame/features/creatures/widgets/overworld_card.dart';

// The Overworld's fight card (user 2026-09-20, "Variante 4 … nur die wichtigen
// Informationen: Belohnung und Gegner"): who you face, what you win, one button.
void main() {
  final species = SpeciesDef(
    id: 'ow_test',
    name: 'Testling',
    element: CreatureElement.fire,
    rarity: CreatureRarity.common,
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [SpeciesStage(name: 'Kit')],
  );
  setUpAll(() => kSpeciesDefs[species.id] = species);

  Future<void> show(
    WidgetTester t, {
    OverworldNodeState state = OverworldNodeState.current,
    bool boss = false,
    int foes = 2,
    List<RewardLine> rewards = const [],
    VoidCallback? onFight,
  }) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 316,
              height: 354,
              child: OverworldFightCard(
                battleNumber: 10,
                isBoss: boss,
                state: state,
                enemies: [
                  for (var i = 0; i < foes; i++)
                    Combatant.fromSpecies(species, level: 25, id: 'e$i'),
                ],
                rewards: rewards,
                onFight: onFight ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('the current battle shows its foes, its reward and Fight', (
    t,
  ) async {
    var fought = 0;
    await show(
      t,
      rewards: const [
        RewardLine('🪙', '120 gold'),
        RewardLine('🪵', '60 wood'),
      ],
      onFight: () => fought++,
    );
    expect(find.text('Battle 10'), findsOneWidget);
    expect(find.text('ENEMIES'), findsOneWidget);
    expect(find.text('REWARD'), findsOneWidget);
    expect(find.text('Lv 25'), findsNWidgets(2));
    expect(find.text('120 gold'), findsOneWidget);
    expect(find.text('60 wood'), findsOneWidget);
    await t.tap(find.text('Fight'));
    await t.pumpAndSettle();
    expect(fought, 1);
  });

  testWidgets('three foes stand side by side with their names', (t) async {
    await show(t, foes: 3, rewards: const [RewardLine('🪙', '120 gold')]);
    expect(find.text('Kit'), findsNWidgets(3));
    expect(find.text('Lv 25'), findsNWidgets(3));
  });

  testWidgets('a crowd of foes is STACKED in one row and the reward stays', (
    t,
  ) async {
    await show(
      t,
      foes: 6,
      rewards: const [
        RewardLine('🪙', '120 gold'),
        RewardLine('🪵', '60 wood'),
        RewardLine('🪨', '40 stone'),
      ],
    );
    // Every foe is there, on ONE line (a wrapped second row is what pushed the
    // reward off the card) …
    final levels = find.text('Lv 25');
    expect(levels, findsNWidgets(6));
    final tops = {
      for (var i = 0; i < 6; i++) t.getTopLeft(levels.at(i)).dy.round(),
    };
    expect(tops, hasLength(1));
    // … their names are dropped (a tooltip keeps them) …
    expect(find.text('Kit'), findsNothing);
    // … and the reward and the button are still on the card.
    expect(find.text('120 gold'), findsOneWidget);
    expect(find.text('60 wood'), findsOneWidget);
    expect(find.text('Fight'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('more rewards than fit say so, and the cue goes at the end', (
    t,
  ) async {
    await show(
      t,
      foes: 3,
      rewards: [
        for (var i = 0; i < 12; i++) RewardLine('🎁', 'Reward number $i'),
      ],
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('▾ more'), findsOneWidget);
    // Scroll the list to its end: nothing is left to signal.
    await t.drag(find.text('Reward number 1'), const Offset(0, -900));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('▾ more'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a short reward list shows no cue', (t) async {
    await show(
      t,
      rewards: const [
        RewardLine('🪙', '120 gold'),
        RewardLine('🪵', '60 wood'),
      ],
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('▾ more'), findsNothing);
  });

  testWidgets('a boss battle is crowned', (t) async {
    await show(t, boss: true, foes: 1);
    expect(find.text('👑 Boss battle 10'), findsOneWidget);
  });

  testWidgets('a locked battle names what to win first and cannot be fought', (
    t,
  ) async {
    var fought = 0;
    await show(t, state: OverworldNodeState.locked, onFight: () => fought++);
    expect(find.text('Win battle 9 first'), findsOneWidget);
    await t.tap(find.text('Win battle 9 first'));
    await t.pumpAndSettle();
    expect(fought, 0);
  });

  testWidgets('a cleared battle offers a rematch for XP only', (t) async {
    await show(t, state: OverworldNodeState.done);
    expect(find.text('Fight again'), findsOneWidget);
    expect(find.text('Nothing new — a rematch earns XP only.'), findsOneWidget);
  });
}
