import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_kit.dart';
import '../settlement/widgets/scroll_paper.dart'
    show kParchmentLight, kParchmentMid;
import '../onboarding/intro_flow.dart';
import '../settlement/settlement_controller.dart';
import 'battle_screen.dart';
import 'collection_screen.dart';
import 'models/combatant.dart';
import 'models/creature_instance.dart';
import 'models/area.dart' show kAreaDefs;
import 'models/expedition.dart';
import 'models/species_def.dart';
import 'services/capture_math.dart';
import 'services/combat_engine.dart';
import 'services/expedition_controller.dart';
import 'services/creatures_controller.dart';

// The catch moment (user design, 2026-07-15; QTE moved INTO the battle
// 2026-07-18): fight the found monster down into its catchable band — the rarer
// it is, the lower it must go (catchHpThreshold), and killing it forfeits the
// catch. Once it's in the band the battle's Catch button lights up; pressing it
// plays the ring QTE right there in the fight. A caught wild pops back here as a
// [CatchSuccess]; a MISS just spends that turn and the fight goes on.
//
// A longer hunt brings back SEVERAL finds (kCaptureHuntOptions) — they're
// played back to back, each its own battle. Progress is checkpointed after
// every find (ExpeditionController.advanceCaptureFind), so leaving and
// reopening resumes at the next unplayed find and can never double-credit.
// Fleeing a battle skips only that find; a wiped group forfeits the rest.
class CaptureEncounterScreen extends StatefulWidget {
  final Expedition expedition;
  const CaptureEncounterScreen({super.key, required this.expedition});

  @override
  State<CaptureEncounterScreen> createState() => _CaptureEncounterScreenState();
}

enum _Phase { intro, done }

class _CaptureEncounterScreenState extends State<CaptureEncounterScreen> {
  // The hunt's rolled finds and which one is up next (resumes from the
  // persisted checkpoint).
  late final List<String> _findIds;
  late int _findIndex;
  late final int _level;

  // Per-find state — reset by _prepareFind().
  SpeciesDef? _species;
  Combatant? _wild;
  // A caught wild that had nowhere to go (housing full) — held so the player can
  // free a slot in the Monsters screen and come back to keep it, instead of
  // losing it (user 2026-07-17). Null once committed or when there was room.
  Combatant? _pendingWild;
  _Phase _phase = _Phase.intro;
  bool _caught = false;
  bool _finishing = false;
  // Set once finishCaptureTrip ran (last find played or hunt forfeited) —
  // flips the done button from "Next find" to "Head home".
  bool _tripFinished = false;
  // Overrides the done-overlay line when the battle decided the outcome —
  // defeated wild, wiped group, fled.
  String? _doneText;

  @override
  void initState() {
    super.initState();
    final e = widget.expedition;
    _findIds = e.captureFindSpeciesIds;
    _findIndex = _findIds.isEmpty
        ? 0
        : e.captureFindsDone.clamp(0, _findIds.length - 1);
    _level = (e.payload['level'] as num?)?.toInt() ?? 1;
    _prepareFind();
  }

  /// Loads find [_findIndex] and resets all per-find state.
  void _prepareFind() {
    _species = _findIds.isEmpty ? null : kSpeciesDefs[_findIds[_findIndex]];
    _caught = false;
    _finishing = false;
    _doneText = null;
    _pendingWild = null;
    final species = _species;
    if (species != null) {
      // Jumpstart: the intro's first battle is fought by a lone starter, so the
      // wild is weakened while the chain runs. The inline QTE is NOT eased — but
      // a missed tap during the tutorial restarts the ring instead of ending the
      // find (BattleScreen.guaranteedCatch), so the catch stays a skill check
      // the player simply cannot fail out of.
      _wild = Combatant.fromSpecies(
        species,
        level: _level,
        id: 'wild',
        statScale: SettlementController().jumpstartActive
            ? kJumpstartEnemyStatMult
            : kCaptureWildStatMult,
      )
        // Tutorial promise: "it cannot faint" — overkill (which normally
        // forfeits the find) is impossible, the wild floors at 1 HP.
        ..cannotBeKoed = _introRun;
    } else {
      _wild = null;
    }
  }

  /// True while the guided tutorial owns this hunt: the catch is guaranteed
  /// (HP-floored wild, endlessly retried QTE).
  bool get _introRun => SettlementController().introStep.isActive;

