import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/app_back_button.dart';
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
import 'widgets/creature_sprite.dart' show decodeWidthFor;
import 'widgets/wild_preview.dart';
import '../../core/ui/pressable.dart';

// The catch moment (user design, 2026-07-15; QTE moved INTO the battle
// 2026-07-18; hunts rebuilt as ONE continuous multi-wild battle 2026-09-11):
// fight the wilds down into their catchable band — the rarer one is, the
// lower it must go (catchHpThreshold), and killing one forfeits ITS catch,
// not the fight. Once a wild is in the band the battle's Catch button lights
// up for it; pressing it plays the ring QTE right there and, hit or miss,
// the fight goes on (see BattleScreen._catchSucceed/_catchMiss).
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
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CollectionScreen()),
    );
    if (!mounted) return;
    final ctrl = ExpeditionController();
    final stillPending = <Combatant>[];
    for (final wild in _pendingWilds) {
      final kept =
          CreaturesController().housingFull ? null : await ctrl.claimPendingWild(wild);
      if (kept == null) stillPending.add(wild);
    }
    if (mounted) setState(() => _pendingWilds = stillPending);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
        // A back button was simply missing (user 2026-09-14) — nothing
        // stopped a player who wanted to leave the fight for later (the
        // hunt already landed; the encounter is deferrable, see the class
        // doc above) without going through it right now. Positioned over
        // everything rather than folded into [_body]'s own Column so it
        // reads the same regardless of phase, same as every other screen's
        // corner back arrow.
        child: Stack(
          children: [
            _wilds.isEmpty ? _goneView() : _body(),
            Positioned(
              top: 8,
              left: 8,
              child: AppBackButton(onTap: () => Navigator.of(context).pop()),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _body() => Column(
    children: [
      const SizedBox(height: 18),
      Text(
        _wilds.length == 1 ? 'A wild encounter!' : 'A wild hunt!',
        style: FoE.title(size: 16),
      ),
      const SizedBox(height: 4),
      Text(
        _wilds.length == 1
            ? '1 find, Lv $_level'
            : '${_wilds.length} finds, Lv $_level',
        style: FoE.dim(size: 11),
      ),
      Expanded(child: Center(child: _preview())),
      Padding(
        padding: const EdgeInsets.all(16),
        child: _footer(),
      ),
    ],
  );

  /// A row of small sprites standing in for "what this hunt has fielded" —
  /// there's no single "the" find any more once a hunt can bring back
  /// several at once (2026-09-11), so this replaces the old one big
  /// species portrait.
  Widget _preview() {
    final shown = _wilds.take(9).toList();
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final w in shown) _thumb(w),
        if (_wilds.length > shown.length)
          SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: Text(
                '+${_wilds.length - shown.length}',
                style: FoE.dim(size: 13),
              ),
            ),
          ),
      ],
    );
  }

  Widget _thumb(Combatant c) {
    final species = c.speciesId == null ? null : kSpeciesDefs[c.speciesId];
    final url = species?.stageAt(0).imageUrl;
    // Never caught before (user 2026-09-14) — same "discovered" test the
    // Bestiary and the detail screen's own preview badge use, shown right
    // here too so a new species stands out before you even open the
    // preview to check.
    final isNew =
        c.speciesId != null &&
        !CreaturesController().creatures.any(
          (owned) => owned.speciesId == c.speciesId,
        );
    final art = Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: url == null
              ? Icon(Icons.pets, color: species?.rarity.color ?? kAccent, size: 32)
              : Image.network(
                  url,
                  filterQuality: FilterQuality.none,
                  fit: BoxFit.contain,
                  cacheWidth: decodeWidthFor(context, 56),
                  errorBuilder: (_, _, _) =>
                      Icon(Icons.pets, color: species?.rarity.color, size: 32),
                ),
        ),
        if (isNew)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: ShapeDecoration(
                color: FoE.goldBright,
                shape: FoE.facet(radius: 5),
              ),
              child: Text(
                'NEW',
                style: FoE.dim(size: 7).copyWith(
                  color: kInk,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
      ],
    );
    // Tap to preview THIS find's own stats before deciding whether it's
    // worth fighting for (user 2026-09-14: "ich will den Monsterdetailscreen
    // über den Catchmodus öffnen können für genau dieses noch nicht
    // gefangene Monster") — only while the battle hasn't started yet; once
    // it's over these thumbnails show what was caught/lost, not a find still
    // worth sizing up.
    if (_phase != _Phase.intro) return art;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => openWildPreview(context, c),
      child: art,
    );
  }

  Widget _footer() {
    switch (_phase) {
      case _Phase.intro:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fight a wild down into its catchable band — without killing '
              'it! — to light up Catch for it. Rarer finds need more, '
              'perfect hits in a row; a miss just spends AP and the fight '
              'goes on, same as attacking. Catch what you want, fight the '
              'rest down for XP.',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 12),
            ),
            const SizedBox(height: 12),
            _bigBtn('⚔️ Face them!', _startBattle),
          ],
        );
      case _Phase.done:
        if (_pendingWilds.isNotEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _summaryLine(),
              const SizedBox(height: 8),
              Text(
                '🏠 ${_pendingWilds.length} caught, but your settlement is '
                'full. Release monsters to make room and keep '
                '${_pendingWilds.length > 1 ? 'them' : 'it'} — otherwise '
                '${_pendingWilds.length > 1 ? 'they stay' : 'it stays'} '
                'behind.',
                textAlign: TextAlign.center,
                style: FoE.dim(size: 12).copyWith(color: kAccent),
              ),
              const SizedBox(height: 12),
              _bigBtn('🐾 Free a slot (Monsters)', _goReleaseAndReturn),
              const SizedBox(height: 8),
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Text(
                  'Leave ${_pendingWilds.length > 1 ? 'them' : 'it'} behind '
                  '· Head home',
                  style: FoE.dim(size: 12).copyWith(color: kInkFaint),
                ),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _summaryLine(),
            const SizedBox(height: 12),
            _bigBtn('Head home', () => Navigator.of(context).pop()),
          ],
        );
    }
  }

  /// The done-phase headline: caught / defeated / lost, plainly (user
  /// 2026-09-11 — no special framing needed for a "good" kill).
  Widget _summaryLine() {
    if (_doneNote != null) {
      return Text(
        _doneNote!,
        textAlign: TextAlign.center,
        style: FoE.title(size: 15).copyWith(color: const Color(0xFF9B3B22)),
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
      ).copyWith(color: _caughtCount > 0 ? kParchmentGo : kInk),
    );
  }

  /// Shown only when NONE of the hunt's finds resolve to a real species any
  /// more (every one removed from Dev Mode) — the whole trip is forfeited
  /// immediately rather than opening onto an empty fight.
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
          _bigBtn('Head home', () => Navigator.of(context).pop()),
        ],
      ),
    ),
  );

  Widget _bigBtn(String label, VoidCallback onTap) =>
      ParchmentButton(label: label, primary: true, onTap: onTap);
}
