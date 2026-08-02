import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import 'creature_detail_screen.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_sprite.dart';
import '../common/widgets/recess_bar.dart';
import '../settlement/widgets/scroll_paper.dart' show kParchmentInk;

// The bestiary (Dex) — the collection endgame.
//
// ── THE WHOLE LINE, NOT THE FIRST OF IT (user 2026-08-01: "beim bestiary will
// ich alle Monster haben, nicht nur stufe 1. Bitte immer alle drei
// nebeneinander") ──
//
// It showed ONE tile per species — your best owned creature, or a silhouette of
// stage 1. So a page meant to answer "what is there and how far have I got"
// showed a third of what there is, and the two forms every monster grows into
// were invisible until you happened to own one.
//
// Every species is a ROW now: its three stages side by side, in order, each one
// either its art or a silhouette. Progress reads along the row — how far this
// line has come for you — and down the page: how many lines you have started.
//
// "Discovered" = you own at least one creature of the species. A STAGE counts as
// seen when your best of that species has reached it (or been caught at it),
// which is the same rule the completion figures at the top have always used.
class BestiaryScreen extends StatefulWidget {
  const BestiaryScreen({super.key});

  @override
  State<BestiaryScreen> createState() => _BestiaryScreenState();
}

class _BestiaryScreenState extends State<BestiaryScreen> {
  final _ctrl = CreaturesController();

  @override
  void initState() {
    super.initState();
    _ctrl.load();
  }

  ({int owned, int bestStage}) _progressFor(String speciesId) {
    var owned = 0;
    var bestStage = -1;
    for (final c in _ctrl.creatures) {
      if (c.speciesId != speciesId) continue;
      owned++;
      if (c.stage > bestStage) bestStage = c.stage;
    }
    return (owned: owned, bestStage: bestStage);
  }

  /// The owned creature that represents a species on its bestiary tile: the one
  /// with the highest total power, if you hold several (user 2026-07-18). Null
  /// = undiscovered.
  CreatureInstance? _representativeFor(String speciesId) {
    CreatureInstance? best;
    for (final c in _ctrl.creatures) {
      if (c.speciesId != speciesId) continue;
      if (best == null || totalPower(c) > totalPower(best)) best = c;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) {
      final species = kSpeciesDefs.values.toList()
        ..sort((a, b) {
          final r = a.rarity.index.compareTo(b.rarity.index);
          return r != 0 ? r : a.name.compareTo(b.name);
        });
      final discovered =
          species.where((s) => _progressFor(s.id).owned > 0).length;
      final mastered =
          species.where((s) => _progressFor(s.id).bestStage >= 2).length;
      return ParchmentPage(
        title: 'Bestiary',
        trailing: Text(
          species.isEmpty
              ? ''
              : '${(discovered / species.length * 100).round()}%',
          style: FoE.value(size: 13).copyWith(color: FoE.gold),
        ),
        child: Column(
          children: [
            if (species.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 10, ParchmentPage.kParchmentPagePad, 0),
                child: Column(
                  children: [
                    RecessBar(
                      value: discovered / species.length,
                      color: FoE.gold,
                      height: 12,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$discovered/${species.length} discovered · '
                      '$mastered/${species.length} at final stage',
                      style: FoE.dim(size: 10),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: species.isEmpty
                  ? Center(
                      child: Text(
                        'No species defined yet.',
                        style: FoE.dim(size: 12),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        ParchmentPage.kParchmentPagePad,
                        6,
                        ParchmentPage.kParchmentPagePad,
                        20,
                      ),
                      itemCount: species.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _speciesRow(species[i]),
                    ),
            ),
          ],
        ),
      );
    },
  );

  /// ONE SPECIES, as its whole line: the three stages side by side.
  ///
  /// The row is a card on the page, so the three tiles read as one family
  /// rather than as three loose monsters — which is the entire point of showing
  /// them together.
  Widget _speciesRow(SpeciesDef species) {
    final progress = _progressFor(species.id);
    final rep = _representativeFor(species.id);
    final discovered = progress.owned > 0;
    return GestureDetector(
      // Tapping a line you have started opens your best of it. An undiscovered
      // line has nothing to open, and must not pretend otherwise.
      onTap: rep == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreatureDetailScreen(creatureId: rep.id),
                ),
              ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: ShapeDecoration(
          color: kParchmentInk.withValues(alpha: discovered ? 0.10 : 0.05),
          shape: FoE.facet(
            radius: 14,
            side: BorderSide(
              color: discovered
                  ? species.rarity.color.withValues(alpha: 0.6)
                  : kParchmentInk.withValues(alpha: 0.14),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(species.element.emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // An undiscovered species keeps its NAME hidden — the line
                    // is the reward, and the silhouettes are the tease.
                    discovered ? species.name : '???',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 13).copyWith(
                      color: discovered ? FoE.parchment : FoE.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  // How far this line has come: 0/3 through 3/3.
                  '${(progress.bestStage + 1).clamp(0, 3)}/3',
                  style: FoE.value(size: 11).copyWith(
                    color: progress.bestStage >= 2
                        ? FoE.positive
                        : discovered
                            ? FoE.gold
                            : FoE.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var stage = 0; stage < 3; stage++) ...[
                  if (stage > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _stageTile(
                      species,
                      stage,
                      seen: progress.bestStage >= stage,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One stage of a line: its art if you have got this far, else its own
  /// silhouette.
  ///
  /// The SILHOUETTE is the stage's real art blacked out, not a question mark —
  /// so an unreached form still shows you its shape, which is what makes a
  /// bestiary worth opening before it is full.
  Widget _stageTile(SpeciesDef species, int stage, {required bool seen}) {
    final def = species.stageAt(stage);
    final url = def.imageUrl;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: ShapeDecoration(
              color: kParchmentInk.withValues(alpha: seen ? 0.06 : 0.10),
              shape: FoE.facet(radius: 10),
            ),
            child: url == null
                ? Icon(Icons.help_outline, size: 20, color: FoE.textMuted)
                : seen
                    ? CreatureSprite(url: url)
                    : ColorFiltered(
                        // Flat black, no blur: the same hard-edged treatment
                        // the rest of the app gives a silhouette.
                        colorFilter: ColorFilter.mode(
                          kParchmentInk.withValues(alpha: 0.55),
                          BlendMode.srcIn,
                        ),
                        child: CreatureSprite(url: url),
                      ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          seen ? def.name : '· · ·',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: FoE.dim(size: 9).copyWith(
            color: seen ? FoE.textDim : FoE.textMuted,
          ),
        ),
      ],
    );
  }
}
