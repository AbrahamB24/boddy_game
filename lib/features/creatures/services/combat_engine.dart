import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/ability_def.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/status_effects.dart';
import 'combat_tuning.dart';
import '../../../core/tuning/game_tuning.dart';

enum CombatOutcome { victory, defeat, fled }

/// A single visible effect of the last action — drives the floating combat
/// text on the battle screen (a damage/heal number popping over the affected
/// combatant). Rebuilt every action; the UI reads [CombatEngine.lastEvents]
/// whenever [CombatEngine.lastAction] changes.
class CombatEvent {
  final Combatant target;

  /// Whoever's turn this was — the log line's own subject ("X attacks...",
  /// "X builds AP…", "X is afflicted by..."). Added so the UI can put that
  /// monster's own portrait beside its log line without re-deriving "who
  /// acted" from mutable engine state at a different point in time than the
  /// event was actually created — [currentActor] can already have moved on
  /// by the time a ChangeNotifier listener gets to react (user 2026-08-29:
  /// "vor den Namen der Monster jeweils ein kleines Icon des Monsterassets
  /// zeigen").
  final Combatant? actor;

  /// Magnitude (always ≥ 0): damage dealt, or HP restored when [heal].
  final int amount;

  /// Green heal number instead of a damage number.
  final bool heal;

  /// Damage crit — the UI shows it bigger / in gold.
  final bool crit;

  /// The strike missed — the UI shows "Miss" instead of a number.
  final bool miss;

  /// Type multiplier of the hit: 1.0 neutral, >1 super-effective, <1 resisted.
  /// Lets the UI tag "super effective!" on the floating number.
  final double typeMult;

  /// The striking move's element — drives the element-coloured impact flash on
  /// the reacting sprite. Neutral for the basic attack, heals and status DoT.
  final CreatureElement element;

  /// A positive status landed on [target] (a self-buff, a regen tick) — the
  /// UI sweeps white lines bottom-to-top over it. Independent of [amount]:
  /// most buffs carry no number at all.
  final bool buff;

  /// A negative status (a secondary debuff — stat drop, etc.) landed on
  /// [target] — the UI sweeps red lines top-to-bottom over it. Rides
  /// alongside the damage event that caused it, not a separate hit.
  final bool debuff;

  /// [target] ended its turn WITHOUT spending it on an action — banking AP
  /// for a stronger move, out of AP entirely, or the player's own "End Turn"
  /// button (user 2026-08-29: "Wenn die KI nichts macht... " / "Das ist
  /// immer so, wenn End Turn gedrückt wird" — the same visual either way).
  /// The UI closes a big yellow ring over it, reading as "AP recharging".
  final bool charging;

  const CombatEvent({
    required this.target,
    this.actor,
    this.amount = 0,
    this.heal = false,
    this.crit = false,
    this.miss = false,
    this.typeMult = 1.0,
    this.element = CreatureElement.neutral,
    this.buff = false,
    this.debuff = false,
    this.charging = false,
  });
}

// Pure combat logic (no UI, no DB): CTB turn queue, damage/heal/status
// resolution, the ACTION-POINT economy (there is no combat energy pool any
// more) and a simple shared AI used both by enemies
// and the player's auto-battle toggle. The screen listens via ChangeNotifier
// and renders whatever this exposes — all rules live HERE so unit tests can
// drive battles without Flutter.
//
// Turn model: kept CTB (continuous initiative queue, faster creatures act
// more often) per explicit user decision, even though the balance-pass doc's
// wording reads like classic simultaneous-round Pokemon combat. Discrete
// "Priority" moves are approximated as a CTB queue-jump (see
// _priorityNudgeFactor) rather than a real priority tier, and status
// durations/DoT tick on each AFFLICTED combatant's own turn-end (not a
// global "round") — the same convention the original haste/slow system used.
class CombatEngine extends ChangeNotifier {
  final List<Combatant> players; // 1..3
  final List<Combatant> enemies; // 1..n
  final math.Random rng;

  /// Turns off the miss roll AND the crit roll, for BOTH sides, for the
  /// whole fight (user 2026-09-03: "während des Tutorials sollten Effekte
  /// wie 'miss oder Crit' ausgeschaltet sein, damit es funktioniert").
  ///
  /// The tutorial's scripted first fight forces every HP change to an exact
  /// named percentage regardless of what the real formula computes — the
  /// NUMBER was never at risk from a bad roll. What a stray miss or crit
  /// broke was the PRESENTATION around it: a "misses!" log line right
  /// before the HP bar visibly drops anyway, or a "Critical!" flash on a
  /// hit the script had already fixed at 33%. This makes the shown
  /// roll match the guaranteed outcome instead of contradicting it.
  final bool deterministicCombat;

  /// FFX-style CTB: a combatant's next turn lands `_turnCost / speed` time
  /// units after its current one — double speed = twice as many turns.
  static const double _turnCost = 1000.0;

  /// The always-available hit every monster has, inside the "Basis" move-power
  /// class (30-50) from the balance pass. It costs [kBasicAttackApCost] AP —
  /// "free" only in the sense that no species has to learn it.
  ///
  /// It used to generate combat ENERGY (kBasicAttackEnergyGain) and cost nothing;
  /// that pool was replaced by action points on 2026-07-20 and nothing here
  /// generates anything any more. This figure is also the anchor of the whole
  /// cost scale: power 40 must price at kBasicAttackApCost, see
  /// AbilityDef._derivedApCost.
  ///
  /// Just [kBasicAttackPower] — kept as its own name here since so much of
  /// this file already says `basicAttackPower`, but the number itself lives
  /// in creature_enums.dart now so combatant.dart's fallback AbilityDef can
  /// share it without a circular import (user 2026-09-03: "attack soll eine
  /// normale Fähigkeit sein").
  static const int basicAttackPower = kBasicAttackPower;

  /// Global damage dial (docs/balancing.md §4) — calibrated via the combat
  /// Monte-Carlo so an equal-level 3v1 resolves in ~4–6 player actions.
  /// At the standard budget (ATK=DEF): basis ≈ 0.5·ATK·damageScale + 2,
  /// i.e. per-hit ≈ maxHP/5 at every level (both scale with stat growth).
  ///
  /// NOW a live dial (CombatTuning), editable in Dev Mode ▸ Balance. This
  /// getter is the single read point so tuning takes effect on the next hit
  /// with no restart; the const default lives in CombatTuning.
  static double get damageScale => CombatTuning().damageScale;

  /// Hard safety ceiling on ONE hit: no single strike may remove more than
  /// this fraction of the target's max HP. A full-HP combatant therefore
  /// always survives one hit — a one-shot is structurally impossible.
  ///
  /// This is a GUARANTEE, not a balance dial (so it is const, not in
  /// CombatTuning): the user requires that two starters can never one-shot
  /// each other, no matter the tuning, and repeatedly confirmed it (2026-07-17).
  /// The multiplier stack (STAB 1.5 × type 1.5 × crit 1.5 = 3.4×) sits on top
  /// of the "per-hit ≈ maxHP/5" calibration, so a kind-stacked hit CAN exceed
  /// full HP at equal level — this clamp is what makes it a big hit (half a
  /// health bar) instead of a deletion. Normal hits (~20% of max HP) never
  /// reach it, so the calibrated anchors are unaffected. Applies to both
  /// sides equally.
  static double get kMaxHitHpFraction =>
      GameTuning.i.raw(Dials.maxHitHpFraction);

  /// Base hit chance before any debuffs (Blenden multiplies this down).
  /// Not specified numerically in the balance doc — picked from its
  /// suggested "~90-95%" range.
  static double get kBaseAccuracy => GameTuning.i.raw(Dials.baseAccuracy);

  /// How much a Priority-flagged ability pulls the user's next turn forward
  /// in the CTB queue, as a fraction reduction of the normal turnCost/speed
  /// increment (e.g. priority 1 → 30% sooner). Approximation, not a literal
  /// discrete tier — see class doc comment.
  static const double _priorityNudgeFactor = 0.30;

  CombatOutcome? outcome;
  String lastAction = '';

  /// Bumped once per resolved action (basic attack, ability use, forced/
  /// voluntary switch, a frozen/feared skip) — a monotonic identity for "a
  /// new action happened" that the UI can compare, because [lastAction] alone
  /// cannot: two buffs in a row with nothing numeric in their text (user
  /// 2026-08-29: "Wenn ich mehrere Buffs/Debuffs pro Runde mache, dann kommt
  /// die Animation nicht mehr") produce the IDENTICAL string, and the battle
  /// screen was comparing by string equality.
  int actionSeq = 0;

  /// Visible effects of the most recent action (damage/heal numbers), read by
  /// the battle screen for floating combat text. Cleared at the start of every
  /// player/AI action so a later turn-end notify never re-floats stale numbers.
  final List<CombatEvent> lastEvents = [];

