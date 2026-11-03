import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../onboarding/intro_flow.dart';
import '../settlement/settlement_controller.dart';
import '../social/widgets/social_kit.dart';
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
import 'widgets/creature_card.dart';
import 'widgets/versus_kit.dart';
import 'widgets/wild_preview.dart';
import '../../core/theme/voxel_kit.dart' show vr;

// The catch moment (user design, 2026-07-15; QTE moved INTO the battle
// 2026-07-18; hunts rebuilt as ONE continuous multi-wild battle 2026-09-11;
// the QTE itself replaced by the Balkenjagd bar-chase 2026-10-01): fight the
// wilds down into their catchable band — the rarer one is, the lower it
// must go (catchHpThreshold), and killing one forfeits ITS catch, not the
// fight. Once a wild is in the band the battle's Catch button lights up for
// it; pressing it pushes CaptureBarScreen (a separate full-screen momentum
// minigame, not an in-place overlay any more) and, caught or not, the fight
// goes on (see BattleScreen._catchSucceed/_catchMiss).
//
// A longer hunt still brings back SEVERAL finds (kCaptureHuntOptions) — but
// they're now ALL fielded together in one battle (CombatEngine's own
// field-of-3-plus-bench, the same mechanic dungeon/Survival/Training battles
// already use), not played one at a time. That's what fixed the problem a
// solo hunter used to have on a long hunt: N sequential fights with no HP
// reset between them meant it would get KO'd partway through and forfeit
// every find after that (user: "Das schaffe ich wohl mit nur einem Monster
// nicht"). The whole battle is one atomic unit — no per-find checkpoint any
// more, same as any other fight in the game already has no mid-battle save.
class CaptureEncounterScreen extends StatefulWidget {
  final Expedition expedition;
  const CaptureEncounterScreen({super.key, required this.expedition});

  @override
  State<CaptureEncounterScreen> createState() => _CaptureEncounterScreenState();
}

enum _Phase { intro, done }

class _CaptureEncounterScreenState extends State<CaptureEncounterScreen> {
  late final int _level;

  /// Every find that still resolves to a real species, built once. A find
  /// whose species def was since removed is simply left out — with several
  /// wilds fielded at once there's no single "current find" left to show a
  /// dedicated "trail went cold" screen for; it just quietly isn't there.
  late final List<Combatant> _wilds;

  _Phase _phase = _Phase.intro;
  bool _finishing = false;

  // Set once the one continuous battle has resolved.
  int _caughtCount = 0;
  int _defeatedCount = 0;
  int _lostCount = 0; // forfeited: fled, or a wipe left some unfought
  List<Combatant> _pendingWilds = []; // caught, but no room to house (yet)
  String? _doneNote; // overrides the summary line (wipe/cold trail)

  @override
  void initState() {
    super.initState();
    final e = widget.expedition;
    _level = (e.payload['level'] as num?)?.toInt() ?? 1;
    final wilds = <Combatant>[];
    final ids = e.captureFindSpeciesIds;
    for (var i = 0; i < ids.length; i++) {
      final species = kSpeciesDefs[ids[i]];
      if (species == null) continue;
      wilds.add(
        Combatant.fromSpecies(
            species,
            level: _level,
            id: 'wild$i',
            // Jumpstart: the intro's first battle is fought by a lone starter,
            // so every wild is weakened while the chain runs. The inline QTE
            // is NOT eased — but a missed tap during the tutorial restarts the
            // ring instead of burning the attempt (BattleScreen.guaranteedCatch),
            // so the catch stays a skill check the player cannot fail out of.
            statScale: SettlementController().jumpstartActive
                ? kJumpstartEnemyStatMult
                : kCaptureWildStatMult,
          )
          // Tutorial promise: "it cannot faint" — overkill (which normally
          // forfeits that wild's own catch) is impossible, it floors at 1 HP.
          ..cannotBeKoed = _introRun,
      );
    }
    _wilds = wilds;
    if (_wilds.isEmpty) {
      ExpeditionController().logResult('A trail went cold — nothing there.');
      _forfeitRest(null, immediate: true);
    }
  }

  /// True while the guided tutorial owns this hunt: the catch is guaranteed
  /// (HP-floored wilds, endlessly retried QTE).
  bool get _introRun => SettlementController().introStep.isActive;

