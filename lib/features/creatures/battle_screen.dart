import '../../core/ui/feel.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart' show HapticFeedback;
// Warms a sprite's BYTES into the same store CreatureSprite reads from,
// without decoding it — see the precache in initState.
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/ui/app_navigator.dart';
import '../../core/theme/cream_kit.dart';
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
import '../social/models/pvp_match.dart';
import '../social/services/friends_service.dart';
import '../social/services/pvp_notifier.dart';
import '../social/services/pvp_service.dart';
import '../social/widgets/social_kit.dart';
import 'pvp_lobby_screen.dart';
import 'capture_bait_picker.dart';
import 'capture_bar_screen.dart';
import 'services/battle_rewards.dart';
import 'services/battle_stars.dart';
import 'services/capture_math.dart';
import 'services/combat_engine.dart';
import 'services/creatures_controller.dart';
import 'services/pvp_combatant_snapshot.dart';
import 'services/pvp_sync_service.dart';
import 'widgets/battle_scene.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_family.dart' show SockelAvatar;
import 'widgets/monster_sheet.dart';
import 'widgets/creature_sprite.dart' show CreatureSprite, decodeWidthFor;
import 'widgets/type_chart_screen.dart';
import 'widgets/wild_preview.dart';
import '../common/widgets/recess_bar.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../settlement/widgets/building_icon.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

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

  /// The campaign battle this is (user 2026-09-28) — set by the overworld, null
  /// for a hunt, Survival, training or PvP. Only a numbered campaign fight is
  /// judged for STARS (see battle_stars.dart) and has its XP scaled by them.
  final int? battleNumber;

  const BattleScreen({
    super.key,
    required this.team,
    required this.enemies,
    this.title = 'Battle',
    this.battleNumber,
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
  // Between powerAttack's "Not very effective" and banking the turn (user
  // 2026-09-30: "nach not very effective soll der User oben auf den type
  // chart klicken... Dann muss der User das Menü wieder schliessen und das
  // Tutorial geht weiter") — the type-chart key is the one lit control;
  // closing the chart (however that happens) advances straight to
  // bankEndTurn.
  typeChartPrompt,
  bankEndTurn,
  enemyAlmostKill,
  finisher,
}

class _BattleScreenState extends State<BattleScreen>
    with TickerProviderStateMixin {
  // Not `final` any more (2026-09-17): a desync resync rebuilds this from
  // scratch — see [_handleDesync]. Every other mode still assigns it exactly
  // once, in initState, same as before.
  late CombatEngine _engine;
  Timer? _autoTimer;
  bool _autoBattle = false;
  bool _outcomeApplied = false;

  // ── PvP (2026-09-15) ─────────────────────────────────────────
  // Only ever touched when widget.isPvp — see that field's doc comment.
  final PvpSyncService _pvpSync = PvpSyncService();
  final PvpService _pvpService = PvpService();
  // Set when a relayed 'flee' arrives — CombatEngine.flee() doesn't record
  // WHICH side fled, so _applyOutcome needs this to award the forfeit win
  // to the side that stayed rather than treating both sides as losers. Also
  // set for a timeout win claimed via [_maybeClaimTimeout] — reuses this
  // exact same path (see that method's doc comment).
  bool _pvpOpponentFled = false;

  // ── PvP resilience (2026-09-17) ───────────────────────────────
  // One timer for "it's their turn" AND "they disconnected" (see
  // supabase/migrations/0053_pvp_resilience.sql's doc comment) — purely
  // LOCAL state, deliberately never read back from the DB: both clients
  // derive the identical deadline independently from the same deterministic
  // action sequence (lockstep), so there's nothing to synchronize. The
  // server write ([PvpService.advanceTurn]) exists only so
  // [PvpService.claimTimeoutWin] has something authoritative to check.
  static const _kPvpTurnTimeout = Duration(seconds: 60);
  String? _turnWindowKey;
  String? _waitingOnId;
  DateTime? _turnDeadline;
  Timer? _turnCountdownTimer;
  bool _claimingTimeout = false;
  // Guards against a resync-triggered replay re-triggering itself if the
  // rebuilt engine somehow still disagreed — see [_handleDesync].
  bool _resyncing = false;

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

  /// Which page of the command deck is open (user 2026-09-20, "Variante 7 — Reiter"):
  /// Items and Change are tabs of the deck now, not bottom sheets. See [_shownTab].
  _DeckTab _deckTab = _DeckTab.attack;

  /// The ability the deck's info box describes — set by a long press on its tile
  /// (which used to open a sheet) or by using it. See [_infoAbilityFor].
  String? _infoAbilityId;

  // ── Idle bob (user request) ────────────────────────────────
  // A slow, small up-down breathing motion so the field never looks frozen
  // between turns. One shared repeating clock rather than one controller per
  // monster — [_idlePhase] offsets each combatant round it so six fighters
  // don't bob in lockstep like a single puppet.
  late final AnimationController _idle;

  // Level-ups captured when the fight resolves, shown in the end overlay with
  // their stat gains (user 2026-07-24).
  List<LevelUpResult> _levelUps = const [];
  // The one-time gold paid for stars reached for the first time (0 on a rematch
  // that did not beat the record) — shown in the victory card.
  int _starGold = 0;
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

  // ── Catch mini-game (Balkenjagd, user 2026-10-01 — replaces the old
  // inline ring QTE; see capture_bar_screen.dart) ───────────
  bool _catchOpen = false; // choosing a bait OR a CaptureBarScreen is pushed

  /// True while the command deck (the right-hand box) has turned into the
  /// bait list (user 2026-10-04: "soll im Kampfscreen die Rechte Box zum
  /// Inventar werden") — a full takeover of [_deckBody], not a 4th tab
  /// beside Attack/Items/Change, since there is nothing to browse back to
  /// mid-pick. False again the moment a bait is thrown or the pick is
  /// cancelled; [_catchOpen] stays true a little longer, through the
  /// pushed minigame itself.
  bool _choosingBait = false;

  /// The wild being attempted and the monster attempting it, captured once
  /// at [_startCatch] time and reused at resolution — up to 3 wilds and 3
  /// hunters can be on the field at once (2026-09-11), so reading
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

  /// Guards the auto-pop below from firing twice while outcome stays
  /// victory across however many rebuilds happen before the route is
  /// actually gone.
  bool _autoPoppedCaptureVictory = false;

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
            // Also explains WHY the number grows (user 2026-09-30: "erklären,
            // dass mehr AP regeneriert werden, wenn die Monster im Level
            // steigen"), not just what it is right now.
            'AP — every move spends Action Points; you regain $regen per '
                'turn, up to $cap. Level your monsters up for more.',
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
      // The Items TAB first; once it is open, the first item's Use button.
      _ScriptBeat.healItem =>
        _deckTab == _DeckTab.items ? 'battle-item-use' : 'battle-items-btn',
      _ScriptBeat.missedAttack ||
      _ScriptBeat.powerAttack => 'battle-first-ability',
      _ScriptBeat.typeChartPrompt => 'battle-typechart-btn',
      _ScriptBeat.bankEndTurn => 'battle-endturn-btn',
      // Bottom-left, the pricier element move (user 2026-09-05: "hier immer
      // die Attacke unten links (4 AP) wählen lassen") — not plain Attack.
      _ScriptBeat.finisher => 'battle-second-ability',
      _ => null,
    };
  }

  String? get _scriptedBattleHint => switch (_scriptBeat) {
    // Fuller line (user 2026-09-30, was the bare "Attack!"): "Attack: Now
    // it's time to attack your opponent."
    _ScriptBeat.tackle => "Now it's time to attack your opponent.",
    _ScriptBeat.healItem => 'That hurt — use your potion to heal up.',
    _ScriptBeat.missedAttack => 'Follow up with your ability.',
    _ScriptBeat.powerAttack => 'Follow up with your ability.',
    _ScriptBeat.typeChartPrompt =>
      "Tap the type chart to see what's effective against what.",
    // Names WHY ending early is sometimes the right call (user 2026-09-30:
    // "erklären... es manchmal sinnvoll ist, einen Zug frühzeitig zu
    // beenden, da die verbleibenden AP in die nächste Runde übernommen
    // werden können und so mächtige Angriffe möglich werden").
    _ScriptBeat.bankEndTurn =>
      'Sometimes it pays to end a turn early — the AP you save carries '
          'into the next one, enough for a bigger attack.',
    // Names the stakes, not just the command (user 2026-09-30: "der Kampf
    // ist auf des Messers Schneide und du musst nun alles riskieren").
    _ScriptBeat.finisher =>
      "Finish it! The fight is on a knife's edge — risk everything now.",
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

  /// Snaps the acting combatant to the tutorial's one enemy — the mirror of
  /// the `forceActing(me)` calls in [_runScriptedEnemyBeat], used after every
  /// PLAYER beat that the script expects an enemy reply to follow
  /// immediately. See the tackle case in [_useAbility] for why this is
  /// needed at all: real speed otherwise still decides who the CTB queue
  /// hands the next turn to, and the script does not tolerate that.
  void _forceHandoffToEnemy() {
    final foe = _engine.activeEnemy;
    if (foe != null) _engine.forceActing(foe);
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

  /// True only for the "Miss" explainer (user 2026-09-30: "Hier musst du
  /// nicht das eigene Monster highlighten") — every other [_scriptInfoHint]
  /// anchors to 'battle-hp' purely for lack of a more specific target, but
  /// at least genuinely followed from something that just happened to an
  /// HP total (a hit, a debuff, a crit). A miss changes nothing, so a glow
  /// ring around the player's own monster there implies a connection that
  /// is not actually there.
  bool _scriptInfoNoRing = false;

  void _dismissScriptInfo() {
    setState(() {
      _scriptInfoHint = null;
      _scriptInfoNoRing = false;
    });
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
    if (widget.isPvp) {
      // On screen: my own turn coming round is not news to me.
      PvpNotifier.instance.openBattleId = widget.pvpMatch!.id;
      _startPvpSync();
    }
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
    // Entry animation (user 2026-07-24): the fighters slide onto the field
    // before the fight begins, so the combat has a proper "Auftritt". The
    // action loop is held until they've arrived.
    // NO per-frame setState here (2026-09-21). The slide is already driven by
    // the AnimatedBuilder around each rank in [_bigSprite]'s caller, which
    // rebuilds only the Transform and keeps its `child` — so a listener that
    // called setState was rebuilding this entire ~6k-line screen sixty times
    // a second for the 620 ms the fighters take to walk on, which is the one
    // moment in a battle when the frame budget is already fullest.
    _entry =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 620),
        )..addStatusListener((s) {
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
    //
    // BYTES, NOT A DECODE, off the web (2026-09-21). [CreatureSprite] caps
    // every sprite's decode with `memCacheWidth`, so it resolves a
    // `ResizeImage(CachedNetworkImageProvider(url), width: …)` — while
    // `precacheImage(NetworkImage(url))` filed a full-resolution decode
    // under a different ImageCache key AND fetched through Flutter's own
    // HttpClient, which shares nothing with flutter_cache_manager's store.
    // On mobile it therefore closed neither half of the gap: not the fetch,
    // not the decode. Pulling the file into the same store the sprite reads
    // from closes the fetch, which is the slow half. Web keeps the old path:
    // there [CreatureSprite] draws through `Image.network`, so this really
    // does warm the browser's cache for it, and six sprites is a decode cost
    // worth paying to keep the first swing from animating a placeholder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cache = kIsWeb ? null : DefaultCacheManager();
      for (final c in [..._engine.players, ..._engine.enemies]) {
        for (final url in {c.imageUrl, c.backImageUrl}) {
          if (url == null) continue;
          if (cache == null) {
            precacheImage(NetworkImage(url), context).catchError((_) {});
          } else {
            cache.downloadFile(url).then((_) {}, onError: (Object _) {});
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _turnCountdownTimer?.cancel();
    _flashTimer?.cancel();
    _fx.dispose();
    _fxReact.dispose();
    _fxStatus.dispose();
    _fxKo.dispose();
    _entry.dispose();
    _idle.dispose();
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    if (widget.isPvp) {
      _pvpSync.disconnect();
      if (PvpNotifier.instance.openBattleId == widget.pvpMatch!.id) {
        PvpNotifier.instance.openBattleId = null;
      }
    }
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
    final myId = supabase.auth.currentUser!.id;
    for (final raw in match.actionLog) {
      _applyRemoteAction(PvpAction.fromJson(raw), checkDesync: false);
    }
    _pvpSync.connect(
      matchId: match.id,
      myUserId: myId,
      opponentUserId: match.otherUserId(myId),
      resumeFromSeq: match.actionLog.length,
      onRemoteAction: _applyRemoteAction,
    );
  }

  /// Builds a completely fresh [CombatEngine] from the match's FROZEN team
  /// snapshots (the same construction [PvpLobbyScreen._goToBattle] did) —
  /// used by [_handleDesync] to discard a diverged engine rather than trying
  /// to patch its already-wrong mutable state. My own side rebuilds from
  /// [widget.team] (live [CreatureInstance]s, untouched by the engine —
  /// [Combatant.fromInstance] only ever reads their pre-battle hp); the
  /// opponent's side must come from the persisted snapshot JSON instead,
  /// since [widget.enemies] IS the live, already-mutated [Combatant] list
  /// the diverged engine has been writing hp/status into directly.
  CombatEngine _buildFreshEngine() {
    final match = widget.pvpMatch!;
    final myId = supabase.auth.currentUser!.id;
    final oppSnapshot = match.playerA == myId ? match.teamB! : match.teamA!;
    return CombatEngine(
      players: widget.team.map(Combatant.fromInstance).toList(),
      enemies: [
        for (final j in oppSnapshot)
          combatantFromSnapshot(j, isPlayerSide: false),
      ],
      isPvp: true,
      rng: math.Random(widget.pvpSeed!),
    );
  }

  /// A remote action's [PvpAction.stateHash] didn't match my own post-apply
  /// [CombatEngine.stateHash] — the two independently-run engines have
  /// quietly diverged (bug/race condition; see the migration's doc comment).
  /// Self-heals by rebuilding from scratch ([_buildFreshEngine]) and
  /// replaying the match's persisted, canonical `action_log` — the exact
  /// mechanism [_startPvpSync] already uses for an ordinary reconnect, just
  /// triggered mid-fight instead. Reports the mismatch either way
  /// ([PvpService.reportDesync]) so a divergence that keeps happening is
  /// visible in the data even though a player only ever sees a brief, silent
  /// re-sync (never a crash).
  Future<void> _handleDesync(PvpAction mismatchedAction) async {
    if (_resyncing) return; // already fixing one; don't pile on
    _resyncing = true;
    try {
      final matchId = widget.pvpMatch!.id;
      unawaited(
        _pvpService.reportDesync(
          matchId,
          seq: mismatchedAction.seq,
          myHash: '${_engine.stateHash}',
          expectedHash: mismatchedAction.stateHash?.toString(),
        ),
      );
      final fresh = await _pvpService.loadMatch(matchId);
      _engine.removeListener(_onEngineChanged);
      _engine.dispose();
      _engine = _buildFreshEngine();
      _engine.addListener(_onEngineChanged);
      for (final raw in fresh.actionLog) {
        _applyRemoteAction(PvpAction.fromJson(raw), checkDesync: false);
      }
      if (mounted) setState(() {});
    } finally {
      _resyncing = false;
    }
  }

  /// Applies one relayed action (mine or the opponent's — see
  /// pvp_sync_service.dart's own doc on why the dispatch doesn't need to
  /// know which) directly to [_engine]. [_onEngineChanged] (already wired
  /// via [ChangeNotifier]) picks up the resulting notify exactly like any
  /// local action would.
  ///
  /// [checkDesync] is false while replaying a persisted `action_log` (the
  /// initial reconnect catch-up in [_startPvpSync], or [_handleDesync]'s own
  /// resync) — those hashes were already valid when first sent; rechecking
  /// them against a freshly-built engine would either be redundant or, if it
  /// somehow still disagreed, risk piling resync attempts on top of each
  /// other (guarded anyway by [_resyncing], but there's no reason to invite
  /// it). It stays true for the normal, live broadcast path.
  void _applyRemoteAction(PvpAction action, {bool checkDesync = true}) {
    final actor = _findCombatant(action.actorId);
    if (actor == null) return;
    final myId = supabase.auth.currentUser!.id;
    switch (action.kind) {
      case 'attack':
        final target = _findCombatant(action.targetId);
        if (target != null) _engine.basicAttack(actor, target);
      case 'ability':
        final ability = action.abilityId == null
            ? null
            : kAbilityDefs[action.abilityId];
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
        // [action.senderId] is who actually gave up — NOT [actor], which is
        // decorative for this kind (see [_confirmFlee]'s doc). This method
        // also replays my OWN past actions during a reconnect catch-up (see
        // [_startPvpSync]), so unconditionally assuming "the opponent fled"
        // here used to falsely flip a reloaded give-up into a win: an old
        // senderId-less log entry (recorded before this field existed) has
        // no way to tell, so it falls back to the old, still-wrong "assume
        // opponent" behaviour rather than crashing.
        _pvpOpponentFled = action.senderId == null || action.senderId != myId;
        _engine.flee();
    }
    if (checkDesync &&
        action.stateHash != null &&
        action.stateHash != _engine.stateHash) {
      unawaited(_handleDesync(action));
    }
    if (widget.isPvp) _syncTurnStateIfNeeded();
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
      // The LOCAL engine already applied this action (see this method's own
      // doc), so [_engine.stateHash] here already reflects the post-action
      // state — exactly what the receiving side should independently arrive
      // at too.
      stateHash: _engine.stateHash,
      // Who actually sent this — see [PvpAction.senderId]'s doc. Needed so a
      // reconnect replaying this same entry back out of `action_log` (which
      // runs every action, mine included, through [_applyRemoteAction]) can
      // still tell it apart from a genuine live receipt from the opponent.
      senderId: supabase.auth.currentUser!.id,
    );
    _syncTurnStateIfNeeded();
  }

  /// Recomputes whose decision the match is currently waiting on — a fresh
  /// [PvpService.advanceTurn] write (and local timer restart) only happens
  /// when that decision-point actually CHANGED (a new key), so calling this
  /// after every action is cheap and safe. "Waiting on" covers a pending
  /// switch-in choice too (a fainted slot with a bench to fill), not just
  /// whoever's [CombatEngine.currentActor] — both are moments the OTHER side
  /// is stuck without my input, or vice versa.
  void _syncTurnStateIfNeeded() {
    if (!widget.isPvp || _engine.outcome != null) return;
    final key =
        '${_engine.needsPlayerSwitch}|${_engine.needsEnemySwitch}|${_engine.currentActor.id}';
    if (key == _turnWindowKey) return;
    _turnWindowKey = key;

    final myId = supabase.auth.currentUser!.id;
    final opponentId = widget.pvpMatch!.otherUserId(myId);
    final waitingOn = _engine.needsPlayerSwitch
        ? myId
        : _engine.needsEnemySwitch
        ? opponentId
        : (_engine.currentActor.isPlayerSide ? myId : opponentId);

    _waitingOnId = waitingOn;
    _turnDeadline = DateTime.now().add(_kPvpTurnTimeout);
    _pvpService.advanceTurn(
      widget.pvpMatch!.id,
      waitingOnUserId: waitingOn,
      deadlineSeconds: _kPvpTurnTimeout.inSeconds,
    );
    _restartTurnCountdown();
  }

  void _restartTurnCountdown() {
    _turnCountdownTimer?.cancel();
    _turnCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _turnCountdownTimer?.cancel();
        return;
      }
      setState(() {}); // only repaints the countdown banner
      _maybeClaimTimeout();
    });
  }

  /// Fires once per second while the countdown banner is up (see
  /// [_restartTurnCountdown]): if the OPPONENT is who we're waiting on and
  /// their deadline has passed, attempts the server-authoritative timeout
  /// claim. A rejection (they actually acted just in time, the server clock
  /// disagrees slightly, …) is expected often enough to be routine — the
  /// next [_syncTurnStateIfNeeded] call simply supersedes this attempt, so
  /// failures are silently swallowed rather than surfaced.
  Future<void> _maybeClaimTimeout() async {
    if (_claimingTimeout || !widget.isPvp || _engine.outcome != null) return;
    final myId = supabase.auth.currentUser!.id;
    final opponentId = widget.pvpMatch!.otherUserId(myId);
    if (_waitingOnId != opponentId) return;
    final deadline = _turnDeadline;
    if (deadline == null || DateTime.now().isBefore(deadline)) return;

    _claimingTimeout = true;
    try {
      await _pvpService.claimTimeoutWin(widget.pvpMatch!.id);
      if (!mounted) return;
      // Same path a relayed 'flee' takes (see [_pvpOpponentFled]'s doc) —
      // the server already recorded the win; this just drives MY OWN local
      // outcome UI/effects through the one mechanism that already exists.
      _pvpOpponentFled = true;
      _engine.flee();
      setState(() {});
    } catch (_) {
      // Not eligible yet (or any other RPC error) — ignored, see this
      // method's own doc comment.
    } finally {
      _claimingTimeout = false;
    }
  }

  void _onEngineChanged() {
    if (!mounted) return;
    // Covers the very FIRST decision point too (before any action has been
    // sent or received) — [_applyRemoteAction]/[_relayPvpAction]'s own calls
    // only fire once something has actually happened.
    if (widget.isPvp) _syncTurnStateIfNeeded();
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
    // More stars, more XP (user 2026-09-28) — only in a numbered campaign fight.
    final bonus = _stars?.xpMultiplier ?? 1.0;
    return (_engine.totalXpReward / _engine.players.length * bonus).round();
  }

  /// How the fight was judged, once it is won — null for anything that is not a
  /// numbered campaign battle (and while it is still running).
  BattleStars? get _stars =>
      widget.battleNumber == null ||
          widget.isPvp ||
          _engine.outcome != CombatOutcome.victory
      ? null
      : judgeBattle(won: true, players: _engine.players);

  Future<void> _applyOutcome() async {
    if (_outcomeApplied) return;
    _outcomeApplied = true;
    // The verdict is heard the moment it falls (a win: the fanfare; a loss:
    // the refusal buzz) — the fight's own music stops with the screen.
    if (_engine.outcome == CombatOutcome.victory) {
      Feel.fanfare();
    } else if (_engine.outcome == CombatOutcome.defeat) {
      Feel.deny();
    }
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
    final stars = _stars;
    final ups = await CreaturesController().applyBattleOutcome(
      _engine.players,
      xpEach: _xpEach,
    );
    // The record, and the one-time gold for stars reached for the first time.
    var starGold = 0;
    if (stars != null) {
      starGold = await SettlementController().recordBattleStars(
        widget.battleNumber!,
        stars.count,
      );
    }
    if (mounted) {
      setState(() {
        _levelUps = ups;
        _starGold = starGold;
      });
    }
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
    // Real speed decides turn order everywhere else, but the tutorial's
    // script assumes strict alternation (user 2026-09-30: "Die
    // Geschwindigkeit darf keine Rolle spielen... Vineguard hat nun zwei
    // Züge bevor Infernoclaw am Zug ist"). A starter faster than its
    // counter-picked opponent otherwise wins the real CTB race for a second
    // turn before the enemy's scripted reply ever fires — the mirror image
    // of [_runScriptedEnemyBeat]'s own `forceActing(me)` calls, which guard
    // the same race in the other direction. MUST run in this same
    // synchronous stretch, right after the action that just fired
    // notifyListeners — see `_runScriptedEnemyBeat`'s enemyBigHit case for
    // why: a later microtask reads `currentActor` before an awaited
    // continuation would ever get the chance to.
    if ((_scriptBeat == _ScriptBeat.tackle && ability.id == 'attack') ||
        _scriptBeat == _ScriptBeat.missedAttack) {
      _forceHandoffToEnemy();
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
          _scriptInfoNoRing = true;
        });
      case _ScriptBeat.powerAttack:
        setState(() {
          // typeChartPrompt, not bankEndTurn directly (user 2026-09-30) —
          // see the type detour documented on that beat's own declaration.
          _scriptBeat = _ScriptBeat.typeChartPrompt;
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

  /// Sends [chosen] in from the bench — the Change tab's "Send in" (and the
  /// forced replacement after a K.O., where the same page is the only one shown).
  void _switchTo(Combatant chosen) {
    final idx = _engine.players.indexOf(chosen);
    final err = _engine.switchActivePlayer(idx);
    if (err != null) {
      _showError(err);
      return;
    }
    _relayPvpAction(kind: 'switch', actor: chosen);
    // The new monster is up: back to its moves.
    if (mounted) setState(() => _deckTab = _DeckTab.attack);
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

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              if (widget.isPvp) _pvpConnectionBanner(),
              // ONE arena and the command deck beside it, both the FULL height
              // (user 2026-09-21: "das HUD rechts wird bis nach oben erweitert,
              // gleiches Padding wie unten"): the top bar is gone — the turn order,
              // the keys and the waiting monsters live on the arena itself (see
              // [_arena]). LANDSCAPE (2026-09-18): the arena takes the left, the
              // command deck the right.
              Expanded(
                // The field runs the FULL width and the command bar lies along
                // its bottom edge (user 2026-11-04) — see [_commandLayer].
                child: Stack(
                  children: [
                    Positioned.fill(child: _arena()),
                    _commandLayer(context),
                  ],
                ),
              ),
            ],
          ),
          if (_floats.isNotEmpty) _floatsLayer(),
          // Held back while a [_scriptInfoHint] is still showing (user
          // 2026-09-04: the finisher's crit explainer must not fight the win
          // screen for the same pixels) — the real engine has usually
          // already recorded the outcome by this point regardless.
          if (_engine.outcome != null && _scriptInfoHint == null) _endOverlay(),
          // Dimmed like every other tutorial step now (user 2026-09-30,
          // reversing the 2026-09-03 decision that used to live here: "bitte
          // jeweils ganze Seite ausgrauen" / "alles andere ausgrauen...
          // Dies bei allen Tutorialschritten während des Kampfes machen") —
          // watching the fight play out mattered less than the rest of the
          // guided intro's own rule of dimming everything but the one lit
          // target.
          if (_battleCallout != null)
            IntroSpotlightOverlay(
              anchorName: _battleCalloutAnchors[_battleCallout!],
              hint: _battleCalloutHints[_battleCallout!],
              onScrimTap: _advanceBattleCallout,
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
              // The type-chart key is round, like the HP ring the four
              // opening callouts already special-case — a facet border
              // would box in far more than just the key.
              circular: _scriptBeat == _ScriptBeat.typeChartPrompt,
            ),
          // A window with NOTHING to press — the enemy's own scripted turn
          // (user 2026-09-30: "während den Attacken soll der ganze Screen
          // frei sein (nicht abgedunkelt) aber ich kann nichts anwählen,
          // bis der nächste Tutorialschritt kommt"): left undimmed so the
          // hit actually plays out on a clear screen, but still fully dead
          // — nothing here is a control this beat authored.
          if (_isFirstBattleTutorial &&
              _battleCallout == null &&
              _scriptBeat != null &&
              _scriptInfoHint == null &&
              _scriptedBattleAnchor == null)
            const IntroBlockOverlay(),
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
              // Miss gets neither (user 2026-09-30: "nur der Text ist
              // gehighlighted, sonst nichts") — there is nothing relevant to
              // ring, and darkening the screen for one floating line has
              // nothing else to justify it either; see [showRing]'s own doc.
              showRing: !_scriptInfoNoRing,
              dim: !_scriptInfoNoRing,
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
        // The battlefield (see BattleScene) is painted behind the whole screen
        // by [body]; this is only what shows before it does.
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
          // ONE battlefield behind EVERYTHING (user 2026-09-21: "den Kampfscreen/
          // Hintergrund durchgehend machen"): the ground says WHERE you are and
          // each monster's own plate says WHAT it is (see widgets/battle_scene).
          // The top bar and the command deck stand directly on it.
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: BattleScene(
                  imageUrl: widget.area?.imageUrl,
                  era: widget.area?.battleStage ?? 1,
                ),
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }

  /// The battlefield with everything that stands ON it (user 2026-09-21): the two
  /// ranks with the log on the seam between them, the turn order centred at the
  /// top with the keys (flee, type chart, AUTO) at its top right, and the monsters
  /// still waiting as small tiles down the LEFT edge — the enemy's at the top, mine
  /// under the log. The command deck is the only thing beside it, and it now runs
  /// the full height too.
  Widget _arena() => LayoutBuilder(
    builder: (context, box) => Stack(
      children: [
        // The battlefield itself is not drawn here: it runs behind the WHOLE
        // screen (see [build]). SIDE VIEW (user 2026-11-04): my monsters stand
        // at the left, the enemy's at the right, on the same ground.
        Transform.translate(
          offset: Offset(0, box.maxHeight * _kArenaDrop),
          child: Stack(children: [Positioned.fill(child: _formation(box))]),
        ),
        // The log sits in the free bottom-left corner above the command bar,
        // clear of both ranks (user 2026-11-08: it was in the wrong place).
        Positioned(
          left: 66,
          top: 8,
          child: SizedBox(
            width: (box.maxWidth / 2 - 224).clamp(140.0, 300.0),
            child: _logLine(),
          ),
        ),
        _arenaHud(box.maxWidth),
        Positioned(
          left: 6,
          top: 56,
          child: _benchColumn(_engine.benchedPlayers, isEnemy: false),
        ),
        Positioned(
          right: 6,
          top: 56,
          child: _benchColumn(_engine.benchedEnemies, isEnemy: true),
        ),
      ],
    ),
  );

  /// The height of the command bar along the bottom edge; the ground ends above
  /// it.
  static const double _kBarH = 58;

  /// Where a slot's FEET stand, as fractions of the ground (its width, its
  /// height above the bar). ISOMETRIC FOREST ARENA (user 2026-11-08): my rank
  /// runs along the lower-left diagonal of the clearing, the enemy's along the
  /// upper-right one, the two facing each other across it. Index = slot; slot 2
  /// is the one standing furthest back, the spot lowest on screen is nearest.
  static const List<Offset> _kSpotsMine = [
    // Neighbours are >= 0.15 of the width apart (a plate is at most ~132 px),
    // the middle stays free, and nobody stands high enough to reach the turn
    // order — so no plate can touch another or sit on a monster.
    // Three DIFFERENT depths (user 2026-11-08: "in der Höhe etwas mehr versetzt,
    // damit es mehr Platz gibt") — front, middle, back, so plates and monsters
    // stagger instead of sharing a row.
    // (user 2026-11-08: "die Monster stehen sich zu wenig gegenüber") Each rank
    // is a line running up-left → down-right, and the two lines are PARALLEL,
    // offset along the diagonal (lower-left vs upper-right) — so every monster
    // looks across the middle at an opponent instead of standing beside it at
    // the same height.
    Offset(0.32, 0.72),
    Offset(0.18, 0.58),
    Offset(0.46, 0.86),
  ];
  static const List<Offset> _kSpotsFoe = [
    Offset(0.68, 0.50),
    Offset(0.54, 0.36),
    Offset(0.82, 0.64),
  ];

  /// The size of the ground the formation was last laid out on, so the lunge
  /// can find where a combatant's feet are without a LayoutBuilder of its own.
  Size? _groundSize;

  Offset _spotFor(int slot, bool isEnemy, int liveCount) {
    final spots = isEnemy ? _kSpotsFoe : _kSpotsMine;
    // A lone monster stands in the middle spot of its rank.
    return liveCount == 1 ? spots[0] : spots[slot % spots.length];
  }

  /// Where [c]'s feet are on screen, or null before the first layout.
  Offset? _footOf(Combatant c) {
    final g = _groundSize;
    if (g == null) return null;
    final field = c.isPlayerSide ? _engine.playerField : _engine.enemyField;
    final slot = field.indexWhere((f) => identical(f, c));
    if (slot < 0) return null;
    final live = field.where((f) => f != null && f.alive).length;
    final s = _spotFor(slot, !c.isPlayerSide, live);
    return Offset(s.dx * g.width, s.dy * g.height);
  }

  /// Unit vector from [c] toward [target] on screen — the way a lunge runs.
  /// Falls back to the rank's own diagonal when either is unknown.
  Offset _lungeDir(Combatant c, Combatant? target) {
    final a = _footOf(c);
    final b = target == null ? null : _footOf(target);
    final v = (a != null && b != null)
        ? b - a
        : Offset(c.isPlayerSide ? 1.0 : -1.0, c.isPlayerSide ? -0.5 : 0.5);
    final d = v.distance;
    return d < 1 ? Offset(c.isPlayerSide ? 1.0 : -1.0, 0) : v / d;
  }

  /// Whether [c] is drawn from the isometric sheets (see
  /// [MonsterSheets.battleIso]) — those stand lower in their box and overflow
  /// it upwards, so their slot is cut shorter than a flat sprite's.
  bool _isIso(Combatant? c) =>
      c == null ||
      MonsterSheets.battleIso(c.speciesId, c.stage, mine: c.isPlayerSide) !=
          null;

  /// The two sides standing on the ground, back to front (user 2026-11-04,
  /// side view). Each monster is a [_fieldSlot]: its plate above its head, its
  /// feet in a shadow. A lone monster stands in the middle spot of its side.
  Widget _formation(BoxConstraints box) {
    final w = box.maxWidth;
    final groundH = box.maxHeight - _kBarH;
    final slotW = (w * 0.2).clamp(104.0, 210.0);
    final flatH = (groundH * 0.44).clamp(80.0, 180.0);
    // An isometric monster's body is low: its slot only has to hold the part of
    // it standing above the feet, the sheet's empty top overflows past it.
    final isoH = (groundH * 0.30).clamp(70.0, 170.0);
    const plateH = 44.0;
    _groundSize = Size(w, groundH);
    final placed = <(double, Widget)>[];
    for (final isEnemy in const [true, false]) {
      final field = isEnemy ? _engine.enemyField : _engine.playerField;
      final live = [
        for (var i = 0; i < CombatEngine.kFieldSlots; i++)
          // A slot whose occupant just fainted stays for the length of its
          // K.O. presentation (user 2026-08-29).
          if ((field[i] != null && field[i]!.alive) ||
              _koPlaying.values.any(
                (e) => e.slot == i && e.isEnemy == isEnemy,
              ))
            i,
      ];
      for (final i in live) {
        final spot = _spotFor(i, isEnemy, live.length);
        final cx = spot.dx * w;
        final foot = spot.dy * groundH;
        final spriteH = _isIso(field[i]) ? isoH : flatH;
        final top = math.max(64.0, foot - spriteH - plateH);
        placed.add((
          foot,
          Positioned(
            left: cx - slotW / 2,
            top: top,
            width: slotW,
            height: foot - top,
            child: _fieldSlot(
              field[i],
              slot: i,
              isEnemy: isEnemy,
              width: slotW,
              // No size wedge any more: the camera is orthographic, so a
              // monster standing further back is as large as one in front.
              back: false,
              // The HP callout points at ONE plate: the first live slot on MY
              // side (user 2026-09-04).
              hpAnchor: !isEnemy && i == live.first,
            ),
          ),
        ));
      }
    }
    placed.sort((a, b) => a.$1.compareTo(b.$1));
    return Stack(children: [for (final p in placed) p.$2]);
  }

  // ── The command bar (user 2026-11-04, "Fußleiste 6") ────────────────────────
  // One row along the bottom: the three tabs, the AP, and — on Attack — the
  // abilities. Items and Change open their page as a card above the bar; the
  // bait pick does the same. The old cream deck beside the arena is gone, the
  // field runs the full width.
  Widget _commandLayer(BuildContext context) {
    const blank = Positioned.fill(child: SizedBox.shrink());
    // Held off exactly as long as [_endOverlay] itself is.
    if (_engine.outcome != null && _scriptInfoHint == null) return blank;
    final forced = _engine.needsPlayerSwitch;
    final actor = _engine.activePlayer;
    Widget? popup;
    double? popupH;
    Widget bar;
    if (_entering) {
      bar = const Center(
        child: Text(
          'Get ready…',
          style: TextStyle(fontSize: 15, color: Color(0xFFF3E6C6)),
        ),
      );
    } else if (_choosingBait) {
      popup = _baitPage();
      bar = const SizedBox.shrink();
    } else if (!forced && actor == null) {
      return blank;
    } else {
      final tab = _shownTab;
      if (tab == _DeckTab.items && actor != null) popup = _itemsPage(actor);
      if (tab == _DeckTab.change) popup = _changePage(actor, forced);
      // The (i) on a tile (or a long press) opens that ability's description
      // above the bar; a tap on the card closes it.
      final info = actor == null ? null : _infoAbilityFor(actor);
      if (tab == _DeckTab.attack && _infoAbilityId != null && info != null) {
        popup = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _infoAbilityId = null),
          child: _abilityInfoBox(info),
        );
        popupH = 210;
      }
      bar = Row(
        children: [
          SizedBox(width: 144, child: _deckTabs(tab, forced)),
          const SizedBox(width: 12),
          if (actor != null) ...[
            KeyedSubtree(
              key: IntroSpotlightAnchors.of('battle-ap'),
              child: _apPips(actor.ap, maxActionPointsForStage(actor.stage)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: (actor != null && !forced)
                ? _abilityRow(actor, _myTurn, _infoAbilityFor(actor))
                : const SizedBox.shrink(),
          ),
          // End turn, and Catch where this encounter can ever be caught (they
          // lived under the ability grid in the old deck).
          if (actor != null && !forced) ...[
            const SizedBox(width: 8),
            if (widget.isCapture) ...[
              SizedBox(
                width: 78,
                height: 40,
                child: _deckTile(
                  'Catch',
                  Icons.catching_pokemon,
                  enabled: _myTurn && _canCatch,
                  onTap: _startCatch,
                ),
              ),
              const SizedBox(width: 6),
            ],
            SizedBox(
              width: 92,
              child: KeyedSubtree(
                key: IntroSpotlightAnchors.of('battle-endturn-btn'),
                child: SocialGoldButton(
                  'End turn',
                  height: 40,
                  fontSize: 13,
                  onTap: _myTurn ? _endTurn : null,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final ph = (box.maxHeight - _kBarH - 64).clamp(160.0, 320.0);
          return Stack(
            children: [
              if (popup != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: _kBarH + 6,
                  child: Center(
                    child: SizedBox(
                      width: 340,
                      height: popupH ?? ph,
                      child: creamCard(
                        padding: const EdgeInsets.all(10),
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(height: 1.15),
                          child: popup,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _kBarH,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF6B4528),
                    border: Border(
                      top: BorderSide(color: Color(0xFF0B1E27), width: 2),
                    ),
                  ),
                  child: bar,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The abilities as ONE row of tiles (the same tiles, the same anchors as the
  /// old 2×2 grid — see [_abilityBtn]).
  Widget _abilityRow(Combatant actor, bool myTurn, AbilityDef? info) {
    return KeyedSubtree(
      key: IntroSpotlightAnchors.of('battle-actions'),
      child: IgnorePointer(
        ignoring:
            _battleCallout != null &&
            _battleCalloutAnchors[_battleCallout!] == 'battle-actions',
        child: Builder(
          builder: (context) {
            final firstReal = _firstRealAbility(actor);
            final secondReal = _secondRealAbility(actor);
            return Row(
              children: [
                for (var i = 0; i < actor.abilities.length; i++) ...[
                  if (i > 0) const SizedBox(width: _kTileGap),
                  Expanded(
                    child: _maybeAnchoredAbilityTile(
                      actor.abilities[i],
                      firstReal,
                      secondReal,
                      _abilityBtn(
                        actor.abilities[i].name,
                        _effectiveApCost(actor.abilities[i]),
                        element: actor.abilities[i].element,
                        enabled:
                            myTurn &&
                            actor.ap >= _effectiveApCost(actor.abilities[i]),
                        onTap: () {
                          _useAbility(actor.abilities[i]);
                        },
                        ability: actor.abilities[i],
                        selected: identical(actor.abilities[i], info),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ── The command deck (user 2026-09-20, "Variante 7 — Reiter") ──────────────
  //
  // A cream Holz card on the right with THREE TABS: Attack | Items | Change.
  // Items and Change used to open bottom sheets over the fight; they are pages of
  // the deck itself now, so nothing ever covers the arena. The Attack page holds
  // the actor row (portrait, name, level, HP, AP), the ability tiles, an info box
  // for the picked ability — which replaces the long-press sheet — and End turn.
  //
  // The tutorial's anchors all live here; see [_scriptedBattleAnchor].

  static const double _kTabH = 32;
  static const double _kTileH = 46;
  static const double _kTileGap = 8;

  /// MY turn = actionable. During the enemy's turn (or auto-battle) the same
  /// controls show but are greyed and inert (user 2026-07-18). `!_presenting`
  /// too (user 2026-08-29) — the engine's own turn flips to the player the
  /// instant an enemy's action resolves, before that action's lunge/react has
  /// finished PLAYING; see [_presenting]'s own doc for what tapping in that gap
  /// used to break.
  bool get _myTurn =>
      _engine.outcome == null &&
      !_engine.needsPlayerSwitch &&
      _engine.isPlayerTurn &&
      !_autoBattle &&
      !_presenting;

  /// The page the deck actually shows. A forced switch always shows Change; the
  /// tutorial's scripted fight keeps every beat but the potion on Attack, so a
  /// stray tap on another tab during an enemy beat can't hide the lit control.
  _DeckTab get _shownTab {
    if (_engine.needsPlayerSwitch) return _DeckTab.change;
    if (_isFirstBattleTutorial &&
        _scriptBeat != null &&
        _scriptBeat != _ScriptBeat.healItem) {
      return _DeckTab.attack;
    }
    return _deckTab;
  }

  /// The ability the info box describes: the one last picked (long-press or
  /// used), else the first real ability — the plain Attack needs no explaining.
  AbilityDef? _infoAbilityFor(Combatant actor) {
    final all = actor.abilities;
    if (all.isEmpty) return null;
    for (final a in all) {
      if (a.id == _infoAbilityId) return a;
    }
    return all.length > 1 ? all[1] : all.first;
  }

  Widget _deckTabs(_DeckTab shown, bool forced) {
    // Tabs are always browsable — the pages grey their own actions when it is
    // not your turn — except in a forced switch (only Change makes sense) and in
    // the scripted fight, where only the potion beat opens anything.
    final canTap =
        !forced &&
        (!_isFirstBattleTutorial || _scriptBeat == _ScriptBeat.healItem);
    Widget tab(_DeckTab t, IconData icon, String label, {String? anchor}) {
      final on = shown == t;
      Widget button = Pressable(
        // No Attack tab (user 2026-11-04: "die Kampffähigkeiten können so
        // immer angezeigt werden"): the abilities are always on the bar, so
        // Items and Change are toggles — a second tap closes the page again.
        onTap: canTap
            ? () => setState(() => _deckTab = on ? _DeckTab.attack : t)
            : null,
        child: Container(
          height: _kTabH,
          alignment: Alignment.center,
          decoration: on ? goldButton() : raisedTile(radius: 11),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PixelIcon(icon, size: 14, color: on ? kBoxInk : kBoxInkSoft),
                const SizedBox(width: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: on ? kBoxInk : kBoxInkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (anchor != null) {
        button = KeyedSubtree(
          key: IntroSpotlightAnchors.of(anchor),
          child: button,
        );
      }
      return Expanded(child: button);
    }

    return Padding(
      // Room for the tabs' own 3px drop shadow.
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          tab(
            _DeckTab.items,
            Icons.backpack,
            'Items',
            anchor: 'battle-items-btn',
          ),
          const SizedBox(width: 6),
          tab(_DeckTab.change, Icons.swap_horiz, 'Change'),
        ],
      ),
    );
  }

  // ── Attack page ───────────────────────────────────────────

  Widget _creamHpBar(int hp, int maxHp, double frac) => Row(
    children: [
      Expanded(
        child: RecessBar(value: frac, color: _hpColor(frac), height: 8),
      ),
      const SizedBox(width: 5),
      Text(
        '$hp/$maxHp',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: kBoxInkSoft,
        ),
      ),
    ],
  );

  /// THE ACTION POINTS — a row of small chips over the moves they pay for. Spent
  /// points are not hidden, they are EMPTIED: what you had this turn is as much
  /// a part of the read as what is left.
  Widget _apPips(int ap, int maxAp) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'AP',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          color: kBoxAccent,
        ),
      ),
      const SizedBox(width: 6),
      for (var i = 0; i < maxAp; i++)
        Container(
          margin: const EdgeInsets.only(right: 4),
          width: 16,
          height: 8,
          decoration: BoxDecoration(
            color: i < ap ? CreamPalette.gold : Colors.transparent,
            borderRadius: vr(3),
            border: Border.all(
              color: i < ap ? CreamPalette.goldDeep : CreamPalette.tan,
              width: 1.2,
            ),
          ),
        ),
    ],
  );

  // ── Bait page (the deck turned into the bag, user 2026-10-04) ──

  Widget _baitPage() {
    if (widget.guaranteedCatch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageHeading('Choose your bait', 'tutorial — never spent'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                _deckRow(
                  leading: Text(
                    practiceBait.emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: practiceBait.name,
                  detail: Text(
                    'Start ${(practiceBait.magnitude * 100).round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: kBoxInkSoft,
                    ),
                  ),
                  action: 'Throw',
                  enabled: true,
                  onTap: () => _chooseBait(practiceBait),
                ),
                _baitCancelRow(),
              ],
            ),
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: SettlementController(),
      builder: (context, _) {
        final owned = SettlementController().items;
        final baits = [
          for (final d in kItemDefs.values)
            if (d.kind == ItemKind.catchBoost) d,
        ]..sort((a, b) => a.magnitude.compareTo(b.magnitude));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageHeading('Choose your bait', 'sets your starting chance'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 4),
                children: [
                  for (final d in baits)
                    _deckRow(
                      leading: Text(
                        d.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: '${d.name} ×${owned[d.id] ?? 0}',
                      detail: Text(
                        'Start ${(d.magnitude * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: kBoxInkSoft,
                        ),
                      ),
                      action: 'Throw',
                      enabled: (owned[d.id] ?? 0) > 0,
                      onTap: () => _chooseBait(d),
                    ),
                  _baitCancelRow(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _baitCancelRow() => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Pressable(
      onTap: _cancelBaitChoice,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: raisedTile(radius: 10),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: kBoxInkSoft,
          ),
        ),
      ),
    ),
  );

  // ── Change page ───────────────────────────────────────────

  Widget _changePage(Combatant? actor, bool forced) {
    final bench = _engine.benchedPlayers;
    // A forced switch is free and always allowed; a voluntary one costs the
    // leaving monster [kSwitchApCost] out of its own pool.
    final canSwitch =
        forced || (_myTurn && actor != null && actor.ap >= kSwitchApCost);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeading(
          forced ? 'Your monster fainted' : 'Switch monster',
          forced ? 'send in a reserve' : 'costs $kSwitchApCost AP',
        ),
        Expanded(
          child: bench.isEmpty
              ? Center(
                  child: Text(
                    'No reserves left.',
                    style: TextStyle(fontSize: 12, color: kBoxInkSoft),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 4),
                  children: [
                    for (final c in bench)
                      _deckRow(
                        leading: SockelAvatar.combatant(
                          c,
                          size: 30,
                          hpColor: _hpColor,
                        ),
                        title: '${c.element.emoji} ${c.name} · Lv ${c.level}',
                        detail: _creamHpBar(
                          c.hp,
                          c.maxHp,
                          c.maxHp <= 0 ? 0.0 : c.hp / c.maxHp,
                        ),
                        action: 'Send in',
                        enabled: canSwitch,
                        onTap: () => _switchTo(c),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// One row of the Items / Change lists: a tile with the thing, what it does,
  /// and a small gold button on the right.
  Widget _deckRow({
    required Widget leading,
    required String title,
    required Widget detail,
    required String action,
    required bool enabled,
    required VoidCallback onTap,
    String? anchor,
  }) {
    Widget button = Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: goldButton(active: enabled),
        child: Text(
          action,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: goldButtonInk(active: enabled),
          ),
        ),
      ),
    );
    if (anchor != null) {
      button = KeyedSubtree(
        key: IntroSpotlightAnchors.of(anchor),
        child: button,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
        decoration: raisedTile(radius: 10),
        child: Row(
          children: [
            SizedBox(width: 28, child: Center(child: leading)),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: kBoxInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  detail,
                ],
              ),
            ),
            const SizedBox(width: 6),
            button,
          ],
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

  /// The player's own deliberate End Turn press — separate from the
  /// programmatic `_engine.endTurn()` calls elsewhere (the catch flow, the
  /// scripted debuff beat), which don't advance the script.
  void _endTurn() {
    final wasBankEndTurn = _scriptBeat == _ScriptBeat.bankEndTurn;
    if (wasBankEndTurn) {
      setState(() => _scriptBeat = _ScriptBeat.enemyAlmostKill);
    }
    // Captured BEFORE endTurn() advances the queue — by the time it
    // returns, currentActor is already whoever's turn came next.
    final actor = _engine.currentActor;
    _engine.endTurn();
    _relayPvpAction(kind: 'endTurn', actor: actor);
    // Same reasoning as the tackle/missedAttack cases in [_useAbility]: a
    // player faster than the enemy can otherwise win the real CTB race for
    // ITS OWN next turn before the scripted enemyAlmostKill beat ever fires.
    if (wasBankEndTurn) _forceHandoffToEnemy();
  }

  /// Turns the command deck into the bait list (user 2026-10-04: "soll im
  /// Kampfscreen die Rechte Box zum Inventar werden und dort wähle ich den
  /// Köder aus") against the currently SELECTED wild — the wild itself was
  /// already "the" lone enemy before hunts fielded several at once
  /// (2026-09-11). Picking a bait there (see [_chooseBait]) is what
  /// actually spends it and pushes [CaptureBarScreen]; cancelling (see
  /// [_cancelBaitChoice]) spends nothing at all, as if Catch was never
  /// pressed.
  void _startCatch() {
    final wild = _target;
    if (wild == null || !_canCatch) return;
    _catchWild = wild;
    _catcher = _engine.activePlayer;
    if (_catcher == null) return;
    setState(() {
      _catchOpen = true;
      _choosingBait = true;
    });
  }

  /// Uses [chosen] on the ACTIVE monster; it costs a flat [kItemApCost] AP, same
  /// as every ability's own AP spend — NOT the whole turn (user 2026-09-05: "ein
  /// Item benutzen, kostet immer 1 AP", replacing the older whole-turn rule from
  /// 2026-07-18).
  Future<void> _applyItem(ItemDef chosen) async {
    final actor = _engine.activePlayer;
    if (actor == null || _usingItem) return;
    _usingItem = true;
    try {
      // Spend FIRST — if the item can't leave the bag, nothing happens.
      final err = await SettlementController().consumeItem(chosen.id);
      if (!mounted) return;
      if (err != null) {
        _flashMessage(err);
        return;
      }
      _applyItemEffect(chosen, actor);
    } finally {
      _usingItem = false;
    }
  }

  void _applyItemEffect(ItemDef chosen, Combatant actor) {
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
        final worked =
            _engine.deterministicCombat ||
            _engine.rng.nextDouble() < chosen.magnitude;
        final cured = worked && actor.cureMainStatus(chosen.cureMainStatus);
        _flashMessage(
          cured
              ? '${chosen.emoji} ${actor.name} is cured!'
              : '${chosen.emoji} ${actor.name} — no effect.',
        );
      case ItemKind.cureDebuffs:
        final worked =
            _engine.deterministicCombat ||
            _engine.rng.nextDouble() < chosen.magnitude;
        final cleansed = worked && actor.clearSecondaryDebuffs();
        _flashMessage(
          cleansed
              ? '${chosen.emoji} ${actor.name} is cleansed!'
              : '${chosen.emoji} ${actor.name} — no effect.',
        );
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
        _deckTab = _DeckTab.attack;
        _scriptBeat = _ScriptBeat.missedAttack;
        _scriptInfoHint =
            'Items cost AP too — always 1, no matter which '
            'one you use.';
      });
    } else {
      // Using an item always costs a flat kItemApCost AP (user 2026-09-05) —
      // the turn stays open for whatever's left, exactly like an ability.
      _engine.useItem(actor);
      // Back to the moves: the potion is the setup, the attack is the point.
      setState(() => _deckTab = _DeckTab.attack);
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

  /// A light tile button on the cream card — the quiet sibling of the gold one.
  Widget _deckTile(
    String label,
    IconData icon, {
    required bool enabled,
    required VoidCallback onTap,
  }) => Pressable(
    onTap: enabled ? onTap : null,
    child: Container(
      height: 36,
      alignment: Alignment.center,
      decoration: raisedTile(radius: 11, locked: !enabled),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelIcon(icon, size: 15, color: enabled ? kBoxInk : kBoxInkFaint),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: enabled ? kBoxInk : kBoxInkFaint,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// A page's small-caps heading with its price on the right, over a hairline.
  Widget _pageHeading(String title, String note) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: kBoxAccent,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Spacer(),
          Text(
            note,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kBoxInkSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Container(height: 1, color: CreamPalette.tan.withValues(alpha: 0.55)),
      const SizedBox(height: 8),
    ],
  );

  Widget _itemsPage(Combatant actor) {
    final held = _usableItems();
    // Every item costs a flat [kItemApCost] (user 2026-09-05); the scripted
    // potion beat is paid for by the script itself.
    final canPay =
        _myTurn &&
        (actor.ap >= kItemApCost || _scriptBeat == _ScriptBeat.healItem);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _pageHeading('Use an item', 'costs $kItemApCost AP'),
        Expanded(
          child: held.isEmpty
              ? Center(
                  child: Text(
                    'No usable items in your bag.',
                    style: TextStyle(fontSize: 12, color: kBoxInkSoft),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 4),
                  children: [
                    for (var i = 0; i < held.length; i++)
                      _deckRow(
                        leading: Text(
                          held[i].$1.emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                        title: '${held[i].$1.name} ×${held[i].$2}',
                        detail: Text(
                          _itemUseLabel(held[i].$1, actor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: kBoxInkSoft,
                          ),
                        ),
                        action: 'Use',
                        enabled: canPay,
                        onTap: () => _applyItem(held[i].$1),
                        // The scripted potion beat lights the FIRST row's button.
                        anchor: i == 0 ? 'battle-item-use' : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// REMATCH (user 2026-09-19): one tap after a PvP result sends the same
  /// opponent a new challenge and walks into its lobby — you can step out of it
  /// like any other. If they already challenged you back (they were quicker),
  /// that one is accepted instead, so two rematches never stack up.
  Future<void> _rematch() async {
    final match = widget.pvpMatch!;
    final myId = supabase.auth.currentUser!.id;
    final opponentId = match.otherUserId(myId);
    // Held before popping: this screen is gone once the route is.
    final nav = appNavigatorKey.currentState;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final notifier = PvpNotifier.instance;
      final open = notifier.openMatches.where(
        (m) =>
            m.otherUserId(myId) == opponentId &&
            (m.status == PvpMatchStatus.pending ||
                m.status == PvpMatchStatus.accepted),
      );
      PvpMatch rematch;
      if (open.isEmpty) {
        rematch = await _pvpService.createChallenge(opponentId);
      } else {
        final existing = open.first;
        rematch =
            existing.status == PvpMatchStatus.pending &&
                existing.playerB == myId
            ? await _pvpService.acceptChallenge(existing.id)
            : existing;
      }
      notifier.remember(rematch);
      final names = await FriendsService().usernamesFor([opponentId]);
      if (nav == null) return;
      final name = names[opponentId] ?? '(unknown)';
      nav.popUntil((r) => r.isFirst);
      nav.push(
        MaterialPageRoute(
          builder: (_) => PvpLobbyScreen(match: rematch, opponentName: name),
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not start a rematch: $e')),
      );
    }
  }

  /// What the picked ability does — its numbers, its effects, and its live
  /// effectiveness against the enemy you have targeted. Fills whatever height the
  /// tiles and buttons leave, and scrolls if an ability says more than fits.
  Widget _abilityInfoBox(AbilityDef a) {
    final enemy = _target;
    final isDamage = a.kind == AbilityKind.damage;
    String? effText;
    Color effColor = kBoxInkFaint;
    if (isDamage && enemy != null && a.element != CreatureElement.neutral) {
      final mult = _effectivenessVsEnemy(a.element);
      // Short (user 2026-09-28): the verdict and the number, nothing else — a
      // neutral matchup says nothing at all.
      if (mult > 1.0) {
        effText = '▲ Strong (×${_fmtMult(mult)})';
        effColor = CreamPalette.better;
      } else if (mult < 1.0) {
        effText = '▼ Weak (×${_fmtMult(mult)})';
        effColor = CreamPalette.warn;
      }
    }
    final notes = abilityNotes(a);
    final soft = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: kBoxInkSoft,
      height: 1.25,
    );
    // In the ability's own element colour, like its tile (user 2026-09-21).
    final tint = a.element.color;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.2),
        borderRadius: vr(10),
        border: Border.all(color: tint.withValues(alpha: 0.85), width: 1.6),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: kBoxInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: CreamPalette.gold,
                          borderRadius: vr(8),
                        ),
                        child: Text(
                          '${_effectiveApCost(a)} AP',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: kBoxInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${a.element.emoji} ${a.element.label}',
                      if (isDamage) 'Power ${a.power}',
                      a.target.label,
                    ].join(' · '),
                    style: soft,
                  ),
                  if (effText != null)
                    Text(
                      effText,
                      style: soft.copyWith(
                        color: effColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  for (final n in notes)
                    Text(n, style: soft.copyWith(color: kBoxInk)),
                  if (a.description.isNotEmpty)
                    Text(
                      shortAbilityDescription(a.description),
                      style: soft.copyWith(
                        color: kBoxInk,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Said out loud: how to get here (tapping a move uses it).
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                PixelIcon(Icons.info_outline, size: 11, color: kBoxInkFaint),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Tap the (i) on a move, or hold it, to read about it.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: kBoxInkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
        // PvP: "Flee" reads oddly for surrendering to another player (it's
        // wording built for escaping a wild encounter) — same button, same
        // mechanism, just "Give up" instead (user 2026-09-17).
        title: Text(
          widget.isPvp ? 'Give up?' : 'Flee?',
          style: FoE.title(size: 15),
        ),
        content: Text(
          widget.isPvp
              ? 'You lose the match. Your opponent wins.'
              : 'The battle ends with no reward. HP and energy stay as they are.',
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
              widget.isPvp ? 'Give up' : 'Flee',
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

  /// Backs out of the bait list without spending anything — the deck
  /// returns to its normal tabs.
  void _cancelBaitChoice() {
    setState(() {
      _choosingBait = false;
      _catchOpen = false;
    });
    _catchWild = null;
    _catcher = null;
  }

  /// Spends [bait] (unless this is the tutorial's practice throw) and
  /// pushes [CaptureBarScreen] with it. AP for the whole attempt is spent
  /// once the minigame resolves (miss or success), not here — see
  /// [_resolveCatchAttempt].
  Future<void> _chooseBait(ItemDef bait) async {
    final wild = _catchWild;
    final catcher = _catcher;
    if (wild == null || catcher == null) return;
    if (!widget.guaranteedCatch) {
      final err = await SettlementController().consumeItem(bait.id);
      if (!mounted) return;
      if (err != null) {
        _flashMessage(err);
        return; // stay on the bait list — stock ran out between taps
      }
    }
    setState(() => _choosingBait = false);

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CaptureBarScreen(
          wild: wild,
          catcher: catcher,
          rng: _engine.rng,
          deterministicCombat: _engine.deterministicCombat,
          itemStart: bait.magnitude,
          guaranteedCatch: widget.guaranteedCatch,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _catchOpen = false);
    if (result == true) {
      Feel.fanfare();
      _catchSucceed();
    } else {
      _catchMiss();
    }
  }

  /// A failed attempt: the wild slips free, and the AP is spent regardless
  /// (user 2026-09-11: trying to catch now costs the same AP whether or not
  /// it lands — see CombatEngine.attemptCatch). The fight goes on either
  /// way — it always did for a miss, but now for a hit too (see
  /// [_catchSucceed]).
  void _catchMiss() {
    final name = _catchWild?.name ?? 'It';
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
    final wild = _catchWild;
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
  /// The "opponent might be gone" strip — shown only while I'm the one
  /// waiting (see [_syncTurnStateIfNeeded]'s `waitingOn`), with a live
  /// countdown to the shared turn/reconnect deadline. Silent otherwise: it's
  /// not shown on MY OWN turn (that's just the normal action panel), and not
  /// shown at all outside a pending decision. [_pvpSync.opponentOnline] only
  /// changes the WORDING ("reconnecting" vs. just "waiting") — the timer and
  /// its eventual [_maybeClaimTimeout] behave identically either way (see
  /// 0053_pvp_resilience.sql's doc comment on why one timer covers both).
  Widget _pvpConnectionBanner() {
    final myId = supabase.auth.currentUser!.id;
    final opponentId = widget.pvpMatch?.otherUserId(myId);
    final deadline = _turnDeadline;
    if (opponentId == null || _waitingOnId != opponentId || deadline == null) {
      return const SizedBox.shrink();
    }
    final secondsLeft = deadline
        .difference(DateTime.now())
        .inSeconds
        .clamp(0, _kPvpTurnTimeout.inSeconds);
    return Container(
      width: double.infinity,
      // Dark glass over the battlefield, not a brown band.
      color: const Color(0x99000000),
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
      child: ValueListenableBuilder<bool>(
        valueListenable: _pvpSync.opponentOnline,
        builder: (context, online, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PixelIcon(
              online ? Icons.hourglass_top : Icons.wifi_off,
              size: 13,
              color: kBoxInk,
            ),
            const SizedBox(width: 6),
            Text(
              online
                  ? 'Waiting for opponent… ${secondsLeft}s'
                  : 'Opponent disconnected — reconnecting… ${secondsLeft}s',
              style: FoE.dim(size: 11).copyWith(color: kBoxInk),
            ),
          ],
        ),
      ),
    );
  }

  // THE HUD ON THE ARENA (user 2026-09-21: "Zugreihenfolge zentrieren auf den
  // Kampfbereich, dafür Typechart und Auto oben rechts des Kampfbereichs"): no top
  // bar any more. The turn-order cards stand centred on the arena, and the three
  // keys — give up, type chart, AUTO — sit at its top right. Both stand straight
  // on the battlefield; taps between them fall through to the monsters.
  Widget _arenaHud(double arenaW) {
    // The keys' cluster at the top RIGHT: 34 + 6 + 66, plus its right margin. Flee
    // has its own corner, top LEFT (user 2026-09-21).
    const cluster = 34 + 6 + 66 + 8.0;
    // Centred, and never wider than what is left when the cluster's width is kept
    // free on BOTH sides (so the strip stays on the arena's own centre line).
    final stripW = (arenaW - 2 * (cluster + 6)).clamp(0.0, 300.0);
    return Positioned(
      top: 6,
      left: 0,
      right: 0,
      height: 54,
      child: Stack(
        children: [
          Center(
            child: SizedBox(
              width: stripW,
              child: KeyedSubtree(
                key: IntroSpotlightAnchors.of('battle-turnorder'),
                child: _initiativeStrip(),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _glassKey(
                Icons.flag,
                widget.isPvp ? 'Give up' : 'Flee',
                _engine.outcome == null ? _confirmFlee : null,
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _typeChartButton(),
                const SizedBox(width: 6),
                // Same tint as the other deck buttons (user request); the ✔ marks
                // it on. Disabled for the tutorial's scripted first fight (user:
                // "der auto button funktioniert während des tutorials, was alles
                // zerstört") — AUTO hands the PLAYER's own turns to
                // performAutoAction(), the real, un-scripted AI, which the whole
                // authored beat sequence (and its HP=12/scriptedNextHit numbers)
                // assumes never runs here.
                _autoButton(
                  // Off in PvP (user 2026-09-15): AUTO hands the player's own
                  // turns to performAutoAction(), the local PvE AI — meaningless
                  // and misleading against a real second human.
                  enabled: !_isFirstBattleTutorial && !widget.isPvp,
                  onTap: () {
                    setState(() => _autoBattle = !_autoBattle);
                    _scheduleAutoIfNeeded();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Type-matchup key ──────────────────────────────────────
  // A compact "what beats what" chart (user request). 2026-09-07: was an
  // inline collapsible strip; now a single tap opens the full-size overlay
  // (see showTypeChart) — "das müsste viel grösser sein... mache
  // bitte ein Overlaymenü wie der Buildingdetailscreen". The overlay draws
  // the live 8-type matrix (CreatureElement, since 2026-09-08).
  //
  // MOVED to the top bar as a round key (user 2026-09-21: "Typecharte woanders
  // platzieren, so dass die Beschreibung der Fähigkeiten mehr Platz hat") — the
  // strip under the deck took a row of height the ability text needs.
  Widget _typeChartButton() {
    final tutorial = _scriptBeat == _ScriptBeat.typeChartPrompt;
    final key = _glassKey(
      Icons.hexagon_outlined,
      'Type chart',
      tutorial ? _openTypeChartFromTutorial : _openTypeChart,
    );
    // Tagged only while it is actually the lit control — see
    // [_ScriptBeat.typeChartPrompt]'s own doc comment.
    return tutorial
        ? KeyedSubtree(
            key: IntroSpotlightAnchors.of('battle-typechart-btn'),
            child: key,
          )
        : key;
  }

  /// Outside the scripted first fight's own [typeChartPrompt] beat (which
  /// goes through [_openTypeChartFromTutorial] instead), this is still the
  /// ONLY way into the chart during any other battle fought while the guided
  /// intro hasn't finished yet (the second node, say) — [IntroStep.secondNode]
  /// is `introStep.isActive` same as every earlier step. The banner there
  /// too (user 2026-10-01: "wenn der type chart geöffnet wird während des
  /// tutorials, bitte ein Text einblenden, welcher erklärt..."), with no
  /// script beat to advance afterwards — closing it is simply closing it.
  void _openTypeChart() => showTypeChart(
    context,
    initial: _target?.element,
    tutorialBanner: SettlementController().introStep.isActive,
  );

  /// Closing the chart (however that happens — there is no separate
  /// dismiss to wait for) is what carries the tutorial on to bankEndTurn
  /// (user 2026-09-30: "Dann muss der User das Menü wieder schliessen und
  /// das Tutorial geht weiter").
  Future<void> _openTypeChartFromTutorial() async {
    await showTypeChart(context, initial: _target?.element, tutorialBanner: true);
    if (!mounted || _scriptBeat != _ScriptBeat.typeChartPrompt) return;
    setState(() => _scriptBeat = _ScriptBeat.bankEndTurn);
  }

  /// A round key on the arena itself: dark glass with a white glyph, so it reads
  /// on grass, stone or a region's own art alike. Null [onTap] = dead.
  Widget _glassKey(IconData icon, String tooltip, VoidCallback? onTap) =>
      Tooltip(
        message: tooltip,
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              color: const Color(0x80000000),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: PixelIcon(
              icon,
              size: 17,
              color: onTap == null ? const Color(0x66FFFFFF) : Colors.white,
            ),
          ),
        ),
      );

  /// The initiative bar's own order during the scripted first fight — strict
  /// alternation, matching what the script actually forces turn to turn
  /// (user 2026-10-01: "die Zugreihenfolge während des tutorials an die
  /// Fakereihenfolge anpassen"). [CombatEngine.forecast] predicts off real
  /// speed, which the script overrides every turn via [_forceHandoffToEnemy]
  /// / `forceActing` (see [_useAbility] and [_runScriptedEnemyBeat]) — the
  /// bar showed that real prediction regardless, so a starter faster than
  /// its counter-picked opponent could show itself two turns running right
  /// before the engine forced the alternation the script actually plays out.
  List<Combatant> _tutorialForecast(int count) {
    final me = _engine.activePlayer;
    final foe = _engine.activeEnemy;
    if (me == null || foe == null) return _engine.forecast(count);
    final first = _engine.currentActor;
    final second = first == me ? foe : me;
    return [for (var i = 0; i < count; i++) i.isEven ? first : second];
  }

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
      List<Combatant> computeOrder() =>
          _isFirstBattleTutorial ? _tutorialForecast(fit) : _engine.forecast(fit);
      final order = _presenting
          ? (_lastSettledOrder ??= computeOrder())
          : (_lastSettledOrder = computeOrder());
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
      child: SockelAvatar.combatant(
        c,
        size: acting ? 34 : 28,
        hpColor: _hpColor,
      ),
    );
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
    // The platform is as wide as its slot (a flank a little narrower, standing
    // further back). The slots are narrower than they were — a gutter for the
    // waiting monsters' tiles takes the edges — so it no longer holds back.
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
          // THE MONSTER STANDS ON THE GROUND (user 2026-11-04: "es soll in
          // diesem Stil sein, d.h. die Monster stehen wirklich am Boden"): no
          // podium, no bowl, no disc. The plate hangs above its head
          // ("Schildchen 3"), the sprite's feet rest in a shadow thrown in the
          // map's own tint — and both slide in together.
          Expanded(
            // Entry slide (user 2026-07-24): the enemy sweeps in from the
            // right, the player from the left, fading up, staggered by slot.
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  KeyedSubtree(
                    key: hpAnchor
                        ? IntroSpotlightAnchors.of('battle-hp')
                        : null,
                    child: _slotPlate(
                      c0,
                      acting: acting,
                      targeted: targeted,
                      width: width,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final spriteW = width * (back ? 0.88 : 1.0);
                        // The feet sit a hair above the slot's bottom edge,
                        // inside the shadow.
                        final feetPad = box.maxHeight * 0.05;
                        final room = box.maxHeight - feetPad;
                        // The isometric sheets are laid out at exactly their
                        // calibrated size; only a flat sprite is scaled up.
                        final iso = _isIso(c0);
                        final target = iso
                            ? room
                            : (room + (isEnemy ? 14 : 16)) *
                                  (back ? 0.92 : 1.0) *
                                  _kSpriteScale;
                        return Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // The shadow on the ground: the map's tint and
                            // opacity, thrown a little to the lower right like
                            // every tree's and house's.
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: math.max(0.0, feetPad - spriteW * 0.03),
                              ),
                              child: Transform.translate(
                                offset: Offset(spriteW * 0.07, 0),
                                // The isometric sheets carry their own cast
                                // shadow, so this is only a small contact patch.
                                child: Container(
                                  width: spriteW * (iso ? 0.46 : 0.74),
                                  height: spriteW * (iso ? 0.09 : 0.14),
                                  decoration: BoxDecoration(
                                    color: kShadowTint.withValues(
                                      alpha: kShadowOpacity * 1.6,
                                    ),
                                    borderRadius: BorderRadius.all(
                                      Radius.elliptical(
                                        spriteW * (iso ? 0.23 : 0.37),
                                        spriteW * (iso ? 0.045 : 0.07),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.only(bottom: feetPad),
                              child: _bigSprite(
                                c0,
                                back: !isEnemy,
                                height: room,
                                targetH: target,
                                acting: acting,
                                targeted: targeted,
                                koing: koing,
                              ),
                            ),
                          ],
                        );
                      },
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
    // One icon per ACTIVE effect (user 2026-09-08) — tapping the strip explains
    // each one in full, see [_showActiveEffects].
    final marks = <Widget>[
      for (final e in c.selfBuffs.keys)
        Text(e.emoji, style: const TextStyle(fontSize: 10)),
      for (final e in c.secondaryDebuffs.keys)
        Text(e.emoji, style: const TextStyle(fontSize: 10)),
      if (c.mainStatus != null)
        Text(c.mainStatus!.emoji, style: const TextStyle(fontSize: 10)),
    ];
    // THE HEALTH LIVES ON THE PLATE NOW (user 2026-11-04, "Schildchen 3"): the
    // podium that carried it as its rim is gone, the monsters stand on the
    // ground. Name, level and the bar — the three things you read at a glance.
    final frac = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    // The two states you act on are said by the plate's own edge: gold for the
    // monster whose turn it is, red for the enemy you are aimed at.
    final edge = targeted
        ? FoE.danger
        : acting
        ? CreamPalette.gold
        : const Color(0xFF0B1E27);
    // DARK plate, light ink (user 2026-11-08: the text could not be read — the
    // light ink of the kit sat on a cream plate). The state is the plate's
    // BACKGROUND: tinted gold on its turn, red when aimed at, and flooded with
    // the striking move's colour while a hit lands on it.
    const baseFill = Color(0xFF1B3445);
    final stateFill = targeted
        ? Color.lerp(baseFill, FoE.danger, 0.45)!
        : acting
        ? Color.lerp(baseFill, CreamPalette.goldDeep, 0.7)!
        : baseFill;
    final struck = identical(c, _fxTarget);
    // The status strip FLOATS above the plate instead of sitting in the column:
    // taking layout height made the slot's sprite area shrink (and the monster
    // with it) the moment a buff such as Armor Up appeared. Sizes must never
    // change during a fight (user 2026-11-08).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (marks.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -1),
              child: Center(
                child: Pressable(
                  onTap: () => _showActiveEffects(c),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: ShapeDecoration(
                      color: FoE.bg.withValues(alpha: 0.65),
                      shape: FoE.facet(radius: 5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: marks),
                  ),
                ),
              ),
            ),
          ),
        AnimatedBuilder(
          animation: _fxReact,
          builder: (context, child) {
            final hit = struck && _fxReact.isAnimating
                ? (1 - _fxReact.value)
                : 0.0;
            return Container(
              width: (width * 0.78).clamp(84.0, 132.0),
              padding: const EdgeInsets.fromLTRB(5, 2, 5, 4),
              decoration: BoxDecoration(
                color: Color.lerp(stateFill, _fxImpact, hit * 0.75),
                border: Border.all(
                  color: edge,
                  width: (acting || targeted) ? 3 : 2,
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x73000000), offset: Offset(2, 2)),
                ],
              ),
              child: child,
            );
          },
          child: _plateBody(c, frac),
        ),
      ],
    );
  }

  Widget _plateBody(Combatant c, double frac) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.1, color: kBoxInk),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'L${c.level}',
            maxLines: 1,
            style: TextStyle(fontSize: 13, height: 1.1, color: kBoxInkSoft),
          ),
        ],
      ),
      const SizedBox(height: 3),
      RecessBar(value: frac, color: _hpColor(frac), height: 7),
    ],
  );


  /// The monsters still waiting, as a column of small tiles (user 2026-09-21:
  /// "links oben und unterhalb des Logs die restlichen Monster anzeigen, welche
  /// dem Spieler/NPC noch zur Verfügung stehen"): the enemy's at the top left of
  /// the arena, mine under the log. Mine are tappable on my turn to switch; the
  /// enemy's are just shown. More than three and the rest is a number.
  Widget _benchColumn(List<Combatant> bench, {required bool isEnemy}) {
    if (bench.isEmpty) return const SizedBox.shrink();
    // Three fit down to the log; more than that and the third becomes the number.
    final cap = bench.length > 3 ? 2 : bench.length;
    final shown = bench.take(cap).toList();
    final more = bench.length - shown.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: _benchTile(c, isEnemyRow: isEnemy),
          ),
        if (more > 0)
          Text(
            '+$more',
            style: FoE.label(size: 11).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w400,
              shadows: const [Shadow(color: Color(0xCC000000), offset: Offset(0, 1))],
            ),
          ),
      ],
    );
  }

  /// One waiting monster: its Sockel (the rim is its HP) and its level, on a
  /// dark-glass tile like the round keys. Gold edge = you can send it in now.
  Widget _benchTile(Combatant c, {required bool isEnemyRow}) {
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
        width: 34,
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 1),
        decoration: ShapeDecoration(
          color: const Color(0x80000000),
          shape: FoE.facet(
            radius: 9,
            side: BorderSide(
              color: canSwitchTo ? FoE.goldBright : const Color(0x33FFFFFF),
              width: canSwitchTo ? 1.6 : 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Center(
                child: SockelAvatar.combatant(c, size: 24, hpColor: _hpColor),
              ),
            ),
            Text(
              'Lv ${c.level}',
              maxLines: 1,
              style: FoE.label(
                size: 9,
              ).copyWith(color: Colors.white, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }

  /// THE DIAL FOR HOW BIG THE MONSTERS ARE DRAWN (user 2026-09-21: "Monster
  /// sollen deutlich grösser sein"). 1.0 = the art fills the room its slot has
  /// above the platform (see [_fieldSlot]); the removed top bar and reserve strip
  /// gave that room back. Higher lets the art rise past it — into the enemy's
  /// edge of the screen, into the clearance above my rank — and a very high value
  /// starts to cover the log and the neighbouring monsters.
  ///
  /// Earlier this was a flat zoom (1.3, once 1.15) on top of a box sized to the
  /// slot; the zoom is now worked out from the target height instead, so the
  /// art is decoded at the size it is drawn.
  static const double _kSpriteScale = 1.0;

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
  // Toned down (user 2026-11-08): the sprites carry their own attack/hurt
  // animations now, so the slide only supports them instead of being the move.
  static const double _kLungeWindupPx = 3.0;
  static const double _kLungePeakPx = 14.0;
  static const double _kLungeReboundPx = 2.0;

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

  /// The large battlefield sprite. [height] is its layout box (its slot), [targetH]
  /// how tall the art is actually DRAWN (see [_kSpriteScale]) — it is scaled up
  /// from the bottom, so the feet stay on the platform. [back] picks the back-view
  /// art (player) over the front (enemy). Plays the hit pulse (shake + white
  /// flash) when this side was just acted upon (user 2026-07-18). Whose turn it is
  /// is shown in the turn-order bar, and its health on the platform's own rim (see
  /// [TypePodium]) — not here.
  Widget _bigSprite(
    Combatant c, {
    required bool back,
    required double height,
    required double targetH,
    required bool acting,
    required bool targeted,
    bool koing = false,
  }) {
    final url = back ? (c.backImageUrl ?? c.imageUrl) : c.imageUrl;
    // [height] is the room the slot really has above the platform; the art is
    // laid out at exactly that (an Image is clamped to its parent, so a taller
    // request would silently be squeezed) and then scaled to [targetH].
    final imgH = math.max(height, 1.0);
    final zoom = targetH / imgH;
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
              // Cuts only BELOW the feet: the isometric sheets overflow their
              // box upwards and must not be cut there.
              clipper: const _BelowFeetClipper(),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Transform.scale(
                    scale: zoom,
                    alignment: Alignment.bottomCenter,
                    child: _sprite(
                      c,
                      back: back,
                      url: url,
                      imgH: imgH,
                      flash: 0.0,
                      shadowColor: c.element.shadowColor,
                      decodeH: targetH,
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
    return AnimatedBuilder(
      animation: Listenable.merge([_fx, _fxReact, _fxStatus, _idle]),
      builder: (context, _) {
        final t = _fx.value;
        // The reaction reads its OWN controller now, not _fx (user 2026-08-29:
        // "zunächst muss die Angriffsanimation kommen, wenn diese fertig ist,
        // kommt erst die Trefferanimation") — _fxReact only starts once the
        // lunge below has finished, see _playHit.
        final active = reacts && _fxReact.isAnimating;
        // The hurt animation is the sprite's own; the struck monster no longer
        // shakes or blinks — its PLATE lights up instead (see [_slotPlate]).
        const shake = 0.0;
        const flash = 0.0;
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
        // SIDE VIEW (user 2026-11-04): the sides face each other across the
        // field, so the lunge runs ACROSS it — mine to the right, the enemy's
        // to the left — and drifts up/down toward the depth the target
        // stands at (0 for a target on the same row).
        // ISOMETRIC (user 2026-11-08): the lunge runs along the ground toward
        // the target's own feet, so it follows the diagonal the two ranks stand
        // on instead of sliding straight across the screen.
        final dir = lunging ? _lungeDir(c, _fxLungeTarget) : Offset.zero;
        final lungeDx = lungeShape * dir.dx * _kLungePeakPx;
        final lungeDy = lungeShape * dir.dy * _kLungePeakPx;
        // Idle bob: a slow, small breathing motion, always running — "nur
        // leicht" (user request), so 2.5px rather than anything that reads as
        // a hop.
        // Removed (user 2026-11-08): the sprites carry their own idle animation.
        const bob = 0.0;
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
                scale: zoom,
                alignment: Alignment.bottomCenter,
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    _sprite(
                      c,
                      back: back,
                      url: url,
                      imgH: imgH,
                      flash: flash,
                      shadowColor: glowColor ?? c.element.shadowColor,
                      decodeH: targetH,
                      // The reacting sprite flashes in the STRIKING move's
                      // colour.
                      flashColor: reacts ? _fxImpact : Colors.white,
                      // Species with baked 3D art play their own attack and
                      // hit animations on top of the lunge/shake.
                      anim: (attacks && lunging)
                          ? 'attack'
                          : (active ? 'hurt' : 'idle'),
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

  /// The creature on the field: its baked animated 3D art if it has any
  /// (see [MonsterSheets]), otherwise the flat network sprite with its drop
  /// shadow. [anim] only matters for the animated art.
  Widget _sprite(
    Combatant c, {
    required bool back,
    required String? url,
    required double imgH,
    required double flash,
    required Color shadowColor,
    Color flashColor = Colors.white,
    double? decodeH,
    String anim = 'idle',
  }) {
    // SIDE VIEW (user 2026-11-04): [back] here means "my side" — it stands at
    // the left and faces right, the enemy at the right faces left.
    final sheets = MonsterSheets.battleIso(
      c.speciesId,
      c.stage,
      mine: back,
    );
    if (sheets == null) {
      return _spriteWithShadow(
        url,
        imgH,
        flash,
        shadowColor,
        flashColor: flashColor,
        decodeH: decodeH,
      );
    }
    // The sheet's cell is far taller than the creature in it (a low seal under
    // a lot of empty air), so it is laid out in a box [_kIsoCellRatio] times the
    // slot and overflows UPWARD out of it: the slot, and with it the plate
    // above, stays as short as the creature itself.
    final cell = imgH * _kIsoCellRatio;
    return SizedBox(
      height: imgH,
      child: OverflowBox(
        alignment: Alignment.bottomCenter,
        minHeight: cell,
        maxHeight: cell,
        minWidth: 0,
        maxWidth: double.infinity,
        child: MonsterSheetPlayer(
          set: sheets,
          anim: anim,
          height: cell,
          flash: flash,
          flashColor: flashColor,
        ),
      ),
    );
  }

  /// Height of an isometric sheet's cell box relative to its slot (see
  /// [_sprite]). Tuned with the slot's 20 % of the ground: the cell then comes
  /// out at about 29 % of it, which is one tile wide on the arena's lattice.
  static const double _kIsoCellRatio = 2.05;

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
    double? decodeH,
  }) {
    Widget img(FilterQuality quality) => url == null
        ? PixelIcon(Icons.pets, color: FoE.gold, size: imgH * 0.6)
        : Image.network(
            url,
            height: imgH,
            // Decode at DISPLAY size, not native (user 2026-08-29: "die
            // Monsterassets werden sehr langsam geladen") — see
            // creature_sprite.dart's decodeWidthFor for why this was the
            // slow part, not the network.
            cacheWidth: decodeWidthFor(context, decodeH ?? imgH),
            fit: BoxFit.contain,
            filterQuality: quality,
            // A soft placeholder while the sprite streams in, so it fades in
            // instead of popping (user request 2026-07-20).
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : SizedBox(
                    height: imgH,
                    child: Center(
                      child: PixelIcon(
                        Icons.pets,
                        color: FoE.gold.withValues(alpha: 0.25),
                        size: imgH * 0.6,
                      ),
                    ),
                  ),
            errorBuilder: (_, _, _) =>
                PixelIcon(Icons.pets, color: FoE.gold, size: imgH * 0.6),
          );
    // The element-coloured silhouette that used to sit behind the sprite is gone
    // (user 2026-11-08: "den gelben Schatten rechts von dem Fuss"); [shadowColor]
    // is kept so the callers do not change.
    return Stack(
      alignment: Alignment.center,
      children: [
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

  Widget _portrait(Combatant c, {required double size}) => c.imageUrl == null
      ? PixelIcon(Icons.pets, color: FoE.gold, size: size)
      : CreatureSprite(
          url: c.imageUrl!,
          width: size,
          height: size,
          fallback: PixelIcon(Icons.pets, color: FoE.gold, size: size),
        );

  // The battle log's fixed height. The log is centred on the seam, so its
  // bottom edge sits _kLogHeight/2 into the lower half — which is where each
  // rank's sprites stop, so the two never overlap.
  static const double _kLogHeight = 46;

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
        // A cream card floating on the seam between the two ranks, in the
        // kit's own paper and hard tan shadow (user 2026-09-21: "Battlelog in
        // neuen UI Farben und Stil").
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
          ),
          borderRadius: vr(12),
          boxShadow: const [
            BoxShadow(color: CreamPalette.tanShadow, offset: Offset(0, 3)),
          ],
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
                    style: FoE.label(size: 11).copyWith(
                      color: CreamPalette.warn,
                      fontWeight: FontWeight.w400,
                    ),
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
                          color: i == lines.length - 1 ? kBoxInk : kBoxInkSoft,
                        ),
                    ],
                  ),
            // The only hint that there's more behind it.
            if (!flashing && _log.isNotEmpty)
              Positioned(
                right: 2,
                bottom: 1,
                child: PixelIcon(Icons.unfold_more, size: 11, color: kBoxInkFaint),
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
    // Was vertical:1 — the fixed _kLogHeight box fits exactly 2 of these
    // rows with almost no slack, so a line whose font falls back for one
    // glyph (a slightly taller substitute font) is enough to overflow by a
    // couple of pixels. Zero reclaims that margin without touching
    // _kLogHeight itself, which also positions the battle seam.
    padding: EdgeInsets.zero,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (line.iconUrl != null) ...[
          ClipRRect(
            borderRadius: vr(3),
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
            style: FoE.label(
              size: 11,
            ).copyWith(color: color, fontWeight: FontWeight.w400),
          ),
        ),
      ],
    ),
  );

  /// The whole fight's log, newest first, in a sheet — what a tap on the
  /// fixed-size [_logLine] bar opens (it only ever shows the last two lines
  /// itself, and truncates each to one line besides).
  Future<void> _openFullLog() async {
    // A cream sheet in the kit's paper, like every other sheet in the app.
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
          ),
          child: creamSurface(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Battle log',
                    style: FoE.title(size: 15).copyWith(color: kBoxInk),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 1,
                    color: CreamPalette.tan.withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 6),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _log.length,
                      itemBuilder: (_, i) {
                        final idx = _log.length - 1 - i; // newest first
                        final line = _log[idx];
                        final newest = i == 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (line.iconUrl != null) ...[
                                ClipRRect(
                                  borderRadius: vr(3),
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
                                  style: FoE.label(size: 12).copyWith(
                                    color: newest ? kBoxInk : kBoxInkSoft,
                                    fontWeight: newest
                                        ? FontWeight.w400
                                        : FontWeight.w400,
                                  ),
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
      ),
    );
  }

  // How far the arena is nudged DOWN toward the deck (fraction of its height).
  // Kept small so the lower tile's rounded bottom corners stay FULLY visible
  // above the deck instead of tucking behind it (user request). Went
  // 0.03 → 0.05 ("nach unten schieben"), now back down to 0.02 (user
  // 2026-08-29: "Alle Monster beim Kampfscreen etwas nach oben schieben")
  // — pushes BOTH ranks, platforms included, since this offset wraps the
  // whole arena Stack.
  // Now 0 (user 2026-09-21: the arena is the full height and the player rank is
  // moved down by its own spacer instead).
  static const double _kArenaDrop = 0.0;

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
    bool selected = false,
  }) {
    // Dark text on light type colours (e.g. Light), white on the rest.
    final onColor = element.color.computeLuminance() > 0.5
        ? const Color(0xFF1A1300)
        : Colors.white;
    // The tile keeps its element colour when it cannot be used right now (user
    // 2026-09-21: "die Fähigkeitsboxen in der Elementfarbe") — dimmed, not turned
    // into a grey card, so the type still reads during the enemy's turn.
    final fg = onColor;
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
          ).copyWith(color: fg, fontWeight: FontWeight.w400, height: 1.1),
        ),
      ),
    );

    Widget tile = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: CreatureBackdrop(
        element: element,
        radius: radius,
        // Bigger (user 2026-08-29: "das Typicon grösser machen") — the card's
        // own embossed glyph, same scale knob TypePodium uses for the same
        // reason.
        symbolScale: 1.35,
        child: label,
      ),
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
      height: _kTileH,
      child: Pressable(
        onTap: enabled ? onTap : null,
        // Long press PICKS the tile for the deck's info box (it used to open a
        // sheet over the fight).
        onLongPress: ability == null
            ? null
            : () => setState(() => _infoAbilityId = ability.id),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: tile),
            // The picked tile wears an ink frame — the one the info box speaks
            // about.
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: vr(10),
                      border: Border.all(color: kBoxInk, width: 2),
                    ),
                  ),
                ),
              ),
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
                  color: enabled
                      ? FoE.gold
                      : CreamPalette.tan.withValues(alpha: 0.28),
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
                    color: enabled ? const Color(0xFF1A1300) : kBoxInkFaint,
                    fontWeight: FontWeight.w400,
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
            // THE WAY TO THE DESCRIPTION, VISIBLE: a small (i) in the tile's
            // corner. One tap on the tile still USES the move; a tap on the (i)
            // only reads about it, and works when the tile is greyed too.
            // (Holding the tile does the same, but nothing said so.)
            if (ability != null)
              Positioned(
                bottom: 0,
                left: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _infoAbilityId = ability.id),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(5, 6, 8, 4),
                    child: PixelIcon(
                      Icons.info_outline,
                      size: 14,
                      color: fg.withValues(alpha: 0.9),
                    ),
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
        PixelIcon(icon, size: 16, color: color ?? FoE.textDim),
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
              ).copyWith(color: FoE.parchment, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 10),
            ...rows,
          ],
        ),
      ),
    );
  }

  /// The top band's AUTO switch: a light Holz tile on the wood; the check marks
  /// it on. [enabled] is false for the tutorial's scripted fight and for PvP.
  Widget _autoButton({required bool enabled, required VoidCallback onTap}) {
    final ink = enabled ? kBoxInk : kBoxInkFaint;
    return Pressable(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 66,
        height: 32,
        alignment: Alignment.center,
        decoration: _autoBattle
            ? goldButton(active: enabled)
            : raisedTile(radius: 11, locked: !enabled),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(Icons.smart_toy, size: 14, color: ink),
              const SizedBox(width: 4),
              Text(
                _autoBattle ? 'AUTO ✔' : 'AUTO',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Items (in-battle potions, cures, buffs) ───────────────
  /// The held items the Items tab lists: battle-usable heal/buff/cure items,
  /// which apply to the ACTIVE monster. (Revive is out-of-battle only — the
  /// active can't be K.O., and bench-targeting is a later slice.)
  List<(ItemDef, int)> _usableItems() => [
    for (final e in SettlementController().items.entries)
      if (kItemDefs[e.key] case final ItemDef d
          when d.battleUsable &&
              (d.kind == ItemKind.heal ||
                  d.kind == ItemKind.buff ||
                  d.kind == ItemKind.cureStatus ||
                  d.kind == ItemKind.cureDebuffs))
        (d, e.value),
  ];

  bool _usingItem = false;

  // ── End overlay ───────────────────────────────────────────
  /// What "Continue" does: hand the result back to whoever launched the fight (a
  /// capture battle also returns every wild caught along the way, 2026-09-11) —
  /// a PvP fight has nobody waiting and goes back to the app root instead.
  VoidCallback _continueTap(CombatOutcome outcome) =>
      () => widget.isPvp
      ? Navigator.of(context).popUntil((r) => r.isFirst)
      : Navigator.of(context).pop(
          widget.isCapture
              ? HuntBattleResult(
                  outcome,
                  _caught,
                  widget.enemies.where((w) => !w.alive).length,
                )
              : outcome,
        );

  /// THE VICTORY PAGE (user 2026-09-28: "Victory Screen muss auf einer Seite Platz
  /// haben ohne zu scrollen. Es kann auch eine volle Seite sein"). A full page,
  /// laid out on a fixed 860 × 372 design grid that is scaled DOWN as a whole when
  /// the screen is smaller — so nothing ever scrolls or overflows, however many
  /// monsters levelled up or unlocks came with the win. Left: the verdict (stars
  /// and the ticks that earned them, or the foe count) and Continue; right: the
  /// team with its XP, the level-ups and what was unlocked.
  Widget _victoryPage(BattleStars? stars) {
    final foes = _engine.enemies.length;
    Widget heading(String t) => CreamHeading(title: t);
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: creamCard(
        padding: const EdgeInsets.all(14),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 860,
            height: 372,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── The verdict ──
                SizedBox(
                  width: 260,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '🏆 Victory!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w400,
                          color: kBoxInk,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (stars != null)
                        Expanded(child: _starsPanel(stars))
                      else
                        Expanded(
                          child: Center(
                            child: Text(
                              'Defeated $foes ${foes == 1 ? 'foe' : 'foes'}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: kBoxInkSoft,
                              ),
                            ),
                          ),
                        ),
                      SocialGoldButton(
                        'Continue',
                        height: 44,
                        fontSize: 15,
                        onTap: _continueTap(CombatOutcome.victory),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // ── The team, the level-ups, the unlocks ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading(
                        stars != null
                            ? 'Your team · $foes ${foes == 1 ? 'foe' : 'foes'} defeated'
                            : 'Your team',
                      ),
                      const SizedBox(height: 8),
                      // The tiles keep their size and the row shrinks as a whole
                      // for a big party, instead of wrapping onto a second line.
                      SizedBox(
                        height: monsterTileHeight(context) + 22,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final p in _engine.players) ...[
                                _victoryCreatureTile(p),
                                const SizedBox(width: 10),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => RecessBar(
                          value: v,
                          color: CreamPalette.gold,
                          height: 10,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Whatever is left: level-ups, then unlocks — scaled down
                      // to fit rather than scrolled.
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: 560,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_levelUps.isNotEmpty) ...[
                                  heading('Level up'),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      for (var i = 0; i < _levelUps.length; i++)
                                        SizedBox(
                                          width: 272,
                                          child: _levelUpCard(_levelUps[i], i),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (widget.victoryRewards.isNotEmpty) ...[
                                  heading('Unlocked'),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 2,
                                    children: [
                                      for (final r in widget.victoryRewards)
                                        SizedBox(
                                          width: 272,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 3,
                                            ),
                                            child: r.buildingId != null
                                                ? _victoryBuildingRow(r)
                                                : _victoryPlainRow(r),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _endOverlay() {
    final outcome = _engine.outcome!;
    // A capture battle's "victory" (every wild caught or fought down) gets
    // NO end-of-battle screen at all now (user 2026-10-04: "victoryscreen
    // nach catch entfernen") — CaptureEncounterScreen's own summary right
    // after this pops ("🎉 N caught · N defeated · N lost") already says
    // what happened; a stars/rewards victory page on top of that was a
    // second "you did it!" screen for the same moment. Pops with the exact
    // same HuntBattleResult the Continue button below would have, just
    // automatically — a defeat or a flee in a capture battle still gets
    // the small card beneath.
    if (outcome == CombatOutcome.victory && widget.isCapture) {
      if (!_autoPoppedCaptureVictory) {
        _autoPoppedCaptureVictory = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pop(
            HuntBattleResult(
              outcome,
              _caught,
              widget.enemies.where((w) => !w.alive).length,
            ),
          );
        });
      }
      return const SizedBox.shrink();
    }
    // A won campaign or Survival fight has its own full page (PvP keeps the
    // small card: its reward is the rating, not spoils).
    if (outcome == CombatOutcome.victory && !widget.isPvp) {
      return _victoryPage(_stars);
    }
    // Victory has no subtitle any more (user 2026-08-28: "Your Team grew
    // Stronger löschen") — the rewards below already say what was won.
    final (title, subtitle) = switch (outcome) {
      CombatOutcome.victory => ('🏆 Victory!', null),
      CombatOutcome.defeat => ('💀 Defeat…', 'Your team needs healing.'),
      CombatOutcome.fled => ('🏃 Fled', 'No reward.'),
    };
    final stars = _stars;
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      alignment: Alignment.center,
      // The result card is a cream Holz card too (user 2026-09-20, Variante 7).
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        // Height-bounded + scrollable so a fight where the whole party levels
        // (several cards) can't overflow the panel (user 2026-07-24).
        constraints: BoxConstraints(
          maxWidth: stars != null ? 740 : 560,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: creamCard(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w400,
                    color: kBoxInk,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: kBoxInkSoft),
                  ),
                ],
                // PvP has no XP/level-up/unlock pool — its reward is the
                // rating change, already applied by [_applyPvpOutcome] and
                // visible on the Ranking tab, not restated here.
                if (outcome == CombatOutcome.victory && !widget.isPvp) ...[
                  const SizedBox(height: 16),
                  // A numbered campaign fight is judged in STARS: the report on
                  // the left, the team and its XP on the right (user 2026-09-28,
                  // "Variante 5"). Any other victory keeps the plain layout.
                  if (stars != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: _starsPanel(stars)),
                        const SizedBox(width: 20),
                        Expanded(flex: 6, child: _victoryRewards()),
                      ],
                    )
                  else
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
                  child: SocialGoldButton(
                    'Continue',
                    height: 42,
                    fontSize: 15,
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
                                    widget.enemies
                                        .where((w) => !w.alive)
                                        .length,
                                  )
                                : outcome,
                          ),
                  ),
                ),
                // A rematch is one tap away (user 2026-09-19).
                if (widget.isPvp) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SocialTileButton(
                      'Rematch',
                      height: 38,
                      fontSize: 14,
                      onTap: _rematch,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The star report of a won campaign battle: the stars, the three ticks that
  /// earned them (the same yardstick whatever the team's size — see
  /// battle_stars.dart) and what the stars paid.
  Widget _starsPanel(BattleStars s) {
    Widget star(int i) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 380 + 170 * i),
      curve: Curves.easeOutBack,
      builder: (context, v, _) => Transform.scale(
        scale: i < s.count ? v.clamp(0.0, 1.25) : 1.0,
        child: PixelIcon(
          Icons.star_rounded,
          size: 48,
          color: i < s.count
              ? CreamPalette.gold
              : kBoxInk.withValues(alpha: 0.16),
        ),
      ),
    );
    Widget tick(bool ok, String text, {String? trail}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          PixelIcon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: ok ? CreamPalette.better : kBoxInkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: FoE.label(
                size: 12.5,
              ).copyWith(color: ok ? kBoxInk : kBoxInkSoft),
            ),
          ),
          if (trail != null)
            Text(
              trail,
              style: FoE.value(
                size: 12.5,
              ).copyWith(color: ok ? CreamPalette.better : CreamPalette.warn),
            ),
        ],
      ),
    );
    final hpNeed = (kStarHpFraction * 100).round();
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: raisedTile(radius: 10),
      child: Text(
        text,
        style: FoE.label(
          size: 12,
        ).copyWith(color: kBoxInk, fontWeight: FontWeight.w400),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [for (var i = 0; i < 3; i++) star(i)],
        ),
        const SizedBox(height: 2),
        Text(
          '${s.count} of 3',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
        ),
        const SizedBox(height: 10),
        CreamHeading(title: 'How you did'),
        const SizedBox(height: 4),
        tick(true, 'Won the battle'),
        tick(s.noKnockOut, 'No monster knocked out'),
        tick(
          s.hpKept,
          'Team kept $hpNeed % of its HP',
          trail: '${(s.hpLeft * 100).round()} %',
        ),
        if (s.xpMultiplier > 1 || _starGold > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (s.xpMultiplier > 1)
                chip('XP ×${_fmtMult(s.xpMultiplier)} for ${s.count} stars'),
              if (_starGold > 0) chip('+$_starGold 🪙 first time'),
            ],
          ),
        ],
      ],
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
            const PixelIcon(Icons.military_tech, size: 15, color: kBoxAccent),
            const SizedBox(width: 6),
            Text(
              'Defeated $foes ${foes == 1 ? 'foe' : 'foes'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: kBoxInkSoft,
              ),
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
              RecessBar(value: v, color: CreamPalette.gold, height: 11),
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
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: CreamPalette.goldDeep,
            ),
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
          const Text(
            'Level Up!',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: kBoxAccent,
            ),
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
      decoration: raisedTile(radius: 12, lit: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No gift icon any more (user 2026-08-28: "Unlocked: Icon
          // löschen") — the title alone says what the box is for.
          Center(
            child: const Text(
              'Unlocked!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: kBoxAccent,
              ),
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
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: kBoxInk,
          ),
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
        decoration: raisedTile(radius: 10, lit: true),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: up.imageUrl == null
                  ? const PixelIcon(Icons.pets, color: FoE.gold, size: 24)
                  : CreatureSprite(
                      url: up.imageUrl!,
                      width: 34,
                      height: 34,
                      fallback: const PixelIcon(
                        Icons.pets,
                        color: FoE.gold,
                        size: 24,
                      ),
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
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: kBoxInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Lv ${up.fromLevel}',
                        style: TextStyle(fontSize: 11, color: kBoxInkSoft),
                      ),
                      Text(
                        '  →  ',
                        style: TextStyle(color: kBoxInkSoft, fontSize: 11),
                      ),
                      Text(
                        '${up.toLevel}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: kBoxAccent,
                        ),
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
      color: CreamPalette.better.withValues(alpha: 0.16),
      shape: FoE.facet(radius: 6),
    ),
    child: Text(
      '${_statAbbrev(stat)} +$gain',
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        color: CreamPalette.better,
      ),
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
                      fontWeight: FontWeight.w400,
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
                      ).copyWith(color: d.color, fontWeight: FontWeight.w400),
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
                  fontWeight: FontWeight.w400,
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

/// The pages of the battle screen's command deck.
enum _DeckTab { attack, items, change }

/// A clip that cuts only below the box's bottom edge (the feet): everything
/// above and to the sides is left alone. The K.O. sink needs the cut under the
/// feet, but the isometric sheets overflow their slot upward.
class _BelowFeetClipper extends CustomClipper<Rect> {
  const _BelowFeetClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-4000, -4000, 4000, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
