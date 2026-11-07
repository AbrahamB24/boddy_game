import 'package:flutter/material.dart' hide Text;

import '../../core/theme/foe_theme.dart';
import '../../core/theme/cream_kit.dart';
import 'creature_detail_screen.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_sprite.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

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

/// Evolution stages every species has. The tile row and the completion figures
/// both need it, and when it lived as a bare `3` in the row only, the header
/// counted SPECIES while the grid showed stages — "1/15" under forty-five
/// pictures (user 2026-08-04).
const int kBestiaryStages = 3;

/// How much of the bestiary [owned] fills in: stages SEEN out of every stage of
/// every species. A stage counts as seen once your best of that species has
/// reached it — the rule the tiles use to un-silhouette, and the one the
/// completion figure at the top of the Bestiary uses. The Monsters screen's
/// Bestiary hub shows the same figure.
({int seen, int total}) bestiaryProgress(Iterable<CreatureInstance> owned) {
  final best = <String, int>{};
  for (final c in owned) {
    if (c.stage > (best[c.speciesId] ?? -1)) best[c.speciesId] = c.stage;
  }
  var seen = 0;
  for (final id in kSpeciesDefs.keys) {
    seen += ((best[id] ?? -1) + 1).clamp(0, kBestiaryStages);
  }
  return (seen: seen, total: kSpeciesDefs.length * kBestiaryStages);
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
      // STAGES, not species. The grid shows every species at all three of its
      // stages, so counting species made the header disagree with what is on
      // screen underneath it. A stage counts as seen once your best of that
      // species has reached it — the same rule the tiles use to un-silhouette.
      final totalStages = species.length * kBestiaryStages;
      final discovered = species.fold<int>(
        0,
        (n, s) =>
            n + (_progressFor(s.id).bestStage + 1).clamp(0, kBestiaryStages),
      );
      final mastered = species
          .where((s) => _progressFor(s.id).bestStage >= kBestiaryStages - 1)
          .length;
      return MenuScaffold(
        title: 'Bestiary',
        trailing: species.isEmpty
            ? null
            : Text(
                '${(discovered / totalStages * 100).round()} %',
                style: FoE.value(size: 13).copyWith(color: kBoxAccent),
              ),
        child: species.isEmpty
            ? Center(
                child: Text(
                  'No species defined yet.',
                  style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                ),
              )
            // No card of its own any more (user 2026-09-30, "hier und
            // andernorts sind noch die alten Kästchen vorhanden") —
            // MenuScaffold is already the one card on screen; the progress
            // bar keeps a light [zoneBox] so it still reads as its own
            // readout above the grid.
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // How far the whole book is filled in.
                  zoneBox(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      children: [
                        RecessBar(
                          value: discovered / totalStages,
                          color: CreamPalette.gold,
                          height: 12,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$discovered/$totalStages stages seen · '
                          '$mastered/${species.length} species fully evolved',
                          style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Two lines of species side by side — a landscape screen has
                  // the width, and a line is only ~440 px of it.
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 452,
                            // Card padding (24) + header row (~18) + gap (8) +
                            // the square stage tiles (as wide as a 452-column
                            // allows, so ~137 tall at aspect 1) + gap (3) +
                            // stage name line (~13) — 156 was too short and
                            // clipped the bottom row (user-reported overflow).
                            mainAxisExtent: 214,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      itemCount: species.length,
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
    return Pressable(
      // Tapping a line you have started opens your best of it. An undiscovered
      // line has nothing to open, and must not pretend otherwise.
      onTap: rep == null
          ? null
          : () => pushMenu(context, CreatureDetailScreen(creatureId: rep.id)),
      // A cream card, its rim the species' rarity once you have started the
      // line; an unreached line is the kit's grey locked tile.
      child: Container(
        decoration: discovered
            ? BoxDecoration(
                borderRadius: vr(15),
                border: Border.all(
                  color: species.rarity.color.withValues(alpha: 0.75),
                  width: 2,
                ),
              )
            : null,
        child: _lineCard(
          discovered: discovered,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    species.element.emoji,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      // An undiscovered species keeps its NAME hidden — the line
                      // is the reward, and the silhouettes are the tease.
                      discovered ? species.name : '???',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(size: 13).copyWith(
                        color: discovered ? kBoxInk : kBoxInkFaint,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  Text(
                    // How far this line has come: 0/3 through 3/3.
                    '${(progress.bestStage + 1).clamp(0, 3)}/3',
                    style: FoE.value(size: 11).copyWith(
                      color: progress.bestStage >= 2
                          ? CreamPalette.better
                          : discovered
                          ? CreamPalette.accent
                          : kBoxInkFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var stage = 0; stage < kBestiaryStages; stage++) ...[
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
      ),
    );
  }

  /// The surface of one species line: a raised tile either way — lit once
  /// you have started it (user 2026-09-30: a grid of cream cards read as a
  /// grid of tiny page-cards, not a grid of items — the same tile family
  /// every other list in the app stands its rows on), grey and locked
  /// before.
  Widget _lineCard({required bool discovered, required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: raisedTile(locked: !discovered, radius: 14),
        child: child,
      );

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
              color: CreamPalette.tan.withValues(alpha: seen ? 0.12 : 0.2),
              shape: FoE.facet(radius: 10),
            ),
            child: url == null
                ? PixelIcon(Icons.help_outline, size: 20, color: kBoxInkFaint)
                : seen
                ? CreatureSprite(url: url)
                : ColorFiltered(
                    // Flat black, no blur: the same hard-edged treatment
                    // the rest of the app gives a silhouette.
                    colorFilter: ColorFilter.mode(
                      // Light on the dark tile (Nacht, 2026-11-03).
                      kBoxInk.withValues(alpha: 0.42),
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
          style: FoE.dim(
            size: 9,
          ).copyWith(color: seen ? kBoxInkSoft : kBoxInkFaint),
        ),
      ],
    );
  }
}
