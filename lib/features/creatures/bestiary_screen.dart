import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../workout/widgets/workout_back_button.dart';
import 'models/species_def.dart';
import 'services/creatures_controller.dart';

// The bestiary (Dex) — the collection endgame: every defined species, with
// undiscovered ones shown as dark silhouettes. "Discovered" = you own (or
// owned... currently: own) at least one creature of the species; per species
// it also shows how many you hold and the highest evolution stage you've
// reached, so 100% completion means every species at final stage.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoE.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _ctrl,
          builder: (context, _) {
            final species = kSpeciesDefs.values.toList()
              ..sort((a, b) {
                final r = a.rarity.index.compareTo(b.rarity.index);
                return r != 0 ? r : a.name.compareTo(b.name);
              });
            final discovered = species
                .where((s) => _progressFor(s.id).owned > 0)
                .length;
            final mastered = species
                .where((s) => _progressFor(s.id).bestStage >= 2)
                .length;
            return Column(
              children: [
                _topBar(discovered, species.length),
                if (species.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: species.isEmpty
                                ? 0
                                : discovered / species.length,
                            minHeight: 8,
                            backgroundColor: FoE.panelDark,
                            color: FoE.goldBright,
                          ),
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
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 130,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.8,
                              ),
                          itemCount: species.length,
                          itemBuilder: (_, i) => _dexCard(species[i]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(int discovered, int total) => Container(
    height: 48,
    decoration: FoE.topBarDecor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        WorkoutBackButton(
          color: FoE.parchment,
          onTap: () => Navigator.of(context).pop(),
        ),
        Text('📖 Bestiary', style: FoE.title(size: 15)),
        const Spacer(),
        Text(
          total == 0 ? '' : '${(discovered / total * 100).round()}%',
          style: FoE.value(size: 13).copyWith(color: FoE.goldBright),
        ),
        const SizedBox(width: 12),
      ],
    ),
  );

  Widget _dexCard(SpeciesDef species) {
    final progress = _progressFor(species.id);
    final discovered = progress.owned > 0;
    // Show the best stage reached — undiscovered species show stage 0 as a
    // black silhouette and hide every detail.
    final stage = discovered ? progress.bestStage : 0;
    final imageUrl = species.stageAt(stage.clamp(0, 2)).imageUrl;

    Widget image = imageUrl == null
        ? Icon(
            Icons.pets,
            color: discovered ? FoE.gold : Colors.black87,
            size: 36,
          )
        : Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.pets, color: FoE.gold, size: 36),
          );
    if (!discovered && imageUrl != null) {
      // Silhouette: paint every non-transparent pixel near-black.
      image = ColorFiltered(
        colorFilter: const ColorFilter.mode(
          Color(0xE6000000),
          BlendMode.srcIn,
        ),
        child: image,
      );
    }

    return Container(
      decoration: FoE.panel(
        radius: 10,
        overrideBorder: discovered ? species.rarity.color : null,
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(child: image),
          const SizedBox(height: 4),
          Text(
            discovered ? species.name : '???',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 11).copyWith(
              color: discovered ? FoE.parchment : FoE.textDim,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            discovered
                ? '${species.element.emoji} ×${progress.owned} · '
                      'Stage ${progress.bestStage + 1}/3'
                : species.rarity.label,
            style: FoE.dim(size: 9).copyWith(
              color: discovered ? FoE.gold : species.rarity.color,
            ),
          ),
        ],
      ),
    );
  }
}
