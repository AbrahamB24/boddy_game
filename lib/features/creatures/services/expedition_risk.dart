import 'dart:math' as math;

import '../../../core/tuning/game_tuning.dart';

import '../models/creature_enums.dart';
import '../models/creature_instance.dart';

// Pure risk math for timed expeditions (gather + capture). Dangerous areas can
// wound or knock out expedition members and cost some of the haul; a stronger
// or larger group lowers that risk — so the danger rating feeds back into the
// group-composition decision (see [[expedition-overworld-redesign]]). Battle
// expeditions have their own combat risk and don't use this.
//
// The peril curve is deterministic and unit-tested; the actual casualties roll
// through an injected Random so a seeded test is reproducible.

/// Threat contributed per danger level ABOVE 1 — danger 1 areas are risk-free
/// (the confirmed "safest place" for a first expedition).
double get kThreatPerDanger => GameTuning.i.raw(Dials.threatPerDanger);

/// A member's combat capability toward surviving an expedition.
double memberCombatPower(CreatureInstance c) =>
    (c.statValue(CreatureStat.attack) + c.statValue(CreatureStat.defense))
        .toDouble();

double groupCombatPower(List<CreatureInstance> members) =>
    members.fold(0.0, (sum, c) => sum + memberCombatPower(c));

/// 0..1 chance that any given member runs into trouble. Rises with danger,
/// falls as the group's combat power grows. 0 for danger level 1.
double perilRatio(int dangerLevel, List<CreatureInstance> members) {
  final threat = (dangerLevel - 1).clamp(0, 100) * kThreatPerDanger;
  if (threat <= 0) return 0;
  final power = groupCombatPower(members);
  return (threat / (threat + power)).clamp(0.0, 1.0);
}

/// One member's misfortune on an expedition.
class Casualty {
  final String creatureId;
  final int hpLost;
  final bool ko;
  const Casualty({
    required this.creatureId,
    required this.hpLost,
    required this.ko,
  });
}

/// Rolls per-member casualties for a resolved expedition. Each member has a
/// [perilRatio] chance of being hit; a hit removes 15–50% of its max HP (never
/// more than it has left — a lethal hit is a K.O., not overkill).
List<Casualty> rollCasualties(
  int dangerLevel,
  List<CreatureInstance> members,
  math.Random rng,
) {
  final peril = perilRatio(dangerLevel, members);
  if (peril <= 0) return const [];
  final out = <Casualty>[];
  for (final c in members) {
    if (rng.nextDouble() >= peril) continue;
    // Both ends are dials (Kampagne → Risiko).
    final lo = GameTuning.i.raw(Dials.casualtyHpMin);
    final hi = GameTuning.i.raw(Dials.casualtyHpMax);
    final frac = lo + (hi - lo).clamp(0.0, 1.0) * rng.nextDouble();
    final raw = (c.maxHp * frac).round().clamp(1, c.maxHp);
    final ko = raw >= c.hp;
    out.add(Casualty(creatureId: c.id, hpLost: ko ? c.hp : raw, ko: ko));
  }
  return out;
}

/// Fraction of the gather haul lost when things went wrong in transit — grows
/// with the number and severity of casualties, capped so a bad trip still
/// brings something home.
double lootPenalty(List<Casualty> casualties) {
  if (casualties.isEmpty) return 0;
  final ko = casualties.where((c) => c.ko).length;
  final hurt = casualties.length - ko;
  return (GameTuning.i.raw(Dials.lootPenaltyPerHurt) * hurt +
          GameTuning.i.raw(Dials.lootPenaltyPerKo) * ko)
      .clamp(0.0, GameTuning.i.raw(Dials.lootPenaltyMax));
}

/// Coarse label for the planner UI.
String perilLabel(double ratio) {
  if (ratio <= 0.0001) return 'None';
  if (ratio < 0.15) return 'Low';
  if (ratio < 0.35) return 'Medium';
  if (ratio < 0.6) return 'High';
  return 'Extreme';
}
