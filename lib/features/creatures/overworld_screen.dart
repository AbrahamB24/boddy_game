import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/fachwerk.dart' show Fachwerk;
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../settlement/settlement_controller.dart';
import 'models/area.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart' show creatureLevelCap;
import 'models/creature_instance.dart';
import 'models/path_node.dart' show regionForBattle;
import 'models/species_def.dart' show kSpeciesDefs;
import 'widgets/creature_card.dart';
import 'widgets/overworld_focus.dart';
import 'widgets/star_row.dart';
import 'widgets/stars_overview.dart';
import 'services/star_overview.dart' show starTotals;
import 'battle_prep_screen.dart';
import 'battle_screen.dart';
import 'services/battle_rewards.dart';
import 'services/combat_engine.dart' show CombatOutcome;
import 'survival_screen.dart' show openSurvivalMode;
import 'services/creatures_controller.dart';
import 'services/overworld_layout.dart';
import 'services/overworld_path.dart';
import 'services/region_dungeon.dart'
    show spawnPathBattle, scriptedFirstBattleEnemy;
import '../../core/theme/voxel_icons.dart';
import '../../core/theme/voxel_kit.dart' show VoxelBackdrop, vr;
import '../../core/ui/game_text.dart';

// ── The Overworld (the campaign) ────────────────────────────
// ONE straight line you climb (linear rebuild 2026-07-24). Numbered BATTLES,
// each a little stronger. Fighting the CURRENT battle and winning steps you up
// the line (grows the party, unlocks buildings), and a region boss unlocks the
// next region + its legendary. The line itself comes from
// services/overworld_layout.dart.
//
// "Nächster Kampf im Fokus" (user 2026-11-03, concept 5 of 10) replaced the
// road on grass: a strip of EVERY battle with its stars, and the picked battle
// filling the page under it (widgets/overworld_focus.dart). Tapping a battle
// PICKS it; tapping the picked one again fights it.
class OverworldScreen extends StatefulWidget {
  const OverworldScreen({super.key});

  @override
  State<OverworldScreen> createState() => _OverworldScreenState();
}

class _OverworldScreenState extends State<OverworldScreen> {
  final _settlement = SettlementController();

  /// The battle strip's scroll — only ever moves when the line is longer than
  /// the screen is wide; then it opens on the current battle.
  final _strip = ScrollController();

  /// True for the whole tutorial visit to this screen — back is blocked the
  /// entire time, and the spotlight below lights up battle 1 as the one
  /// thing to press, from the very first frame rather than after a separate
  /// one-time popup (user 2026-09-03).
  bool get _tutorialLocksThisScreen =>
      _settlement.introStep == IntroStep.firstNode;

  /// The battle number the player has picked; null = the current one.
  int? _selected;

  /// The foes of each battle, worked out once for the view. (They are seeded by
  /// area + battle number, or authored on the node — the same list every time —
  /// but a Combatant is mutable, so a FIGHT always builds its own fresh ones;
  /// these are for looking at.) The tutorial's scripted first fight is never
  /// cached: it depends on the starter, which may not be loaded yet.
  final Map<int, List<Combatant>> _foesSeen = {};