  /// One-shot override for the tutorial's scripted first fight (user
  /// 2026-09-04): consumed by the very next damaging hit this engine
  /// resolves — a forced Miss, or a forced exact number — in place of the
  /// real accuracy roll and [_rollDamage]. Without this, the scripted beats
  /// could only fix the HP a hit left BEHIND; the floating number and log
  /// line still showed whatever the real stats/RNG produced, which almost
  /// never matched the document's own "3 damage", "Miss", "8 damage"... Set
  /// right before the one real engine call each beat makes; cleared
  /// automatically the instant a damage hit consumes it.
  ({int damage, bool miss})? scriptedNextHit;

  /// One-shot AP-cost override for the very next [useAbility] call, same
  /// shape as [scriptedNextHit] but for what the move COSTS rather than what
  /// it deals. Used ONLY by the tutorial's scripted "tackle" beat (user
  /// 2026-09-05: "ich starte mit 3 AP, sollte aber nur mit 2 starten") — the
  /// opening actor's deliberately-lean AP used to get invisibly topped up to
  /// afford a full Attack ([kBasicAttackApCost] > the opener's own
  /// [kStartApFirst]); scripting the COST down to what the player actually
  /// sees keeps the AP counter honest instead of silently jumping ahead of
  /// their own tap.
  int? scriptedApCost;

  // ── Balancing instrumentation (dev matrix tool) ───────────
  /// AP-spending actions taken this battle, per side. This is what the
  /// balancing tool's "a fight lasts 3–10 actions" rule counts — attacks and
  /// abilities, not switches or banked turns.
  int playerActionsTaken = 0;
  int enemyActionsTaken = 0;

  /// How often each ability id was used, per side — feeds the "every ability
  /// earns its slot" check. Sides are separate because ability DEFS are shared
  /// between species.
  final Map<String, int> playerAbilityUses = {};
  final Map<String, int> enemyAbilityUses = {};

  void _countAction(Combatant actor, [AbilityDef? ability]) {
    if (actor.isPlayerSide) {
      playerActionsTaken++;
      if (ability != null) {
        playerAbilityUses[ability.id] =
            (playerAbilityUses[ability.id] ?? 0) + 1;
      }
    } else {
      enemyActionsTaken++;
      if (ability != null) {
        enemyAbilityUses[ability.id] = (enemyAbilityUses[ability.id] ?? 0) + 1;
      }
    }
  }

  /// PvP mode (2026-09-15, social/real-time-6v6 feature): when true, the
  /// "enemies" side gets the SAME player-grade field control as [players] —
  /// a bounded bench that pauses for a chosen reserve on faint
  /// ([needsEnemySwitch]/[switchActiveEnemy]) instead of the PvE wave's
  /// unlimited bench that refills itself instantly. PvE combat (the default,
  /// `isPvp: false`) is byte-for-byte unchanged: every branch this flag adds
  /// is dead code unless a caller opts in, which only battle_screen.dart's
  /// own `isPvp` mode does. Necessary because in a real PvP match BOTH sides
  /// are humans who expect to choose their own reserve, and
  /// [switchActivePlayer] was written player-only.
  final bool isPvp;

  CombatEngine({
    required this.players,
    required this.enemies,
    math.Random? rng,
    this.deterministicCombat = false,
    this.isPvp = false,
  }) : rng = rng ?? math.Random() {
    // Initial schedule; the tiny index epsilon makes equal-speed ties
    // deterministic (list order) instead of map-iteration luck.
    var i = 0;
    for (final c in [...players, ...enemies]) {
      c.nextTurnAt = _turnCost / c.effectiveSpeed + i * 0.001;
      i++;
    }
    // Both sides take the field in ROSTER ORDER — the first three of the party
    // the prep screen sent in, and the first three of the pack. No _sendIn
    // here: these are the opening positions, not arrivals, so they keep the
    // schedule just computed.
    _fillField(players, playerField, schedule: false);
    _fillField(enemies, enemyField, schedule: false);
    _acting = _activeAlive.isEmpty ? null : _lowestNextTurn();
    _seedOpeningAp();
  }

  /// Combatants that have already had a turn begin. A monster's FIRST turn runs
  /// on its seeded opening AP; regen starts from its second turn, so "the second
  /// monster opens on 3" stays exactly 3 instead of 3 + regen. Identity-based
  /// (Combatant has no ==), which is what we want.
  final Set<Combatant> _opened = {};

  /// Seeds the opening AP pools (user 2026-07-20, ramp extended 2026-09-04):
  /// whoever acts FIRST opens on [kStartApFirst], whoever is next opens on
  /// [kStartApSecond], and each one behind that opens one AP richer than the
  /// one before it — a monster standing sixth in the opening order is not
  /// stuck on the same lean pool as the one standing second — capped at its
  /// own stage's capacity. Deliberately NOT a regen — turn one is the lean
  /// one, and a reserve coming in later arrives on whatever this left it
  /// with.
  void _seedOpeningAp() {
    final first = _acting;
    if (first != null) {
      first.ap = math.min(maxActionPointsForStage(first.stage), kStartApFirst);
    }
    // Everyone else, ramped in the order they'll actually come up — field
    // members before whatever is still waiting on the bench.
    final rest = [...players, ...enemies]
      ..removeWhere((c) => identical(c, first))
      ..sort((a, b) => a.nextTurnAt.compareTo(b.nextTurnAt));
    for (var i = 0; i < rest.length; i++) {
      final c = rest[i];
      c.ap = math.min(maxActionPointsForStage(c.stage), kStartApSecond + i);
    }
    // The first actor is already standing in its opening turn — mark it so its
    // NEXT turn is the one that regenerates.
    if (first != null) _opened.add(first);
    _turnPriority = 0;
  }

  /// Overrides who opens the fight — used ONLY by the tutorial's scripted
  /// first battle, whose enemy is picked purely for TYPE effectiveness
  /// against whatever starter it's fighting (see `scriptedFirstBattleEnemy`)
  /// and fights at its own natural stats, unlike an ordinary jumpstart fight.
  /// Real speed decides turn order everywhere else in the game; this one
  /// fight's opening beat ("tackle") is authored to be the player's, not
  /// rolled, so a starter that happens to be slower than its counter-picked
  /// opponent must not lose the coin flip.
  ///
  /// SWAPS ap with whoever [_seedOpeningAp] actually gave the opening turn
  /// to, rather than re-running that seed with [c] as `first` — re-seeding
  /// would touch every OTHER combatant's ap too (the whole `rest` ramp), not
  /// just these two. [_opened] is corrected the same way: [_seedOpeningAp]
  /// already (wrongly, as it turns out) marked the real opener as having had
  /// its first turn — undo that and mark [c] instead, so whichever of the
  /// two genuinely takes ITS first turn later still skips the one-time regen
  /// bonus exactly once, not zero or two times.
  void forceOpeningActor(Combatant c) {
    final old = _acting;
    if (old == null || identical(old, c)) return;
    _acting = c;
    final tmp = c.ap;
    c.ap = old.ap;
    old.ap = tmp;
    _opened.remove(old);
    _opened.add(c);
  }

  /// Forces [c] to act NEXT, no AP/[_opened] bookkeeping touched — for
  /// correcting turn order MID-fight rather than at the opening turn (see
  /// [forceOpeningActor] for that one). Used by the tutorial's scripted
  /// battle after each of its three enemy beats: with only two combatants on
  /// the field, a genuinely faster enemy (battle 1's own doc: picked for
  /// type effectiveness, fighting at natural stats — nothing evens out its
  /// speed) can win two or three real CTB turns in a row before the
  /// player's own `nextTurnAt` next comes up, each one an unscripted
  /// fallback hit the HP-guard in `_runScriptedEnemyBeat` keeps harmless but
  /// still visibly plays out (user 2026-09-05: "infernoclaw attackiert
  /// weiterhin 3x nacheinander (2 davon sind nicht im tutorial
  /// festgehalten)"). Forcing the player back to `_acting` the instant the
  /// ONE authored enemy beat resolves is what actually stops the extras from
  /// ever getting scheduled, rather than just neutering their damage.
  void forceActing(Combatant c) => _acting = c;

  /// Starts the acting monster's turn: it REGENERATES its stage's regen, capped
  /// at its capacity — it does not refill. Unspent points from earlier turns are
  /// still there, which is the whole point of the resource.
  void _beginTurn() {
    if (outcome != null || _activeAlive.isEmpty) return;
    _turnPriority = 0;
    final a = _acting ??= _lowestNextTurn();
    // First turn on the field → it already holds its opening AP.
    if (_opened.add(a)) return;
    a.ap = math.min(
      maxActionPointsForStage(a.stage),
      a.ap + apRegenForStage(a.stage),
    );
  }

