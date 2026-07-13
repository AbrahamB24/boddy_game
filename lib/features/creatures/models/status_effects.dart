// ── Status effect catalog ────────────────────────────────────
// Fixed, game-wide numeric effects for every status/buff/debuff (balance
// spec section 8). Abilities only reference WHICH of these to apply and
// with what chance — the magnitude/duration live here, once, so tuning is
// a one-line change instead of hunting through move data.
//
// Only ONE main status can be active at a time (mutually exclusive);
// secondary debuffs (Blind/Speed-Down) stack separately from the main
// status; self buffs coexist with each other and refresh their duration on
// reapply rather than stacking.

/// The 4 mutually-exclusive main statuses (only one active at a time).
enum MainStatusKind {
  burn('Burn', '🔥'),
  frost('Frost', '❄️'),
  poison('Poison', '☠️'),
  fear('Fear', '😨');

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
  _ => 0.0,
};

/// The 2 secondary debuffs — stack independently of the main status (a
/// burned target can also be blinded).
enum SecondaryDebuffKind {
  blind('Blind', '👁️'),
  speedDown('Slowed', '🐌');

  final String label;
  final String emoji;
  const SecondaryDebuffKind(this.label, this.emoji);
}

const int kSecondaryDebuffDuration = 2;

double secondaryAccuracyMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.blind ? 0.75 : 1.0;

double secondarySpeedMult(SecondaryDebuffKind kind) =>
    kind == SecondaryDebuffKind.speedDown ? 0.70 : 1.0;

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
