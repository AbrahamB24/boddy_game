import '../../core/ui/feel.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../core/theme/foe_theme.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/services/crafting.dart';
import '../settlement/services/daily_tasks.dart' show DailyTaskKind;
import '../settlement/settlement_controller.dart';
import 'models/ability_def.dart';
import 'models/area.dart' show AreaDef;
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'models/status_effects.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/battle_rewards.dart';
import 'services/capture_math.dart';
import 'services/combat_engine.dart';
import 'services/creatures_controller.dart';
import 'widgets/battle_scene.dart';
import 'widgets/creature_backdrop.dart';
import '../common/widgets/recess_bar.dart';
import '../common/widgets/parchment_page.dart';

/// Result popped when the player WINS the inline catch mini-game (user
/// 2026-07-18): the ring QTE now plays inside the battle itself, so a success
/// pops the caught wild for the caller to record. A failed attempt does NOT pop
/// — it just burns the turn and the fight goes on.
class CatchSuccess {
  final Combatant wild;
  const CatchSuccess(this.wild);
}

// The JRPG battle screen: enemies on top, the player's team below, the CTB
// initiative bar across the top and an action panel when it's a player
// creature's turn. Enemy turns (and player turns with auto-battle on) run on
// a short delay so the flow is readable. On finish the outcome is written
// back to the collection (pools always, XP on victory) and the screen pops
// with the CombatOutcome as its result.
class BattleScreen extends StatefulWidget {
  /// Presentation toggle (user 2026-07-20): `true` = the polished "mobile game"
  /// look (scene backdrop, glossy panels, chunkier buttons); `false` = the
  /// original flat layout. Static so the choice sticks across battles for the
  /// session; flipped live by the palette button in the top bar. Same battle
  /// LOGIC either way — only the styling differs.
  static bool polished = true;

  final List<CreatureInstance> team;
  final List<Combatant> enemies;
  final String title;

  /// WHERE this fight happens (user 2026-07-31). Decides the battlefield's art:
  /// the region's own scene when it has one, else its era's gradient. Null (a
  /// re-fight, a test) simply lands on era I's palette.
  final AreaDef? area;

  /// Unlocks to celebrate in the victory overlay (new party size, buildings,
  /// features, boss spoils). Empty for a re-fight. See battle_rewards.dart.
  final List<RewardLine> victoryRewards;

  /// Capture-encounter mode: fight the (single) wild DOWN to this HP fraction
  /// to enable the inline Catch button. Overkill closes it for good (a dead
  /// wild is nothing to catch).
  final double? catchThresholdFraction;

  /// Tutorial catch: the ring QTE cannot be failed out of — a miss just restarts
  /// the ring (matches the guided intro's "the catch cannot be lost" promise).
  final bool guaranteedCatch;

  const BattleScreen({
    super.key,
    required this.team,
    required this.enemies,
    this.title = 'Battle',
    this.area,
    this.catchThresholdFraction,
    this.guaranteedCatch = false,
    this.victoryRewards = const [],
  });

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  late final CombatEngine _engine;
  Timer? _autoTimer;
  bool _autoBattle = false;
  bool _outcomeApplied = false;
  // The static type-matchup chart starts COLLAPSED (user request 2026-07-20):
  // the ability tiles now show effectiveness inline, so the chart is an
  // on-demand reference rather than permanent furniture that eats the field.
  bool _typeChartOpen = false;

  // Set while popping the caught wild, so PopScope lets the pop through.
  bool _exitingToCatch = false;

  // A brief inline message (rejected action etc.) shown IN the battle log line
  // instead of a bottom SnackBar — a SnackBar floats over the action menu and
  // covers it (user 2026-07-18).
  String? _flash;
  Timer? _flashTimer;

  // ── Hit animation (user 2026-07-18) ───────────────────────
  // A short shake+flash pulse played whenever an action lands.
  //
  // Per COMBATANT since 2026-07-27, not per side: with three monsters standing
  // on each half, "the enemy side reacts" would shake all three of them for a
  // hit that landed on one. [_fxTarget] is the one that flinches, [_fxActor]
  // the one that lunges.
  late final AnimationController _fx;
  Combatant? _fxTarget;
  Combatant? _fxActor;

  // ── Target selection (user 2026-07-27) ────────────────────
  // With up to three opponents on the field, WHICH one to hit is a decision the
  // 1v1 model never had to offer. Held by id rather than by reference so a
  // target that falls (or is replaced by a reserve stepping into its slot)
  // resolves to null on the next read instead of pointing at a corpse.
  String? _targetId;

  /// The enemy the next action is aimed at: the one you tapped while it still
  /// stands, else the first of the pack. Never null while an enemy is up.
  Combatant? get _target {
    final field = _engine.fieldEnemies;
    if (field.isEmpty) return null;
    for (final c in field) {
      if (c.id == _targetId) return c;
    }
    return field.first;
  }

  // ── Entry animation (user 2026-07-24) ─────────────────────
  // Plays once when the screen opens: the fighters slide onto the field, and
  // the action loop is held (`_entering`) until they've arrived.
  late final AnimationController _entry;
  bool _entering = true;

  // Level-ups captured when the fight resolves, shown in the end overlay with
  // their stat gains (user 2026-07-24).
  List<LevelUpResult> _levelUps = const [];
  // Tint of the current hit's flash on the reacting sprite — the striking
  // move's element colour, so a super-effective fire hit flashes orange, a
  // basic attack white (user request 2026-07-20).
  Color _fxImpact = Colors.white;
  String _lastActionSeen = '';
  // The last two combat-log lines shown in the middle bar (user 2026-07-18).
  final List<String> _log = [];

  // ── Floating combat text (user 2026-07-20) ────────────────
  // Damage/heal numbers that pop over the struck monster and drift up. Fed by
  // the engine's per-action CombatEvents; each entry self-animates and removes
  // itself by id when done.
  final List<_FloatText> _floats = [];
  int _floatSeq = 0;

  // ── Inline catch mini-game (user 2026-07-18) ──────────────
  late final AnimationController _ring; // shrinking-ring timer
  final _rng = math.Random();
  bool _catchOpen = false; // the QTE overlay is up
  bool _catchResolving = false; // guards double-resolve
  int _catchHits = 0;
  int _catchHitsNeeded = 1;
  bool _catchBetween = false; // brief beat between rounds (ring hidden)
  bool _catchMissed = false; // tutorial: last tap missed, retrying
  ({double lo, double hi}) _catchWindow = (lo: 0.3, hi: 0.4);
  SpeciesDef? _catchSpecies;