  // ── The field (user design 2026-07-27) ─────────────────────
  // "Wenn pro Seite mehrere Monster kämpfen, kämpfen diese wie in einem jrpg
  // gleichzeitig. D.h sie tauchen in der Rundenleiste auf und sobald sie an der
  // Reihe sind, können sie ihre Aktion machen. Daher werden sie auch immer
  // angezeigt. Maximal 3 Monster können pro Seite gleichzeitig kämpfen."
  //
  // This replaces the 1v1 reserve model (2026-07-17), where a side's roster
  // took turns ONE AT A TIME and the rest sat on a bench that could neither act
  // nor be hit. A party of four was really four sequential duels: bringing more
  // monsters bought you more HP, never more actions, and the initiative bar
  // only ever alternated between two names.
  //
  // Now up to [kFieldSlots] per side stand on the field TOGETHER. Every one of
  // them is in the CTB queue, takes its own turns and can be targeted.
  //
  //   player  up to 3 on the field, up to 3 in reserve (kMaxPartySize = 6).
  //           A reserve comes in when a slot empties — the player picks who
  //           (needsPlayerSwitch), and may also swap on their own turn for AP.
  //   enemies up to 3 on the field and an UNLIMITED bench behind them, which
  //           steps into an empty slot the moment one opens.
  //
  // Slots are positional and kept as a fixed-length list with holes: a monster
  // stays where it stands for the whole fight, so the battlefield doesn't
  // reshuffle under the player's finger when a neighbour goes down.

  /// How many monsters of one side stand on the field at once.
  static int get kFieldSlots => GameTuning.i.count(Dials.fieldSlots);

  /// The player's field, by slot. Null = the slot is empty (nobody left to fill
  /// it, or a reserve is owed — see [needsPlayerSwitch]).
  final List<Combatant?> playerField = List.filled(kFieldSlots, null);
  final List<Combatant?> enemyField = List.filled(kFieldSlots, null);

  /// The monster whose turn it is. Tracked EXPLICITLY rather than derived from
  /// the queue: with several combatants on the field an ally can faint in the
  /// middle of somebody else's turn, and a derived "lowest nextTurnAt" would
  /// silently hand the rest of that turn to a different monster.
  Combatant? _acting;

  /// Fills empty slots on [side]'s field from its bench, in roster order.
  void _fillField(
    List<Combatant> side,
    List<Combatant?> field, {
    bool schedule = true,
  }) {
    for (var i = 0; i < kFieldSlots; i++) {
      if (field[i] != null) continue;
      final next = _nextFromBench(side, field);
      if (next == null) return;
      field[i] = next;
      if (schedule) _sendIn(next);
    }
  }

  /// The first alive roster member not already standing on [field].
  Combatant? _nextFromBench(List<Combatant> side, List<Combatant?> field) {
    for (final c in side) {
      if (!c.alive) continue;
      if (field.any((f) => identical(f, c))) continue;
      return c;
    }
    return null;
  }

  /// Everyone actually standing on the field, alive, in slot order.
  List<Combatant> get fieldPlayers => [
    for (final c in playerField)
      if (c != null && c.alive) c,
  ];
  List<Combatant> get fieldEnemies => [
    for (final c in enemyField)
      if (c != null && c.alive) c,
  ];

  /// The field of whichever side [c] fights for.
  List<Combatant> _fieldOf(Combatant c) =>
      c.isPlayerSide ? fieldPlayers : fieldEnemies;

  /// The living opponents of [c] — everyone it may attack.
  List<Combatant> opponentsOf(Combatant c) =>
      c.isPlayerSide ? fieldEnemies : fieldPlayers;

  // ── Action points (user redesign 2026-07-20) ──────────────
  // AP live ON the combatant now ([Combatant.ap]) — they are CARRIED between
  // that monster's turns, not handed out fresh each time. A turn begins by
  // regenerating [apRegenForStage] up to [maxActionPointsForStage]; each action
  // spends from the pool; the turn ends when nothing is affordable or the player
  // ends it, and whatever is left is STILL THERE next turn.
  //
  // Highest priority among this turn's abilities — applied once at turn end so
  // a priority move still pulls the next turn forward.
  int _turnPriority = 0;

  /// AP the acting monster currently holds.
  int get turnAp {
    if (outcome != null || _activeAlive.isEmpty) return 0;
    return currentActor.ap;
  }

  /// The acting monster's AP CAPACITY — for the UI to show "3/6 AP".
  int get currentActorMaxAp =>
      outcome == null ? maxActionPointsForStage(currentActor.stage) : 0;

  /// Cheapest action the current actor could still take — the turn auto-ends
  /// once its pool drops below this.
  int _minActionCost() {
    var min = kBasicAttackApCost; // an attack is always available
    if (currentActor.isPlayerSide) {
      min = math.min(min, kItemApCost); // Items button is always up
      if (benchedPlayers.isNotEmpty) min = math.min(min, kSwitchApCost);
    }
    return min;
  }

  /// True while the acting side still has AP to do something — the UI keeps
  /// the action panel open until this is false (then auto-ends).
  bool get canActThisTurn =>
      outcome == null &&
      !needsPlayerSwitch &&
      !needsEnemySwitch &&
      currentActor.ap >= _minActionCost();

  /// The player's acting monster, or — outside its turn — the first one
  /// standing. Kept for the screens that ask "whose panel am I drawing?"; the
  /// FIELD ([fieldPlayers]) is what the battlefield itself renders now.
  Combatant? get activePlayer {
    final acting = _acting;
    if (acting != null && acting.isPlayerSide && acting.alive) return acting;
    final field = fieldPlayers;
    return field.isEmpty ? null : field.first;
  }

  /// The enemy the UI treats as "the" opponent when it needs exactly one — the
  /// catch overlay, which only ever runs against a lone wild.
  Combatant? get activeEnemy {
    final field = fieldEnemies;
    return field.isEmpty ? null : field.first;
  }

  /// Alive roster members NOT on the field — the reserve.
  List<Combatant> get benchedPlayers => [
    for (final c in players)
      if (c.alive && !playerField.any((f) => identical(f, c))) c,
  ];

  List<Combatant> get benchedEnemies => [
    for (final c in enemies)
      if (c.alive && !enemyField.any((f) => identical(f, c))) c,
  ];

  /// Empty player slots that a reserve is waiting to fill.
  int get openPlayerSlots {
    var n = 0;
    for (final c in playerField) {
      if (c == null || !c.alive) n++;
    }
    return n;
  }

  /// True while a player slot stands empty and somebody could fill it. The UI
  /// shows the reserve picker; the turn order does not move on until
  /// [switchActivePlayer] has filled it.
  ///
  /// With three slots this can be owed SEVERAL times over (an AoE that drops
  /// two at once), so it stays true until every fillable slot has been filled.
  bool get needsPlayerSwitch =>
      outcome == null && openPlayerSlots > 0 && benchedPlayers.isNotEmpty;

  /// Empty enemy slots a reserve is waiting to fill — only meaningful in
  /// [isPvp] mode; in PvE the enemy bench refills itself instantly (see
  /// [_resolveFaints]), so this is never owed.
  int get openEnemySlots {
    if (!isPvp) return 0;
    var n = 0;
    for (final c in enemyField) {
      if (c == null || !c.alive) n++;
    }
    return n;
  }

  /// [needsPlayerSwitch]'s mirror for the enemy side, gated behind [isPvp] —
  /// see that flag's doc comment.
  bool get needsEnemySwitch =>
      isPvp &&
      outcome == null &&
      openEnemySlots > 0 &&
      benchedEnemies.isNotEmpty;

  // Whole-roster liveness — drives victory/defeat (a side loses only when its
  // WHOLE roster is down, not when the field empties).
  List<Combatant> get alivePlayers =>
      players.where((c) => c.alive).toList(growable: false);
  List<Combatant> get aliveEnemies =>
      enemies.where((c) => c.alive).toList(growable: false);

  /// Everyone on the field, both sides — the combatants that take turns and can
  /// be targeted.
  List<Combatant> get _activeAlive => [...fieldPlayers, ...fieldEnemies];

  Combatant get currentActor {
    final acting = _acting;
    if (acting != null && acting.alive && _onField(acting)) return acting;
    return _lowestNextTurn();
  }

  bool _onField(Combatant c) =>
      playerField.any((f) => identical(f, c)) ||
      enemyField.any((f) => identical(f, c));

  Combatant _lowestNextTurn() =>
      _activeAlive.reduce((a, b) => a.nextTurnAt <= b.nextTurnAt ? a : b);

