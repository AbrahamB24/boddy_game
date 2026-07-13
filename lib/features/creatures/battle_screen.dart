import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import 'models/ability_def.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'services/catch_logic.dart';
import 'services/combat_engine.dart';
import 'services/creatures_controller.dart';

// The JRPG battle screen: enemies on top, the player's team below, the CTB
// initiative bar across the top and an action panel when it's a player
// creature's turn. Enemy turns (and player turns with auto-battle on) run on
// a short delay so the flow is readable. On finish the outcome is written
// back to the collection (pools always, XP on victory) and the screen pops
// with the CombatOutcome as its result.
class BattleScreen extends StatefulWidget {
  final List<CreatureInstance> team;
  final List<Combatant> enemies;
  final String title;

  /// One catch attempt after victory (decided: 1 per won fight). Training
  /// battles pass `none` so dungeons stay the only source of new creatures.
  final CatchMode catchMode;

  const BattleScreen({
    super.key,
    required this.team,
    required this.enemies,
    this.title = 'Battle',
    this.catchMode = CatchMode.none,
  });

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  late final CombatEngine _engine;
  Timer? _autoTimer;
  bool _autoBattle = false;
  bool _outcomeApplied = false;

  // Pending player action awaiting a target tap (null = choosing action).
  _PendingAction? _pending;

  // Catch state (victory overlay): one attempt per battle, decided design.
  Combatant? _catchTarget;
  bool _catchAttempted = false;
  bool _catching = false;
  String? _catchResult;

  @override
  void initState() {
    super.initState();
    _engine = CombatEngine(
      players: widget.team.map(Combatant.fromInstance).toList(),
      enemies: widget.enemies,
    );
    _engine.addListener(_onEngineChanged);
    // Kick the loop in case an enemy is fastest and acts first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEngineChanged());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleAutoIfNeeded();
  }

