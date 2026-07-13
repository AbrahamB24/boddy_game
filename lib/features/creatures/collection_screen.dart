import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../workout/widgets/workout_back_button.dart';
import '../settlement/settlement_controller.dart';
import 'battle_screen.dart';
import 'bestiary_screen.dart';
import 'breeding_screen.dart';
import 'creature_detail_screen.dart';
import 'models/combatant.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creatures_controller.dart';

// The player's creature collection (FoE look, opened from the settlement's
// quick menu). Empty collection = one-time starter pick from all defined
// species; afterwards new creatures come from catching (phase 5) and
// breeding (phase 6).
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();

  @override
  void initState() {
    super.initState();
    _ctrl.load();
    // Blocks breeding parents out of the training-battle team.
    BreedingController().load();
  }

  Future<void> _adoptStarter(SpeciesDef species) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Choose ${species.name}?', style: FoE.title(size: 15)),
        content: Text(
          'Your starter accompanies you from the very beginning. This choice is final!',
          style: FoE.label(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: FoE.dim(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Choose',
              style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final created = await _ctrl.adoptStarter(species);
    if (created != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatureDetailScreen(creatureId: created.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoE.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _ctrl,
          builder: (context, _) => Column(
            children: [
              _topBar(),
              Expanded(
                child: _ctrl.isLoading && _ctrl.creatures.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: FoE.gold),
                      )
                    : _ctrl.creatures.isEmpty
                    ? _starterPicker()
                    : _collectionGrid(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Training battle vs. 1-3 random wild creatures near the team's level.
  // The stand-in fight until dungeons (phase 4) become the real entry point.
  Future<void> _startTrainingBattle() async {
    final team = _ctrl.battleTeam();
    if (team.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No battle-ready creature — all K.O.!',
            style: FoE.label(size: 13),
          ),
          backgroundColor: FoE.panelDark,
        ),
      );
      return;
    }
    final species = kSpeciesDefs.values.toList();
    if (species.isEmpty) return;
    final rng = math.Random();
    final avgLevel =
        (team.fold(0, (s, c) => s + c.level) / team.length).round();
    final enemies = List.generate(
      1 + rng.nextInt(math.min(3, species.length)),
      (i) => Combatant.fromSpecies(
        species[rng.nextInt(species.length)],
        level: math.max(1, avgLevel - 1 + rng.nextInt(3)),
        id: 'e_$i',
        rng: rng,
      ),
    );
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: team,
          enemies: enemies,
          title: '🌿 Training Battle',
        ),
      ),
    );
  }

  Widget _topBar() => Container(
    height: 48,
    decoration: FoE.topBarDecor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        WorkoutBackButton(
          color: FoE.parchment,
          onTap: () => Navigator.of(context).pop(),
        ),
        Text('🐾 Creatures', style: FoE.title(size: 15)),
        const Spacer(),
        Text('${_ctrl.creatures.length} collected', style: FoE.dim(size: 11)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BestiaryScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: FoE.btn(),
            child: Text('📖', style: FoE.label(size: 12)),
          ),
        ),
        const SizedBox(width: 6),
        if (_ctrl.creatures.isNotEmpty) ...[
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BreedingScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: FoE.btn(),
              child: Text('🥚 Breeding', style: FoE.label(size: 12)),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (_settlement.isDev && _ctrl.creatures.isNotEmpty) ...[
          GestureDetector(
            onTap: () => _ctrl.healAll(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: FoE.btn(),
              child: Text('🛠 Heal', style: FoE.label(size: 12)),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (_ctrl.creatures.isNotEmpty)
          GestureDetector(
            onTap: _startTrainingBattle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: FoE.btn(active: true),
              child: Text(
                '⚔️ Training',
                style: FoE.label(size: 12).copyWith(color: FoE.goldBright),
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    ),
  );

  // ── Starter pick (empty collection) ────────────────────────
  Widget _starterPicker() {
    final species = kSpeciesDefs.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (species.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No species defined yet.\nCreate them in Dev Mode (Species tab).',
            textAlign: TextAlign.center,
            style: FoE.label(size: 13),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
          child: Text('Choose your starter!', style: FoE.title(size: 18)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Your first creature — it starts at Level 5.',
            style: FoE.dim(size: 12),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: species.length,
            itemBuilder: (_, i) => _speciesCard(species[i]),
          ),
        ),
      ],
    );
  }

  Widget _speciesCard(SpeciesDef species) {
    return GestureDetector(
      onTap: () => _adoptStarter(species),
      child: Container(
        decoration: FoE.panel(radius: 10, overrideBorder: species.rarity.color),
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(child: _creatureImage(species.stageAt(0).imageUrl)),
            const SizedBox(height: 6),
            Text(
              species.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
            ),
            const SizedBox(height: 2),
            Text(
              '${species.element.emoji} ${species.element.label} · ${species.rarity.label}',
              style: FoE.dim(size: 10).copyWith(color: species.rarity.color),
            ),
          ],
        ),
      ),
    );
  }

  // ── Collection grid ────────────────────────────────────────
  Widget _collectionGrid() {
    final list = _ctrl.creatures;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _creatureCard(list[i]),
    );
  }

  Widget _creatureCard(CreatureInstance creature) {
    final species = creature.species;
    final rarityColor = species?.rarity.color ?? FoE.borderGold;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatureDetailScreen(creatureId: creature.id),
        ),
      ),
      child: Container(
        decoration: FoE.panel(radius: 10, overrideBorder: rarityColor),
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(child: _creatureImage(creature.imageUrl)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    creature.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                  ),
                ),
                Text(
                  creature.gender.symbol,
                  style: TextStyle(color: creature.gender.color, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  'Lv ${creature.level}',
                  style: FoE.value(size: 11).copyWith(color: FoE.goldBright),
                ),
                const Spacer(),
                if (species != null)
                  Text(
                    species.element.emoji,
                    style: const TextStyle(fontSize: 12),
                  ),
                if (creature.canEvolve)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.upgrade,
                      color: FoE.goldBright,
                      size: 13,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _creatureImage(String? url) => url == null
      ? const Center(child: Icon(Icons.pets, color: FoE.gold, size: 40))
      : Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.pets, color: FoE.gold, size: 40)),
        );
}
