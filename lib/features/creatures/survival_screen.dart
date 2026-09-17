import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_kit.dart';
import '../settlement/bag_screen.dart' show openBag;
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/scroll_paper.dart'
    show kParchmentLight, kParchmentMid;
import 'battle_prep_screen.dart';
import 'battle_screen.dart';
import 'models/creature_instance.dart';
import 'services/combat_engine.dart' show CombatOutcome;
import 'services/overworld_path.dart' show kMaxPartySize;
import 'services/survival_run.dart';

// ── Survival Mode (user 2026-09-06) ─────────────────────────────────────────
// "ich hätte gerne den survival modus, aber mit 6 Monster" — pick a full
// party once, then fight floor after floor back to back (no trip home, Bag
// items ARE allowed between floors) until the whole team is wiped or you
// retreat. Rewards land only at the end, scaled by how far you got — see
// services/survival_run.dart for the floor-squad/reward math. Structural
// shape borrowed from capture_encounter_screen.dart (a counter, a small
// phase enum, the same screen doubling as its own results view once the
// run's over) since that is the closest existing "loop battles, then show a
// result" screen in the app.
Future<void> openSurvivalMode(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const SurvivalScreen()),
);

class SurvivalScreen extends StatefulWidget {
  const SurvivalScreen({super.key});

  @override
  State<SurvivalScreen> createState() => _SurvivalScreenState();
}

enum _Phase { loading, betweenFloors, over }

class _SurvivalScreenState extends State<SurvivalScreen> {
  _Phase _phase = _Phase.loading;

  List<CreatureInstance> _team = const [];
  int _floor = 1;
  int _floorsCleared = 0;

  // Set once the run ends — the results view reads these rather than
  // re-deriving from live state, so a defeat mid-battle (this screen is
  // covered by BattleScreen when it happens) still has something frozen to
  // show once control returns here.
  int _resultFloors = 0;
  double _resultGold = 0;
  bool _isNewBest = false;

  @override
  void initState() {
    super.initState();
    // Straight to team selection (user 2026-09-08: "dieser Screen kann
    // gelöscht werden, direkt zur Teamauswahl") — the old intro screen (mode
    // blurb, best-run line, a "Pick your team" button) added a tap for
    // nothing the player couldn't already read on the Overworld entry
    // point. Post-frame, not directly in initState, since pushing a route
    // needs a BuildContext already attached to the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginRun());
  }

  /// Team pick, once, at the start of a run — never again mid-run (that is
  /// the whole point: no trading members in and out between floors, only
  /// items and the normal in-battle reserve swap).
  Future<void> _beginRun() async {
    final team = await Navigator.push<List<CreatureInstance>>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePrepScreen(
          title: 'Survival Mode',
          enemies: buildFloorSquad(1),
          partySize: kMaxPartySize,
          rewards: const [],
          // "You face" previewed only floor 1's random squad — every later
          // floor rerolls its own, so it promised more than it told (user
          // 2026-09-08: "beim survival mode brauche ich 'you face' nicht").
          showEnemyPreview: false,
        ),
      ),
    );
    if (!mounted) return;
    if (team == null || team.isEmpty) {
      // Cancelled the team pick — nothing left for this screen to show
      // (there is no intro to fall back to any more), so leave the same way
      // backing out of any other picker would: straight back to the
      // Overworld.
      Navigator.of(context).pop();
      return;
    }
    _team = team;
    _floor = 1;
    _floorsCleared = 0;
    unawaited(_fightFloor());
  }

  Future<void> _fightFloor() async {
    final squad = buildFloorSquad(_floor);
    final outcome = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: _team,
          enemies: squad,
          title: isSurvivalBossFloor(_floor)
              ? 'Survival — Floor $_floor · Boss'
              : 'Survival — Floor $_floor',
        ),
      ),
    );
    if (!mounted) return;
    if (outcome == CombatOutcome.victory) {
      _floorsCleared = _floor;
      setState(() => _phase = _Phase.betweenFloors);
      return;
    }
    // Defeat or fled — the run is over at whatever was last CLEARED.
    await _endRun();
  }

  void _continueRun() {
    setState(() {
      _floor += 1;
      _phase = _Phase.loading; // transient — _fightFloor pushes over it at once
    });
    unawaited(_fightFloor());
  }

  Future<void> _openBag() async {
    await openBag(context);
    if (mounted) setState(() {}); // refresh the HP list below
  }

  Future<void> _endRun() async {
    final cleared = _floorsCleared;
    final gold = goldRewardForFloors(cleared);
    final prevBest = SettlementController().survivalBestFloor;
    await SettlementController().recordSurvivalRun(cleared);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.over;
      _resultFloors = cleared;
      _resultGold = gold;
      _isNewBest = cleared > prevBest && cleared > 0;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // Same sheet every other full-screen encounter stands on (user
    // 2026-07-27) — see capture_encounter_screen.dart's own doc comment.
    backgroundColor: kParchmentMid,
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kParchmentLight, kParchmentMid],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_phase) {
            // The team picker (BattlePrepScreen) is already covering this
            // screen by the time a frame with content would show — this is
            // only ever visible for an instant, if at all.
            _Phase.loading => const SizedBox.shrink(),
            _Phase.betweenFloors => _betweenFloorsView(),
            _Phase.over => _resultsView(),
          },
        ),
      ),
    ),
  );

  Widget _betweenFloorsView() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        isSurvivalBossFloor(_floor)
            ? '👑 Floor $_floor cleared — a boss fell!'
            : '✅ Floor $_floor cleared',
        style: FoE.title(size: 16).copyWith(color: kParchmentGo),
      ),
      const SizedBox(height: 14),
      ..._team.map(
        (c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                c.isKo ? '💀' : '❤️',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 6),
              Text(
                '${c.displayName}  ${c.hp}/${c.maxHp}',
                style: FoE.dim(size: 12).copyWith(
                  color: c.isKo ? kAccent : null,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      ParchmentButton(label: '🎒 Bag', onTap: _openBag),
      const SizedBox(height: 8),
      ParchmentButton(
        label: 'Continue → Floor ${_floor + 1}',
        primary: true,
        onTap: _continueRun,
      ),
      const SizedBox(height: 8),
      ParchmentButton(
        label: 'Retreat & bank rewards',
        danger: true,
        onTap: _endRun,
      ),
    ],
  );

  Widget _resultsView() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        _resultFloors > 0 ? '💀 Run over' : '💨 No floor cleared',
        style: FoE.title(size: 18),
      ),
      const SizedBox(height: 10),
      Text('Floors cleared: $_resultFloors', style: FoE.label(size: 14)),
      const SizedBox(height: 4),
      Text(
        '🪙 +${_resultGold.toStringAsFixed(0)} gold',
        style: FoE.label(size: 14).copyWith(color: FoE.gold),
      ),
      if (_isNewBest) ...[
        const SizedBox(height: 8),
        Text('🏆 New best run!', style: FoE.label(size: 13).copyWith(color: kParchmentGo)),
      ],
      const SizedBox(height: 20),
      ParchmentButton(
        label: 'Back to Overworld',
        primary: true,
        onTap: () => Navigator.of(context).pop(),
      ),
    ],
  );
}