  /// Cheap deterministic fingerprint of the whole battle state (PvP desync
  /// detection, see pvp_sync_service.dart's [PvpAction.stateHash]): two
  /// independently-run engines fed the identical action sequence must always
  /// compute the same value. Covers hp/ap/status/alive for EVERY combatant
  /// (bench included — a benched monster's hp still matters) plus who's
  /// acting, since that's exactly the state a missed or misapplied action
  /// would perturb. Deliberately NOT a security boundary (a client could lie
  /// about its own hash) — only a "did our simulations quietly diverge"
  /// self-check.
  int get stateHash {
    var hash = 0;
    for (final c in [...players, ...enemies]) {
      hash = Object.hash(
        hash,
        c.id,
        c.hp,
        c.ap,
        c.alive,
        c.mainStatus,
        c.mainStatusTurnsRemaining,
        c.secondaryDebuffs.length,
        c.selfBuffs.length,
      );
    }
    return Object.hash(hash, _acting?.id);
  }

  bool get isPlayerTurn =>
      outcome == null &&
      !needsPlayerSwitch &&
      !needsEnemySwitch &&
      currentActor.isPlayerSide;

  /// [isPlayerTurn]'s mirror for the enemy side — only meaningful in [isPvp]
  /// mode, where the "enemy" is a second human with the same voluntary-
  /// switch rights (see [switchActiveEnemy]).
  bool get isEnemyTurn =>
      outcome == null &&
      !needsPlayerSwitch &&
      !needsEnemySwitch &&
      !currentActor.isPlayerSide;

  /// Upcoming turn order for the initiative bar. EVERY monster on the field is
  /// in it now (up to six), ordered by when the CTB queue reaches them — which
  /// is the whole point of the simultaneous model: the bar is where you read
  /// that your slow tank acts after both of their attackers.
  List<Combatant> forecast(int count) {
    final sim = [
      for (final c in _activeAlive)
        (combatant: c, at: c.nextTurnAt, gain: _turnCost / c.effectiveSpeed),
    ];
    final order = <Combatant>[];
    final at = {for (final e in sim) e.combatant: e.at};
    for (var i = 0; i < count && sim.isNotEmpty; i++) {
      var best = sim.first;
      for (final e in sim) {
        if (at[e.combatant]! < at[best.combatant]!) best = e;
      }
      order.add(best.combatant);
      at[best.combatant] = at[best.combatant]! + best.gain;
    }
    return order;
  }

  /// Schedules a monster that just entered the field so it does NOT get a free
  /// immediate turn: it acts one of its own turns after the queue's CURRENT
  /// position.
  ///
  /// The clock is the acting monster's own slot rather than "the opponent's",
  /// which is what it used to be — with up to six on the field there is no
  /// single opponent to measure against, and taking the fastest enemy's
  /// position would have handed slow reserves a free strike.
  void _sendIn(Combatant c) {
    final now =
        _acting?.nextTurnAt ??
        (_activeAlive.isEmpty ? c.nextTurnAt : _lowestNextTurn().nextTurnAt);
    c.nextTurnAt = now + _turnCost / c.effectiveSpeed;
  }

  /// Sends a reserve in. Two jobs, as before:
  ///
  ///  • FORCED — a slot stands empty ([needsPlayerSwitch]). The reserve drops
  ///    into that slot and the fight continues where it paused. It does NOT
  ///    inherit anyone's turn: the other two slots were never interrupted.
  ///  • VOLUNTARY — on the acting monster's own turn, it steps out and [index]
  ///    steps into ITS slot, paying [kSwitchApCost] out of the leaving
  ///    monster's own pool. The incoming one inherits the turn slot, so no turn
  ///    is lost.
  ///
  /// Returns null on success or a user-facing error.
  String? switchActivePlayer(int index) {
    if (outcome != null) return 'The battle is over';
    if (index < 0 || index >= players.length) return 'No such monster';
    final target = players[index];
    if (!target.alive) return '${target.name} is K.O.';
    if (playerField.any((f) => identical(f, target))) {
      return '${target.name} is already fighting';
    }

    final forced = needsPlayerSwitch;
    if (!forced && !isPlayerTurn) {
      return 'You can only switch on your turn';
    }
    if (forced) {
      final slot = playerField.indexWhere((c) => c == null || !c.alive);
      if (slot < 0) return 'No free slot';
      playerField[slot] = target;
      _sendIn(target);
      lastEvents.clear();
      actionSeq++;
      lastAction = '🔄 ${target.name} steps up!';
      // Resume whatever the empty slot interrupted — the end of a turn, or
      // nothing at all when an ally fell during somebody else's.
      _advanceIfPending();
      _checkOutcome();
      notifyListeners();
      return null;
    }
    // Voluntary: the OUTGOING monster pays out of its own pool (AP are carried
    // per monster since 2026-07-20, so there is no budget to hand over). The
    // incoming one arrives on its own AP and does NOT regen — it isn't starting
    // a fresh turn, it is stepping into this one.
    final outgoing = currentActor;
    if (outgoing.ap < kSwitchApCost) {
      return 'Not enough AP to switch ($kSwitchApCost needed)';
    }
    final slot = playerField.indexWhere((c) => identical(c, outgoing));
    if (slot < 0) return 'That monster is not on the field';
    outgoing.ap -= kSwitchApCost;
    target.nextTurnAt = outgoing.nextTurnAt;
    playerField[slot] = target;
    _acting = target;
    lastEvents.clear();
    actionSeq++;
    lastAction = '🔄 ${target.name} steps up!';
    _afterAction(target);
    return null;
  }

  /// [switchActivePlayer]'s exact mirror for the enemy side — only usable in
  /// [isPvp] mode (an enemy roster index otherwise has no bench to switch
  /// from at all; PvE's unlimited bench refills itself, see
  /// [_resolveFaints]). See the [isPvp] field's doc comment for why this
  /// exists.
  String? switchActiveEnemy(int index) {
    if (!isPvp) return 'Not a PvP match';
    if (outcome != null) return 'The battle is over';
    if (index < 0 || index >= enemies.length) return 'No such monster';
    final target = enemies[index];
    if (!target.alive) return '${target.name} is K.O.';
    if (enemyField.any((f) => identical(f, target))) {
      return '${target.name} is already fighting';
    }

    final forced = needsEnemySwitch;
    if (!forced && !isEnemyTurn) {
      return 'You can only switch on your turn';
    }
    if (forced) {
      final slot = enemyField.indexWhere((c) => c == null || !c.alive);
      if (slot < 0) return 'No free slot';
      enemyField[slot] = target;
      _sendIn(target);
      lastEvents.clear();
      actionSeq++;
      lastAction = '🔄 ${target.name} steps up!';
      _advanceIfPending();
      _checkOutcome();
      notifyListeners();
      return null;
    }
    final outgoing = currentActor;
    if (outgoing.ap < kSwitchApCost) {
      return 'Not enough AP to switch ($kSwitchApCost needed)';
    }
    final slot = enemyField.indexWhere((c) => identical(c, outgoing));
    if (slot < 0) return 'That monster is not on the field';
    outgoing.ap -= kSwitchApCost;
    target.nextTurnAt = outgoing.nextTurnAt;
    enemyField[slot] = target;
    _acting = target;
    lastEvents.clear();
    actionSeq++;
    lastAction = '🔄 ${target.name} steps up!';
    _afterAction(target);
    return null;
  }

  /// Spends [kItemApCost] AP for [actor] using a battle item — the fixed
  /// price is the same for every item (user 2026-09-05: "ein Item benutzen,
  /// kostet immer 1 AP"), unlike an ability's power-derived cost. The actual
  /// heal/buff is applied by the caller directly on the Combatant (items
  /// aren't AbilityDefs); this just gates and spends the AP through the same
  /// [_afterAction] path everything else uses, so the turn stays open when
  /// AP is left over instead of always ending it.
  ///
  /// Returns a user-facing error (not enough AP / not this monster's turn)
  /// or null when the AP was spent.
  String? useItem(Combatant actor) {
    if (outcome != null || !actor.alive) return 'The battle is over.';
    if (!identical(actor, currentActor)) return 'Not this monster\'s turn.';
    if (actor.ap < kItemApCost) {
      return 'Not enough AP ($kItemApCost needed).';
    }
    actor.ap -= kItemApCost;
    lastEvents.clear();
    actionSeq++;
    lastAction = '🎒 ${actor.name} uses an item';
    _afterAction(actor);
    return null;
  }

  /// Spends [kCatchApCost] AP for [actor] attempting a hunt catch — same
  /// gate/spend/continue shape as [useItem]. The hit-or-miss QTE result
  /// itself lives in the UI (battle_screen.dart's ring mini-game); this only
  /// prices the ATTEMPT through the shared AP economy, so trying to catch a
  /// fielded wild costs as much as attacking it and competes with attacking
  /// for the turn instead of being a free, unconditional turn-ender
  /// (2026-09-11 — catching used to always end the whole battle, so it never
  /// needed an AP price of its own).
  ///
  /// Called once the QTE overlay has already closed (hit or miss), same
  /// timing [endTurn] used to be called at — spending AP/continuing the turn
  /// while the ring overlay is still up would let an enemy act underneath it.
  String? attemptCatch(Combatant actor) {
    if (outcome != null || !actor.alive) return 'The battle is over.';
    if (!identical(actor, currentActor)) return 'Not this monster\'s turn.';
    if (actor.ap < kCatchApCost) {
      return 'Not enough AP ($kCatchApCost needed).';
    }
    actor.ap -= kCatchApCost;
    lastEvents.clear();
    actionSeq++;
    lastAction = '🪤 ${actor.name} tries a catch';
    _afterAction(actor);
    return null;
  }

