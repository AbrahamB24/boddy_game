import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../creatures/models/expedition.dart';
import '../creatures/services/expedition_controller.dart';
import '../settlement/settlement_controller.dart';
import '../social/social_actions.dart' show confirmDialog;
import 'intro_flow.dart';

/// The new-player guidance card, shown over the settlement map for as long as
/// the intro chain runs. Deliberately a card the player can ignore rather than
/// a modal tour: it names the next move and gets out of the way, and the skip
/// cross ends it (and the jumpstart) for good.
///
/// IN THE CREAM KIT since 2026-09-21 — it was the last surface still wearing
/// the old dark/blue `FoE.panel` look after the app-wide redesign, which made
/// the very first thing a new player ever sees the one thing that did not
/// match the game around it. Same paper, tan shadow and gold button as every
/// dialog and menu: [creamCard] for the body, [goldButton] for the
/// call-to-action, [KitCloseButton] for the skip, and the shared cream
/// [confirmDialog] for the confirmation behind it.
///
/// Sizing is the caller's job — the settlement screen centres this over the
/// map and caps it at 520 px (see SettlementScreen._introCard).
class IntroCardPanel extends StatelessWidget {
  final SettlementController ctrl;

  /// Opens the screen a step's call-to-action points at. The card owns no
  /// navigation of its own — the settlement screen already has these routes.
  final void Function(IntroDestination) onNavigate;

  /// pickStarter's CTA doesn't navigate anywhere — the settlement screen is
  /// already where the Monsters tile lives. Pressing it instead tells the
  /// screen to swap the spotlight onto that tile (user 2026-09-02: "wenn ich
  /// auf Choose starter drücke, dann bleibe ich auf der Karte, aber der
  /// Monsterbutton wird gehighlighted").
  final VoidCallback onPromptQuickMenu;

  const IntroCardPanel({
    super.key,
    required this.ctrl,
    required this.onNavigate,
    required this.onPromptQuickMenu,
  });

  @override
  Widget build(BuildContext context) {
    // Rebuild on expedition changes too: the capture step's CTA flips from
    // "Open the map" to "Open Trips" the moment the hunt is dispatched, and
    // waiting for the settlement's 5s tick to notice would leave the lit
    // button pointing at the wrong place.
    return AnimatedBuilder(
      animation: ExpeditionController(),
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    final step = ctrl.introStep;
    final card = introCardFor(step);
    if (card == null) return const SizedBox.shrink();

    // The catch step spans a trip: once the hunt is out, the job is playing
    // it from the Trips list, not sending another one — the CTA follows.
    final capturePending =
        step == IntroStep.firstCapture &&
        ExpeditionController().expeditions.any(
          (e) => e.type == ExpeditionType.capture,
        );
    final ctaLabel = capturePending ? '🎒 Open Trips' : card.ctaLabel;
    final destination = capturePending
        ? IntroDestination.trips
        : card.destination;

    return creamCard(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
      // The skip cross rides the card's own corner, like every other cream
      // surface's leaving button — it no longer has to share the header row
      // with the step counter.
      corner: _skipButton(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTrail(step),
          const SizedBox(height: 9),
          // FLAT heading, never a gold pill — in this kit a pill means
          // "pressable", and the title is not (see cream_kit.dart).
          Text(
            card.title,
            style: FoE.title(size: 16).copyWith(color: kBoxInk),
          ),
          const SizedBox(height: 7),
          Text(
            card.body,
            style: FoE.label(size: 12).copyWith(color: kBoxInkSoft, height: 1.3),
          ),
          if (ctaLabel != null && destination != null) ...[
            const SizedBox(height: 14),
            _ctaButton(ctaLabel, destination, step),
          ],
        ],
      ),
    );
  }

  /// Where the player is in the chain, as a row of pips rather than "3/9".
  /// A new player has no idea how long nine steps is; a short row they can
  /// see filling up answers "how much more of this?" at a glance, which is
  /// the only question the counter was ever really being asked.
  Widget _stepTrail(IntroStep step) {
    final total = IntroStep.done.index;
    return Row(
      children: [
        Text(
          'GETTING STARTED',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: kBoxAccent,
          ),
        ),
        const SizedBox(width: 10),
        // Room for the corner button, so a long trail never runs under it.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: KitCloseButton.size - 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (var i = 0; i < total; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: _Pip(done: i < step.index, current: i == step.index),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _ctaButton(
    String label,
    IntroDestination destination,
    IntroStep step,
  ) => Pressable(
    onTap: () {
      // welcome has no milestone of its own to advance from elsewhere, so
      // its CTA just advances the chain — the player stays on the
      // settlement map and sees the pickStarter card next, whose own CTA
      // is what opens the starter picker (user 2026-09-02: "Wenn ich auf
      // lets go klicke, soll ich noch auf der Karte bleiben").
      if (step == IntroStep.welcome) {
        unawaited(ctrl.advanceIntro(step));
        return;
      }
      // pickStarter doesn't navigate either (user 2026-09-02, same day):
      // the player is still on the settlement map, and the ONE lit control
      // is now the real Monsters tile in the quick menu rather than a
      // second copy of it on this card.
      if (step == IntroStep.pickStarter) {
        onPromptQuickMenu();
        return;
      }
      onNavigate(destination);
    },
    child: Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: FoE.tapTarget),
      alignment: Alignment.center,
      decoration: goldButton(),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: FoE.title(size: 13).copyWith(color: goldButtonInk()),
      ),
    ),
  );

  Widget _skipButton(BuildContext context) => KitCloseButton(
    onTap: () async {
      final ok = await confirmDialog(
        context,
        title: 'Skip the intro?',
        body:
            'You will lose the head start that comes with it: faster '
            'expeditions, research and building, and weakened enemies. This '
            'cannot be undone.',
        confirmLabel: 'Skip',
        cancelLabel: 'Keep it',
      );
      if (ok) await ctrl.skipIntro();
    },
  );
}

/// One step of the trail: filled for a step already behind the player, gold
/// and a touch larger for the one they are on, hollow for what is still to
/// come.
class _Pip extends StatelessWidget {
  final bool done;
  final bool current;

  const _Pip({required this.done, required this.current});

  @override
  Widget build(BuildContext context) {
    final size = current ? 8.0 : 6.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: current
            ? CreamPalette.gold
            : done
            ? CreamPalette.tan
            : Colors.transparent,
        border: done || current
            ? null
            : Border.all(color: CreamPalette.tan.withValues(alpha: 0.5)),
      ),
    );
  }
}
