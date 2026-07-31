import 'status_effects.dart';

// ── What an ability's effect MEANS in combat ─────────────────
// User 2026-07-30: "Wenn ich einen Effect auswähle für eine Fähigkeit, zeige mir
// ganz genau, was dies im Kampf bedeutet. Das Menü darf noch übersichtlicher
// werden. Effekt wählen (alle Effekte in einer Liste), Dauer (0 default, falls
// es nicht auf Zeit ist), Wert des Effekts (bsp wieviel HP burn verursacht)."
//
// Three things were in the way of that, and this file is all three:
//
//  1. ONE LIST. The form asked the author to know the engine's internal
//     families first — "main status", "secondary debuff", "self buff",
//     "self-cost" were four separate pickers, and heal/lifesteal were fields
//     somewhere else entirely. [AbilityEffectKind] is the flat list: every
//     effect an ability can carry, in one enum, in one dropdown.
//
//  2. NUMBERS THAT BELONG TO THE MOVE. Duration and magnitude were global
//     constants in status_effects.dart, so "Burn" meant exactly one thing
//     forever and two fire moves could not differ. Each effect now carries its
//     own [turns] and [value]; 0 means "use the catalog default", which is what
//     keeps every existing ability exactly as it was.
//
//  3. WORDS FOR IT. [describeAbilityEffect] states the whole outcome — the part
//     the author tuned AND the parts that are fixed — from the same numbers the
//     engine applies. The form, the battle screen's ability card and the species
//     editor all read it, so nothing can describe an effect one way and resolve
//     it another.
//
// The magnitude is ALWAYS a positive fraction of "how much" — damage per turn,
// speed lost, defense gained, chance to skip. Never a multiplier: 0.30 reads as
// "30 % of something" for every effect in the list, and the direction is the
// effect's business, not the author's.

/// Which slot of [AbilityDef] an effect is stored in — the engine's own
/// grouping, kept because the RULES differ per family (a main status is
/// exclusive, a debuff stacks alongside it, a self-cost hits the user).
enum AbilityEffectFamily {
  /// Burn/frost/poison/fear/sleep — at most ONE on a target at a time.
  mainStatus,

  /// Blind / slow / weaken / expose — stack alongside the main status, one
  /// instance each.
  debuff,

  /// Armor/rage/haste — on the USER, several at once.
  selfBuff,

  /// Restores HP. Not timed.
  heal,

  /// Heals the attacker a share of the damage just dealt. Not timed.
  lifesteal,

  /// A cost the user pays for using the move at all — no chance roll.
  selfPenalty,

  /// Heals the user a little at the end of each of its turns, for a while
  /// (user 2026-07-30, Pokémon's Wish/Leech).
  regen,

  /// The user takes a share of the damage it just dealt (Double-Edge).
  recoil,
}

/// EVERY effect an ability can carry, in one list (user 2026-07-30). The order
/// is the order the picker shows: what you do to THEM, then what you do for
/// YOURSELF, then what it costs you.
enum AbilityEffectKind {
  burn,
  poison,
  frost,
  fear,
  sleep,
  blind,
  slow,
  attackDown,
  defenseDown,
  heal,
  regen,
  lifesteal,
  armor,
  rage,
  haste,
  recoil,
  selfDefDown,
  selfSpeedDown;

  AbilityEffectFamily get family => switch (this) {
    burn || poison || frost || fear || sleep => AbilityEffectFamily.mainStatus,
    blind || slow || attackDown || defenseDown => AbilityEffectFamily.debuff,
    heal => AbilityEffectFamily.heal,
    regen => AbilityEffectFamily.regen,
    lifesteal => AbilityEffectFamily.lifesteal,
    armor || rage || haste => AbilityEffectFamily.selfBuff,
    recoil => AbilityEffectFamily.recoil,
    selfDefDown || selfSpeedDown => AbilityEffectFamily.selfPenalty,
  };

