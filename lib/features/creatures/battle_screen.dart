import '../../core/ui/feel.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
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
import '../social/models/pvp_match.dart';
import '../social/services/pvp_service.dart';
import 'services/battle_rewards.dart';
import 'services/capture_math.dart';
import 'services/combat_engine.dart';
import 'services/creatures_controller.dart';
import 'services/pvp_sync_service.dart';
import 'widgets/battle_scene.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_sprite.dart' show decodeWidthFor;
import 'widgets/type_circle_dialog.dart';
import 'widgets/wild_preview.dart';
import '../common/widgets/recess_bar.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../settlement/widgets/building_icon.dart';
import '../../core/ui/pressable.dart';

/// Result popped when a capture battle ends — replaces the old single-wild
/// [CatchSuccess] (2026-09-11): a hunt now fields several wilds in ONE
/// continuous battle instead of one battle per find, so a catch mid-fight no
/// longer ends the screen (it just removes that one wild and the fight goes
/// on — see CombatEngine.catchEnemy). This is what's actually popped once
/// [outcome] is finally reached, carrying EVERY wild caught along the way.
class HuntBattleResult {
  final CombatOutcome outcome;
  final List<Combatant> caught;

  /// Wilds that fainted rather than being caught — earned normal kill XP.
  /// Whatever's neither caught nor counted here (only possible if the
  /// player fled, or a wipe left some never engaged) was simply never
  /// resolved and is lost with the rest of the trip.
  final int defeatedCount;

  const HuntBattleResult(this.outcome, this.caught, this.defeatedCount);
}

/// Which status swept over a monster last — drives the rising white / falling
/// red lines, or the closing yellow ring, in _bigSprite (user 2026-08-29).
/// See BattleScreen's own [_fxStatusKind] doc for why this needs no separate
/// target field.
enum _StatusFx { none, buff, debuff, charging }

/// One battle-log line — the text plus whoever's turn it was, so both the
/// inline bar and the full-log sheet can show that monster's own portrait
/// before its name (user 2026-08-29: "vor den Namen der Monster jeweils ein
/// kleines Icon des Monsterassets zeigen"). [iconUrl] rides in at the moment
/// the line is captured, off [CombatEvent.actor] — see that field's own doc
/// for why it can't be re-derived later from the engine's current state.
class _LogLine {
  final String text;
  final String? iconUrl;
  const _LogLine(this.text, this.iconUrl);
}

/// A fainted combatant still playing its K.O. presentation, and where it was
/// standing when it fell — see BattleScreen's own [_koPlaying] doc for why
/// this has to be tracked separately from CombatEngine's field arrays.
class _KoEntry {
  final Combatant combatant;
  final int slot;
  final bool isEnemy;
  const _KoEntry(this.combatant, this.slot, this.isEnemy);
}

// The JRPG battle screen: enemies on top, the player's team below, the CTB
// initiative bar across the top and an action panel when it's a player
// creature's turn. Enemy turns (and player turns with auto-battle on) run on
// a short delay so the flow is readable. On finish the outcome is written
// back to the collection (pools always, XP on victory) and the screen pops
// with the CombatOutcome as its result.
class BattleScreen extends StatefulWidget {
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

  /// Capture-encounter mode: fight a wild DOWN into its catchable band to
  /// enable the inline Catch button. The threshold itself is per-wild now
  /// (2026-09-11 — see [catchHpThreshold]/[_canCatch]), since a hunt can
  /// field several at once and rarer ones must be brought lower; this flag
  /// only says whether catching is possible in this battle AT ALL. Overkill
  /// closes a given wild's own catch for good (a dead wild is nothing to
  /// catch), same as always.
  final bool isCapture;

  /// Tutorial catch: the ring QTE cannot be failed out of — a miss just restarts
  /// the ring (matches the guided intro's "the catch cannot be lost" promise).
  final bool guaranteedCatch;

  /// Live PvP mode (user 2026-09-15's Lobby rework) — `enemies` here are a
  /// real second human's monsters (reconstructed from their Lobby snapshot,
  /// see pvp_combatant_snapshot.dart), not AI. Every `isPvp`-gated branch in
  /// this file is additive: with the default `false` this screen behaves
  /// byte-for-byte as it always did. See the seams: [_scheduleAutoIfNeeded]
  /// (never calls performAutoAction for a PvP "enemy" turn), [_useAbility]/
  /// [_endTurn]/the switch handlers (relay the local action), [_applyOutcome]
  /// (reports to PvpService instead of granting XP), and [_endOverlay] (pops
  /// to the app root instead of returning a CombatOutcome to a dungeon
  /// caller).
  final bool isPvp;

  /// The shared seed both sides' CombatEngine must start on — see
  /// test/pvp_determinism_test.dart for why an identical seed + identical
  /// relayed action order is the whole lockstep bet. Required when [isPvp].
  final int? pvpSeed;

  /// The match row — carries `id` (for the sync channel/checkpoint) and, on
  /// a reconnect, `actionLog` to replay before going live. Required when
  /// [isPvp].
  final PvpMatch? pvpMatch;

  const BattleScreen({
    super.key,
    required this.team,
    required this.enemies,
    this.title = 'Battle',
    this.area,
    this.isCapture = false,
    this.guaranteedCatch = false,
    this.victoryRewards = const [],
    this.isPvp = false,
    this.pvpSeed,
    this.pvpMatch,
  });

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

/// Beats of the tutorial's fully scripted first fight — see the doc comment
/// on `_BattleScreenState._scriptBeat`.
enum _ScriptBeat {
  tackle,
  enemyBigHit,
  healItem,
  missedAttack,
  enemyDebuffHit,
  powerAttack,
  bankEndTurn,
  enemyAlmostKill,
  finisher,
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  late final CombatEngine _engine;
  Timer? _autoTimer;
  bool _autoBattle = false;
  bool _outcomeApplied = false;

  // ── PvP (2026-09-15) ─────────────────────────────────────────
  // Only ever touched when widget.isPvp — see that field's doc comment.
  final PvpSyncService _pvpSync = PvpSyncService();
  final PvpService _pvpService = PvpService();
  // Set when a relayed 'flee' arrives — CombatEngine.flee() doesn't record
  // WHICH side fled, so _applyOutcome needs this to award the forfeit win
  // to the side that stayed rather than treating both sides as losers.
  bool _pvpOpponentFled = false;

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
  // The struck monster's shake+flash, kept on its OWN controller and started
  // only once [_fx] (the attacker's lunge) finishes (user 2026-08-29: "jetzt
  // ist es asynchron. Zunächst muss die Angriffsanimation kommen, wenn diese
  // fertig ist, kommt erst die Trefferanimation") — sequential, not the same
  // timeline: the two used to share [_fx], playing the swing and the flinch
  // at once instead of one causing the other.
  late final AnimationController _fxReact;
  // A buff/debuff's own presentation — no lunge, no shake, just the line
  // sweep, at its own slower pace (user 2026-08-29: "Bei Buffs oder Debuffs
  // soll das Monster nicht hoch oder runter gehen. Nur die Striche, diese
  // dafür etwas langsamer"). Kept off [_fx]/[_fxReact] entirely rather than
  // suppressing their output: since neither controller ever runs for a
  // status action, every motion computation in _bigSprite that reads
  // `_fx.isAnimating`/`_fxReact.isAnimating` naturally resolves to zero on
  // its own — nothing to remember to zero out by hand.
  late final AnimationController _fxStatus;
  Combatant? _fxTarget;
  Combatant? _fxActor;
  // WHO the current lunge is aimed at, so it can angle sideways toward that
  // slot rather than only ever moving straight up/down (user 2026-08-29:
  // "den Angriff noch in die Richtung des anvisierten Monsters machen").
  // Separate from [_fxTarget] because it's needed DURING the lunge, before
  // the target has even started reacting.
  Combatant? _fxLungeTarget;

  // White lines rising for a buff, red lines falling for a debuff (user
  // 2026-08-29) — which one, and NOT who: a buff always lands on whoever is
  // lunging ([_fxLungeTarget]/[_fxActor], since a self-buff's "target" IS the
  // actor) and a debuff always lands on whoever is reacting ([_fxTarget]),
  // so no separate combatant field is needed — see _bigSprite.
  _StatusFx _fxStatusKind = _StatusFx.none;

  // True for the whole of [_playHit] — the engine's OWN turn state flips to
  // the player the instant an enemy's action resolves, well before that
  // action's lunge/react has finished PLAYING. Without this, a player who
  // acts in that window starts a SECOND [_playHit] on the same shared
  // [_fx]/[_fxReact] controllers while the first is still running — forward()
  // called again mid-flight completes the first TickerFuture early and
  // reassigns [_fxActor]/[_fxLungeTarget]/[_fxTarget] out from under it,
  // which is why the enemy's forward swing sometimes never visibly finished
  // and why a struck monster occasionally jumped along the wrong axis (user
  // 2026-08-29: "Bei gegnerischen Attacken wird manchmal die
  // vorwärtsgerichtete Animation nicht durchgeführt" / "das getroffene
  // Monster shaken... und nicht hoch und runter gehen"). [_playerActions]
  // greys its buttons on this too, so the player physically cannot start a
  // second presentation before the first one is actually done.
  bool _presenting = false;

  // The initiative strip's own frozen-while-presenting snapshot — see
  // [_initiativeStrip] for why it needs one at all.
  List<Combatant>? _lastSettledOrder;

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

  // ── K.O. animation (user 2026-08-29: "eine K.O animation. Das Monster
  // blinkt, geht hoch und durch das Podest verschwindet es nach unten") ──
  // A fainted combatant is cleared from CombatEngine's own field array the
  // INSTANT its HP hits 0 (see _resolveFaints) — before this, that meant it
  // just vanished from the tree with nothing shown. [_koPlaying] holds onto
  // it a little longer, in its own last-known slot, purely for this
  // screen's own presentation; the engine has already moved on.
  late final AnimationController _fxKo;
  final Map<String, _KoEntry> _koPlaying = {};
  // The last field arrays this screen actually SAW, compared against the
  // engine's current ones every notifyListeners() tick — a slot that held a
  // living combatant last time and now holds something else (empty, or the
  // enemy bench's auto-refill) is how a fresh K.O. is detected, since the
  // engine gives no event for "this one just left the field".
  List<Combatant?> _prevPlayerField = const [];
  List<Combatant?> _prevEnemyField = const [];

  // ── Entry animation (user 2026-07-24) ─────────────────────
  // Plays once when the screen opens: the fighters slide onto the field, and
  // the action loop is held (`_entering`) until they've arrived.
  late final AnimationController _entry;
  bool _entering = true;

  // ── Idle bob (user request) ────────────────────────────────
  // A slow, small up-down breathing motion so the field never looks frozen
  // between turns. One shared repeating clock rather than one controller per
  // monster — [_idlePhase] offsets each combatant round it so six fighters
  // don't bob in lockstep like a single puppet.
  late final AnimationController _idle;
  static double _idlePhase(Combatant c) => (c.id.hashCode % 1000) / 1000.0;

  // Level-ups captured when the fight resolves, shown in the end overlay with
  // their stat gains (user 2026-07-24).
  List<LevelUpResult> _levelUps = const [];
  // Tint of the current hit's flash on the reacting sprite — the striking
  // move's element colour, so a super-effective fire hit flashes orange, a
  // basic attack white (user request 2026-07-20).
  Color _fxImpact = Colors.white;
  // Compared against [CombatEngine.actionSeq], not [CombatEngine.lastAction]
  // (user 2026-08-29: "Wenn ich mehrere Buffs/Debuffs pro Runde mache, dann
  // kommt die Animation nicht mehr") — two buffs back to back can produce the
  // IDENTICAL log string ("🛡️ Defense Up" twice), and comparing text made the
  // second one invisible: not logged, not animated, the presentation just
  // silently skipped it.
  int _lastActionSeqSeen = 0;
  // The last two combat-log lines shown in the middle bar (user 2026-07-18).
  final List<_LogLine> _log = [];

  // ── Floating combat text (user 2026-07-20) ────────────────
  // Damage/heal numbers that pop over the struck monster and drift up. Fed by
  // the engine's per-action CombatEvents; each entry self-animates and removes
  // itself by id when done.
  final List<_FloatText> _floats = [];
  int _floatSeq = 0;

  // ── Rising heal crosses (user 2026-09-15: "steigen grüne Kreuze auf") ──
  // A little cluster of ✚ glyphs over the healed monster, on top of the
  // usual "+N" number — the number says HOW MUCH, the crosses say WHAT KIND
  // at a glance, the same way a miss already gets its own word.
  final List<_HealCross> _healCrosses = [];
  int _healCrossSeq = 0;

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

  /// The wild being attempted and the monster attempting it, captured once
  /// at [_startCatch] time and reused through miss/succeed — up to 3 wilds
  /// and 3 hunters can be on the field at once (2026-09-11), so reading
  /// [_target]/[_engine.activePlayer] fresh at resolution time would risk
  /// resolving against whichever happens to be selected THEN, not who this
  /// specific attempt was actually against.
  Combatant? _catchWild;
  Combatant? _catcher;

  /// Every wild caught so far THIS battle (2026-09-11) — a catch no longer
  /// ends the fight (see CombatEngine.catchEnemy), so this accumulates
  /// across however many of a hunt's fielded wilds the player catches
  /// before the battle actually ends, and rides home on [HuntBattleResult].
  final List<Combatant> _caught = [];

  // ── Guided intro: turn order → AP → actions → HP (user 2026-08-24) ──
  // Only ever set on the tutorial's own first fight — every anchored widget
  // is dimmed-and-dead except the one this index points at, so the player
  // physically cannot act until they have tapped through all four, and
  // "explain the parts of a battle" cannot be skipped by accident.
  int? _battleCallout;
  static const _battleCalloutAnchors = [
    'battle-turnorder',
    'battle-ap',
    'battle-actions',
    'battle-hp',
  ];

  /// Index 1 (AP) is filled in dynamically — see [_battleCalloutHints] —
  /// with the actual regen number rather than a vague "they refill" (user
  /// 2026-09-03: "Ap erklären, um wieviel sie sich regenerieren"), since it
  /// depends on the acting monster's evolution stage.
  static const _battleCalloutHintTemplates = [
    'Turn order — whoever is next lights up here.',
    null,
    'Attack and abilities — spend AP here to act.',
    'HP — the ring around your monster. It never heals on its own.',
  ];

  List<String> get _battleCalloutHints {
    final stage = _engine.currentActor.stage;
    final regen = apRegenForStage(stage);
    final cap = maxActionPointsForStage(stage);
    return [
      for (final t in _battleCalloutHintTemplates)
        t ??
            'AP — every move spends Action Points; you regain $regen per '
                'turn, up to $cap.',
    ];
  }

  void _advanceBattleCallout() {
    final i = _battleCallout;
    if (i == null) return;
    final done = i + 1 >= _battleCalloutAnchors.length;
    setState(() {
      _battleCallout = done ? null : i + 1;
      // The scripted fight itself starts the instant the explanatory
      // callouts finish (user 2026-09-03). No _ensureApFor here (user
      // 2026-09-05: "ich starte mit 3 AP, sollte aber nur mit 2 starten") —
      // tackle's own cost is scripted down to what the opener actually
      // holds instead, see [_effectiveApCost] and [_useAbility]'s
      // scriptedApCost, so the AP counter never jumps ahead of the tap.
      if (done && _isFirstBattleTutorial) {
        _scriptBeat = _ScriptBeat.tackle;
      }
    });
  }

  // ── Guided intro, part 2: the scripted fight itself (user 2026-09-03) ──
  // Once the four explanatory callouts above are done, the tutorial's first
  // fight runs a fully authored beat sequence — not "these three things
  // happen eventually" but an EXACT script (user: "mache die Angriffe und
  // HP Verlust unabhängig von den tatsächlichen Werten. Daher ist dieser
  // Kampf fake, dass es aufgeht"): every HP change is forced to its named
  // percentage regardless of what the real damage formula would have
  // produced, and the enemy's two attacks + one debuff are DRIVEN here
  // rather than left to CombatEngine's own AI, so they land in the exact
  // order and with the exact effect the script names. At every PLAYER beat,
  // exactly one control is enabled — everything else greyed out, the same
  // "one lit thing" rule the rest of the tutorial follows. Enemy beats have
  // no anchor at all: there is nothing for the player to press while it
  // isn't their turn, same as any other fight.
  //
  //   tackle          — player: plain Attack — enemy −25% (75% left)
  //   enemyBigHit     — enemy: effective hit — player down to 33% of max HP
  //   healItem        — player: Items — costs a flat kItemApCost AP (see
  //                     [_openItems]), not the whole turn, so the AP left
  //                     over still buys the same turn's second action
  //   missedAttack    — player: ability (NOT plain Attack), same turn as
  //                     healItem — a scripted Miss, so the enemy's HP stays
  //                     exactly where tackle left it (user 2026-09-05:
  //                     turned from an earlier scripted "Resisted" 0 into a
  //                     scripted Miss — same reason, teaches a different
  //                     concept). Priced at position 1's own tile cost, not
  //                     plain Attack's (user 2026-09-05: "soll eine Attacke
  //                     sein, welche 3 AP braucht... nicht Standardattacke").
  //   enemyDebuffHit  — enemy: Defense down + a real hit — player down to
  //                     75% of max HP
  //   powerAttack     — player: ability — resisted ("not very effective") —
  //                     enemy down to 33% of its max HP
  //   bankEndTurn     — player: End Turn, same turn as powerAttack, banking
  //                     the leftover AP
  //   enemyAlmostKill — enemy: player forced to 1 HP (survives)
  //   finisher        — player: the bottom-left element move (NOT plain
  //                     Attack, user 2026-09-05), a scripted critical —
  //                     enemy to 0, fight over
  //
  // Several of these beats also carry a one-line concept explainer in
  // [_scriptInfoHint] (effectiveness, resistance, buffs, "not very
  // effective", crit) — a SEPARATE blocking overlay layered above the
  // beat's own spotlight, dismissed by tap, so the player reads it before
  // whatever control lights up next (user 2026-09-04's turn-by-turn
  // script).
  _ScriptBeat? _scriptBeat;

  /// The scripted fight's one lit control right now, or null outside the
  /// tutorial, while the four explanatory callouts (or a [_scriptInfoHint])
  /// are still running, on an enemy beat (nothing to press), or once the
  /// sequence is done.
  String? get _scriptedBattleAnchor {
    if (!_isFirstBattleTutorial || _battleCallout != null) return null;
    return switch (_scriptBeat) {
      _ScriptBeat.tackle => 'battle-attack-btn',
      _ScriptBeat.healItem => 'battle-items-btn',
      _ScriptBeat.missedAttack ||
      _ScriptBeat.powerAttack => 'battle-first-ability',
      _ScriptBeat.bankEndTurn => 'battle-endturn-btn',
      // Bottom-left, the pricier element move (user 2026-09-05: "hier immer
      // die Attacke unten links (4 AP) wählen lassen") — not plain Attack.
      _ScriptBeat.finisher => 'battle-second-ability',
      _ => null,
    };
  }

