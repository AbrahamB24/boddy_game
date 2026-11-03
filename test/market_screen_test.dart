import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/creatures/widgets/creature_card.dart';
import 'package:boddygame/features/settlement/market_screen.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The Market (user 2026-09-20, "Variante 3, Handelskacheln"): the three
// resources of an era sit side by side, and the amount is a field you tap to
// type the exact quantity.
void main() {
  CreatureInstance mon(String id) => CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: 's',
    gender: CreatureGender.male,
    statBase: {CreatureStat.carry: 60, CreatureStat.speed: 40},
    statSlope: const {},
  );

  Future<void> open(WidgetTester t, {int stage = 1}) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = SettlementController();
    s.dungeonMaxStage = stage;
    s.resources = ResourceModel(
      settlementId: 's',
      wood: 340,
      stone: 210,
      gold: 1240,
      goods: const {'fish': 96, 'meat': 40, 'clay': 80, 'frame': 12},
      lastUpdatedAt: DateTime(2026),
    );
    CreaturesController().creatures = [mon('a'), mon('b')];
    await t.pumpWidget(const MaterialApp(home: MarketScreen()));
    await t.pump();
  }

  /// Puts the first free monster on the caravan through the picker.
  Future<void> loadHauler(WidgetTester t) async {
    await t.tap(find.byIcon(Icons.add).first);
    await t.pumpAndSettle();
    await t.tap(find.byType(CreatureCard).first);
    await t.pumpAndSettle();
    // Preview-then-confirm since the 2026-10-05 picker unification: the tap
    // above only previews; the panel's gold button commits the pick.
    await t.tap(find.text('Add this hauler'));
    await t.pumpAndSettle();
  }

  testWidgets('an era is one row: wood, stone and fish side by side', (
    t,
  ) async {
    await open(t);
    final wood = t.getTopLeft(find.text('Wood'));
    final stone = t.getTopLeft(find.text('Stone'));
    final fish = t.getTopLeft(find.text('Fish'));
    expect(stone.dy, wood.dy);
    expect(fish.dy, wood.dy);
    expect(wood.dx < stone.dx && stone.dx < fish.dx, isTrue);
  });

  testWidgets('with no hauler the cards say what is missing', (t) async {
    await open(t);
    expect(find.text('Prepare a caravan'), findsNWidgets(3));
  });

  testWidgets('tapping the amount field sets the exact quantity', (t) async {
    await open(t);
    await loadHauler(t);
    expect(find.text('Prepare a caravan'), findsNothing);

    await t.tap(find.byIcon(Icons.edit).first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '25');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    final field = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('25 /'),
    );
    expect(field, findsOneWidget);
  });

  testWidgets('a number over the ceiling is set to the ceiling', (t) async {
    await open(t);
    await loadHauler(t);
    await t.tap(find.byIcon(Icons.edit).first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '999999');
    await t.pump();
    expect(find.textContaining('takes at most'), findsOneWidget);
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    // Set to the ceiling: "N /N".
    final capped = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final m = RegExp(r'^(\d+) /(\d+)$').firstMatch(w.text.toPlainText());
      return m != null && m.group(1) == m.group(2);
    });
    expect(capped, findsWidgets);
  });

  testWidgets('older eras wait under the current one', (t) async {
    await open(t, stage: 2);
    // Era II (meat, clay, frame) is the current row; era I sits below it.
    expect(
      t.getTopLeft(find.text('Meat')).dy,
      lessThan(t.getTopLeft(find.text('Wood')).dy),
    );
  });

  testWidgets('exchange offers a Get picker and a buy-with-gold mode', (
    t,
  ) async {
    await open(t);
    await t.tap(find.text('Exchange').first);
    await t.pumpAndSettle();
    expect(find.text('Get'), findsOneWidget);
    await t.tap(find.text('Buy with gold'));
    await t.pumpAndSettle();
    expect(find.text('Get'), findsNothing);
  });
}
