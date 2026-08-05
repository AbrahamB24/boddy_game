import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import 'models/combatant.dart';
import 'models/creature_instance.dart';
import 'widgets/creature_backdrop.dart';
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
  /// ── THE ENEMY LOOKS LIKE A MONSTER (user 2026-08-04) ──
  /// It was a 96-px bordered box with a small sprite, a name and a level, laid
  /// out beside a grid of full monster tiles. Two ways of drawing the same kind
  /// of thing on one screen, and the comparison you are about to make — my six
  /// against their three — was the one thing the layout made hard.
  ///
  /// So the enemies use the monster tile's geometry: the same grid, the same
  /// aspect, the same element backdrop under the art, the same deepened strip
  /// carrying the name, the same rounded shape and the same pop-out band above
  /// the tile for the sprite to break into.
  ///
  /// It is a MATCHED tile, not literally [CreatureCard]: that widget is built
  /// on a CreatureInstance with a species, XP and HP behind it, and an enemy
  /// has none of those. Faking an instance to reuse the widget would put a lie
  /// in the model to save a hundred lines in the view. What is shared instead
  /// is the vocabulary — [CreatureBackdrop], [FoE.facet], the strip tones —
  /// so the two cannot drift apart on the things a player actually sees.
  Widget _enemyRow() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.only(top: 2),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.70,
    ),
    itemCount: widget.enemies.length,
    itemBuilder: (_, i) => _enemyCard(widget.enemies[i]),
  );

  Widget _enemyCard(Combatant e) {
    final element = e.element.color;
    final stripDark = Color.lerp(element, Colors.black, 0.46)!;
    return LayoutBuilder(
      builder: (context, c) {
        // The same three numbers the monster tile uses, for the same reasons:
        // a strip tall enough for two lines, and a band above the tile the art
        // is allowed to break into so the sprite reads as standing in front of
        // its card rather than boxed inside it.
        const stripH = 44.0;
        final topReserve = c.maxHeight * 0.17;
        return Stack(
          children: [
            Positioned(
              top: topReserve,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: stripDark,
                  shape: FoE.facet(
                    radius: 22,
                    // A boss is the one enemy worth a frame. Everything else
                    // says what it is by its element alone, exactly as my own
                    // monsters do.
                    side: e.isBoss
                        ? const BorderSide(color: FoE.goldBright, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CreatureBackdrop(
                        element: e.element,
                        radius: 0,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    SizedBox(
                      height: stripH,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FoE.label(size: 12).copyWith(
                                color: FoE.parchment,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              e.isBoss ? '👑 Boss · Lv ${e.level}'
                                  : '${e.element.emoji} Lv ${e.level}',
                              maxLines: 1,
                              style: FoE.dim(size: 10).copyWith(
                                color: e.isBoss ? FoE.goldBright : FoE.textDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The sprite, breaking up out of the tile.
            Positioned(
              left: 4,
              right: 4,
              top: 0,
              bottom: stripH + 4,
              child: e.imageUrl == null
                  ? const Icon(Icons.pets, color: FoE.gold, size: 34)
                  : CreatureSprite(
                      url: e.imageUrl!,
                      fallback:
                          const Icon(Icons.pets, color: FoE.gold, size: 34),
                    ),
            ),
          ],
        );
      },
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