  bool get _isLastFind => _findIndex + 1 >= _findIds.length;

  /// The battle phase: fight the wild down into its catchable band, then use the
  /// in-battle Catch button. A successful catch pops [CatchSuccess]; killing it
  /// or withdrawing loses just this find; a wiped group forfeits the rest.
  Future<void> _startBattle() async {
    final species = _species;
    final wild = _wild;
    if (species == null || wild == null) return;
    final creatures = CreaturesController();
    final team = widget.expedition.memberIds
        .map(creatures.byId)
        .whereType<CreatureInstance>()
        .where((c) => !c.isKo)
        .toList();
    if (team.isEmpty) {
      await _forfeitRest('No conscious group member — the hunt is over.');
      return;
    }

    final result = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: team,
          enemies: [wild],
          title: 'Wild ${species.name}',
          catchThresholdFraction: catchHpThreshold(species.rarity),
          guaranteedCatch: _introRun,
          // A hunt is fought in the region it was sent to, so the battlefield
          // looks like that region (user 2026-07-31).
          area: kAreaDefs[widget.expedition.areaId],
        ),
      ),
    );
    if (!mounted) return;

    // Caught it in the fight — record it.
    if (result is CatchSuccess) {
      await _endFind(caught: true);
      return;
    }
    if (result == CombatOutcome.defeat) {
      await _forfeitRest('Your group was defeated — the hunt is over.');
      return;
    }
    final note = result == CombatOutcome.victory
        ? '${species.name} was defeated — nothing left to catch.'
        : '${species.name} escaped as you withdrew.';
    await _endFind(caught: false, note: note);
  }

  /// Resolves the CURRENT find (caught or lost), checkpoints it, and — after
  /// the last find — closes the whole trip (casualties, member release).
  Future<void> _endFind({required bool caught, String? note}) async {
    if (_finishing) return;
    _finishing = true;
    final ctrl = ExpeditionController();
    final wild = _wild;
    if (caught && wild != null) {
      if (CreaturesController().housingFull) {
        // No room — hold the catch; the done overlay lets the player free a
        // slot and come back to keep it (see _goReleaseAndReturn).
        _pendingWild = wild;
      } else {
        await ctrl.recordCatch(wild);
      }
    } else if (note != null) {
      ctrl.logResult(note);
    } else if (wild != null) {
      ctrl.logResult('${wild.name} slipped away!');
    }
    await ctrl.advanceCaptureFind(widget.expedition);
    if (_isLastFind) {
      await ctrl.finishCaptureTrip(widget.expedition);
      _tripFinished = true;
    }
    if (mounted) {
      setState(() {
        _caught = caught;
        _doneText = note;
        _phase = _Phase.done;
      });
    }
  }

  /// Ends the WHOLE hunt early (wiped/unconscious group): remaining finds are
  /// forfeited without being played.
  Future<void> _forfeitRest(String note) async {
    if (_finishing) return;
    _finishing = true;
    await ExpeditionController().finishCaptureTrip(
      widget.expedition,
      note: note,
    );
    _tripFinished = true;
    if (mounted) {
      setState(() {
        _caught = false;
        _doneText = note;
        _phase = _Phase.done;
      });
    }
  }

  /// The catch had no room: open the Monsters screen so the player can release
  /// one or more, then — back here — commit the held catch if a slot is now free.
  Future<void> _goReleaseAndReturn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CollectionScreen()),
    );
    if (!mounted) return;
    final wild = _pendingWild;
    if (wild != null && !CreaturesController().housingFull) {
      await ExpeditionController().recordCatch(wild);
      if (mounted) setState(() => _pendingWild = null);
    } else {
      // Still full (nothing released) — keep the prompt.
      setState(() {});
    }
  }

  /// Moves on to the next unplayed find (done overlay's "Next find" button).
  void _nextFind() {
    setState(() {
      _findIndex += 1;
      _prepareFind();
      _phase = _Phase.intro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final species = _species;
    return Scaffold(
      // The same sheet as everything else (user 2026-07-27) — the encounter is
      // a page you are taken to, not a place of its own.
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
        child: species == null || _wild == null
            ? _goneView()
            : Column(
                children: [
                  const SizedBox(height: 18),
                  Text('A wild encounter!', style: FoE.title(size: 16)),
                  if (_findIds.length > 1)
                    Text(
                      'Find ${_findIndex + 1} / ${_findIds.length}',
                      style: FoE.dim(size: 11),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '${species.name} · Lv $_level',
                    style: FoE.label(size: 13)
                        .copyWith(color: species.rarity.color),
                  ),
                  Text(species.rarity.label,
                      style: FoE.dim(size: 11)
                          .copyWith(color: species.rarity.color)),
                  Expanded(child: Center(child: _sprite(species))),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _footer(species),
                  ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _sprite(SpeciesDef species) => SizedBox(
    width: 180,
    height: 180,
    child: species.stageAt(0).imageUrl == null
        ? const Icon(Icons.pets, color: kAccent, size: 80)
        : Image.network(
            species.stageAt(0).imageUrl!,
            filterQuality: FilterQuality.none,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.pets, color: kAccent, size: 80),
          ),
  );

  Widget _footer(SpeciesDef species) {
    switch (_phase) {
      case _Phase.intro:
        final pct = (catchHpThreshold(species.rarity) * 100).round();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fight it down to ≤$pct% HP — without killing it! — to light up '
              'the Catch button. The lower its HP, the BIGGER the golden ring. '
              'Then tap Catch and hit the ring: '
              '${qteHitsRequired(species.rarity) == 1 ? 'one clean hit and it\'s yours' : '${qteHitsRequired(species.rarity)} perfect hits in a row'} — a miss just spends that turn.',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 12),
            ),
            const SizedBox(height: 12),
            _bigBtn('⚔️ Face it!', _startBattle),
          ],
        );
      case _Phase.done:
        // Caught but no room to house it — offer to free a slot and keep it.
        if (_pendingWild != null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '🎉 ${species.name} was caught!',
                textAlign: TextAlign.center,
                style: FoE.title(size: 15).copyWith(color: kParchmentGo),
              ),
              const SizedBox(height: 8),
              Text(
                '🏠 But your settlement is full. Release a monster to make '
                'room and keep it — otherwise it stays behind.',
                textAlign: TextAlign.center,
                style: FoE.dim(size: 12).copyWith(color: kAccent),
              ),
              const SizedBox(height: 12),
              _bigBtn('🐾 Free a slot (Monsters)', _goReleaseAndReturn),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _tripFinished
                    ? () => Navigator.of(context).pop()
                    : _nextFind,
                child: Text(
                  _tripFinished
                      ? 'Leave it behind · Head home'
                      : 'Leave it behind · Next find',
                  style: FoE.dim(size: 12).copyWith(color: kInkFaint),
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _caught
                  ? '🎉 ${species.name} was caught!'
                  : _doneText ?? '💨 ${species.name} escaped!',
              textAlign: TextAlign.center,
              style: FoE.title(size: 15).copyWith(
                color: _caught ? kParchmentGo : const Color(0xFF9B3B22),
              ),
            ),
            const SizedBox(height: 12),
            _tripFinished
                ? _bigBtn('Head home', () => Navigator.of(context).pop())
                : _bigBtn(
                    '➡️ Next find (${_findIndex + 2}/${_findIds.length})',
                    _nextFind,
                  ),
          ],
        );
    }
  }

  /// Shown when the CURRENT find's species no longer exists (def removed) —
  /// skips just that find; the rest of the hunt goes on.
  Widget _goneView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('The trail went cold…', style: FoE.title(size: 15)),
          const SizedBox(height: 8),
          Text(
            'Whatever left these tracks is gone (species removed).',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12),
          ),
          const SizedBox(height: 14),
          _bigBtn(_isLastFind ? 'Head home' : '➡️ Next find', () async {
            final ctrl = ExpeditionController();
            ctrl.logResult('A trail went cold — nothing there.');
            await ctrl.advanceCaptureFind(widget.expedition);
            if (_isLastFind) {
              await ctrl.finishCaptureTrip(widget.expedition);
              if (mounted) Navigator.of(context).pop();
            } else {
              _nextFind();
            }
          }),
        ],
      ),
    ),
  );

  Widget _bigBtn(String label, VoidCallback onTap) =>
      ParchmentButton(label: label, primary: true, onTap: onTap);
}
