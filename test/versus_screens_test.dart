import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/battle_prep_screen.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/battle_rewards.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/creatures/widgets/versus_kit.dart';

// The card duel (user 2026-09-20, "Variante 8" with the power bar of "Variante 2"):
// Battle Prep and the pages built on the same kit. Layout smoke tests at the
// landscape size — an overflow fails a widget test.
void main() {
  final species = SpeciesDef(
    id: 'vs_test',
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

  CreatureInstance mine(String id) => CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: species.id,
    gender: CreatureGender.male,
    statBase: {for (final s in CreatureStat.values) s: 20},
    statSlope: const {},
  );

  List<Combatant> enemies(int n) => [
    for (var i = 0; i < n; i++)
      Combatant.fromSpecies(species, level: 5, id: 'e$i'),
  ];

  Future<void> open(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    CreaturesController().creatures = [mine('a'), mine('b')];
    await t.pumpWidget(MaterialApp(home: screen));
    await t.pumpAndSettle();
  }

  testWidgets('Battle Prep: the enemy above, your team below, a bar between', (
    t,
  ) async {
    await open(
      t,
      BattlePrepScreen(
        title: 'Forest Hollow',
        enemies: enemies(3),
        partySize: 3,
        rewards: const [
          RewardLine('🪙', '120 gold'),
          RewardLine('🪵', '60 wood'),
          RewardLine('🥚', 'A rare egg'),
        ],
      ),
    );
    expect(find.text('YOU FACE'), findsOneWidget);
    expect(find.text('YOUR TEAM'), findsOneWidget);
    expect(find.text('REWARDS'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('Fight'), findsOneWidget);
    expect(find.text('2/3 chosen'), findsOneWidget);
  });

  testWidgets('Battle Prep: the rewards button lists everything', (t) async {
    await open(
      t,
      BattlePrepScreen(
        title: 'Forest Hollow',
        enemies: enemies(2),
        partySize: 3,
        rewards: const [
          RewardLine('🪙', '120 gold'),
          RewardLine('🪵', '60 wood'),
        ],
      ),
    );
    await t.tap(find.text('REWARDS'));
    await t.pumpAndSettle();
    expect(find.text('120 gold'), findsOneWidget);
    expect(find.text('60 wood'), findsOneWidget);
  });

  testWidgets('a team pick with no enemy draws only your own fan', (t) async {
    await open(
      t,
      const BattlePrepScreen(
        title: 'vs. Mira',
        enemies: [],
        partySize: 6,
        rewards: [],
        showEnemyPreview: false,
        confirmLabel: 'Ready',
      ),
    );
    expect(find.text('YOU FACE'), findsNothing);
    expect(find.text('VS'), findsNothing);
    expect(find.text('YOUR TEAM'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('the comparison bar splits by the two totals', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PowerVersusBar(mine: 300, theirs: 100)),
      ),
    );
    expect(find.text('⚡ 300'), findsOneWidget);
    expect(find.text('⚡ 100'), findsOneWidget);
  });

  test('a combatant tile carries the combatant\'s own numbers', () {
    final e = Combatant.fromSpecies(species, level: 7, id: 'x');
    final shown = enemyInstanceOf(e);
    expect(shown.level, 7);
    expect(shown.maxHp, e.stats[CreatureStat.hp]);
    expect(
      CreatureStat.values.fold<int>(0, (s, k) => s + shown.statValue(k)),
      combatantPower(e),
    );
  });
}