  String get label => switch (this) {
    burn => 'Burn',
    poison => 'Poison',
    frost => 'Frost',
    fear => 'Fear',
    sleep => 'Sleep',
    blind => 'Blind',
    slow => 'Slow',
    attackDown => 'Weaken (attack down)',
    defenseDown => 'Expose (defense down)',
    heal => 'Heal',
    regen => 'Regeneration',
    lifesteal => 'Lifesteal',
    armor => 'Armor',
    rage => 'Rage',
    haste => 'Haste',
    recoil => 'Recoil',
    selfDefDown => 'Self-cost: Defense',
    selfSpeedDown => 'Self-cost: Speed',
  };

  String get emoji => switch (this) {
    burn => '🔥',
    poison => '☠️',
    frost => '❄️',
    fear => '😨',
    sleep => '😴',
    blind => '👁️',
    slow => '🐌',
    attackDown => '💤',
    defenseDown => '🪓',
    heal => '💚',
    regen => '🌱',
    lifesteal => '🩸',
    recoil => '💥',
    armor => '🛡️',
    rage => '💢',
    haste => '⏱️',
    selfDefDown || selfSpeedDown => '⚠️',
  };

  /// Whether the effect RUNS for a while. A heal and a lifesteal happen once
  /// and are over, so their duration field is meaningless — that is the "falls
  /// es nicht auf Zeit ist" case, and the form says so instead of offering a
  /// number that would be ignored.
  bool get isTimed =>
      family != AbilityEffectFamily.heal &&
      family != AbilityEffectFamily.lifesteal &&
      family != AbilityEffectFamily.recoil;

  /// Whether it lands on the OPPONENT. The rest land on the user, which decides
  /// whether a chance roll even makes sense.
  bool get hitsTarget =>
      family == AbilityEffectFamily.mainStatus ||
      family == AbilityEffectFamily.debuff;

  /// Whether a chance below 100 % is authorable. A self buff, a heal and a
  /// self-cost always land — rolling for them would only ever be a way to waste
  /// a turn.
  bool get rollsChance => hitsTarget;

  /// What the [value] field means, in the author's words. Always a percentage.
  String get valueLabel => switch (this) {
    burn => 'Damage per turn (% of max HP)',
    poison => 'Damage on the FIRST turn (% of max HP)',
    frost => 'Speed lost (%)',
    fear => 'Chance the turn is skipped (%)',
    sleep => 'Chance the turn is skipped (%)',
    blind => 'Accuracy lost (%)',
    slow => 'Speed lost (%)',
    attackDown => 'Attack the target loses (%)',
    defenseDown => 'Defense the target loses (%)',
    heal => 'HP restored (% of max HP)',
    regen => 'HP restored per turn (% of max HP)',
    lifesteal => 'Of the damage dealt (%)',
    recoil => 'Of the damage dealt, taken BACK (%)',
    armor => 'Defense gained (%)',
    rage => 'Attack gained (%)',
    haste => 'Speed gained (%)',
    selfDefDown => 'Defense the USER loses (%)',
    selfSpeedDown => 'Speed the USER loses (%)',
  };

  /// The catalog value a `0` in the form falls back to, as a fraction.
  /// Everything here is derived from status_effects.dart rather than repeated,
  /// so the defaults cannot drift from the game's own numbers.
  double get defaultValue => switch (this) {
    burn => statusDotFraction(MainStatusKind.burn, 0),
    poison => statusDotFraction(MainStatusKind.poison, 0),
    frost => 1 - statusSpeedMult(MainStatusKind.frost),
    fear => statusSkipChance(MainStatusKind.fear),
    sleep => statusSkipChance(MainStatusKind.sleep),
    blind => 1 - secondaryAccuracyMult(SecondaryDebuffKind.blind),
    slow => 1 - secondarySpeedMult(SecondaryDebuffKind.speedDown),
    attackDown => 1 - secondaryAttackMult(SecondaryDebuffKind.attackDown),
    defenseDown => 1 - secondaryDefenseMult(SecondaryDebuffKind.defenseDown),
    // A heal, a lifesteal, a regen and a recoil have no catalog entry — the
    // move's own percentage IS the effect, so these are the seed values the form
    // starts a fresh one at.
    heal => 0.35,
    regen => 0.08,
    lifesteal => 0.30,
    recoil => 0.25,
    armor => selfBuffDefenseMult(SelfBuffKind.armor) - 1,
    rage => selfBuffAttackMult(SelfBuffKind.rage) - 1,
    haste => selfBuffSpeedMult(SelfBuffKind.haste) - 1,
    selfDefDown || selfSpeedDown => 0.10,
  };