  /// Clears the fallen out of both fields and refills what can be refilled.
  ///
  /// The enemy's bench is UNLIMITED and steps in by itself the moment a slot
  /// opens (user 2026-07-27) — that is what makes a pack a wave rather than a
  /// queue. The player's side is left empty on purpose: which reserve comes in
  /// is a decision, and [needsPlayerSwitch] holds the fight for it.
  void _resolveFaints() {
    for (var i = 0; i < kFieldSlots; i++) {
      if (playerField[i] != null && !playerField[i]!.alive) {
        playerField[i] = null;
      }
      if (enemyField[i] != null && !enemyField[i]!.alive) enemyField[i] = null;
    }
    // PvP: the "enemy" is a human too, and picks their own reserve — the
    // same reason the player's own side is left empty here (see this
    // method's own doc comment above). PvE keeps the unlimited-bench
    // auto-fill unchanged.
    if (!isPvp) _fillField(enemies, enemyField);
    _checkOutcome();
  }

  /// Removes a caught wild from the fight entirely — not fainted, GONE — so
  /// it no longer counts toward [enemies]/[totalXpReward] (a catch is the
  /// reward, it earns no kill XP on top) and can never be targeted again.
  /// Refills the vacated slot from the bench exactly like a faint does, then
  /// re-checks the outcome, since this may have been the last one standing
  /// (2026-09-11 — hunts now field several wilds in ONE continuous battle
  /// instead of one battle per find, so a catch must continue the fight
  /// rather than end it).
  void catchEnemy(Combatant wild) {
    if (outcome != null) return;
    for (var i = 0; i < kFieldSlots; i++) {
      if (identical(enemyField[i], wild)) enemyField[i] = null;
    }
    enemies.remove(wild);
    _fillField(enemies, enemyField);
    _checkOutcome();
    notifyListeners();
  }

  // ── Actions ───────────────────────────────────────────────
  /// AP an ability costs. The author can now set it explicitly in Dev Mode
  /// (AbilityDef.apCost); otherwise it is derived from the move's strength.
  /// This just delegates to [AbilityDef.resolvedApCost] — the one source of
  /// truth (the value the abilities are already capped to per unlock stage in
  /// Combatant._capToStage).
  static int abilityApCost(AbilityDef ability) => ability.resolvedApCost;

  /// Convenience wrapper, not a separate mechanic — Attack is a genuine
  /// AbilityDef now (user 2026-09-03: "attack soll eine normale Fähigkeit
  /// sein. Falls es noch andere gibt, bitte auch diese als echte Fähigkeit
  /// aufnehmen"), resolved onto every combatant by Combatant.fromInstance/
  /// fromSpecies alongside its equipped/wild moves, and this just runs it through the
  /// exact same [useAbility] every other move goes through (same accuracy
  /// roll, same damage formula, same crit/miss handling, same log format).
  /// Kept under its own name because every existing caller — the AI's own
  /// fallback, the tutorial's scripted enemy beats — already asks for it
  /// this way; nothing about THEM needed to change for Attack to stop being
  /// a special case underneath.
  void basicAttack(Combatant actor, Combatant target) {
    final attack = actor.abilities.firstWhere(
      (a) => a.id == 'attack',
      orElse: () => AbilityDef(
        id: 'attack',
        name: 'Attack',
        element: CreatureElement.neutral,
        kind: AbilityKind.damage,
        target: AbilityTarget.enemy,
        power: basicAttackPower,
        // Explicit, not auto-derived (user 2026-09-08: "attack soll nur 2 AP
        // kosten") — always matches the dial, whatever power/powerPerAp do.
        apCost: kBasicAttackApCost,
      ),
    );
    useAbility(actor, attack, target);
  }

  /// Returns a user-facing error (not enough AP / invalid target) or null when
  /// the ability resolved.
  String? useAbility(Combatant actor, AbilityDef ability, Combatant? target) {
    if (outcome != null || !actor.alive) return 'The battle is over.';
    if (!identical(actor, currentActor)) return 'Not this monster\'s turn.';
    final cost = scriptedApCost ?? abilityApCost(ability);
    scriptedApCost = null; // one shot, whether or not it was actually set
    if (actor.ap < cost) return 'Not enough AP ($cost needed).';
    final targets = _resolveTargets(actor, ability, target);
    if (targets.isEmpty) return 'No valid target.';

    actor.ap -= cost;
    _countAction(actor, ability);
    _turnPriority = math.max(_turnPriority, ability.priority);
    lastEvents.clear();
    actionSeq++;

    // Self-penalty (Power Surge/Gaia's Wrath): always applies on use, hit or miss.
    if (ability.selfPenaltyStat != null) {
      actor.applySelfPenalty(
        SelfPenalty(
          stat: ability.selfPenaltyStat!,
          mult: ability.selfPenaltyMult,
          turns: ability.selfPenaltyTurns,
        ),
      );
    }

    final parts = <String>[];
    switch (ability.kind) {
      case AbilityKind.buff:
        if (ability.selfBuff != null) {
          // The MOVE's own duration and magnitude (user 2026-07-30); 0 passes
          // through as the catalog default, so an untouched ability is unchanged.
          actor.applySelfBuff(
            ability.selfBuff!,
            turns: ability.selfBuffTurns,
            value: ability.selfBuffValue,
          );
          parts.add('${ability.selfBuff!.emoji} ${ability.selfBuff!.label}');
        }
        if (ability.regenValue > 0) {
          actor.applyRegen(
            // The kind's own default, not a literal: a 0 in the row means "the
            // standard length", and that length lives in ONE place.
            turns: ability.regenTurns > 0
                ? ability.regenTurns
                : AbilityEffectKind.regen.defaultTurns,
            value: ability.regenValue,
          );
          parts.add('🌱 regenerating');
        }
        // One event for the whole buff action, win or no self-buff/regen was
        // even rolled into it — the UI's white-lines-rising cue reads off
        // this (see battle_screen's _consumeCombatEvents), and a buff that
        // adds no number to the log still needs SOMETHING to animate against.
        lastEvents.add(CombatEvent(target: actor, actor: actor, buff: true));
      case AbilityKind.heal:
        // REGEN (user 2026-07-30, Pokémon's Wish): a heal move may leave a trickle
        // behind as well as topping the target up right now.
        if (ability.regenValue > 0) {
          actor.applyRegen(
            // The kind's own default, not a literal: a 0 in the row means "the
            // standard length", and that length lives in ONE place.
            turns: ability.regenTurns > 0
                ? ability.regenTurns
                : AbilityEffectKind.regen.defaultTurns,
            value: ability.regenValue,
          );
          parts.add('🌱 regenerating');
        }
        for (final t in targets) {
          final amount = (t.maxHp * ability.healPct).round();
          final before = t.hp;
          t.hp = math.min(t.maxHp, t.hp + amount);
          lastEvents.add(
            CombatEvent(
              target: t,
              actor: actor,
              amount: t.hp - before,
              heal: true,
            ),
          );
          parts.add('${t.name} +${t.hp - before} HP');
        }
      case AbilityKind.damage:
        for (final t in targets) {
          _resolveOneHit(actor, ability, t, parts, allowScripted: true);
          // Extra hits (user 2026-09-08: "nicht nur 1 gegner treffen sondern
          // 2 oder 3... mit jedem Treffer sinkt die Chance, noch einen
          // Treffer zu landen") — only meaningful for the classic single-
          // enemy case; allEnemies/allAllies already hit everyone. Capped at
          // 3 total hits: each extra swing needs an independent
          // extraHitChance roll, so the odds of reaching a 3rd hit are that
          // chance SQUARED, always lower than reaching a 2nd.
          if (ability.target == AbilityTarget.enemy &&
              ability.extraHitChance > 0) {
            final alreadyHit = {t};
            var current = t;
            for (var extra = 0; extra < 2; extra++) {
              if (rng.nextDouble() >= ability.extraHitChance) break;
              if (ability.extraHitSameTarget) {
                if (!current.alive) break; // nothing left to hit again
              } else {
                final next = opponentsOf(
                  actor,
                ).where((e) => e.alive && !alreadyHit.contains(e)).toList();
                if (next.isEmpty) break; // cleave: no fresh enemy left
                current = next[rng.nextInt(next.length)];
                alreadyHit.add(current);
              }
              _resolveOneHit(actor, ability, current, parts);
            }
          }
        }
    }
    lastAction = '${actor.name}: ${ability.name} — ${parts.join(', ')}';
    _afterAction(actor);
    return null;
  }

