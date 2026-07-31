import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../creatures/models/expedition.dart';
import '../creatures/services/expedition_controller.dart';
import '../settlement/settlement_controller.dart';
import 'intro_flow.dart';

/// The new-player guidance card, shown over the settlement map for as long as
/// the intro chain runs. Deliberately a card the player can ignore rather than
/// a modal tour: it names the next move and gets out of the way, and "✕ Skip"
/// ends it (and the jumpstart) for good.
///
/// Sizing is the caller's job — the settlement screen stacks this above the
/// quick menu, and PhoneFrame caps the viewport at [FoE.phoneMaxWidth].
class IntroCardPanel extends StatelessWidget {
  final SettlementController ctrl;

  /// Opens the screen a step's call-to-action points at. The card owns no
  /// navigation of its own — the settlement screen already has these routes.
  final void Function(IntroDestination) onNavigate;

  const IntroCardPanel({
    super.key,
    required this.ctrl,
    required this.onNavigate,
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
    final capturePending = step == IntroStep.firstCapture &&
        ExpeditionController()
            .expeditions
            .any((e) => e.type == ExpeditionType.capture);
    final ctaLabel = capturePending ? '🎒 Open Trips' : card.ctaLabel;
    final destination =
        capturePending ? IntroDestination.trips : card.destination;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: FoE.panel(overrideBorder: FoE.borderGold, glow: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'GETTING STARTED · ${step.index + 1}/${IntroStep.done.index}',
                  style: FoE.dim(size: 9).copyWith(color: FoE.gold),
                ),
              ),
              _skipButton(context),
            ],
          ),
          const SizedBox(height: 6),
          Text(card.title, style: FoE.title(size: 13)),
          const SizedBox(height: 6),
          Text(card.body, style: FoE.label(size: 11)),
          if (ctaLabel != null && destination != null) ...[
            const SizedBox(height: 12),
            _ctaButton(ctaLabel, destination),
          ],
        ],
      ),
    );
  }

  Widget _ctaButton(String label, IntroDestination destination) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => onNavigate(destination),
      borderRadius: BorderRadius.circular(FoE.radiusSmall),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: FoE.tapTarget),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: FoE.goldGradient,
          borderRadius: BorderRadius.circular(FoE.radiusSmall),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          // Dark ink on the accent fill — this is the one primary action on
          // the screen and should look like it.
          style: FoE.title(size: 12).copyWith(color: FoE.bg),
        ),
      ),
    ),
  );

  Widget _skipButton(BuildContext context) => GestureDetector(
    onTap: () async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: FoE.panelMid,
          shape: FoE.facet(radius: FoE.radius, side: const BorderSide(color: FoE.border, width: 2)),
          title: Text('Skip the intro?', style: FoE.title(size: 13)),
          content: Text(
            'You will lose the head start that comes with it: faster '
            'expeditions, research and building, and weakened enemies. This '
            'cannot be undone.',
            style: FoE.label(size: 11),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Keep it', style: FoE.label(size: 11)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Skip',
                style: FoE.label(size: 11).copyWith(color: FoE.danger),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) await ctrl.skipIntro();
    },
    // A bare glyph is a ~12px target. Padded out to a thumb-sized one; the
    // icon stays small, the hit area does not.
    child: const SizedBox(
      width: 36,
      height: 32,
      child: Icon(Icons.close_rounded, size: 16, color: FoE.textDim),
    ),
  );
}
