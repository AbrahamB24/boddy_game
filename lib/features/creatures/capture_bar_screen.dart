import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart' show Ticker;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../social/widgets/social_kit.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'services/capture_math.dart';
import 'widgets/creature_family.dart' show CreatureFigure;
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';

/// The Balkenjagd catch screen (user 2026-10-01, replacing the old inline
/// ring QTE; bait selection split OUT into its own step 2026-10-02, then
/// moved from a bottom sheet into the command deck itself 2026-10-04 — see
/// BattleScreen._baitPage): pushed from BattleScreen._chooseBait, AFTER the
/// player has already chosen and spent a bait there. Four independent
/// levers decide the difficulty (see capture_math.dart's own "Balkenjagd"
/// section); [itemStart] (that bait's own magnitude) only sets the STARTING
/// percentage, never the difficulty — so this screen always plays straight
/// through to a result, with nothing left to pick or back out of.
///
/// Pops `true` on a successful final roll, `false` on a miss — the wild
/// stays in the fight either way (see CombatEngine.attemptCatch's own doc
/// on why a miss no longer forfeits it).
class CaptureBarScreen extends StatefulWidget {
  final Combatant wild;
  final Combatant catcher;
  final math.Random rng;
  final bool deterministicCombat;

  /// The already-chosen bait's starting fraction (0..1) — see
  /// BattleScreen._chooseBait.
  final double itemStart;

  /// Tutorial: the final roll always succeeds.
  final bool guaranteedCatch;

  const CaptureBarScreen({
    super.key,
    required this.wild,
    required this.catcher,
    required this.rng,
    required this.deterministicCombat,
    required this.itemStart,
    this.guaranteedCatch = false,
  });

  @override
  State<CaptureBarScreen> createState() => _CaptureBarScreenState();
}

enum _Phase { ready, running, rolling, done }

