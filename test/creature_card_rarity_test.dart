import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/widgets/creature_card.dart';

// The rarity word on a monster tile sits between two hairlines and must be
// centred on the tile (user 2026-09-22: "die Seltenheit ist nicht mittig, bei
// epic gut zu sehen") — a short word used to sit left of centre.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  SpeciesDef species(String id, CreatureRarity rarity) => SpeciesDef(
    id: id,
    name: id,
    element: CreatureElement.water,
    rarity: rarity,
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [SpeciesStage(name: 'Kit')],
  );

  for (final rarity in CreatureRarity.values) {
    testWidgets('${rarity.label} is centred on the tile', (t) async {
      final def = species('rar_${rarity.name}', rarity);
      kSpeciesDefs[def.id] = def;
      addTearDown(() => kSpeciesDefs.remove(def.id));
      final c = CreatureInstance(
        id: 'c',
        userId: 'u',
        speciesId: def.id,
        gender: CreatureGender.female,
        statBase: const {CreatureStat.hp: 50},
        statSlope: const {},
      );
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
      final word = t.getRect(find.text(rarity.label.toUpperCase()));
      final card = t.getRect(find.byType(CreatureCard));
      expect(word.center.dx, moreOrLessEquals(card.center.dx, epsilon: 2));
      expect(t.takeException(), isNull);
    });
  }
}