  String? get _scriptedBattleHint => switch (_scriptBeat) {
    _ScriptBeat.tackle => 'Attack!',
    _ScriptBeat.healItem => 'That hurt — use your potion to heal up.',
    _ScriptBeat.missedAttack => 'Follow up with your ability.',
    _ScriptBeat.powerAttack => 'Follow up with your ability.',
    _ScriptBeat.bankEndTurn =>
      'End Turn without acting — the AP you save carries into next turn.',
    _ScriptBeat.finisher => 'Finish it!',
    _ => null,
  };

  /// Fixed AP cost for the tutorial's four ability tiles, BY POSITION —
  /// index 0..3 in the 2-column grid (top-left, top-right, bottom-left,
  /// bottom-right) — the same for all three starters throughout the whole
  /// fight (user 2026-09-05: "oben links attack 2 ap / oben rechts
  /// Elementattacke 2 ap / unten links Elementattacke 4 ap / unten rechts
  /// Buff 2 ap. Das ist bei allen Startermonster über das gesamte Tutorial
  /// genau so."). Supersedes the earlier beat-by-beat overrides (a
  /// dedicated tackle cost, a dedicated finisher cost, and so on) with one
  /// table that doesn't care which beat is live or which specific move a
  /// starter happens to have in that slot — Attack sits at index 0 on every
  /// combatant (user 2026-09-03), and the tutorial's backfilled starting
  /// kit (see CreatureInstance.backfillAbilities) fills 1..3 the same way
  /// for every starter.
  static const List<int> _kTutorialTileApCost = [2, 2, 4, 2];

  /// [_kTutorialTileApCost] for whichever position [a] occupies in [me]'s
  /// own ability list, or null outside the tutorial / past the fourth tile
  /// (a species with a 5th+ equipped move keeps its real price there).
  int? _tutorialTileApCost(Combatant me, AbilityDef a) {
    if (!_isFirstBattleTutorial) return null;
    final i = me.abilities.indexOf(a);
    return i >= 0 && i < _kTutorialTileApCost.length
        ? _kTutorialTileApCost[i]
        : null;
  }

  /// What [a] will actually cost RIGHT NOW — [CombatEngine.abilityApCost]
  /// normally, [_tutorialTileApCost] during the tutorial. Drives both the
  /// tile's displayed cost and its enabled check, so the two never
  /// disagree.
  int _effectiveApCost(AbilityDef a) {
    final me = _engine.activePlayer;
    if (me != null) {
      final fixed = _tutorialTileApCost(me, a);
      if (fixed != null) return fixed;
    }
    return CombatEngine.abilityApCost(a);
  }

  /// The script is a fixed cutscene, not a stat check — an actor whose AP
  /// happens to fall short of what the next beat needs (regen didn't line
  /// up, the item beat's own 1-AP spend) must never be able to block it
  /// (user 2026-09-03: "unabhängig von den tatsächlichen Werten").
  void _ensureApFor(_ScriptBeat beat) {
    final me = _engine.activePlayer;
    if (me == null) return;
    final need = switch (beat) {
      // Position 0 (top-left: Attack) — see _kTutorialTileApCost.
      _ScriptBeat.tackle => _kTutorialTileApCost[0],
      // Position 2 (bottom-left: the pricier element move — user
      // 2026-09-05: "hier immer die Attacke unten links (4 AP) wählen
      // lassen"), not Attack any more.
      _ScriptBeat.finisher => _kTutorialTileApCost[2],
      // Enough that the item's own kItemApCost spend actually shows as a
      // real deduction, leaving exactly position 1's own cost afterward
      // (user 2026-09-05: "es bleiben noch 2 AP übrig für eine Attacke").
      _ScriptBeat.healItem => kItemApCost + _kTutorialTileApCost[1],
      // Position 1 (top-right: the follow-up element move).
      _ScriptBeat.missedAttack => _kTutorialTileApCost[1],
      // Position 1 again, PLUS a small surplus: bankEndTurn right after is
      // scripted as "End Turn WITHOUT acting, banking the leftover AP",
      // which needs something left to actually bank.
      _ScriptBeat.powerAttack => _kTutorialTileApCost[1] + _kBankedApSurplus,
      _ => 0,
    };
    // FORCED to exactly `need`, not just floored up to it (user 2026-09-06:
    // "hier sind die AP von 0 auf 3 gesprungen") — the real engine keeps
    // accruing AP off the actor's own Speed throughout this fight same as
    // any other, since only damage/miss/crit are scripted (deterministicCombat
    // never touches AP). A floor left whatever that real accrual happened to
    // produce sitting on top of `need`, so the number shown after the next
    // scripted spend no longer matched the fixed "leaves exactly N AP" this
    // whole beat sequence promises — same reasoning as every forced HP
    // number in this fight.
    me.ap = need;
  }

  /// How much AP [_ScriptBeat.bankEndTurn] visibly banks — see
  /// [_ensureApFor]'s own `powerAttack` case.
  static const int _kBankedApSurplus = 1;

  /// [c]'s first ability that ISN'T the universal Attack — i.e. the actual
  /// species-authored move the script means by "your ability" (powerAttack,
  /// 'battle-first-ability'). Attack sits at abilities[0] on every combatant
  /// now (user 2026-09-03: "attack soll eine normale Fähigkeit sein"), so
  /// plain `.first` would grab the wrong one.
  AbilityDef? _firstRealAbility(Combatant c) {
    for (final a in c.abilities) {
      if (a.id != 'attack') return a;
    }
    return null;
  }

  /// [c]'s ability at tile position 2 (bottom-left) — the second, pricier
  /// element move the finisher beat uses (user 2026-09-05: "hier immer die
  /// Attacke unten links (4 AP) wählen lassen. Diese ist eine
  /// Elementattacke."). Same position-based reasoning as
  /// [_kTutorialTileApCost]: whichever move a starter has equipped there,
  /// not a specific move id.
  AbilityDef? _secondRealAbility(Combatant c) =>
      c.abilities.length > 2 ? c.abilities[2] : null;

  /// Runs one of the enemy's three scripted beats directly — CombatEngine's
  /// own AI (performAutoAction) picks whatever it judges best, which is
  /// exactly what the script can't allow: it needs THIS move, on THIS turn,
  /// landing for THIS exact amount. Falls back to the real AI outside the
  /// three enemy beats (and once the sequence is done) so the rest of the
  /// fight — the intro callouts' own turns, anything after the finisher —
  /// still plays normally.
  Future<void> _runScriptedEnemyBeat() async {
    final beat = _scriptBeat;
    final foe = _engine.currentActor;
    final me = _engine.activePlayer;
    if (me == null ||
        beat != _ScriptBeat.enemyBigHit &&
            beat != _ScriptBeat.enemyDebuffHit &&
            beat != _ScriptBeat.enemyAlmostKill) {
      if (_isFirstBattleTutorial) {
        // A turn outside the three named beats — the enemy (battle 1's own
        // doc: picked "at its natural stats", not scaled down) getting to
        // act for real during the intro callouts, before [_scriptBeat] is
        // even set, or on any other unscripted turn — must never be able to
        // end the tutorial for real. Both fighters are forced to exactly 12
        // HP for the script's own numbers (see initState); a genuine hit
        // against that is a coin-flip KO. Restores the blanket protection
        // _armAgainstOverkill used to give every real action here, lost
        // when it was replaced by the beat-specific scriptedNextHit, which
        // only covers the three named beats.
        final before = {
          for (final c in _engine.playerField)
            if (c != null) c: c.hp,
        };
        for (final c in before.keys) {
          c.hp = 999999;
        }
        _engine.performAutoAction();
        for (final entry in before.entries) {
          entry.key.hp = entry.value;
        }
      } else {
        _engine.performAutoAction();
      }
      return;
    }
    // Same reasoning as _ensureApFor: an attack beat's presentation (lunge,
    // floating number, log line) still needs basicAttack to actually FIRE,
    // which needs AP — the enemy's carried pool is real gameplay state, not
    // scripted, so top it up rather than let a low roll silently skip the
    // animation ([_engine.scriptedNextHit] still lands the exact scripted
    // number either way).
    if ((beat == _ScriptBeat.enemyBigHit ||
            beat == _ScriptBeat.enemyDebuffHit ||
            beat == _ScriptBeat.enemyAlmostKill) &&
        foe.ap < kBasicAttackApCost) {
      foe.ap = kBasicAttackApCost;
    }
    switch (beat!) {
      case _ScriptBeat.enemyBigHit:
        // Document's own figures (user 2026-09-04): both fighters open the
        // fight on exactly 12 HP (forced in initState), so every beat's flat
        // number below reproduces the document's HP column exactly.
        _engine.scriptedNextHit = (damage: 8, miss: false);
        _engine.basicAttack(foe, me);
        // Hands the turn straight back — with only two combatants, a
        // genuinely faster foe otherwise wins the real CTB race for a
        // second (and third) turn before the player's own comes up again
        // (user 2026-09-05: "infernoclaw attackiert weiterhin 3x
        // nacheinander"/"greift weiterhin einfach an"). MUST run BEFORE the
        // await below, in the same synchronous stretch as basicAttack:
        // basicAttack's own notifyListeners already queued
        // _consumeCombatEvents().then(_scheduleAutoIfNeeded) as a
        // microtask, and that callback reads currentActor/_scriptBeat
        // whenever it happens to run — which, polling _presenting on a
        // 30ms timer, is not guaranteed to lose the race against
        // _waitForPresentation below. Only code that runs before Dart ever
        // yields to the microtask queue is guaranteed to land first.
        _engine.forceActing(me);
        // Ensures the item's own 1-AP spend actually SHOWS (user
        // 2026-09-05: "Item Verbrauchen, verbraucht immer 1 AP... es
        // bleiben noch 2 AP übrig für eine Attacke") — at 0 AP the subtract
        // just clamped back to 0, so the cost never visibly landed.
        _ensureApFor(_ScriptBeat.healItem);
        await _waitForPresentation(); // see _useAbility's own doc
        setState(() {
          _scriptBeat = _ScriptBeat.healItem;
          _scriptInfoHint =
              'Super effective! A type advantage deals extra '
              'damage.';
        });
      case _ScriptBeat.enemyDebuffHit:
        // A real attack for the "+ att" half, THEN the status — same order
        // the beat is named in (user 2026-09-04's script: "Buff auf
        // Verteidigung + att").
        _engine.scriptedNextHit = (damage: 3, miss: false);
        _engine.basicAttack(foe, me);
        me.secondaryDebuffs[SecondaryDebuffKind.defenseDown] = ActiveEffect(
          turnsRemaining: kSecondaryDebuffDuration,
          value: 0.30,
        );
        _flashMessage('${foe.name} lowers your Defense!');
        // NOT _engine.endTurn() — that refuses on principle while it's the
        // ENEMY's turn (see its own doc comment). basicAttack can leave AP
        // behind that the real AI would keep spending; this beat is only
        // authored for ONE hit, so the turn is forced closed right after.
        _engine.forceEndTurn();
        _engine.forceActing(me); // see enemyBigHit's own doc — same race
        await _waitForPresentation(); // the "AP recharging" bank visual
        _ensureApFor(_ScriptBeat.powerAttack);
        setState(() {
          _scriptBeat = _ScriptBeat.powerAttack;
          _scriptInfoHint =
              'Debuff — that weakens a stat for a few turns. '
              'Watch for the icon on the status row.';
        });
      case _ScriptBeat.enemyAlmostKill:
        _engine.scriptedNextHit = (damage: 8, miss: false);
        _engine.basicAttack(foe, me);
        _engine.forceActing(me); // see enemyBigHit's own doc — same race
        await _waitForPresentation();
        _ensureApFor(_ScriptBeat.finisher);
        setState(() => _scriptBeat = _ScriptBeat.finisher);
      default:
        _engine.performAutoAction();
    }
  }

  /// The player's own deliberate End Turn press — separate from the
  /// programmatic `_engine.endTurn()` calls elsewhere (the catch flow, the
  /// scripted debuff beat), which don't advance the script.
  void _endTurn() {
    if (_scriptBeat == _ScriptBeat.bankEndTurn) {
      setState(() => _scriptBeat = _ScriptBeat.enemyAlmostKill);
    }
    // Captured BEFORE endTurn() advances the queue — by the time it
    // returns, currentActor is already whoever's turn came next.
    final actor = _engine.currentActor;
    _engine.endTurn();
    _relayPvpAction(kind: 'endTurn', actor: actor);
  }

  /// A one-line concept explainer sitting ON TOP of whatever beat is live —
  /// non-null between a beat landing and the player tapping past it (user
  /// 2026-09-04: effectiveness/miss/buffs/"not very effective"/crit each get
  /// their own beat). The beat underneath has already advanced by the time
  /// this is set, so dismissing it just reveals that beat's own spotlight —
  /// except for [_pendingVictory], which the finisher beat holds off on
  /// exactly so the crit explainer isn't fighting the win screen for the
  /// same pixels.
  String? _scriptInfoHint;
  void _dismissScriptInfo() {
    setState(() => _scriptInfoHint = null);
    // An enemy beat may have been waiting on exactly this (see
    // [_scheduleAutoIfNeeded]'s own guard) — nothing else re-triggers it
    // once the hint that blocked it is gone.
    _scheduleAutoIfNeeded();
  }

  /// The tutorial's own scripted first fight — gates the intro callouts, the
  /// free starting potion, and the fully authored beat sequence in
  /// [_scriptBeat]. Every HP/status change in that sequence is forced
  /// directly rather than tuned through real stats (user 2026-09-03:
  /// "mache die Angriffe und HP Verlust unabhängig von den tatsächlichen
  /// Werten. Daher ist dieser Kampf fake, dass es aufgeht") — so, unlike an
  /// ordinary jumpstart fight, nothing here needs a stat handicap at all.
  bool _isFirstBattleTutorial = false;

