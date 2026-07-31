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

  const CombatEvent({
    required this.target,
    this.amount = 0,
    this.heal = false,
    this.crit = false,
    this.miss = false,
    this.typeMult = 1.0,
    this.element = CreatureElement.neutral,
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
  static const int basicAttackPower = 40;

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

  /// Visible effects of the most recent action (damage/heal numbers), read by
  /// the battle screen for floating combat text. Cleared at the start of every
  /// player/AI action so a later turn-end notify never re-floats stale numbers.
  final List<CombatEvent> lastEvents = [];

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
        playerAbilityUses[ability.id] = (playerAbilityUses[ability.id] ?? 0) + 1;
      }
    } else {
      enemyActionsTaken++;
      if (ability != null) {
        enemyAbilityUses[ability.id] = (enemyAbilityUses[ability.id] ?? 0) + 1;
      }
    }
  }

  CombatEngine({required this.players, required this.enemies, math.Random? rng})
    : rng = rng ?? math.Random() {
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

  /// Seeds the opening AP pools (user 2026-07-20): whoever acts FIRST opens on
  /// [kStartApFirst], everyone else on [kStartApSecond]. Deliberately NOT a
  /// regen — turn one is the lean one, and a reserve coming in later arrives on
  /// whatever this left it with.
  void _seedOpeningAp() {
    final first = _acting;
    for (final c in [...players, ...enemies]) {
      c.ap = identical(c, first) ? kStartApFirst : kStartApSecond;
    }
    // The first actor is already standing in its opening turn — mark it so its
    // NEXT turn is the one that regenerates.
    if (first != null) _opened.add(first);
    _turnPriority = 0;
  }

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
  void _fillField(List<Combatant> side, List<Combatant?> field,
      {bool schedule = true}) {
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
  List<Combatant> get fieldPlayers =>
      [for (final c in playerField) if (c != null && c.alive) c];
  List<Combatant> get fieldEnemies =>
      [for (final c in enemyField) if (c != null && c.alive) c];

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
    if (currentActor.isPlayerSide && benchedPlayers.isNotEmpty) {
      min = math.min(min, kSwitchApCost);
    }
    return min;
  }

  /// True while the acting side still has AP to do something — the UI keeps
  /// the action panel open until this is false (then auto-ends).
  bool get canActThisTurn => outcome == null &&
      !needsPlayerSwitch &&
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

  Combatant _lowestNextTurn() => _activeAlive
      .reduce((a, b) => a.nextTurnAt <= b.nextTurnAt ? a : b);

  bool get isPlayerTurn =>
      outcome == null && !needsPlayerSwitch && currentActor.isPlayerSide;

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
    final now = _acting?.nextTurnAt ??
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
    lastAction = '🔄 ${target.name} steps up!';
    _afterAction(target);
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
      if (playerField[i] != null && !playerField[i]!.alive) playerField[i] = null;
      if (enemyField[i] != null && !enemyField[i]!.alive) enemyField[i] = null;
    }
    _fillField(enemies, enemyField);
    _checkOutcome();
  }

  // ── Actions ───────────────────────────────────────────────
  /// AP an ability costs. The author can now set it explicitly in Dev Mode
  /// (AbilityDef.apCost); otherwise it is derived from the move's strength.
  /// This just delegates to [AbilityDef.resolvedApCost] — the one source of
  /// truth (the value the abilities are already capped to per unlock stage in
  /// Combatant._resolveAbilities).
  static int abilityApCost(AbilityDef ability) => ability.resolvedApCost;

  void basicAttack(Combatant actor, Combatant target) {
    if (outcome != null || !actor.alive || !target.alive) return;
    if (!identical(actor, currentActor) || actor.ap < kBasicAttackApCost) {
      return;
    }
    actor.ap -= kBasicAttackApCost;
    _countAction(actor);
    lastEvents.clear();
    String msg;
    if (!_rollAccuracy(actor)) {
      lastEvents.add(CombatEvent(target: target, miss: true));
      msg = '${actor.name} attacks ${target.name} — miss!';
    } else {
      final roll = _rollDamage(
        actor: actor,
        target: target,
        power: basicAttackPower,
        // The normal Attack is NEUTRAL — it never lands bonus damage.
        element: CreatureElement.neutral,
      );
      target.hp = math.max(target.cannotBeKoed ? 1 : 0, target.hp - roll.dmg);
      lastEvents.add(CombatEvent(
        target: target,
        amount: roll.dmg,
        crit: roll.crit,
        typeMult: roll.typeMult,
      ));
      msg =
          '${actor.name} attacks ${target.name}: ${roll.dmg} damage'
          '${target.alive ? '' : ' — K.O.!'}';
    }
    lastAction = msg;
    _afterAction(actor);
  }

  /// Returns a user-facing error (not enough AP / invalid target) or null when
  /// the ability resolved.
  String? useAbility(Combatant actor, AbilityDef ability, Combatant? target) {
    if (outcome != null || !actor.alive) return 'The battle is over.';
    if (!identical(actor, currentActor)) return 'Not this monster\'s turn.';
    final cost = abilityApCost(ability);
    if (actor.ap < cost) return 'Not enough AP ($cost needed).';
    final targets = _resolveTargets(actor, ability, target);
    if (targets.isEmpty) return 'No valid target.';

    actor.ap -= cost;
    _countAction(actor, ability);
    _turnPriority = math.max(_turnPriority, ability.priority);
    lastEvents.clear();

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
            CombatEvent(target: t, amount: t.hp - before, heal: true),
          );
          parts.add('${t.name} +${t.hp - before} HP');
        }
      case AbilityKind.damage:
        for (final t in targets) {
          if (!_rollAccuracy(actor)) {
            lastEvents.add(CombatEvent(target: t, miss: true));
            parts.add('misses ${t.name}');
            continue;
          }
          final roll = _rollDamage(
            actor: actor,
            target: t,
            power: ability.power,
            element: ability.element,
          );
          final dmg = roll.dmg;
          t.hp = math.max(t.cannotBeKoed ? 1 : 0, t.hp - dmg);
          lastEvents.add(CombatEvent(
            target: t,
            amount: dmg,
            crit: roll.crit,
            typeMult: roll.typeMult,
            element: ability.element,
          ));
          parts.add('$dmg damage to ${t.name}${t.alive ? '' : ' (K.O.)'}');

          if (ability.lifestealPct > 0) {
            final before = actor.hp;
            actor.hp = math.min(
              actor.maxHp,
              actor.hp + (dmg * ability.lifestealPct).round(),
            );
            if (actor.hp > before) {
              lastEvents.add(CombatEvent(
                target: actor,
                amount: actor.hp - before,
                heal: true,
              ));
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
              actor.hp = math.max(
                actor.cannotBeKoed ? 1 : 0,
                actor.hp - back,
              );
              lastEvents.add(CombatEvent(target: actor, amount: back));
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
            }
          }
        }
    }
    lastAction = '${actor.name}: ${ability.name} — ${parts.join(', ')}';
    _afterAction(actor);
    return null;
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
    // An empty player slot pauses everything until a reserve fills it — even
    // mid-turn, so the field is never drawn a monster short.
    if (needsPlayerSwitch) {
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
    lastEvents.clear();
    _endTurn();
  }

  void _endTurn() {
    _finishActorTurn(currentActor, priority: _turnPriority);
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
    if (needsPlayerSwitch) return; // still owed — hold the queue
    _pendingAdvance = false;
    _acting = _activeAlive.isEmpty ? null : _lowestNextTurn();
    _advanceToActionableActor();
    if (outcome == null && !needsPlayerSwitch) _beginTurn();
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
    if (outcome != null || needsPlayerSwitch) return;
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
      final typeMult = a.element.multiplierVs(target.element);
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
      final beatsPlanB = bestAnyScore >
          math.max(bestScore, basicAttackPower.toDouble()) * 1.3;
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
        final s = a.power * stab * a.element.multiplierVs(t.element);
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
          (bestMoveScore(t) / basicAttackPower) * atk * (atk / (atk + def)) *
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
        final newStatus =
            a.inflictMain != null && target.mainStatus == null;
        final newDebuff = a.inflictDebuff != null &&
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
        final t = valid(opponents) ?? (opponents.isEmpty ? null : opponents.first);
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
    final typeMult = element.multiplierVs(target.element);
    // Crit chance scales gently with speed (spec's alternative: a flat
    // 6.25% — this is the primary, speed-scaled formula), capped ~10%.
    // Base chance, how much speed adds, the ceiling and the multiplier are
    // all dials (Monster → Kampf).
    final critChance = (GameTuning.i.raw(Dials.critBase) +
            actor.effectiveSpeed / GameTuning.i.raw(Dials.critSpeedDivisor))
        .clamp(0.0, GameTuning.i.raw(Dials.critMax));
    final critMult = rng.nextDouble() < critChance
        ? GameTuning.i.raw(Dials.critMultiplier)
        : 1.0;
    final variance = 0.85 + rng.nextDouble() * 0.15;
    final raw = (basis * stab * typeMult * critMult * variance).floor();
    // Hard cap: never more than kMaxHitHpFraction of the target's max HP in
    // one hit, so a full-HP combatant can never be one-shot (see the const).
    final cap = math.max(1, (target.maxHp * kMaxHitHpFraction).floor());
    return (
      dmg: math.max(1, math.min(raw, cap)),
      crit: critMult > 1.0,
      typeMult: typeMult,
    );
  }

  void _finishActorTurn(Combatant actor, {int priority = 0}) {
    final dot = actor.tickStatusEndOfRound();
    if (dot > 0) {
      lastEvents.add(CombatEvent(target: actor, amount: dot));
      lastAction = '$lastAction · ${actor.name} takes $dot status damage';
    }
    // The mirror of the DoT line — regen ticks in the same upkeep (user
    // 2026-07-30), so it has to be as visible as the damage is.
    if (actor.lastRegenHeal > 0) {
      lastEvents.add(
        CombatEvent(target: actor, amount: actor.lastRegenHeal, heal: true),
      );
      lastAction = '$lastAction · ${actor.name} regenerates '
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

  // Auto-resolves any consecutive frozen/feared skip turns (rolled at the
  // START of each such turn) so isPlayerTurn/currentActor never point at a
  // combatant who's about to be skipped anyway — the UI/AI only ever sees
  // actionable turns.
  void _advanceToActionableActor() {
    var guard = 0;
    while (outcome == null && !needsPlayerSwitch && guard < 50) {
      guard++;
      if (_activeAlive.isEmpty) return;
      final actor = _acting ??= _lowestNextTurn();
      if (!actor.rollSkipTurn(rng)) return;
      final status = actor.mainStatus!;
      final dot = actor.tickStatusEndOfRound();
      lastEvents.clear();
      if (dot > 0) lastEvents.add(CombatEvent(target: actor, amount: dot));
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
