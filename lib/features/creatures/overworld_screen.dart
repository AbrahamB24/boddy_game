import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/settlement_controller.dart';
import 'models/area.dart';
import 'models/combatant.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart' show kSpeciesDefs;
import 'battle_prep_screen.dart';
import 'battle_screen.dart';
import 'services/battle_rewards.dart';
import 'services/combat_engine.dart' show CombatOutcome;
import 'services/creatures_controller.dart';
import 'services/overworld_layout.dart';
import 'services/overworld_path.dart';
import 'services/region_dungeon.dart' show spawnPathBattle;

// ── The Overworld ───────────────────────────────────────────
// ONE straight line you climb (linear rebuild 2026-07-24). Numbered BATTLES run
// bottom → top, each a little stronger. Tapping the CURRENT battle fights it —
// winning it steps you up the line (grows the party, unlocks buildings), and an
// era boss unlocks the next region + its legendary.
//
// The map is ONLY the campaign now (2026-07-25): research nodes were removed
// with the tech system, and the resource spots + hunt moved to the Expeditions
// screen on the main nav, so this file has exactly one kind of node and one tap
// action. Geometry + state live in services/overworld_layout.dart.
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

  @override
  void initState() {
    super.initState();
    _settlement.addListener(_onChange);
    CreaturesController().load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
  }

  @override
  void dispose() {
    _settlement.removeListener(_onChange);
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
    return _nodesCache =
        buildLinearOverworld(battlesCleared: _settlement.battlesCleared);
  }

  Size get _canvas => overworldCanvasSize(_nodes);

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
  /// The scale at which the canvas covers the screen on both axes. The rule
  /// itself lives with the rest of the geometry, in overworld_layout.
  double _fillScale(Size screen) => overworldFillScale(screen, _canvas);

  /// Opens centred on the CURRENT battle — where the player is on the line — so
  /// the next fight is the first thing they see. Falls back to the foot.
  void _centerOnCurrent() {
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final canvas = _canvas;
    OverworldNode? current;
    for (final n in _nodes) {
      if (n.state == OverworldNodeState.current) current = n;
    }
    final focusY = current?.pos.dy ?? (canvas.height - _bottomFocus);
    final fill = _fillScale(size);
    // Screen y of a canvas point is `fill * y + ty`, so the clamp is against the
    // SCALED height — at 1.37× a 3 000-long trail is 4 100 tall, and clamping
    // against the unscaled figure would have parked the view in empty space
    // below the first battle.
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        0,
        (size.height / 2 - focusY * fill)
            .clamp(size.height - canvas.height * fill, 0.0),
        0,
        1,
      )
      ..scaleByDouble(fill, fill, 1, 1);
  }

  static const double _bottomFocus = 160;

  /// The fill the transform was last built for — see [build].
  double? _appliedFill;

  @override
  Widget build(BuildContext context) {
    final fill = _fillScale(MediaQuery.sizeOf(context));
    // The scale is FIXED, so nothing corrects it after a size change any more —
    // a rotation would leave yesterday's zoom and today's bars. Re-centring on
    // the next frame restores both the fill and the "you are here" framing.
    if (_appliedFill != null && (_appliedFill! - fill).abs() > 0.0001) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent());
    }
    _appliedFill = fill;
    return Scaffold(
      backgroundColor: FoE.mapBase,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
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
              // balken auch nicht sehen"). Every pixel of slack here is a pixel
              // of bare background you can drag into view — 200 of them at the
              // top and bottom is exactly what put the beige strips above the
              // boss and below the first battle.
              boundaryMargin: EdgeInsets.zero,
              constrained: false,
              child: SizedBox(
                width: _canvas.width,
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
                        ),
                      ),
                    ),
                    // Atmosphere: a soft dark vignette gives the map depth and
                    // keeps the top bar legible over bright grass.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                FoE.bg.withValues(alpha: 0.45),
                                FoE.bg.withValues(alpha: 0.0),
                                FoE.bg.withValues(alpha: 0.0),
                                FoE.bg.withValues(alpha: 0.35),
                              ],
                              stops: const [0.0, 0.18, 0.82, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _TrailPainter(_nodes)),
                      ),
                    ),
                    for (final node in _nodes) _nodeWidget(node),
                  ],
                ),
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _topBar()),
        ],
      ),
    );
  }

  /// THE bar (user 2026-07-31: "überall wo es einen header hat, soll dieser
  /// immer genau gleich aussehen"). This screen had its own: a flat box, its own
  /// padding, its own back button and its own title size — three values that had
  /// all drifted from the shared one.
  Widget _topBar() => const SafeArea(
    bottom: false,
    child: ParchmentHeader(title: 'Overworld'),
  );

  // ── Nodes ──────────────────────────────────────────────────
  Widget _nodeWidget(OverworldNode node) {
    // Bosses read as the landmark capping each region — a touch larger.
    final size = node.isBoss ? 68.0 : 58.0;
    return Positioned(
      left: node.pos.dx - size / 2,
      top: node.pos.dy - size / 2,
      child: _MapNode(
        node: node,
        size: size,
        pulse: _pulse,
        onTap: () => _launchBattle(node),
      ),
    );
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
    final enemies = spawnPathBattle(area, node.battleNumber);
    if (enemies == null) {
      context.snack('No monsters live here yet (Dev Mode → Species).');
      return;
    }
    if (CreaturesController().battleReadyCreatures.isEmpty) {
      context.snack('No battle-ready monster — heal up first!');
      return;
    }
    final title =
        node.isBoss ? '👑 ${area.name} — Boss' : 'Battle ${node.battleNumber}';
    // Only clearing the CURRENT node grants the map unlocks, so only preview
    // rewards there (a re-fight just gives XP).
    final isFrontier = node.state == OverworldNodeState.current;
    final rewards =
        isFrontier ? battleRewardsFor(node.battleNumber) : const <RewardLine>[];

    // PRE-BATTLE briefing: pick the team, see the foes + rewards (user
    // 2026-07-24). Cancelling (null) backs out without a fight.
    final team = await Navigator.push<List<CreatureInstance>>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePrepScreen(
          title: title,
          enemies: enemies,
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
          enemies: enemies,
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
    }
    if (mounted) setState(() {});
  }

  /// After a region boss falls the FIRST time: unlock the next region (rides on
  /// dungeonMaxStage, same as before) and award the region legendary. PUSHING
  /// ON — moving the settlement's own tier up to match — is still a manual,
  /// paid step at the Castle (unchanged).
  Future<void> _grantBossRewards(AreaDef area, int battleNumber) async {
    final era = eraForBattle(battleNumber); // == area.battleStage
    final firstClear = _settlement.dungeonMaxStage <= era;
    await _settlement.unlockDungeonStage(era);
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
    context.snack(caught != null
        ? '👑 ${caught.displayName} joins you! The next region is open — '
            'push on at the Castle.'
        : 'The next region is open — push on at the Castle.');
  }

}

