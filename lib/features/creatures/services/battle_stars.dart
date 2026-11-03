import '../models/combatant.dart';

// ── Stars for a won campaign battle (user 2026-09-28) ─────────────────────────
// "Es braucht klare Kriterien für die Sterne, egal wie viele Monster beteiligt
// sind." Every criterion is a YES/NO or a FRACTION of the team's own maximum —
// never a count of monsters, moves or rounds — so a lone starter and a party of
// six are judged by the same yardstick.
//
//   ★    Win the battle.
//   ★★   No monster of yours was knocked out.
//   ★★★  Your team finished with at least [kStarHpFraction] of its combined max HP.
//
// Each star is its own tick, so the count is simply how many are ticked (a win
// that kept 80 % HP but lost one monster is ★ + ★★★ = 2 stars, and the checklist
// says which one is missing). Stars never gate progress: the map unlocks come
// with the FIRST star; the rest only pay a bonus.

/// The share of the team's combined max HP it must keep for the third star.
const double kStarHpFraction = 0.6;

/// What each star count multiplies the XP of the fight by.
const Map<int, double> kStarXpMultiplier = {1: 1.0, 2: 1.25, 3: 1.5};

/// Gold paid ONCE per battle for each star reached for the first time (the first
/// star pays none — it is the win itself, and the map's own unlocks).
const Map<int, int> kStarFirstTimeGold = {2: 20, 3: 40};

/// How a finished fight was judged.
class BattleStars {
  final bool won;

  /// Nobody on the team was knocked out.
  final bool noKnockOut;

  /// The team's combined HP at the end, as a fraction of its combined max HP.
  final double hpLeft;

  const BattleStars({
    required this.won,
    required this.noKnockOut,
    required this.hpLeft,
  });

  /// The third star's tick.
  bool get hpKept => hpLeft >= kStarHpFraction;

  /// 0 for a fight that was not won, otherwise 1–3.
  int get count => !won ? 0 : 1 + (noKnockOut ? 1 : 0) + (hpKept ? 1 : 0);

  /// The XP multiplier this many stars earn.
  double get xpMultiplier => kStarXpMultiplier[count] ?? 1.0;
}

/// Judges a fight from its final state: [players] is the whole team INCLUDING
/// the benched, as the engine keeps it.
BattleStars judgeBattle({required bool won, required List<Combatant> players}) {
  var hp = 0, max = 0;
  var knockedOut = false;
  for (final p in players) {
    hp += p.hp.clamp(0, p.maxHp);
    max += p.maxHp;
    if (!p.alive) knockedOut = true;
  }
  return BattleStars(
    won: won,
    noKnockOut: !knockedOut,
    hpLeft: max <= 0 ? 0 : hp / max,
  );
}

/// The one-time gold for taking a battle from [before] stars to [after].
int firstTimeStarGold(int before, int after) {
  var gold = 0;
  for (var s = before + 1; s <= after; s++) {
    gold += kStarFirstTimeGold[s] ?? 0;
  }
  return gold;
}
