import '../../../core/tuning/game_tuning.dart';

// ── THE linear overworld path ───────────────────────────────
// (redesign 2026-07-24, user: "Der Weg auf der Map ist Linear … die ersten 5
// Kämpfe sind immer 1vs1 … ab Kampf 6 zwei Monster, ab Kampf 15 drei, in Ära 2
// bis auf 6. Die Gegner sollen mitskalieren.")
//
// The overworld is ONE continuous line of numbered battles. Battle 1 sits at the
// foot of the trail; you climb, and every battle up the line is a little
// stronger than the last. Resource spots and hunts sit inline as you pass them.
// The numbering NEVER resets between eras — battle 1..N runs straight through —
// and each era's segment ends in a BOSS battle (the era gate). This is the pure
// model: party-size rule, enemy scaling and the battle↔era mapping. No widgets,
// so it tests without pumping a frame.
//
// Party size is set by WHERE ON THE LINE the fight is, not by research: the same
// battle always allows the same number of monsters (re-fighting battle 3 is
// always 1v1). Team-size techs are gone — see kTeamSizeTechIds's removal.

/// Regular battles before a FALLBACK-generated boss (user 2026-09-05: real
/// content no longer has a fixed region length — a region is however long
/// the path editor makes it, ending wherever a node's own `isBoss` flag is
/// set; see `PathNode.isBoss` / `regionForBattle` in path_node.dart). This
/// dial only shapes the BUNDLED starter path (`_buildFallbackPath`) and the
/// degenerate "no node authored here at all" fallback below — never a
/// region an author has actually placed a boss in.
///
/// 18 puts the bundled path's party-size steps (battles 6 and 15) comfortably
/// inside its first fallback region, with a boss at battle 19.
int get kBattlesBeforeBoss => GameTuning.i.count(Dials.battlesBeforeBoss);

/// Full length of one FALLBACK region segment (regular battles + the boss) —
/// see [kBattlesBeforeBoss].
int get kFallbackBattlesPerRegion => kBattlesBeforeBoss + 1;

/// Largest party the game ever allows.
int get kMaxPartySize => GameTuning.i.count(Dials.maxPartySize);

/// The battle numbers at which the max party size steps up by one.
///
/// Five plain battle numbers since 2026-07-29 (Kampagne → Gruppengrösse). They
/// used to be two Era-I anchors plus three DERIVED from the era length — which
/// meant the last three moved whenever the path got longer, and no menu could
/// show where they actually were. Absolute numbers are the thing the author
/// thinks in ("ab Kampf 6 zwei Monster"), and they are now exactly that.
///
/// Sorted, so entering them out of order still yields a rising ladder rather
/// than a silently dead threshold.
List<int> partySizeThresholds() => [
  GameTuning.i.count(Dials.partyStep2),
  GameTuning.i.count(Dials.partyStep3),
  GameTuning.i.count(Dials.partyStep4),
  GameTuning.i.count(Dials.partyStep5),
  GameTuning.i.count(Dials.partyStep6),
]..sort();

/// Max party size allowed when fighting [battleNumber] (1-based on the line).
///
/// A RULE OF POSITION: early battles are always small, however far the player
/// has otherwise progressed. Grows 1 → 6 as the thresholds are passed.
int partySizeForBattle(int battleNumber) {
  var size = 1;
  for (final t in partySizeThresholds()) {
    if (battleNumber >= t) size++;
  }
  return size.clamp(1, kMaxPartySize);
}

/// The next party-size step ahead of a player who has cleared [battlesCleared]
/// battles: how big the party gets, from which battle number, and how many more
/// wins it takes to allow it. Null once the largest party is already allowed.
///
/// Seats come from the map alone (user 2026-09-22: "nur die Anzahl der Monster pro
/// Team wird freigeschalten durch die Map") — the number of SAVED teams is not
/// limited. The Teams screen reads this for its "seat 3 from battle 15 — 5 wins
/// to go" line and the locked seat on every team.
({int size, int battle, int winsToGo})? nextPartySeat(int battlesCleared) {
  final cap = partySizeForBattle(battlesCleared + 1);
  if (cap >= kMaxPartySize) return null;
  for (final t in partySizeThresholds()) {
    final size = partySizeForBattle(t);
    if (t > battlesCleared + 1 && size > cap) {
      // The allowance for the NEXT battle is what counts (see partyCap): clearing
      // battle t-1 is what lets battle t take the bigger party.
      return (size: size, battle: t, winsToGo: t - 1 - battlesCleared);
    }
  }
  return null;
}

/// The max party the player has UNLOCKED so far, given the furthest battle they
/// have reached. This is the cap for things not tied to a single battle node —
/// standing teams and expedition groups — where "the highest I've earned"
/// applies rather than "this specific fight". Reaching battle N unlocks
/// [partySizeForBattle](N).
int unlockedPartySize(int highestBattleReached) =>
    partySizeForBattle(highestBattleReached);

/// Whether [battleNumber] is a boss battle — the FALLBACK answer only, for
/// when no [PathNode] exists at this position at all (see path_node.dart's
/// `pathNodeAtOrder`); real authored content answers this via the node's own
/// `isBoss` flag instead, which always wins where both exist. Real regions
/// are variable-length now (a region ends wherever a node's `isBoss` is
/// true), so this fixed-length formula is only ever a degenerate default.
bool isBossBattle(int battleNumber) =>
    battleNumber > 0 && battleNumber % kFallbackBattlesPerRegion == 0;

/// Enemy level for a battle, scaling smoothly up the line so each fight is a
/// little stronger than the last (user: "die Gegner sollen mitskalieren").
///
/// The starter now begins at level 1 (see adoptStarter) and the first five
/// fights must be winnable 1v1, so the curve starts low and rises ~ +1 every
/// two battles. Bosses fight [kBossLevelBonus] above their line position.
///
/// Deliberately simple and central — this is THE dial the combat Monte-Carlo
/// tunes against; re-run it after changing the slope.
int enemyLevelForBattle(int battleNumber) {
  final n = battleNumber < 1 ? 1 : battleNumber;
  final base = 1 + (n - 1) ~/ 2;
  return isBossBattle(n) ? base + kBossLevelBonus : base;
}

/// How far above their line position a boss fights.
int get kBossLevelBonus => GameTuning.i.count(Dials.bossLevelBonus);

/// How many enemies a regular battle fields (bosses are always a lone elite).
///
/// The count scales up the line for variety, but stays STRICTLY BELOW the party
/// you may bring at that battle ([partySizeForBattle]) — so you are never
/// confronted with as many (or more) monsters than you have unlocked the right
/// to bring (user 2026-07-24: "ich werde der Schwierigkeit zuerst konfrontiert,
/// bevor ich es freispiele"). Concretely enemies = partySize − 1 (min 1): you
/// unlock the 2-monster party (battle 6) and still fight ONE foe; you meet a
/// second foe only at battle 15, where the party is already three. So you
/// always outnumber, and every new pack size arrives AFTER the party that
/// beats it. (The auto-battle also handles "you outnumber" far better than a
/// symmetric pack — see test/linear_combat_probe_test.dart.)
int enemyCountForBattle(int battleNumber) =>
    (partySizeForBattle(battleNumber) - 1).clamp(1, kMaxPartySize);
