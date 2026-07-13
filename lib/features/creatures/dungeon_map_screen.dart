import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../settlement/settlement_controller.dart';
import 'battle_screen.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/dungeon.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/catch_logic.dart';
import 'services/combat_engine.dart';
import 'services/creatures_controller.dart';

// ── Entry flow ──────────────────────────────────────────────
// Bottom sheet: pick a permanently-unlocked stage (1..dungeonMaxStage), see
// the entry cost (gold's decided spending sink) and the team, then pay &
// enter. The map itself is generated fresh per run; clearing a stage's boss
// permanently unlocks the next one (SettlementController.unlockDungeonStage).
Future<void> showDungeonEntrySheet(BuildContext context) async {
  final creatures = CreaturesController();
  await creatures.load();
  // Breeding jobs block their parents from the battle team — must be loaded
  // before battleTeam() filters.
  await BreedingController().load();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _DungeonEntrySheet(),
  );
}

class _DungeonEntrySheet extends StatefulWidget {
  const _DungeonEntrySheet();

  @override
  State<_DungeonEntrySheet> createState() => _DungeonEntrySheetState();
}

class _DungeonEntrySheetState extends State<_DungeonEntrySheet> {
  final _settlement = SettlementController();
  final _creatures = CreaturesController();
  late int _stage = _settlement.dungeonMaxStage;
  bool _starting = false;

  List<CreatureInstance> get _team => _creatures.battleTeam();

  Future<void> _start() async {
    if (kSpeciesDefs.isEmpty) {
      _snack('No species defined (Dev Mode → Species).');
      return;
    }
    if (_team.isEmpty) {
      _snack('No battle-ready creature — heal up or choose a starter first!');
      return;
    }
    setState(() => _starting = true);
    final paid = await _settlement.spendResources(dungeonEntryCost(_stage));
    if (!mounted) return;
    setState(() => _starting = false);
    if (!paid) {
      _snack('Not enough resources to enter.');
      return;
    }
    Navigator.pop(context); // close sheet
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            DungeonMapScreen(map: DungeonMap.generate(stage: _stage)),
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: FoE.label(size: 13)),
      backgroundColor: FoE.panelDark,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cost = dungeonEntryCost(_stage);
    final res = _settlement.resources;
    final affordable =
        res != null &&
        cost.entries.every((e) => (res.asMap[e.key] ?? 0) >= e.value);
    final isLegendary = _stage == kLegendaryStage;

    return Container(
      margin: const EdgeInsets.all(10),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: FoE.panel(radius: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏰 Enter Dungeon', style: FoE.title(size: 16)),
          const SizedBox(height: 4),
          Text(
            'Procedurally generated paths — rewards are kept even on '
            'defeat.',
            style: FoE.dim(size: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Stage', style: FoE.label(size: 13)),
              const Spacer(),
              _stepBtn(
                Icons.remove,
                _stage > 1 ? () => setState(() => _stage -= 1) : null,
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '$_stage/$kMaxDungeonStage',
                  textAlign: TextAlign.center,
                  style: FoE.value(size: 15).copyWith(color: FoE.goldBright),
                ),
              ),
              _stepBtn(
                Icons.add,
                _stage < _settlement.dungeonMaxStage
                    ? () => setState(() => _stage += 1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isLegendary
                ? '👑 Wild Lv ${wildLevelForStage(_stage)} · Boss Lv '
                      '${bossLevelForStage(_stage)} — the Legendary!'
                : 'Wild Lv ${wildLevelForStage(_stage)} · Boss Lv '
                      '${bossLevelForStage(_stage)}',
            style: FoE.dim(size: 11).copyWith(
              color: isLegendary ? FoE.goldBright : FoE.textDim,
            ),
          ),
          const SizedBox(height: 12),
          Text('Entry cost', style: FoE.dim(size: 11)),
          const SizedBox(height: 4),
          Row(
            children: [
              _costChip('🪙', cost['gold']!, res?.gold ?? 0),
              const SizedBox(width: 8),
              _costChip('🪵', cost['wood']!, res?.wood ?? 0),
              const SizedBox(width: 8),
              _costChip('🪨', cost['stone']!, res?.stone ?? 0),
            ],
          ),
          const SizedBox(height: 12),
          Text('Team (first 3 battle-ready)', style: FoE.dim(size: 11)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (_team.isEmpty)
                Text('— none —', style: FoE.label(size: 12)),
              for (final c in _team)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: FoE.panel(radius: 8),
                        child: c.imageUrl == null
                            ? const Icon(Icons.pets, color: FoE.gold, size: 22)
                            : Image.network(
                                c.imageUrl!,
                                width: 38,
                                height: 38,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.pets,
                                  color: FoE.gold,
                                  size: 22,
                                ),
                              ),
                      ),
                      const SizedBox(height: 2),
                      Text('Lv ${c.level}', style: FoE.dim(size: 9)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _starting || !affordable ? null : _start,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: FoE.btn(active: affordable),
                alignment: Alignment.center,
                child: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: FoE.goldBright,
                        ),
                      )
                    : Text(
                        affordable
                            ? 'Enter'
                            : 'Not enough resources',
                        style: FoE.label(size: 14).copyWith(
                          color: affordable ? FoE.goldBright : FoE.textDim,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: FoE.btn(active: onTap != null),
      child: Icon(
        icon,
        size: 16,
        color: onTap != null ? FoE.goldBright : FoE.textMuted,
      ),
    ),
  );

  Widget _costChip(String emoji, double cost, double have) {
    final ok = have >= cost;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: FoE.panel(radius: 8),
      child: Text(
        '$emoji ${cost.toStringAsFixed(0)}',
        style: FoE.label(
          size: 12,
        ).copyWith(color: ok ? FoE.parchment : Colors.redAccent),
      ),
    );
  }
}

// ── The run itself ──────────────────────────────────────────
class DungeonMapScreen extends StatefulWidget {
  final DungeonMap map;
  const DungeonMapScreen({super.key, required this.map});

