import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/overworld_screen.dart';
import 'package:boddygame/features/creatures/widgets/overworld_card.dart';

// The Overworld (user 2026-09-20, "Variante 4"): the road beside a fight card.
// A tap PICKS a battle and the card follows. The map's pulse never settles, so
// these step the clock instead of pumpAndSettle.
void main() {
  setUp(() {
    kAreaDefs
      ..clear()
      ..addAll({for (final a in kFallbackAreaDefs) a.id: a});
  });

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: OverworldScreen()));
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opens on the current battle, with the card beside the road', (
    t,
  ) async {
    await open(t);
    expect(find.text('Overworld'), findsOneWidget);
    expect(find.text('Survival'), findsOneWidget);
    expect(find.text('Battle 1'), findsOneWidget);
    expect(find.text('ENEMIES'), findsOneWidget);
    expect(find.text('REWARD'), findsOneWidget);
    expect(find.text('Fight'), findsOneWidget);
  });

  testWidgets('the fight card runs the full height with equal padding, and '
      'the header (Survival, the way out) sits over the road only', (t) async {
    await open(t);
    final card = t.getRect(
      find.ancestor(
        of: find.text('ENEMIES'),
        matching: find.byType(OverworldFightCard),
      ),
    );
    final screen = t.view.physicalSize / t.view.devicePixelRatio;
    // The same 10 px above and below the card.
    expect(card.top, moreOrLessEquals(10, epsilon: 0.5));
    expect(screen.height - card.bottom, moreOrLessEquals(10, epsilon: 0.5));
    // Survival is left of the card, in the header, and the header ends where the
    // card's column begins.
    final survival = t.getRect(find.text('Survival'));
    expect(survival.right, lessThan(card.left));
    expect(survival.top, lessThan(46));
    final title = t.getRect(find.text('Overworld'));
    expect(title.right, lessThan(card.left));
    expect(t.takeException(), isNull);
  });

  testWidgets('a tap on a locked node picks it: the card names what to win', (
    t,
  ) async {
    await open(t);
    await t.tap(find.byIcon(Icons.lock).first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Win battle'), findsOneWidget);
    expect(find.text('Fight'), findsNothing);
  });
}
