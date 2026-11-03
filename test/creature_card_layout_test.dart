import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/widgets/creature_card.dart';

// The tile's text (user 2026-09-28): level and power sit TOGETHER in the middle,
// and a monster that can evolve wears a proper stamp on its corner.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final def = SpeciesDef(
    id: 'layout_test',
    name: 'Droplet',
    element: CreatureElement.water,
    rarity: CreatureRarity.common,
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [
      SpeciesStage(name: 'Kit'),
      SpeciesStage(name: 'Kit 2'),
    ],
  );
  setUp(() => kSpeciesDefs[def.id] = def);
  tearDown(() => kSpeciesDefs.remove(def.id));

  Future<CreatureInstance> show(WidgetTester t, {required int level}) async {
    final c = CreatureInstance(
      id: 'c',
      userId: 'u',
      speciesId: def.id,
      gender: CreatureGender.male,
      statBase: const {CreatureStat.hp: 50},
      statSlope: const {},
    );
    c.level = level;
    t.view.physicalSize = const Size(400, 400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 128,
              height: 180,
              child: CreatureCard(creature: c),
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 200));
    return c;
  }

  testWidgets('level and power stand close together, centred on the tile', (
    t,
  ) async {
    await show(t, level: 8);
    final lv = t.getRect(find.text('Lv 8'));
    final power = t.getRect(find.textContaining('⚡'));
    final card = t.getRect(find.byType(CreatureCard));
    // A small gap between them, not the width of the tile.
    expect(power.left - lv.right, lessThan(20));
    // …and the pair is centred like the name is.
    final pair = Rect.fromLTRB(lv.left, lv.top, power.right, power.bottom);
    expect(pair.center.dx, moreOrLessEquals(card.center.dx, epsilon: 3));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'a monster that can evolve wears the stamp, one that cannot does not',
    (t) async {
      final ready = await show(t, level: 100);
      expect(ready.canEvolve, isTrue);
      expect(find.bySemanticsLabel('Can evolve'), findsOneWidget);

      await show(t, level: 1);
      expect(find.bySemanticsLabel('Can evolve'), findsNothing);
    },
  );

  testWidgets(
    'the evolve stamp sits INSIDE the coloured foot, not past the cell\'s '
    'own top (user 2026-09-29: "sollte noch im blauen Kästchen sein … so '
    'dass es nicht verdeckt werden kann")',
    (t) async {
      await show(t, level: 100);
      final card = t.getRect(find.byType(CreatureCard));
      final stamp = t.getRect(find.bySemanticsLabel('Can evolve'));
      // The foot starts about a third down the tile — the stamp must not sit
      // in the free strip above it, where a tight grid's row above can clip
      // or cover it.
      expect(stamp.top, greaterThan(card.top + card.height * 0.3));
      expect(t.takeException(), isNull);
    },
  );
}