  @override
  State<DungeonMapScreen> createState() => _DungeonMapScreenState();
}

class _DungeonMapScreenState extends State<DungeonMapScreen> {
  final _settlement = SettlementController();
  final _creatures = CreaturesController();
  final _rng = math.Random();

  String? _currentId;
  bool _failed = false;
  bool _completed = false;
  bool _resolving = false;

  // Run totals, shown in the end overlays. Credited live per space.
  double _gold = 0, _wood = 0, _stone = 0;
  int _spacesCleared = 0;

  DungeonMap get map => widget.map;

  List<CreatureInstance> get _team => _creatures.battleTeam();

  Set<String> get _selectableIds {
    if (_failed || _completed || _resolving) return {};
    if (_currentId == null) {
      return map.layer(0).map((n) => n.id).toSet();
    }
    return map.byId(_currentId!).next.toSet();
  }

  // ── Enemy generation ───────────────────────────────────────
  // Regular encounters roll from every species (species-gating hook: see
  // kActiveDungeonAllowedSpeciesIds — this is the only dungeon today, so it
  // stays unrestricted, but a future dungeon can narrow the pool here).
  List<SpeciesDef> get _pool {
    final all = kActiveDungeonAllowedSpeciesIds == null
        ? kSpeciesDefs.values
        : kSpeciesDefs.values.where(
            (s) => kActiveDungeonAllowedSpeciesIds!.contains(s.id),
          );
    return all.toList();
  }

  SpeciesDef _rollSpecies() {
    final all = _pool;
    final weights = {
      CreatureRarity.common: 45,
      CreatureRarity.uncommon: 28,
      CreatureRarity.rare: 17,
      CreatureRarity.epic: 8,
      CreatureRarity.legendary: 2,
    };
    final total = all.fold(0, (s, d) => s + (weights[d.rarity] ?? 1));
    var roll = _rng.nextInt(math.max(1, total));
    for (final d in all) {
      roll -= weights[d.rarity] ?? 1;
      if (roll < 0) return d;
    }
    return all.last;
  }

  /// Stage 9's boss IS the dungeon's Legendary (decided design) — every
  /// earlier stage gets a boss-worthy roll biased away from Common instead.
  SpeciesDef _rollBossSpecies() {
    if (map.isLegendaryStage) {
      final legendary = _pool.where(
        (s) => s.rarity == CreatureRarity.legendary,
      );
      if (legendary.isNotEmpty) return legendary.first;
    }
    final nonCommon = _pool
        .where((s) => s.rarity != CreatureRarity.common)
        .toList();
    if (nonCommon.isEmpty) return _rollSpecies();
    final weights = {
      CreatureRarity.uncommon: 40,
      CreatureRarity.rare: 35,
      CreatureRarity.epic: 20,
      CreatureRarity.legendary: 5,
    };
    final total = nonCommon.fold(0, (s, d) => s + (weights[d.rarity] ?? 1));
    var roll = _rng.nextInt(math.max(1, total));
    for (final d in nonCommon) {
      roll -= weights[d.rarity] ?? 1;
      if (roll < 0) return d;
    }
    return nonCommon.last;
  }

