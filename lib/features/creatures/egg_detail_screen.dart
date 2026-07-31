import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/scroll_paper.dart'
    show
        kParchmentInk,
        kParchmentLight,
        parchmentButton,
        parchmentButtonInk;
import 'hatchery_screen.dart';
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'models/species_balance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'widgets/egg_card.dart';
import 'widgets/egg_details.dart';

/// ONE EGG, OPENED FROM THE BAG (user 2026-07-27: "sobald ich auf ein Ei
/// drücke. Komme ich in ein neues Menü, welches das Ei zusammen mit den Stats
/// zeigt, von wo ich es ausbrüten kann und in die Hatchery gelange").
///
/// The bag used to carry all of this on the row itself: a 🥚 glyph, the species
/// name and a button — and none of the numbers. That made the eggs in a bag
/// indistinguishable from each other, when the one thing that separates two
/// eggs of a species is the child frozen inside them (migration 0027).
///
/// So the bag became a grid of eggs and this is what a tap opens: the egg
/// itself, where it came from, the fourteen genes it will hatch with, and the
/// one action there is to take.
///
/// THE BUTTON GOES TO THE HATCHERY rather than incubating from here (the
/// standing rule since 2026-07-27: "Wenn ich bei einem Ei auf incubate drücke,
/// will ich in die hatchery kommen und es soll ausgewählt sein, nicht direkt
/// ausbrüten"). Committing a Hatchery slot from a page that shows neither how
/// many are free nor how long it takes is a decision made blind — over there
/// both are on screen, and the egg arrives already in the slot.
class EggDetailScreen extends StatefulWidget {
  final String eggId;

  const EggDetailScreen({super.key, required this.eggId});

  @override
  State<EggDetailScreen> createState() => _EggDetailScreenState();
}

class _EggDetailScreenState extends State<EggDetailScreen> {
  // The parchment palette every page reached from a building wears.
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);

  final _breeding = BreedingController();

  /// The egg, or null once it has left the bag (placed, hatched or discarded).
  BreedingJob? get _job {
    for (final j in _breeding.eggs) {
      if (j.id == widget.eggId) return j;
    }
    return null;
  }

  /// What an incubation will ACTUALLY take: the rarity base already cut by the
  /// hatchers posted at the Hatchery — the same quote its own button gives.
  double _hatchHours(SpeciesDef s) => breedingHours(
    kSpeciesBalance.of(s.rarity).hatchHours,
    SettlementController().hatchingPower(kHatcheryBuildingId),
  );

  Future<void> _discard(BreedingJob job) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kParchmentLight,
        title: Text(
          'Discard this egg?',
          style: FoE.title(size: 15).copyWith(color: _ink),
        ),
        content: Text(
          'It is gone for good — the child inside it is never born.',
          style: FoE.dim(size: 12).copyWith(color: _inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep',
              style: FoE.label(size: 12).copyWith(color: _ink),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Discard',
              style: FoE.label(size: 12).copyWith(color: FoE.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _breeding.cancel(job);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _breeding,
    builder: (context, _) {
      final job = _job;
      return ParchmentPage(
        // The SPECIES names the page — "Egg" alone would be the same title on
        // every one of them, and the shell below is the picture that says what
        // kind of object this is.
        title: job == null
            ? 'Egg'
            : kSpeciesDefs[job.speciesId]?.name ?? job.speciesId,
        child: job == null
            ? Center(
                child: Text(
                  'This egg has left your bag.',
                  style: FoE.dim(size: 12).copyWith(color: _inkSoft),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 12, ParchmentPage.kParchmentPagePad, 20),
                children: _body(job),
              ),
      );
    },
  );

  List<Widget> _body(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final free = _breeding.freeHatcherySlots > 0;
    final noHatchery = _breeding.hatcherySlots <= 0;
    return [
      // THE EGG IN THE MIDDLE, at the Hatchery slot's own size — half width,
      // not full: a lone tile stretched across the page reads as a banner
      // rather than as the object you are holding.
      Center(
        child: FractionallySizedBox(
          widthFactor: 0.46,
          child: AspectRatio(
            // The Monsters-grid cell shape, as everywhere an egg is shown.
            aspectRatio: 0.70,
            child: EggCard(job: job),
          ),
        ),
      ),
      const SizedBox(height: 12),
      EggFacts(job: job),
      const SizedBox(height: 12),
      EggGeneTable(job: job),
      const SizedBox(height: 16),
      // The one action, in the Hatchery's own button shape: what it does on
      // top, the wait it commits you to underneath — and the reason in place of
      // the label when the Hatchery cannot take it.
      GestureDetector(
        onTap: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HatcheryScreen(selectedEggId: job.id),
          ),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: parchmentButton(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                noHatchery ? 'Open the Hatchery' : 'Hatch',
                style: FoE.label(
                  size: 13,
                ).copyWith(color: parchmentButtonInk()),
              ),
              const SizedBox(height: 3),
              Text(
                noHatchery
                    ? 'No incubation slots yet'
                    : free && species != null
                        ? '${_hatchHours(species).round()}h'
                        : 'Hatchery full — free a slot there',
                style: FoE.dim(size: 10).copyWith(color: parchmentButtonInk()),
              ),
            ],
          ),
        ),
      ),
      // The button stays LIVE even with the Hatchery full or unbuilt (unlike
      // the Hatchery's own, which commits a slot): all this one does is take
      // you there, and being able to go and look at why is the point.
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: () => _discard(job),
          child: Text(
            'Discard egg',
            style: FoE.dim(size: 11).copyWith(color: FoE.danger),
          ),
        ),
      ),
      // A last line for the eggs that predate the frozen genes — the table
      // above already says it, but this is where the consequence lands.
      if (!job.hasChildGenes) ...[
        const SizedBox(height: 6),
        Text(
          'Its child is rolled at the moment it hatches.',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 10).copyWith(color: _inkFaint),
        ),
      ],
    ];
  }
}