class _CaptureBarScreenState extends State<CaptureBarScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  _Phase _phase = _Phase.ready;

  // Kinematics — everything is a fraction (0..1) of the track's width.
  double _targetPos = 0.5;
  double _targetDir = 1;
  double _barPos = 0.5;
  double _barVel = 0;
  late final double _halfW;
  late final double _speed;
  late final double _turnProb;
  late final int _durationMs;

  double _skillPoints = 0; // 0..kBarSkillMax
  Duration _elapsed = Duration.zero;
  Duration? _lastTick;
  bool? _caught;

  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    final rarity = widget.wild.rarity;
    final hpFraction = widget.wild.maxHp <= 0
        ? 0.0
        : widget.wild.hp / widget.wild.maxHp;
    _speed = barWildSpeed(rarity, hpFraction);
    _turnProb = barTurnProb(rarity);
    _durationMs = barDurationMs(rarity);
    _halfW = barWidthFraction(widget.catcher.stat(CreatureStat.catchRate)) / 2;
    _targetPos = 0.3 + widget.rng.nextDouble() * 0.4;
    _targetDir = widget.rng.nextBool() ? 1 : -1;
    // Not started yet — see [_startRound]. The scene sits still until the
    // player taps Ready (user 2026-10-04: "es braucht noch einen Ready
    // Button, bevor es startet").
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick ?? elapsed;
    var dt = (elapsed - last).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;
    if (dt > 0.1) dt = 0.1; // guard a stalled frame (e.g. app resumed)

    if (_phase == _Phase.running) {
      _targetPos += _targetDir * _speed * dt;
      if (_targetPos < 0.08) {
        _targetPos = 0.08;
        _targetDir = 1;
      }
      if (_targetPos > 0.92) {
        _targetPos = 0.92;
        _targetDir = -1;
      }
      if (widget.rng.nextDouble() < _turnProb * (dt * 60)) {
        _targetDir = -_targetDir;
      }

      _barVel *= math.pow(0.86, dt * 60).toDouble();
      _barPos += _barVel * dt;
      if (_barPos < _halfW) {
        _barPos = _halfW;
        _barVel = math.max(0, _barVel);
      }
      if (_barPos > 1 - _halfW) {
        _barPos = 1 - _halfW;
        _barVel = math.min(0, _barVel);
      }
    }

    if (_phase == _Phase.running) {
      final overlap = (_targetPos - _barPos).abs() <= _halfW;
      if (overlap) {
        final gain = barSkillGainPerSecond(_durationMs) * dt;
        _skillPoints = math.min(kBarSkillMax, _skillPoints + gain);
      }
      _elapsed += Duration(microseconds: (dt * 1e6).round());
      if (_elapsed.inMilliseconds >= _durationMs) {
        _finishRound();
        return;
      }
    }
    setState(() {});
  }

  /// Leaves [_Phase.ready] and starts the ticker — nothing moves or
  /// accumulates before this.
  void _startRound() {
    if (_phase != _Phase.ready) return;
    _lastTick = null;
    _ticker.start();
    setState(() => _phase = _Phase.running);
  }

  double get _percent => barCatchPercent(widget.itemStart, _skillPoints);

  void _impulse(double dir) {
    if (_phase != _Phase.running) return;
    const kick = 0.85, maxV = 1.55;
    _barVel = (_barVel + dir * kick).clamp(-maxV, maxV);
  }

  void _startHold(double dir) {
    _impulse(dir);
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(
      const Duration(milliseconds: 115),
      (_) => _impulse(dir),
    );
  }

  void _stopHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _finishRound() {
    final pct = _percent;
    setState(() => _phase = _Phase.rolling);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      final caught =
          widget.guaranteedCatch ||
          widget.deterministicCombat ||
          widget.rng.nextDouble() * 100 < pct;
      setState(() {
        _caught = caught;
        _phase = _Phase.done;
      });
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // The bait is already spent by the time this screen is pushed (see
    // BattleScreen._chooseBait) — there is nothing left to back out of.
    canPop: false,
    child: MenuScaffold(
      title: 'Catch Attempt',
      showClose: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
        // "Daumenhälften" layout (user pick no. 7, 2026-11-05): the left and
        // right slabs of the screen ARE the controls — hold anywhere on them
        // — and the percentage, track and Ready button sit in the middle.
        child: Row(
          children: [
            Expanded(flex: 2, child: _thumbZone('◀️', -1)),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  _wildHeader(),
                  const SizedBox(height: 4),
                  // The percentage sits ABOVE the catch bar (user 2026-10-04:
                  // "die Prozentzahl soll über dem Fangbalken gross stehen").
                  _percentReadout(),
                  const SizedBox(height: 10),
                  Expanded(child: _track()),
                  const SizedBox(height: 10),
                  _footer(),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _thumbZone('▶️', 1)),
          ],
        ),
      ),
    ),
  );

  Widget _wildHeader() => Text(
    '${widget.wild.name} · ${_rarityLabel(widget.wild.rarity)}',
    style: FoE.title(size: 15).copyWith(color: kBoxInk),
  );

  String _rarityLabel(CreatureRarity r) => switch (r) {
    CreatureRarity.common => 'Common',
    CreatureRarity.uncommon => 'Uncommon',
    CreatureRarity.rare => 'Rare',
    CreatureRarity.epic => 'Epic',
    CreatureRarity.legendary => 'Legendary',
  };

  Widget _track() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_phase == _Phase.ready || _phase == _Phase.running) _durationBar(),
      const SizedBox(height: 6),
      Expanded(
        child: zoneBox(
          padding: EdgeInsets.zero,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final h = c.maxHeight;
              const figure = 64.0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _barPos * w - _halfW * w,
                    top: 0,
                    bottom: 0,
                    width: _halfW * 2 * w,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CreamPalette.gold.withValues(alpha: 0.30),
                        border: Border.all(color: CreamPalette.goldDeep, width: 2),
                        borderRadius: vr(8),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (_targetPos * w - figure / 2).clamp(0, w - figure),
                    top: (h - figure) / 2,
                    width: figure,
                    height: figure,
                    child: CreatureFigure(
                      imageUrl: widget.wild.imageUrl,
                      element: widget.wild.element,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ],
  );

  Widget _durationBar() {
    final remain = (1 - _elapsed.inMilliseconds / _durationMs).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: vr(4),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: remain,
          backgroundColor: CreamPalette.tan.withValues(alpha: 0.25),
          color: remain < 0.25 ? CreamPalette.warn : CreamPalette.better,
        ),
      ),
    );
  }

  double _heldDir = 0; // which thumb slab is down (for the pressed look)

  /// A full-height timber slab that is the hold control for one direction.
  Widget _thumbZone(String arrow, double dir) {
    final down = _heldDir == dir;
    return Listener(
      onPointerDown: (_) {
        _heldDir = dir;
        _startHold(dir);
        setState(() {});
      },
      onPointerUp: (_) {
        _heldDir = 0;
        _stopHold();
        setState(() {});
      },
      onPointerCancel: (_) {
        _heldDir = 0;
        _stopHold();
        setState(() {});
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: dir < 0 ? Alignment.centerLeft : Alignment.centerRight,
            end: dir < 0 ? Alignment.centerRight : Alignment.centerLeft,
            colors: down
                ? const [Color(0xFFB0683A), Color(0xFF8C4A28)]
                : const [Color(0xFF6E3A1F), Color(0xFF8C4A28)],
          ),
          borderRadius: vr(12),
          border: Border.all(color: const Color(0xFF2A1409), width: 2),
        ),
        child: Text(
          arrow,
          style: FoE.title(size: 40).copyWith(color: const Color(0xFFF6E7C4)),
        ),
      ),
    );
  }

  Widget _percentReadout() {
    final pct = _percent;
    final color = Color.lerp(
      Color.lerp(CreamPalette.warn, CreamPalette.gold, (pct / 50).clamp(0.0, 1.0)),
      CreamPalette.better,
      ((pct - 50) / 50).clamp(0.0, 1.0),
    );
    // Forced to the FULL width (not just as wide as "38%" wants to be) —
    // a bare Column child only gets as much width as its widest child asks
    // for, and the text alone is narrow. This is what actually makes the
    // bar "breit genug" underneath it.
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${pct.round()}%',
            textAlign: TextAlign.center,
            style: FoE.title(size: 38).copyWith(color: color),
          ),
          const SizedBox(height: 6),
          // Tall enough to read as the headline meter it is (user
          // 2026-10-04: "der Balken soll breit/hoch genug sein") — this is
          // the ONLY progress indicator on screen now that it sits above
          // the track instead of a thin strip underneath it.
          ClipRRect(
            borderRadius: vr(10),
            child: SizedBox(
              height: 20,
              child: LinearProgressIndicator(
                value: pct / 100,
                backgroundColor: CreamPalette.tan.withValues(alpha: 0.2),
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    switch (_phase) {
      case _Phase.ready:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Get the catch bar in position, then start the clock.',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            ),
            const SizedBox(height: 10),
            SocialGoldButton('Ready!', height: 40, onTap: _startRound),
          ],
        );
      case _Phase.running:
        return Text(
          'Keep the catch bar over the wild.',
          style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
        );
      case _Phase.rolling:
        return Text(
          'Rolling …',
          style: FoE.title(size: 14).copyWith(color: kBoxInk),
        );
      case _Phase.done:
        final caught = _caught ?? false;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              caught ? '🎉 Caught!' : '💨 Got away.',
              style: FoE.title(
                size: 16,
              ).copyWith(color: caught ? CreamPalette.better : CreamPalette.warn),
            ),
            const SizedBox(height: 10),
            SocialGoldButton(
              'Done',
              height: 40,
              onTap: () => Navigator.of(context).pop(caught),
            ),
          ],
        );
    }
  }
}