  List<Combatant> _enemiesFor(DungeonNode node) {
    final wildLvl = map.wildLevel;
    switch (node.type) {
      case DungeonNodeType.battle:
        // The very first fight of the very first dungeon stage must always
        // be winnable with a single fresh, unevolved Lvl-5 starter: one
        // Common enemy pitched a notch below the wild level, instead of the
        // usual 2-3-enemy pack. Every later battle node keeps normal odds.
        if (map.stage == 1 && node.layer == 0) {
          final commons = _pool
              .where((s) => s.rarity == CreatureRarity.common)
              .toList();
          final species = commons.isNotEmpty
              ? commons[_rng.nextInt(commons.length)]
              : _rollSpecies();
          return [
            Combatant.fromSpecies(
              species,
              level: math.max(1, wildLvl - 1),
              id: 'e_0',
              rng: _rng,
            ),
          ];
        }
        final count = 2 + _rng.nextInt(2);
        return List.generate(
          count,
          (i) => Combatant.fromSpecies(
            _rollSpecies(),
            level: math.max(1, wildLvl - 1 + _rng.nextInt(3)),
            id: 'e_$i',
            rng: _rng,
          ),
        );
      case DungeonNodeType.catchNode:
        // One noticeably stronger wild — the fight phase 5's guaranteed
        // catch attempt will hang off.
        return [
          Combatant.fromSpecies(
            _rollSpecies(),
            level: wildLvl + 3,
            id: 'e_0',
            rng: _rng,
          ),
        ];
      case DungeonNodeType.boss:
        final boss = Combatant.fromSpecies(
          _rollBossSpecies(),
          level: map.bossLevel,
          id: 'e_boss',
          rng: _rng,
          isBoss: true,
        );
        final minion = Combatant.fromSpecies(
          _rollSpecies(),
          level: math.max(1, wildLvl - 1),
          id: 'e_minion',
          rng: _rng,
        );
        return [boss, minion];
      case DungeonNodeType.heal:
        return const [];
    }
  }

