import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/settlement/dev/dev_mode_screen.dart';

// Dev Mode, "Variante 3" (user 2026-09-20): a rail of menus; species, buildings,
// items and areas as a list with its form beside it; the ability and budget
// pages read-only. Layout smoke tests at the landscape size.
void main() {
  final species = SpeciesDef(
    id: 'dev_test',
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

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: DevModeScreen()));
    await t.pumpAndSettle();
  }

  testWidgets('the rail lists the six menus; Monster opens on its species', (
    t,
  ) async {
    await open(t);
    for (final m in [
      'Monster',
      'Kampagne',
      'Gebäude',
      'Items',
      'Ressourcen',
      'Aktionen',
    ]) {
      expect(find.text(m), findsWidgets);
    }
    // The sub-pages of Monster, in the band.
    expect(find.text('Arten'), findsOneWidget);
    expect(find.text('Abilities'), findsOneWidget);
    expect(find.text('Budgets & Grenzen'), findsOneWidget);
    // The list, and the pane's hint beside it.
    expect(find.text('Testling'), findsOneWidget);
    expect(find.textContaining('Wähle links eine Art'), findsOneWidget);
  });

  testWidgets('Budgets & Grenzen is a page to read, with its explanation', (
    t,
  ) async {
    await open(t);
    await t.tap(find.text('Budgets & Grenzen'));
    await t.pumpAndSettle();
    expect(find.text('STAT-BUDGET JE SELTENHEIT'), findsOneWidget);
    expect(find.text('FANG'), findsOneWidget);
    expect(find.text('ERFAHRUNG'), findsOneWidget);
    expect(find.textContaining('sag mir, welche Zahl'), findsOneWidget);
  });

  testWidgets('Abilities is a page to read', (t) async {
    await open(t);
    await t.tap(find.text('Abilities'));
    await t.pumpAndSettle();
    expect(find.textContaining('Keine Abilities'), findsOneWidget);
  });

  testWidgets('a tap on a species opens its form in the pane beside the list', (
    t,
  ) async {
    await open(t);
    await t.tap(find.text('Testling'));
    await t.pumpAndSettle();
    expect(find.text('Edit Species'), findsOneWidget);
    expect(find.text('Basis'), findsWidgets);
    // The list is still there.
    expect(find.text('Testling'), findsWidgets);
    expect(find.textContaining('Wähle links eine Art'), findsNothing);
  });

  testWidgets('Kampagne has Pfad and Gebiete', (t) async {
    await open(t);
    await t.tap(find.text('Kampagne'));
    await t.pumpAndSettle();
    expect(find.text('Pfad'), findsWidgets);
    expect(find.text('Gebiete'), findsOneWidget);
  });

  testWidgets('Aktionen holds every cheat that left the player screens', (
    t,
  ) async {
    await open(t);
    await t.tap(find.text('Aktionen'));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Gold, Holz und Stein auffüllen'),
      findsOneWidget,
    );
    expect(find.textContaining('Alle Monster heilen'), findsOneWidget);
    expect(find.textContaining('Intro neu starten'), findsOneWidget);
    expect(find.textContaining('Rote Budgets reparieren'), findsOneWidget);
    expect(
      find.textContaining('Alle laufenden Ausflüge beenden'),
      findsOneWidget,
    );
  });
}
