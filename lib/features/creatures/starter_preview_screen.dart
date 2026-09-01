import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import 'models/species_def.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_sprite.dart';

/// A look at a starter species BEFORE anything is adopted — pushed from
/// [CollectionScreen]'s starter picker in place of the old confirm dialog.
///
/// Nothing is created until [_confirm] runs: the species stays a
/// [SpeciesDef], never a [CreatureInstance], while this screen is up, so the
/// system back button just pops with no trace to undo (user 2026-08-24:
/// "will ich in den monster Detail screen von diesem Monster kommen ...
/// Gehe ich zurück, komme ich wieder in den choose your starter screen").
/// Confirming adopts and returns straight to the settlement — this is the
/// player's very first creature, not a screen worth lingering on.
class StarterPreviewScreen extends StatefulWidget {
  final SpeciesDef species;

  const StarterPreviewScreen({super.key, required this.species});

  @override
  State<StarterPreviewScreen> createState() => _StarterPreviewScreenState();
}

class _StarterPreviewScreenState extends State<StarterPreviewScreen> {
  final _ctrl = CreaturesController();
  bool _adopting = false;

  Future<void> _confirm() async {
    setState(() => _adopting = true);
    final created = await _ctrl.adoptStarter(widget.species);
    if (!mounted) return;
    if (created == null) {
      // No pop-up any more (user 2026-08-29: "wirklich alle pop up
      // nachrichten... löschen") — the button re-enabling (_adopting back to
      // false) is the signal to try again.
      setState(() => _adopting = false);
      return;
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final species = widget.species;
    final art = species.stageAt(0).imageUrl;
    return ParchmentPage(
      title: species.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ParchmentPage.kParchmentPagePad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            SizedBox(
              height: 220,
              child: CreatureBackdrop(
                element: species.element,
                radius: 12,
                child: Center(
                  child: art == null
                      ? const Icon(Icons.pets, color: FoE.gold, size: 64)
                      : CreatureSprite(
                          url: art,
                          fallback: const Icon(
                            Icons.pets,
                            color: FoE.gold,
                            size: 64,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(species.name, style: FoE.title(size: 20)),
            const SizedBox(height: 4),
            Text(
              '${species.element.emoji} ${species.element.label} · ${species.rarity.label}',
              style: FoE.label(size: 13).copyWith(color: species.rarity.color),
            ),
            if (species.description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(species.description, style: FoE.dim(size: 12)),
            ],
            const SizedBox(height: 12),
            Text(
              'Your starter accompanies you from the very beginning. This '
              'choice is final!',
              style: FoE.dim(size: 11),
            ),
            const Spacer(),
            _confirmButton(species),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _confirmButton(SpeciesDef species) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _adopting ? null : _confirm,
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
          _adopting ? 'Choosing…' : 'Choose ${species.name}',
          textAlign: TextAlign.center,
          style: FoE.title(size: 13).copyWith(color: FoE.bg),
        ),
      ),
    ),
  );
}
