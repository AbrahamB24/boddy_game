import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../settlement/settlement_controller.dart';
import 'models/area.dart';
import 'models/combatant.dart';
import 'models/creature_instance.dart';
import 'models/path_node.dart' show regionForBattle;
import 'models/species_def.dart' show kSpeciesDefs;
import 'widgets/creature_sprite.dart' show decodeWidthFor;
import 'widgets/overworld_card.dart';
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

// ── The Overworld ───────────────────────────────────────────
// ONE straight line you climb (linear rebuild 2026-07-24). Numbered BATTLES run
// bottom → top, each a little stronger. Tapping the CURRENT battle fights it —
// winning it steps you up the line (grows the party, unlocks buildings), and an
// a region boss unlocks the next region + its legendary.
//
// The map is ONLY the campaign now (2026-07-25): research nodes were removed
// with the tech system, and the resource spots + hunt moved to the Expeditions
// screen on the main nav, so this file has exactly one kind of node and one tap
// action. Geometry + state live in services/overworld_layout.dart.
//
// "Variante 4" (user 2026-09-20, Holz kit): the road on the left, and beside it
// a cream card for the battle you have picked — its ENEMIES and its REWARD, and
// nothing else — with the gold button that goes on to the preparation. Tapping a
// node PICKS it (the card follows); tapping the picked one again fights it.
class OverworldScreen extends StatefulWidget {
  const OverworldScreen({super.key});

  @override
  State<OverworldScreen> createState() => _OverworldScreenState();
}

