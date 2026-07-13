import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/ability_def.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/status_effects.dart';

enum CombatOutcome { victory, defeat, fled }

// Pure combat logic (no UI, no DB): CTB turn queue, damage/heal/status
// resolution, energy economy and a simple shared AI used both by enemies
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

  /// Free, always-available hit — inside the "Basis" move-power class
  /// (30-50) from the balance pass; costs nothing and GENERATES energy
  /// (kBasicAttackEnergyGain), the core resource loop.
  static const int basicAttackPower = 40;

  /// Base hit chance before any debuffs (Blenden multiplies this down).
  /// Not specified numerically in the balance doc — picked from its
  /// suggested "~90-95%" range.
  static const double kBaseAccuracy = 0.92;

  /// How much a Priority-flagged ability pulls the user's next turn forward
  /// in the CTB queue, as a fraction reduction of the normal turnCost/speed
  /// increment (e.g. priority 1 → 30% sooner). Approximation, not a literal
  /// discrete tier — see class doc comment.
  static const double _priorityNudgeFactor = 0.30;

  CombatOutcome? outcome;
  String lastAction = '';

  CombatEngine({required this.players, required this.enemies, math.Random? rng})
    : rng = rng ?? math.Random() {
    // Initial schedule; the tiny index epsilon makes equal-speed ties
    // deterministic (list order) instead of map-iteration luck.
    var i = 0;
    for (final c in [...players, ...enemies]) {
      c.nextTurnAt = _turnCost / c.effectiveSpeed + i * 0.001;
      i++;
    }
  }

  List<Combatant> get _all => [...players, ...enemies];
  List<Combatant> get alivePlayers =>
      players.where((c) => c.alive).toList(growable: false);
  List<Combatant> get aliveEnemies =>
      enemies.where((c) => c.alive).toList(growable: false);

  Combatant get currentActor => _all
      .where((c) => c.alive)
      .reduce((a, b) => a.nextTurnAt <= b.nextTurnAt ? a : b);

  bool get isPlayerTurn => outcome == null && currentActor.isPlayerSide;

  /// Upcoming turn order for the visible initiative bar. Approximation: uses
  /// each combatant's CURRENT effective speed for the whole horizon (a status
  /// expiring mid-forecast isn't simulated — close enough for a preview and
  /// exactly what the current-speed math guarantees).
  List<Combatant> forecast(int count) {
    final sim = [
      for (final c in _all.where((c) => c.alive))
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

  // ── Actions ───────────────────────────────────────────────
  void basicAttack(Combatant actor, Combatant target) {
    if (outcome != null || !actor.alive || !target.alive) return;
    String msg;
    if (!_rollAccuracy(actor)) {
      msg = '${actor.name} attacks ${target.name} — miss!';
    } else {
      final dmg = _rollDamage(
        actor: actor,
        target: target,
        power: basicAttackPower,
        element: null,
      );
      target.hp = math.max(0, target.hp - dmg);
      msg =
          '${actor.name} attacks ${target.name}: $dmg damage'
          '${target.alive ? '' : ' — K.O.!'}';
    }
    actor.energy = math.min(
      actor.maxEnergy,
      actor.energy + kBasicAttackEnergyGain,
    );
    lastAction = msg;
    _finishActorTurn(actor);
  }

  /// Returns a user-facing error (not enough energy / invalid target) or
  /// null when the ability resolved.
  String? useAbility(Combatant actor, AbilityDef ability, Combatant? target) {
    if (outcome != null || !actor.alive) return 'The battle is over.';
    if (actor.energy < ability.energyCost) {
      return 'Not enough energy (${ability.energyCost} ⚡ needed).';
    }
    final targets = _resolveTargets(actor, ability, target);
    if (targets.isEmpty) return 'No valid target.';

    actor.energy -= ability.energyCost;

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
          actor.applySelfBuff(ability.selfBuff!);
          parts.add('${ability.selfBuff!.emoji} ${ability.selfBuff!.label}');
        }
      case AbilityKind.heal:
        for (final t in targets) {
          final amount = (t.maxHp * ability.healPct).round();
          final before = t.hp;
          t.hp = math.min(t.maxHp, t.hp + amount);
          parts.add('${t.name} +${t.hp - before} HP');
        }
      case AbilityKind.damage:
        for (final t in targets) {
          if (!_rollAccuracy(actor)) {
            parts.add('misses ${t.name}');
            continue;
          }
          final dmg = _rollDamage(
            actor: actor,
            target: t,
            power: ability.power,
            element: ability.element,
          );
          t.hp = math.max(0, t.hp - dmg);
          parts.add('$dmg damage to ${t.name}${t.alive ? '' : ' (K.O.)'}');

          if (ability.lifestealPct > 0) {
            final before = actor.hp;
            actor.hp = math.min(
              actor.maxHp,
              actor.hp + (dmg * ability.lifestealPct).round(),
            );
            if (actor.hp > before) {
              parts.add('${actor.name} drains ${actor.hp - before} HP');
            }
          }
          if (t.alive) {
            if (ability.inflictMain != null &&
                t.mainStatus == null &&
                rng.nextDouble() < ability.inflictMainChance) {
              t.applyMainStatus(ability.inflictMain!);
              parts.add(
                '${t.name} ${ability.inflictMain!.emoji} ${ability.inflictMain!.label}',
              );
            }
            if (ability.inflictDebuff != null &&
                rng.nextDouble() < ability.inflictDebuffChance) {
              t.applySecondaryDebuff(ability.inflictDebuff!);
              parts.add(
                '${t.name} ${ability.inflictDebuff!.emoji} ${ability.inflictDebuff!.label}',
              );
            }
          }
        }
    }
    lastAction = '${actor.name}: ${ability.name} — ${parts.join(', ')}';
    _finishActorTurn(actor, priority: ability.priority);
    return null;
  }

  void flee() {
    if (outcome != null) return;
    outcome = CombatOutcome.fled;
    lastAction = 'Fled!';
    notifyListeners();
  }

  // ── Shared AI (enemies + player auto-battle) ─────────────
  void performAutoAction() {
    if (outcome != null) return;
    final actor = currentActor;
    final allies = actor.isPlayerSide ? alivePlayers : aliveEnemies;
    final opponents = actor.isPlayerSide ? aliveEnemies : alivePlayers;
    if (opponents.isEmpty) return;

    // 1. Emergency heal: an ally below 45% and an affordable heal.
    final heal = _affordableHeal(actor);
    if (heal != null) {
      final hurt = allies.where((a) => a.hp / a.maxHp < 0.45).toList()
        ..sort((a, b) => (a.hp / a.maxHp).compareTo(b.hp / b.maxHp));
      if (hurt.isNotEmpty) {
        useAbility(actor, heal, hurt.first);
        return;
      }
    }

    // 2. Best affordable damage ability vs. the squishiest opponent
    //    (STAB + element multiplier included in the ranking).
    final target = opponents.reduce((a, b) => a.hp <= b.hp ? a : b);
    AbilityDef? best;
    double bestScore = 0;
    for (final a in actor.abilities) {
      if (a.kind != AbilityKind.damage) continue;
      if (actor.energy < a.energyCost) continue;
      final stab = (a.element != null && a.element == actor.element)
          ? 1.5
          : 1.0;
      final typeMult = a.element?.multiplierVs(target.element) ?? 1.0;
      final score = a.power * stab * typeMult;
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    // Only burn energy when it clearly beats the (free, energy-generating)
    // basic attack.
    if (best != null && bestScore > basicAttackPower * 1.2) {
      useAbility(actor, best, target);
    } else {
      basicAttack(actor, target);
    }
  }

  AbilityDef? _affordableHeal(Combatant actor) {
    for (final a in actor.abilities) {
      if (a.kind == AbilityKind.heal && actor.energy >= a.energyCost) {
        return a;
      }
    }
    return null;
  }

  // ── Rewards ───────────────────────────────────────────────
  /// XP granted on victory, BEFORE splitting across the team (the caller —
  /// CreaturesController.applyBattleOutcome — divides by team size).
  /// EP_pro_Kill = round(9.0 · Level^2.3); a boss additionally ×6.
  int get totalXpReward => enemies.fold(0, (sum, e) {
    final killXp = (9.0 * math.pow(e.level, 2.3)).round();
    return sum + (e.isBoss ? killXp * 6 : killXp);
  });

  // ── Internals ─────────────────────────────────────────────
  List<Combatant> _resolveTargets(
    Combatant actor,
    AbilityDef ability,
    Combatant? picked,
  ) {
    final allies = actor.isPlayerSide ? alivePlayers : aliveEnemies;
    final opponents = actor.isPlayerSide ? aliveEnemies : alivePlayers;
    switch (ability.target) {
      case AbilityTarget.enemy:
        return picked != null && picked.alive && opponents.contains(picked)
            ? [picked]
            : opponents.isEmpty
            ? const []
            : [opponents.first];
      case AbilityTarget.allEnemies:
        return opponents;
      case AbilityTarget.ally:
        return picked != null && picked.alive && allies.contains(picked)
            ? [picked]
            : [actor];
      case AbilityTarget.allAllies:
        return allies;
      case AbilityTarget.self:
        return [actor];
    }
  }

  bool _rollAccuracy(Combatant actor) =>
      rng.nextDouble() < (kBaseAccuracy * actor.effectiveAccuracy);

  // Basis = ((2·Level/5 + 2) · Power · ATK/DEF) / 50 + 2
  // Schaden = max(1, floor(Basis · STAB · Typ · Crit · Random(0.85..1.0)))
  int _rollDamage({
    required Combatant actor,
    required Combatant target,
    required int power,
    required CreatureElement? element,
  }) {
    final atk = actor.effectiveAttack;
    final def = math.max(1.0, target.effectiveDefense);
    final basis = ((2 * actor.level / 5 + 2) * power * atk / def) / 50 + 2;
    final stab = (element != null && element == actor.element) ? 1.5 : 1.0;
    final typeMult = element?.multiplierVs(target.element) ?? 1.0;
    // Crit chance scales gently with speed (spec's alternative: a flat
    // 6.25% — this is the primary, speed-scaled formula), capped ~10%.
    final critChance = (0.0625 + actor.effectiveSpeed / 5000).clamp(0.0, 0.10);
    final critMult = rng.nextDouble() < critChance ? 1.5 : 1.0;
    final variance = 0.85 + rng.nextDouble() * 0.15;
    return math.max(1, (basis * stab * typeMult * critMult * variance).floor());
  }

  void _finishActorTurn(Combatant actor, {int priority = 0}) {
    final dot = actor.tickStatusEndOfRound();
    if (dot > 0) {
      lastAction = '$lastAction · ${actor.name} takes $dot status damage';
    }
    var increment = _turnCost / actor.effectiveSpeed;
    if (priority > 0) {
      increment *= (1 - _priorityNudgeFactor * priority).clamp(0.1, 1.0);
    }
    actor.nextTurnAt += increment;
    _checkOutcome();
    if (outcome == null) _advanceToActionableActor();
    notifyListeners();
  }

  // Auto-resolves any consecutive frozen/feared skip turns (rolled at the
  // START of each such turn) so isPlayerTurn/currentActor never point at a
  // combatant who's about to be skipped anyway — the UI/AI only ever sees
  // actionable turns.
  void _advanceToActionableActor() {
    var guard = 0;
    while (outcome == null && guard < 50) {
      guard++;
      final actor = currentActor;
      if (!actor.rollSkipTurn(rng)) return;
      final status = actor.mainStatus!;
      final dot = actor.tickStatusEndOfRound();
      lastAction =
          '${actor.name} is afflicted by ${status.label} and skips its turn!'
          '${dot > 0 ? ' ($dot status damage)' : ''}';
      actor.nextTurnAt += _turnCost / actor.effectiveSpeed;
      _checkOutcome();
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
