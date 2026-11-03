import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/battle_screen.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/battle_rewards.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// The victory page (user 2026-09-28: "Victory Screen muss auf einer Seite Platz
// haben ohne zu scrollen"): one full page, however long the list of unlocks —
// it scales down instead of scrolling, and never overflows.
void main() {
  final species = SpeciesDef(
    id: 'victory_test',
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
    nickname: 'Mine $id',
    gender: CreatureGender.male,
    statBase: {for (final s in CreatureStat.values) s: 60},
    statSlope: const {},
  );

  testWidgets('a won fight ends on one page: no scrolling, no overflow', (
    t,
  ) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final party = [for (var i = 0; i < 6; i++) mine('m$i')];
    CreaturesController().creatures = party;
    await t.pumpWidget(
      MaterialApp(
        home: BattleScreen(
          team: party,
          battleNumber: 3,
          enemies: [Combatant.fromSpecies(species, level: 1, id: 'e0')],
          victoryRewards: [
            for (var i = 0; i < 8; i++) RewardLine('🎁', 'Reward number $i'),
          ],
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // AUTO plays the player's turns; the lone level-1 foe goes down quickly.
    await t.tap(find.text('AUTO'));
    for (var i = 0; i < 400; i++) {
      await t.pump(const Duration(milliseconds: 100));
      if (find.text('Continue').evaluate().isNotEmpty) break;
    }
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('🏆 Victory!'), findsOneWidget);
    // Nothing on the page scrolls…
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
    // …and every reward is on it, inside the screen.
    for (var i = 0; i < 8; i++) {
      final row = find.text('Reward number $i');
      expect(row, findsOneWidget);
      final r = t.getRect(row);
      expect(r.left >= 0 && r.right <= 932, isTrue, reason: '$i horizontally');
      expect(r.top >= 0 && r.bottom <= 430, isTrue, reason: '$i vertically');
    }
    final btn = t.getRect(find.text('Continue'));
    expect(btn.bottom <= 430 && btn.right <= 932, isTrue);
  });
}