class _OverworldScreenState extends State<OverworldScreen>
    with SingleTickerProviderStateMixin {
  final _settlement = SettlementController();
  final _transform = TransformationController();

  // A slow breathing pulse for the CURRENT node's glow — "you are here".
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  /// True for the whole tutorial visit to this screen — back is blocked the
  /// entire time, and the spotlight below lights up battle 1 as the one
  /// thing to press, from the very first frame rather than after a separate
  /// one-time popup (user 2026-09-03: "click on the first node soll
  /// gleichzeitig mit dem gehighlighteten Button 'tap the first battle to
  /// begin' kommen" — the explanation and the highlight are now the SAME
  /// moment, not two in sequence; the old dismissible full-screen intro this
  /// replaced said the same thing a second time anyway).
  bool get _tutorialLocksThisScreen =>
      _settlement.introStep == IntroStep.firstNode;

  /// The battle number the player has picked on the map; null = the current one.
  int? _selected;

  /// The foes of each battle, worked out once for the card. (They are seeded by
  /// area + battle number, or authored on the node — the same list every time —
  /// but a Combatant is mutable, so a FIGHT always builds its own fresh ones;
  /// these are for looking at.) The tutorial's scripted first fight is never
  /// cached: it depends on the starter, which may not be loaded yet.
  final Map<int, List<Combatant>> _foesSeen = {};

  /// The size of the map's own viewport (the screen less the card).
  Size? _viewSize;

  @override
  void initState() {
    super.initState();
    _settlement.addListener(_onChange);
    // The scripted first fight's enemy depends on the starter, which loads a
    // moment after this screen opens.
    CreaturesController().addListener(_onChange);
    CreaturesController().load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
  }

  @override
  void dispose() {
    _settlement.removeListener(_onChange);
    CreaturesController().removeListener(_onChange);
    _pulse.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  // Cached, not a getter: buildLinearOverworld allocates and interleaves, and
  // the settlement's 5s ticker keeps rebuilding this screen while it's pushed.
  List<OverworldNode>? _nodesCache;
  String? _nodesKey;

  List<OverworldNode> get _nodes {
    final key = '${_settlement.battlesCleared}|${kAreaDefs.length}';
    if (_nodesKey == key && _nodesCache != null) return _nodesCache!;
    _nodesKey = key;
    return _nodesCache = buildLinearOverworld(
      battlesCleared: _settlement.battlesCleared,
    );
  }

  Size get _canvas => overworldCanvasSize(_nodes);

  /// The node the card is about: the picked one, else the current battle, else
  /// (a fully cleared line) the last.
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
    return nodes.reduce((a, b) => a.pathIndex >= b.pathIndex ? a : b);
  }

  // ── Keine Balken links und rechts (user 2026-07-31) ─────────
  // "balken links und rechts dürfen nicht sichtbar sein, daher den zoom
  //  anpassen."
  //
  // The trail's canvas is a FIXED 300 wide (one lane — see overworld_layout), so
  // on any wider phone it was drawn at 1:1 and centred, and the two strips of
  // bare background beside it read as the app not filling the screen.
  //
  // The fix is the zoom, not the canvas: the map opens at exactly the scale that
  // makes those 300 cover the width, and cannot go below it. Widening the canvas
  // instead would have moved every node's x and left the lane off-centre.
  /// The scale at which the canvas covers the map viewport on both axes. The
  /// rule itself lives with the rest of the geometry, in overworld_layout.
  double _fillScale(Size view) => overworldFillScale(view, _canvas);

  /// LANDSCAPE (2026-09-18): the lane is a fixed 300 wide, so filling a 900px
  /// long axis with it would zoom 3x and turn every node into a 170px disc on
  /// a 430px-tall phone. The zoom is capped instead, and the canvas is WIDENED
  /// to whatever the screen then needs, with the lane centred in it and the
  /// grass running edge to edge - the side bars stay hidden without the giant
  /// nodes.
  ///
  /// 1.15 (user 2026-09-20: "zoome etwas heraus, damit ich mehr vom Weg sehe"),
  /// down from 1.5 — about a third more of the road on screen at once.
  static const double _kMaxScale = 1.15;

  /// Never below what keeps the scaled canvas as tall as the view: a short
  /// trail (few battles) would otherwise show bare ground under it now that the
  /// cap is lower.
  double _scaleFor(Size view) {
    final coverHeight = _canvas.height > 0 ? view.height / _canvas.height : 0.0;
    return math.max(math.min(_fillScale(view), _kMaxScale), coverHeight);
  }

  /// The canvas's own width once widened to [view] at [_scaleFor]'s zoom.
  double _canvasWidthFor(Size view) =>
      math.max(_canvas.width, view.width / _scaleFor(view));

  /// Opens centred on the CURRENT battle — where the player is on the line — so
  /// the next fight is the first thing they see. Falls back to the foot.
  void _centerOnCurrent() {
    if (!mounted) return;
    final size = _viewSize ?? MediaQuery.of(context).size;
    final canvas = _canvas;
    OverworldNode? current;
    for (final n in _nodes) {
      if (n.state == OverworldNodeState.current) current = n;
    }
    final focusY = current?.pos.dy ?? (canvas.height - _bottomFocus);
    final fill = _scaleFor(size);
    // Screen y of a canvas point is `fill * y + ty`, so the clamp is against the
    // SCALED height — at 1.37× a 3 000-long trail is 4 100 tall, and clamping
    // against the unscaled figure would have parked the view in empty space
    // below the first battle.
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        0,
        (size.height / 2 - focusY * fill).clamp(
          size.height - canvas.height * fill,
          0.0,
        ),
        0,
        1,
      )
      ..scaleByDouble(fill, fill, 1, 1);
  }

  static const double _bottomFocus = 160;

  /// The fill the transform was last built for — see [_map].
  double? _appliedFill;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    // The same deck width the battle screen uses, so the two pages match.
    final cardW = (screenW * 0.34).clamp(270.0, 340.0);
    // Back is blocked for the whole tutorial visit (user 2026-09-02: "zurück
    // sollte nicht anwählbar sein") — both the system gesture/hardware
    // button (PopScope) and the header's own arrow, which _topBar hides
    // under the same condition.
    return PopScope(
      canPop: !_tutorialLocksThisScreen,
      child: Scaffold(
        backgroundColor: CreamPalette.groundBottom,
        body: Stack(
          children: [
            SafeArea(
              // The fight card runs the full height of the screen (user
              // 2026-09-22: "Next fight Kachel geht bis zum oberen Rand"), so the
              // wood band with Survival and the way out sits over the road only.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _topBar(),
                        Expanded(
                          child: ClipRect(
                            child: LayoutBuilder(
                              builder: (context, box) => _map(box.biggest),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _card(cardW),
                ],
              ),
            ),
            // Up from the very first frame of the tutorial visit, not after a
            // separate dismissible popup — lights up battle 1 alone and
            // dead-zones everything else (the header's back arrow included),
            // the same "exactly one lit control" grammar the settlement
            // screen's own tutorial overlay uses. Circular (user 2026-09-03:
            // "der Button ist nicht richtig markiert") to match the node's
            // own round disc rather than a mismatched rectangular glow.
            if (_tutorialLocksThisScreen)
              const IntroSpotlightOverlay(
                anchorName: 'overworld-node-1',
                hint: 'Click on the first battle to unlock the next one.',
                circular: true,
              ),
          ],
        ),
      ),
    );
  }

  /// The road: a scroll of grass with the trail and its nodes, sized to [view].
  Widget _map(Size view) {
    _viewSize = view;
    final fill = _scaleFor(view);
    final canvasW = _canvasWidthFor(view);
    final laneDx = (canvasW - _canvas.width) / 2;
    // The scale is FIXED, so nothing corrects it after a size change any more —
    // a rotation would leave yesterday's zoom and today's bars. Re-centring on
    // the next frame restores both the fill and the "you are here" framing.
    if (_appliedFill != null && (_appliedFill! - fill).abs() > 0.0001) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
    }
    _appliedFill = fill;
    final picked = _selectedNode?.battleNumber;
    return InteractiveViewer(
      transformationController: _transform,
      // ── NO ZOOM AT ALL (user 2026-07-31: "zoom bei der map
      // rausnehmen") ──
      //
      // The map is a single lane you walk up: there is nothing to see
      // wider and nothing to read closer, so a pinch could only ever put
      // it in a state you then had to undo — and every such state is one
      // where the bare background shows. What is left is a scroll.
      //
      // The bounds are pinned to the fill anyway, so even a programmatic
      // scale (or a future gesture) cannot go anywhere else.
      scaleEnabled: false,
      minScale: fill,
      maxScale: fill,
      // NO MARGIN AT ALL (user 2026-07-31: "oben und unten will ich die
      // Balken auch nicht sehen"). Every pixel of slack here is a pixel
      // of bare background you can drag into view — 200 of them at the
      // top and bottom is exactly what put the beige strips above the
      // boss and below the first battle.
      boundaryMargin: EdgeInsets.zero,
      constrained: false,
      child: SizedBox(
        width: canvasW,
        height: _canvas.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: Image.asset(
                  'assets/images/overworld_grass.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  // Capped, not native 1080x1080 (user 2026-09-06:
                  // "performance deutlich verbessern") — a 4.4 MB
                  // RGBA decode for a texture that only ever tiles
                  // BoxFit.cover across the canvas's own width.
                  cacheWidth: decodeWidthFor(context, canvasW),
                ),
              ),
            ),
            // Atmosphere: a soft dark vignette gives the map depth.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        FoE.bg.withValues(alpha: 0.25),
                        FoE.bg.withValues(alpha: 0.0),
                        FoE.bg.withValues(alpha: 0.0),
                        FoE.bg.withValues(alpha: 0.35),
                      ],
                      stops: const [0.0, 0.12, 0.82, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // The lane itself, centred in the widened canvas.
            Positioned(
              left: laneDx,
              top: 0,
              width: _canvas.width,
              height: _canvas.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _TrailPainter(_nodes)),
                    ),
                  ),
                  for (final node in _nodes)
                    _nodeWidget(node, picked: node.battleNumber == picked),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
              fontWeight: FontWeight.w800,
              color: CreamPalette.paperTop,
            ),
          ),
          const Spacer(),
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
                    Icon(
                      Icons.whatshot_rounded,
                      size: 16,
                      color: CreamPalette.warn,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Survival',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
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

  /// The card beside the road, on the same wood ground the battle's deck stands
  /// on.
  Widget _card(double width) {
    final node = _selectedNode;
    return Container(
      width: width,
      decoration: const BoxDecoration(gradient: kMenuGround),
      // The same 10 px above as below and beside it.
      padding: const EdgeInsets.fromLTRB(8, 10, 10, 10),
      child: node == null
          ? const SizedBox.shrink()
          : OverworldFightCard(
              battleNumber: node.battleNumber,
              isBoss: node.isBoss,
              state: node.state,
              enemies: _foesFor(node),
              // Only the current battle grants its unlocks (a re-fight is XP
              // only, see [_launchBattle]); the ones still ahead show what they
              // will grant once they are the current one.
              rewards: node.state == OverworldNodeState.done
                  ? const []
                  : battleRewardsFor(node.battleNumber),
              onFight: () => _launchBattle(node),
            ),
    );
  }

  // ── Nodes ──────────────────────────────────────────────────
  Widget _nodeWidget(OverworldNode node, {required bool picked}) {
    // Bosses read as the landmark capping each region — a touch larger.
    final size = node.isBoss ? 56.0 : 46.0;
    // The tutorial's ONE lit target while it's locking this screen (user
    // 2026-09-02: "highlighte den 1. Node") — see the IntroSpotlightOverlay
    // in [build].
    final anchorKey = node.battleNumber == 1
        ? IntroSpotlightAnchors.of('overworld-node-1')
        : null;
    final map = _MapNode(
      node: node,
      size: size,
      pulse: _pulse,
      picked: picked,
      onTap: () => _onNodeTap(node),
    );
    return Positioned(
      left: node.pos.dx - size / 2,
      top: node.pos.dy - size / 2,
      child: anchorKey == null ? map : KeyedSubtree(key: anchorKey, child: map),
    );
  }

  /// A tap PICKS a node (the card follows); a tap on the node already picked
  /// fights it — so the tutorial's "tap the first battle" still goes straight in,
  /// the current battle being picked from the start.
  void _onNodeTap(OverworldNode node) {
    if (node.battleNumber == _selectedNode?.battleNumber) {
      _launchBattle(node);
    } else {
      setState(() => _selected = node.battleNumber);
    }
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
          victoryRewards: rewards,
          // WHERE the fight happens — the battlefield's art comes from here
          // (user 2026-07-31).
          area: area,
        ),
      ),
    );
    if (!mounted) return;
    // Only clearing the CURRENT node moves the line forward.
    if (outcome == CombatOutcome.victory && isFrontier) {
      await _settlement.advanceBattlesCleared(toBattle: node.battleNumber);
      if (node.isBoss) await _grantBossRewards(area, node.battleNumber);
      if (introNodeStep != null) await _settlement.advanceIntro(introNodeStep);
      // The card moves on to the next battle.
      _selected = null;
    }
    if (!mounted) return;
    // Straight back to the settlement after the tutorial's FIRST fight (user
    // 2026-09-06) rather than staying on this map — node 2 would otherwise
    // sit right there, tappable before the buildHealingHut → buildRoad →
    // assignHealer → healStarter → firstCapture steps in between have run.
    if (introNodeStep == IntroStep.firstNode) {
      Navigator.pop(context);
      return;
    }
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
    context.snack(
      caught != null
          ? '👑 ${caught.displayName} joins you! The next region is open.'
          : 'The next region is open!',
    );
  }
}