  /// ONE swing of a damage ability at [t]: the accuracy roll, the damage
  /// roll, lifesteal, recoil, and a main-status/debuff roll — everything a
  /// single hit does. Extracted (user 2026-09-08) so a multi-hit/cleave move
  /// can call this more than once per `useAbility` — see the extra-hit loop
  /// in the `AbilityKind.damage` case above, the only other caller.
  ///
  /// [allowScripted] lets the deterministic test hook ([scriptedNextHit])
  /// apply — only the FIRST hit of a sequence passes true, since a test that
  /// scripts "this hit" means one specific swing, not an entire multi-hit
  /// run; every extra hit after it always uses real [rng].
  void _resolveOneHit(
    Combatant actor,
    AbilityDef ability,
    Combatant t,
    List<String> parts, {
    bool allowScripted = false,
  }) {
    final scripted = allowScripted ? scriptedNextHit : null;
    if (scripted != null) {
      scriptedNextHit = null; // one shot
      if (scripted.miss) {
        lastEvents.add(CombatEvent(target: t, actor: actor, miss: true));
        parts.add('misses ${t.name}');
      } else {
        final dmg = scripted.damage;
        t.hp = math.max(t.cannotBeKoed ? 1 : 0, t.hp - dmg);
        lastEvents.add(
          CombatEvent(
            target: t,
            actor: actor,
            amount: dmg,
            element: ability.element,
          ),
        );
        parts.add('$dmg damage to ${t.name}${t.alive ? '' : ' (K.O.)'}');
      }
      return;
    }
    if (!_rollAccuracy(actor)) {
      lastEvents.add(CombatEvent(target: t, actor: actor, miss: true));
      parts.add('misses ${t.name}');
      return;
    }
    final roll = _rollDamage(
      actor: actor,
      target: t,
      power: ability.power,
      element: ability.element,
    );
    final dmg = roll.dmg;
    t.hp = math.max(t.cannotBeKoed ? 1 : 0, t.hp - dmg);
    lastEvents.add(
      CombatEvent(
        target: t,
        actor: actor,
        amount: dmg,
        crit: roll.crit,
        typeMult: roll.typeMult,
        element: ability.element,
      ),
    );
    parts.add('$dmg damage to ${t.name}${t.alive ? '' : ' (K.O.)'}');

    if (ability.lifestealPct > 0) {
      final before = actor.hp;
      actor.hp = math.min(
        actor.maxHp,
        actor.hp + (dmg * ability.lifestealPct).round(),
      );
      if (actor.hp > before) {
        lastEvents.add(
          CombatEvent(
            target: actor,
            actor: actor,
            amount: actor.hp - before,
            heal: true,
          ),
        );
        parts.add('${actor.name} drains ${actor.hp - before} HP');
      }
    }
    // RECOIL (user 2026-07-30, Double-Edge): a share of what it just dealt,
    // taken by the user. After lifesteal, so a move carrying both nets out
    // in the order the log reads — and it CAN knock the user out, which is
    // what makes it a cost.
    if (ability.recoilValue > 0) {
      final back = (dmg * ability.recoilValue).round();
      if (back > 0) {
        actor.hp = math.max(actor.cannotBeKoed ? 1 : 0, actor.hp - back);
        lastEvents.add(CombatEvent(target: actor, actor: actor, amount: back));
        parts.add('${actor.name} takes $back recoil');
      }
    }
    if (t.alive) {
      if (ability.inflictMain != null &&
          t.mainStatus == null &&
          rng.nextDouble() < ability.inflictMainChance) {
        t.applyMainStatus(
          ability.inflictMain!,
          turns: ability.inflictMainTurns,
          value: ability.inflictMainValue,
        );
        parts.add(
          '${t.name} ${ability.inflictMain!.emoji} ${ability.inflictMain!.label}',
        );
      }
      if (ability.inflictDebuff != null &&
          rng.nextDouble() < ability.inflictDebuffChance) {
        t.applySecondaryDebuff(
          ability.inflictDebuff!,
          turns: ability.inflictDebuffTurns,
          value: ability.inflictDebuffValue,
        );
        parts.add(
          '${t.name} ${ability.inflictDebuff!.emoji} ${ability.inflictDebuff!.label}',
        );
        // Rides alongside the damage event just added above, rather
        // than replacing it — the hit still flashes/shakes AND the
        // red-lines-falling cue plays over the same target (see
        // battle_screen's _consumeCombatEvents).
        lastEvents.add(CombatEvent(target: t, actor: actor, debuff: true));
      }
    }
  }

  /// Called after every AP-spending action. Resolves faints, then either ends
  /// [actor]'s turn (nothing affordable left, or it fell itself) or lets it
  /// keep going.
  ///
  /// [actor] is passed IN rather than read back off `currentActor`: with a
  /// crowded field the action may have killed the actor itself (status DoT, a
  /// reprisal), and `currentActor` would then already point at whoever is next
  /// — ending that monster's turn instead of this one's.
  void _afterAction(Combatant actor) {
    _resolveFaints();
    if (outcome != null) {
      notifyListeners();
      return;
    }
    if (!actor.alive) {
      // Its own turn died with it. Nothing to tick or reschedule — it is off
      // the field; just move the queue on.
      _pendingAdvance = true;
      _advanceIfPending();
      notifyListeners();
      return;
    }
    // An empty player (or, in PvP, enemy) slot pauses everything until a
    // reserve fills it — even mid-turn, so the field is never drawn a
    // monster short.
    if (needsPlayerSwitch || needsEnemySwitch) {
      notifyListeners();
      return;
    }
    if (actor.ap < _minActionCost()) {
      _finishActorTurn(actor, priority: _turnPriority);
    } else {
      notifyListeners();
    }
  }

  /// Ends the acting monster's turn voluntarily (the "End turn" button) —
  /// banks the leftover AP and advances the CTB queue.
  void endTurn() {
    if (outcome != null || needsPlayerSwitch || !isPlayerTurn) return;
    _endTurn();
  }

  /// Same tail as [endTurn], but without its `!isPlayerTurn` refusal — for
  /// scripted content that ends the ENEMY's own turn directly (user
  /// 2026-09-03's authored debuff beat: it applies a status effect outside
  /// the normal attack/ability pipeline, so nothing else advances the CTB
  /// queue for it). [endTurn] stays player-only on purpose everywhere
  /// else; this is the one legitimate reason to bypass that.
  void forceEndTurn() {
    if (outcome != null || needsPlayerSwitch || needsEnemySwitch) return;
    _endTurn();
  }

  /// The shared tail of every turn that ends WITHOUT spending it on an
  /// action — the player's own "End Turn" button and both AI cases below
  /// (banking, out of AP) all funnel through here, so the "AP recharging"
  /// visual is one thing to get right rather than three copies that could
  /// drift (user 2026-08-29, after confirming the AI's silent bank should
  /// look the same as the player's own End Turn: "Das ist immer so, wenn End
  /// Turn gedrückt wird").
  void _endTurn() {
    final actor = currentActor;
    lastEvents.clear();
    lastEvents.add(CombatEvent(target: actor, actor: actor, charging: true));
    actionSeq++;
    lastAction = '${actor.name} builds AP…';
    _finishActorTurn(actor, priority: _turnPriority);
  }

  /// True while a turn has ended but the next actor has not been chosen,
  /// because the player still owes us a reserve. The forced switch consumes it,
  /// which is what makes the fight resume exactly where the faint stopped it.
  bool _pendingAdvance = false;

  void _advanceIfPending() {
    if (!_pendingAdvance) return;
    if (outcome != null) {
      _pendingAdvance = false;
      return;
    }
    if (needsPlayerSwitch || needsEnemySwitch) {
      return; // still owed — hold the queue
    }
    _pendingAdvance = false;
    _acting = _activeAlive.isEmpty ? null : _lowestNextTurn();
    _advanceToActionableActor();
    if (outcome == null && !needsPlayerSwitch && !needsEnemySwitch) {
      _beginTurn();
    }
  }

  void flee() {
    if (outcome != null) return;
    outcome = CombatOutcome.fled;
    lastEvents.clear();
    lastAction = 'Fled!';
    notifyListeners();
  }

  // ── Shared AI (enemies + player auto-battle) ─────────────

  /// Fills an owed player slot with the first reserve, the way the enemy side
  /// fills its own. For callers with nobody to ask: the Monte-Carlo harness and
  /// the auto-battle toggle.
  ///
  /// This exists because [performAutoAction] REFUSES to act while a slot is
  /// owed — the pick is the player's. A headless loop that never answered it
  /// simply span until its guard ran out and scored the fight as a loss, which
  /// is exactly what the balance probe was reporting for the bigger parties.
  bool autoSwitchIn() {
    if (outcome != null || !needsPlayerSwitch) return false;
    final bench = benchedPlayers;
    if (bench.isEmpty) return false;
    return switchActivePlayer(players.indexOf(bench.first)) == null;
  }

