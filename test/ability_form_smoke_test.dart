import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/dev/ability_def_form.dart';
import 'package:boddygame/features/creatures/models/ability_def.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/status_effects.dart';

// The rebuilt effect menu (user 2026-07-30), from the outside: it has to OPEN.
//
// A dropdown whose current value is not among its items throws at build time —
// analyze cannot see it, and it is exactly what a mismatched effect (a burn on a
// heal move, from an older row or a changed Kind) would produce. So each shape
// gets pumped here.
Future<void> _pump(WidgetTester tester, AbilityDef? existing) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: AbilityDefForm(existing: existing)));
  await tester.pumpAndSettle();
}

AbilityDef _def({
  AbilityKind kind = AbilityKind.damage,
  MainStatusKind? main,
  double mainTurns = 0,
  double mainValue = 0,
  SelfBuffKind? buff,
  double healPct = 0,
}) => AbilityDef(
  id: 'a',
  name: 'A',
  element: CreatureElement.fire,
  kind: kind,
  target: AbilityTarget.enemy,
  power: 60,
  inflictMain: main,
  inflictMainChance: main == null ? 0 : 0.3,
  inflictMainTurns: mainTurns.toInt(),
  inflictMainValue: mainValue,
  selfBuff: buff,
  healPct: healPct,
);

void main() {
  testWidgets('a brand-new ability opens with an empty effect list',
      (tester) async {
    await _pump(tester, null);
    expect(find.text('Effects'), findsOneWidget);
    expect(find.textContaining('only deals its damage'), findsOneWidget);
    expect(find.text('+ Add effect'), findsOneWidget);
  });

  testWidgets('an effect card states the fight outcome, not just its name',
      (tester) async {
    await _pump(tester, _def(main: MainStatusKind.burn, mainTurns: 4,
        mainValue: 0.1));
    expect(find.text('In combat'), findsOneWidget);
    // The authored numbers, in words.
    expect(find.textContaining('10 %'), findsWidgets);
    expect(find.textContaining('4 turns'), findsWidgets);
    // And the part that is NOT authorable but comes with picking Burn.
    expect(find.textContaining('attacks for'), findsOneWidget);
    // The unit lives in the field's own label — that is what makes one list work.
    expect(find.textContaining('Damage per turn'), findsOneWidget);
  });

  testWidgets('an untimed effect offers no duration field', (tester) async {
    await _pump(tester, _def(kind: AbilityKind.heal, healPct: 0.35));
    expect(find.textContaining('Not on a timer'), findsOneWidget);
    expect(find.textContaining('HP restored'), findsOneWidget);
  });

  testWidgets('a buff move opens on its buff', (tester) async {
    await _pump(tester, _def(kind: AbilityKind.buff, buff: SelfBuffKind.haste));
    expect(find.textContaining('Speed gained'), findsOneWidget);
    expect(find.textContaining('acts more often'), findsOneWidget);
  });

  testWidgets('a MISMATCHED effect renders and says why it will not fire',
      (tester) async {
    // The dropdown-assert case: a heal move carrying a burn. It must draw, warn,
    // and refuse to save it rather than throwing on open.
    await _pump(
      tester,
      AbilityDef(
        id: 'x',
        name: 'X',
        element: CreatureElement.fire,
        kind: AbilityKind.heal,
        target: AbilityTarget.ally,
        healPct: 0.2,
        inflictMain: MainStatusKind.burn,
        inflictMainChance: 0.5,
      ),
    );
    expect(find.textContaining('never applies this'), findsOneWidget);
    expect(find.textContaining('will NOT be saved'), findsOneWidget);
  });

  testWidgets('the cost card reads the AP rules back for THIS move',
      (tester) async {
    await _pump(tester, _def(main: MainStatusKind.frost));
    expect(find.text('Cost and turn order'), findsOneWidget);
    // A status move is mid-clamped, and the card says so — the rule that makes
    // one cheap for its power.
    expect(find.textContaining('AP'), findsWidgets);
  });
}