  /// The one continuous battle: every fielded/benched wild fought and caught
  /// or defeated freely until none are left, the team wipes, or the player
  /// flees.
  Future<void> _startBattle() async {
    if (_wilds.isEmpty) return;
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
          enemies: _wilds,
          title: _wilds.length > 1 ? 'Wild hunt' : 'Wild encounter',
          isCapture: true,
          guaranteedCatch: _introRun,
          // A hunt is fought in the region it was sent to, so the battlefield
          // looks like that region (user 2026-07-31).
          area: kAreaDefs[widget.expedition.areaId],
        ),
      ),
    );
    if (!mounted) return;

    if (result is HuntBattleResult) {
      await _finishHunt(result);
      return;
    }
    if (result == CombatOutcome.defeat) {
      await _forfeitRest('Your group was defeated — the hunt is over.');
      return;
    }
    // Fled before the fight otherwise resolved — nothing was caught or
    // defeated.
    await _finishHunt(const HuntBattleResult(CombatOutcome.fled, [], 0));
  }

  /// Resolves the whole hunt from the battle's own result: houses every
  /// catch (any that don't fit come back as [_pendingWilds]), logs one
  /// summary line, and ends the trip — all in one shot, since the battle
  /// itself was one atomic unit.
  Future<void> _finishHunt(HuntBattleResult result) async {
    if (_finishing) return;
    _finishing = true;
    final resolved = result.caught.length + result.defeatedCount;
    final lost = _wilds.length - resolved;
    if (lost > 0) {
      ExpeditionController().logResult(
        '$lost find${lost > 1 ? 's' : ''} left unplayed — '
        '${result.outcome == CombatOutcome.fled ? 'you withdrew.' : 'the hunt ended early.'}',
      );
    }
    final pending = await ExpeditionController().resolveCaptureTrip(
      widget.expedition,
      caught: result.caught,
      defeatedCount: result.defeatedCount,
    );
    if (mounted) {
      setState(() {
        _caughtCount = result.caught.length;
        _defeatedCount = result.defeatedCount;
        _lostCount = lost;
        _pendingWilds = pending;
        _phase = _Phase.done;
      });
    }
  }

  /// Ends the WHOLE hunt early (wiped/unconscious group, or nothing to hunt
  /// at all): every find is forfeited without being played.
  Future<void> _forfeitRest(String? note, {bool immediate = false}) async {
    if (_finishing) return;
    _finishing = true;
    await ExpeditionController().finishCaptureTrip(
      widget.expedition,
      note: note,
    );
    _lostCount = _wilds.length;
    _doneNote = note;
    if (immediate) return; // called from initState — build() runs fresh
    if (mounted) setState(() => _phase = _Phase.done);
  }

  /// The catch(es) had no room: open the Monsters screen so the player can
  /// release one or more, then — back here — claim whichever pending wilds
  /// now fit. Several can be pending at once (2026-09-11 — a continuous
  /// battle can catch more than housing has room for in one go), so this
  /// retries all of them, not just one.
  Future<void> _goReleaseAndReturn() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CollectionScreen()));
    if (!mounted) return;
    final ctrl = ExpeditionController();
    final stillPending = <Combatant>[];
    for (final wild in _pendingWilds) {
      final kept = CreaturesController().housingFull
          ? null
          : await ctrl.claimPendingWild(wild);
      if (kept == null) stillPending.add(wild);
    }
    if (mounted) setState(() => _pendingWilds = stillPending);
  }

  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: 'Encounter',
    child: _wilds.isEmpty ? _goneView() : _body(),
  );

  /// The encounter, laid out like the other duel pages: what you found as a
  /// FAN of monster cards — a tap on one shows it in full — then what to do
  /// about it, or how it went. No card of its own any more (user 2026-09-30,
  /// "hier und andernorts sind noch die alten Kästchen vorhanden") —
  /// MenuScaffold is already the one card on screen.
  Widget _body() => Padding(
    padding: const EdgeInsets.fromLTRB(6, 2, 6, 10),
    child: Column(
      children: [
        Text(
          _wilds.length == 1 ? 'A wild encounter!' : 'A wild hunt!',
          style: FoE.title(size: 17).copyWith(color: kBoxInk),
        ),
        Text(
          _wilds.length == 1
              ? '1 find, Lv $_level'
              : '${_wilds.length} finds, Lv $_level',
          style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
        ),
        Expanded(child: Center(child: _finds())),
        Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _footer(),
          ),
        ),
      ],
    ),
  );

  Widget _finds() {
    final shown = _wilds.take(6).toList();
    final more = _wilds.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VersusFan(
          cards: [for (final w in shown) _card(w)],
          tileW: shown.length <= 4 ? 78 : 66,
          tileH: shown.length <= 4 ? 130 : 110,
        ),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              '+$more more',
              style: FoE.dim(size: 13).copyWith(color: kBoxInkSoft),
            ),
          ),
      ],
    );
  }

  /// One find: its monster card, with a NEW flag when no monster of that species
  /// is owned yet.
  Widget _card(Combatant c) {
    final isNew =
        c.speciesId != null &&
        !CreaturesController().creatures.any(
          (owned) => owned.speciesId == c.speciesId,
        );
    final card = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CreatureCard(
            creature: enemyInstanceOf(c),
            showHp: false,
            onTap: _phase == _Phase.intro
                ? () => openWildPreview(context, c)
                : null,
          ),
        ),
        if (isNew)
          Positioned(
            top: 2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: CreamPalette.gold,
                borderRadius: vr(6),
                border: Border.all(color: CreamPalette.goldDeep),
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: kBoxInk,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
      ],
    );
    return card;
  }

  Widget _footer() {
    switch (_phase) {
      case _Phase.intro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fight a wild down into its catchable band — without killing '
              'it! — to light up Catch for it. Throwing a cage opens its '
              'own screen: hold your catch bar over the wild to build your '
              'chance, then throw. A miss just spends AP and the cage, and '
              'the fight goes on, same as attacking. Catch what you want, '
              'fight the rest down for XP.',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
            ),
            const SizedBox(height: 10),
            _bigBtn('⚔️ Face them!', _startBattle),
          ],
        );
      case _Phase.done:
        if (_pendingWilds.isNotEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _summaryLine(),
              const SizedBox(height: 6),
              Text(
                '🏠 ${_pendingWilds.length} caught, but your settlement is '
                'full. Release monsters to make room and keep '
                '${_pendingWilds.length > 1 ? 'them' : 'it'} — otherwise '
                '${_pendingWilds.length > 1 ? 'they stay' : 'it stays'} '
                'behind.',
                textAlign: TextAlign.center,
                style: FoE.dim(size: 11.5).copyWith(color: CreamPalette.warn),
              ),
              const SizedBox(height: 10),
              _bigBtn('🐾 Free a slot (Monsters)', _goReleaseAndReturn),
              const SizedBox(height: 6),
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Text(
                  'Leave ${_pendingWilds.length > 1 ? 'them' : 'it'} behind '
                  '· Head home',
                  style: FoE.dim(size: 12).copyWith(color: kBoxInkFaint),
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryLine(),
            const SizedBox(height: 10),
            _bigBtn('Head home', () => Navigator.of(context).pop()),
          ],
        );
    }
  }

  Widget _summaryLine() {
    if (_doneNote != null) {
      return Text(
        _doneNote!,
        textAlign: TextAlign.center,
        style: FoE.title(size: 15).copyWith(color: CreamPalette.warn),
      );
    }
    final parts = <String>[
      if (_caughtCount > 0) '🎉 $_caughtCount caught',
      if (_defeatedCount > 0) '⚔️ $_defeatedCount defeated for XP',
      if (_lostCount > 0) '💨 $_lostCount lost',
    ];
    return Text(
      parts.isEmpty ? 'Nothing came of it.' : parts.join('  ·  '),
      textAlign: TextAlign.center,
      style: FoE.title(
        size: 15,
      ).copyWith(color: _caughtCount > 0 ? CreamPalette.better : kBoxInk),
    );
  }

  Widget _goneView() => Center(
    child: SizedBox(
      width: 380,
      // A zone, not a card of its own — MenuScaffold is already the one
      // card on screen.
      child: zoneBox(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The trail went cold…',
              style: FoE.title(size: 15).copyWith(color: kBoxInk),
            ),
            const SizedBox(height: 8),
            Text(
              'Whatever left these tracks is gone (species removed).',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            ),
            const SizedBox(height: 14),
            _bigBtn('Head home', () => Navigator.of(context).pop()),
          ],
        ),
      ),
    ),
  );

  Widget _bigBtn(String label, VoidCallback onTap) => SocialGoldButton(
    label,
    height: 40,
    fontSize: 14,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    onTap: onTap,
  );
}
