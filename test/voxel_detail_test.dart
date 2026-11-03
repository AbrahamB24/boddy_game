import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/core/theme/voxel_kit.dart';
import 'package:boddygame/features/creatures/creature_detail_screen.dart';
import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';

// The voxel skin of the monster detail screen (Tidelord): every tab must lay
// out at the game's landscape size without an overflow, the skin is on for
// every species (since 2026-11-03, was Tidelord only), and the kit's own pieces must
// paint.
void main() {
  SpeciesDef species(String id) => SpeciesDef(
    id: id,
    name: id,
    element: CreatureElement.water,
    rarity: CreatureRarity.epic,
    description: 'A calm giant of the tides.',
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [
      SpeciesStage(name: 'One'),
      SpeciesStage(name: 'Two'),
      SpeciesStage(name: 'Three'),
    ],
  );

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    kSpeciesDefs['tidelord'] = species('tidelord');
    kSpeciesDefs['plain_one'] = species('plain_one');
    kAbilityDefs['attack'] = const AbilityDef(
      id: 'attack',
      name: 'Attack',
      element: CreatureElement.neutral,
      kind: AbilityKind.damage,
      target: AbilityTarget.enemy,
      power: 40,
    );
  });

  CreatureInstance monster(String speciesId) => CreatureInstance(
    id: 'm1',
    userId: 'u',
    speciesId: speciesId,
    gender: CreatureGender.female,
    level: 12,
    stage: 0,
    statBase: {for (final s in CreatureStat.values) s: 30.0},
    statSlope: {for (final s in CreatureStat.values) s: 1.5},
    currentHp: 40,
    learnedAbilityIds: const ['attack'],
    equippedAbilityIds: const ['attack'],
  );

  Future<void> show(WidgetTester t, String speciesId) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(home: CreatureDetailScreen(previewCreature: monster(speciesId))),
    );
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Tidelord wears the voxel skin on every tab, without overflow', (
    t,
  ) async {
    await show(t, 'tidelord');
    expect(find.byType(VoxelBackdrop), findsOneWidget);
    expect(find.byType(VoxelIcon), findsWidgets);
    for (final tab in ['Stats', 'Evolution', 'Abilities', 'General']) {
      await t.tap(find.text(tab));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('every other species wears the voxel skin too', (t) async {
    // User 2026-11-03: "der Monsterdetailscreen soll noch überall angepasst
    // werden wie bei tidelord".
    await show(t, 'plain_one');
    expect(find.byType(VoxelBackdrop), findsOneWidget);
    for (final tab in ['Stats', 'Evolution', 'Abilities', 'General']) {
      await t.tap(find.text(tab));
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('the kit paints: shape, bar, icons', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Container(
                width: 120,
                height: 60,
                decoration: ShapeDecoration(
                  color: Colors.blue,
                  shape: const VoxelShape(notch: 3),
                  shadows: voxelDrop(),
                ),
              ),
              const VoxelBar(value: 0.55, color: Colors.green),
              for (final g in VoxelGlyph.values) VoxelIcon(g),
            ],
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
  });
}
