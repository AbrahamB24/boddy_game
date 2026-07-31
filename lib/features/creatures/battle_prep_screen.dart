import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import 'models/combatant.dart';
import 'models/creature_instance.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_sprite.dart';
import 'services/battle_rewards.dart';
import 'services/combat_engine.dart';
import 'services/creatures_controller.dart';

// ── Pre-battle briefing (user 2026-07-24) ───────────────────
// Before a fight starts you see WHO you're fighting, WHAT clearing it unlocks,
// and you PICK the monster(s) you take in (up to the battle's party allowance).
// Pops the chosen team (in selection order) — or null if you back out.
class BattlePrepScreen extends StatefulWidget {
  final String title;
  final List<Combatant> enemies;
  final int partySize;
  final List<RewardLine> rewards;
  final bool isBoss;

  const BattlePrepScreen({
    super.key,
    required this.title,
    required this.enemies,
    required this.partySize,
    required this.rewards,
    this.isBoss = false,
  });

  @override
  State<BattlePrepScreen> createState() => _BattlePrepScreenState();
}

class _BattlePrepScreenState extends State<BattlePrepScreen> {
  final _ctrl = CreaturesController();

  /// Selected creature ids, kept in the order they were picked (first = the
  /// monster that leads the fight).
  final List<String> _selected = [];

  @override
  void initState() {
    super.initState();
    // Pre-select the default roster so a player can just hit Fight — the saved
    // active team if there is one (battleTeam honours it), else the first N
    // ready. Still fully re-pickable.
    final defaults = _ctrl.battleTeam(size: widget.partySize);
    final seed = defaults.isNotEmpty
        ? defaults
        : _ctrl.battleReadyCreatures.take(widget.partySize).toList();
    _selected.addAll(seed.map((c) => c.id));
  }

  void _toggle(CreatureInstance c) {
    setState(() {
      if (_selected.remove(c.id)) return;
      // At the cap: drop the earliest pick so tapping a new one always works.
      if (_selected.length >= widget.partySize && _selected.isNotEmpty) {
        _selected.removeAt(0);
      }
      _selected.add(c.id);
    });
  }

  List<CreatureInstance> get _team => _selected
      .map(_ctrl.byId)
      .whereType<CreatureInstance>()
      .toList();

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.battleReadyCreatures;
    return ParchmentPage(
      title: widget.title,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 12, ParchmentPage.kParchmentPagePad, 16),
              children: [

                _sectionTitle('⚔️ You face'),
                const SizedBox(height: 8),
                _enemyRow(),
                const SizedBox(height: 20),
                if (widget.rewards.isNotEmpty) ...[
                  _sectionTitle('🎁 Rewards for clearing this'),
                  const SizedBox(height: 8),
                  _rewardList(),
                  const SizedBox(height: 20),
                ],
                _sectionTitle(
                  'Your team · ${_selected.length}/${widget.partySize}',
                ),
                const SizedBox(height: 4),
                Text(
                  ready.isEmpty
                      ? 'No battle-ready monster — heal your team first.'
                      : 'Tap to pick up to ${widget.partySize} '
                          'monster${widget.partySize > 1 ? 's' : ''}. '
                          'Everyone you bring earns XP.',
                  style: FoE.dim(size: 12),
                ),
                // WHO ACTUALLY STANDS THERE (user 2026-07-27): up to three
                // fight at once and the rest wait. Worth saying here — you
                // pick six and see three, and the ORDER you pick in decides
                // which three, which nothing else on this screen reveals.
                if (widget.partySize > CombatEngine.kFieldSlots) ...[
                  const SizedBox(height: 3),
                  Text(
                    'The first ${CombatEngine.kFieldSlots} fight together — '
                    'the rest wait in reserve and step in when one falls.',
                    style: FoE.dim(size: 12).copyWith(color: FoE.gold),
                  ),
                ],
                const SizedBox(height: 10),
                _teamGrid(ready),
              ],
            ),
          ),
          _fightBar(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold));

  // ── Enemies ────────────────────────────────────────────────
  Widget _enemyRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final e in widget.enemies) _enemyCard(e)],
    );
  }

  Widget _enemyCard(Combatant e) {
    final color = e.element.color;
    return Container(
      width: 96,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FoE.panelDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: e.isBoss ? FoE.gold : color.withValues(alpha: 0.6),
          width: e.isBoss ? 2 : 1.4,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 52,
            child: e.imageUrl == null
                ? const Icon(Icons.pets, color: FoE.gold, size: 34)
                : CreatureSprite(
                    url: e.imageUrl!,
                    fallback: const Icon(Icons.pets, color: FoE.gold, size: 34),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            '${e.element.emoji} ${e.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 11).copyWith(color: FoE.parchment),
          ),
          Text(
            e.isBoss ? '👑 Boss · Lv ${e.level}' : 'Lv ${e.level}',
            style: FoE.dim(size: 10).copyWith(
              color: e.isBoss ? FoE.goldBright : FoE.textDim,
            ),
          ),
        ],
      ),
    );
  }

  // ── Rewards ────────────────────────────────────────────────
  Widget _rewardList() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: FoE.panel(radius: 12),
    child: Column(
      children: [
        for (final r in widget.rewards)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Text(r.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    r.text,
                    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  // ── Team picker ────────────────────────────────────────────
  Widget _teamGrid(List<CreatureInstance> ready) {
    if (ready.isEmpty) return const SizedBox.shrink();
    // THE monster tile, in the Monsters grid's own cell (user 2026-07-27:
    // "übernimm bitte überall genau diese Kachel für die Monster"). This screen
    // used to draw its own: a 104-px box with a sprite, a name, a level and an
    // HP bar — the same four facts the tile carries, in a different frame and a
    // different size, on the screen where you are choosing between the very
    // monsters the grid just showed you.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.70,
      ),
      itemCount: ready.length,
      itemBuilder: (_, i) => _pickCard(ready[i]),
    );
  }

  Widget _pickCard(CreatureInstance c) {
    final selected = _selected.contains(c.id);
    final order = _selected.indexOf(c.id);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: selected ? 1 : 0.62,
          child: CreatureCard(creature: c, onTap: () => _toggle(c)),
        ),
        // WHICH ONE, AND IN WHAT ORDER — the two things the tile itself cannot
        // say. The picked ones stand at full strength and the rest step back,
        // so the party reads off the grid without a frame around each tile.
        if (selected)
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: FoE.goldBright,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${order + 1}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Fight bar ──────────────────────────────────────────────
  Widget _fightBar() {
    final canFight = _selected.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: FoE.panelDark,
        border: Border(top: BorderSide(color: FoE.border)),
      ),
      child: GestureDetector(
        onTap: canFight ? () => Navigator.of(context).pop(_team) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: FoE.btn(active: canFight),
          child: Text(
            canFight
                ? '⚔️ Fight  (${_selected.length}/${widget.partySize})'
                : 'Pick at least one monster',
            style: FoE.label(size: 15).copyWith(
              color: canFight ? Colors.white : FoE.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