  @override
  void initState() {
    super.initState();
    _isFirstBattleTutorial =
        SettlementController().introStep == IntroStep.firstNode;
    if (_isFirstBattleTutorial) _battleCallout = 0;
    _engine = CombatEngine(
      players: widget.team.map(Combatant.fromInstance).toList(),
      enemies: widget.enemies,
      // Cosmetic, not load-bearing (the scripted beats override HP either
      // way) — turns off miss AND crit for both sides, so the log/floating
      // text (user 2026-09-03: "Effekte wie 'miss oder Crit' ausgeschaltet")
      // always shows a plain successful hit that matches the guaranteed
      // percentage, instead of a "misses!"/"Critical!" that contradicts it.
      deterministicCombat: _isFirstBattleTutorial,
      // PvP: BOTH sides are a human, so the "enemy" field needs the same
      // bounded-bench/voluntary-switch rights [players] already has — see
      // CombatEngine's own `isPvp` doc. The shared seed is what makes two
      // independently-built engines (one per device) stay in lockstep; see
      // test/pvp_determinism_test.dart.
      isPvp: widget.isPvp,
      rng: widget.isPvp ? math.Random(widget.pvpSeed!) : null,
    );
    if (_isFirstBattleTutorial) {
      // "Beide Monster starten mit genau 12HP" (user 2026-09-04) — the
      // script's whole HP column assumes this, and every flat number in the
      // beats below is a subtraction from it. `stats` is a regular mutable
      // map, so overriding the HP entry in place needs no parallel
      // "scripted maxHp" field, and the HP ring reads it exactly like any
      // other stat.
      for (final c in [..._engine.players, ..._engine.enemies]) {
        c.stats[CreatureStat.hp] = 12;
        c.hp = 12;
      }
      // "tackle" is scripted as the player's OPENING move — but the enemy is
      // picked purely for type effectiveness and fights at its own natural
      // speed (see _launchBattle), so it can easily win the real coin flip
      // against a slower starter (user: "wenn ich vineguard als starter
      // nehme, dann greift mich infernoclaw direkt an"). Force the player's
      // own combatant to open instead of leaving it to real stats.
      if (_engine.players.isNotEmpty) {
        _engine.forceOpeningActor(_engine.players.first);
      }
    }
    _prevPlayerField = List.of(_engine.playerField);
    _prevEnemyField = List.of(_engine.enemyField);
    _engine.addListener(_onEngineChanged);
    if (widget.isPvp) _startPvpSync();
    _fx = AnimationController(
      vsync: this,
      // The ATTACKER's own lunge — windup, strike, rebound — and its sound
      // cue, all fractions of this one duration. Was 320ms (user 2026-08-29:
      // "die Kampfanimationen sind noch zu schnell, bitte alles etwas
      // langsamer").
      duration: const Duration(milliseconds: 460),
    );
    // The TARGET's reaction — shake + flash — starts only once [_fx]
    // finishes (see [_playHit]), so it is a shorter, separate beat rather
    // than a fraction of the same one.
    _fxReact = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    // Slower than either — a buff/debuff sweep isn't racing a swing or a
    // flinch, it IS the whole presentation (user 2026-08-29: "diese [Striche]
    // dafür etwas langsamer").
    _fxStatus = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    // Blink, rise, sink — one continuous clock for all three beats (user
    // 2026-08-29: "eine K.O animation. Das Monster blinkt, geht hoch und
    // durch das Podest verschwindet es nach unten"). See _bigSprite's koing
    // branch for the actual curve.
    _fxKo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
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
    _entry =
        AnimationController(
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
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat();
    Feel.startBattleMusic();
    // Every sprite in the fight, warmed BEFORE anyone's first swing (user
    // 2026-08-29: "beim ersten Angriff von jedem meiner Monster [greift der
    // Gegner direkt an]" — every monster's OWN first attack, not just the
    // battle's). The lunge (~460ms) is often shorter than a cold network
    // fetch+decode, so a combatant's first-ever appearance on screen used to
    // show its FADED LOADING PLACEHOLDER moving instead of the real sprite —
    // technically animating, but reading as "nothing happened" because there
    // was nothing recognisable to see move. Precached here, the real image
    // is already resident by the time anyone's first turn comes up — bench
    // included, since a reserve's own first attack has the exact same gap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final c in [..._engine.players, ..._engine.enemies]) {
        for (final url in {c.imageUrl, c.backImageUrl}) {
          if (url != null) {
            precacheImage(NetworkImage(url), context).catchError((_) {});
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _flashTimer?.cancel();
    _fx.dispose();
    _fxReact.dispose();
    _fxStatus.dispose();
    _fxKo.dispose();
    _ring.dispose();
    _entry.dispose();
    _idle.dispose();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    if (widget.isPvp) _pvpSync.disconnect();
    Feel.stopBattleMusic();
    super.dispose();
  }

  // ── PvP relay (2026-09-15) ───────────────────────────────────
  // See widget.isPvp's doc comment for the overall shape: both devices
  // build an identical engine from the same seed + team snapshots, then
  // apply only the small [PvpAction] messages either side sends — proven
  // to stay in sync by test/pvp_determinism_test.dart.
  Combatant? _findCombatant(String? id) {
    if (id == null) return null;
    for (final c in [..._engine.players, ..._engine.enemies]) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Replays [widget.pvpMatch]'s persisted `action_log` (a reconnect
  /// picking up mid-fight) against the freshly-built engine, then connects
  /// live from where that leaves off.
  void _startPvpSync() {
    final match = widget.pvpMatch!;
    for (final raw in match.actionLog) {
      _applyRemoteAction(PvpAction.fromJson(raw));
    }
    _pvpSync.connect(
      matchId: match.id,
      resumeFromSeq: match.actionLog.length,
      onRemoteAction: _applyRemoteAction,
    );
  }

  /// Applies one relayed action (mine or the opponent's — see
  /// pvp_sync_service.dart's own doc on why the dispatch doesn't need to
  /// know which) directly to [_engine]. [_onEngineChanged] (already wired
  /// via [ChangeNotifier]) picks up the resulting notify exactly like any
  /// local action would.
  void _applyRemoteAction(PvpAction action) {
    final actor = _findCombatant(action.actorId);
    if (actor == null) return;
    switch (action.kind) {
      case 'attack':
        final target = _findCombatant(action.targetId);
        if (target != null) _engine.basicAttack(actor, target);
      case 'ability':
        final ability = action.abilityId == null ? null : kAbilityDefs[action.abilityId];
        if (ability != null) {
          _engine.useAbility(actor, ability, _findCombatant(action.targetId));
        }
      case 'switch':
        if (actor.isPlayerSide) {
          _engine.switchActivePlayer(_engine.players.indexOf(actor));
        } else {
          _engine.switchActiveEnemy(_engine.enemies.indexOf(actor));
        }
      case 'endTurn':
        _engine.forceEndTurn();
      case 'flee':
        _pvpOpponentFled = true;
        _engine.flee();
    }
    if (mounted) setState(() {});
  }

  /// Sends MY chosen action over [_pvpSync] — called right after the LOCAL
  /// engine call that already applied it (never before: the local player
  /// sees their own action instantly, the relay is a side effect, not a
  /// gate). No-op outside [widget.isPvp].
  void _relayPvpAction({
    required String kind,
    required Combatant actor,
    String? abilityId,
    Combatant? target,
  }) {
    if (!widget.isPvp) return;
    _pvpSync.sendAction(
      widget.pvpMatch!.id,
      kind: kind,
      actorId: actor.id,
      abilityId: abilityId,
      targetId: target?.id,
    );
  }

  void _onEngineChanged() {
    if (!mounted) return;
    // Checked on EVERY change, not just new actions — a faint can ride
    // along with any of them (a hit, a DoT tick, recoil), and the engine
    // clears its own field the instant it happens.
    _detectKos();
    // A new log line means an action just landed — spawn its floating numbers
    // and play the hit pulse on the struck side (derived from the events, not
    // the actor, so it's right even after the turn advances).
    final isNewAction = _engine.actionSeq != _lastActionSeqSeen;
    if (isNewAction) {
      _lastActionSeqSeen = _engine.actionSeq;
      // The FULL history is kept now (user 2026-08-28: "Kampflog
      // aufklappbar machen, damit der ganze Log angezeigt wird") — the
      // inline bar still only shows the last two lines; [_openFullLog]
      // reads all of it.
      if (_engine.lastAction.isNotEmpty) {
        // Read HERE, not later — by the time anything else looks at it,
        // lastEvents may already belong to a different action.
        final icon = _engine.lastEvents.isEmpty
            ? null
            : _engine.lastEvents.first.actor?.imageUrl;
        _log.add(_LogLine(_engine.lastAction, icon));
      }
    }
    setState(() {});
    if (!isNewAction) {
      _scheduleAutoIfNeeded();
      return;
    }
    // WAIT for this action's own presentation to finish — lunge, then the
    // hit reaction — before even STARTING the pause that leads into the next
    // one (user 2026-08-29: "Zunächst alle Animationen von einem Kampf
    // abspielen lassen, dann eine Pause und erst dann soll die gegnerische
    // Aktion durchgeführt werden"). Before this, [_scheduleAutoIfNeeded]'s
    // own pause ran IN PARALLEL with the animation instead of after it — the
    // two happened to be a similar length, which is exactly what made an
    // enemy's next swing already landing while the last one was still
    // playing read as chaos rather than as two separate hits.
    // whenComplete, NOT .then — an exception anywhere in the presentation
    // pipeline (float text, sound, the lunge/react animations) used to just
    // swallow this continuation: .then()'s success callback never runs on a
    // failed Future, so nothing ever re-armed the next auto-action and the
    // fight froze solid with no error shown (nothing here sits inside a
    // widget build, so Flutter never puts up its red error screen either).
    // whenComplete runs either way and the underlying error still
    // propagates/logs, but the fight itself can no longer wedge on it.
    _consumeCombatEvents().whenComplete(() {
      if (mounted) _scheduleAutoIfNeeded();
    });
  }

  /// Compares the last field arrays this screen saw against the engine's
  /// current ones — a slot that held a LIVING combatant last time and now
  /// holds something else is a fresh faint (see [_koPlaying]'s own doc for
  /// why the engine gives no event for this). Newly-found ones are added and
  /// the shared K.O. clock started; [_koPlaying] itself is cleared once that
  /// clock finishes, in the same sweep for however many joined it.
  void _detectKos() {
    var foundNew = false;
    void check(List<Combatant?> prev, List<Combatant?> current, bool isEnemy) {
      for (var i = 0; i < prev.length && i < current.length; i++) {
        final was = prev[i];
        if (was != null && !was.alive && !_koPlaying.containsKey(was.id)) {
          _koPlaying[was.id] = _KoEntry(was, i, isEnemy);
          foundNew = true;
        }
      }
    }

    check(_prevPlayerField, _engine.playerField, false);
    check(_prevEnemyField, _engine.enemyField, true);
    _prevPlayerField = List.of(_engine.playerField);
    _prevEnemyField = List.of(_engine.enemyField);
    if (foundNew && !_fxKo.isAnimating) {
      _fxKo.forward(from: 0).whenComplete(() {
        if (mounted) setState(_koPlaying.clear);
      });
    }
  }

  /// Reads the engine's per-action events: pops a floating number for each,
  /// drives the impact pulse + haptic off the struck target, and — the
  /// returned Future — says when that presentation is actually DONE, so the
  /// caller can hold the next action back until it is.
  ///
  /// EVERY action gets the lunge and its full duration now, heals and
  /// buffs included (user 2026-08-29: "Die Aktionen die kein Struck event
  /// sind, sollen auch eine Animation erhalten und dauern") — before this, an
  /// action with nothing to strike (every event a heal, or a status tick
  /// with no target reacting) returned instantly: no motion, no time taken,
  /// so it looked like the turn had SKIPPED rather than like something had
  /// happened. Only an actual hit/miss also plays the target's flinch
  /// (`reacts` on [_playHit]) and the attack sound — a heal has nothing to
  /// flinch FROM.
  Future<void> _consumeCombatEvents() async {
    final events = _engine.lastEvents;
    if (events.isEmpty) return;
    if (_engine.outcome != null) return;
    CombatEvent? struck; // first damage/miss on a target = who reacts
    CombatEvent? first;
    var sawBuff = false;
    var sawDebuff = false;
    var sawCharging = false;
    for (final e in events) {
      _spawnFloat(e);
      first ??= e;
      if (!e.heal && (e.miss || e.amount > 0)) struck ??= e;
      if (e.buff) sawBuff = true;
      if (e.debuff) sawDebuff = true;
      if (e.charging) sawCharging = true;
    }
    final s = struck ?? first;
    if (s == null) return;
    final isHit = struck != null;
    // A buff always rides the actor's OWN lunge (a self-buff's "target" IS
    // the actor); a debuff always rides the struck target's react — see
    // [_fxStatusKind]'s doc. If a single action somehow carried both (it
    // never does today: buff-kind abilities don't also inflict debuffs),
    // debuff wins, since it lines up with the phase ([_fxTarget]) that
    // exists regardless of whether this action even reacts. A charging
    // event never shares an action with anything else (see CombatEngine's
    // _endTurn), so it needs no such tie-break.
    _fxStatusKind = sawDebuff
        ? _StatusFx.debuff
        : sawBuff
        ? _StatusFx.buff
        : sawCharging
        ? _StatusFx.charging
        : _StatusFx.none;
    if (isHit) {
      _fxImpact = (s.miss || s.element == CreatureElement.neutral)
          ? Colors.white
          : s.element.color;
      // Timed to the lunge's OWN forward swing, not to the moment the event
      // arrived (user 2026-08-29: "beim nach vorne gehen kommt der Angriff
      // sound") — see _kLungeWindupFraction, the single constant both this
      // and _lungeCurve read. Fire-and-forget: audio finishing is not part
      // of what the caller waits on.
      Future.delayed(_fx.duration! * _kLungeWindupFraction, () {
        if (mounted) Feel.attackSound(s.element);
      });
      if (!s.miss) {
        s.crit ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
      }
    }
    // s.actor, not _engine.currentActor read later inside _playHit — the
    // engine's turn cursor can already have moved on to whoever's next by
    // the time that runs (user 2026-08-29, confirming their own suspicion:
    // "vermutlich ist es so, dass meine Monster die Vorwärtsanimation
    // machen, wenn der Gegner angreift"). An action that empties its actor's
    // AP ends that actor's turn and advances CombatEngine's _acting BEFORE
    // notifyListeners() fires (see CombatEngine._afterAction/
    // _finishActorTurn) — reading currentActor from inside this
    // synchronous listener callback could already be capturing the NEXT
    // actor, often a player monster, and lunging IT instead of whoever
    // actually just struck. CombatEvent.actor exists for exactly this (see
    // its own doc) and was already used correctly for the log icon; this
    // was the one remaining place still re-deriving "who acted" from live
    // state instead of reading it off the event.
    await _playHit(target: s.target, actor: s.actor, reacts: isHit);
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
    // A real hit that rounds down to 0 damage still needs to render if it
    // carries a "Resisted"/"Super effective!" tag via typeMult — that tag is
    // the whole point of the hit. A genuine 0-damage no-op (typeMult == 1.0,
    // nothing to say) still has nothing worth showing.
    if (!e.miss && !e.heal && e.amount <= 0 && e.typeMult == 1.0) return;
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
    // "Critical!" alongside the effectiveness tag, not instead of it (user
    // 2026-08-29: "kritische Treffer... im Kampf speziell hervorheben, falls
    // dies nicht schon der Fall ist") — a crit already got a bigger, gold
    // number and a heavier haptic, but nothing SAID it was a crit; a hit
    // that was both critical AND super-effective reads as one, not either.
    final tagParts = <String>[
      if (e.crit) 'Critical!',
      if (e.typeMult > 1.0)
        'Super effective!'
      else if (e.typeMult < 1.0)
        'Resisted',
    ];
    final tag = (e.heal || e.miss || tagParts.isEmpty)
        ? null
        : tagParts.join(' · ');
    _floats.add(
      _FloatText(
        id: id,
        text: text,
        color: color,
        scale: scale,
        onEnemy: !e.target.isPlayerSide,
        alignX: _slotAlignX(e.target),
        tag: tag,
      ),
    );
    // The rising crosses (user 2026-09-15) ride ALONGSIDE the "+N" number,
    // not instead of it — three, lightly staggered, so it reads as a little
    // burst rather than one glyph.
    if (e.heal && e.amount > 0) {
      final alignX = _slotAlignX(e.target);
      final onEnemy = !e.target.isPlayerSide;
      for (var i = 0; i < 3; i++) {
        _healCrosses.add(
          _HealCross(
            id: _healCrossSeq++,
            alignX: alignX,
            onEnemy: onEnemy,
            xJitter: (i - 1) * 0.05,
            delay: Duration(milliseconds: i * 130),
          ),
        );
      }
    }
  }

  void _removeFloat(int id) {
    if (!mounted) return;
    setState(() => _floats.removeWhere((f) => f.id == id));
  }

  void _removeHealCross(int id) {
    if (!mounted) return;
    setState(() => _healCrosses.removeWhere((f) => f.id == id));
  }

  /// The attacker's lunge, then — only once it's done — the struck monster's
  /// shake+flash. Sequential on purpose (user 2026-08-29: "zunächst muss die
  /// Angriffsanimation kommen, wenn diese fertig ist, kommt erst die
  /// Trefferanimation"): the impact is a REACTION to the swing landing, not
  /// something that happens at the same time as it. Both by identity, so the
  /// two neighbours standing beside them hold still.
  ///
  /// A buff or debuff SKIPS all of that (user 2026-08-29: "Bei Buffs oder
  /// Debuffs soll das Monster nicht hoch oder runter gehen. Nur die
  /// Striche") — [_fxStatusKind] being set overrides [reacts] entirely, even
  /// for a debuff riding a real hit: the sweep alone is the presentation.
  ///
  /// Returns once the presentation is fully finished — _consumeCombatEvents
  /// awaits this so the next action cannot be scheduled while this one is
  /// still on screen. [reacts] is false for a plain heal: the lunge alone is
  /// the whole gesture then, since there is nothing on the receiving end to
  /// flinch.
  Future<void> _playHit({
    required Combatant target,
    Combatant? actor,
    bool reacts = true,
  }) async {
    // try/finally so EVERY exit path — including the early `!mounted`
    // return — clears this; see its own doc for why that matters.
    _presenting = true;
    try {
      _fxLungeTarget = target;
      if (_fxStatusKind != _StatusFx.none) {
        await _fxStatus.forward(from: 0);
        if (mounted) {
          setState(() {
            _fxLungeTarget = null;
            _fxStatusKind = _StatusFx.none;
          });
        }
        return;
      }
      // [actor] — from the CombatEvent, not read fresh off the engine here.
      // CombatEngine's turn cursor (currentActor) can already have advanced
      // to whoever's next by the time this synchronous listener callback
      // runs — an action that empties its actor's AP ends that actor's turn
      // immediately, before notifyListeners() even fires (user 2026-08-29,
      // confirming their own read: "vermutlich ist es so, dass meine
      // Monster die Vorwärtsanimation machen, wenn der Gegner angreift" —
      // this was it: currentActor had already become the PLAYER's next
      // monster, so that one lunged instead of the enemy that actually
      // struck). The `?? _engine.currentActor` is only a safety net for the
      // rare event with no actor recorded; every real attack/ability/charge
      // path sets one (see CombatEvent.actor's own doc).
      _fxActor = actor ?? _engine.currentActor;
      await _fx.forward(from: 0);
      if (!mounted) return;
      setState(() {
        _fxActor = null;
        _fxLungeTarget = null;
        if (reacts) _fxTarget = target;
      });
      if (!reacts) return;
      await _fxReact.forward(from: 0);
      if (mounted) setState(() => _fxTarget = null);
    } finally {
      _presenting = false;
    }
  }

  // This is now the QUIET BEAT after a presentation has fully finished, not a
  // number racing the animation (see _onEngineChanged) — lengthened on top of
  // that fix (user 2026-08-29: "Gerne die Pausen zwischen den Aktionen noch
  // verlängern, damit es übersichtlicher wird"), was 700ms.
  //
  // THIS is the "loading time" now (user 2026-08-29: "Manchmal kommt ein
  // Ladebalken mit enemys turn. Dies bitte nicht einblenden und die
  // Ladezeit vor jeder Aktion des Gegners einbauen... die Pause/Ladezeit
  // vor jeder Aktion des Gegners gleich halten") — the "Enemy is acting"
  // spinner (_turnStatus, since removed) read as a variable-length loading
  // state when what was actually running underneath it was already this
  // exact fixed timer, every single time. Deleting the spinner and keeping
  // the timer is the fix: the same pause was always there, it just used to
  // look like it might not be.
  static const Duration _kAutoActionPause = Duration(milliseconds: 1100);

  // Enemy turns always run automatically; player turns only with the auto
  // toggle. One timer at a time — every engine change reschedules.
  void _scheduleAutoIfNeeded() {
    _autoTimer?.cancel();
    if (_engine.outcome != null) {
      _applyOutcome();
      return;
    }
    // The tutorial's own concept explainer (user 2026-09-06: the enemy's
    // next hit must not land while its text box is still covering the
    // screen) — held here rather than only inside the timers below because
    // this function can fire WHILE the switch statement that sets
    // [_scriptInfoHint] is still racing it (see [_useAbility]'s own doc on
    // that race). Re-armed by [_dismissScriptInfo] the instant the player
    // taps it away.
    if (_scriptInfoHint != null) return;
    // An empty player slot pauses everything — the deck shows "Send in a
    // reserve" and nobody acts until one is. With AUTO on, that pick is one the
    // player already handed over, so it fills itself.
    if (_engine.needsPlayerSwitch) {
      if (_autoBattle) {
        _autoTimer = Timer(_kAutoActionPause, () {
          if (!mounted || !_engine.needsPlayerSwitch) return;
          // Belt and braces (user 2026-08-29: "wenn ich mit meinem Monster
          // angreife, greift parallel dazu bereits das gegnerische
          // Monster an") — this timer is only ever STARTED once the
          // previous action's presentation has already finished, but if
          // something manages to still have one running when it FIRES
          // (this call is the only place that dispatches an actual game
          // action, so it is the one place that actually matters to
          // guard), reschedule instead of firing into it and racing the
          // shared _fx/_fxReact controllers.
          if (_presenting) {
            _scheduleAutoIfNeeded();
            return;
          }
          _engine.autoSwitchIn();
        });
      }
      return;
    }
    final actorIsPlayer = _engine.isPlayerTurn;
    // PvP: the "enemy" is a real second human — their actions arrive via
    // _applyRemoteAction (pvp_sync_service.dart), never performAutoAction.
    // Nothing to schedule here while it's their turn; just wait.
    if (widget.isPvp && !actorIsPlayer) return;
    if (!actorIsPlayer || _autoBattle) {
      _autoTimer = Timer(_kAutoActionPause, () {
        if (!mounted || _engine.outcome != null || _engine.needsPlayerSwitch) {
          return;
        }
        if (_presenting || _scriptInfoHint != null) {
          _scheduleAutoIfNeeded();
          return;
        }
        if (_isFirstBattleTutorial) {
          _runScriptedEnemyBeat();
        } else {
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
    if (widget.isPvp) {
      await _applyPvpOutcome();
      return;
    }
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

  /// PvP's own outcome handling — reports the result and my own rating
  /// change (see PvpService's own doc on why a client can only ever write
  /// its OWN `pvp_stats` row). Deliberately grants no XP and no daily-task
  /// credit: a PvP fight's reward is the rating, not the PvE pool.
  Future<void> _applyPvpOutcome() async {
    final myId = supabase.auth.currentUser!.id;
    final match = widget.pvpMatch!;
    final winnerId = switch (_engine.outcome!) {
      CombatOutcome.victory => myId,
      CombatOutcome.defeat => match.otherUserId(myId),
      CombatOutcome.fled => _pvpOpponentFled ? myId : match.otherUserId(myId),
    };
    await _pvpService.finishMatch(match, winnerId);
    final finished = await _pvpService.loadMatch(match.id);
    await _pvpService.syncMyRatingAfterMatch(finished);
  }

  // Offensive actions go to the SELECTED enemy (user 2026-07-27) — [_target],
  // which the player sets by tapping a monster on the enemy half and which
  // falls back to the first of the pack. Ally/self abilities still resolve to
  // the caster: choosing an ally to heal would want its own tap mode, and every
  // heal in the game is a self-heal today.
  //
  // ONE entry point for every tile now, Attack included (user 2026-09-03:
  // "attack soll eine normale Fähigkeit sein") — there is no separate
  // _attack() any more; the tutorial's own "tackle" beat is just another
  // case in the switch below, guarded on which ability actually fired
  // (though in practice only Attack's tile is ever enabled while that beat
  // is live — see [_scriptedBattleAnchor]).
  Future<void> _useAbility(AbilityDef ability) async {
    final actor = _engine.currentActor;
    final target = switch (ability.target) {
      AbilityTarget.enemy || AbilityTarget.allEnemies => _target,
      _ => actor,
    };
    // Document's own figures (user 2026-09-04), set BEFORE the real engine
    // call so [CombatEngine.scriptedNextHit] lands them as the actual hit —
    // floating number and log line included — not just a value patched into
    // HP after the fact. Both fighters open the fight on exactly 12 HP
    // (forced in initState), so every flat number below reproduces the
    // document's HP column exactly.
    if (_scriptBeat == _ScriptBeat.tackle && ability.id == 'attack') {
      _engine.scriptedNextHit = (damage: 3, miss: false);
    } else if (_scriptBeat == _ScriptBeat.missedAttack) {
      // Forced Miss (user 2026-09-05: was a scripted "Resisted" 0, now a
      // scripted Miss) — same reason the 0 was flat rather than real in the
      // first place: the enemy's HP has to stay exactly where tackle left
      // it, same as every other player hit here, and a miss does that for
      // free instead of needing a tagged 0-damage hit.
      _engine.scriptedNextHit = (damage: 0, miss: true);
    } else if (_scriptBeat == _ScriptBeat.powerAttack) {
      _engine.scriptedNextHit = (damage: 5, miss: false);
    } else if (_scriptBeat == _ScriptBeat.finisher &&
        actor.abilities.indexOf(ability) == 2) {
      _engine.scriptedNextHit = (damage: 4, miss: false);
    }
    // Fixed by TILE POSITION, not by beat or by this starter's own real
    // price (user 2026-09-05: "oben links attack 2 ap / oben rechts
    // Elementattacke 2 ap / unten links Elementattacke 4 ap / unten rechts
    // Buff 2 ap. Das ist bei allen Startermonster über das gesamte
    // Tutorial genau so.") — see _effectiveApCost's own doc for the table.
    final fixedCost = _tutorialTileApCost(actor, ability);
    if (fixedCost != null) _engine.scriptedApCost = fixedCost;
    final error = _engine.useAbility(actor, ability, target);
    if (error != null) {
      _showError(error);
      return;
    }
    _relayPvpAction(
      kind: ability.id == 'attack' ? 'attack' : 'ability',
      actor: actor,
      abilityId: ability.id == 'attack' ? null : ability.id,
      target: target,
    );
    // Let the hit actually PLAY (lunge, reaction, floating number) before
    // the next scripted prompt appears (user 2026-09-03: "bitte alle
    // Animationen abwarten, bevor der nächste Tutorialinput kommt, sonst
    // kann ich nicht verfolgen, was passiert") — without this, _scriptBeat
    // (and the spotlight/hint it drives) jumped to the next beat the
    // instant the engine call returned, well before _onEngineChanged's own
    // async _consumeCombatEvents had finished presenting THIS one.
    if (_scriptBeat != null) await _waitForPresentation();
    switch (_scriptBeat) {
      case _ScriptBeat.tackle when ability.id == 'attack':
        setState(() => _scriptBeat = _ScriptBeat.enemyBigHit);
      case _ScriptBeat.missedAttack:
        setState(() {
          _scriptBeat = _ScriptBeat.enemyDebuffHit;
          _scriptInfoHint =
              'Miss — every attack has a small chance to '
              'miss entirely, no matter how strong it is.';
        });
      case _ScriptBeat.powerAttack:
        setState(() {
          _scriptBeat = _ScriptBeat.bankEndTurn;
          _scriptInfoHint =
              'Not very effective — the wrong type deals '
              'less damage.';
        });
      case _ScriptBeat.finisher when actor.abilities.indexOf(ability) == 2:
        _flashMessage('💥 Critical Hit!');
        // The real engine has already detected victory (enemy HP hit 0) by
        // this point — [_endOverlay] just waits for [_scriptInfoHint] to
        // clear before it shows (see build()).
        setState(() {
          _scriptBeat = null;
          _scriptInfoHint =
              'Critical hit! Every attack has a small chance '
              'to land extra hard.';
        });
      default:
        break;
    }
  }

  /// Waits until the CURRENT action's presentation (lunge, hit reaction,
  /// floating number) has actually finished playing — see [_presenting]'s
  /// own doc for why the engine's turn/notify state flips well before that.
  /// A frame's grace up front lets the engine's own notifyListeners →
  /// _onEngineChanged → _consumeCombatEvents chain (synchronous up to its
  /// first real suspension point) actually SET [_presenting], so checking
  /// immediately here can't race a "hasn't started yet" false negative.
  Future<void> _waitForPresentation() async {
    await Future<void>.delayed(Duration.zero);
    while (mounted && _presenting) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  /// Wraps [ability]'s tile in the scripted fight's own anchor — Attack
  /// always gets 'battle-attack-btn' (user 2026-09-03: now just its own
  /// entry in the same list, not a separate hardcoded tile), whichever
  /// ability [firstReal] names (see [_firstRealAbility]) gets
  /// 'battle-first-ability', and [secondReal] (see [_secondRealAbility])
  /// gets 'battle-second-ability'. None of these anchors do anything
  /// outside the tutorial's first fight — [_scriptedBattleAnchor] is what
  /// actually decides which one is lit.
  Widget _maybeAnchoredAbilityTile(
    AbilityDef ability,
    AbilityDef? firstReal,
    AbilityDef? secondReal,
    Widget tile,
  ) {
    final anchor = ability.id == 'attack'
        ? 'battle-attack-btn'
        : (firstReal != null && ability.id == firstReal.id
              ? 'battle-first-ability'
              : (secondReal != null && ability.id == secondReal.id
                    ? 'battle-second-ability'
                    : null));
    return anchor == null
        ? tile
        : KeyedSubtree(key: IntroSpotlightAnchors.of(anchor), child: tile);
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
                forced
                    ? 'Your monster fainted — send in a reserve'
                    : 'Switch monster (free — costs no turn)',
                style: FoE.title(size: 14),
              ),
              const SizedBox(height: 12),
              for (final c in bench)
                Pressable(
                  onTap: () => Navigator.pop(context, c),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    // all(12), not all(10) (2026-08-31 audit) — matching
                    // this sheet's own sibling row below ("Use an item"),
                    // the same selectable-row shape.
                    padding: const EdgeInsets.all(12),
                    decoration: FoE.panel(radius: 8),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: _portrait(c, size: 28)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${c.element.emoji} ${c.name} · Lv ${c.level}',
                                style: FoE.label(size: 13),
                              ),
                              const SizedBox(height: 4),
                              _bar(
                                c.hp / c.maxHp,
                                FoE.positive,
                                '${c.hp}/${c.maxHp}',
                              ),
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
    if (err != null) {
      if (mounted) _showError(err);
      return;
    }
    _relayPvpAction(kind: 'switch', actor: chosen);
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

  // ── ONE LOOK (user 2026-08-01: "designe den Kampfscreen komplett neu, so
  // dass er modern wirkt, aber trotzdem den gleichen Stil verfolgt") ──
  //
  // There were TWO designs in this file behind a `polished` flag — a flat
  // original and a glossier one — and every surface carried both branches. That
  // is how a screen stops having a style: half the decisions are made twice, and
  // the one nobody looks at rots. The flag, its toggle button and every branch
  // are gone; what is left is the app's own language, faceted and dark.

  // ── The screen's two surfaces ─────────────────────────────
  // The monsters are FLAT-coloured art, so the chrome is too: the tray and the
  // slabs on it are one tone each, separated by a STEP rather than by a
  // hairline, and lit along the edge that faces you (FoE.lit). Gold stays the
  // one accent, so the vivid element colours keep the field to themselves.
  static const Color _flatSurface = FoE.panelDark; // trays, cards, log
  static const Color _flatSurfaceHi = FoE.panelMid; // raised surface

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
          // Held back while a [_scriptInfoHint] is still showing (user
          // 2026-09-04: the finisher's crit explainer must not fight the win
          // screen for the same pixels) — the real engine has usually
          // already recorded the outcome by this point regardless.
          if (_engine.outcome != null && _scriptInfoHint == null) _endOverlay(),
          // Undimmed (user 2026-09-03: "ich möchte aber, dass der gesamte
          // screen erhellt ist, damit ich das Kampfgeschehen verfolgen
          // kann") — the battle itself is worth watching (HP bars, hit
          // reactions, floating numbers) even while only one control is
          // actually pressable; a dark scrim over all of that just hid it.
          if (_battleCallout != null)
            IntroSpotlightOverlay(
              anchorName: _battleCalloutAnchors[_battleCallout!],
              hint: _battleCalloutHints[_battleCallout!],
              onScrimTap: _advanceBattleCallout,
              dim: false,
              // The HP ring is round, so its own glow frame should be too
              // (user 2026-09-04: a facet border around the podium's own
              // circle read as boxing in far more than just the ring).
              circular: _battleCalloutAnchors[_battleCallout!] == 'battle-hp',
            ),
          // No onScrimTap — unlike the four explanatory callouts above,
          // each of these three is a real action the player has to actually
          // perform (user 2026-09-03's "gescriptet"), not a fact to
          // dismiss. Held back while a [_scriptInfoHint] is showing (the
          // beat underneath has usually already advanced by then) so the
          // two don't glow two different controls at once.
          if (_scriptInfoHint == null && _scriptedBattleAnchor != null)
            IntroSpotlightOverlay(
              anchorName: _scriptedBattleAnchor!,
              hint: _scriptedBattleHint,
              dim: false,
            ),
          // The scripted fight's own concept explainers — effectiveness,
          // miss, buffs, "not very effective", crit (user 2026-09-04) — one
          // beat's worth of narration, dismissed by tap like the four
          // opening callouts. Anchored to the HP ring for lack of a more
          // specific target; what matters is the text, not the hole.
          if (_scriptInfoHint != null)
            IntroSpotlightOverlay(
              anchorName: 'battle-hp',
              hint: _scriptInfoHint,
              onScrimTap: _dismissScriptInfo,
              dim: false,
            ),
        ],
      ),
    );
    return PopScope(
      canPop: _engine.outcome != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmFlee();
      },
      child: Scaffold(
        // The arena paints its own place (see BattleScene); everything around
        // it is the app's page.
        backgroundColor: FoE.bg,
        // A small camera shake on every hit (user request) — rides
        // [_fxReact], the struck monster's OWN flinch pulse, so it needs no
        // timer of its own and lands in lockstep with it. Was [_fx] (the
        // attacker's lunge) before [_fx] and [_fxReact] were split into two
        // separate controllers (user 2026-08-29: sequencing attack-then-hit)
        // — left pointed at the wrong one, the whole screen was jolting
        // during the SWING instead of the IMPACT, which is likely what read
        // as "das getroffene Monster geht hoch und runter" even though the
        // monster's own shake was already purely horizontal. Whole screen,
        // not just the arena: top bar and action panel jolt with it, which is
        // what reads as the CAMERA moving rather than one sprite.
        body: AnimatedBuilder(
          animation: _fxReact,
          builder: (context, child) {
            final t = _fxReact.value;
            final shake = _fxReact.isAnimating
                ? math.sin(t * math.pi * 10) * 3 * (1 - t)
                : 0.0;
            return Transform.translate(offset: Offset(shake, 0), child: child);
          },
          child: body,
        ),
      ),
    );
  }

  /// The floating combat numbers, drawn over everything but the overlays. Each
  /// is anchored over the monster it belongs to: its side decides the height,
  /// its SLOT the horizontal position (user 2026-07-27 — a spread move now hits
  /// three at once, and three numbers stacked in the middle of the half would
  /// say nothing about who took what). A small per-id nudge keeps two numbers
  /// in the same slot from landing exactly on top of each other.
  ///
  /// Nudged right of that slot now, not centred on it (user 2026-08-29: "Die
  /// Schadenszahl soll rechts nahe dem Monster sein", then again once more
  /// clearly: "Die Schadenszahlen sollen rechts von dem Monster sein" — 0.16
  /// read as barely offset at all, so this is a real step right, not a
  /// nudge) — still close enough to read as THIS monster's number, not
  /// drifting toward its neighbour's slot.
  static const double _kFloatRightOffset = 0.34;

  Widget _floatsLayer() => Positioned.fill(
    child: IgnorePointer(
      child: Stack(
        children: [
          for (final f in _floats)
            Align(
              alignment: Alignment(
                (f.alignX + _kFloatRightOffset + ((f.id % 3) - 1) * 0.05).clamp(
                  -1.0,
                  1.0,
                ),
                f.onEnemy ? -0.42 : 0.16,
              ),
              child: _FloatingNumber(
                key: ValueKey(f.id),
                data: f,
                onDone: () => _removeFloat(f.id),
              ),
            ),
          for (final c in _healCrosses)
            Align(
              alignment: Alignment(
                (c.alignX + c.xJitter).clamp(-1.0, 1.0),
                c.onEnemy ? -0.42 : 0.16,
              ),
              child: _RisingCross(
                key: ValueKey(c.id),
                data: c,
                onDone: () => _removeHealCross(c.id),
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
        shape: FoE.facet(
          radius: 12,
          side: const BorderSide(color: FoE.borderGold),
        ),
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
    if (ok == true) {
      final actor = _engine.currentActor;
      _engine.flee();
      // PvP: fleeing is a forfeit — the opponent's own engine only learns
      // the fight is over if this is relayed like any other action (flee
      // has no actor/target of its own; [actor] just satisfies the
      // message's shape, [_applyRemoteAction] ignores it for this kind).
      _relayPvpAction(kind: 'flee', actor: actor);
    }
  }

  // ── Inline catch mini-game (user 2026-07-18) ──────────────
  /// Whether the Catch button is live: a capture battle, the player's turn,
  /// enough AP for the attempt, the SELECTED wild (user 2026-09-11: catch
  /// can now target any of up to 3 fielded wilds, not just "the" one — see
  /// [_target]) alive and worn DOWN into its catchable band (fighting it
  /// lower widens the ring). Overkilling it, the wrong turn, or not enough
  /// AP greys the button out.
  bool get _canCatch {
    // Non-null just means "this is a capture battle at all" now (2026-09-11)
    // — the actual threshold is per-wild (rarer finds must be brought
    // lower), read straight off whichever is SELECTED via [catchHpThreshold],
    // since a hunt can field wilds of different rarities at once.
    if (!widget.isCapture ||
        _catchOpen ||
        _engine.outcome != null ||
        !_engine.isPlayerTurn) {
      return false;
    }
    if ((_engine.activePlayer?.ap ?? 0) < kCatchApCost) return false;
    final wild = _target;
    if (wild == null || !wild.alive) return false;
    final frac = wild.maxHp <= 0 ? 0.0 : wild.hp / wild.maxHp;
    return frac <= catchHpThreshold(wild.rarity);
  }

  /// Opens the catch QTE overlay against the currently SELECTED wild (user
  /// 2026-09-11 — was always "the" lone enemy before hunts fielded several
  /// at once): the ring sizing (speed + golden band) comes from the wild's
  /// rarity, how deep it was fought, and the active catcher's catchRate
  /// (switch your catcher in to widen it). AP for the attempt is spent once
  /// it resolves (miss or success), not here — see [_resolveCatchAttempt].
  void _startCatch() {
    final wild = _target;
    if (wild == null || !_canCatch) return;
    _catchWild = wild;
    _catcher = _engine.activePlayer;
    final rarity = wild.rarity;
    final catchRate = _catcher?.stat(CreatureStat.catchRate) ?? 0;
    final hpFraction = wild.maxHp <= 0 ? 0.0 : wild.hp / wild.maxHp;
    _catchSpecies = wild.speciesId == null
        ? null
        : kSpeciesDefs[wild.speciesId];
    _catchHits = 0;
    _catchHitsNeeded = qteHitsRequired(rarity);
    _catchWindow = qteWindow(
      rarity,
      hpFraction: hpFraction,
      catchRate: catchRate,
    );
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

  /// A failed attempt: the wild slips free, the overlay closes, and the AP
  /// is spent regardless (user 2026-09-11: trying to catch now costs the
  /// same AP whether or not it lands — see CombatEngine.attemptCatch). The
  /// fight goes on either way — it always did for a miss, but now for a hit
  /// too (see [_catchSucceed]).
  void _catchMiss() {
    if (_catchResolving) return;
    _catchResolving = true;
    _ring.stop();
    final name = _catchWild?.name ?? 'It';
    setState(() {
      _catchOpen = false;
      _catchBetween = false;
    });
    _flashMessage('💨 $name slipped free!');
    _resolveCatchAttempt();
  }

  /// A caught wild: removed from the fight outright (CombatEngine.catchEnemy
  /// — no kill XP, the catch is the reward, and it can never be targeted
  /// again) and banked in [_caught]. The AP for the attempt is spent exactly
  /// like a miss — a catch no longer ends the whole battle (2026-09-11):
  /// with up to 3 wilds fielded from a hunt's find queue at once, there may
  /// be more still to fight or catch. The battle's own outcome (and this
  /// screen's normal end-of-fight pop) resolves on its own once every
  /// fielded-and-benched wild is gone, via the same path every other battle
  /// already uses.
  void _catchSucceed() {
    if (_catchResolving) return;
    _catchResolving = true;
    _ring.stop();
    final wild = _catchWild;
    setState(() {
      _catchOpen = false;
      _catchBetween = false;
    });
    if (wild != null) {
      _engine.catchEnemy(wild);
      _caught.add(wild);
    }
    _resolveCatchAttempt();
  }

  /// Shared tail for a miss or a success: spends the attempt's AP through
  /// the engine's normal action economy (the turn continues if AP remains,
  /// ends otherwise — exactly like an attack) at the same point [endTurn]
  /// used to be called — AFTER the ring overlay has already closed, so an
  /// enemy can never act while it's still on screen.
  void _resolveCatchAttempt() {
    final catcher = _catcher;
    if (catcher != null && _engine.isPlayerTurn) {
      _engine.attemptCatch(catcher);
    }
    _catchWild = null;
    _catcher = null;
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
    // Grown from 44 to fit the bigger turn-order cards (user request).
    height: 58,
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
          Expanded(
            child: KeyedSubtree(
              key: IntroSpotlightAnchors.of('battle-turnorder'),
              child: _initiativeStrip(),
            ),
          ),
          const SizedBox(width: 6),
          // Same tint as the other deck buttons (user request); the ✔ marks it on.
          // Disabled for the tutorial's scripted first fight (user: "der auto
          // button funktioniert während des tutorials, was alles zerstört")
          // — AUTO hands the PLAYER's own turns to performAutoAction(), the
          // real, un-scripted AI, which the whole authored beat sequence
          // (and its HP=12/scriptedNextHit numbers) assumes never runs here.
          _deckButton(
            icon: Icons.smart_toy,
            label: _autoBattle ? 'AUTO ✔' : 'AUTO',
            base: _kUtilTint,
            // Off in PvP (user 2026-09-15): AUTO hands the player's own
            // turns to performAutoAction(), the local PvE AI — meaningless
            // and misleading against a real second human.
            enabled: !_isFirstBattleTutorial && !widget.isPvp,
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
  // A compact "what beats what" chart (user request). 2026-09-07: was an
  // inline collapsible strip; now a single tap opens the full-size overlay
  // (see showTypeCircleDialog) — "das müsste viel grösser sein... mache
  // bitte ein Overlaymenü wie der Buildingdetailscreen". The overlay draws
  // the live 8-type matrix (CreatureElement, since 2026-09-08).
  Widget _typeChart() => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => showTypeCircleDialog(context),
    child: Container(
      color: FoE.bg,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.hexagon_outlined, size: 13, color: FoE.textDim),
          const SizedBox(width: 6),
          Text('Type chart', style: FoE.dim(size: 11)),
          const SizedBox(width: 4),
          Icon(Icons.open_in_full, size: 12, color: FoE.textDim),
        ],
      ),
    ),
  );

  // ── Turn order (CTB queue) ────────────────────────────────
  /// Who acts next, as faceted cards between Flee and AUTO (redesign
  /// 2026-08-01).
  ///
  /// It was a row of portraits with a gold CIRCLE around the current one and a
  /// coloured underline for the side. Three problems, all of them style: a
  /// circle is the shape this app cannot make, an underline is a fourth way of
  /// saying "side" on a screen that already says it by position, and the queue
  /// read as a strip of stickers rather than as part of the bar.
  ///
  /// Now each fighter is a small slab cut from the bar, tinted by SIDE, and the
  /// one acting is the tall one with a lit edge — size and light rather than a
  /// ring. Nothing else marks it, because nothing else needs to.
  Widget _initiativeStrip() => LayoutBuilder(
    builder: (context, box) {
      // BIGGER cards, FEWER of them (user request) — the queue used to trade
      // size for count, cramming up to twelve thumbnails into the strip. Six
      // is plenty to plan around; the width that freed up goes into cards you
      // can actually read at a glance.
      const slot = 44.0;
      const gap = 6.0;
      final fit = ((box.maxWidth + gap) / (slot + gap)).floor().clamp(1, 6);
      // Frozen while a presentation is still playing (user 2026-08-29: "es
      // ist noch immer so, dass manche gegnerische Monster vorgreifen") —
      // forecast() reads the engine's CURRENT queue, which can already have
      // advanced past the action still being shown on screen (an action that
      // ends its actor's turn moves the queue on immediately, well before
      // that action's own lunge/react has finished playing). Recomputing
      // this live put the next — often enemy — fighter at the front of the
      // strip before its predecessor's animation was actually done, which is
      // the same premature reveal the acting-glow fix addressed for the
      // sprites themselves, just on this bar instead.
      final order = _presenting
          ? (_lastSettledOrder ??= _engine.forecast(fit))
          : (_lastSettledOrder = _engine.forecast(fit));
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < order.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            _queueCard(order[i], acting: i == 0),
          ],
        ],
      );
    },
  );

  /// One place in the queue. [acting] is the fighter whose turn it is.
  Widget _queueCard(Combatant c, {required bool acting}) {
    final side = c.isPlayerSide ? FoE.positive : FoE.danger;
    return Container(
      width: acting ? 44 : 38,
      height: acting ? 50 : 42,
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(
        // The side, as the card's own tint — no extra bar to read.
        color: side.withValues(alpha: acting ? 0.30 : 0.16),
        shape: FoE.facet(
          radius: 8,
          side: BorderSide(
            color: acting ? FoE.lit(side) : side.withValues(alpha: 0.45),
            width: acting ? 2 : 1,
          ),
        ),
      ),
      child: _portrait(c, size: acting ? 38 : 32),
    );
  }

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
          // Shrunk to the old formula's OWN floor when there is no bench
          // (user request: bigger monsters) — an empty strip was costing
          // every fighter the same height whether or not anyone was waiting
          // in it — but never below that floor: on the player's rank this
          // band is also what keeps the nameplate clear of the action deck
          // below it, and going lower than 16 let the deck cover the name
          // (user 2026-08-27: "Der Name wird verdeckt").
          final reserve = bench.isEmpty ? 16.0 : (h * 0.16).clamp(16.0, 44.0);
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
                // ── ONLY THE OCCUPIED SLOTS, CENTRED (user 2026-08-04) ──
                // Three Expanded cells were laid out whether or not anyone
                // stood in them, so a lone survivor kept the seat it started
                // in — a single monster stranded on the left of an empty rank.
                //
                // The WEDGE only means anything with three: it says "the middle
                // one has stepped forward", and with two there is no middle,
                // just two monsters at different heights for no reason. So the
                // step applies at three and the pair stands level.
                child: Builder(
                  builder: (_) {
                    final live = [
                      for (var i = 0; i < CombatEngine.kFieldSlots; i++)
                        // Also keeps a slot whose occupant just fainted in
                        // the row for the length of its K.O. presentation
                        // (user 2026-08-29) — otherwise the slot drops out of
                        // `live` and _fieldSlot is never even called for it
                        // again once the engine clears/refills it, which is
                        // exactly the moment the animation needs to run.
                        if ((field[i] != null && field[i]!.alive) ||
                            _koPlaying.values.any(
                              (e) => e.slot == i && e.isEnemy == isEnemy,
                            ))
                          i,
                    ];
                    final wedge = live.length == CombatEngine.kFieldSlots;
                    // This Row sits inside the Positioned's own left:2/
                    // right:2 inset, so its REAL available width is w - 4,
                    // not w — using raw w for 3 equal-width slots summed to
                    // exactly 4px more than the Row actually had (user
                    // 2026-08-29, seen live: "Am rechten Rand gibt es noch
                    // immer einen Overflow" — the console's own "overflowed
                    // by 4.0 pixels" matches this exactly).
                    final innerW = w - 4;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final i in live)
                          SizedBox(
                            // The slot keeps its full-rank width, so a monster
                            // is the same size whether one stands or three do.
                            width: innerW / CombatEngine.kFieldSlots,
                            child: Transform.translate(
                              // FORWARD is toward the seam: down for the enemy
                              // rank, up for mine.
                              offset: Offset(
                                0,
                                !wedge
                                    ? 0
                                    : (_isCentreSlot(i) ? step : -step * 0.5) *
                                          (isEnemy ? 1 : -1),
                              ),
                              child: _fieldSlot(
                                field[i],
                                slot: i,
                                isEnemy: isEnemy,
                                width: innerW / CombatEngine.kFieldSlots,
                                back: wedge && !_isCentreSlot(i),
                                // The HP callout points at ONE ring, not the
                                // whole rank (user 2026-09-04) — the leftmost
                                // live slot on MY side, same one that is
                                // always alone during the guided intro.
                                hpAnchor: !isEnemy && i == live.first,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // ENEMY reserve strip removed (user 2026-08-29: "Diese kleine
              // Kachel löschen" — the small bench-chip tile that floated
              // top-left over the green arena, easy to mistake for stray
              // UI since it carries no label connecting it to anything).
              // It was purely informational — the enemy's own bench isn't
              // tappable — so nothing is lost by dropping it; the PLAYER's
              // own reserve strip stays: that one IS how you switch in a
              // benched monster.
              if (bench.isNotEmpty && !isEnemy)
                Positioned(
                  bottom: 2,
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
  /// its own width — i.e. how deep the monster stands in it. Lower now (user
  /// 2026-08-29: "jetzt den Text näher an das Podest nehmen") — this lift is
  /// exactly the gap between the platform's own bottom and the nameplate
  /// right after it in the Column, so less lift is less gap. Not zero: the
  /// 2026-07-31 request this value first answered ("schiebe die plattformen
  /// weiter nach oben") is still real — a platform flush with the slot's own
  /// bottom read as floating above its ground, not standing in it.
  static const double _kPlatformLift = 0.10;

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
    // A flank stands further back, so it is drawn a little smaller: the size
    // difference is what makes the wedge read as DEPTH rather than as a rank
    // that failed to line up. Passed IN rather than derived from the slot,
    // because there is no wedge unless all three are standing — and a lone
    // monster in slot 0 must not be drawn as if it were hanging back from
    // company that is no longer there.
    required bool back,
    // Carries the 'battle-hp' spotlight anchor onto this slot's own HP ring
    // (user 2026-09-04) instead of the whole rank — only ever true for one
    // slot at a time, so it's the sole place [IntroSpotlightAnchors.of]
    // gets attached.
    bool hpAnchor = false,
  }) {
    // A K.O. in progress stands in for whatever is actually in this slot,
    // for the length of its own presentation (user 2026-08-29: "eine K.O
    // animation") — checked FIRST, ahead of [c], because the enemy side
    // auto-refills a fallen slot from its bench in the SAME engine tick
    // (see CombatEngine._resolveFaints): [c] can already be the fresh
    // arrival by the time this builds. The fainted one wins the slot until
    // its own animation finishes; the new arrival is simply what appears
    // once [_koPlaying] drops it.
    _KoEntry? ko;
    for (final e in _koPlaying.values) {
      if (e.slot == slot && e.isEnemy == isEnemy) {
        ko = e;
        break;
      }
    }
    final koing = ko != null;
    if (koing) {
      c = ko.combatant;
    } else if (c == null || !c.alive) {
      return const SizedBox.shrink();
    }
    // A plain non-nullable local from here on — Dart's own promotion of the
    // reassigned parameter doesn't reliably survive into the closures below.
    final Combatant c0 = c;
    // Held back while a presentation is still playing (user 2026-08-29:
    // "wenn ich mit meinem Monster angreife, greift parallel dazu bereits
    // das gegnerische Monster an") — the ENGINE's currentActor advances the
    // instant an action resolves, which can be well before that action's
    // own lunge/react has finished being SHOWN (a hit that empties the
    // actor's AP ends its turn immediately). Reading it live here meant the
    // next actor — often an enemy — started glowing "up next" while the
    // just-acted monster was still visibly mid-swing, reading as the two
    // attacking at once. Freezing the glow off until _presenting clears
    // means it only ever lands on the actor once the screen agrees the
    // previous action is actually done. A fainting monster never glows.
    final acting =
        !koing &&
        !_presenting &&
        identical(c0, _engine.currentActor) &&
        _engine.outcome == null;
    // Only while it's the PLAYER's own turn (user 2026-08-29: "sobald der
    // Gegner am Zug ist, muss der rote Schatten/Markierung für das
    // Anvisieren verschwinden") — [_target] itself stays set (so the choice
    // is remembered for when the turn comes back), only the marker's
    // visibility is gated.
    final targeted = isEnemy && identical(c0, _target) && _engine.isPlayerTurn;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: (isEnemy && !koing)
          ? () => setState(() => _targetId = c0.id)
          : null,
      // Long-press to size up a wild mid-fight (user 2026-09-14: "auch
      // während des Kampfes, will ich bei einem wilden Monster die Werte
      // ansehen können") — a plain tap already picks the attack target, so
      // the stat preview needs a gesture of its own rather than fighting it
      // for the same one.
      onLongPress: (isEnemy && !koing)
          ? () => openWildPreview(context, c0)
          : null,
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
                final raw = (_entry.value * 1.3 - slot * 0.12).clamp(0.0, 1.0);
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
                      key: hpAnchor
                          ? IntroSpotlightAnchors.of('battle-hp')
                          : null,
                      padding: EdgeInsets.only(
                        bottom: width * (back ? 0.82 : 0.92) * _kPlatformLift,
                      ),
                      child: TypePodium(
                        element: c0.element,
                        width: width * (back ? 0.82 : 0.92),
                        dim: back,
                        // Mirrored for the PLAYER's own monster (user
                        // 2026-08-28: "bei den eigenen Monster das Typicon
                        // gespiegelt auf der rechten Seite") — the enemy
                        // keeps the default left.
                        watermarkLeft: isEnemy,
                        // THE RIM IS THE HEALTH BAR (user 2026-07-31). The
                        // straight bar under the name is gone with it — two bars
                        // for one number is one bar too many.
                        hpFraction: c0.maxHp <= 0
                            ? 0.0
                            : (c0.hp / c0.maxHp).clamp(0.0, 1.0),
                        hpColor: _hpColor(
                          c0.maxHp <= 0
                              ? 0.0
                              : (c0.hp / c0.maxHp).clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                    _bigSprite(
                      c0,
                      back: !isEnemy,
                      height: box.maxHeight * (back ? 0.92 : 1.0),
                      acting: acting,
                      targeted: targeted,
                      koing: koing,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _slotPlate(c0, acting: acting, targeted: targeted, width: width),
          // Shifts the platform AND the nameplate up together (user
          // 2026-08-28: "Podest und Namensbox weiter nach oben schieben") —
          // a trailing spacer in a Column packed to `end` moves everything
          // BEFORE it up by exactly its own height, so the podium (bottom-
          // anchored inside the Expanded above) and the plate (the sibling
          // right after it) both rise the same amount without needing two
          // separate offsets that could drift apart.
          //
          // MINE more than the enemy's (user 2026-08-28, twice now: "beim
          // eigenen Monster noch etwas höher", then again "näher an das
          // Podest (höher)") — the player's own monster is what the fight
          // is actually about; the enemy's plate stays put.
          // Bumped again on both sides (user 2026-08-28: "Der Text näher an
          // das Podest schieben") — this time without the "own monster
          // only" qualifier earlier bumps had.
          //
          // Brought back down (user 2026-08-29: "Nur das Podest und den
          // Text etwas nach unten schieben. Die Monsterassets dort
          // belassen") — this spacer only moves the podium + plate (the
          // Column siblings before it), not the sprite itself, so it's the
          // right lever for "podium and text only": a smaller value here
          // means less upward push, i.e. both sit lower, with the sprite's
          // own position (set elsewhere, via [_kArenaDrop] and its own
          // Transform.scale) completely untouched.
          // A bit more again (user 2026-08-29: "noch ein bisschen mehr").
          SizedBox(height: isEnemy ? 10 : 26),
        ],
      ),
    );
  }

  /// The nameplate under one fighter (redesign 2026-08-01).
  ///
  /// It carried a name, a level and an HP fraction in two stacked rows, plus
  /// status icons — five things under each of six monsters. Health moved to the
  /// platform's rim on 2026-07-31 and the plate never lost the weight it was
  /// carrying for it.
  ///
  /// One row now: the name, then the numbers that decide whether one more hit
  /// finishes it. Status rides ABOVE the plate as a strip of marks, where it is
  /// read at a glance instead of competing with the name.
  ///
  /// The two states you act on are said by the plate's own EDGE — gold for the
  /// monster whose turn it is, red for the enemy you are aimed at — because a
  /// facet edge is what this app uses for "this one".
  Widget _slotPlate(
    Combatant c, {
    required bool acting,
    required bool targeted,
    required double width,
  }) {
    // One icon per ACTIVE effect (user 2026-09-08: "Buffs und Debuffs
    // besser erklären, damit ich genau weiss, was diese machen") — every
    // self-buff and secondary debuff now shows, not just haste/slowed's own
    // derived arrows (which hid armor/rage/blind/weakened/exposed
    // entirely). Tapping the strip explains each one in full — see
    // [_showActiveEffects].
    final marks = <Widget>[
      for (final e in c.selfBuffs.keys)
        Text(e.emoji, style: const TextStyle(fontSize: 10)),
      for (final e in c.secondaryDebuffs.keys)
        Text(e.emoji, style: const TextStyle(fontSize: 10)),
      if (c.mainStatus != null)
        Text(c.mainStatus!.emoji, style: const TextStyle(fontSize: 10)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The status strip, only when there is something to say.
        if (marks.isNotEmpty)
          Pressable(
            onTap: () => _showActiveEffects(c),
            child: Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: ShapeDecoration(
                color: FoE.bg.withValues(alpha: 0.65),
                shape: FoE.facet(radius: 5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: marks),
            ),
          ),
        // No more box, and the level in place of the HP numbers (user
        // 2026-08-28: "Lösche die HP Zahlen und die Box... Anstelle der HP
        // Zahlen bitte das Level") — the platform's own rim already IS the
        // HP bar (see TypePodium), so the plate isn't the only place it was
        // read.
        //
        // White, and the level on its OWN line under the name now (user
        // 2026-08-28, same day: "Die Namen und Level in Weiss, dafür das
        // Level unter dem Namen") — this also DROPS the acting/targeted
        // colour the text briefly carried in the box's ring's place; that
        // signal has no home here any more.
        Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: FoE.label(size: 11).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 2)],
          ),
        ),
        Text(
          'Lv ${c.level}',
          maxLines: 1,
          textAlign: TextAlign.center,
          style: FoE.label(size: 10).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 2)],
          ),
        ),
      ],
    );
  }

  /// Who is waiting behind the rank. The player's reserves are tappable (a
  /// switch, or the forced replacement); the enemy's are just counted — its
  /// bench is unlimited and there is nothing to decide about it.
  Widget _reserveStrip(List<Combatant> bench, {required bool isEnemy}) => Row(
    mainAxisAlignment: isEnemy
        ? MainAxisAlignment.start
        : MainAxisAlignment.end,
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
        Text(
          '+${bench.length} waiting',
          style: FoE.dim(size: 10).copyWith(color: FoE.textDim),
        )
      else
        for (final c in bench) _benchChip(c, isEnemyRow: isEnemy),
    ],
  );

  /// A small bench portrait. Player chips are tappable on the player's turn to
  /// switch (free); enemy chips are just shown.
  Widget _benchChip(Combatant c, {required bool isEnemyRow}) {
    // !_presenting too (user 2026-08-29, same underlying race as the action
    // deck's own myTurn gate): isPlayerTurn can already be true while a
    // still-playing presentation has the shared animation controllers busy.
    final canSwitchTo =
        !isEnemyRow &&
        _engine.outcome == null &&
        !_presenting &&
        (_engine.isPlayerTurn || _engine.needsPlayerSwitch);
    return Pressable(
      onTap: canSwitchTo
          ? () {
              final idx = _engine.players.indexOf(c);
              final err = _engine.switchActivePlayer(idx);
              if (err != null) {
                _showError(err);
                return;
              }
              _relayPvpAction(kind: 'switch', actor: c);
            }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(3),
        decoration: ShapeDecoration(
          color: FoE.panelDark,
          shape: FoE.facet(
            radius: 6,
            side: BorderSide(color: canSwitchTo ? FoE.goldBright : FoE.border),
          ),
        ),
        child: SizedBox(width: 30, height: 30, child: _portrait(c, size: 22)),
      ),
    );
  }

