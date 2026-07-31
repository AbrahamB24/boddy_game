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

  ActiveEffect({required this.turnsRemaining, required this.value});
}

/// The mutually-exclusive main statuses (only one active at a time).
///
/// `sleep` joined on 2026-07-30 (user: "Gerne darfst du noch weitere Effekte
/// hinzufügen, welche an Pokemon angelehnt sind"). It is the heaviest thing that
/// can happen to a turn — a near-certain skip — which is why it belongs in THIS
/// group: a sleeping monster cannot also be frozen, and stacking two turn-eaters
/// would take a monster out of the fight entirely.
enum MainStatusKind {
  burn('Burn', '🔥'),
  frost('Frost', '❄️'),
  poison('Poison', '☠️'),
  fear('Fear', '😨'),
  sleep('Sleep', '😴');

  final String label;
  final String emoji;
  const MainStatusKind(this.label, this.emoji);
}

/// Fixed duration (in the afflicted combatant's own turns) for each main
/// status.
int mainStatusDuration(MainStatusKind kind) => switch (kind) {
  MainStatusKind.burn => 3,
  MainStatusKind.frost => 2,
  MainStatusKind.poison => 4,
  MainStatusKind.fear => 3,
  // Short on purpose: at an 85 % skip chance, two turns is already two lost
  // actions, and Pokémon's multi-turn sleep is famous for deciding fights.
  MainStatusKind.sleep => 2,
};

/// End-of-round damage-over-time as a fraction of max HP. Poison escalates
/// with [turnsActive] (0-indexed: 0 on the round it was inflicted); burn is
/// flat. Frost/fear deal no direct damage (their cost is skip chance/speed).
double statusDotFraction(MainStatusKind kind, int turnsActive) =>
    switch (kind) {
      MainStatusKind.burn => 0.05,
      MainStatusKind.poison => 0.06 + 0.02 * turnsActive,
      MainStatusKind.frost => 0,
      MainStatusKind.fear => 0,
      MainStatusKind.sleep => 0,
    };

/// Attack multiplier while afflicted (burn saps offense).
double statusAttackMult(MainStatusKind kind) =>
    kind == MainStatusKind.burn ? 0.80 : 1.0;

/// Speed multiplier while afflicted (frost is a heavy slow).
double statusSpeedMult(MainStatusKind kind) =>
    kind == MainStatusKind.frost ? 0.60 : 1.0;

/// Chance the afflicted combatant's turn is skipped entirely this round.
double statusSkipChance(MainStatusKind kind) => switch (kind) {
  MainStatusKind.frost => 0.10,
  MainStatusKind.fear => 0.25,
  MainStatusKind.sleep => 0.85,
  _ => 0.0,
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
  defenseDown('Exposed', '🪓');

  final String label;
  final String emoji;
  const SecondaryDebuffKind(this.label, this.emoji);
}

const int kSecondaryDebuffDuration = 2;

double secondaryAccuracyMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.blind ? 0.75 : 1.0;

double secondarySpeedMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.speedDown ? 0.70 : 1.0;

/// Attack multiplier while [kind] is on the target (Growl).
double secondaryAttackMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.attackDown ? 0.75 : 1.0;

/// Defense multiplier while [kind] is on the target (Screech).
double secondaryDefenseMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.defenseDown ? 0.70 : 1.0;

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

const int kSelfBuffDuration = 2;

double selfBuffDefenseMult(SelfBuffKind kind) =>
    kind == SelfBuffKind.armor ? 1.30 : 1.0;

double selfBuffAttackMult(SelfBuffKind kind) =>
    kind == SelfBuffKind.rage ? 1.25 : 1.0;

double selfBuffSpeedMult(SelfBuffKind kind) =>
    kind == SelfBuffKind.haste ? 1.30 : 1.0;

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