  void performAutoAction() {
    if (outcome != null || needsPlayerSwitch || needsEnemySwitch) return;
    final actor = currentActor;
    // With up to three opponents standing there is a CHOICE now — see
    // [_pickAiTarget]. The ally to look after is the one bleeding worst, which
    // may well be somebody other than the actor.
    final opponents = opponentsOf(actor);
    if (opponents.isEmpty) return;
    final target = _pickAiTarget(actor, opponents);
    final allies = _fieldOf(actor);
    final ally = allies.isEmpty
        ? actor
        : allies.reduce((a, b) => a.hp / a.maxHp <= b.hp / b.maxHp ? a : b);

    // 1. Emergency heal for whoever on the field is worst off, below 45%.
    final heal = _affordableHeal(actor);
    if (heal != null && ally.hp / ally.maxHp < 0.45) {
      useAbility(actor, heal, ally);
      return;
    }

    // 2. Set up with a buff/debuff EARLY in the turn — but only when there's
    // still AP left afterwards to attack (buffs are cheap, so this leans into
    // the "buff then hit" play the cheap cost is meant to encourage, and shows
    // the player buffs/debuffs are worth using). Skip if the effect is already
    // in place, so the AI doesn't waste AP re-buffing.
    final setup = _pickSetupAbility(actor, target);
    if (setup != null &&
        actor.ap >= abilityApCost(setup) + kBasicAttackApCost) {
      useAbility(actor, setup, setup.kind == AbilityKind.buff ? actor : target);
      return;
    }

    // 3. Best damage ability vs. the lone opponent (STAB + element multiplier
    //    included in the ranking) — scored twice: the best AFFORDABLE one, and
    //    the best REGARDLESS of AP, which drives the banking decision below.
    AbilityDef? best;
    double bestScore = 0;
    AbilityDef? bestAny;
    double bestAnyScore = 0;
    for (final a in actor.abilities) {
      if (a.kind != AbilityKind.damage) continue;
      final stab = a.element == actor.element ? 1.5 : 1.0;
      final typeMult = target.incomingTypeMult(a.element);
      final score = a.power * stab * typeMult;
      if (score > bestAnyScore) {
        bestAnyScore = score;
        bestAny = a;
      }
      if (actor.ap < abilityApCost(a)) continue;
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }

    // 3b. BANK (AP redesign 2026-07-20: pools carry over, regen < capacity).
    // If a CLEARLY better move is unaffordable now but payable next turn by
    // saving, end the turn instead of wasting the AP on a weak hit — the play
    // the carried-AP economy exists to reward. Guards: the move must fit the
    // capacity at all, and banking must actually get us there next turn.
    if (bestAny != null && !identical(bestAny, best)) {
      final cost = abilityApCost(bestAny);
      final cap = maxActionPointsForStage(actor.stage);
      final nextTurnAp = math.min(cap, actor.ap + apRegenForStage(actor.stage));
      final beatsPlanB =
          bestAnyScore > math.max(bestScore, basicAttackPower.toDouble()) * 1.3;
      if (cost <= cap && actor.ap < cost && nextTurnAp >= cost && beatsPlanB) {
        _endTurn();
        return;
      }
    }

    // Spend AP on an ability only when it clearly beats a basic attack.
    if (best != null && bestScore > basicAttackPower * 1.2) {
      useAbility(actor, best, target);
    } else if (actor.ap >= kBasicAttackApCost) {
      basicAttack(actor, target);
    } else {
      _endTurn(); // out of AP for anything — end the turn (belt and braces)
    }
  }

  /// WHICH of the opponents to hit (user 2026-07-27 — with three on the field
  /// this is a real decision the 1v1 model never had to make).
  ///
  /// Two things decide it, in this order:
  ///
  ///  • FINISH WHAT IS NEARLY DEAD. A target the actor's best move can drop
  ///    this turn is always taken: removing a monster removes every turn it
  ///    would still have taken, which is worth more than any damage spread.
  ///  • Otherwise the best MATCH-UP: the opponent the actor's strongest move
  ///    scores highest against (STAB × type), tie-broken towards the one with
  ///    the least HP left.
  ///
  /// Deliberately not clever beyond that: the same routine drives the player's
  /// auto-battle, and an AI that outplays its own owner is not a feature.
  Combatant _pickAiTarget(Combatant actor, List<Combatant> opponents) {
    double bestMoveScore(Combatant t) {
      var score = basicAttackPower.toDouble();
      for (final a in actor.abilities) {
        if (a.kind != AbilityKind.damage) continue;
        if (actor.ap < abilityApCost(a)) continue;
        final stab = a.element == actor.element ? 1.5 : 1.0;
        final s = a.power * stab * t.incomingTypeMult(a.element);
        if (s > score) score = s;
      }
      return score;
    }

    Combatant? finisher;
    for (final t in opponents) {
      // Rough reach of the best affordable move, on the same shape the damage
      // formula uses. An estimate is enough — being wrong costs a turn, not a
      // rule.
      final atk = actor.effectiveAttack;
      final def = math.max(1.0, t.effectiveDefense);
      final reach =
          (bestMoveScore(t) / basicAttackPower) *
          atk *
          (atk / (atk + def)) *
          damageScale;
      if (reach >= t.hp && (finisher == null || t.hp < finisher.hp)) {
        finisher = t;
      }
    }
    if (finisher != null) return finisher;

    var best = opponents.first;
    var bestScore = bestMoveScore(best);
    for (final t in opponents.skip(1)) {
      final s = bestMoveScore(t);
      if (s > bestScore || (s == bestScore && t.hp < best.hp)) {
        best = t;
        bestScore = s;
      }
    }
    return best;
  }

  /// A buff/debuff-setup ability worth playing now: a self-buff not yet up, or
  /// a damage move whose status/debuff the [target] doesn't already have.
  /// Null when nothing new would land (so the AI doesn't waste AP).
  AbilityDef? _pickSetupAbility(Combatant actor, Combatant target) {
    for (final a in actor.abilities) {
      if (actor.ap < abilityApCost(a)) continue;
      if (a.kind == AbilityKind.buff && a.selfBuff != null) {
        if (!actor.selfBuffs.containsKey(a.selfBuff)) return a;
      } else if (a.kind == AbilityKind.damage) {
        final newStatus = a.inflictMain != null && target.mainStatus == null;
        final newDebuff =
            a.inflictDebuff != null &&
            !target.secondaryDebuffs.containsKey(a.inflictDebuff);
        if (newStatus || newDebuff) return a;
      }
    }
    return null;
  }

  AbilityDef? _affordableHeal(Combatant actor) {
    for (final a in actor.abilities) {
      if (a.kind == AbilityKind.heal && actor.ap >= abilityApCost(a)) {
        return a;
      }
    }
    return null;
  }

  // ── Rewards ───────────────────────────────────────────────
  /// XP granted on victory, BEFORE splitting across the team (the caller —
  /// CreaturesController.applyBattleOutcome — divides by team size).
  ///
  /// Per defeated monster: factor · Level^exponent, a boss additionally
  /// ×bossMultiplier — seeded with the balance-pass 9.0 · L^2.3 / ×6 and
  /// dev-authored since 2026-07-26 (Species-Budget → XP), because how much a
  /// kill is worth at a given level is the dial that sets the whole levelling
  /// pace against the requirement curve.
  int get totalXpReward => enemies.fold(
    0,
    (sum, e) => sum + kXpBalance.killXp(e.level, boss: e.isBoss).round(),
  );

  // ── Internals ─────────────────────────────────────────────
  List<Combatant> _resolveTargets(
    Combatant actor,
    AbilityDef ability,
    Combatant? picked,
  ) {
    // Everyone on the field counts now, which is what finally gives the SPREAD
    // targets their meaning: `allEnemies` used to resolve to the single active
    // opponent, so an AoE was a single-target move with a grander name.
    final opponents = opponentsOf(actor);
    final allies = _fieldOf(actor);
    // A picked target only counts if it is actually standing there — a stale
    // selection (it fell to an ally's strike a moment ago) falls back to the
    // first live one rather than fizzling the move.
    Combatant? valid(List<Combatant> among) =>
        picked != null && picked.alive && among.any((c) => identical(c, picked))
        ? picked
        : null;
    switch (ability.target) {
      case AbilityTarget.enemy:
        final t =
            valid(opponents) ?? (opponents.isEmpty ? null : opponents.first);
        return t == null ? const [] : [t];
      case AbilityTarget.allEnemies:
        return opponents;
      case AbilityTarget.ally:
        return [valid(allies) ?? actor];
      case AbilityTarget.allAllies:
        return allies.isEmpty ? [actor] : allies;
      case AbilityTarget.self:
        return [actor];
    }
  }