  @override
  void initState() {
    super.initState();
    _engine = CombatEngine(
      players: widget.team.map(Combatant.fromInstance).toList(),
      enemies: widget.enemies,
    );
    _engine.addListener(_onEngineChanged);
    _fx = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _ring = AnimationController(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((s) {
        // Ring fully shrank with no tap → a miss.
        if (s == AnimationStatus.completed && _catchOpen && !_catchBetween) {
          _catchMiss();
        }
      });
    // Entry animation (user 2026-07-24): the fighters slide onto the field
    // before the fight begins, so the combat has a proper "Auftritt". The
    // action loop is held until they've arrived.
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _entering = false);
          // Kick the loop now (an enemy may be fastest and act first).
          _onEngineChanged();
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _entry.forward());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _flashTimer?.cancel();
    _fx.dispose();
    _ring.dispose();
    _entry.dispose();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    super.dispose();
  }

  void _onEngineChanged() {
    if (!mounted) return;
    // A new log line means an action just landed — spawn its floating numbers
    // and play the hit pulse on the struck side (derived from the events, not
    // the actor, so it's right even after the turn advances).
    if (_engine.lastAction != _lastActionSeen) {
      _lastActionSeen = _engine.lastAction;
      if (_engine.lastAction.isNotEmpty) {
        _log.add(_engine.lastAction);
        if (_log.length > 2) _log.removeRange(0, _log.length - 2);
      }
      _consumeCombatEvents();
    }
    setState(() {});
    _scheduleAutoIfNeeded();
  }

  /// Reads the engine's per-action events: pops a floating number for each and
  /// drives the impact pulse + haptic off the struck target.
  void _consumeCombatEvents() {
    final events = _engine.lastEvents;
    if (events.isEmpty) return;
    CombatEvent? struck; // first damage/miss on a target = who reacts
    for (final e in events) {
      _spawnFloat(e);
      if (!e.heal && (e.miss || e.amount > 0)) struck ??= e;
    }
    final s = struck;
    if (s != null && _engine.outcome == null) {
      _fxImpact = (s.miss || s.element == CreatureElement.neutral)
          ? Colors.white
          : s.element.color;
      _playHit(target: s.target);
      if (!s.miss) {
        s.crit ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
      }
    }
  }

  /// Which slot a combatant stands in, as a −1..1 alignment across its half —
  /// what the floating numbers and the reserve strip line themselves up with.
  /// Centre for anyone not on the field (a heal on a monster that just left).
  double _slotAlignX(Combatant c) {
    final field = c.isPlayerSide ? _engine.playerField : _engine.enemyField;
    final slot = field.indexWhere((f) => identical(f, c));
    if (slot < 0) return 0;
    // Three slots → −0.62, 0, 0.62; matches the thirds the sprites sit in.
    return (slot - (CombatEngine.kFieldSlots - 1) / 2) * 0.62;
  }

  /// Adds a floating combat number for one event, over the struck monster.
  void _spawnFloat(CombatEvent e) {
    if (!e.miss && !e.heal && e.amount <= 0) return;
    final id = _floatSeq++;
    final String text;
    final Color color;
    var scale = 1.0;
    if (e.miss) {
      text = 'Miss';
      color = FoE.textDim;
    } else if (e.heal) {
      text = '+${e.amount}';
      color = FoE.positive;
    } else {
      text = '-${e.amount}';
      color = e.crit ? FoE.goldBright : FoE.danger;
      if (e.crit) scale = 1.45;
    }
    final tag = (e.heal || e.miss)
        ? null
        : e.typeMult > 1.0
            ? 'Super effective!'
            : e.typeMult < 1.0
                ? 'Resisted'
                : null;
    _floats.add(_FloatText(
      id: id,
      text: text,
      color: color,
      scale: scale,
      onEnemy: !e.target.isPlayerSide,
      alignX: _slotAlignX(e.target),
      tag: tag,
    ));
  }

  void _removeFloat(int id) {
    if (!mounted) return;
    setState(() => _floats.removeWhere((f) => f.id == id));
  }

  /// A short shake+flash on the struck monster, and a lunge on whoever struck
  /// it — both by identity, so the two neighbours standing beside them hold
  /// still.
  void _playHit({required Combatant target}) {
    _fxTarget = target;
    _fxActor = _engine.currentActor;
    _fx.forward(from: 0).whenComplete(() {
      if (mounted) {
        setState(() {
          _fxTarget = null;
          _fxActor = null;
        });
      }
    });
  }

  // Enemy turns always run automatically; player turns only with the auto
  // toggle. One timer at a time — every engine change reschedules.
  void _scheduleAutoIfNeeded() {
    _autoTimer?.cancel();
    if (_engine.outcome != null) {
      _applyOutcome();
      return;
    }
    // An empty player slot pauses everything — the deck shows "Send in a
    // reserve" and nobody acts until one is. With AUTO on, that pick is one the
    // player already handed over, so it fills itself.
    if (_engine.needsPlayerSwitch) {
      if (_autoBattle) {
        _autoTimer = Timer(const Duration(milliseconds: 700), () {
          if (mounted && _engine.needsPlayerSwitch) _engine.autoSwitchIn();
        });
      }
      return;
    }
    final actorIsPlayer = _engine.isPlayerTurn;
    if (!actorIsPlayer || _autoBattle) {
      _autoTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted &&
            _engine.outcome == null &&
            !_engine.needsPlayerSwitch) {
          _engine.performAutoAction();
        }
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
    // Daily-task hook: a won battle counts, however it was fought.
    if (_engine.outcome == CombatOutcome.victory) {
      SettlementController().reportDailyProgress(DailyTaskKind.winBattles);
    }
    // NOTE: linear-path progress (advanceBattlesCleared) is NOT advanced here —
    // only clearing the CURRENT node on the overworld counts, so the overworld
    // screen advances it explicitly. That keeps re-fights and capture/other
    // battles from over-counting (user 2026-07-24).
    final ups = await CreaturesController().applyBattleOutcome(
      _engine.players,
      xpEach: _xpEach,
    );
    if (mounted) setState(() => _levelUps = ups);
  }

  // Offensive actions go to the SELECTED enemy (user 2026-07-27) — [_target],
  // which the player sets by tapping a monster on the enemy half and which
  // falls back to the first of the pack. Ally/self abilities still resolve to
  // the caster: choosing an ally to heal would want its own tap mode, and every
  // heal in the game is a self-heal today.
  void _attack() {
    final target = _target;
    if (target == null) return;
    _engine.basicAttack(_engine.currentActor, target);
  }

  void _useAbility(AbilityDef ability) {
    final actor = _engine.currentActor;
    final target = switch (ability.target) {
      AbilityTarget.enemy || AbilityTarget.allEnemies => _target,
      _ => actor,
    };
    final error = _engine.useAbility(actor, ability, target);
    if (error != null) _showError(error);
  }

  /// Opens the bench picker to switch monsters. [forced] = the active fainted
  /// and a reserve MUST come in (can't be dismissed).
  Future<void> _openSwitchPicker({required bool forced}) async {
    final bench = _engine.benchedPlayers;
    if (bench.isEmpty) return;
    final chosen = await showModalBottomSheet<Combatant>(
      context: context,
      backgroundColor: FoE.panelDark,
      isDismissible: !forced,
      enableDrag: !forced,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      builder: (_) => PopScope(
        canPop: !forced,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                forced ? 'Your monster fainted — send in a reserve'
                    : 'Switch monster (free — costs no turn)',
                style: FoE.title(size: 14),
              ),
              const SizedBox(height: 12),
              for (final c in bench)
                GestureDetector(
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: FoE.panel(radius: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: _portrait(c, size: 28)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c.element.emoji} ${c.name} · Lv ${c.level}',
                                  style: FoE.label(size: 13)),
                              const SizedBox(height: 4),
                              _bar(c.hp / c.maxHp, FoE.positive,
                                  '${c.hp}/${c.maxHp}'),
                            ],
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
    );
    if (chosen == null) return;
    final idx = _engine.players.indexOf(chosen);
    final err = _engine.switchActivePlayer(idx);
    if (err != null && mounted) _showError(err);
  }

  // Shows [message] inline in the battle log line for a moment — NOT a bottom
  // SnackBar, which would cover the action menu (user 2026-07-18).
  void _showError(String message) {
    setState(() => _flash = message);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  // ── Polished "mobile game" styling (user 2026-07-20) ──────
  // A single flag flips the whole screen between the flat original and a
  // glossy, chunkier mobile-game look. Every _fancy branch below leaves the
  // classic path untouched so switching back is exact.
  bool get _fancy => BattleScreen.polished;

  // ── Flat modern palette (user 2026-07-20) ─────────────────
  // The monsters are FLAT-coloured art, so the polished chrome is flat too: no
  // gloss/gradients/3D bevels — matte cool-graphite surfaces, thin cool
  // hairlines, gold kept as the one accent so the vivid element colours pop.
  static const Color _sceneTop = Color(0xFF2E3A43); // Steel Blue, lifted
  static const Color _sceneBottom = FoE.bg;
  static const Color _flatSurface = FoE.panelDark; // trays, cards, log
  static const Color _flatSurfaceHi = FoE.panelMid; // raised surface
  static const Color _flatHairline = FoE.border; // cool border

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _topBar(),
                  // Type-matchup key between the turn order and the arena (user
                  // request): the fire/water/plant RPS ring + light↔shadow.
                  _typeChart(),
                  // Split battlefield (user 2026-07-18): the enemy up top on
                  // ITS type backdrop, my monster below on MINE. The two type
                  // tiles now run all the way to the middle and MEET there; the
                  // battle log is overlaid on that seam rather than sitting in a
                  // gap between them (user request). My monster faces away (back
                  // art). It keeps its FULL size but is nudged DOWN toward the
                  // buttons (user request); the small bottom overshoot tucks
                  // behind the (opaque) command deck.
                  Expanded(
                    child: Stack(
                      children: [
                        // ONE battlefield behind BOTH ranks (user 2026-07-31).
                        // The two element tiles that used to meet at a seam are
                        // gone: a rank of three can hold three types, so the
                        // ground says WHERE you are and each monster's own plate
                        // says WHAT it is. See widgets/battle_scene.dart.
                        Positioned.fill(
                          child: BattleScene(
                            imageUrl: widget.area?.imageUrl,
                            era: widget.area?.battleStage ?? 1,
                          ),
                        ),
                        // The sprites (and only the sprites) sit slightly low in
                        // the arena, tucking the player's rank toward the deck.
                        LayoutBuilder(
                          builder: (context, box) => Transform.translate(
                            offset: Offset(0, box.maxHeight * _kArenaDrop),
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    Expanded(child: _rank(isEnemy: true)),
                                    const Expanded(child: SizedBox()),
                                  ],
                                ),
                                // On the seam where the two ranks face off.
                                Align(
                                  alignment: Alignment.center,
                                  child: _logLine(),
                                ),
                                // MY rank last, so it stands in FRONT of the
                                // battle log (user request, kept).
                                Column(
                                  children: [
                                    const Expanded(child: SizedBox()),
                                    Expanded(child: _rank(isEnemy: false)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _actionPanel(),
                ],
              ),
              if (_floats.isNotEmpty) _floatsLayer(),
              if (_catchOpen) _catchOverlay(),
              if (_engine.outcome != null) _endOverlay(),
            ],
          ),
        );
    return PopScope(
      canPop: _engine.outcome != null || _exitingToCatch,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmFlee();
      },
      child: Scaffold(
        // In fancy mode a deep scene gradient replaces the flat black, so the
        // rounded panels read as floating over a battlefield (user 2026-07-20).
        backgroundColor: _fancy ? _sceneBottom : FoE.bg,
        body: _fancy
            ? DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_sceneTop, _sceneBottom],
                  ),
                ),
                child: body,
              )
            : body,
      ),
    );
  }

  /// The floating combat numbers, drawn over everything but the overlays. Each
  /// is anchored over the monster it belongs to: its side decides the height,
  /// its SLOT the horizontal position (user 2026-07-27 — a spread move now hits
  /// three at once, and three numbers stacked in the middle of the half would
  /// say nothing about who took what). A small per-id nudge keeps two numbers
  /// in the same slot from landing exactly on top of each other.
  Widget _floatsLayer() => Positioned.fill(
    child: IgnorePointer(
      child: Stack(
        children: [
          for (final f in _floats)
            Align(
              alignment: Alignment(
                (f.alignX + ((f.id % 3) - 1) * 0.06).clamp(-1.0, 1.0),
                f.onEnemy ? -0.42 : 0.16,
              ),
              child: _FloatingNumber(
                key: ValueKey(f.id),
                data: f,
                onDone: () => _removeFloat(f.id),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _confirmFlee() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: FoE.facet(radius: 12, side: const BorderSide(color: FoE.borderGold)),
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

  // ── Inline catch mini-game (user 2026-07-18) ──────────────
  /// Whether the Catch button is live: a capture battle, the player's turn, the
  /// wild alive and worn DOWN into its catchable band (fighting it lower widens
  /// the ring). Overkilling or the wrong turn greys it out.
  bool get _canCatch {
    final t = widget.catchThresholdFraction;
    if (t == null ||
        _catchOpen ||
        _engine.outcome != null ||
        !_engine.isPlayerTurn) {
      return false;
    }
    final wild = _engine.activeEnemy;
    if (wild == null || !wild.alive) return false;
    final frac = wild.maxHp <= 0 ? 0.0 : wild.hp / wild.maxHp;
    return frac <= t;
  }

  /// Opens the catch QTE overlay: the ring sizing (speed + golden band) comes
  /// from the wild's rarity, how deep it was fought, and the active catcher's
  /// catchRate (switch your catcher in to widen it).
  void _startCatch() {
    final wild = _engine.activeEnemy;
    if (wild == null || !_canCatch) return;
    final rarity = wild.rarity;
    final catchRate = _engine.activePlayer?.stat(CreatureStat.catchRate) ?? 0;
    final hpFraction = wild.maxHp <= 0 ? 0.0 : wild.hp / wild.maxHp;
    _catchSpecies = wild.speciesId == null ? null : kSpeciesDefs[wild.speciesId];
    _catchHits = 0;
    _catchHitsNeeded = qteHitsRequired(rarity);
    _catchWindow =
        qteWindow(rarity, hpFraction: hpFraction, catchRate: catchRate);
    _catchMissed = false;
    _catchResolving = false;
    setState(() => _catchOpen = true);
    _startCatchRound();
  }

  void _startCatchRound() {
    if (!_catchOpen) return;
    final species = _catchSpecies;
    final jitter = 1 + (_rng.nextDouble() * 2 - 1) * kQteDurationJitter;
    final secs = species != null ? qteSeconds(species, round: _catchHits) : 1.8;
    _catchBetween = false;
    _ring
      ..duration = Duration(milliseconds: (secs * jitter * 1000).round())
      ..forward(from: 0);
    setState(() {});
  }

  void _catchTap() {
    if (!_catchOpen || _catchBetween || _catchResolving) return;
    _ring.stop();
    final radius = 1 - _ring.value; // outer edge = 1, centre = 0
    final inWindow = radius >= _catchWindow.lo && radius <= _catchWindow.hi;
    if (inWindow) {
      _catchMissed = false;
      _catchHits += 1;
      if (_catchHits >= _catchHitsNeeded) {
        Feel.fanfare(); // caught!
        _catchSucceed();
      } else {
        Feel.tap(); // ring hit, more to go
        _betweenCatchRounds();
      }
    } else if (widget.guaranteedCatch) {
      // Tutorial: a miss simply restarts the ring — the catch cannot be lost.
      _catchHits = 0;
      _catchMissed = true;
      _betweenCatchRounds();
    } else {
      _catchMiss();
    }
  }

  void _betweenCatchRounds() {
    setState(() => _catchBetween = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _catchOpen && _catchBetween) _startCatchRound();
    });
  }

  /// A failed attempt: the wild slips free, the overlay closes and the turn is
  /// SPENT — the fight goes on (user 2026-07-18).
  void _catchMiss() {
    if (_catchResolving) return;
    _catchResolving = true;
    _ring.stop();
    final name = _engine.activeEnemy?.name ?? 'It';
    setState(() {
      _catchOpen = false;
      _catchBetween = false;
    });
    _flashMessage('💨 $name slipped free — your turn is spent!');
    // Consume the action: end the turn so the fight continues.
    if (_engine.isPlayerTurn) _engine.endTurn();
  }

  /// A caught wild: persist the fight (no kill XP — the catch is the reward)
  /// and pop it for the caller to record.
  Future<void> _catchSucceed() async {
    if (_catchResolving) return;
    _catchResolving = true;
    _ring.stop();
    final wild = _engine.activeEnemy;
    setState(() {
      _catchOpen = false;
      _catchBetween = false;
    });
    if (wild == null) return;
    setState(() => _exitingToCatch = true);
    _autoTimer?.cancel();
    _outcomeApplied = true;
    await CreaturesController().applyBattleOutcome(_engine.players, xpEach: 0);
    if (mounted) Navigator.pop(context, CatchSuccess(wild));
  }

  void _flashMessage(String message) {
    setState(() => _flash = message);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  /// THE bar, wearing the app's band (user 2026-07-31: "überall wo es einen
  /// header hat, soll dieser immer genau gleich aussehen").
  ///
  /// A battle's bar carries controls instead of a title — Flee, the turn queue,
  /// the look toggle, AUTO — so it takes [ParchmentHeader.band] rather than the
  /// whole header, which is the same split the settlement's resource strip uses.
  /// The MATERIAL is identical; only what stands on it differs.
  Widget _topBar() => ParchmentHeader.band(
    height: 44,
    child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.flag, color: FoE.parchment, size: 18),
          tooltip: 'Flee',
          onPressed: _engine.outcome == null ? _confirmFlee : null,
        ),
        // The upcoming-turn queue now rides on THIS row, between Flee and AUTO
        // (user request), instead of on a row of its own.
        Expanded(child: _initiativeStrip()),
        const SizedBox(width: 6),
        // Live look toggle: flip between the polished mobile-game skin and the
        // original flat layout (user 2026-07-20).
        IconButton(
          icon: Icon(
            _fancy ? Icons.auto_awesome : Icons.auto_awesome_outlined,
            color: _fancy ? FoE.goldBright : FoE.textDim,
            size: 18,
          ),
          tooltip: _fancy ? 'Classic look' : 'Polished look',
          onPressed: () => setState(() => BattleScreen.polished = !_fancy),
        ),
        const SizedBox(width: 2),
        // Same tint as the other deck buttons (user request); the ✔ marks it on.
        _deckButton(
          icon: Icons.smart_toy,
          label: _autoBattle ? 'AUTO ✔' : 'AUTO',
          base: _kUtilTint,
          enabled: true,
          onTap: () {
            setState(() => _autoBattle = !_autoBattle);
            _scheduleAutoIfNeeded();
          },
          width: 62,
          height: 32,
        ),
        const SizedBox(width: 4),
      ],
    ),
    ),
  );

  // ── Type-matchup key ──────────────────────────────────────
  // A compact "what beats what" chart (user request): the fire→plant→water→fire
  // rock-paper-scissors RING on the left, and light/shadow (which counter each
  // other) stacked on the right. Arrows point attacker → the type it's strong
  // against.
  Widget _typeChart() => Container(
    color: FoE.bg,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A slim tappable header — the whole strip toggles the chart open/shut.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _typeChartOpen = !_typeChartOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hexagon_outlined, size: 13, color: FoE.textDim),
                const SizedBox(width: 6),
                Text('Type chart', style: FoE.dim(size: 11)),
                const SizedBox(width: 4),
                Icon(
                  _typeChartOpen ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: FoE.textDim,
                ),
              ],
            ),
          ),
        ),
        // The full RPS ring + light/shadow key, revealed on demand.
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _typeChartOpen
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: CustomPaint(
                          painter: _RpsRingPainter(),
                          child: _RpsRingLabels(),
                        ),
                      ),
                      SizedBox(width: 30),
                      SizedBox(
                        width: 46,
                        height: 88,
                        child: CustomPaint(
                          painter: _DuoArrowPainter(),
                          child: _DuoLabels(),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    ),
  );

  // ── Turn order (CTB queue) ────────────────────────────────
  // The monsters' PNGs in upcoming-turn order, INLINE between Flee and AUTO
  // (user request). No label, no scroll — it shows exactly as many portraits as
  // fit the gap between the two buttons; ONLY the one whose turn it is (first)
  // is marked, with a plain gold circle.
  Widget _initiativeStrip() => LayoutBuilder(
    builder: (context, box) {
      // Widest slot (the ringed current icon is 34) + gap, so the packed row
      // can never overflow the width between the buttons.
      const slot = 34.0;
      const gap = 5.0;
      final fit = ((box.maxWidth + gap) / (slot + gap)).floor().clamp(1, 12);
      final order = _engine.forecast(fit);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < order.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            // WHOSE turn it is, and WHOSE SIDE. The side bar is new (user
            // 2026-07-27): the strip used to alternate between two monsters, so
            // the sides were obvious; with up to six in the queue a row of bare
            // portraits says nothing about who is about to hit whom.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                i == 0
                    ? Container(
                        width: 34,
                        height: 34,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: FoE.goldBright, width: 2),
                        ),
                        child: _portrait(order[i], size: 26),
                      )
                    : SizedBox(
                        width: 28,
                        height: 28,
                        child: _portrait(order[i], size: 26),
                      ),
                const SizedBox(height: 2),
                Container(
                  width: i == 0 ? 22 : 18,
                  height: 2.5,
                  decoration: ShapeDecoration(color: order[i].isPlayerSide ? FoE.positive : FoE.danger, shape: FoE.facet(radius: 2)),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );

  // ── Battlefield ─────────────────────────────────
  // ONE arena, TWO ranks (redesign 2026-07-31). It used to be two halves, each
  // tiled with its lead monster's element and meeting at a seam under the log.
  // A rank can hold three types, so the tile was picking one of them and calling
  // it the world; the ground is now the REGION (see BattleScene) and the type
  // moved onto a plate under each fighter, where it can be true for all three.
  //
  // Each rank stands in a WEDGE (user 2026-07-31: "Das mittlere Monster ist
  // etwas weiter vorne und die beiden anderen etwas nach hinten"): the middle
  // steps toward the enemy, the flanks hold back and read a touch smaller for
  // depth. Two spearheads pointed at each other, rather than six figures on one
  // ruler line.
  Widget _rank({required bool isEnemy}) {
    final field = isEnemy ? _engine.enemyField : _engine.playerField;
    final bench = isEnemy ? _engine.benchedEnemies : _engine.benchedPlayers;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          final w = box.maxWidth;
          // The strip the reserve waits in, on the rank's OUTER edge (enemy at
          // the top, mine at the bottom) — the sprites keep clear of it.
          final reserve = (h * 0.16).clamp(16.0, 44.0);
          // How far the wedge opens. A fraction of the rank's own height, so it
          // is the same shape on every phone; small on purpose — this is a step
          // forward, not a second row.
          final step = h * _kWedgeStep;
          // CLEARANCE FOR THE LOG (user 2026-07-31: "Monster weiter nach oben,
          // so dass es keine überschneidungen mit dem combat log gibt"). Half
          // the log sits in each rank's half, and the wedge then steps the
          // middle monster straight into it — so the reserved band is the log's
          // half PLUS the step it is about to take, plus a hair of air.
          final seam = _kLogHeight / 2 + step + 6;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: isEnemy ? reserve : seam,
                bottom: isEnemy ? seam : reserve,
                left: 2,
                right: 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < CombatEngine.kFieldSlots; i++)
                      Expanded(
                        child: Transform.translate(
                          // FORWARD is toward the seam: down for the enemy rank,
                          // up for mine. The flanks give way by half a step in
                          // the other direction.
                          offset: Offset(
                            0,
                            (_isCentreSlot(i) ? step : -step * 0.5) *
                                (isEnemy ? 1 : -1),
                          ),
                          child: _fieldSlot(
                            field[i],
                            slot: i,
                            isEnemy: isEnemy,
                            width: w / CombatEngine.kFieldSlots,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (bench.isNotEmpty)
                Positioned(
                  top: isEnemy ? 0 : null,
                  bottom: isEnemy ? null : 2,
                  left: 8,
                  right: 8,
                  height: reserve,
                  child: _reserveStrip(bench, isEnemy: isEnemy),
                ),
            ],
          );
        },
      ),
    );
  }

  /// How far the wedge's point steps forward, as a fraction of the rank height.
  static const double _kWedgeStep = 0.07;

  /// How far the platform is lifted off the bottom of its slot, as a fraction of
  /// its own width — i.e. how deep the monster stands in it.
  static const double _kPlatformLift = 0.16;

  /// The tip of the wedge. With an even number of slots there is no single
  /// middle, so the two innermost both count as the point — the shape stays a
  /// wedge whatever [CombatEngine.kFieldSlots] is dialled to.
  static bool _isCentreSlot(int slot) {
    final n = CombatEngine.kFieldSlots;
    if (n <= 2) return true;
    final mid = (n - 1) / 2;
    return (slot - mid).abs() < 0.51;
  }

  /// One place in the rank: the monster standing there with its plate, or an
  /// empty gap.
  ///
  /// The slot is TAPPABLE on the enemy side — that is how the target is chosen
  /// (user 2026-07-27), and the only new input the simultaneous field needs.
  /// On the player side a tap does nothing: switching is a deliberate,
  /// AP-costing move and lives in the command deck where the other actions are.
  Widget _fieldSlot(
    Combatant? c, {
    required int slot,
    required bool isEnemy,
    required double width,
  }) {
    if (c == null || !c.alive) return const SizedBox.shrink();
    final acting = identical(c, _engine.currentActor) && _engine.outcome == null;
    final targeted = isEnemy && identical(c, _target);
    // A flank stands further back, so it is drawn a little smaller. The size
    // difference is what makes the wedge read as DEPTH rather than as a rank
    // that failed to line up.
    final back = !_isCentreSlot(slot);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isEnemy ? () => setState(() => _targetId = c.id) : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            // Entry slide (user 2026-07-24): on battle start the enemy sweeps
            // in from the right, the player from the left, fading up. Staggered
            // by slot so a rank of three arrives as a rank, not as one block.
            child: AnimatedBuilder(
              animation: _entry,
              builder: (context, child) {
                final raw =
                    (_entry.value * 1.3 - slot * 0.12).clamp(0.0, 1.0);
                final t = Curves.easeOutCubic.transform(raw);
                final dx = (1 - t) * (isEnemy ? 300.0 : -300.0);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Opacity(opacity: t, child: child),
                );
              },
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // THE TYPE, under its own monster (user 2026-07-31) — this
                    // is what the half-wide element tile turned into. Behind the
                    // sprite and shaped like ground, so it reads as standing
                    // somewhere rather than as a card behind a portrait.
                    Padding(
                      // LIFTED (user 2026-07-31: "schiebe die plattformen
                      // weiter nach oben"): sitting flush with the bottom of the
                      // box, the slab was under the sprite's transparent margin
                      // rather than under its feet, so the monster read as
                      // floating above its own ground.
                      padding: EdgeInsets.only(
                        bottom: width * (back ? 0.82 : 0.92) * _kPlatformLift,
                      ),
                      child: TypePodium(
                        element: c.element,
                        width: width * (back ? 0.82 : 0.92),
                        dim: back,
                        // THE RIM IS THE HEALTH BAR (user 2026-07-31). The
                        // straight bar under the name is gone with it — two bars
                        // for one number is one bar too many.
                        hpFraction:
                            c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0),
                        hpColor: _hpColor(
                          c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                    _bigSprite(
                      c,
                      back: !isEnemy,
                      height: box.maxHeight * (back ? 0.92 : 1.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _slotPlate(c, acting: acting, targeted: targeted, width: width),
        ],
      ),
    );
  }

  /// The compact nameplate under one fighter: name, level and HP.
  ///
  /// Replaces the half's single corner plate — a third of the screen wide, so
  /// it carries the three facts you act on and nothing else. Two rings tell you
  /// where you are: GOLD for the monster whose turn it is (with three of your
  /// own acting in turn, the initiative bar alone means hunting for the name),
  /// RED for the enemy your next action is aimed at.
  Widget _slotPlate(
    Combatant c, {
    required bool acting,
    required bool targeted,
    required double width,
  }) {
    final ring = targeted
        ? FoE.danger
        : acting
            ? FoE.goldBright
            : _flatHairline;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: ShapeDecoration(color: _flatSurfaceHi,
        
        
        shadows: const [
          BoxShadow(color: Colors.black38, blurRadius: 0, offset: Offset(0, 2)),
        ], shape: FoE.facet(radius: 9, side: BorderSide(color: ring,
          width: targeted || acting ? 1.6 : 1))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: FoE.label(size: 11).copyWith(
                    color: FoE.parchment,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (c.hasted)
                const Icon(Icons.keyboard_double_arrow_up,
                    size: 11, color: FoE.positive),
              if (c.slowed)
                const Icon(Icons.keyboard_double_arrow_down,
                    size: 11, color: FoE.accentBlue),
              if (c.mainStatus != null)
                Text(c.mainStatus!.emoji, style: const TextStyle(fontSize: 9)),
            ],
          ),
          const SizedBox(height: 2),
          // NO BAR HERE any more (user 2026-07-31): health is the platform's
          // front rim now. The NUMBERS stay — an arc tells you roughly how bad
          // it is, "34/120" tells you whether one more hit finishes it.
          Text(
            'Lv ${c.level} · ${c.hp}/${c.maxHp}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: FoE.dim(size: 9).copyWith(color: FoE.textDim),
          ),
        ],
      ),
    );
  }

  /// Who is waiting behind the rank. The player's reserves are tappable (a
  /// switch, or the forced replacement); the enemy's are just counted — its
  /// bench is unlimited and there is nothing to decide about it.
  Widget _reserveStrip(List<Combatant> bench, {required bool isEnemy}) => Row(
    mainAxisAlignment: isEnemy ? MainAxisAlignment.start : MainAxisAlignment.end,
    children: [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(
          isEnemy ? Icons.groups : Icons.chair,
          size: 13,
          color: FoE.textDim,
        ),
      ),
      // A long enemy wave would run off the edge — past four, say the number.
      if (isEnemy && bench.length > 4)
        Text('+${bench.length} waiting',
            style: FoE.dim(size: 10).copyWith(color: FoE.textDim))
      else
        for (final c in bench) _benchChip(c, isEnemyRow: isEnemy),
    ],
  );

  /// A small bench portrait. Player chips are tappable on the player's turn to
  /// switch (free); enemy chips are just shown.
  Widget _benchChip(Combatant c, {required bool isEnemyRow}) {
    final canSwitchTo = !isEnemyRow &&
        _engine.outcome == null &&
        (_engine.isPlayerTurn || _engine.needsPlayerSwitch);
    return GestureDetector(
      onTap: canSwitchTo
          ? () {
              final idx = _engine.players.indexOf(c);
              final err = _engine.switchActivePlayer(idx);
              if (err != null) _showError(err);
            }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(3),
        decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 6, side: BorderSide(color: canSwitchTo ? FoE.goldBright : FoE.border))),
        child: SizedBox(width: 30, height: 30, child: _portrait(c, size: 22)),
      ),
    );
  }

  /// The large battlefield sprite standing in its HP arc, sized to [height].
  /// [back] picks the back-view art (player) over the front (enemy). Plays the
  /// hit pulse (shake + white flash) when this side was just acted upon (user
  /// 2026-07-18). Whose turn it is is shown in the turn-order bar, not here.
  Widget _bigSprite(
    Combatant c, {
    required bool back,
    required double height,
  }) {
    final url = back ? (c.backImageUrl ?? c.imageUrl) : c.imageUrl;
    final imgH = (height - 12).clamp(72.0, double.infinity);
    // Per COMBATANT (user 2026-07-27): this sprite flinches only if IT was the
    // one struck, and lunges only if it was the one that struck. By side, a hit
    // on one of three would have shaken all three of them.
    final reacts = identical(c, _fxTarget);
    final attacks = identical(c, _fxActor) && !identical(c, _fxTarget);
    final hpFrac = c.maxHp <= 0 ? 0.0 : c.hp / c.maxHp;
    final hpColor = _hpColor(hpFrac);
    return AnimatedBuilder(
      animation: _fx,
      builder: (context, _) {
        final t = _fx.value;
        final active = reacts && _fx.isAnimating;
        final shake = active ? math.sin(t * math.pi * 6) * 7 * (1 - t) : 0.0;
        final flash = active ? (1 - t) * 0.5 : 0.0;
        // Attacker lunge: a quick step toward the seam and back (peaks mid-
        // pulse). The player (back) lunges UP, the enemy DOWN (user 2026-07-20).
        final lunging = attacks && _fx.isAnimating;
        final lungeDy = lunging
            ? (back ? -1 : 1) * math.sin(t * math.pi) * 14.0
            : 0.0;
        return SizedBox(
          width: double.infinity,
          height: height,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // HP as a shallow bowl under the monster — styled like the detail
              // screen's XP arc, sized as a constant fraction of the sprite so
              // it looks identical on every monster (user request).
              Positioned(
                bottom: 16,
                child: SizedBox(
                  width: imgH * 0.96,
                  height: imgH * 0.28,
                  child: CustomPaint(
                    painter: _HpArcPainter(hpFrac, hpColor),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(shake, lungeDy),
                child: Padding(
                  // Lift the monster a bit while the HP arc below stays put
                  // (user 2026-07-18) — the sprite floats just above its bowl.
                  padding: const EdgeInsets.only(bottom: 26),
                  child: _spriteWithShadow(
                    url,
                    imgH,
                    flash,
                    c.element.shadowColor,
                    // The reacting sprite flashes in the STRIKING move's colour.
                    flashColor: reacts ? _fxImpact : Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The battlefield sprite with a drop shadow behind it — a SHARP, un-blurred
  /// silhouette in the element's own [shadowColor] (the same tone, and the same
  /// crisp offset trick, as its type icon's 3D emboss), nudged down so the
  /// monster reads as standing on the tile. The white hit-flash tint rides on
  /// top.
  Widget _spriteWithShadow(
    String? url,
    double imgH,
    double flash,
    Color shadowColor, {
    Color flashColor = Colors.white,
  }) {
    Widget img(FilterQuality quality) => url == null
        ? Icon(Icons.pets, color: FoE.gold, size: imgH * 0.6)
        : Image.network(
            url,
            height: imgH,
            fit: BoxFit.contain,
            filterQuality: quality,
            // A soft placeholder while the sprite streams in, so it fades in
            // instead of popping (user request 2026-07-20).
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : SizedBox(
                    height: imgH,
                    child: Center(
                      child: Icon(
                        Icons.pets,
                        color: FoE.gold.withValues(alpha: 0.25),
                        size: imgH * 0.6,
                      ),
                    ),
                  ),
            errorBuilder: (_, _, _) =>
                Icon(Icons.pets, color: FoE.gold, size: imgH * 0.6),
          );
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          // CLOSE to the monster (user 2026-07-31: "Die effektiven Schatten der
          // Monster sind zu weit vom Monster nach unten geschoben"). 7px down
          // was tuned when the sprite sat flat on a type tile; on a platform the
          // same offset reads as a second, sunken monster. A short drop keeps it
          // an extrude of the silhouette, which is what it is.
          offset: const Offset(1.5, 3),
          // A bit SMALLER than the sprite, anchored at the feet, so it reads as
          // a cast shadow hugging the base on the platform (user request).
          child: Transform.scale(
            scale: 0.94,
            alignment: Alignment.bottomCenter,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                shadowColor,
                BlendMode.srcATop,
              ),
              child: img(FilterQuality.none),
            ),
          ),
        ),
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            flashColor.withValues(alpha: flash),
            BlendMode.srcATop,
          ),
          child: img(FilterQuality.none),
        ),
      ],
    );
  }

  static Color _hpColor(double frac) => frac <= 0
      ? FoE.danger
      : frac < 0.3
      ? FoE.danger
      : frac < 0.6
      ? FoE.gold
      : FoE.positive;

  Widget _bar(double fraction, Color color, String label) => Row(
    children: [
      Expanded(
        child: RecessBar(
          value: fraction.clamp(0.0, 1.0),
          color: color,
          height: 9,
          onDark: true,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: FoE.dim(size: 9)),
    ],
  );

  Widget _portrait(Combatant c, {required double size}) => c.imageUrl == null
      ? Icon(Icons.pets, color: FoE.gold, size: size)
      : Image.network(
        filterQuality: FilterQuality.none,
          c.imageUrl!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>
              Icon(Icons.pets, color: FoE.gold, size: size),
        );

  // The battle log's fixed height. The log is centred on the seam, so its
  // bottom edge sits _kLogHeight/2 into the lower half — which is where each
  // rank's sprites stop, so the two never overlap.
  static const double _kLogHeight = 54;

  Widget _logLine() {
    // The middle bar: overlaid on the seam where the two tiles meet, EDGE TO
    // EDGE across the full width (user request), tall enough for the LAST TWO
    // log lines — the newest in full colour, the one before it dimmed (user
    // 2026-07-18). A rejected action / catch-miss flashes here in danger colour
    // instead of a bottom SnackBar. Fixed height so it never nudges the field.
    final flashing = _flash != null;
    final lines = _log.isEmpty
        ? const ['The battle begins!']
        : _log.sublist(_log.length >= 2 ? _log.length - 2 : 0);
    return Container(
      width: double.infinity,
      height: _kLogHeight,
      alignment: Alignment.center,
      // Fancy: a floating rounded, glossy banner with a gold hairline + shadow.
      // Classic: an edge-to-edge square opaque bar (user request).
      margin: _fancy
          ? const EdgeInsets.symmetric(horizontal: 14)
          : EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: _fancy
          ? ShapeDecoration(color: _flatSurfaceHi,
              
              
              shadows: const [
                BoxShadow(
                    color: Colors.black38, blurRadius: 0, offset: Offset(0, 3)),
              ], shape: FoE.facet(radius: 13, side: BorderSide(color: _flatHairline)))
          : const BoxDecoration(color: FoE.panelDark),
      child: flashing
          ? Text(
              _flash!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: FoE.label(size: 11).copyWith(color: FoE.danger),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Newest line on TOP, the earlier one dimmed below it (user
                // request): reverse so the latest action reads first.
                for (var i = lines.length - 1; i >= 0; i--)
                  Text(
                    lines[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: FoE.label(size: 11).copyWith(
                      color: i == lines.length - 1 ? FoE.parchment : FoE.textDim,
                    ),
                  ),
              ],
            ),
    );
  }

  // ── Action panel (command deck) ───────────────────────────
  // A distinct footer below the arena (user 2026-07): a dark bar with a gold
  // hairline on top. NEW arrangement (user request): the AP read-out + End Turn
  // on top, then the Items/Change/Catch utilities, and the ability tiles — each
  // FULLY painted in its type colour — at the BOTTOM, in the thumb zone. Height
  // is COMPUTED to fit everything (never scrolls), derived from the active
  // PLAYER's ability count so the enemy's turn reserves the same space.
  // How far the arena is nudged DOWN toward the deck (fraction of its height).
  // Kept small so the lower tile's rounded bottom corners stay FULLY visible
  // above the deck instead of tucking behind it (user request).
  static const double _kArenaDrop = 0.03;
  static const double _kStatusH = 16; // enemy-turn status line
  static const double _kAbilityW = 112;
  static const double _kAbilityH = 56;
  static const double _kTileGap = 8;
  static const double _kMenuH = 44;
  static const double _kApPipH = 17; // one vertical AP pip incl. its margin
  static const double _kApColW = 26; // AP column + its gap, reserved beside abilities
  // Shared tint for EVERY non-type deck button (Auto/End Turn/Items/Catch/Change)
  // so they read as one utility family next to the vivid type abilities.
  static const Color _kUtilTint = FoE.panelLight;

  Widget _actionPanel() {
    return LayoutBuilder(
      builder: (context, box) {
        // Abilities share the row with a vertical AP column, so they lose its
        // width.
        final usable = box.maxWidth - 20 - _kApColW;
        final perRow =
            ((usable + _kTileGap) / (_kAbilityW + _kTileGap)).floor().clamp(1, 6);
        final abilities = _engine.activePlayer?.abilities.length ?? 0;
        final boxes = 1 + abilities; // attack + abilities
        final rows = (boxes / perRow).ceil().clamp(1, 6);
        final abilitiesH = rows * _kAbilityH + (rows - 1) * _kTileGap;
        final maxAp = _engine.activePlayer != null
            ? maxActionPointsForStage(_engine.activePlayer!.stage)
            : kBaseActionPoints;
        final apColH = maxAp * _kApPipH;
        // utility row + gap + (abilities | AP column, tallest). The deck now
        // ENDS directly above the buttons (user request): the enemy-turn status
        // no longer reserves a strip on top — it floats just above the deck (see
        // the overlay below) so the deck shrinks and the arena grows to match.
        final contentH = _kMenuH + 8 + math.max(abilitiesH, apColH);
        final panelH = contentH + 22; // top 8 / bottom 10 padding + buffer

        final showStatus = _engine.outcome == null && !_engine.needsPlayerSwitch;
        final myTurn = showStatus && _engine.isPlayerTurn && !_autoBattle;

        Widget content;
        if (_engine.outcome != null) {
          content = const SizedBox.shrink();
        } else if (_entering) {
          // Hold input while the fighters are still sliding on.
          content = Center(
            child: Text('Get ready…',
                style: FoE.title(size: 15).copyWith(color: FoE.goldBright)),
          );
        } else if (_engine.needsPlayerSwitch) {
          content = Center(
            child: _actionBtn(
              'Send in a reserve',
              icon: Icons.swap_horiz,
              enabled: true,
              onTap: () => _openSwitchPicker(forced: true),
            ),
          );
        } else {
          content = _playerActions();
        }
        return Container(
          height: panelH.toDouble(),
          // Fancy: a FLAT rounded command tray — matte surface, thin cool top
          // hairline, one soft shadow for separation (no gloss/gradient).
          // Classic: flat black (user request).
          decoration: _fancy
              ? const BoxDecoration(
                  color: _flatSurface,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(3)),
                  border: Border(
                    top: BorderSide(color: _flatHairline, width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 0,
                      offset: Offset(0, -3),
                    ),
                  ],
                )
              : const BoxDecoration(color: FoE.bg),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          // The status line floats ABOVE the deck (negative top) so it never
          // reserves height inside it.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              if (showStatus && !myTurn)
                Positioned(
                  top: -_kStatusH - 2,
                  left: 0,
                  right: 0,
                  child: _turnStatus(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _playerActions() {
    // MY turn = actionable. During the enemy's turn (or auto-battle) the same
    // buttons show but are greyed and inert (user 2026-07-18).
    final myTurn = _engine.outcome == null &&
        !_engine.needsPlayerSwitch &&
        _engine.isPlayerTurn &&
        !_autoBattle;
    final actor = _engine.activePlayer;
    if (actor == null) return const SizedBox.shrink();
    // AP are CARRIED per monster now (user 2026-07-20), so show MY monster's
    // real pool at all times — including during the enemy's turn, when what you
    // banked is exactly what you're planning around. `myTurn` alone greys the
    // buttons; it must no longer zero the read-out.
    final ap = actor.ap;
    final maxAp = maxActionPointsForStage(actor.stage);
    final canSwitch = _engine.benchedPlayers.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Utilities — ALL the same tint (user request), order: End Turn,
        // Items, Change, Catch.
        SizedBox(
          height: _kMenuH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _deckButton(
                  icon: Icons.skip_next,
                  label: 'End Turn',
                  base: _kUtilTint,
                  enabled: myTurn,
                  onTap: _engine.endTurn,
                ),
              ),
              const SizedBox(width: _kTileGap),
              Expanded(
                child: _deckButton(
                  icon: Icons.backpack,
                  label: 'Items',
                  base: _kUtilTint,
                  enabled: myTurn,
                  onTap: _openItems,
                ),
              ),
              const SizedBox(width: _kTileGap),
              Expanded(
                child: _deckButton(
                  icon: Icons.swap_horiz,
                  label: 'Change',
                  base: _kUtilTint,
                  enabled: myTurn && canSwitch && ap >= kSwitchApCost,
                  onTap: () => _openSwitchPicker(forced: false),
                ),
              ),
              const SizedBox(width: _kTileGap),
              Expanded(
                child: _deckButton(
                  icon: Icons.catching_pokemon,
                  label: 'Catch',
                  base: _kUtilTint,
                  enabled: myTurn && _canCatch,
                  onTap: _startCatch,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Ability tiles (thumb zone) + the vertical AP column to their RIGHT.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: _kTileGap,
                runSpacing: _kTileGap,
                children: [
                  _abilityBtn('Attack', kBasicAttackApCost,
                      element: CreatureElement.neutral,
                      enabled: myTurn && ap >= kBasicAttackApCost,
                      onTap: _attack),
                  for (final ability in actor.abilities)
                    _abilityBtn(
                      ability.name,
                      CombatEngine.abilityApCost(ability),
                      element: ability.element,
                      enabled:
                          myTurn && ap >= CombatEngine.abilityApCost(ability),
                      onTap: () => _useAbility(ability),
                      ability: ability,
                    ),
                ],
              ),
            ),
            const SizedBox(width: _kTileGap),
            _apColumn(ap, maxAp),
          ],
        ),
      ],
    );
  }

  /// AP as a VERTICAL stack of pips beside the abilities (user request): the
  /// remaining points glow gold, spent ones are greyed out.
  Widget _apColumn(int ap, int maxAp) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < maxAp; i++)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2.5),
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Remaining (top) = gold; spent = greyed out.
            color: i < ap ? FoE.gold : FoE.panelLight,
            border: Border.all(
              color: i < ap ? FoE.gold : FoE.border,
              width: 1.5,
            ),
          ),
        ),
    ],
  );

  /// The "not your turn" state — a compact centred line with a live spinner,
  /// slim enough to fit the thin status row.
  Widget _turnStatus() => Center(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(strokeWidth: 2, color: FoE.textDim),
        ),
        const SizedBox(width: 7),
        Text(
          _autoBattle ? 'Auto-battle running' : 'Enemy is acting',
          style: FoE.dim(size: 11),
        ),
      ],
    ),
  );

  /// An ability tile: the SAME type backdrop as the monsters — the element's
  /// gradient with its symbol EMBOSSED into the background (via CreatureBackdrop)
  /// — with the name + AP on top and NO border (user request). Fixed size so the
  /// name length never changes the footprint. Disabled = flat greyed panel.
  Widget _abilityBtn(
    String name,
    int ap, {
    required CreatureElement element,
    required bool enabled,
    required VoidCallback onTap,
    AbilityDef? ability,
  }) {
    // Dark text on light type colours (e.g. Light), white on the rest.
    final onColor = element.color.computeLuminance() > 0.5
        ? const Color(0xFF1A1300)
        : Colors.white;
    final fg = enabled ? onColor : FoE.textMuted;
    // Type effectiveness vs the CURRENT enemy — an inline cue so the static
    // type chart isn't the only place to read it (user request 2026-07-20).
    // Only DAMAGE moves with a real element land bonus/reduced damage.
    final isDamage = ability == null || ability.kind == AbilityKind.damage;
    final mult = (enabled && isDamage)
        ? _effectivenessVsEnemy(element)
        : 1.0;
    final radius = FoE.radiusSmall + 2;
    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.label(size: 12).copyWith(
            color: fg,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$ap AP',
          style: FoE.dim(size: 10).copyWith(
            color: enabled ? fg.withValues(alpha: 0.85) : FoE.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    Widget tile = enabled
        ? CreatureBackdrop(
            element: element,
            radius: radius,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Align(alignment: Alignment.centerLeft, child: content),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            alignment: Alignment.centerLeft,
            decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: radius)),
            child: content,
          );
    // Strong/weak → a coloured ring + a corner badge (flat: crisp border, no
    // glow bloom).
    final effColor = mult > 1.0
        ? FoE.positive
        : mult < 1.0
            ? FoE.danger
            : null;
    if (effColor != null) {
      tile = Container(
        decoration: ShapeDecoration(shape: FoE.facet(radius: radius, side: BorderSide(color: effColor, width: 2))),
        child: tile,
      );
    }
    return SizedBox(
      width: _kAbilityW,
      height: _kAbilityH,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onLongPress: () => _showAbilityPreview(name, ap, element, ability),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: tile),
            if (effColor != null)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: effColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: FoE.bg, width: 1.5),
                  ),
                  child: Icon(
                    mult > 1.0
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 13,
                    color: FoE.bg,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Type multiplier the given attack [element] lands on the SELECTED enemy —
  /// 1.0 when nothing is targeted or the move is typeless. It follows the
  /// target (user 2026-07-27), so tapping another monster re-reads the preview
  /// against the one you are actually about to hit.
  double _effectivenessVsEnemy(CreatureElement element) {
    final enemy = _target;
    if (enemy == null || element == CreatureElement.neutral) return 1.0;
    return element.multiplierVs(enemy.element);
  }

  static String _fmtMult(double m) =>
      m % 1 == 0 ? m.toInt().toString() : m.toStringAsFixed(1);

  Widget _previewRow(IconData icon, String text, {Color? color}) => Padding(
    padding: const EdgeInsets.only(top: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color ?? FoE.textDim),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: FoE.label(size: 13).copyWith(color: color ?? FoE.parchment),
          ),
        ),
      ],
    ),
  );

  /// Long-press preview of an ability (or the basic Attack when [a] is null):
  /// what it does, its numbers, and its live effectiveness vs the current enemy
  /// — so the player can weigh a move before spending AP (user request).
  Future<void> _showAbilityPreview(
    String name,
    int ap,
    CreatureElement element,
    AbilityDef? a,
  ) async {
    final enemy = _target;
    final isDamage = a == null || a.kind == AbilityKind.damage;
    final rows = <Widget>[];

    if (isDamage && enemy != null && element != CreatureElement.neutral) {
      final mult = _effectivenessVsEnemy(element);
      final (label, icon, color) = mult > 1.0
          ? ('Super effective vs ${enemy.name}', Icons.keyboard_arrow_up, FoE.positive)
          : mult < 1.0
              ? ('Resisted by ${enemy.name}', Icons.keyboard_arrow_down, FoE.danger)
              : ('Neutral vs ${enemy.name}', Icons.remove, FoE.textDim);
      rows.add(_previewRow(icon, '$label  (×${_fmtMult(mult)})', color: color));
    }

    if (a == null) {
      rows.add(_previewRow(
          Icons.bolt, 'Basic attack · Power ${CombatEngine.basicAttackPower}'));
      rows.add(_previewRow(
          Icons.info_outline, 'Free, typeless strike — never lands bonus damage.'));
    } else {
      if (a.kind == AbilityKind.damage) {
        rows.add(_previewRow(Icons.bolt, 'Power ${a.power}'));
      }
      // ONE row per effect, in the effect's own numbers (user 2026-07-30). It
      // used to print "Burn · 30% chance" — which said nothing about how hard or
      // how long, and since abilities carry their own duration and magnitude now,
      // two moves with that exact line can be wildly different fights.
      // Same text the Dev-Mode form previews, so the card cannot drift from it.
      for (final e in a.effects) {
        rows.add(_previewRow(
          switch (e.kind.family) {
            AbilityEffectFamily.mainStatus => Icons.local_fire_department,
            AbilityEffectFamily.debuff => Icons.visibility_off,
            AbilityEffectFamily.selfBuff => Icons.shield,
            AbilityEffectFamily.heal => Icons.favorite,
            AbilityEffectFamily.regen => Icons.eco,
            AbilityEffectFamily.recoil => Icons.dangerous,
            AbilityEffectFamily.lifesteal => Icons.bloodtype,
            AbilityEffectFamily.selfPenalty => Icons.warning_amber,
          },
          summariseAbilityEffect(e),
          color: switch (e.kind.family) {
            AbilityEffectFamily.heal ||
            AbilityEffectFamily.regen ||
            AbilityEffectFamily.selfBuff ||
            AbilityEffectFamily.lifesteal =>
              FoE.positive,
            AbilityEffectFamily.selfPenalty ||
            AbilityEffectFamily.recoil =>
              FoE.danger,
            _ => null,
          },
        ));
      }
      if (a.priority > 0) {
        rows.add(_previewRow(
            Icons.flash_on, 'Priority +${a.priority} — acts sooner'));
      }
      rows.add(_previewRow(Icons.gps_fixed, 'Target: ${a.target.label}'));
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FoE.panelDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 14, 16, 16 + MediaQuery.of(ctx).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: ShapeDecoration(color: element.color, shape: FoE.facet(radius: 6)),
                  child: Text(
                    element.label,
                    style: FoE.label(size: 11).copyWith(
                      color: element.color.computeLuminance() > 0.5
                          ? const Color(0xFF1A1300)
                          : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: FoE.title(size: 16))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: ShapeDecoration(color: _kUtilTint, shape: FoE.facet(radius: 6)),
                  child: Text('$ap AP',
                      style: FoE.label(size: 11)
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            ...rows,
            if (a != null && a.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(a.description, style: FoE.dim(size: 12)),
            ],
          ],
        ),
      ),
    );
  }

  /// A non-type deck button (Auto / Items / Change / Catch / End Turn): the SAME
  /// embossed-symbol backdrop tile as the abilities — [symbol] worked into a
  /// [base]-coloured background, [label] on top, NO border (user request).
  /// Disabled = flat greyed panel. Fills its parent when [width]/[height] are
  /// null (utility row uses stretch); pass them for a fixed size (Auto).
  Widget _deckButton({
    required IconData icon,
    required String label,
    required Color base,
    required bool enabled,
    required VoidCallback onTap,
    double? width,
    double? height,
  }) {
    final onColor =
        base.computeLuminance() > 0.5 ? const Color(0xFF1A1300) : Colors.white;
    final fg = enabled ? onColor : FoE.textMuted;
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: FoE.label(size: 12).copyWith(
          color: fg,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    final radius = FoE.radiusSmall + 2;
    Widget tile = enabled
        ? CreatureBackdrop(
            element: CreatureElement.neutral,
            baseColor: base,
            iconSymbol: icon,
            radius: radius,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Center(child: content),
          )
        : Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: radius)),
            child: content,
          );
    if (_fancy && enabled) {
      // Flat button: just a subtle shadow to lift it off the tray — no gloss.
      tile = DecoratedBox(
        decoration: ShapeDecoration(shadows: const [
            BoxShadow(color: Colors.black26, blurRadius: 0, offset: Offset(0, 2)),
          ], shape: FoE.facet(radius: radius)),
        child: tile,
      );
    }
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: SizedBox(width: width, height: height, child: tile),
    );
  }

  /// The forced-switch button (active fainted) — a single prominent gold pill.
  Widget _actionBtn(
    String label, {
    required bool enabled,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    final text = Text(
      label,
      style: FoE.label(size: 13).copyWith(
        color: FoE.goldBright,
        fontWeight: FontWeight.w700,
      ),
    );
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: ShapeDecoration(color: FoE.panelMid, shape: FoE.facet(radius: FoE.radiusSmall + 3, side: BorderSide(color: FoE.gold, width: 1.5))),
        child: icon == null
            ? text
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: FoE.goldBright),
                  const SizedBox(width: 8),
                  text,
                ],
              ),
      ),
    );
  }

  // ── Items (in-battle heal potions) ────────────────────────
  /// Opens a sheet of held heal items; using one heals the ACTIVE monster and
  /// spends the turn (user 2026-07-18).
  Future<void> _openItems() async {
    final settlement = SettlementController();
    final actor = _engine.activePlayer;
    if (actor == null) return;
    // Battle-usable heal + buff items apply to the ACTIVE monster. (Revive is
    // out-of-battle only — the active can't be K.O., and bench-targeting is a
    // later slice.)
    final held = [
      for (final e in settlement.items.entries)
        if (kItemDefs[e.key] case final ItemDef d
            when d.battleUsable &&
                (d.kind == ItemKind.heal || d.kind == ItemKind.buff))
          (d, e.value),
    ];
    final chosen = await showModalBottomSheet<ItemDef>(
      context: context,
      backgroundColor: FoE.panelDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Use an item (spends the turn)', style: FoE.title(size: 14)),
            const SizedBox(height: 12),
            if (held.isEmpty)
              Text('No usable items in your bag.', style: FoE.dim(size: 12))
            else
              for (final (def, count) in held)
                GestureDetector(
                  onTap: () => Navigator.pop(context, def),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: FoE.panel(radius: 8),
                    child: Row(
                      children: [
                        Text(def.emoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            def.kind == ItemKind.buff
                                ? '${def.name} ×$count · ${_selfBuffForStat(def.buffStat).name}'
                                : '${def.name} ×$count · +${healFromItem(def, (actor.maxHp - actor.hp).toDouble()).round()} HP',
                            style: FoE.label(size: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    // Spend FIRST — if the item can't leave the bag, nothing happens.
    final err = await settlement.consumeItem(chosen.id);
    if (!mounted) return;
    if (err != null) {
      _flashMessage(err);
      return;
    }
    switch (chosen.kind) {
      case ItemKind.buff:
        final buff = _selfBuffForStat(chosen.buffStat);
        // The ITEM'S OWN magnitude (fixed 2026-07-30). ItemDef.magnitude is
        // documented as "buff fraction" and was simply dropped here: every buff
        // item granted the catalog's +30 %/+25 %, so the number the author typed
        // did nothing. A 0 still means "the standard strength" — applySelfBuff
        // resolves it the same way an ability's does.
        actor.applySelfBuff(buff, value: chosen.magnitude);
        _flashMessage('${chosen.emoji} ${actor.name} — ${buff.name}!');
      default: // heal
        final heal =
            healFromItem(chosen, (actor.maxHp - actor.hp).toDouble()).round();
        actor.hp = (actor.hp + heal).clamp(0, actor.maxHp).toInt();
        _flashMessage('${chosen.emoji} ${actor.name} +$heal HP');
    }
    // Using an item spends the turn.
    if (_engine.isPlayerTurn) _engine.endTurn();
    setState(() {});
  }

  /// Maps an item's buff stat onto the engine's self-buff (rage=attack,
  /// armor=defense, haste=speed; attack/other → rage).
  SelfBuffKind _selfBuffForStat(CreatureStat? s) => switch (s) {
    CreatureStat.defense => SelfBuffKind.armor,
    CreatureStat.speed => SelfBuffKind.haste,
    _ => SelfBuffKind.rage,
  };

  // ── End overlay ───────────────────────────────────────────
  Widget _endOverlay() {
    final outcome = _engine.outcome!;
    final (title, subtitle) = switch (outcome) {
      CombatOutcome.victory => ('🏆 Victory!', 'Your team grew stronger.'),
      CombatOutcome.defeat => ('💀 Defeat…', 'Your team needs healing.'),
      CombatOutcome.fled => ('🏃 Fled', 'No reward.'),
    };
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        // Height-bounded + scrollable so a fight where the whole party levels
        // (several cards) can't overflow the panel (user 2026-07-24).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        padding: const EdgeInsets.all(20),
        decoration: FoE.panel(radius: 12, glow: true),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: FoE.title(size: 20)),
            const SizedBox(height: 8),
            Text(subtitle, style: FoE.label(size: 13)),
            if (outcome == CombatOutcome.victory) ...[
              const SizedBox(height: 16),
              _victoryRewards(),
              if (_levelUps.isNotEmpty) ...[
                const SizedBox(height: 16),
                _levelUpSection(),
              ],
              if (widget.victoryRewards.isNotEmpty) ...[
                const SizedBox(height: 16),
                _unlockSection(),
              ],
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
                    style: FoE.label(size: 14).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  /// Victory spoils: how many foes fell, each team member with the XP it earned,
  /// and a gold XP bar that sweeps 0→full so the reward feels earned (user
  /// request 2026-07-20).
  Widget _victoryRewards() {
    final foes = _engine.enemies.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.military_tech, size: 15, color: FoE.gold),
            const SizedBox(width: 6),
            Text('Defeated $foes ${foes == 1 ? 'foe' : 'foes'}',
                style: FoE.dim(size: 12)),
          ],
        ),
        const SizedBox(height: 12),
        // Team portraits, each tagged with the XP it gained.
        Wrap(
          spacing: 14,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in _engine.players)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: p.alive ? 1 : 0.4,
                    child: Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(3),
                      decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 8, side: BorderSide(color: FoE.border))),
                      child: _portrait(p, size: 30),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('+$_xpEach XP',
                      style: FoE.label(size: 10).copyWith(color: FoE.gold)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        // The sweeping XP bar (purely celebratory — one full sweep).
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => RecessBar(
            value: v,
            color: FoE.gold,
            height: 11,
            onDark: true,
          ),
        ),
      ],
    );
  }

  // ── Level-up celebration (user 2026-07-24) ────────────────
  /// Shown after a won fight for every monster that gained a level: a card that
  /// pops in with "Lv X → Y" and the stat points it earned, so the growth is
  /// visible instead of silently banked.
  Widget _levelUpSection() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⬆️', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text('Level Up!',
              style: FoE.title(size: 14).copyWith(color: FoE.goldBright)),
        ],
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < _levelUps.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _levelUpCard(_levelUps[i], i),
        ),
    ],
  );

  /// The map-progression spoils of this fight (new party size, buildings,
  /// features, boss rewards) — user 2026-07-24: show what a win unlocked.
  Widget _unlockSection() => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 380),
    curve: Curves.easeOutBack,
    builder: (context, v, child) => Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.scale(scale: 0.9 + 0.1 * v.clamp(0.0, 1.0), child: child),
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 12, side: BorderSide(color: FoE.goldBright.withValues(alpha: 0.6)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎁', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text('Unlocked!',
                  style: FoE.title(size: 14).copyWith(color: FoE.goldBright)),
            ],
          ),
          const SizedBox(height: 8),
          for (final r in widget.victoryRewards)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(r.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.text,
                      style: FoE.label(size: 12).copyWith(color: FoE.parchment),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _levelUpCard(LevelUpResult up, int index) {
    return TweenAnimationBuilder<double>(
      // Staggered pop-in: later cards settle a touch after the first, for a
      // small cascade.
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + index * 130),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.85 + 0.15 * v.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 10, side: BorderSide(color: FoE.gold.withValues(alpha: 0.55)))),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: up.imageUrl == null
                  ? const Icon(Icons.pets, color: FoE.gold, size: 24)
                  : Image.network(
                      up.imageUrl!,
                      filterQuality: FilterQuality.none,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.pets, color: FoE.gold, size: 24),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          up.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.label(size: 12)
                              .copyWith(color: FoE.parchment),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Lv ${up.fromLevel}',
                          style: FoE.dim(size: 11)),
                      const Text('  →  ',
                          style: TextStyle(color: FoE.textDim, fontSize: 11)),
                      Text('${up.toLevel}',
                          style: FoE.value(size: 13)
                              .copyWith(color: FoE.goldBright)),
                    ],
                  ),
                  if (up.statGains.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final e in up.statGains.entries)
                          _statGainChip(e.key, e.value),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statGainChip(CreatureStat stat, int gain) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: ShapeDecoration(color: FoE.positive.withValues(alpha: 0.16), shape: FoE.facet(radius: 6)),
    child: Text(
      '${_statAbbrev(stat)} +$gain',
      style: FoE.label(size: 10).copyWith(color: FoE.positive),
    ),
  );

  static String _statAbbrev(CreatureStat stat) => switch (stat) {
    CreatureStat.hp => 'HP',
    CreatureStat.attack => 'ATK',
    CreatureStat.defense => 'DEF',
    CreatureStat.speed => 'SPD',
    CreatureStat.catchRate => 'CATCH',
    _ => stat.label,
  };

  // ── Catch mini-game overlay ───────────────────────────────
  /// The inline ring QTE: a shrinking ring closes on the wild — tap while it
  /// crosses the golden band. Success catches it; a miss burns the turn and the
  /// fight goes on (user 2026-07-18).
  Widget _catchOverlay() {
    final wild = _engine.activeEnemy;
    final showRing = _catchOpen && !_catchBetween;
    final radius = showRing ? (1 - _ring.value) : 1.0;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _catchTap(),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.74),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Catch it!',
                  style: FoE.title(size: 18).copyWith(color: FoE.goldBright)),
              const SizedBox(height: 4),
              Text(
                _catchMissed && _catchBetween
                    ? '💫 Missed — here it comes again!'
                    : _catchBetween
                    ? 'Get ready…'
                    : 'Hit $_catchHits/$_catchHitsNeeded — tap in the golden ring!',
                style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              ),
              const SizedBox(height: 14),
              // Zoom in on the wild as the overlay opens — a one-shot scale so
              // it feels like the camera pushes onto the enemy (user 2026-07-18).
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.55, end: 1.0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: CustomPaint(
                    painter: _BattleRingPainter(
                      radiusFraction: radius,
                      showRing: showRing,
                      windowLo: _catchWindow.lo,
                      windowHi: _catchWindow.hi,
                      zoneColor: _catchBetween ? FoE.positive : FoE.gold,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 150,
                        height: 150,
                        child: wild?.imageUrl == null
                            ? const Icon(Icons.pets, color: FoE.gold, size: 80)
                            : Image.network(
                                wild!.imageUrl!,
                                filterQuality: FilterQuality.none,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(
                                    Icons.pets, color: FoE.gold, size: 80),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('Miss and your turn is spent.', style: FoE.dim(size: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// HP as an open-topped semicircle "bowl" under the monster — drawn EXACTLY
/// like the detail screen's XP arc [_XpArcPainter] (same 210° sweep, thin
/// track, leading dot), only colour-coded by HP instead of gold (user request).
/// Everything scales with [size], which the caller sets as a constant fraction
/// of the sprite PNG, so the bowl keeps the same proportions on every monster
/// and at every sprite size — mirroring the XP arc's own 3px-in-57px ratio.
class _HpArcPainter extends CustomPainter {
  final double frac;
  final Color color;
  const _HpArcPainter(this.frac, this.color);

  static const _start = 195 * math.pi / 180;
  static const _sweep = -210 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.height * (3 / 57); // same stroke:height ratio as the XP arc
    final rect = (Offset.zero & size).deflate(stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawArc(rect, _start, _sweep, false, track);

    final f = frac.clamp(0.0, 1.0);
    if (f <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = color;
    canvas.drawArc(rect, _start, _sweep * f, false, fill);

    // Leading dot at the head of the fill, as on the XP arc.
    final angle = _start + _sweep * f;
    final pos = Offset(
      rect.center.dx + rect.width / 2 * math.cos(angle),
      rect.center.dy + rect.height / 2 * math.sin(angle),
    );
    final dotR = stroke * 0.9;
    canvas.drawCircle(pos, dotR * 1.6, Paint()..color = Colors.black.withValues(alpha: 0.35));
    canvas.drawCircle(pos, dotR, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HpArcPainter old) =>
      old.frac != frac || old.color != color;
}

/// Golden target band + shrinking ring for the inline catch QTE (mirrors the
/// capture screen's ring). The band bounds come from the wild's rarity/depth.
class _BattleRingPainter extends CustomPainter {
  final double radiusFraction;
  final bool showRing;
  final double windowLo;
  final double windowHi;
  final Color zoneColor;

  const _BattleRingPainter({
    required this.radiusFraction,
    required this.showRing,
    required this.windowLo,
    required this.windowHi,
    required this.zoneColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2 - 4;

    final band = Paint()
      ..color = zoneColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (windowHi - windowLo) * maxR;
    final bandMid = (windowLo + windowHi) / 2;
    canvas.drawCircle(center, bandMid * maxR, band);

    final bandEdge = Paint()
      ..color = zoneColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, windowLo * maxR, bandEdge);
    canvas.drawCircle(center, windowHi * maxR, bandEdge);

    if (showRing) {
      final ring = Paint()
        ..color = FoE.accentBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawCircle(center, radiusFraction * maxR, ring);
    }
  }

  @override
  bool shouldRepaint(_BattleRingPainter old) =>
      old.radiusFraction != radiusFraction ||
      old.showRing != showRing ||
      old.windowLo != windowLo ||
      old.windowHi != windowHi ||
      old.zoneColor != zoneColor;
}

/// The fire→plant→water→fire rock-paper-scissors CIRCLE (user request): a faint
/// ring with GREY arc arrows running clockwise, each pointing at the type it is
/// strong against. Emoji sit on the ring via _RpsRingLabels.
class _RpsRingPainter extends CustomPainter {
  const _RpsRingPainter();

  static const double _d2r = math.pi / 180;

  static Offset _rot(Offset v, double a) {
    final c = math.cos(a), s = math.sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  void _arc(Canvas canvas, Offset c, double r, double startDeg, double endDeg,
      Paint stroke, Paint fill) {
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      startDeg * _d2r,
      (endDeg - startDeg) * _d2r,
      false,
      stroke,
    );
    // Arrowhead at the END, pointing along the clockwise travel direction.
    final endA = endDeg * _d2r;
    final tip = c + Offset(math.cos(endA), math.sin(endA)) * r;
    final back = Offset(math.sin(endA), -math.cos(endA)); // opposite of tangent
    const head = 7.0;
    final p1 = tip + _rot(back, 0.5) * head;
    final p2 = tip + _rot(back, -0.5) * head;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      fill,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 * 0.70;
    // The faint circle itself.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = FoE.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final stroke = Paint()
      ..color = FoE.textDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = FoE.textDim
      ..style = PaintingStyle.fill;
    // Fire(top,-90°) → Plant(30°) → Water(150°) → Fire, clockwise. Inset ~22°
    // from each emoji so the arrows don't run under the glyphs.
    _arc(canvas, c, r, -68, 8, stroke, fill); // fire → plant
    _arc(canvas, c, r, 52, 128, stroke, fill); // plant → water
    _arc(canvas, c, r, 172, 248, stroke, fill); // water → fire
  }

  @override
  bool shouldRepaint(_RpsRingPainter old) => false;
}

class _RpsRingLabels extends StatelessWidget {
  const _RpsRingLabels();
  @override
  Widget build(BuildContext context) => const Stack(
    children: [
      // Positions match the painter: fire top, plant lower-right, water
      // lower-left, all on the ring (0.70 of the half-box).
      Align(
        alignment: Alignment(0, -0.70),
        child: Text('🔥', style: TextStyle(fontSize: 21)),
      ),
      Align(
        alignment: Alignment(0.606, 0.35),
        child: Text('🌿', style: TextStyle(fontSize: 21)),
      ),
      Align(
        alignment: Alignment(-0.606, 0.35),
        child: Text('💧', style: TextStyle(fontSize: 21)),
      ),
    ],
  );
}

/// Light and shadow counter EACH OTHER — a GREY double-headed arrow between them.
class _DuoArrowPainter extends CustomPainter {
  const _DuoArrowPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final top = Offset(size.width * 0.5, size.height * 0.33);
    final bottom = Offset(size.width * 0.5, size.height * 0.67);
    canvas.drawLine(
      top,
      bottom,
      Paint()
        ..color = FoE.textDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    final headPaint = Paint()
      ..color = FoE.textDim
      ..style = PaintingStyle.fill;
    void head(Offset tip, double dirY) {
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(tip.dx - 4.5, tip.dy + dirY * 8)
          ..lineTo(tip.dx + 4.5, tip.dy + dirY * 8)
          ..close(),
        headPaint,
      );
    }

    head(top, 1); // arrow pointing up (light beats shadow)
    head(bottom, -1); // arrow pointing down (shadow beats light)
  }

  @override
  bool shouldRepaint(_DuoArrowPainter old) => false;
}

class _DuoLabels extends StatelessWidget {
  const _DuoLabels();
  @override
  Widget build(BuildContext context) => const Stack(
    children: [
      Align(
        alignment: Alignment(0, -0.66),
        child: Text('✨', style: TextStyle(fontSize: 21)),
      ),
      Align(
        alignment: Alignment(0, 0.66),
        child: Text('🌑', style: TextStyle(fontSize: 21)),
      ),
    ],
  );
}

/// One floating combat number's data (see _BattleScreenState._floats). Pure
/// data — the animation lives in [_FloatingNumber].
class _FloatText {
  final int id;
  final String text;
  final Color color;
  final double scale;
  final bool onEnemy; // struck side: enemy = up top, player = below

  /// Which SLOT it was struck in, as a −1..1 alignment across the half (user
  /// 2026-07-27). It used to be a per-id jitter, which was fine when a side had
  /// one monster and only had to keep simultaneous numbers from stacking; with
  /// three standing there the number has to land over the one that was hit.
  final double alignX;
  final String? tag; // "Super effective!" / "Resisted" / null
  const _FloatText({
    required this.id,
    required this.text,
    required this.color,
    required this.scale,
    required this.onEnemy,
    required this.alignX,
    this.tag,
  });
}

/// Animates a floating number: a quick pop-in, then a drift upward while it
/// fades. Calls [onDone] once finished so the screen can drop it from the list.
class _FloatingNumber extends StatefulWidget {
  final _FloatText data;
  final VoidCallback onDone;
  const _FloatingNumber({super.key, required this.data, required this.onDone});

  @override
  State<_FloatingNumber> createState() => _FloatingNumberState();
}

class _FloatingNumberState extends State<_FloatingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        // Pop in over the first 18%, rise ~34px over the whole life, fade out
        // over the last 30%.
        final pop = t < 0.18 ? Curves.easeOutBack.transform(t / 0.18) : 1.0;
        final rise = -34.0 * Curves.easeOut.transform(t);
        final opacity =
            t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, rise),
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: d.scale * pop,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.text,
                    style: FoE.title(size: 20).copyWith(
                      color: d.color,
                      fontWeight: FontWeight.w900,
                      shadows: const [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 0,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  if (d.tag != null)
                    Text(
                      d.tag!,
                      style: FoE.label(size: 10).copyWith(
                        color: d.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