// ── Node ────────────────────────────────────────────────────
/// A Holz medallion (user 2026-09-20): gold with a check once cleared, cream with
/// a glowing gold rim and its number when it is the one you are on, grey with a
/// lock while it is out of reach; a boss wears a crown and a dark-wood ring. The
/// one PICKED (whose card is showing) gets a white ring.
class _MapNode extends StatelessWidget {
  final OverworldNode node;
  final double size;
  final VoidCallback onTap;
  final bool picked;

  /// Drives the current node's breathing glow.
  final Animation<double> pulse;

  const _MapNode({
    required this.node,
    required this.size,
    required this.onTap,
    required this.pulse,
    required this.picked,
  });

  static const Color _wood = Color(0xFF5C3B22);

  @override
  Widget build(BuildContext context) {
    final done = node.state == OverworldNodeState.done;
    final locked = node.state == OverworldNodeState.locked;
    final current = node.state == OverworldNodeState.current;
    final boss = node.isBoss;

    final Gradient face = done
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFD97A), CreamPalette.gold],
          )
        : locked
        ? const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [CreamPalette.lockedTop, CreamPalette.lockedBottom],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
          );
    final rim = current
        ? CreamPalette.gold
        : locked
        ? CreamPalette.lockedShadow
        : CreamPalette.goldDeep;
    final drop = locked ? CreamPalette.lockedShadow : CreamPalette.goldDeep;

    Widget disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: face,
        boxShadow: [
          BoxShadow(color: rim, spreadRadius: current ? 3 : 2),
          if (boss && !current) const BoxShadow(color: _wood, spreadRadius: 6),
          BoxShadow(color: drop, offset: const Offset(0, 3)),
        ],
      ),
      child: _content(done, locked),
    );

    // "You are here": the current node breathes a soft gold glow.
    if (current) {
      disc = AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final t = pulse.value;
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: CreamPalette.gold.withValues(alpha: 0.30 + 0.35 * t),
                  blurRadius: 0 + 14 * t,
                  spreadRadius: 4 + 3 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: disc,
      );
    }

    return Pressable(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // ── Nur noch die Scheibe (user 2026-07-31) ──
      // "«battle n» und der Balken unten mit den Infos löschen"
      //
      // The disc already says which fight this is (its number, a crown for a
      // boss, a tick for a cleared one) and the card beside the map says the
      // rest the moment you pick it.
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // The picked one wears a white ring, clear of the boss's wood one.
            if (picked)
              Positioned(
                left: boss ? -11 : -8,
                right: boss ? -11 : -8,
                top: boss ? -11 : -8,
                bottom: boss ? -11 : -8,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ),
            disc,
          ],
        ),
      ),
    );
  }

  Widget _content(bool done, bool locked) {
    // A boss reads as a crown whatever its state; a regular fight is a tick, its
    // number, or a lock.
    if (node.isBoss) {
      return Opacity(
        opacity: locked ? 0.5 : 1,
        child: Text('👑', style: TextStyle(fontSize: size * 0.46)),
      );
    }
    if (locked) {
      return Icon(Icons.lock, size: size * 0.4, color: kBoxInkFaint);
    }
    if (done) {
      return Icon(Icons.check_rounded, size: size * 0.52, color: kBoxInk);
    }
    return Text(
      '${node.battleNumber}',
      style: TextStyle(
        color: kBoxInk,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

// ── Trail ───────────────────────────────────────────────────
/// Draws the single road threading every node in path order — a straight climb,
/// solid up to the reached (done/current) nodes and dashed into the fog beyond.
class _TrailPainter extends CustomPainter {
  final List<OverworldNode> nodes;
  const _TrailPainter(this.nodes);

  static const _roadShadow = Color(0x55000000);
  static const _roadEdge = Color(0xCC1B2329);
  static const _roadFill = CreamPalette.gold;

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = nodes.toList()
      ..sort((a, b) => a.pathIndex.compareTo(b.pathIndex));
    if (ordered.length < 2) return;

    // Split at the frontier: the walked road is solid, the road ahead is dashed
    // (into the unknown). The frontier is the current battle, or the last done
    // node if the line is fully cleared in view.
    var frontier = 0;
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i].state;
      if (s == OverworldNodeState.done || s == OverworldNodeState.current) {
        frontier = i;
      }
    }

    // A WINDING road: the nodes stay on the centre lane, but the road curves
    // gently side to side between them so the climb reads as a real trail, not
    // a ruler line.
    final walked = _winding(ordered, 0, frontier);
    final fog = _winding(ordered, frontier, ordered.length - 1);

    // Soft drop shadow beneath the walked road for depth.
    canvas.drawPath(
      walked,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _roadShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    // Dark casing.
    canvas.drawPath(
      walked,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _roadEdge,
    );
    // Gold fill.
    canvas.drawPath(
      walked,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = _roadFill,
    );
    // A dashed centre line, like cobbles marking the trodden way.
    _dashedAlong(
      canvas,
      walked,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFD97A).withValues(alpha: 0.8),
      dash: 9,
      gap: 9,
    );

    // The road ahead: dashed gold following the same curve into the fog.
    _dashedAlong(
      canvas,
      fog,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = _roadFill.withValues(alpha: 0.5),
    );
  }

  /// A smooth cubic curve through the lane points [from]..[to], bulging left/
  /// right on alternate segments so the trail meanders.
  Path _winding(List<OverworldNode> pts, int from, int to) {
    final path = Path();
    if (to <= from) return path;
    path.moveTo(pts[from].pos.dx, pts[from].pos.dy);
    for (var i = from; i < to; i++) {
      final a = pts[i].pos;
      final b = pts[i + 1].pos;
      final amp = (i.isEven ? 1 : -1) * 22.0;
      final dy = b.dy - a.dy;
      path.cubicTo(
        a.dx + amp,
        a.dy + dy * 0.35,
        b.dx + amp,
        b.dy - dy * 0.35,
        b.dx,
        b.dy,
      );
    }
    return path;
  }

  void _dashedAlong(
    Canvas canvas,
    Path path,
    Paint paint, {
    double dash = 11,
    double gap = 8,
  }) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => !identical(old.nodes, nodes);
}