  bool _rollAccuracy(Combatant actor) =>
      deterministicCombat ||
      rng.nextDouble() < (kBaseAccuracy * actor.effectiveAccuracy);

  // Basis = (Power/40) · ATK · ATK/(ATK+DEF) · damageScale + 2
  // Schaden = max(1, floor(Basis · STAB · Typ · Crit · Random(0.85..1.0)))
  //
  // Retuned 2026-07-16 against the docs/balancing.md anchors (Monte-Carlo
  // findings §4a). The old Pokémon basis ((2·L/5+2)·Power·ATK/DEF)/50+2 had
  // two structural problems: its level factor grew ~7× from Lv5→69 while HP
  // only grows ~2.7× (fights drifted 16→7 actions), and the pure ATK/DEF
  // RATIO cancelled both sides' linear stat growth. Now ATK itself carries
  // the growth (damage tracks HP, fight length stays level-stable) and
  // ATK/(ATK+DEF) keeps DEF as % mitigation, so stat/level gaps cut both
  // ways — hit softer AND get hit harder.
  ({int dmg, bool crit, double typeMult}) _rollDamage({
    required Combatant actor,
    required Combatant target,
    required int power,
    required CreatureElement element,
  }) {
    final atk = actor.effectiveAttack;
    // defenseWeight (live dial) scales how much DEF mitigates: the term
    // atk/(atk + def·w) is the % of damage that gets through. w>1 → defense
    // matters more (softer hits), w<1 → attack dominates. w=1 is calibrated.
    final def =
        math.max(1.0, target.effectiveDefense) * CombatTuning().defenseWeight;
    final basis =
        (power / basicAttackPower) * atk * (atk / (atk + def)) * damageScale +
        2;
    // Bonus damage comes only from the move's TYPE. A NEUTRAL move (the normal
    // Attack, most buffs) has no type identity: no STAB (a creature is never
    // neutral, so element == actor.element can't hold) and multiplierVs is 1.0.
    final stab = element == actor.element ? 1.5 : 1.0;
    // EXPOSURE (user 2026-09-15): a target afflicted by a type-flavoured
    // main status (burning/frozen/petrified/…) is weak to that element TOO,
    // on top of its own — see Combatant.incomingTypeMult.
    final typeMult = target.incomingTypeMult(element);
    // Crit chance scales gently with speed (spec's alternative: a flat
    // 6.25% — this is the primary, speed-scaled formula), capped ~10%.
    // Base chance, how much speed adds, the ceiling and the multiplier are
    // all dials (Monster → Kampf).
    final critChance =
        (GameTuning.i.raw(Dials.critBase) +
                actor.effectiveSpeed / GameTuning.i.raw(Dials.critSpeedDivisor))
            .clamp(0.0, GameTuning.i.raw(Dials.critMax));
    final critMult = !deterministicCombat && rng.nextDouble() < critChance
        ? GameTuning.i.raw(Dials.critMultiplier)
        : 1.0;
    final variance = 0.85 + rng.nextDouble() * 0.15;
    final raw = (basis * stab * typeMult * critMult * variance).floor();
    // The cap is now OFF by default (user 2026-08-29: "es soll keine Grenze
    // geben" — a big enough level gap made every move land on the exact
    // same capped number regardless of its own power, which read as "power
    // does nothing" rather than as the anti-one-shot floor it actually was).
    // <= 0 means disabled — the dial's own `felt` text already promised this
    // ("—" instead of a hit count), but the maths here used to fold straight
    // into `math.max(1, ...)` without ever checking for it, so "0" quietly
    // meant "cap every hit at 1 damage" instead of "no cap at all".
    final capFraction = kMaxHitHpFraction;
    final dmg = capFraction <= 0
        ? math.max(1, raw)
        : math.max(
            1,
            math.min(raw, math.max(1, (target.maxHp * capFraction).floor())),
          );
    return (dmg: dmg, crit: critMult > 1.0, typeMult: typeMult);
  }

  void _finishActorTurn(Combatant actor, {int priority = 0}) {
    final dot = actor.tickStatusEndOfRound(_statusRng);
    if (dot > 0) {
      lastEvents.add(CombatEvent(target: actor, actor: actor, amount: dot));
      lastAction = '$lastAction · ${actor.name} takes $dot status damage';
    }
    // The mirror of the DoT line — regen ticks in the same upkeep (user
    // 2026-07-30), so it has to be as visible as the damage is.
    if (actor.lastRegenHeal > 0) {
      lastEvents.add(
        CombatEvent(
          target: actor,
          actor: actor,
          amount: actor.lastRegenHeal,
          heal: true,
        ),
      );
      lastAction =
          '$lastAction · ${actor.name} regenerates '
          '${actor.lastRegenHeal} HP';
    }
    var increment = _turnCost / actor.effectiveSpeed;
    if (priority > 0) {
      increment *= (1 - _priorityNudgeFactor * priority).clamp(0.1, 1.0);
    }
    actor.nextTurnAt += increment;
    // Handles the enemy's auto-fill and victory/defeat. An empty player slot
    // leaves needsPlayerSwitch true — the advance below holds until the UI has
    // sent a reserve in, and picks up again from _advanceIfPending.
    _resolveFaints();
    _pendingAdvance = true;
    _advanceIfPending();
    notifyListeners();
  }

  /// null in deterministic-combat mode (tests) so status decay/cure stays the
  /// exact fixed-countdown it always was — matches every other roll's own
  /// `!deterministicCombat` guard (see _rollDamage's crit, _rollAccuracy).
  math.Random? get _statusRng => deterministicCombat ? null : rng;

  // Auto-resolves any consecutive frozen/feared/confused turns (rolled at the
  // START of each such turn) so isPlayerTurn/currentActor never point at a
  // combatant who's about to be skipped/self-hit anyway — the UI/AI only
  // ever sees actionable turns.
  void _advanceToActionableActor() {
    var guard = 0;
    while (outcome == null &&
        !needsPlayerSwitch &&
        !needsEnemySwitch &&
        guard < 50) {
      guard++;
      if (_activeAlive.isEmpty) return;
      final actor = _acting ??= _lowestNextTurn();
      // CONFUSION (user 2026-09-15): the one main status that doesn't skip —
      // it makes the actor hit ITSELF instead, so it needs the real damage
      // roll rather than rollSkipTurn's plain skip.
      if (actor.mainStatus == MainStatusKind.confusion &&
          !deterministicCombat &&
          rng.nextDouble() < actor.mainStatusValue) {
        _resolveConfusionSelfHit(actor);
        continue;
      }
      if (!actor.rollSkipTurn(rng)) return;
      final status = actor.mainStatus!;
      final dot = actor.tickStatusEndOfRound(_statusRng);
      lastEvents.clear();
      actionSeq++;
      if (dot > 0) {
        lastEvents.add(CombatEvent(target: actor, actor: actor, amount: dot));
      }
      lastAction =
          '${actor.name} is afflicted by ${status.label} and skips its turn!'
          '${dot > 0 ? ' ($dot status damage)' : ''}';
      actor.nextTurnAt += _turnCost / actor.effectiveSpeed;
      // A skip-turn's DoT can KO the actor — clear the field and refill before
      // choosing who is next.
      _resolveFaints();
      _acting = _activeAlive.isEmpty ? null : _lowestNextTurn();
    }
  }

  /// A confused actor's turn: a typeless hit on itself (the classic
  /// Pokémon-confusion self-inflicted swing), consuming the turn exactly
  /// like a skip would.
  void _resolveConfusionSelfHit(Combatant actor) {
    final roll = _rollDamage(
      actor: actor,
      target: actor,
      power: basicAttackPower,
      element: CreatureElement.neutral,
    );
    actor.hp = math.max(actor.cannotBeKoed ? 1 : 0, actor.hp - roll.dmg);
    final dot = actor.tickStatusEndOfRound(_statusRng);
    lastEvents.clear();
    actionSeq++;
    lastEvents.add(CombatEvent(target: actor, actor: actor, amount: roll.dmg));
    if (dot > 0) {
      lastEvents.add(CombatEvent(target: actor, actor: actor, amount: dot));
    }
    lastAction =
        '${actor.name} is confused and hurts itself for ${roll.dmg} damage!'
        '${dot > 0 ? ' ($dot status damage)' : ''}';
    actor.nextTurnAt += _turnCost / actor.effectiveSpeed;
    _resolveFaints();
    _acting = _activeAlive.isEmpty ? null : _lowestNextTurn();
  }

  void _checkOutcome() {
    if (outcome != null) return;
    if (aliveEnemies.isEmpty) {
      outcome = CombatOutcome.victory;
      lastAction = '$lastAction\n🏆 Victory!';
    } else if (alivePlayers.isEmpty) {
      outcome = CombatOutcome.defeat;
      lastAction = '$lastAction\n💀 Defeat…';
    }
  }
}
