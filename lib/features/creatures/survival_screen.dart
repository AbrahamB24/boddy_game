import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/recess_bar.dart';
import '../social/widgets/social_kit.dart';
import '../settlement/bag_screen.dart' show openBag;
import '../settlement/settlement_controller.dart';
import 'battle_prep_screen.dart';
import 'battle_screen.dart';
import 'models/creature_instance.dart';
import 'services/combat_engine.dart' show CombatOutcome;
import 'services/overworld_path.dart' show kMaxPartySize;
import 'services/survival_run.dart';
import 'widgets/creature_family.dart' show CreatureAvatar;
import '../../core/ui/game_text.dart';

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
          confirmLabel: 'Start run',
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
    final prevBest = SettlementController().survivalBestFloor;
    final gold = goldRewardForFloors(cleared, previousBest: prevBest);
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
  Widget build(BuildContext context) => MenuScaffold(
    title: 'Survival',
    trailing: Text(
      'Floor $_floor · best ${SettlementController().survivalBestFloor}',
      style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
    ),
    child: switch (_phase) {
      _Phase.loading => const SizedBox.shrink(),
      _Phase.betweenFloors => _betweenFloorsView(),
      _Phase.over => _resultsView(),
    },
  );

  /// Between two floors (user 2026-09-20, laid out like the other duel pages): the
  /// team's health on the left as two columns of rows — a K.O. faded — and on the
  /// right what you can do: open the Bag (items ARE allowed between floors),
  /// go on, or retreat and bank what the run has earned.
  Widget _betweenFloorsView() {
    final next = _floor + 1;
    // The team's health and the decision panel ARE different Gebiete (user
    // 2026-09-29, "Trennlinien und Zonen gemischt", app-wide), so the
    // decision side gets a [zoneBox] of its own. (MenuScaffold is the one
    // card now — no [pageCard] here.)
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isSurvivalBossFloor(_floor)
                        ? '👑 Floor $_floor cleared — a boss fell!'
                        : 'Floor $_floor cleared',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: CreamPalette.better,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [for (final c in _team) _memberRow(c)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 282,
            child: zoneBox(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'FLOOR $next NEXT',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.9,
                      color: kBoxAccent,
                    ),
                  ),
                  if (isSurvivalBossFloor(next))
                    Text(
                      'The next floor holds a boss.',
                      textAlign: TextAlign.center,
                      style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                    ),
                  const SizedBox(height: 12),
                  SocialTileButton(
                    'Bag',
                    icon: Icons.backpack,
                    height: 38,
                    onTap: _openBag,
                  ),
                  const SizedBox(height: 10),
                  SocialGoldButton(
                    'Continue → Floor $next',
                    height: 44,
                    fontSize: 14,
                    onTap: _continueRun,
                  ),
                  const SizedBox(height: 10),
                  Pressable(
                    behavior: HitTestBehavior.opaque,
                    onTap: _endRun,
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      decoration: raisedTile(radius: 11),
                      child: const Text(
                        'Retreat & bank rewards',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: CreamPalette.warn,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One member of the team: portrait, name, HP bar and figure.
  Widget _memberRow(CreatureInstance c) {
    final frac = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    return Opacity(
      opacity: c.isKo ? 0.55 : 1,
      child: Container(
        width: 250,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: raisedTile(radius: 12),
        child: Row(
          children: [
            CreatureAvatar.of(c, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                c.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: kBoxInk,
                ),
              ),
            ),
            SizedBox(
              width: 70,
              child: RecessBar(
                value: frac,
                color: frac < 0.3 ? CreamPalette.warn : CreamPalette.better,
                height: 8,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              child: Text(
                c.isKo ? 'K.O.' : '${c.hp}/${c.maxHp}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: c.isKo ? CreamPalette.warn : kBoxInkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsView() => Center(
    child: SizedBox(
      width: 380,
      // A zone, not a card of its own (user 2026-09-29, "diese Kasten gibt
      // es nicht mehr") — MenuScaffold is already the one card on screen;
      // stacking another cream card inside it would just be the same
      // boxes-within-boxes look one level down.
      child: zoneBox(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _resultFloors > 0 ? 'Run over' : 'No floor cleared',
              style: FoE.title(size: 18).copyWith(color: kBoxInk),
            ),
            const SizedBox(height: 12),
            Text(
              'Floors cleared: $_resultFloors',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: kBoxInk,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '🪙 +${_resultGold.toStringAsFixed(0)} gold',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: CreamPalette.goldInk,
              ),
            ),
            if (_isNewBest) ...[
              const SizedBox(height: 8),
              const Text(
                '🏆 New best run!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: CreamPalette.better,
                ),
              ),
            ],
            const SizedBox(height: 18),
            SocialGoldButton(
              'Back to Overworld',
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 36),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}
