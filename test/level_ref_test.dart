import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/core/ui/pressable.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/creature_power.dart';
import 'package:boddygame/features/creatures/widgets/creature_card.dart';
import 'package:boddygame/features/creatures/widgets/gene_bar_toggle.dart';

// Breeding switches its numbers between level 1 and the maximum (user
// 2026-09-28) — the tile's ⚡ included.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  final def = SpeciesDef(
    id: 'ref_test',
    name: 'Refling',
    element: CreatureElement.water,
    rarity: CreatureRarity.common,
    stats: {
      for (final s in CreatureStat.values)
        s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
    },
    stages: const [SpeciesStage(name: 'Kit')],
  );
  setUp(() => kSpeciesDefs[def.id] = def);
  tearDown(() => kSpeciesDefs.remove(def.id));

  CreatureInstance mon(int level) {
    final c = CreatureInstance(
      id: 'c',
      userId: 'u',
      speciesId: def.id,
      gender: CreatureGender.male,
      statBase: {for (final s in CreatureStat.values) s: 20},
      statSlope: {for (final s in CreatureStat.values) s: 2},
    );
    c.level = level;
    return c;
  }

  test('power at the monster\'s own level is its total power', () {
    final c = mon(12);
    expect(powerAtLevel(c, 12), totalPower(c));
  });

  test('level 1 is the genes, and max is far above it', () {
    final c = mon(12);
    expect(powerAtLevel(c, 1), levelOnePower(c));
    expect(
      powerAtLevel(c, kCreatureMaxLevel),
      greaterThan(powerAtLevel(c, 1)),
    );
  });

  testWidgets('the tile shows the power at the chosen level', (t) async {
    final c = mon(12);
    Future<void> show(int? level) async {
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
                child: CreatureCard(creature: c, atLevel: level),
              ),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 200));
    }

    await show(null);
    expect(find.text('⚡${totalPower(c)}'), findsOneWidget);
    // The level shown is the chosen one, not the monster's own.
    expect(find.text('Lv 12'), findsOneWidget);
    await show(1);
    expect(find.text('⚡${powerAtLevel(c, 1)}'), findsOneWidget);
    expect(find.text('Lv 1'), findsOneWidget);
    await show(kCreatureMaxLevel);
    expect(find.text('⚡${powerAtLevel(c, kCreatureMaxLevel)}'), findsOneWidget);
    expect(find.text('Lv $kCreatureMaxLevel'), findsOneWidget);
    // No "At Lv 1" flag any more — the switch says it.
    expect(find.textContaining('At Lv'), findsNothing);
  });

  testWidgets('the Now / Lv 1 / Max switch reports each choice', (t) async {
    var index = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, set) => LevelRefToggle(
                index: index,
                onChanged: (i) => set(() => index = i),
                ink: Colors.black,
                inkFaint: Colors.grey,
                accent: Colors.orange,
              ),
            ),
          ),
        ),
      ),
    );
    for (final (label, want) in [('Max', 2), ('Lv 1', 1), ('Now', 0)]) {
      await t.tap(find.text(label));
      await t.pump(Pressable.duration + const Duration(milliseconds: 50));
      expect(index, want, reason: label);
    }
  });
}
