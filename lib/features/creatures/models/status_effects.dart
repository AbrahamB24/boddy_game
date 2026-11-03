// ── Status effect catalog ────────────────────────────────────
// Fixed, game-wide numeric effects for every status/buff/debuff (balance
// spec section 8). Abilities only reference WHICH of these to apply and
// with what chance — the magnitude/duration live here, once, so tuning is
// a one-line change instead of hunting through move data.
//
// Only ONE main status can be active at a time (mutually exclusive); the
// secondary debuffs (Blind / Slow / Weaken / Expose) stack separately from the
// main status; self buffs coexist with each other and refresh their duration on
// reapply rather than stacking.
//
// The numbers here are DEFAULTS since 2026-07-30, not the values: an ability
// carries its own duration and magnitude and only falls back to these — see
// AbilityEffect and Combatant.applyMainStatus.
//
// The self-buff/secondary-debuff magnitudes and durations are Dials since
// 2026-09-08 (user: "Buffs und Debuffs sollen sich wirklich lohnen") — see
// Dials.buffArmorPct etc. in dials.dart. The main-status numbers (burn,
// frost, poison, fear, sleep) stay plain constants here for now.

import '../../../core/tuning/game_tuning.dart';
import 'creature_enums.dart' show CreatureElement;

/// One effect ACTIVE on a combatant: how many of its turns are left, and the
/// magnitude it was inflicted with (user 2026-07-30).
///
/// The magnitude used to be a lookup by kind, which is why every burn in the
/// game was the same burn. It travels WITH the instance now — the ability that
/// applied it decides how hard it bites, and the constants below are only what a
/// move that says nothing falls back to.
class ActiveEffect {
  int turnsRemaining;

  /// A positive fraction of "how much": accuracy lost, speed lost, stat gained.
  final double value;

  /// Applied during its holder's OWN turn and not yet carried through an
  /// opponent's turn. The end-of-turn upkeep skips the countdown once for a
  /// fresh effect: a self-buff cast this turn used to tick down in the same
  /// upkeep it was cast in, so a 1-turn Quick Guard/Quick Sprint expired
  /// before a single enemy acted — it did literally nothing.
  bool fresh;

  ActiveEffect({
    required this.turnsRemaining,
    required this.value,
    this.fresh = false,
  });
}

/// The mutually-exclusive main statuses (only one active at a time).
///
/// `sleep` joined on 2026-07-30 (user: "Gerne darfst du noch weitere Effekte
/// hinzufügen, welche an Pokemon angelehnt sind"). It is the heaviest thing that
/// can happen to a turn — a near-certain skip — which is why it belongs in THIS
/// group: a sleeping monster cannot also be frozen, and stacking two turn-eaters
/// would take a monster out of the fight entirely.
///
/// EXPANDED 2026-09-15 (user: "für alle Typen einen Angriffseffekt... das
/// getroffene Monster hat nun die Schwächen des eigenen Typs und die
/// Schwächen des [Angreifer-]Typs") — every type now has (at least) one
/// signature status, and every one of them EXPOSES the target to that
/// element's own weaknesses on top of its own (see [mainStatusExposure] and
/// Combatant.incomingTypeMult). `freeze`/`petrify`/`paralysis`/`soaked`/
/// `dazzled` are new; `poison`/`fear` — already Pokémon-flavoured — simply
/// gained an element home (Plant/Shadow) they never had before. `confusion`
/// is the one exception: a universal ailment no single type owns, so it
/// exposes nothing (see [mainStatusExposure]).
enum MainStatusKind {
  burn('Burn', '🔥'),
  frost('Frost', '❄️'),
  // A second, HEAVIER ice status (user 2026-09-15's "eingefrieren", distinct
  // from the mild chip-damage-free slow `frost` already was) — cheap Ice
  // moves chill (frost), expensive ones truly freeze (near-total skip, same
  // tier as sleep).
  freeze('Freeze', '🥶'),
  poison('Poison', '☠️'),
  fear('Fear', '😨'),
  sleep('Sleep', '😴'),
  // Stone's signature (user's own explicit "versteinern") — a heavy skip,
  // shorter than freeze/sleep so three same-shaped statuses don't all read
  // identically.
  petrify('Petrify', '🗿'),
  // Lightning's signature — a moderate, Pokémon-paralysis-flavoured skip.
  paralysis('Paralysis', '⚡'),
  // Water's signature — a pure attack-sap, no DoT/skip of its own (the
  // "shape" burn and frost don't already cover).
  soaked('Soaked', '💧'),
  // Light's signature — a pure accuracy-sap (the heavier, timed cousin of
  // the existing `blind` secondary debuff).
  dazzled('Dazzled', '✨'),
  // The one status no type owns (user 2026-09-15's "Konfusion", listed
  // alongside the type-exposure ask but explicitly its own thing): each of
  // the afflicted's own turns has a chance to hit ITSELF instead of acting —
  // see CombatEngine's confusion handling, which is why it needs no
  // skip-chance catalog entry of its own the way fear/sleep do.
  confusion('Confusion', '💫');