  /// The catalog duration a `0` in the form falls back to, in the afflicted
  /// combatant's own turns. 0 for the untimed ones.
  int get defaultTurns => switch (this) {
    burn => mainStatusDuration(MainStatusKind.burn),
    poison => mainStatusDuration(MainStatusKind.poison),
    frost => mainStatusDuration(MainStatusKind.frost),
    fear => mainStatusDuration(MainStatusKind.fear),
    sleep => mainStatusDuration(MainStatusKind.sleep),
    regen => 3,
    blind || slow || attackDown || defenseDown => kSecondaryDebuffDuration,
    armor || rage || haste => kSelfBuffDuration,
    selfDefDown || selfSpeedDown => 1,
    heal || lifesteal || recoil => 0,
  };

  // ── POWER: what the effect is worth (user 2026-07-30) ──────
  // "gib den einzelnen Effekten je nach stärkegrad auch einen powerwert, damit es
  // vergleichbar wird mit den AP."
  //
  // The AP formula used to price effects as flat surcharges — a status was worth
  // +8 whether it burned for 5 % over 3 turns or for 25 % over nine. So a
  // stronger effect was strictly free, which is the one thing a cost formula must
  // never allow. Every effect now converts to POWER, the same unit a move's
  // damage is in (basic attack = 40), and AbilityDef._derivedApCost simply adds
  // it up. See [AbilityEffect.power].
  //
  // The scale: 200 power ≈ one full health bar, because the game's calibration
  // is "a hit ≈ 20 % of max HP at power 40". Everything else is measured against
  // a lost TURN, worth about one action = 40 power.

  /// Power per 1.0 of [value], per turn for a timed effect.
  ///
  /// Three coefficients only, and each is a statement about the game:
  ///  • 200 — HP moved. A fraction of a health bar, dealt or restored.
  ///  • 40  — a TURN bent. Speed, accuracy, attack, defense and skip chance all
  ///          buy the same thing: actions, theirs or yours.
  ///  • 70  — a share of THIS hit's damage (lifesteal/recoil), which is worth
  ///          less than the same share of a health bar because it only pays out
  ///          when the hit lands.
  double get powerCoefficient => switch (family) {
    AbilityEffectFamily.heal ||
    AbilityEffectFamily.regen =>
      200,
    AbilityEffectFamily.lifesteal || AbilityEffectFamily.recoil => 70,
    AbilityEffectFamily.mainStatus => this == burn || this == poison ? 200 : 40,
    AbilityEffectFamily.debuff ||
    AbilityEffectFamily.selfBuff ||
    AbilityEffectFamily.selfPenalty =>
      40,
  };

  /// Whether this effect makes the move WORSE for its user — then its power is
  /// negative and it makes the move cheaper, which is the whole point of a cost.
  /// The old formula ignored self-costs entirely, so Power Surge's drawback was
  /// decoration.
  bool get isCost =>
      family == AbilityEffectFamily.selfPenalty ||
      family == AbilityEffectFamily.recoil;

  /// The main-status kind this maps to, or null.
  MainStatusKind? get mainStatus => switch (this) {
    burn => MainStatusKind.burn,
    poison => MainStatusKind.poison,
    frost => MainStatusKind.frost,
    fear => MainStatusKind.fear,
    sleep => MainStatusKind.sleep,
    _ => null,
  };