  /// The large battlefield sprite, sized to [height]. [back] picks the
  /// back-view art (player) over the front (enemy). Plays the hit pulse
  /// (shake + white flash) when this side was just acted upon (user
  /// 2026-07-18). Whose turn it is is shown in the turn-order bar, and its
  /// health on the platform's own rim (see [TypePodium]) — not here.
  /// A flat visual zoom on top of the sprite's own box (user 2026-08-28:
  /// "Die Monster sollen nicht höher sein, sondern grösser... 30% grösser
  /// machen/zoomen" — a correction of the previous attempt, which grew the
  /// rank's own HEIGHT allowance and left most sprites no bigger at all,
  /// since `BoxFit.contain` inside [imgH] is bound by WIDTH first for a
  /// typical sprite and only uses the extra height as empty air above the
  /// monster). [Transform.scale] grows both axes together regardless of
  /// which one the box was actually bound by, and paints past the box
  /// rather than needing more layout space for it.
  /// Dialled back from 1.3 (user 2026-08-29, seen live: "Das linke
  /// gegnerische Monster schaut aus dem Screen heraus") — bottomCenter
  /// growth splits evenly left/right, and for the OUTERMOST slot in a full
  /// 3-wide wedge that pushes the sprite's outer edge off the arena, where
  /// this app's headless test harness (a square Icon placeholder, since it
  /// can't load real network art) never could have caught it: a real
  /// sprite's own aspect ratio decides how far the growth actually reaches
  /// sideways, and there was no way to verify that without the live app.
  static const double _kSpriteZoom = 1.15;

