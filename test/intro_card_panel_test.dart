import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/cream_kit.dart';
import 'package:boddygame/core/ui/pressable.dart';
import 'package:boddygame/features/onboarding/intro_card_panel.dart';
import 'package:boddygame/features/onboarding/intro_flow.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The guided tutorial's guide card — the FIRST thing a new player ever sees,
// and (2026-09-21) the last surface to move onto the cream kit. These pin the
// two things that make it usable rather than its looks: the current step's
// copy is on screen, and the one control it offers does what the step needs.
void main() {
  late List<IntroDestination> navigated;
  late int promptedQuickMenu;

  Future<void> open(WidgetTester t, IntroStep step) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    navigated = [];
    promptedQuickMenu = 0;
    final ctrl = SettlementController();
    ctrl.introStep = step;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: IntroCardPanel(
                ctrl: ctrl,
                onNavigate: navigated.add,
                onPromptQuickMenu: () => promptedQuickMenu++,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  tearDown(() => SettlementController().introStep = IntroStep.done);

  /// Taps and waits out [Pressable]'s own press-and-release delay — the kit's
  /// buttons run their callback when the button comes back UP, not on the
  /// pointer-down, so a bare `pump()` lands before anything has happened.
  Future<void> press(WidgetTester t, Finder f) async {
    await t.tap(f);
    await t.pump(Pressable.duration + const Duration(milliseconds: 20));
  }

  testWidgets('shows the current step\'s own title and body', (t) async {
    await open(t, IntroStep.welcome);
    final card = introCardFor(IntroStep.welcome)!;
    expect(find.text(card.title), findsOneWidget);
    expect(find.text(card.body), findsOneWidget);
  });

  testWidgets('every active step renders without overflowing', (t) async {
    // The card is centred over the map at a fixed 520px cap, and its copy
    // varies a lot in length — buildRoad's is several times welcome's. A
    // step whose text does not fit is a step the player cannot read.
    for (final step in IntroStep.values) {
      if (!step.isActive) continue;
      await open(t, step);
      expect(
        find.text(introCardFor(step)!.title),
        findsOneWidget,
        reason: step.name,
      );
      expect(t.takeException(), isNull, reason: step.name);
    }
  });

  testWidgets('the done step renders nothing at all', (t) async {
    await open(t, IntroStep.done);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('welcome\'s button advances the chain in place', (t) async {
    // It must NOT navigate (user 2026-09-02: "Wenn ich auf lets go klicke,
    // soll ich noch auf der Karte bleiben") — the player stays on the map
    // and the next card takes over.
    await open(t, IntroStep.welcome);
    await press(t, find.text(introCardFor(IntroStep.welcome)!.ctaLabel!));
    expect(navigated, isEmpty);
  });

  testWidgets('pickStarter\'s button hands off to the Monsters tile', (
    t,
  ) async {
    // Also no navigation: it lights the real quick-pad tile instead of
    // opening the picker itself (user 2026-09-02).
    await open(t, IntroStep.pickStarter);
    await press(t, find.text(introCardFor(IntroStep.pickStarter)!.ctaLabel!));
    expect(promptedQuickMenu, 1);
    expect(navigated, isEmpty);
  });

  testWidgets('a navigating step sends the player where its card says', (
    t,
  ) async {
    const step = IntroStep.healStarter;
    final card = introCardFor(step)!;
    await open(t, step);
    await press(t, find.text(card.ctaLabel!));
    expect(navigated, [card.destination]);
  });

  testWidgets('a narration-only step offers no button to press', (t) async {
    // firstNode deliberately has no CTA — the quick pad's Map tile is the
    // lit target instead, so a second button here would compete with it.
    expect(introCardFor(IntroStep.firstNode)!.ctaLabel, isNull);
    await open(t, IntroStep.firstNode);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('the skip control is always offered', (t) async {
    await open(t, IntroStep.buildRoad);
    expect(find.byType(KitCloseButton), findsOneWidget);
  });
}