  final String label;
  final String emoji;
  const MainStatusKind(this.label, this.emoji);
}

/// The element a status is the SIGNATURE ailment of — while it's active the
/// target is exposed to THIS element's weaknesses on top of its own (user
/// 2026-09-15). Null for the two statuses no single type owns (`sleep`,
/// generic since before this feature existed; `confusion`, deliberately
/// universal).
CreatureElement? mainStatusExposure(MainStatusKind kind) => switch (kind) {
  MainStatusKind.burn => CreatureElement.fire,
  MainStatusKind.frost || MainStatusKind.freeze => CreatureElement.ice,
  MainStatusKind.poison => CreatureElement.plant,
  MainStatusKind.fear => CreatureElement.shadow,
  MainStatusKind.petrify => CreatureElement.stone,
  MainStatusKind.paralysis => CreatureElement.lightning,
  MainStatusKind.soaked => CreatureElement.water,
  MainStatusKind.dazzled => CreatureElement.light,
  MainStatusKind.sleep || MainStatusKind.confusion => null,
};

/// Fixed duration (in the afflicted combatant's own turns) for each main
/// status.
int mainStatusDuration(MainStatusKind kind) => switch (kind) {
  MainStatusKind.burn => 3,
  MainStatusKind.frost => 2,
  MainStatusKind.freeze => 2,
  MainStatusKind.poison => 4,
  MainStatusKind.fear => 3,
  // Short on purpose: at an 85 % skip chance, two turns is already two lost
  // actions, and Pokémon's multi-turn sleep is famous for deciding fights.
  MainStatusKind.sleep => 2,
  MainStatusKind.petrify => 2,
  MainStatusKind.paralysis => 3,
  MainStatusKind.soaked => 3,
  MainStatusKind.dazzled => 3,
  MainStatusKind.confusion => 3,
};

/// End-of-round damage-over-time as a fraction of max HP. Poison escalates
/// with [turnsActive] (0-indexed: 0 on the round it was inflicted); burn is
/// flat. Every other status deals no direct damage this way (their cost is
/// skip chance/stat loss/self-hit instead).
double statusDotFraction(MainStatusKind kind, int turnsActive) =>
    switch (kind) {
      MainStatusKind.burn => 0.05,
      MainStatusKind.poison => 0.06 + 0.02 * turnsActive,
      _ => 0,
    };

/// Attack multiplier while afflicted — burn saps offense by a FIXED amount
/// (not authorable, see AbilityEffectKind.burn); soaked's own sap is the
/// move's AUTHORED value instead (applied directly off `mainStatusValue` in
/// Combatant.effectiveAttack), so this is only its CATALOG default.
double statusAttackMult(MainStatusKind kind) => switch (kind) {
  MainStatusKind.burn => 0.80,
  MainStatusKind.soaked => 0.70,
  _ => 1.0,
};

/// Speed multiplier while afflicted (frost is a heavy slow).
double statusSpeedMult(MainStatusKind kind) =>
    kind == MainStatusKind.frost ? 0.60 : 1.0;

/// Accuracy multiplier while afflicted — dazzled's CATALOG default, mirrored
/// by the secondary `blind` debuff's own (smaller, stackable) version.
double statusAccuracyMult(MainStatusKind kind) =>
    kind == MainStatusKind.dazzled ? 0.55 : 1.0;

/// Chance the afflicted combatant's turn is skipped entirely this round —
/// also confusion's CATALOG default self-hit chance, which shares this
/// plumbing despite hitting itself rather than skipping outright (both are
/// "roll this fraction, big effect if it lands" statuses read the same way
/// by Combatant._catalogMainValue).
double statusSkipChance(MainStatusKind kind) => switch (kind) {
  MainStatusKind.frost => 0.10,
  MainStatusKind.fear => 0.25,
  MainStatusKind.sleep => 0.85,
  MainStatusKind.freeze => 0.70,
  MainStatusKind.petrify => 0.65,
  MainStatusKind.paralysis => 0.20,
  MainStatusKind.confusion => 0.33,
  _ => 0.0,
};

