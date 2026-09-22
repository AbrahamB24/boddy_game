import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/services/combat_engine.dart';

import 'combat_engine_test.dart' show make;

/// The Phase 5 "determinism spike" the plan calls for BEFORE building the
/// PvP networking layer on top of the engine: two independently-constructed
/// CombatEngine instances, seeded identically, fed the exact same scripted
/// action sequence — including a VOLUNTARY switch on both the player and
/// (new, isPvp-only) enemy side — must land on byte-identical state. If this
/// ever fails, lockstep PvP (relay only the chosen actions, not full state)
/// is not viable and the async turn-based fallback in the plan should be
/// used instead.
void main() {
  test('two engines with the same seed and actions land on identical state', () {
    List<Combatant> team(String prefix, bool player) => [
      make(id: '$prefix-1', player: player, speed: 12, hp: 300, attack: 55),
      make(id: '$prefix-2', player: player, speed: 8, hp: 260, attack: 60),
      make(id: '$prefix-3', player: player, speed: 15, hp: 240, attack: 50),
      make(id: '$prefix-4', player: player, speed: 10, hp: 280, attack: 45),
    ];

    const seed = 424242;
    final engineA = CombatEngine(
      players: team('a', true),
      enemies: team('b', false),
      rng: math.Random(seed),
      isPvp: true,
    );
    final engineB = CombatEngine(
      players: team('a', true),
      enemies: team('b', false),
      rng: math.Random(seed),
      isPvp: true,
    );

    for (final c in [...engineA.players, ...engineA.enemies, ...engineB.players, ...engineB.enemies]) {
      c.ap = 10;
    }

    Combatant find(CombatEngine e, String id) =>
        [...e.players, ...e.enemies].firstWhere((c) => c.id == id);

    // A scripted sequence a real relayed match would produce: attacks from
    // whoever the engine says is up, plus one voluntary switch per side —
    // exercising the new isPvp switchActiveEnemy path, not just attacks.
    void applyScript(CombatEngine e) {
      e.basicAttack(find(e, 'a-3'), find(e, 'b-3')); // a-3 is fastest player
      if (e.isEnemyTurn) {
        e.basicAttack(find(e, 'b-3'), find(e, 'a-3'));
      }
      if (e.isPlayerTurn) {
        e.switchActivePlayer(e.players.indexOf(find(e, 'a-2')));
      }
      if (e.isEnemyTurn) {
        e.switchActiveEnemy(e.enemies.indexOf(find(e, 'b-2')));
      }
      // Drive a few more real turns through whichever side is actually up,
      // always attacking the opposing field's first member — a stand-in for
      // "relay whatever action each remote player actually chose".
      for (var i = 0; i < 6 && e.outcome == null; i++) {
        if (e.needsPlayerSwitch) {
          e.switchActivePlayer(e.players.indexOf(e.benchedPlayers.first));
          continue;
        }
        if (e.needsEnemySwitch) {
          e.switchActiveEnemy(e.enemies.indexOf(e.benchedEnemies.first));
          continue;
        }
        final actor = e.currentActor;
        final opponents = e.opponentsOf(actor);
        if (opponents.isEmpty) break;
        e.basicAttack(actor, opponents.first);
      }
    }

    applyScript(engineA);
    applyScript(engineB);

    // The two engines never talked to each other — only the SEED and the
    // SCRIPT are shared, exactly like two PvP clients relaying only chosen
    // actions. Identical resulting HP for every combatant is the whole
    // lockstep bet.
    for (final id in ['a-1', 'a-2', 'a-3', 'a-4', 'b-1', 'b-2', 'b-3', 'b-4']) {
      expect(
        find(engineA, id).hp,
        find(engineB, id).hp,
        reason: '$id diverged between the two lockstep engines',
      );
    }
    expect(engineA.outcome, engineB.outcome);
    // The PvP desync check (battle_screen.dart's _handleDesync) leans on
    // this being true for any two engines that really are in sync — this
    // is that guarantee, asserted directly.
    expect(engineA.stateHash, engineB.stateHash);

    engineA.dispose();
    engineB.dispose();
  });
}
