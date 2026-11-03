import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/overworld_screen.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// The campaign (user 2026-11-03, concept 5): a strip of every battle over the
// picked battle in focus. A tap PICKS a battle and the view follows.
void main() {
  final species = SpeciesDef(
    id: 'overworld_test',
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

  setUp(() {
    kAreaDefs
      ..clear()
      ..addAll({for (final a in kFallbackAreaDefs) a.id: a});
    // A battle-ready monster — what any player past the intro's starter step
    // actually has. Without one the Fight button reads "Catch a monster
    // first" and is inert (see OverworldFightCard.noTeam), which is its own
    // narrow edge case, not what these layout/navigation tests are about.
    CreaturesController().creatures = [
      CreatureInstance(
        id: 'm0',
        userId: 'u',
        speciesId: species.id,
        nickname: 'Mine',
        gender: CreatureGender.male,
        statBase: {for (final s in CreatureStat.values) s: 20},
        statSlope: const {},
      ),
    ];
  });
  tearDown(() => CreaturesController().creatures = []);

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: OverworldScreen()));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opens on the current battle: strip, facts, enemies, Fight', (
    t,
  ) async {
    await open(t);
    expect(find.text('Overworld'), findsOneWidget);
    expect(find.text('Survival'), findsOneWidget);
    expect(find.text('Battle 1'), findsOneWidget);
    expect(find.text('ENEMIES'), findsOneWidget);
    expect(find.text('REWARD'), findsOneWidget);
    expect(find.text('Fight'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the strip shows every battle of the line, in one row', (
    t,
  ) async {
    // Concept 5 (user 2026-11-03): "idealerweise werden alle 20 Kämpfe
    // gezeigt" — the chips share the width instead of a road you scroll.
    await open(t);
    final chips = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('battle-chip-'),
    );
    expect(chips, findsWidgets);
    final tops = {
      for (final e in chips.evaluate())
        t.getRect(find.byWidget(e.widget)).top.round(),
    };
    expect(tops.length, 1, reason: 'all chips sit in one row');
    expect(t.takeException(), isNull);
  });

  testWidgets('a tap on a locked battle picks it: the view names what to win', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('battle-chip-2')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Battle 2'), findsOneWidget);
    expect(find.textContaining('Win battle'), findsOneWidget);
    expect(find.text('Fight'), findsNothing);
  });

  testWidgets('the arrows step to the next battle and back', (t) async {
    await open(t);
    await t.tap(find.bySemanticsLabel('Next battle'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Battle 2'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Previous battle'));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Battle 1'), findsOneWidget);
  });
}