// ── Node ────────────────────────────────────────────────────
class _MapNode extends StatelessWidget {
  final OverworldNode node;
  final double size;
  final VoidCallback onTap;

  /// Drives the current node's breathing glow.
  final Animation<double> pulse;

  const _MapNode({
    required this.node,
    required this.size,
    required this.onTap,
    required this.pulse,
  });

  // The boss is the landmark that caps a region; a regular fight is a threat.
  Color get _accent => node.isBoss ? FoE.gold : FoE.danger;

  @override
  Widget build(BuildContext context) {
    final done = node.state == OverworldNodeState.done;
    final locked = node.state == OverworldNodeState.locked;
    final current = node.state == OverworldNodeState.current;
    final accent = _accent;

    // The disc: a filled, softly shadowed token. Done nodes fill with their
    // accent; the rest read as carved stone (light → dark gradient).
    Widget disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: done
              ? [accent.withValues(alpha: 0.9), accent.withValues(alpha: 0.55)]
              : [FoE.panelLight, FoE.panelDark],
        ),
        border: Border.all(
          color: accent.withValues(alpha: locked ? 0.35 : 1),
          width: (current || node.isBoss) ? 3 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: FoE.bg.withValues(alpha: 0.55),
            offset: const Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: _discContent(done, locked),
    );

    // "You are here": the current node breathes a soft accent glow.
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
                  color: accent.withValues(alpha: 0.30 + 0.35 * t),
                  blurRadius: 0 + 14 * t,
                  spreadRadius: 1 + 3 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: disc,
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // ── Nur noch die Scheibe (user 2026-07-31) ──
      // "«battle n» und der Balken unten mit den Infos löschen"
      //
      // The disc already says which fight this is (its number, a crown for a
      // boss, a tick for a cleared one) and the prep screen says the rest the
      // moment you tap it. The caption repeated the number, and the badge
      // stacked level, foe count and party size under every single node — three
      // rows of chrome per stop, on a map whose whole subject is one line.
      child: SizedBox(
        width: size,
        child: disc,
      ),
    );
  }

  Widget _discContent(bool done, bool locked) {
    if (locked) return Icon(Icons.lock, size: size * 0.34, color: FoE.textDim);
    if (done) {
      return Icon(Icons.check_rounded, size: size * 0.52, color: Colors.white);
    }
    // Boss reads as a crown; a regular fight shows its number.
    if (node.isBoss) return Text('👑', style: TextStyle(fontSize: size * 0.44));
    return Text(
      '${node.battleNumber}',
      style: TextStyle(
        color: FoE.parchment,
        fontSize: 20,
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
  static const _roadFill = FoE.gold;

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
        ..color = FoE.goldBright.withValues(alpha: 0.7),
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
        a.dx + amp, a.dy + dy * 0.35,
        b.dx + amp, b.dy - dy * 0.35,
        b.dx, b.dy,
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