  /// Was an extra bonus on TOP of [_kSpriteZoom] for the player's own
  /// monsters — dropped back to 1.0 (user 2026-08-29: "Zoom wieder auf
  /// 1.15" — the same figure for both sides now) in favour of moving the
  /// whole rank DOWN instead (see [_kArenaDrop]): the bottom anchor that
  /// keeps feet on the platform meant every bit of EXTRA zoom went up,
  /// toward the log ("Das eigene Monster geht zu weit in den Kampflog
  /// hinein") — a position shift gets the same "more of mine, up close"
  /// feeling without that trade-off.
  static const double _kPlayerSpriteZoomBonus = 1.0;

  // ── The lunge's own timeline, as fractions of _fx's 320ms (user
  // 2026-08-29) ── windup: ease back a little. strike: FAST swing past rest,
  // out to the peak. rebound: a small dip past 0 the other way, then settle.
  // [_kLungeWindupFraction] is shared with _consumeCombatEvents, which fires
  // the attack sound at exactly this point in the SAME animation — so the
  // sound always lands on the forward swing's own start, not on a duration
  // guessed separately.
  static const double _kLungeWindupFraction = 0.20;
  static const double _kLungeStrikeEndFraction = 0.55;
  // Bigger, all three (user 2026-08-29: "mache die Animationen grösser. D.h
  // der Angriff soll das Monster deutlich in die Richtung des Gegners
  // führen") — was 4/16/2. Scaled up together, not just the peak, so the
  // windup and the rebound still read as the SAME motion at the new size
  // rather than a big swing bracketed by two small leftover twitches.
  static const double _kLungeWindupPx = 10.0;
  static const double _kLungePeakPx = 42.0;
  static const double _kLungeReboundPx = 6.0;

