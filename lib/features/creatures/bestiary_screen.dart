import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import 'creature_detail_screen.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_card.dart';
import '../common/widgets/recess_bar.dart';

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
                  : GridView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 4, ParchmentPage.kParchmentPagePad, 20),
                      // Same grid as the Monsters screen so the tiles read 1:1
                      // (user 2026-07-18).
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.70,
                      ),
                      itemCount: species.length,
                      itemBuilder: (_, i) => _dexCard(species[i]),
                    ),
            ),
          ],
        ),
      );
    },
  );

  /// The bestiary tile: the exact Monsters-screen card for a discovered species
  /// (using its highest-power owned creature), or a shrouded silhouette for one
  /// not yet discovered (user 2026-07-18).
  Widget _dexCard(SpeciesDef species) {
    final rep = _representativeFor(species.id);
    if (rep == null) {
      return CreatureCard.shrouded(
        shroudImageUrl: species.stageAt(0).imageUrl,
      );
    }
    return CreatureCard(
      creature: rep,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatureDetailScreen(creatureId: rep.id),
        ),
      ),
    );
  }
}
