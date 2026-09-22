import '../../../core/tuning/game_tuning.dart';
import '../models/ability_def.dart';

// What learning a move at the Combat School costs (user 2026-09-05: "Je
// nach Powerwert, dauert das Erlernen länger"). Modeled on healing_cost.dart:
// one small function, real time, no goods — the user only asked for a time
// cost, not a resource sink, so this stays minimal rather than inventing a
// price nobody asked for.

/// How long training [ability] takes — scales with the move's own
/// [AbilityDef.totalPower] (its damage plus every effect it carries, in one
/// unit — the same number the Dev-Mode form calls "Power"), so a heavier
/// move is a longer lesson. A DIAL (Dials.trainSecondsPerPower), not a
/// hardcoded constant — tunable in Dev Mode like every other timer in the
/// game.
Duration trainingDuration(AbilityDef ability) {
  final seconds =
      ability.totalPower * GameTuning.i.raw(Dials.trainSecondsPerPower);
  return Duration(seconds: seconds.round());
}