  /// How far sideways the lunge angles per unit of [_slotAlignX] difference
  /// between attacker and target — see _bigSprite's lungeDx. Slots are ±0.62
  /// apart, so an adjacent-slot target adds ~28px of sideways swing at the
  /// peak, a target across the whole rank (±1.24) ~56px.
  static const double _kLungeHorizontalPxPerAlign = 45.0;

  /// dy at animation-time [t] (0..1 of _fx), toward the target: negative
  /// during windup (a step AWAY), positive at the strike's peak (a step IN),
  /// dipping briefly negative again during the rebound before it settles
  /// back to 0. The caller flips the sign for which side is lunging.
  static double _lungeCurve(double t) {
    if (t <= _kLungeWindupFraction) {
      final p = Curves.easeOut.transform(t / _kLungeWindupFraction);
      return -_kLungeWindupPx * p;
    }
    if (t <= _kLungeStrikeEndFraction) {
      final p = Curves.easeIn.transform(
        (t - _kLungeWindupFraction) /
            (_kLungeStrikeEndFraction - _kLungeWindupFraction),
      );
      return -_kLungeWindupPx + (_kLungePeakPx + _kLungeWindupPx) * p;
    }
    // The rebound: peak -> a small overshoot past rest -> settled at 0,
    // split at its own midpoint so the dip and the settle can each ease on
    // their own terms rather than sharing one curve that fits neither.
    final p = (t - _kLungeStrikeEndFraction) / (1 - _kLungeStrikeEndFraction);
    const dipAt = 0.6;
    if (p <= dipAt) {
      final q = Curves.easeIn.transform(p / dipAt);
      return _kLungePeakPx + (-_kLungeReboundPx - _kLungePeakPx) * q;
    }
    final q = Curves.easeOut.transform((p - dipAt) / (1 - dipAt));
    return -_kLungeReboundPx + _kLungeReboundPx * q;
  }