  /// The secondary debuff this maps to, or null.
  SecondaryDebuffKind? get debuff => switch (this) {
    blind => SecondaryDebuffKind.blind,
    slow => SecondaryDebuffKind.speedDown,
    attackDown => SecondaryDebuffKind.attackDown,
    defenseDown => SecondaryDebuffKind.defenseDown,
    _ => null,
  };

  /// The self buff this maps to, or null.
  SelfBuffKind? get selfBuff => switch (this) {
    armor => SelfBuffKind.armor,
    rage => SelfBuffKind.rage,
    haste => SelfBuffKind.haste,
    _ => null,
  };

  /// The self-cost stat this maps to, or null.
  SelfPenaltyStat? get penaltyStat => switch (this) {
    selfDefDown => SelfPenaltyStat.defense,
    selfSpeedDown => SelfPenaltyStat.speed,
    _ => null,
  };

  static AbilityEffectKind? ofMainStatus(MainStatusKind k) => switch (k) {
    MainStatusKind.burn => burn,
    MainStatusKind.poison => poison,
    MainStatusKind.frost => frost,
    MainStatusKind.fear => fear,
    MainStatusKind.sleep => sleep,
  };

  static AbilityEffectKind ofDebuff(SecondaryDebuffKind k) => switch (k) {
    SecondaryDebuffKind.blind => blind,
    SecondaryDebuffKind.speedDown => slow,
    SecondaryDebuffKind.attackDown => attackDown,
    SecondaryDebuffKind.defenseDown => defenseDown,
  };

  static AbilityEffectKind ofSelfBuff(SelfBuffKind k) => switch (k) {
    SelfBuffKind.armor => armor,
    SelfBuffKind.rage => rage,
    SelfBuffKind.haste => haste,
  };

  static AbilityEffectKind ofPenalty(SelfPenaltyStat s) =>
      s == SelfPenaltyStat.defense ? selfDefDown : selfSpeedDown;
}

/// One effect as the author set it: which, how likely, how long, how strong.
///
/// [turns] and [value] are 0 for "the catalog default" (user 2026-07-30), which
/// is what lets an existing ability keep its numbers without a backfill — and
/// what makes a deliberate change visible as a number the author typed.
class AbilityEffect {
  final AbilityEffectKind kind;

  /// 0..1. Ignored (treated as certain) for anything that does not roll — see
  /// [AbilityEffectKind.rollsChance].
  final double chance;

  /// Duration in the afflicted combatant's own turns; 0 = the default.
  final int turns;

  /// Magnitude as a positive fraction; 0 = the default.
  final double value;

  const AbilityEffect({
    required this.kind,
    this.chance = 1.0,
    this.turns = 0,
    this.value = 0,
  });

  /// The magnitude the engine will really use.
  double get resolvedValue => value > 0 ? value : kind.defaultValue;

  /// The duration the engine will really use, 0 for an untimed effect.
  int get resolvedTurns =>
      !kind.isTimed ? 0 : (turns > 0 ? turns : kind.defaultTurns);

  /// The chance the engine will really use — certain for anything that does not
  /// roll, and for a rolling effect authored at 0 (an effect that can never
  /// land is a field left blank, not a design).
  double get resolvedChance =>
      !kind.rollsChance ? 1.0 : (chance > 0 ? chance.clamp(0.0, 1.0) : 1.0);