  // ── Node resolution ────────────────────────────────────────
  Future<void> _enterNode(DungeonNode node) async {
    if (!_selectableIds.contains(node.id)) return;
    setState(() => _resolving = true);

    if (node.type == DungeonNodeType.heal) {
      // Heals the run's team (last battle participants) INCLUDING its K.O.
      // members — that's the whole point of a heal space. Falls back to the
      // first 3 creatures if no battle happened yet (can't normally occur:
      // layer 0 is always battle).
      final targets = _teamIds.isEmpty
          ? _creatures.creatures.take(3).toList()
          : _creatures.creatures
                .where((c) => _teamIds.contains(c.id))
                .toList();
      await _creatures.healTeam(targets);
      _clearNode(node);
      _snack('💚 Rest: team healed, K.O. creatures revived.');
      setState(() => _resolving = false);
      return;
    }

    final team = _team;
    if (team.isEmpty) {
      setState(() {
        _resolving = false;
        _failed = true;
      });
      return;
    }
    _teamIds = team.map((c) => c.id).toSet();

    final outcome = await Navigator.push<CombatOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: team,
          enemies: _enemiesFor(node),
          title:
              '${node.type.emoji} ${node.type.label} · Lv '
              '${node.type == DungeonNodeType.boss ? map.bossLevel : map.wildLevel}',
          // Decided: 1 catch attempt after every won dungeon fight (bosses
          // included — stage 9's boss only ever spawns as the Legendary, so
          // this is automatically "the" Legendary catch chance); the catch
          // SPACE's stronger single wild is a guaranteed catch instead.
          catchMode: node.type == DungeonNodeType.catchNode
              ? CatchMode.guaranteed
              : CatchMode.standard,
        ),
      ),
    );
    if (!mounted) return;

    switch (outcome) {
      case CombatOutcome.victory:
        // EP is split across the whole team (decided design), computed from
        // the engine's per-kill formula — applied via BattleScreen already
        // calling CreaturesController.applyBattleOutcome, so nothing extra
        // needed here beyond resource rewards.
        final reward = dungeonSpaceReward(map.stage, node.type);
        await _settlement.grantResources(reward);
        _gold += reward['gold'] ?? 0;
        _wood += reward['wood'] ?? 0;
        _stone += reward['stone'] ?? 0;
        _clearNode(node);
        if (node.type == DungeonNodeType.boss) {
          _completed = true;
          await _settlement.unlockDungeonStage(map.stage);
        }
      case CombatOutcome.defeat:
        _failed = true;
      case CombatOutcome.fled:
      case null:
        break; // stay where we are — the node can be retried
    }
    setState(() => _resolving = false);
  }

  Set<String> _teamIds = {};

  void _clearNode(DungeonNode node) {
    node.cleared = true;
    _currentId = node.id;
    _spacesCleared++;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: FoE.label(size: 13)),
      backgroundColor: FoE.panelDark,
    ),
  );

  Future<void> _confirmAbandon() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Leave dungeon?', style: FoE.title(size: 15)),
        content: Text(
          'Rewards earned so far are kept.',
          style: FoE.label(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Stay', style: FoE.dim(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Leave',
              style: FoE.label(size: 13).copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  // ── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _failed || _completed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmAbandon();
      },
      child: Scaffold(
        backgroundColor: FoE.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  Expanded(child: _mapView()),
                ],
              ),
              if (_failed || _completed) _endOverlay(),
            ],
          ),
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
        IconButton(
          icon: const Icon(Icons.close, color: FoE.parchment, size: 20),
          onPressed: _failed || _completed
              ? () => Navigator.of(context).pop()
              : _confirmAbandon,
        ),
        Text(
          '${map.isLegendaryStage ? '👑' : '🏰'} Stage ${map.stage}/$kMaxDungeonStage',
          style: FoE.title(size: 14),
        ),
        const Spacer(),
        Text(
          '🪙${_gold.toStringAsFixed(0)} 🪵${_wood.toStringAsFixed(0)} '
          '🪨${_stone.toStringAsFixed(0)}',
          style: FoE.dim(size: 10),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  // Layers drawn bottom (entrance) to top (boss), edges behind the nodes.
  Widget _mapView() {
    const rowH = 96.0;
    final height = map.layerCount * rowH + 40;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        Offset nodeCenter(DungeonNode n) {
          final layerNodes = map.layer(n.layer);
          final x = width * (n.index + 1) / (layerNodes.length + 1);
          final y = height - (n.layer + 0.5) * rowH - 20;
          return Offset(x, y);
        }

        return SingleChildScrollView(
          reverse: true, // start scrolled to the entrance at the bottom
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(width, height),
                  painter: _EdgePainter(map: map, centerOf: nodeCenter),
                ),
                for (final node in map.nodes)
                  _positionedNode(node, nodeCenter(node)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _positionedNode(DungeonNode node, Offset center) {
    final selectable = _selectableIds.contains(node.id);
    final isCurrent = node.id == _currentId;
    final isBoss = node.type == DungeonNodeType.boss;
    final size = isBoss ? 64.0 : 52.0;
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: GestureDetector(
        onTap: selectable ? () => _enterNode(node) : null,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: FoE.panelGradient,
            border: Border.all(
              color: selectable
                  ? Colors.greenAccent
                  : isCurrent
                  ? FoE.goldBright
                  : node.cleared
                  ? FoE.positive
                  : FoE.border,
              width: selectable || isCurrent ? 2.5 : 1.5,
            ),
            boxShadow: [
              if (selectable)
                BoxShadow(
                  color: Colors.greenAccent.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: node.cleared
              ? const Icon(Icons.check, color: FoE.goldBright, size: 20)
              : Text(
                  isBoss && map.isLegendaryStage ? '👑' : node.type.emoji,
                  style: TextStyle(fontSize: isBoss ? 26 : 20),
                ),
        ),
      ),
    );
  }

  Widget _endOverlay() {
    final (title, subtitle) = _completed
        ? (
            map.isLegendaryStage ? '👑 Legendary defeated!' : '🏆 Dungeon cleared!',
            map.stage < kMaxDungeonStage
                ? 'Stage ${map.stage + 1} is now unlocked.'
                : 'The boss is defeated.',
          )
        : ('💀 Run ended', 'Your team was defeated — you keep the loot.');
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 36),
        padding: const EdgeInsets.all(20),
        decoration: FoE.panel(radius: 12, glow: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: FoE.title(size: 18)),
            const SizedBox(height: 8),
            Text(subtitle, style: FoE.label(size: 13)),
            const SizedBox(height: 12),
            Text(
              'Loot: 🪙${_gold.toStringAsFixed(0)}  '
              '🪵${_wood.toStringAsFixed(0)}  🪨${_stone.toStringAsFixed(0)}\n'
              '$_spacesCleared rooms cleared',
              textAlign: TextAlign.center,
              style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: FoE.btn(active: true),
                  alignment: Alignment.center,
                  child: Text(
                    'Back to settlement',
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
}

class _EdgePainter extends CustomPainter {
  final DungeonMap map;
  final Offset Function(DungeonNode) centerOf;
  _EdgePainter({required this.map, required this.centerOf});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FoE.border
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final clearedPaint = Paint()
      ..color = FoE.gold.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final node in map.nodes) {
      final from = centerOf(node);
      for (final id in node.next) {
        final target = map.byId(id);
        final to = centerOf(target);
        // Both endpoints cleared = the path actually walked; highlight it.
        final walked = node.cleared && target.cleared;
        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(
            from.dx,
            from.dy - 30,
            to.dx,
            to.dy + 30,
            to.dx,
            to.dy,
          );
        canvas.drawPath(path, walked ? clearedPaint : paint);
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}