/// Every status whose authored [AbilityDef.inflictMainValue] IS a skip (or
/// confusion's self-hit) chance, as opposed to frost's — whose authored
/// value is its speed loss, with its 10 % skip a fixed side effect nobody
/// tunes. Combatant.rollSkipTurn and CombatEngine's confusion check both
/// read this to know whether `mainStatusValue` is that chance directly.
bool statusValueIsRollChance(MainStatusKind kind) => switch (kind) {
  MainStatusKind.fear ||
  MainStatusKind.sleep ||
  MainStatusKind.freeze ||
  MainStatusKind.petrify ||
  MainStatusKind.paralysis ||
  MainStatusKind.confusion => true,
  _ => false,
};

/// The secondary debuffs — they stack independently of the main status (a burned
/// target can also be blinded), one instance each.
///
/// `attackDown` and `defenseDown` joined on 2026-07-30 (user: Pokémon-flavoured
/// additions). They are the other half of a fight nobody could author before:
/// the game had three ways to make a monster act LESS (blind, slow, frost) and
/// no way to make it hit softer or crumple faster — Growl and Screech, which is
/// what a support monster is for.
enum SecondaryDebuffKind {
  blind('Blind', '👁️'),
  speedDown('Slowed', '🐌'),
  attackDown('Weakened', '💤'),
  defenseDown('Exposed', '🪓'),
  // "Deevolution" (user 2026-09-15): battle-only, never touches the actual
  // species/stage on the collection creature — Combatant's stats are
  // resolved once at construction and the engine never reaches back into
  // species defs mid-fight (see Combatant's own class doc), so a REAL
  // stage-down would break that. A flat all-stats cut approximates
  // "fighting one stage weaker" close enough while staying inside that
  // rule: one number softens attack, defense AND speed together, applied
  // wherever the other secondary debuffs already are.
  regression('Regressed', '⏪');

  final String label;
  final String emoji;
  const SecondaryDebuffKind(this.label, this.emoji);
}

int get kSecondaryDebuffDuration =>
    GameTuning.i.count(Dials.debuffDurationTurns);

double secondaryAccuracyMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.blind
    ? 1 - GameTuning.i.raw(Dials.debuffBlindPct)
    : 1.0;

double secondarySpeedMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.speedDown
    ? 1 - GameTuning.i.raw(Dials.debuffSlowPct)
    : 1.0;

/// Attack multiplier while [kind] is on the target (Growl).
double secondaryAttackMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.attackDown
    ? 1 - GameTuning.i.raw(Dials.debuffWeakenPct)
    : 1.0;

/// Defense multiplier while [kind] is on the target (Screech).
double secondaryDefenseMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.defenseDown
    ? 1 - GameTuning.i.raw(Dials.debuffExposePct)
    : 1.0;

/// The ALL-STATS multiplier while regressed — the one debuff that hits
/// attack, defense AND speed together (see [SecondaryDebuffKind.regression]'s
/// own doc for why a flat cut stands in for a real stage-down).
double secondaryRegressionMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.regression
    ? 1 - GameTuning.i.raw(Dials.debuffRegressionPct)
    : 1.0;

/// The 3 self buffs — a combatant can hold all 3 at once; reapplying one
/// just refreshes its duration rather than stacking magnitude.
enum SelfBuffKind {
  armor('Armor', '🛡️'),
  rage('Rage', '💢'),
  haste('Haste', '⏱️');

  final String label;
  final String emoji;
  const SelfBuffKind(this.label, this.emoji);
}

int get kSelfBuffDuration => GameTuning.i.count(Dials.buffDurationTurns);

double selfBuffDefenseMult(SelfBuffKind kind) =>
    kind == SelfBuffKind.armor ? 1 + GameTuning.i.raw(Dials.buffArmorPct) : 1.0;

double selfBuffAttackMult(SelfBuffKind kind) =>
    kind == SelfBuffKind.rage ? 1 + GameTuning.i.raw(Dials.buffRagePct) : 1.0;

double selfBuffSpeedMult(SelfBuffKind kind) =>
    kind == SelfBuffKind.haste ? 1 + GameTuning.i.raw(Dials.buffHastePct) : 1.0;

/// A one-off self-penalty some universal/Plant moves inflict on their OWN
/// user as a cost of use (Power Surge: -10% Def 1 turn; Gaia's Wrath: -Speed
/// next turn) — deliberately outside the named buff/debuff catalog above
/// since these are move-specific costs, not reusable status types.
enum SelfPenaltyStat { defense, speed }

class SelfPenalty {
  final SelfPenaltyStat stat;
  final double mult; // e.g. 0.90 for -10%
  final int turns;
  const SelfPenalty({required this.stat, required this.mult, this.turns = 1});
}