  Widget _bigSprite(
    Combatant c, {
    required bool back,
    required double height,
    required bool acting,
    required bool targeted,
    bool koing = false,
  }) {
    final url = back ? (c.backImageUrl ?? c.imageUrl) : c.imageUrl;
    // Bigger monsters (user request, twice now — 2026-08-27): nearly the
    // WHOLE slot's own height, not height-minus-a-dozen-px, and a taller
    // floor so a cramped layout can't shrink a lone monster down small.
    final imgH = (height - 2).clamp(96.0, double.infinity);
    // Blink, rise, sink through the podium — its own presentation entirely,
    // no idle bob or hit-reaction competing with it (user 2026-08-29: "eine
    // K.O animation. Das Monster blinkt, geht hoch und durch das Podest
    // verschwindet es nach unten").
    if (koing) {
      return AnimatedBuilder(
        animation: _fxKo,
        builder: (context, _) {
          final t = _fxKo.value;
          const blinkEnd = 0.35;
          const riseEnd = 0.55;
          const riseHeight = 16.0;
          // Well past the sprite's own resting position — the ClipRect
          // below (matching this box's own height) is what turns "moves
          // down a lot" into "sinks out of sight through the podium": once
          // it translates past the box's bottom edge, that edge cuts it
          // off rather than letting it overflow past the ground.
          const sinkDepth = 90.0;
          double dy;
          double opacity;
          if (t < blinkEnd) {
            dy = 0.0;
            // Three flickers across the blink window.
            final phase = (t / blinkEnd * 3) % 1.0;
            opacity = phase < 0.5 ? 1.0 : 0.2;
          } else if (t < riseEnd) {
            final p = Curves.easeOut.transform(
              (t - blinkEnd) / (riseEnd - blinkEnd),
            );
            dy = -riseHeight * p;
            opacity = 1.0;
          } else {
            final p = Curves.easeIn.transform((t - riseEnd) / (1 - riseEnd));
            dy = -riseHeight + (riseHeight + sinkDepth) * p;
            opacity = (1.0 - p).clamp(0.0, 1.0);
          }
          return SizedBox(
            width: double.infinity,
            height: height,
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: back
                        ? _kSpriteZoom * _kPlayerSpriteZoomBonus
                        : _kSpriteZoom,
                    alignment: Alignment.bottomCenter,
                    child: _spriteWithShadow(
                      url,
                      imgH,
                      0.0,
                      c.element.shadowColor,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    // Per COMBATANT (user 2026-07-27): this sprite flinches only if IT was the
    // one struck, and lunges only if it was the one that struck. By side, a hit
    // on one of three would have shaken all three of them.
    final reacts = identical(c, _fxTarget);
    final attacks = identical(c, _fxActor) && !identical(c, _fxTarget);
    final phase = _idlePhase(c);
    return AnimatedBuilder(
      animation: Listenable.merge([_fx, _fxReact, _fxStatus, _idle]),
      builder: (context, _) {
        final t = _fx.value;
        // The reaction reads its OWN controller now, not _fx (user 2026-08-29:
        // "zunächst muss die Angriffsanimation kommen, wenn diese fertig ist,
        // kommt erst die Trefferanimation") — _fxReact only starts once the
        // lunge below has finished, see _playHit.
        final tReact = _fxReact.value;
        final active = reacts && _fxReact.isAnimating;
        final shake = active
            ? math.sin(tReact * math.pi * 6) * 7 * (1 - tReact)
            : 0.0;
        final flash = active ? (1 - tReact) * 0.5 : 0.0;
        // Attacker lunge: WIND UP a little away from the target first, then a
        // fast swing past the resting point, then a small rebound past 0
        // before it settles — anticipation, strike, follow-through (user
        // 2026-08-29: "zunächst ein bisschen zurück gehen und dann mit
        // Schwung nach vorne... nach dem nach vorne schnellen gibt es einen
        // minimalen Rebounce"). The player (back) lunges UP, the enemy DOWN
        // (user 2026-07-20); [_kLungeWindupFraction] of _fx's OWN duration is
        // also when the attack sound fires (see _consumeCombatEvents) — the
        // sound and the forward swing start at exactly the same instant
        // because both read the same constant.
        final lunging = attacks && _fx.isAnimating;
        final lungeShape = lunging ? _lungeCurve(t) / _kLungePeakPx : 0.0;
        final lungeDy = lungeShape * (back ? -1 : 1) * _kLungePeakPx;
        // Sideways toward the ACTUAL target's slot, not just straight up/down
        // (user 2026-08-29: "den Angriff noch in die Richtung des
        // anvisierten Monsters machen") — the same windup/strike/rebound
        // shape as the vertical lunge, scaled by how far off-axis the target
        // stands (0 for a same-slot fight, so nothing changes there).
        final lungeTarget = _fxLungeTarget;
        final lungeDx = (lunging && lungeTarget != null)
            ? lungeShape *
                  (_slotAlignX(lungeTarget) - _slotAlignX(c)) *
                  _kLungeHorizontalPxPerAlign
            : 0.0;
        // Idle bob: a slow, small breathing motion, always running — "nur
        // leicht" (user request), so 2.5px rather than anything that reads as
        // a hop.
        final bob = math.sin((_idle.value + phase) * 2 * math.pi) * 2.5;
        // Whose turn it is / who's targeted (user 2026-08-29: "sehe ich noch
        // nicht gut, welches Monster an der Reihe ist" / "das gleiche gilt
        // für die Gegnerauswahl") — the monster's OWN shadow lit in an accent
        // colour rather than a new shape on the field, so the signal costs no
        // extra chrome. Not a blink (user: "nicht blinken, sondern nur
        // aufleuchten") and not flat either (user: "ein ganz sanftes heller
        // werden und wieder etwas dünkler") — a slow breathe, off the same
        // idle controller as the bob above, between the plain accent and a
        // darker shade of the SAME colour (user: "von rot zu dunkelrot" /
        // "gelb bis dunkel gelb" — not toward white, which read as a
        // different colour rather than as the same one dimming). Gold for
        // acting, red for targeted; the two never coincide on one monster
        // (targeting only applies to enemies, acting only to whoever the
        // engine has up).
        final baseGlow = targeted ? FoE.danger : (acting ? FoE.gold : null);
        final glowColor = baseGlow == null
            ? null
            : Color.lerp(
                baseGlow,
                Colors.black,
                (math.sin(_idle.value * 2 * math.pi) + 1) / 2 * 0.55,
              );
        // White lines rising for a buff, red falling for a debuff (user
        // 2026-08-29) — both keyed to [_fxLungeTarget]: for a self-buff
        // that's the actor itself, for a debuff it's the struck target,
        // either way the one combatant [_playHit]'s status-only branch is
        // presenting right now (own controller, own pace — see _fxStatus).
        final statusSweep =
            _fxStatusKind != _StatusFx.none &&
            identical(c, _fxLungeTarget) &&
            _fxStatus.isAnimating;
        final buffSweep = statusSweep && _fxStatusKind == _StatusFx.buff;
        final debuffSweep = statusSweep && _fxStatusKind == _StatusFx.debuff;
        // A big yellow ring closing in — "the AI did nothing" (banking AP,
        // out of AP) and the player's own End Turn both read as "AP is
        // recharging" now instead of as nothing happening at all (user
        // 2026-08-29: "soll ein grosser gelber Kreis sich über dem Monster
        // zusammenziehen als Zeichen, dass AP generiert werden" — confirmed
        // to cover the player's End Turn too: "Das ist immer so, wenn End
        // Turn gedrückt wird").
        final chargingRing = statusSweep && _fxStatusKind == _StatusFx.charging;
        return SizedBox(
          width: double.infinity,
          height: height,
          child: Transform.translate(
            offset: Offset(shake + lungeDx, lungeDy + bob),
            child: Padding(
              // Was 26, then 10, then 4 to clear the HP arc that used to sit
              // under the sprite (see TypePodium's own history) — that arc
              // is gone, and the leftover gap kept reading as the monster
              // floating above its platform (user 2026-08-27, then twice
              // more on 2026-08-28: "die Monster wieder etwas tiefer und
              // näher zum Podest nehmen"). Zero now — the platform's own
              // front rim is enough of a stop on its own.
              padding: EdgeInsets.zero,
              // Anchored at the BOTTOM so the feet stay planted on the
              // platform and the growth reads as "closer", not as
              // "floating up" or "spreading sideways from the middle".
              child: Transform.scale(
                scale: back
                    ? _kSpriteZoom * _kPlayerSpriteZoomBonus
                    : _kSpriteZoom,
                alignment: Alignment.bottomCenter,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    _spriteWithShadow(
                      url,
                      imgH,
                      flash,
                      glowColor ?? c.element.shadowColor,
                      // The reacting sprite flashes in the STRIKING move's
                      // colour.
                      flashColor: reacts ? _fxImpact : Colors.white,
                    ),
                    if (buffSweep || debuffSweep)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _StatusSweepPainter(
                              t: _fxStatus.value,
                              color: buffSweep ? Colors.white : FoE.danger,
                              upward: buffSweep,
                            ),
                          ),
                        ),
                      ),
                    if (chargingRing)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _ChargingRingPainter(t: _fxStatus.value),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
            // Decode at DISPLAY size, not native (user 2026-08-29: "die
            // Monsterassets werden sehr langsam geladen") — see
            // creature_sprite.dart's decodeWidthFor for why this was the
            // slow part, not the network.
            cacheWidth: decodeWidthFor(context, imgH),
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
              colorFilter: ColorFilter.mode(shadowColor, BlendMode.srcATop),
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
          cacheWidth: decodeWidthFor(context, size),
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
        ? const [_LogLine('The battle begins!', null)]
        : _log.sublist(_log.length >= 2 ? _log.length - 2 : 0);
    return Pressable(
      // Tap to see the WHOLE log (user 2026-08-28: "Kampflog aufklappbar
      // machen, damit der ganze Log angezeigt wird") — the bar itself stays
      // this fixed two-line size (it sits on the seam, with the sprites
      // right up against it on both sides), so "expanded" is a sheet over
      // the fight rather than the bar growing into them.
      onTap: _log.isEmpty ? null : _openFullLog,
      child: Container(
        width: double.infinity,
        height: _kLogHeight,
        alignment: Alignment.center,
        // A slab floating on the seam between the two ranks: one tone, a cut
        // corner, and the hard offset a flat-shaded thing casts.
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: ShapeDecoration(
          color: _flatSurfaceHi,
          shadows: FoE.drop(dy: 3),
          shape: FoE.facet(
            radius: 10,
            side: BorderSide(color: FoE.lit(_flatSurfaceHi), width: 1.5),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            flashing
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
                      // Newest line on TOP, the earlier one dimmed below it
                      // (user request): reverse so the latest action reads
                      // first.
                      for (var i = lines.length - 1; i >= 0; i--)
                        _logRow(
                          lines[i],
                          color: i == lines.length - 1
                              ? FoE.parchment
                              : FoE.textDim,
                        ),
                    ],
                  ),
            // The only hint that there's more behind it.
            if (!flashing && _log.isNotEmpty)
              Positioned(
                right: 2,
                bottom: 1,
                child: Icon(
                  Icons.unfold_more,
                  size: 11,
                  color: FoE.textDim.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One log line, the actor's own small portrait before its text (user
  /// 2026-08-29: "vor den Namen der Monster jeweils ein kleines Icon des
  /// Monsterassets zeigen") — shared by the inline bar and the full-log
  /// sheet so the two can't drift into two different looks.
  Widget _logRow(_LogLine line, {required Color color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (line.iconUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Image.network(
              line.iconUrl!,
              width: 14,
              height: 14,
              fit: BoxFit.cover,
              cacheWidth: decodeWidthFor(context, 14),
              errorBuilder: (_, _, _) => const SizedBox(width: 14, height: 14),
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            line.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 11).copyWith(color: color),
          ),
        ),
      ],
    ),
  );

  /// The whole fight's log, newest first, in a sheet — what a tap on the
  /// fixed-size [_logLine] bar opens (it only ever shows the last two lines
  /// itself, and truncates each to one line besides).
  Future<void> _openFullLog() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FoE.panelDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Battle log',
                  style: FoE.title(size: 15).copyWith(color: FoE.goldBright),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _log.length,
                    itemBuilder: (_, i) {
                      final idx = _log.length - 1 - i; // newest first
                      final line = _log[idx];
                      final color = i == 0 ? FoE.parchment : FoE.textDim;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (line.iconUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: Image.network(
                                  line.iconUrl!,
                                  width: 16,
                                  height: 16,
                                  fit: BoxFit.cover,
                                  cacheWidth: decodeWidthFor(context, 16),
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox(width: 16, height: 16),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                line.text,
                                style: FoE.label(
                                  size: 12,
                                ).copyWith(color: color),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
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
  // above the deck instead of tucking behind it (user request). Went
  // 0.03 → 0.05 ("nach unten schieben"), now back down to 0.02 (user
  // 2026-08-29: "Alle Monster beim Kampfscreen etwas nach oben schieben")
  // — pushes BOTH ranks, platforms included, since this offset wraps the
  // whole arena Stack.
  static const double _kArenaDrop = 0.02;
  static const double _kAbilityW = 112;
  static const double _kAbilityH = 56;
  static const double _kTileGap = 8;
  static const double _kMenuH = 44;

  /// The AP row's height including the gap under it — one line, not a column.
  static const double _kApRowH = 14;
  // Shared tint for EVERY non-type deck button (Auto/End Turn/Items/Catch/Change)
  // so they read as one utility family next to the vivid type abilities.
  static const Color _kUtilTint = FoE.panelLight;

  Widget _actionPanel() {
    return LayoutBuilder(
      builder: (context, box) {
        // The AP row sits ABOVE the moves now, so the tiles have the full
        // width (2026-08-01).
        final usable = box.maxWidth - 20;
        final perRow = ((usable + _kTileGap) / (_kAbilityW + _kTileGap))
            .floor()
            .clamp(1, 6);
        final abilities = _engine.activePlayer?.abilities.length ?? 0;
        final boxes = 1 + abilities; // attack + abilities
        // Same split the deck itself renders with — see [_abilityRowSplit] —
        // so the reserved height always matches what actually gets drawn.
        final rows = _abilityRowSplit(boxes, perRow).length;
        final abilitiesH = rows * _kAbilityH + (rows - 1) * _kTileGap;
        // The AP row is one line, whatever the pool is.
        const apRowH = _kApRowH;
        // utility row + gap + (abilities | AP column, tallest). The deck now
        // ENDS directly above the buttons (user request): the enemy-turn status
        // no longer reserves a strip on top — it floats just above the deck (see
        // the overlay below) so the deck shrinks and the arena grows to match.
        final contentH = _kMenuH + 8 + apRowH + 6 + abilitiesH;
        final panelH = contentH + 22; // top 8 / bottom 10 padding + buffer

        Widget content;
        // Held off exactly as long as [_endOverlay] itself is (see its own
        // "held back while a [_scriptInfoHint] is still showing" comment) —
        // the finisher's crit explainer can leave [_engine.outcome] set for
        // a beat before the win screen is allowed to take over, and this
        // panel used to collapse to nothing the instant outcome was set,
        // leaving a dead blank strip under the still-showing hint (user
        // 2026-09-06: "am Ende des Kampfes verschwindet das UI").
        if (_engine.outcome != null && _scriptInfoHint == null) {
          content = const SizedBox.shrink();
        } else if (_entering) {
          // Hold input while the fighters are still sliding on.
          content = Center(
            child: Text(
              'Get ready…',
              style: FoE.title(size: 15).copyWith(color: FoE.goldBright),
            ),
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
          // The command tray: one plane, lit along the edge that faces you —
          // the same two-facet grammar the page's header band wears.
          decoration: BoxDecoration(
            color: _flatSurface,
            border: Border(
              top: BorderSide(color: FoE.lit(_flatSurface), width: 2),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: content,
        );
      },
    );
  }

  Widget _playerActions() {
    // MY turn = actionable. During the enemy's turn (or auto-battle) the same
    // buttons show but are greyed and inert (user 2026-07-18). `!_presenting`
    // too (user 2026-08-29) — the engine's own turn flips to the player the
    // instant an enemy's action resolves, before that action's lunge/react
    // has finished PLAYING; see [_presenting]'s own doc for what tapping in
    // that gap used to break.
    final myTurn =
        _engine.outcome == null &&
        !_engine.needsPlayerSwitch &&
        _engine.isPlayerTurn &&
        !_autoBattle &&
        !_presenting;
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
                child: KeyedSubtree(
                  key: IntroSpotlightAnchors.of('battle-endturn-btn'),
                  child: _deckButton(
                    icon: Icons.skip_next,
                    label: 'End Turn',
                    base: _kUtilTint,
                    enabled: myTurn,
                    onTap: _endTurn,
                  ),
                ),
              ),
              const SizedBox(width: _kTileGap),
              Expanded(
                child: KeyedSubtree(
                  key: IntroSpotlightAnchors.of('battle-items-btn'),
                  child: _deckButton(
                    icon: Icons.backpack,
                    label: 'Items',
                    base: _kUtilTint,
                    enabled: myTurn,
                    onTap: _openItems,
                  ),
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
              // Only shown when this encounter can EVER be caught — a story
              // battle isn't [isCapture] at all and never will be this turn
              // or any other (user 2026-08-28: "Catchbutton nur dann
              // anzeigen, wenn das Monster theoretisch gefangen werden
              // kann"). [_canCatch] still gates whether it's ENABLED right
              // now (wrong turn, not worn down enough yet).
              if (widget.isCapture) ...[
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        // The cost, then what it buys (2026-08-01).
        KeyedSubtree(
          key: IntroSpotlightAnchors.of('battle-ap'),
          child: Align(
            // Centred (user 2026-08-28: "Die AP bitte zentrieren") — was
            // left-aligned since the 2026-08-01 redesign, which read as
            // pinned to the deck's edge rather than as the header over the
            // move tiles it costs.
            alignment: Alignment.center,
            child: _apBar(ap, maxAp),
          ),
        ),
        const SizedBox(height: 6),
        KeyedSubtree(
          key: IntroSpotlightAnchors.of('battle-actions'),
          // This callout's hole is the WHOLE tile row, unlike every other
          // anchor here — so unlike a plain info readout (turn order, AP,
          // HP), the real buttons underneath stay live and tappable purely
          // because the scrim happens to be punched out around them. Not
          // just cosmetic: firing a REAL ability here would spend AP and
          // damage the enemy outside the script, which the exact
          // percentages after it assume never happened (user 2026-09-03:
          // "dürfen die Fähigkeiten nicht aktiv sein, sonst funktioniert
          // das Tutorial nicht"). IgnorePointer only while this exact
          // callout is up — every later step still needs these tiles live.
          child: IgnorePointer(
            ignoring:
                _battleCallout != null &&
                _battleCalloutAnchors[_battleCallout!] == 'battle-actions',
            child: LayoutBuilder(
              builder: (context, box) {
                // Attack sits at abilities[0] on every combatant now (user
                // 2026-09-03: "attack soll eine normale Fähigkeit sein") —
                // ONE loop, no more separate hardcoded tile for it.
                final abilities = actor.abilities;
                final firstReal = _firstRealAbility(actor);
                final secondReal = _secondRealAbility(actor);
                final tiles = [
                  for (final a in abilities)
                    _maybeAnchoredAbilityTile(
                      a,
                      firstReal,
                      secondReal,
                      _abilityBtn(
                        a.name,
                        _effectiveApCost(a),
                        element: a.element,
                        enabled: myTurn && ap >= _effectiveApCost(a),
                        onTap: () => _useAbility(a),
                        ability: a,
                      ),
                    ),
                ];
                final maxPerRow =
                    ((box.maxWidth + _kTileGap) / (_kAbilityW + _kTileGap))
                        .floor()
                        .clamp(1, 6);
                final split = _abilityRowSplit(tiles.length, maxPerRow);
                var i = 0;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var r = 0; r < split.length; r++) ...[
                      if (r > 0) const SizedBox(height: _kTileGap),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var j = 0; j < split[r]; j++) ...[
                            if (j > 0) const SizedBox(width: _kTileGap),
                            tiles[i++],
                          ],
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// How many tiles sit on each row of the move deck. Explicit for 4/5/6
  /// (user 2026-08-28: "Bei 4 Fähigkeiten oben und unten 2. Bei 5 oben drei,
  /// unten 2 und bei 6 beide Zeilen 3.") — a plain [Wrap] packed rows
  /// GREEDILY by width instead, which for 4 tiles that all fit 3-per-row
  /// gave 3 + 1 rather than the even 2 + 2 asked for here. Falls back to the
  /// old greedy fill when [maxPerRow] is too narrow for the explicit split
  /// (a cramped phone), and for every other count, where greedy already
  /// gives the same one full row.
  static List<int> _abilityRowSplit(int boxes, int maxPerRow) {
    final want = switch (boxes) {
      4 when maxPerRow >= 2 => [2, 2],
      5 when maxPerRow >= 3 => [3, 2],
      6 when maxPerRow >= 3 => [3, 3],
      _ => null,
    };
    if (want != null) return want;
    final rows = <int>[];
    var remaining = boxes;
    while (remaining > 0) {
      final take = remaining < maxPerRow ? remaining : maxPerRow;
      rows.add(take);
      remaining -= take;
    }
    return rows.isEmpty ? [0] : rows;
  }

  /// THE ACTION POINTS — a row of faceted chips above the moves they pay for
  /// (redesign 2026-08-01).
  ///
  /// They were a column of round pips down the right-hand edge, which cost the
  /// tiles a whole column of width and put the number you spend furthest from
  /// the thing you spend it on. A ROW sits directly over the moves, reads
  /// left-to-right like a cost, and is the one place a circle had survived the
  /// faceting.
  ///
  /// Spent points are not hidden, they are EMPTIED: what you had this turn is
  /// as much a part of the read as what is left.
  Widget _apBar(int ap, int maxAp) => Row(
    // min, not the Row default — a Row otherwise fills the Align it sits in
    // and centres nothing (user 2026-08-28: "Die AP bitte zentrieren").
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('AP', style: FoE.dim(size: 10).copyWith(color: FoE.textDim)),
      const SizedBox(width: 6),
      for (var i = 0; i < maxAp; i++)
        Container(
          margin: const EdgeInsets.only(right: 4),
          width: 16,
          height: 8,
          decoration: ShapeDecoration(
            color: i < ap ? FoE.gold : Colors.transparent,
            shape: FoE.facet(
              radius: 3,
              side: BorderSide(
                color: i < ap ? FoE.lit(FoE.gold) : FoE.border,
                width: 1.2,
              ),
            ),
          ),
        ),
    ],
  );

  /// A MOVE, as a faceted card (redesign 2026-08-01).
  ///
  /// The surface is the monster's own — [CreatureBackdrop], the same material
  /// the platforms under the fighters wear — so a move and the type it belongs
  /// to are one thing wherever you meet them.
  ///
  /// What changed with the redesign:
  ///  • the AP cost was a second line of text under the name. It is a CORNER
  ///    CHIP now: a cost is a number you scan, not a sentence you read, and the
  ///    name gets the whole width back.
  ///  • effectiveness was a ring plus a round badge. The ring stays (it is a
  ///    facet edge); the badge is a TRIANGLE — the one shape a faceted world
  ///    makes, pointing the way the damage goes.
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
    final mult = (enabled && isDamage) ? _effectivenessVsEnemy(element) : 1.0;
    final radius = FoE.radiusSmall + 2;

    // Dead centre now, not bottom-left (user 2026-08-29: "den Namen komplett
    // mittig von der Box") — with the AP chip its own corner and no second
    // line of text competing for room, the name can just sit in the middle
    // of the tile instead of being anchored to an edge.
    Widget label = Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: FoE.label(
            size: 12,
          ).copyWith(color: fg, fontWeight: FontWeight.w800, height: 1.1),
        ),
      ),
    );

    Widget tile = enabled
        ? CreatureBackdrop(
            element: element,
            radius: radius,
            // Bigger (user 2026-08-29: "das Typicon grösser machen") — the
            // card's own embossed glyph, same scale knob TypePodium uses for
            // the same reason.
            symbolScale: 1.35,
            child: label,
          )
        : Container(
            decoration: ShapeDecoration(
              color: FoE.panelDark,
              shape: FoE.facet(radius: radius),
            ),
            child: label,
          );

    // Strong/weak → an arrow in the answer's colour (user 2026-08-29: "Zum
    // Start des Kampfes hat es noch gelbe/grüne Ränder um die Aktionen,
    // diese Bitte löschen. Effektiv und nicht effektiv sollen durch einen
    // Pfeil nach oben (grün) oder Pfeil nach unten (rot) dargestellt
    // werden") — the facet-edge border this used to also draw is gone; the
    // corner mark below is now the ONE signal for it.
    final effColor = mult > 1.0
        ? FoE.positive
        : mult < 1.0
        ? FoE.danger
        : null;

    return SizedBox(
      width: _kAbilityW,
      height: _kAbilityH,
      child: Pressable(
        onTap: enabled ? onTap : null,
        onLongPress: () => _showAbilityPreview(name, ap, element, ability),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: tile),
            // THE COST, in the corner it is cut from. Yellow, and a bit
            // bigger (user 2026-08-29: "Die Ecke, welche anzeigt, wieviel AP
            // eine Aktion kostet, soll gelb sein und ein bisschen grösser")
            // — AP is the one number every move choice hinges on, so it gets
            // the app's own "important number" colour instead of a low-
            // contrast dark chip.
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 3, 7, 4),
                decoration: ShapeDecoration(
                  color: enabled ? FoE.gold : Colors.transparent,
                  shape: const RoundedRectangleBorder(
                    // Rounded on the inner corner only: the chip is a piece of
                    // the tile's own edge, not a sticker on it.
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                child: Text(
                  '$ap',
                  style: FoE.value(size: 13).copyWith(
                    color: enabled ? const Color(0xFF1A1300) : FoE.textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (effColor != null)
              Positioned(
                bottom: 3,
                right: 3,
                child: CustomPaint(
                  size: const Size(14, 14),
                  painter: _EffectivenessArrow(color: effColor, up: mult > 1.0),
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

  /// Tap the status strip on a combatant's plate → explain EVERY effect
  /// currently active on it, in plain language (user 2026-09-08: "Buffs und
  /// Debuffs besser erklären, damit ich genau weiss, was diese machen").
  ///
  /// Reuses [describeAbilityEffect] — the exact text an ability's own
  /// preview already promises — built from the effect's REAL, currently
  /// active magnitude/remaining turns rather than the catalog default, so
  /// the numbers shown are true right now even if the move that applied
  /// them authored its own. Drops that function's trailing "lands on a X %
  /// roll" sentence: that line is about whether an ability WOULD apply this
  /// — meaningless for something already sitting on the combatant.
  Future<void> _showActiveEffects(Combatant c) async {
    List<String> activeLines(AbilityEffect e) {
      final all = describeAbilityEffect(e);
      return all.length > 1 ? all.sublist(0, all.length - 1) : all;
    }

    final rows = <Widget>[
      if (c.mainStatus != null)
        _previewRow(
          Icons.local_fire_department,
          '${c.mainStatus!.emoji} ${c.mainStatus!.label}\n'
          '${activeLines(AbilityEffect(kind: AbilityEffectKind.ofMainStatus(c.mainStatus!)!, turns: c.mainStatusTurnsRemaining, value: c.mainStatusValue)).join('\n')}',
        ),
      for (final e in c.selfBuffs.entries)
        _previewRow(
          Icons.shield,
          '${e.key.emoji} ${e.key.label}\n'
          '${activeLines(AbilityEffect(kind: AbilityEffectKind.ofSelfBuff(e.key), turns: e.value.turnsRemaining, value: e.value.value)).join('\n')}',
          color: FoE.positive,
        ),
      for (final e in c.secondaryDebuffs.entries)
        _previewRow(
          Icons.visibility_off,
          '${e.key.emoji} ${e.key.label}\n'
          '${activeLines(AbilityEffect(kind: AbilityEffectKind.ofDebuff(e.key), turns: e.value.turnsRemaining, value: e.value.value)).join('\n')}',
        ),
    ];
    if (rows.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FoE.panelDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          16 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.name} — active effects',
              style: FoE.label(
                size: 14,
              ).copyWith(color: FoE.parchment, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            ...rows,
          ],
        ),
      ),
    );
  }

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
          ? (
              'Super effective vs ${enemy.name}',
              Icons.keyboard_arrow_up,
              FoE.positive,
            )
          : mult < 1.0
          ? ('Resisted by ${enemy.name}', Icons.keyboard_arrow_down, FoE.danger)
          : ('Neutral vs ${enemy.name}', Icons.remove, FoE.textDim);
      rows.add(_previewRow(icon, '$label  (×${_fmtMult(mult)})', color: color));
    }

    if (a == null) {
      rows.add(
        _previewRow(
          Icons.bolt,
          'Basic attack · Power ${CombatEngine.basicAttackPower}',
        ),
      );
      rows.add(
        _previewRow(
          Icons.info_outline,
          'Free, typeless strike — never lands bonus damage.',
        ),
      );
    } else {
      if (a.kind == AbilityKind.damage) {
        rows.add(_previewRow(Icons.bolt, 'Power ${a.power}'));
      }
      // Extra hits (user 2026-09-08: "nicht nur 1 gegner treffen sondern 2
      // oder 3... mit jedem Treffer sinkt die Chance"): the compound chance
      // to reach each further hit, capped at 3 total.
      if (a.extraHitChance > 0) {
        final pct2 = (a.extraHitChance * 100).round();
        final pct3 = (a.extraHitChance * a.extraHitChance * 100).round();
        rows.add(
          _previewRow(
            Icons.blur_on,
            a.extraHitSameTarget
                ? 'May hit the SAME target again: 2nd hit $pct2 % chance, '
                      '3rd $pct3 %.'
                : 'May also hit ANOTHER enemy: 2nd hit $pct2 % chance, 3rd '
                      '$pct3 % — does nothing extra alone.',
          ),
        );
      }
      // ONE row per effect, stated fully (user 2026-07-30: "zeige mir ganz
      // genau, was dies im Kampf bedeutet" — the same describeAbilityEffect
      // the Dev-Mode form uses, so this card cannot say less than the editor
      // already promised the author it would do).
      for (final e in a.effects) {
        rows.add(
          _previewRow(
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
            describeAbilityEffect(e).join('\n'),
            color: switch (e.kind.family) {
              AbilityEffectFamily.heal ||
              AbilityEffectFamily.regen ||
              AbilityEffectFamily.selfBuff ||
              AbilityEffectFamily.lifesteal => FoE.positive,
              AbilityEffectFamily.selfPenalty ||
              AbilityEffectFamily.recoil => FoE.danger,
              _ => null,
            },
          ),
        );
      }
      if (a.priority > 0) {
        rows.add(
          _previewRow(Icons.flash_on, 'Priority +${a.priority} — acts sooner'),
        );
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
          16,
          14,
          16,
          16 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: ShapeDecoration(
                    color: element.color,
                    shape: FoE.facet(radius: 6),
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: ShapeDecoration(
                    color: _kUtilTint,
                    shape: FoE.facet(radius: 6),
                  ),
                  child: Text(
                    '$ap AP',
                    style: FoE.label(
                      size: 11,
                    ).copyWith(fontWeight: FontWeight.w800),
                  ),
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
    final onColor = base.computeLuminance() > 0.5
        ? const Color(0xFF1A1300)
        : Colors.white;
    final fg = enabled ? onColor : FoE.textMuted;
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        style: FoE.label(
          size: 12,
        ).copyWith(color: fg, fontWeight: FontWeight.w800),
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
            decoration: ShapeDecoration(
              color: FoE.panelDark,
              shape: FoE.facet(radius: radius),
            ),
            child: content,
          );
    if (enabled) {
      // The offset facet that lifts a key off the tray.
      tile = DecoratedBox(
        decoration: ShapeDecoration(
          shadows: FoE.drop(dy: 2, alpha: 0.35),
          shape: FoE.facet(radius: radius),
        ),
        child: tile,
      );
    }
    return Pressable(
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
      style: FoE.label(
        size: 13,
      ).copyWith(color: FoE.goldBright, fontWeight: FontWeight.w700),
    );
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: ShapeDecoration(
          color: FoE.panelMid,
          shape: FoE.facet(
            radius: FoE.radiusSmall + 3,
            side: BorderSide(color: FoE.gold, width: 1.5),
          ),
        ),
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
  /// costs a flat [kItemApCost] AP, same as every ability's own AP spend —
  /// NOT the whole turn (user 2026-09-05: "ein Item benutzen, kostet immer
  /// 1 AP", replacing the older whole-turn rule from 2026-07-18).
  Future<void> _openItems() async {
    final settlement = SettlementController();
    final actor = _engine.activePlayer;
    if (actor == null) return;
    // Battle-usable heal/buff/cure items apply to the ACTIVE monster. (Revive
    // is out-of-battle only — the active can't be K.O., and bench-targeting
    // is a later slice.)
    final held = [
      for (final e in settlement.items.entries)
        if (kItemDefs[e.key] case final ItemDef d
            when d.battleUsable &&
                (d.kind == ItemKind.heal ||
                    d.kind == ItemKind.buff ||
                    d.kind == ItemKind.cureStatus ||
                    d.kind == ItemKind.cureDebuffs))
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
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use an item (costs $kItemApCost AP)',
              style: FoE.title(size: 14),
            ),
            const SizedBox(height: 12),
            if (held.isEmpty)
              Text('No usable items in your bag.', style: FoE.dim(size: 12))
            else
              for (final (def, count) in held)
                Pressable(
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
                            '${def.name} ×$count · ${_itemUseLabel(def, actor)}',
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
      case ItemKind.cureStatus:
        // The item's own magnitude IS its reliability (user 2026-09-15's
        // weak/strong remedies — see ItemKind.cureStatus's own doc).
        // deterministicCombat always succeeds, matching every other roll's
        // own convention (see CombatEngine._rollAccuracy).
        final worked = _engine.deterministicCombat ||
            _engine.rng.nextDouble() < chosen.magnitude;
        final cured = worked && actor.cureMainStatus(chosen.cureMainStatus);
        _flashMessage(cured
            ? '${chosen.emoji} ${actor.name} is cured!'
            : '${chosen.emoji} ${actor.name} — no effect.');
      case ItemKind.cureDebuffs:
        final worked = _engine.deterministicCombat ||
            _engine.rng.nextDouble() < chosen.magnitude;
        final cleansed = worked && actor.clearSecondaryDebuffs();
        _flashMessage(cleansed
            ? '${chosen.emoji} ${actor.name} is cleansed!'
            : '${chosen.emoji} ${actor.name} — no effect.');
      default: // heal
        final heal = healFromItem(
          chosen,
          (actor.maxHp - actor.hp).toDouble(),
        ).round();
        actor.hp = (actor.hp + heal).clamp(0, actor.maxHp).toInt();
        _flashMessage('${chosen.emoji} ${actor.name} +$heal HP');
    }
    if (_scriptBeat == _ScriptBeat.healItem) {
      // Scripted for THIS fight only: the cutscene sets AP directly rather
      // than going through _engine.useItem, so a low roll can never block
      // the next authored beat (user 2026-09-03: "unabhängig von den
      // tatsächlichen Werten") — it happens to spend the exact same
      // [kItemApCost] the real rule below now also charges (user
      // 2026-09-05), so the two no longer diverge, they just take different
      // paths to it.
      actor.ap = math.max(0, actor.ap - kItemApCost);
      // "9 regeneriert" (user 2026-09-04) tops the starter right back up to
      // full regardless of the real potion's own formula — same fakery as
      // every other forced HP number in this fight.
      actor.hp = actor.maxHp;
      _ensureApFor(_ScriptBeat.missedAttack);
      setState(() {
        _scriptBeat = _ScriptBeat.missedAttack;
        _scriptInfoHint =
            'Items cost AP too — always 1, no matter which '
            'one you use.';
      });
    } else {
      // Using an item always costs a flat kItemApCost AP (user 2026-09-05) —
      // the turn stays open for whatever's left, exactly like an ability.
      _engine.useItem(actor);
      setState(() {});
    }
  }

  /// Maps an item's buff stat onto the engine's self-buff (rage=attack,
  /// armor=defense, haste=speed; attack/other → rage).
  SelfBuffKind _selfBuffForStat(CreatureStat? s) => switch (s) {
    CreatureStat.defense => SelfBuffKind.armor,
    CreatureStat.speed => SelfBuffKind.haste,
    _ => SelfBuffKind.rage,
  };

  /// What tapping [def] would do to [actor] RIGHT NOW — the "Use an item"
  /// sheet's one-line preview, same job for every kind (user 2026-09-15
  /// added the cure lines).
  String _itemUseLabel(ItemDef def, Combatant actor) {
    switch (def.kind) {
      case ItemKind.buff:
        return _selfBuffForStat(def.buffStat).name;
      case ItemKind.cureStatus:
        final pct = (def.magnitude * 100).round();
        final target = def.cureMainStatus?.label ?? 'any status';
        return actor.mainStatus == null
            ? 'nothing to cure right now'
            : 'cures $target · $pct%';
      case ItemKind.cureDebuffs:
        final pct = (def.magnitude * 100).round();
        return actor.secondaryDebuffs.isEmpty
            ? 'nothing to cleanse right now'
            : 'cleanses all debuffs · $pct%';
      default: // heal
        return '+${healFromItem(def, (actor.maxHp - actor.hp).toDouble()).round()} HP';
    }
  }

  // ── End overlay ───────────────────────────────────────────
  Widget _endOverlay() {
    final outcome = _engine.outcome!;
    // Victory has no subtitle any more (user 2026-08-28: "Your Team grew
    // Stronger löschen") — the rewards below already say what was won.
    final (title, subtitle) = switch (outcome) {
      CombatOutcome.victory => ('🏆 Victory!', null),
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
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(subtitle, style: FoE.label(size: 13)),
              ],
              // PvP has no XP/level-up/unlock pool — its reward is the
              // rating change, already applied by [_applyPvpOutcome] and
              // visible on the Ranking tab, not restated here.
              if (outcome == CombatOutcome.victory && !widget.isPvp) ...[
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
                child: Pressable(
                  // A capture battle returns every wild caught along the
                  // way too (2026-09-11) — every other battle (dungeon,
                  // Survival, Training) still just gets its bare outcome.
                  // PvP has no caller waiting on a result at all — it just
                  // goes back to the app root (the PvP tab, not mid-lobby).
                  onTap: () => widget.isPvp
                      ? Navigator.of(context).popUntil((r) => r.isFirst)
                      : Navigator.of(context).pop(
                          widget.isCapture
                              ? HuntBattleResult(
                                  outcome,
                                  _caught,
                                  widget.enemies.where((w) => !w.alive).length,
                                )
                              : outcome,
                        ),
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
            Text(
              'Defeated $foes ${foes == 1 ? 'foe' : 'foes'}',
              style: FoE.dim(size: 12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Every participating monster gets its OWN tile now (user
        // 2026-08-28: "Zeige alle beteiligten eigenen Monster mit ihrer
        // Monsterkachel an") — the same [CreatureCard] every other screen
        // uses, not a small bordered portrait.
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [for (final p in _engine.players) _victoryCreatureTile(p)],
        ),
        const SizedBox(height: 12),
        // The sweeping XP bar (purely celebratory — one full sweep).
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) =>
              RecessBar(value: v, color: FoE.gold, height: 11, onDark: true),
        ),
      ],
    );
  }

  /// One participant's own tile, [CreatureCard] and all, with the XP it
  /// earned this fight captioned under it. Falls back to the small portrait
  /// badge only if the instance can't be found any more (released mid-fight,
  /// say) — should not happen in practice.
  Widget _victoryCreatureTile(Combatant p) {
    final inst = p.instanceId == null
        ? null
        : CreaturesController().byId(p.instanceId!);
    return Opacity(
      opacity: p.alive ? 1 : 0.55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: monsterTileWidth(context),
            height: monsterTileHeight(context),
            child: inst != null
                ? CreatureCard(creature: inst)
                : Container(
                    padding: const EdgeInsets.all(3),
                    decoration: ShapeDecoration(
                      color: FoE.panelDark,
                      shape: FoE.facet(
                        radius: 8,
                        side: BorderSide(color: FoE.border),
                      ),
                    ),
                    child: _portrait(p, size: 30),
                  ),
          ),
          const SizedBox(height: 3),
          Text(
            '+$_xpEach XP',
            style: FoE.label(size: 10).copyWith(color: FoE.gold),
          ),
        ],
      ),
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
          Text(
            'Level Up!',
            style: FoE.title(size: 14).copyWith(color: FoE.goldBright),
          ),
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
      child: Transform.scale(
        scale: 0.9 + 0.1 * v.clamp(0.0, 1.0),
        child: child,
      ),
    ),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: FoE.panelDark,
        shape: FoE.facet(
          radius: 12,
          side: BorderSide(color: FoE.goldBright.withValues(alpha: 0.6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No gift icon any more (user 2026-08-28: "Unlocked: Icon
          // löschen") — the title alone says what the box is for.
          Center(
            child: Text(
              'Unlocked!',
              style: FoE.title(size: 14).copyWith(color: FoE.goldBright),
            ),
          ),
          const SizedBox(height: 8),
          for (final r in widget.victoryRewards)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              // Same principle as the battle preview's reward list (user
              // 2026-08-28: "darunter das gleiche Prinzip wie bei der
              // Kampfvorschau. Gebäudeicon und der Name") — a building
              // reward shows its OWN preview picture and just its name,
              // not the 🏛️ glyph and "New building: X" every other line
              // still uses.
              child: r.buildingId != null
                  ? _victoryBuildingRow(r)
                  : _victoryPlainRow(r),
            ),
        ],
      ),
    ),
  );

  /// How wide every unlock line's icon SLOT is, whatever fills it — an
  /// emoji glyph or a 36-px [BuildingIcon] (user 2026-08-28: "den Text
  /// immer gleich bündig machen. D.h in der gleichen Spalte" — the same fix
  /// as the battle preview's own reward list). The icon is centred in the
  /// slot; the text starts at the same x either way.
  static const double _kUnlockIconSlot = 36;

  Widget _unlockRow(Widget icon, String text) => Row(
    children: [
      SizedBox(
        width: _kUnlockIconSlot,
        child: Center(child: icon),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: FoE.label(size: 12).copyWith(color: FoE.parchment),
        ),
      ),
    ],
  );

  // fontSize 16, not 15 (2026-08-31 audit) — this row's own comment below
  // says it mirrors battle_prep_screen.dart's _buildingRewardRow/
  // _plainRewardRow; the glyph size had drifted by 1px from what it claims
  // to copy.
  Widget _victoryPlainRow(RewardLine r) =>
      _unlockRow(Text(r.emoji, style: const TextStyle(fontSize: 16)), r.text);

  /// A "new building" unlock, as the building's OWN preview picture and its
  /// name — mirrors battle_prep_screen.dart's own [_buildingRewardRow]. The
  /// same headroom compensation applies: the bundled renders carry real
  /// camera space above the roofline, so the building sits noticeably lower
  /// than the text beside it without the nudge.
  Widget _victoryBuildingRow(RewardLine r) => _unlockRow(
    Transform.translate(
      offset: const Offset(0, -6),
      child: BuildingIcon(defId: r.buildingId, emoji: r.emoji, size: 36),
    ),
    r.text.replaceFirst('New building: ', ''),
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
        child: Transform.scale(
          scale: 0.85 + 0.15 * v.clamp(0.0, 1.0),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: ShapeDecoration(
          color: FoE.panelDark,
          shape: FoE.facet(
            radius: 10,
            side: BorderSide(color: FoE.gold.withValues(alpha: 0.55)),
          ),
        ),
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
                      cacheWidth: decodeWidthFor(context, 34),
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
                          style: FoE.label(
                            size: 12,
                          ).copyWith(color: FoE.parchment),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Lv ${up.fromLevel}', style: FoE.dim(size: 11)),
                      const Text(
                        '  →  ',
                        style: TextStyle(color: FoE.textDim, fontSize: 11),
                      ),
                      Text(
                        '${up.toLevel}',
                        style: FoE.value(
                          size: 13,
                        ).copyWith(color: FoE.goldBright),
                      ),
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
    decoration: ShapeDecoration(
      color: FoE.positive.withValues(alpha: 0.16),
      shape: FoE.facet(radius: 6),
    ),
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
    // The wild THIS attempt is against (2026-09-11) — captured at
    // _startCatch time, not necessarily the same as _engine.activeEnemy /
    // fieldEnemies.first once more than one wild can be on the field.
    final wild = _catchWild;
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
              Text(
                'Catch it!',
                style: FoE.title(size: 18).copyWith(color: FoE.goldBright),
              ),
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
                                cacheWidth: decodeWidthFor(context, 150),
                                errorBuilder: (_, _, _) => const Icon(
                                  Icons.pets,
                                  color: FoE.gold,
                                  size: 80,
                                ),
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
    _c =
        AnimationController(
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
        final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
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
                      style: FoE.label(
                        size: 10,
                      ).copyWith(color: d.color, fontWeight: FontWeight.w800),
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

/// One rising heal cross's data (see _BattleScreenState._healCrosses). Pure
/// data, same shape as [_FloatText] — [xJitter] spreads a burst of them apart
/// horizontally and [delay] staggers when each one starts rising, so three
/// spawned together read as a little burst rather than one glyph tripled in
/// place.
class _HealCross {
  final int id;
  final double alignX;
  final bool onEnemy;
  final double xJitter;
  final Duration delay;
  const _HealCross({
    required this.id,
    required this.alignX,
    required this.onEnemy,
    required this.xJitter,
    required this.delay,
  });
}

/// A single ✚ that pops in, drifts up further and longer than a damage
/// number (a heal is a slower, gentler beat than a hit), and fades — see
/// [_HealCross]'s own doc for why several of these ride one heal.
class _RisingCross extends StatefulWidget {
  final _HealCross data;
  final VoidCallback onDone;
  const _RisingCross({super.key, required this.data, required this.onDone});

  @override
  State<_RisingCross> createState() => _RisingCrossState();
}

class _RisingCrossState extends State<_RisingCross>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _c =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1400),
        )..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        });
    Future.delayed(widget.data.delay, () {
      if (mounted) {
        setState(() => _started = true);
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pop = t < 0.2 ? Curves.easeOutBack.transform(t / 0.2) : 1.0;
        // Rises further than a damage number and keeps drifting for its
        // whole life — a heal is a slow float, not a quick pop.
        final rise = -52.0 * Curves.easeOut.transform(t);
        final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, rise),
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: pop,
              child: Text(
                '✚',
                style: FoE.title(size: 16).copyWith(
                  color: FoE.positive,
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
            ),
          ),
        );
      },
    );
  }
}

/// The strong/weak mark on a move: a literal arrow — up for extra damage,
/// down for reduced (user 2026-08-29: "Effektiv und nicht effektiv sollen
/// durch einen Pfeil nach oben (grün) oder Pfeil nach unten (rot) dargestellt
/// werden").
///
/// Was a corner-filling right-angle triangle (a ribbon/folded-page shape,
/// "pointing" only by which diagonal it cut) — it said UP/DOWN by
/// convention, not by silhouette. A straight isoceles triangle, apex up or
/// apex down, is the one shape that reads as an arrow with nothing to learn.
class _EffectivenessArrow extends CustomPainter {
  final Color color;
  final bool up;

  const _EffectivenessArrow({required this.color, required this.up});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = Path();
    if (up) {
      p
        ..moveTo(w / 2, 0)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
    } else {
      p
        ..moveTo(w / 2, h)
        ..lineTo(w, 0)
        ..lineTo(0, 0)
        ..close();
    }
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EffectivenessArrow old) =>
      old.color != color || old.up != up;
}

/// The buff/debuff sweep (user 2026-08-29: "Bei Buffs sollen vertikale weisse
/// dünne Linien von unten nach oben über das betreffende Monster ziehen. Bei
/// Debuffs sollen rote vertikale dünne Linien von oben nach unten über das
/// 'Opfer' ziehen.") — a handful of thin lines travelling the sprite's own
/// height, [upward] deciding which way. Staggered per line (a fixed phase
/// offset each) so they read as a passing SCAN rather than one bar sliding by,
/// and each fades in/out over its own travel so no line just appears or
/// vanishes at a hard edge.
class _StatusSweepPainter extends CustomPainter {
  /// 0..1 across the whole sweep — the caller's own animation value, not
  /// owned by this painter.
  final double t;
  final Color color;

  /// true = bottom-to-top (buff), false = top-to-bottom (debuff).
  final bool upward;

  const _StatusSweepPainter({
    required this.t,
    required this.color,
    required this.upward,
  });

  static const int _lineCount = 5;
  static const double _lineLenFraction = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final halfLen = size.height * _lineLenFraction / 2;
    final travel = size.height + halfLen * 2;
    for (var i = 0; i < _lineCount; i++) {
      final x = size.width * (i + 0.5) / _lineCount;
      // Each line a little further along than the last, wrapped — a staggered
      // scan rather than a single bar.
      final phase = (t + i * 0.09) % 1.0;
      final travelled = upward
          ? size.height + halfLen - phase * travel
          : -halfLen + phase * travel;
      final y0 = (travelled - halfLen).clamp(0.0, size.height);
      final y1 = (travelled + halfLen).clamp(0.0, size.height);
      if (y1 <= y0) continue;
      // Fades in from nothing, fades back out to nothing — no line simply
      // appears or vanishes at a hard edge.
      final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);
      if (fade <= 0.02) continue;
      paint.color = color.withValues(alpha: fade * 0.9);
      canvas.drawLine(Offset(x, y0), Offset(x, y1), paint);
    }
  }

  @override
  bool shouldRepaint(_StatusSweepPainter old) =>
      old.t != t || old.color != color || old.upward != upward;
}

/// A big yellow ring closing in over a monster that ended its turn without
/// acting — the AI banking AP, out of AP entirely, or the player's own "End
/// Turn" (user 2026-08-29: "ein grosser gelber Kreis sich über dem Monster
/// zusammenziehen als Zeichen, dass AP generiert werden"). Stroke, not a
/// fill — a closing ring reads as energy drawing IN; a shrinking disc would
/// just read as something disappearing.
///
/// Two phases, not one continuous shrink (user 2026-08-29: "dicker sein und
/// etwas schneller zusammenziehen. Nach dem Zusammenziehen gibt es einen
/// kleine Burst"): CONTRACT closes the ring in the first [_contractEnd] of
/// [t] (less of the timeline than before is what makes it read as faster,
/// same [_fxStatus] duration underneath), then BURST is the release — a
/// bright pop outward from where it closed, fading as it goes.
class _ChargingRingPainter extends CustomPainter {
  /// 0..1 across the whole thing, contract and burst together.
  final double t;

  const _ChargingRingPainter({required this.t});

  static const double _contractEnd = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.55);
    final maxR = size.shortestSide * 0.85;
    final minR = size.shortestSide * 0.08;

    if (t < _contractEnd) {
      final p = Curves.easeIn.transform(t / _contractEnd);
      final r = maxR + (minR - maxR) * p;
      // Thicker throughout, and thickens further as it closes — a ring
      // drawing itself together, not a fixed loop just shrinking in place.
      final width = 4.0 + p * 5.0;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = FoE.gold.withValues(alpha: (1 - p * 0.2).clamp(0.0, 1.0)),
      );
      return;
    }

    // The burst: what the ring was gathering toward, released — a quick
    // bright ring popping outward from the closed point and fading as its
    // own stroke thins out.
    final p = Curves.easeOut.transform((t - _contractEnd) / (1 - _contractEnd));
    canvas.drawCircle(
      center,
      minR + minR * 3.5 * p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (7.0 * (1 - p)).clamp(0.5, 7.0)
        ..color = FoE.goldBright.withValues(alpha: (1 - p).clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(_ChargingRingPainter old) => old.t != t;
}
