import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/combat_school_screen.dart';
import 'package:boddygame/features/creatures/healing_hut_screen.dart';
import 'package:boddygame/features/creatures/hatchery_screen.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The slot family (user 2026-09-20, "Variante 2, Slot-Karten"): the Healing Hut,
// the Combat School and the merged Breeding & Hatchery page all lay out the same
// way. These are layout smoke tests at the landscape size — a RenderFlex
// overflow fails a widget test, which is what they catch.
void main() {
  CreatureInstance hurt(String id, {int hp = 5}) => CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: 's',
    gender: CreatureGender.male,
    statBase: {CreatureStat.hp: 40},
    statSlope: const {},
    currentHp: hp,
  );

  Future<void> pump(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    SettlementController().resources = ResourceModel(
      settlementId: 's',
      wood: 0,
      stone: 0,
      gold: 100,
      goods: const {'fish': 50},
      lastUpdatedAt: DateTime(2026),
    );
    await t.pumpWidget(MaterialApp(home: screen));
    await t.pumpAndSettle();
  }

  testWidgets('Healing Hut: the hurt are tiles, with Heal all above them', (
    t,
  ) async {
    CreaturesController().creatures = [hurt('a'), hurt('b', hp: 9)];
    await pump(t, const HealingHutScreen());
    expect(find.text('Healing Hut'), findsOneWidget);
    expect(find.textContaining('WOUNDED'), findsOneWidget);
    expect(find.textContaining('Heal all'), findsOneWidget);
    expect(find.text('Free bed'), findsWidgets);
  });

  testWidgets('Healing Hut: nobody hurt is a quiet page', (t) async {
    CreaturesController().creatures = [];
    await pump(t, const HealingHutScreen());
    expect(find.text('Everyone is at full health.'), findsOneWidget);
    expect(find.textContaining('Heal all'), findsNothing);
  });

  testWidgets('Combat School: nothing to learn is a quiet page', (t) async {
    CreaturesController().creatures = [];
    await pump(t, const CombatSchoolScreen());
    expect(find.text('Combat School'), findsOneWidget);
    expect(find.text('Nobody has anything left to learn.'), findsOneWidget);
  });

  testWidgets('Breeding & Hatchery: two tabs, one page', (t) async {
    CreaturesController().creatures = [];
    await pump(t, const HatcheryScreen());
    // Opens on the Hatchery half.
    expect(find.text('Breeding & Hatchery'), findsOneWidget);
    expect(find.textContaining('EGGS IN THE BAG'), findsOneWidget);
    // The Breeding half is one tap away.
    await t.tap(find.text('Breeding Hut').first);
    await t.pumpAndSettle();
    expect(find.text('MATING'), findsWidgets);
    expect(find.textContaining('EGGS IN THE BAG'), findsNothing);
  });

  testWidgets('the Breeding Hut opens the Breeding half', (t) async {
    CreaturesController().creatures = [];
    await pump(t, const HatcheryScreen(startOn: NurseryTab.breeding));
    expect(find.text('MATING'), findsWidgets);
  });
}
