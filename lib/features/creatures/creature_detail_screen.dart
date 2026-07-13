import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../workout/widgets/workout_back_button.dart';
import '../settlement/data/tech_definitions.dart';
import '../settlement/settlement_controller.dart';
import 'models/ability_def.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';

// One creature: stats (with IVs), XP progress, abilities and the evolution
// flow (BP-gated). Takes the ID and resolves against the controller on every
// build so rename/evolve/release updates are always reflected.
class CreatureDetailScreen extends StatefulWidget {
  final String creatureId;
  const CreatureDetailScreen({super.key, required this.creatureId});

  @override
  State<CreatureDetailScreen> createState() => _CreatureDetailScreenState();
}

class _CreatureDetailScreenState extends State<CreatureDetailScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();
  bool _evolving = false;

  CreatureInstance? get _creature {
    for (final c in _ctrl.creatures) {
      if (c.id == widget.creatureId) return c;
    }
    return null;
  }

  Future<void> _evolve(CreatureInstance creature) async {
    setState(() => _evolving = true);
    final error = await _ctrl.evolve(creature);
    if (!mounted) return;
    setState(() => _evolving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? '✨ ${creature.displayName} evolved!',
          style: FoE.label(size: 13).copyWith(
            color: error == null ? FoE.goldBright : Colors.redAccent,
          ),
        ),
        backgroundColor: FoE.panelDark,
      ),
    );
  }

  Future<void> _rename(CreatureInstance creature) async {
    final controller = TextEditingController(
      text: creature.nickname ?? '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Nickname', style: FoE.title(size: 15)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: FoE.label(size: 14).copyWith(color: FoE.parchment),
          decoration: InputDecoration(
            hintText: 'Empty = species name',
            hintStyle: FoE.dim(size: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: FoE.dim(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              'Save',
              style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
            ),
          ),
        ],
      ),
    );
    if (name != null) await _ctrl.rename(creature, name);
  }

  Future<void> _release(CreatureInstance creature) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Release?', style: FoE.title(size: 15)),
        content: Text(
          '${creature.displayName} leaves you forever.',
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
              'Release',
              style: FoE.label(size: 13).copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      final error = await _ctrl.release(creature);
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error, style: FoE.label(size: 13)),
            backgroundColor: FoE.panelDark,
          ),
        );
        return;
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoE.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_ctrl, _settlement]),
          builder: (context, _) {
            final creature = _creature;
            if (creature == null) {
              return Center(
                child: Text('Creature not found', style: FoE.label()),
              );
            }
            return Column(
              children: [
                _topBar(creature),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _header(creature),
                      const SizedBox(height: 12),
                      _xpPanel(creature),
                      const SizedBox(height: 12),
                      if (creature.stage < 2) ...[
                        _evolutionPanel(creature),
                        const SizedBox(height: 12),
                      ],
                      _statsPanel(creature),
                      const SizedBox(height: 12),
                      _abilitiesPanel(creature),
                      const SizedBox(height: 12),
                      _actionsRow(creature),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(CreatureInstance creature) => Container(
    height: 48,
    decoration: FoE.topBarDecor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        WorkoutBackButton(
          color: FoE.parchment,
          onTap: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Text(
            creature.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.title(size: 15),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit, color: FoE.gold, size: 18),
          onPressed: () => _rename(creature),
        ),
      ],
    ),
  );

  Widget _header(CreatureInstance creature) {
    final species = creature.species;
    final rarityColor = species?.rarity.color ?? FoE.borderGold;
    return Container(
      decoration: FoE.panel(radius: 12, overrideBorder: rarityColor, glow: true),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            height: 110,
            child: creature.imageUrl == null
                ? const Icon(Icons.pets, color: FoE.gold, size: 56)
                : Image.network(
                    creature.imageUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.pets, color: FoE.gold, size: 56),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        creature.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.title(size: 17),
                      ),
                    ),
                    Text(
                      creature.gender.symbol,
                      style: TextStyle(
                        color: creature.gender.color,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (species != null) ...[
                  Text(
                    '${species.element.emoji} ${species.element.label}',
                    style: FoE.label(size: 12),
                  ),
                  Text(
                    species.rarity.label,
                    style: FoE.label(size: 12).copyWith(color: rarityColor),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Stage ${creature.stage + 1}/3 · Lv ${creature.level}',
                  style: FoE.value(size: 13).copyWith(color: FoE.goldBright),
                ),
                if (creature.isKo)
                  Text(
                    '💤 K.O. — needs healing',
                    style: FoE.dim(size: 11).copyWith(color: Colors.redAccent),
                  ),
                if (creature.assignedStat != null)
                  Text(
                    '🔨 Working: ${creature.assignedStat!.label}',
                    style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _xpPanel(CreatureInstance creature) {
    final atMax = creature.level >= kCreatureMaxLevel;
    final toNext = xpToNextLevel(creature.level);
    final progress = atMax ? 1.0 : (creature.xp / toNext).clamp(0.0, 1.0);
    return Container(
      decoration: FoE.panel(radius: 10),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Experience', style: FoE.title(size: 12)),
              const Spacer(),
              Text(
                atMax ? 'MAX' : '${creature.xp} / $toNext XP',
                style: FoE.dim(size: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: FoE.panelDark,
              color: FoE.goldBright,
            ),
          ),
        ],
      ),
    );
  }

  Widget _evolutionPanel(CreatureInstance creature) {
    final species = creature.species;
    if (species == null) return const SizedBox();
    final targetStage = creature.stage + 1;
    final reqLevel = species.evoLevelFrom(creature.stage);
    final cost = creature.nextEvolutionCostBp ?? 0;
    final levelOk = creature.level >= reqLevel;
    final bpOk = _settlement.bp >= cost;
    // Research gate — only once the tech def exists as content.
    final techDef = kTechDefs[kEvolutionTechIds[creature.stage.clamp(0, 1)]];
    final techOk =
        techDef == null || _settlement.unlockedTechs.contains(techDef.id);
    final ready = levelOk && bpOk && techOk && !_evolving;
    return Container(
      decoration: FoE.panel(
        radius: 10,
        overrideBorder: ready ? FoE.goldBright : null,
        glow: ready,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Evolution', style: FoE.title(size: 12)),
          const SizedBox(height: 6),
          Text(
            '→ ${species.stageAt(targetStage).name}',
            style: FoE.label(size: 14).copyWith(color: FoE.parchment),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                levelOk ? Icons.check_circle : Icons.lock,
                size: 14,
                color: levelOk ? Colors.greenAccent : FoE.textDim,
              ),
              const SizedBox(width: 4),
              Text('Level $reqLevel', style: FoE.dim(size: 11)),
              const SizedBox(width: 14),
              Icon(
                bpOk ? Icons.check_circle : Icons.lock,
                size: 14,
                color: bpOk ? Colors.greenAccent : FoE.textDim,
              ),
              const SizedBox(width: 4),
              Text(
                '$cost BP (you have ${_settlement.bp})',
                style: FoE.dim(size: 11),
              ),
            ],
          ),
          if (techDef != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  techOk ? Icons.check_circle : Icons.lock,
                  size: 14,
                  color: techOk ? Colors.greenAccent : FoE.textDim,
                ),
                const SizedBox(width: 4),
                Text(
                  'Research: ${techDef.name}',
                  style: FoE.dim(size: 11),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: ready ? () => _evolve(creature) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: FoE.btn(active: ready),
                alignment: Alignment.center,
                child: _evolving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: FoE.goldBright,
                        ),
                      )
                    : Text(
                        ready
                            ? '✨ Evolve ($cost BP)'
                            : !levelOk
                            ? 'Requires Level $reqLevel'
                            : !techOk
                            ? 'Research "${techDef.name}" required'
                            : 'Not enough BP — work out!',
                        style: FoE.label(size: 13).copyWith(
                          color: ready ? FoE.goldBright : FoE.textDim,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsPanel(CreatureInstance creature) {
    // Bars scaled against the creature's own best stat so the profile shape
    // (tank? fast? caster?) reads at a glance. Combat and civilian (work)
    // stats are grouped separately since they serve different systems.
    final values = {
      for (final s in CreatureStat.values) s: creature.statValue(s),
    };
    final maxVal = values.values.reduce((a, b) => a > b ? a : b);

    Widget statRow(CreatureStat stat) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(stat.label, style: FoE.label(size: 12)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: maxVal > 0 ? values[stat]! / maxVal : 0,
                minHeight: 6,
                backgroundColor: FoE.panelDark,
                color: stat.isCombat ? FoE.gold : const Color(0xFF6B8E4E),
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              '${values[stat]}  '
              '(${(creature.statBase[stat] ?? 0).toStringAsFixed(1)}'
              '·${(creature.statSlope[stat] ?? 0).toStringAsFixed(2)})',
              textAlign: TextAlign.right,
              style: FoE.value(size: 10),
            ),
          ),
        ],
      ),
    );

    return Container(
      decoration: FoE.panel(radius: 10),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Combat stats', style: FoE.title(size: 12)),
              const Spacer(),
              Text('(Base · Growth/Lv)', style: FoE.dim(size: 9)),
            ],
          ),
          const SizedBox(height: 10),
          for (final stat in kCombatStats) statRow(stat),
          const SizedBox(height: 6),
          Text('Work stats', style: FoE.title(size: 12)),
          const SizedBox(height: 10),
          for (final stat in kCivilianStats) statRow(stat),
        ],
      ),
    );
  }

  Widget _abilitiesPanel(CreatureInstance creature) {
    final species = creature.species;
    final abilities = List.of(species?.abilities ?? const [])
      ..sort((a, b) => a.unlockStage.compareTo(b.unlockStage));
    return Container(
      decoration: FoE.panel(radius: 10),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Abilities', style: FoE.title(size: 12)),
          const SizedBox(height: 8),
          if (abilities.isEmpty)
            Text('No abilities defined.', style: FoE.dim(size: 11)),
          for (final sa in abilities)
            _abilityRow(creature, sa.abilityId, sa.unlockStage),
        ],
      ),
    );
  }

  Widget _abilityRow(CreatureInstance creature, String abilityId, int unlockStage) {
    final ability = kAbilityDefs[abilityId];
    final unlocked = creature.stage >= unlockStage;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: unlocked ? 1 : 0.45,
        child: Row(
          children: [
            Text(
              ability?.element?.emoji ?? '⚔️',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ability?.name ?? abilityId,
                    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                  ),
                  Text(
                    ability == null
                        ? 'Unknown ability'
                        : '${ability.kind.label} · Power ${ability.power} · ${ability.energyCost} ⚡',
                    style: FoE.dim(size: 10),
                  ),
                ],
              ),
            ),
            Text(
              unlocked ? '✓' : 'Stage ${unlockStage + 1}',
              style: FoE.dim(size: 11).copyWith(
                color: unlocked ? Colors.greenAccent : FoE.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsRow(CreatureInstance creature) {
    return Row(
      children: [
        if (_settlement.isDev)
          Expanded(
            child: GestureDetector(
              onTap: () => _ctrl.devGainXp(creature, 500),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: FoE.btn(),
                alignment: Alignment.center,
                child: Text('🛠 +500 XP (Dev)', style: FoE.label(size: 12)),
              ),
            ),
          ),
        if (_settlement.isDev) const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _release(creature),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: FoE.btn(),
              alignment: Alignment.center,
              child: Text(
                'Release',
                style: FoE.label(size: 12).copyWith(color: Colors.redAccent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