  @override
  void initState() {
    super.initState();
    _settlement.addListener(_onChange);
    // The scripted first fight's enemy depends on the starter, which loads a
    // moment after this screen opens.
    CreaturesController().addListener(_onChange);
    CreaturesController().load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _settlement.removeListener(_onChange);
    CreaturesController().removeListener(_onChange);
    _strip.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // Cached, not a getter: buildLinearOverworld allocates and interleaves, and
  // the settlement's 5s ticker keeps rebuilding this screen while it's pushed.
  List<OverworldNode>? _nodesCache;
  String? _nodesKey;

  /// Every battle on the line, in order — battle 1 up to the boss of the
  /// region being worked through (later regions are not shown).
  List<OverworldNode> get _nodes {
    final key = '${_settlement.battlesCleared}|${kAreaDefs.length}';
    if (_nodesKey == key && _nodesCache != null) return _nodesCache!;
    _nodesKey = key;
    return _nodesCache = buildLinearOverworld(
      battlesCleared: _settlement.battlesCleared,
    )..sort((a, b) => a.battleNumber.compareTo(b.battleNumber));
  }

  /// The node the view is about: the picked one, else the current battle,
  /// else (a fully cleared line) the last.
  OverworldNode? get _selectedNode {
    final nodes = _nodes;
    if (nodes.isEmpty) return null;
    if (_selected != null) {
      for (final n in nodes) {
        if (n.battleNumber == _selected) return n;
      }
    }
    for (final n in nodes) {
      if (n.state == OverworldNodeState.current) return n;
    }
    return nodes.last;
  }

  // ── The layout ─────────────────────────────────────────────
  //
  // "NÄCHSTER KAMPF IM FOKUS" (user 2026-11-03, concept 5 of 10): the road on
  // grass is gone. On the app's normal ground: the header, then ONE strip with
  // every battle of the line and the stars earned on each, then the picked
  // battle filling the rest — its facts and reward on the left, its enemies
  // big on the right with the Fight button.

  static const double _kChipMin = 38;
  static const double _kChipMax = 58;
  static const double _kChipGap = 5;
  static const double _kStripH = 56;

  @override
  Widget build(BuildContext context) {
    final node = _selectedNode;
    // Back is blocked for the whole tutorial visit (user 2026-09-02) — both
    // the system gesture (PopScope) and the header's own button.
    return PopScope(
      canPop: !_tutorialLocksThisScreen,
      child: Scaffold(
        backgroundColor: CreamPalette.groundBottom,
        body: Stack(
          children: [
            const Positioned.fill(
              child: VoxelBackdrop(color: CreamPalette.groundTop),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(),
                  const SizedBox(height: 8),
                  SizedBox(height: _kStripH, child: _battleStrip()),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      child: node == null ? const SizedBox() : _focus(node),
                    ),
                  ),
                ],
              ),
            ),
            // Up from the very first frame of the tutorial visit — lights up
            // battle 1 alone and dead-zones everything else (user 2026-09-30:
            // "kurz erklären, dass es die Kampagnenkarte ist und du jetzt den
            // ersten Kampf bestreiten sollst").
            if (_tutorialLocksThisScreen)
              const IntroSpotlightOverlay(
                anchorName: 'overworld-node-1',
                hint:
                    'This is your path of battles — tap the first one to '
                    'begin.',
              ),
          ],
        ),
      ),
    );
  }

  /// EVERY battle of the line in one row, with its stars (user 2026-11-03:
  /// "Füge bei den Kämpfen oben noch die gesammelten Sterne hinzu und
  /// idealerweise werden alle 20 Kämpfe gezeigt"). The chips share the width;
  /// only a line too long for even the smallest chip scrolls.
  Widget _battleStrip() {
    final nodes = _nodes;
    final picked = _selectedNode?.battleNumber;
    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - 20;
        final n = nodes.length;
        final w = n == 0
            ? _kChipMax
            : ((avail - (n - 1) * _kChipGap) / n).clamp(_kChipMin, _kChipMax);
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: _kChipGap),
              _chip(nodes[i], w, picked: nodes[i].battleNumber == picked),
            ],
          ],
        );
        return SingleChildScrollView(
          controller: _strip,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: avail),
            child: Center(child: row),
          ),
        );
      },
    );
  }

  /// One battle: its number (a crown for a boss) and its stars under it —
  /// cleared ones in the button colour, the current one cream with a gold
  /// rim, locked ones faint. The PICKED one wears a white ring.
  Widget _chip(OverworldNode node, double width, {required bool picked}) {
    final done = node.state == OverworldNodeState.done;
    final current = node.state == OverworldNodeState.current;
    final locked = node.state == OverworldNodeState.locked;
    final stars = _settlement.starsFor(node.battleNumber);
    final Color fill = done
        ? CreamPalette.gold
        : current
        ? const Color(0xFFF6EFE0)
        : CreamPalette.lockedTop;
    final Color ink = done || current ? CreamPalette.ink : kBoxInkFaint;
    final chip = Pressable(
      key: ValueKey('battle-chip-${node.battleNumber}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _onNodeTap(node),
      child: Container(
        width: width,
        height: _kStripH,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: vr(10),
          border: Border.all(
            color: picked
                ? Colors.white
                : current || node.isBoss
                ? Fachwerk.windowGlow
                : Colors.transparent,
            width: picked ? 3 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: done ? CreamPalette.goldDeep : CreamPalette.lockedShadow,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            node.isBoss
                ? PixelIcon(
                    Icons.workspace_premium_rounded,
                    size: 20,
                    color: locked ? kBoxInkFaint : Fachwerk.windowGlow,
                  )
                : Text(
                    '${node.battleNumber}',
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.1,
                      fontWeight: FontWeight.w400,
                      color: ink,
                    ),
                  ),
            const SizedBox(height: 3),
            if (!locked)
              StarRow(
                count: stars,
                size: (width / 4.2).clamp(8.0, 12.0),
                empty: ink.withValues(alpha: 0.3),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
    // The tutorial's ONE lit target (user 2026-09-02: "highlighte den 1.
    // Node") — see the IntroSpotlightOverlay in [build].
    final anchor = node.battleNumber == 1
        ? IntroSpotlightAnchors.of('overworld-node-1')
        : null;
    return anchor == null ? chip : KeyedSubtree(key: anchor, child: chip);
  }

  /// Puts the current battle in view when the strip is longer than the screen.
  void _scrollToCurrent() {
    if (!mounted || !_strip.hasClients) return;
    final nodes = _nodes;
    final i = nodes.indexWhere((n) => n.state == OverworldNodeState.current);
    if (i < 0) return;
    final pos = _strip.position;
    final step = _kChipMin + _kChipGap;
    _strip.jumpTo(
      (i * step - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent),
    );
  }

  Widget _focus(OverworldNode node) {
    final nodes = _nodes;
    final i = nodes.indexOf(node);
    final area = areaForBattle(node.battleNumber);
    return OverworldFocusView(
      battleNumber: node.battleNumber,
      isBoss: node.isBoss,
      state: node.state,
      regionName: area?.name,
      stars: _settlement.starsFor(node.battleNumber),
      enemies: _foesFor(node),
      // Only the current battle grants its unlocks (a re-fight is XP only, see
      // [_launchBattle]); the ones still ahead show what they will grant.
      rewards: node.state == OverworldNodeState.done
          ? const []
          : battleRewardsFor(node.battleNumber),
      onFight: () => _launchBattle(node),
      noTeam: CreaturesController().battleReadyCreatures.isEmpty,
      onPrev: i > 0
          ? () => setState(() => _selected = nodes[i - 1].battleNumber)
          : null,
      onNext: i >= 0 && i < nodes.length - 1
          ? () => setState(() => _selected = nodes[i + 1].battleNumber)
          : null,
    );
  }

  /// A tap PICKS a battle (the view follows); a tap on the one already picked
  /// fights it — so the tutorial's "tap the first battle" still goes straight
  /// in, the current battle being picked from the start.
  void _onNodeTap(OverworldNode node) {
    if (node.battleNumber == _selectedNode?.battleNumber) {
      _launchBattle(node);
    } else {
      setState(() => _selected = node.battleNumber);
    }
  }

  /// The wood band on top, like the battle's: back, the title, and the door to
  /// Survival Mode (user 2026-09-06) — both hidden during the tutorial, because
  /// a lit control that leads off the guided chain reads as broken, not as a
  /// bonus feature (user 2026-09-02: "zurück sollte nicht anwählbar sein").
  Widget _topBar() => ParchmentHeader.band(
    height: 46,
    fill: CreamPalette.groundTop,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Text(
            'Overworld',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: kBoxInk,
            ),
          ),
          const Spacer(),
          // ALL the stars at a glance (user 2026-09-28) — a tap opens the
          // region-by-region overview. Hidden in the tutorial like Survival.
          if (!_tutorialLocksThisScreen) ...[
            _starsChip(),
            const SizedBox(width: 8),
          ],
          if (!_tutorialLocksThisScreen)
            Pressable(
              onTap: () => openSurvivalMode(context),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: raisedTile(radius: 12),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PixelIcon(
                      Icons.whatshot_rounded,
                      size: 16,
                      color: CreamPalette.warn,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Survival',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: kBoxInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // The kit's one leaving button, right end of the title row like every
          // other screen (user 2026-09-22).
          if (!_tutorialLocksThisScreen) ...[
            const SizedBox(width: 10),
            const KitCloseButton(),
          ],
        ],
      ),
    ),
  );

  /// "★ 23 / 60": every star earned over every star there is; opens the overview.
  Widget _starsChip() {
    final t = starTotals(
      stars: _settlement.battleStars,
      battlesCleared: _settlement.battlesCleared,
    );
    return Pressable(
      onTap: () => showStarsOverview(
        context,
        stars: _settlement.battleStars,
        battlesCleared: _settlement.battlesCleared,
      ),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: raisedTile(radius: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PixelIcon(
              Icons.star_rounded,
              size: 17,
              color: CreamPalette.gold,
            ),
            const SizedBox(width: 4),
            Text(
              '${t.earned} / ${t.max}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: kBoxInk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Foes ───────────────────────────────────────────────────

  /// The tutorial's first two nodes can't be lost: while either is the current
  /// step, its enemies fight at kJumpstartEnemyStatMult.
  IntroStep? _introStepFor(OverworldNode node) => switch (node.battleNumber) {
    1 => IntroStep.firstNode,
    2 => IntroStep.secondNode,
    _ => null,
  };

  bool _guaranteedWin(OverworldNode node) {
    final step = _introStepFor(node);
    return step != null && _settlement.introStep == step;
  }

  /// The foes [node] fields, freshly built. Battle 1's fight is fully scripted
  /// (user 2026-09-03): a hand-picked, type-effective enemy at its natural stats
  /// rather than a random pick scaled uniformly down — see
  /// scriptedFirstBattleEnemy's own doc for why.
  List<Combatant>? _buildFoes(OverworldNode node, AreaDef area) {
    final guaranteedWin = _guaranteedWin(node);
    if (node.battleNumber == 1 && guaranteedWin) {
      final starterElement =
          CreaturesController().creatures.firstOrNull?.species?.element;
      final enemy = starterElement == null
          ? null
          : scriptedFirstBattleEnemy(area, starterElement);
      return enemy == null ? null : [enemy];
    }
    return spawnPathBattle(
      area,
      node.battleNumber,
      statScale: guaranteedWin ? kJumpstartEnemyStatMult : 1.0,
    );
  }

  /// The foes for the card — remembered, so a rebuild is not a re-spawn.
  List<Combatant>? _foesFor(OverworldNode node) {
    final area = areaForBattle(node.battleNumber);
    if (area == null) return null;
    if (_guaranteedWin(node)) return _buildFoes(node, area);
    final seen = _foesSeen[node.battleNumber];
    if (seen != null) return seen;
    final built = _buildFoes(node, area);
    if (built != null) _foesSeen[node.battleNumber] = built;
    return built;
  }

  Future<void> _launchBattle(OverworldNode node) async {
    if (node.state == OverworldNodeState.locked) {
      context.snack('Win the battle below this one first.');
      return;
    }
    final area = areaForBattle(node.battleNumber);
    if (area == null) {
      context.snack('No monsters live this far yet.');
      return;
    }
    final introNodeStep = _introStepFor(node);
    final enemies = _buildFoes(node, area);
    if (enemies == null || enemies.isEmpty) {
      context.snack('No monsters live here yet (Dev Mode → Species).');
      return;
    }
    // A stable non-null binding — `enemies` itself can't promote across the
    // closures below (MaterialPageRoute's builder).
    final resolvedEnemies = enemies;
    if (CreaturesController().battleReadyCreatures.isEmpty) {
      context.snack('No battle-ready monster — heal up first!');
      return;
    }
    final title = node.isBoss
        ? '👑 ${area.name} — Boss'
        : 'Battle ${node.battleNumber}';
    // Only clearing the CURRENT node grants the map unlocks, so only preview
    // rewards there (a re-fight just gives XP).
    final isFrontier = node.state == OverworldNodeState.current;
    final rewards = isFrontier
        ? battleRewardsFor(node.battleNumber)
        : const <RewardLine>[];

    // PRE-BATTLE briefing: pick the team, see the foes + rewards (user
    // 2026-07-24). Cancelling (null) backs out without a fight.
    final team = await Navigator.push<List<CreatureInstance>>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePrepScreen(
          title: title,
          enemies: resolvedEnemies,
          partySize: node.partySize,
          rewards: rewards,
          isBoss: node.isBoss,
        ),
      ),
    );
    if (!mounted || team == null || team.isEmpty) return;

    final outcome = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: team,
          enemies: resolvedEnemies,
          title: title,
          // Judged for stars (see battle_stars.dart).
          battleNumber: node.battleNumber,
          victoryRewards: rewards,
          // WHERE the fight happens — the battlefield's art comes from here
          // (user 2026-07-31).
          area: area,
        ),
      ),
    );
    if (!mounted) return;
    // Straight back to the settlement after the tutorial's FIRST fight (user
    // 2026-09-06) rather than staying on this map — node 2 would otherwise
    // sit right there, tappable before the buildHealingHut → buildRoad →
    // assignHealer → healStarter → firstCapture steps in between have run.
    //
    // Popped BEFORE the awaited bookkeeping below, not after (user report
    // 2026-09-30: "Nach dem Kampf kommt ganz kurz noch der Weg, bevor es zum
    // Homescreen geht" — the awaits are real network round-trips, and this
    // screen sat fully visible for however long they took before the old
    // code finally popped). SettlementController is a singleton the
    // settlement screen already reacts to, so advancing it after leaving
    // this route still lands correctly; nothing here needs `context` again.
    if (introNodeStep == IntroStep.firstNode) Navigator.pop(context);
    // Only clearing the CURRENT node moves the line forward.
    if (outcome == CombatOutcome.victory && isFrontier) {
      await _settlement.advanceBattlesCleared(toBattle: node.battleNumber);
      if (node.isBoss) await _grantBossRewards(area, node.battleNumber);
      if (introNodeStep != null) await _settlement.advanceIntro(introNodeStep);
      // The card moves on to the next battle.
      _selected = null;
    }
    if (introNodeStep == IntroStep.firstNode) return;
    if (!mounted) return;
    setState(() {});
  }

  /// After a region boss falls the FIRST time: unlock the next region
  /// (rides on dungeonMaxStage) and award the region legendary. Fully
  /// automatic (user 2026-09-05: eras and the paid Castle ascension are
  /// gone) — the next region's buildings/costs/level cap apply the instant
  /// this returns, nothing left to pay for or trigger separately.
  Future<void> _grantBossRewards(AreaDef area, int battleNumber) async {
    final region = regionForBattle(battleNumber); // == area.battleStage
    final firstClear = _settlement.dungeonMaxStage <= region;
    await _settlement.unlockDungeonStage(region);
    if (!firstClear) return;
    final legendary = kSpeciesDefs[area.bossSpeciesId];
    if (legendary == null) return;
    final caught = await CreaturesController().captureWild(
      Combatant.fromSpecies(
        legendary,
        level: enemyLevelForBattle(battleNumber),
        id: 'legendary',
        isBoss: true,
      ),
      force: true,
    );
    if (!mounted) return;
    // THE milestone of a region — boss down, a legendary joins, the level cap
    // rises. It used to be announced only through a snack, and snacks have
    // been silent since 2026-08-29, so the biggest reward in the game landed
    // without a word. A ceremony, not a toast: one dialog, closed by hand.
    Feel.fanfare();
    final cap = creatureLevelCap(_settlement.dungeonMaxStage);
    await showDialog<void>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (_) => ParchmentDialog(
        title: '👑 ${area.name} cleared!',
        closeLabel: 'Onwards',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (caught != null)
                SizedBox(
                  width: 110,
                  child: CreatureCard(creature: caught, showHp: false),
                ),
              if (caught != null) const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (caught != null)
                      Text(
                        '${caught.displayName} joins you!',
                        style: FoE.title(size: 16).copyWith(color: kBoxInk),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'The next region is open, with new monsters and new '
                      'buildings.',
                      style: FoE.label(size: 12).copyWith(color: kBoxInk),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your monsters can now grow to level $cap.',
                      style: FoE.label(size: 12).copyWith(color: kBoxInk),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