  /// What this effect is WORTH, in the same power unit a move's damage uses
  /// (basic attack = 40) — user 2026-07-30: "damit es vergleichbar wird mit den
  /// AP". Negative for a self-cost, which makes the move cheaper.
  ///
  /// Three factors, all of them things the author typed:
  ///  • magnitude — twice the burn is twice the power.
  ///  • duration  — three turns of it is three times the power.
  ///  • CHANCE    — a 30 % burn is worth 30 % of a certain one. This is what
  ///    keeps the new pricing close to the old flat +8 for a typical move while
  ///    making a guaranteed nine-turn burn cost what it actually does.
  ///
  /// POISON is the one special case: its damage climbs by a fixed step each turn
  /// (the shape of poison, not a magnitude), so its power is the real total over
  /// its run rather than value × turns.
  double get power {
    final turnsFactor = kind.isTimed ? resolvedTurns : 1;
    var magnitude = resolvedValue * turnsFactor;
    if (kind == AbilityEffectKind.poison) {
      final step = statusDotFraction(MainStatusKind.poison, 1) -
          statusDotFraction(MainStatusKind.poison, 0);
      final t = resolvedTurns;
      magnitude = resolvedValue * t + step * (t * (t - 1) / 2);
    }
    final p = magnitude * kind.powerCoefficient * resolvedChance;
    return kind.isCost ? -p : p;
  }

  AbilityEffect copyWith({
    AbilityEffectKind? kind,
    double? chance,
    int? turns,
    double? value,
  }) => AbilityEffect(
    kind: kind ?? this.kind,
    chance: chance ?? this.chance,
    turns: turns ?? this.turns,
    value: value ?? this.value,
  );
}

String _pct(double v) {
  final p = v * 100;
  final r = (p * 10).round() / 10;
  return r == r.roundToDouble() ? '${r.round()} %' : '$r %';
}

String _turns(int n) => n == 1 ? '1 turn' : '$n turns';