  // Enemy turns always run automatically; player turns only with the auto
  // toggle. One timer at a time — every engine change reschedules.
  void _scheduleAutoIfNeeded() {
    _autoTimer?.cancel();
    if (_engine.outcome != null) {
      _applyOutcome();
      return;
    }
    final actorIsPlayer = _engine.isPlayerTurn;
    if (!actorIsPlayer || _autoBattle) {
      _pending = null;
      _autoTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted && _engine.outcome == null) _engine.performAutoAction();
      });
    }
  }

  /// XP is split across the whole team (decided design) rather than each
  /// member getting the full pool — the engine computes the raw total,
  /// division by team size happens here at the one call site.
  int get _xpEach {
    if (_engine.outcome != CombatOutcome.victory || _engine.players.isEmpty) {
      return 0;
    }
    return (_engine.totalXpReward / _engine.players.length).round();
  }

  Future<void> _applyOutcome() async {
    if (_outcomeApplied) return;
    _outcomeApplied = true;
    await CreaturesController().applyBattleOutcome(
      _engine.players,
      xpEach: _xpEach,
    );
  }

  void _pickAbility(AbilityDef ability) {
    final actor = _engine.currentActor;
    // Abilities without a single-target choice resolve immediately.
    if (ability.target == AbilityTarget.allEnemies ||
        ability.target == AbilityTarget.allAllies ||
        ability.target == AbilityTarget.self) {
      final error = _engine.useAbility(actor, ability, null);
      if (error != null) _showError(error);
      return;
    }
    setState(() => _pending = _PendingAction(ability: ability));
  }

  void _tapCombatant(Combatant target) {
    final pending = _pending;
    if (pending == null || !_engine.isPlayerTurn) return;
    final actor = _engine.currentActor;
    final wantsAlly = pending.ability != null &&
        pending.ability!.target == AbilityTarget.ally;
    if (wantsAlly != target.isPlayerSide && pending.ability != null) return;
    if (pending.ability == null && target.isPlayerSide) return;
    if (!target.alive) return;

    setState(() => _pending = null);
    if (pending.ability == null) {
      _engine.basicAttack(actor, target);
    } else {
      final error = _engine.useAbility(actor, pending.ability!, target);
      if (error != null) _showError(error);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: FoE.label(size: 13)),
        backgroundColor: FoE.panelDark,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _engine.outcome != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmFlee();
      },
      child: Scaffold(
        backgroundColor: FoE.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  _initiativeBar(),
                  const SizedBox(height: 8),
                  Expanded(child: _enemyArea()),
                  _logLine(),
                  Expanded(child: _playerArea()),
                  _actionPanel(),
                ],
              ),
              if (_engine.outcome != null) _endOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmFlee() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Flee?', style: FoE.title(size: 15)),
        content: Text(
          'The battle ends with no reward. HP and energy stay as they are.',
          style: FoE.label(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep fighting', style: FoE.dim(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Flee',
              style: FoE.label(size: 13).copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) _engine.flee();
  }

  Widget _topBar() => Container(
    height: 44,
    decoration: FoE.topBarDecor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.flag, color: FoE.parchment, size: 18),
          tooltip: 'Flee',
          onPressed: _engine.outcome == null ? _confirmFlee : null,
        ),
        Expanded(
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: FoE.title(size: 14),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() => _autoBattle = !_autoBattle);
            _scheduleAutoIfNeeded();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: FoE.btn(active: _autoBattle),
            child: Text(
              'AUTO',
              style: FoE.label(size: 11).copyWith(
                color: _autoBattle ? FoE.goldBright : FoE.textDim,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );

  // ── Initiative bar (CTB queue) ────────────────────────────
  Widget _initiativeBar() {
    final order = _engine.forecast(8);
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Text('Turn order', style: FoE.dim(size: 9)),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: order.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final c = order[i];
                final first = i == 0;
                return Container(
                  width: first ? 40 : 34,
                  height: first ? 40 : 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: FoE.panelMid,
                    border: Border.all(
                      color: c.isPlayerSide ? FoE.goldBright : FoE.danger,
                      width: first ? 2 : 1,
                    ),
                  ),
                  child: ClipOval(child: _portrait(c, size: first ? 22 : 18)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Battlefield ───────────────────────────────────────────
  Widget _enemyArea() => _sideArea(_engine.enemies, isEnemyRow: true);
  Widget _playerArea() => _sideArea(_engine.players, isEnemyRow: false);

  Widget _sideArea(List<Combatant> side, {required bool isEnemyRow}) {
    final selectable = _selectableSide(isEnemyRow);
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (final c in side)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _combatantCard(c, selectable: selectable && c.alive),
              ),
          ],
        ),
      ),
    );
  }

  bool _selectableSide(bool isEnemyRow) {
    final pending = _pending;
    if (pending == null || !_engine.isPlayerTurn) return false;
    if (pending.ability == null) return isEnemyRow; // basic attack
    return switch (pending.ability!.target) {
      AbilityTarget.enemy => isEnemyRow,
      AbilityTarget.ally => !isEnemyRow,
      _ => false,
    };
  }

  Widget _combatantCard(Combatant c, {required bool selectable}) {
    final isActor =
        _engine.outcome == null && _engine.currentActor == c && c.alive;
    return GestureDetector(
      onTap: selectable ? () => _tapCombatant(c) : null,
      child: Opacity(
        opacity: c.alive ? 1 : 0.35,
        child: Container(
          width: 110,
          padding: const EdgeInsets.all(8),
          decoration: FoE.panel(
            radius: 10,
            overrideBorder: selectable
                ? Colors.greenAccent
                : isActor
                ? FoE.goldBright
                : null,
            glow: selectable || isActor,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 52, child: _portrait(c, size: 34)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(size: 11).copyWith(color: FoE.parchment),
                    ),
                  ),
                  if (c.hasted)
                    const Text('⏫', style: TextStyle(fontSize: 12)),
                  if (c.slowed)
                    const Text('⏬', style: TextStyle(fontSize: 12)),
                ],
              ),
              Text(
                '${c.element.emoji} Lv ${c.level}',
                style: FoE.dim(size: 9),
              ),
              const SizedBox(height: 4),
              _bar(c.hp / c.maxHp, const Color(0xFF3BAE38), '${c.hp}'),
              if (c.isPlayerSide) ...[
                const SizedBox(height: 3),
                _bar(
                  c.maxEnergy > 0 ? c.energy / c.maxEnergy : 0,
                  const Color(0xFF2196F3),
                  '${c.energy}⚡',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(double fraction, Color color, String label) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: FoE.panelDark,
            color: color,
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: FoE.dim(size: 9)),
    ],
  );

  Widget _portrait(Combatant c, {required double size}) => c.imageUrl == null
      ? Icon(Icons.pets, color: FoE.gold, size: size)
      : Image.network(
          c.imageUrl!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Icon(Icons.pets, color: FoE.gold, size: size),
        );

  Widget _logLine() => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 10),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: FoE.panel(radius: 8),
    child: Text(
      _engine.lastAction.isEmpty ? 'The battle begins!' : _engine.lastAction,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: FoE.label(size: 11),
    ),
  );

  // ── Action panel ──────────────────────────────────────────
  Widget _actionPanel() {
    if (_engine.outcome != null) return const SizedBox(height: 8);
    if (!_engine.isPlayerTurn || _autoBattle) {
      return Container(
        height: 56,
        alignment: Alignment.center,
        child: Text(
          _autoBattle ? 'Auto-battle running…' : 'Enemy is acting…',
          style: FoE.dim(size: 12),
        ),
      );
    }
    final actor = _engine.currentActor;
    if (_pending != null) {
      final forAlly =
          _pending!.ability != null &&
          _pending!.ability!.target == AbilityTarget.ally;
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                forAlly ? 'Choose an ally…' : 'Choose a target…',
                style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _pending = null),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: FoE.btn(),
                child: Text('Cancel', style: FoE.label(size: 12)),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                "${actor.name}'s turn",
                style: FoE.label(size: 12).copyWith(color: FoE.goldBright),
              ),
              const Spacer(),
              Text('${actor.energy}/${actor.maxEnergy} ⚡', style: FoE.dim(size: 11)),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _actionBtn(
                  '⚔️ Attack (+$kBasicAttackEnergyGain⚡)',
                  enabled: true,
                  onTap: () =>
                      setState(() => _pending = _PendingAction(ability: null)),
                ),
                for (final ability in actor.abilities)
                  _actionBtn(
                    '${ability.element?.emoji ?? '✦'} ${ability.name} (${ability.energyCost}⚡)',
                    enabled: actor.energy >= ability.energyCost,
                    onTap: () => _pickAbility(ability),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    String label, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: FoE.btn(active: enabled),
          child: Text(
            label,
            style: FoE.label(size: 12).copyWith(
              color: enabled ? FoE.parchment : FoE.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  // ── End overlay ───────────────────────────────────────────
  Widget _endOverlay() {
    final outcome = _engine.outcome!;
    final (title, subtitle) = switch (outcome) {
      CombatOutcome.victory => (
        '🏆 Victory!',
        '+$_xpEach XP per team member',
      ),
      CombatOutcome.defeat => (
        '💀 Defeat…',
        'Your team needs healing.',
      ),
      CombatOutcome.fled => ('🏃 Fled', 'No reward.'),
    };
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(20),
        decoration: FoE.panel(radius: 12, glow: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: FoE.title(size: 20)),
            const SizedBox(height: 8),
            Text(subtitle, style: FoE.label(size: 13)),
            if (outcome == CombatOutcome.victory &&
                widget.catchMode != CatchMode.none) ...[
              const SizedBox(height: 14),
              _catchSection(),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(outcome),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: FoE.btn(active: true),
                  alignment: Alignment.center,
                  child: Text(
                    'Continue',
                    style: FoE.label(size: 14).copyWith(color: FoE.goldBright),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Catch attempt (victory only) ──────────────────────────
  List<Combatant> get _catchables =>
      _engine.enemies.where((e) => e.speciesId != null).toList();

  Future<void> _attemptCatch() async {
    final catchables = _catchables;
    if (catchables.isEmpty || _catchAttempted || _catching) return;
    final target = _catchTarget ?? catchables.first;
    setState(() => _catching = true);

    final chance = widget.catchMode == CatchMode.guaranteed
        ? 1.0
        : catchChance(target: target, team: _engine.players);
    final success = _engine.rng.nextDouble() < chance;

    String result;
    if (success) {
      final created = await CreaturesController().captureWild(target);
      result = created != null
          ? '🎉 Caught ${target.name} (Lv ${target.level})!'
          : 'Save failed — not caught.';
    } else {
      result = '💨 ${target.name} got away…';
    }
    if (!mounted) return;
    setState(() {
      _catching = false;
      _catchAttempted = true;
      _catchResult = result;
    });
  }

  Widget _catchSection() {
    if (_catchAttempted) {
      return Text(
        _catchResult ?? '',
        textAlign: TextAlign.center,
        style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
      );
    }
    final catchables = _catchables;
    if (catchables.isEmpty) return const SizedBox();
    // Captured monsters occupy housing — a full settlement can't take another.
    if (CreaturesController().housingFull) {
      return Text(
        '🏠 Settlement full — build more housing to catch new creatures.',
        textAlign: TextAlign.center,
        style: FoE.label(size: 12).copyWith(color: Colors.redAccent),
      );
    }
    final selected = _catchTarget ?? catchables.first;
    return Column(
      children: [
        Text(
          widget.catchMode == CatchMode.guaranteed
              ? '🪤 Guaranteed catch — choose your target:'
              : '🪤 One catch attempt — choose your target:',
          style: FoE.label(size: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: [
            for (final e in catchables)
              GestureDetector(
                onTap: () => setState(() => _catchTarget = e),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: FoE.btn(active: e == selected),
                  child: Text(
                    '${e.name} · Lv ${e.level} · '
                    '${widget.catchMode == CatchMode.guaranteed ? '100' : (catchChance(target: e, team: _engine.players) * 100).round()}%',
                    style: FoE.label(size: 11).copyWith(
                      color: e == selected ? FoE.goldBright : FoE.parchment,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: _catching ? null : _attemptCatch,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: FoE.btn(active: true),
              alignment: Alignment.center,
              child: _catching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FoE.goldBright,
                      ),
                    )
                  : Text(
                      '🪤 Catch!',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: FoE.goldBright),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingAction {
  /// null = basic attack (always targets an enemy).
  final AbilityDef? ability;
  const _PendingAction({required this.ability});
}