/// EXACTLY what [e] does in a fight, in sentences — the answer to "was bedeutet
/// dies im Kampf" (user 2026-07-30).
///
/// States three things on purpose: what the authored number buys, what comes
/// with the effect and is NOT authorable (burn also saps attack; frost can skip
/// a turn on its own), and the RULE that decides whether it lands at all. The
/// second kind is what the old form hid completely — picking "Burn" quietly
/// bought a −20 % attack debuff nobody could see.
List<String> describeAbilityEffect(AbilityEffect e) {
  final v = e.resolvedValue;
  final t = e.resolvedTurns;
  final out = <String>[];
  switch (e.kind) {
    case AbilityEffectKind.burn:
      out.add('Deals ${_pct(v)} of the target\'s MAX HP at the end of each of '
          'its turns, for ${_turns(t)}.');
      out.add('While burning it also attacks for '
          '${_pct(1 - statusAttackMult(MainStatusKind.burn))} less (fixed).');
    case AbilityEffectKind.poison:
      final step = statusDotFraction(MainStatusKind.poison, 1) -
          statusDotFraction(MainStatusKind.poison, 0);
      out.add('Deals ${_pct(v)} of MAX HP at the end of the target\'s turn and '
          '${_pct(step)} MORE every turn after that, for ${_turns(t)} — '
          '${_pct(v + step * (t - 1))} on the last one.');
      out.add('Total over its full run: about '
          '${_pct(v * t + step * (t * (t - 1) / 2))} of max HP.');
    case AbilityEffectKind.frost:
      out.add('The target loses ${_pct(v)} SPEED for ${_turns(t)} — it acts '
          'that much less often in the turn order.');
      out.add('It also has a '
          '${_pct(statusSkipChance(MainStatusKind.frost))} chance to lose each '
          'of those turns entirely (fixed).');
    case AbilityEffectKind.fear:
      out.add('The target loses each of its next $t turns with a ${_pct(v)} '
          'chance — rolled again at the start of every one of them.');
      out.add('No damage and no stat change: fear only steals turns.');
    case AbilityEffectKind.sleep:
      out.add('The target loses each of its next $t turns with a ${_pct(v)} '
          'chance — rolled again at the start of every one of them.');
      out.add('The heaviest turn-eater there is: at this chance it is out of the '
          'fight for most of $t turns, which is why it is short.');
    case AbilityEffectKind.attackDown:
      out.add('The target deals ${_pct(v)} LESS damage for ${_turns(t)}.');
      out.add('Stacks with a burn\'s own attack sap — a burned, weakened '
          'monster hits for very little.');
    case AbilityEffectKind.defenseDown:
      out.add('The target TAKES more damage for ${_turns(t)}: it defends with '
          '${_pct(v)} less.');
      out.add('The support move for a party: it multiplies what everyone else '
          'does to that target, not what you do.');
    case AbilityEffectKind.regen:
      out.add('The USER heals ${_pct(v)} of its max HP at the end of each of '
          'its own turns, for ${_turns(t)} — ${_pct(v * t)} in total if it '
          'survives that long.');
      out.add('Nothing interrupts it and nothing stacks it: re-using the move '
          'refreshes the timer.');
    case AbilityEffectKind.recoil:
      out.add('COST: the user takes ${_pct(v)} of the damage it just dealt. A '
          'miss costs nothing, and it can knock the user out.');
    case AbilityEffectKind.blind:
      out.add('The target\'s attacks miss ${_pct(v)} more often for '
          '${_turns(t)}.');
    case AbilityEffectKind.slow:
      out.add('The target loses ${_pct(v)} SPEED for ${_turns(t)} — it acts '
          'that much less often in the turn order.');
    case AbilityEffectKind.heal:
      out.add('Restores ${_pct(v)} of the TARGET\'s max HP at once. Never '
          'above full, and it cannot revive a K.O.\'d monster.');
    case AbilityEffectKind.lifesteal:
      out.add('The user heals ${_pct(v)} of the damage this move actually '
          'dealt — so a blocked or missed hit heals nothing.');
    case AbilityEffectKind.armor:
      out.add('The USER takes less damage for ${_turns(t)}: +${_pct(v)} '
          'defense.');
    case AbilityEffectKind.rage:
      out.add('The USER deals more damage for ${_turns(t)}: +${_pct(v)} '
          'attack.');
    case AbilityEffectKind.haste:
      out.add('The USER acts more often for ${_turns(t)}: +${_pct(v)} speed.');
    case AbilityEffectKind.selfDefDown:
      out.add('COST: the user loses ${_pct(v)} defense for ${_turns(t)} — no '
          'roll, it always happens.');
    case AbilityEffectKind.selfSpeedDown:
      out.add('COST: the user loses ${_pct(v)} speed for ${_turns(t)} — no '
          'roll, it always happens.');
  }
  // The rule that decides whether it lands at all.
  switch (e.kind.family) {
    case AbilityEffectFamily.mainStatus:
      out.add('Lands on a ${_pct(e.resolvedChance)} roll, and ONLY if the '
          'target carries no other main status (burn/frost/poison/fear are '
          'mutually exclusive) — a second attempt on an afflicted target is '
          'simply wasted.');
    case AbilityEffectFamily.debuff:
      out.add('Lands on a ${_pct(e.resolvedChance)} roll. It stacks alongside a '
          'main status; re-applying only refreshes the duration.');
    case AbilityEffectFamily.selfBuff:
      out.add('Always lands. Coexists with the user\'s other buffs; '
          're-applying refreshes the duration instead of stacking.');
    case AbilityEffectFamily.heal:
    case AbilityEffectFamily.lifesteal:
      out.add('Always applies — nothing to roll and nothing to expire.');
    case AbilityEffectFamily.selfPenalty:
      out.add('A move carries ONE self-cost; it replaces any earlier one.');
    case AbilityEffectFamily.regen:
      out.add('Always lands on the user.');
    case AbilityEffectFamily.recoil:
      out.add('Always applies, on every target the move hits.');
  }
  return out;
}

/// The one-line form of [describeAbilityEffect] — for a list row or a tooltip.
String summariseAbilityEffect(AbilityEffect e) {
  final v = _pct(e.resolvedValue);
  final t = e.resolvedTurns;
  final chance = e.kind.rollsChance && e.resolvedChance < 1
      ? ' · ${_pct(e.resolvedChance)}'
      : '';
  final dur = e.kind.isTimed ? ' · ${_turns(t)}' : '';
  return '${e.kind.emoji} ${e.kind.label} $v$dur$chance';
}
