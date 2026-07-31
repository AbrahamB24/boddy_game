import 'ability_effects.dart';
import 'creature_enums.dart';
import 'status_effects.dart';

// The effect LIST and the words for it live next door (user 2026-07-30) and are
// re-exported here: every reader of an ability already imports this file, and a
// def's effects are not a separate concept from the def.
export 'ability_effects.dart';

/// What an ability fundamentally does — and therefore WHICH EFFECTS it can
/// carry: `damage` rolls ATK vs. DEF (no physical/magic split, per the balance
/// pass), `heal` restores HP with no damage component, `buff` acts on the user.
///
/// The KIND is the frame; the effects are the content, and they are a flat list
/// on top of it rather than three shapes of ability (see [AbilityDef.effects],
/// user 2026-07-30). A damage move is what can land a status, a debuff, lifesteal
/// or recoil, because those need a hit to land with; a heal or a buff is what can
/// leave a regeneration behind. AbilityDefForm._allows is the single table of
/// which effect fits which kind, and it drops what cannot fire rather than
/// saving a move that quietly does less than it says.
enum AbilityKind {
  damage('Damage'),
  heal('Heal'),
  buff('Self Buff');

  final String label;
  const AbilityKind(this.label);

  static AbilityKind fromName(String? name) =>
      AbilityKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => AbilityKind.damage,
      );
}

enum AbilityTarget {
  enemy('One Enemy'),
  allEnemies('All Enemies'),
  ally('One Ally'),
  allAllies('All Allies'),
  self('Self');

  final String label;
  const AbilityTarget(this.label);

  static AbilityTarget fromName(String? name) => AbilityTarget.values
      .firstWhere((t) => t.name == name, orElse: () => AbilityTarget.enemy);
}

// Abilities are their own dev-editable defs (not embedded in species) so one
// ability — "Biss", "Funke" — can be assigned to several species without
// duplicating its numbers. Species reference them by id with an unlock
// stage (see SpeciesAbility).
class AbilityDef {
  final String id;
  final String name;
  final String description;

  /// The ability's TYPE — every ability has one (user request). It drives both
  /// STAB and the type-effectiveness multiplier, i.e. an ability is the ONLY
  /// thing that lands bonus damage. The basic `Attack` is deliberately typeless
  /// (see CombatEngine.basicAttack) so it never gets that bonus.
  final CreatureElement element;
  final AbilityKind kind;
  final AbilityTarget target;

  /// Damage magnitude (`kind == damage`), scaled by the user's ATK stat in
  /// the combat formula. Unused for heal/buff.
  final int power;

  /// CTB queue nudge: a priority move pulls the user's NEXT turn forward a
  /// bit (approximating discrete priority tiers inside the continuous CTB
  /// queue we kept — see combat_engine.dart's _priorityNudgeFactor). 0 =
  /// normal move.
  final int priority;

  /// `kind == heal`: heals this fraction of the TARGET's max HP — which for a
  /// self-targeted move is the user, but for `ally`/`allAllies` it is each ally's
  /// own maximum (see CombatEngine.useAbility). 0 for non-heal kinds.
  ///
  /// The doc said "the user's own max HP" for as long as heals have been
  /// targetable, which made a party heal look like it scaled off the healer.
  final double healPct;

  /// `kind == damage` only: heals the ATTACKER this fraction of the damage
  /// just dealt (Aderlass 0.30, Wurzelgriff 0.25). 0 = no lifesteal.
  final double lifestealPct;

  /// `kind == damage` only: chance to inflict this main status on the target
  /// (burn/frost/poison/fear/sleep — mutually exclusive with whatever status the
  /// target already has).
  final MainStatusKind? inflictMain;
  final double inflictMainChance;

  /// THIS move's own duration and magnitude for the status above — 0 = the
  /// game-wide catalog value (user 2026-07-30: "Dauer (0 default …), Wert des
  /// Effekts (bsp wieviel HP burn verursacht)").
  ///
  /// Before this, every burn in the game was the same burn: the numbers lived in
  /// status_effects.dart as constants, so two fire moves could differ in power
  /// and in nothing else. The catalog is still the default, which is why no
  /// existing ability changed when these arrived.
  ///
  /// [inflictMainValue] is a POSITIVE FRACTION of "how much", never a
  /// multiplier — damage per turn for burn/poison, speed lost for frost, chance
  /// to lose the turn for fear. See AbilityEffectKind.valueLabel.
  final int inflictMainTurns;
  final double inflictMainValue;

  /// `kind == damage` only: chance to inflict this secondary debuff on the
  /// target (blind / slow / attack-down / defense-down — each stacks
  /// independently of the main status).
  final SecondaryDebuffKind? inflictDebuff;
  final double inflictDebuffChance;

  /// This move's own duration and magnitude for the debuff — 0 = catalog
  /// default. The value is what the target LOSES: accuracy (blind), speed
  /// (slow), attack (weaken) or defense (expose).
  final int inflictDebuffTurns;
  final double inflictDebuffValue;

  /// `kind == buff` only: which of the 3 named self buffs this applies (a buff
  /// move may also carry a regeneration — see [regenValue]).
  final SelfBuffKind? selfBuff;

  /// This move's own duration and magnitude for that buff — 0 = catalog
  /// default. The value is the stat GAINED (0.30 = +30 %).
  final int selfBuffTurns;
  final double selfBuffValue;

  /// A one-off cost-of-use penalty the user inflicts on THEMSELVES
  /// (Kraftakt: -10% Def 1 turn; Gaia-Zorn: -Speed next turn). Always
  /// applies (no chance roll) when the ability is used.
  final SelfPenaltyStat? selfPenaltyStat;
  final double selfPenaltyMult;
  final int selfPenaltyTurns;

  /// REGENERATION on the user (user 2026-07-30, Pokémon-flavoured): heals this
  /// fraction of its max HP at the end of each of its own turns, for
  /// [regenTurns]. 0 = the move has none.
  ///
  /// Its own pair of fields rather than a reuse of [healPct]: a Wish and a
  /// straight heal are different moves, and a move can carry both.
  final double regenValue;
  final int regenTurns;

  /// RECOIL (Double-Edge): the user takes this fraction of the damage it just
  /// dealt. 0 = none. Not timed — it happens with the hit.
  final double recoilValue;

  /// Author-set AP cost (Dev Mode, user request). 0 = AUTO: derive it from
  /// power/effects (the original rule, see [_derivedApCost]). >0 = use this
  /// exact value (clamped 1..[kMaxActionPoints]). Either way it is capped per
  /// species-assignment so a starting ability stays affordable — see
  /// Combatant._resolveAbilities.
  final int apCost;

  const AbilityDef({
    required this.id,
    required this.name,
    this.description = '',
    required this.element,
    required this.kind,
    required this.target,
    this.power = 0,
    this.priority = 0,
    this.healPct = 0,
    this.lifestealPct = 0,
    this.inflictMain,
    this.inflictMainChance = 0,
    this.inflictMainTurns = 0,
    this.inflictMainValue = 0,
    this.inflictDebuff,
    this.inflictDebuffChance = 0,
    this.inflictDebuffTurns = 0,
    this.inflictDebuffValue = 0,
    this.selfBuff,
    this.selfBuffTurns = 0,
    this.selfBuffValue = 0,
    this.selfPenaltyStat,
    this.selfPenaltyMult = 1.0,
    this.selfPenaltyTurns = 1,
    this.regenValue = 0,
    this.regenTurns = 0,
    this.recoilValue = 0,
    this.apCost = 0,
  });

  // ── The effect LIST (user 2026-07-30) ──────────────────────
  // "Effekt wählen (alle effekte in einer Liste)". The author picks from one
  // list; the fields above are where those picks are STORED, and the mapping is
  // one-to-one, so nothing changed about the row format or the engine.
  //
  // The slots also carry the rules that make the list finite: ONE per family —
  // one main status (they are mutually exclusive on the target anyway), one
  // debuff, one buff, one heal, one lifesteal, one regeneration, one recoil, one
  // self-cost. Add a second burn to a move and the engine could only ever apply
  // one of them, so the list refuses it the same way — see [withEffects].

  /// Every effect this ability carries, as the form shows them.
  List<AbilityEffect> get effects => [
    if (inflictMain != null)
      AbilityEffect(
        kind: AbilityEffectKind.ofMainStatus(inflictMain!)!,
        chance: inflictMainChance,
        turns: inflictMainTurns,
        value: inflictMainValue,
      ),
    if (inflictDebuff != null)
      AbilityEffect(
        kind: AbilityEffectKind.ofDebuff(inflictDebuff!),
        chance: inflictDebuffChance,
        turns: inflictDebuffTurns,
        value: inflictDebuffValue,
      ),
    if (healPct > 0)
      AbilityEffect(kind: AbilityEffectKind.heal, value: healPct),
    if (lifestealPct > 0)
      AbilityEffect(kind: AbilityEffectKind.lifesteal, value: lifestealPct),
    if (selfBuff != null)
      AbilityEffect(
        kind: AbilityEffectKind.ofSelfBuff(selfBuff!),
        turns: selfBuffTurns,
        value: selfBuffValue,
      ),
    if (regenValue > 0)
      AbilityEffect(
        kind: AbilityEffectKind.regen,
        turns: regenTurns,
        value: regenValue,
      ),
    if (recoilValue > 0)
      AbilityEffect(kind: AbilityEffectKind.recoil, value: recoilValue),
    if (selfPenaltyStat != null)
      AbilityEffect(
        kind: AbilityEffectKind.ofPenalty(selfPenaltyStat!),
        turns: selfPenaltyTurns,
        // Stored as the MULTIPLIER it has always been (0.90); the list speaks in
        // "how much is lost", so the two convert here rather than in the form.
        value: (1 - selfPenaltyMult).clamp(0.0, 1.0),
      ),
  ];

  /// This ability with [list] as its effects — the write side of [effects].
  /// LAST ONE WINS per family, which is what makes "one main status per move"
  /// true by construction instead of by a validation message.
  AbilityDef withEffects(List<AbilityEffect> list) {
    AbilityEffect? of(AbilityEffectFamily f) {
      AbilityEffect? found;
      for (final e in list) {
        if (e.kind.family == f) found = e;
      }
      return found;
    }

    final main = of(AbilityEffectFamily.mainStatus);
    final debuff = of(AbilityEffectFamily.debuff);
    final buff = of(AbilityEffectFamily.selfBuff);
    final heal = of(AbilityEffectFamily.heal);
    final steal = of(AbilityEffectFamily.lifesteal);
    final cost = of(AbilityEffectFamily.selfPenalty);
    final regen = of(AbilityEffectFamily.regen);
    final recoil = of(AbilityEffectFamily.recoil);
    return AbilityDef(
      id: id,
      name: name,
      description: description,
      element: element,
      kind: kind,
      target: target,
      power: power,
      priority: priority,
      healPct: heal?.resolvedValue ?? 0,
      lifestealPct: steal?.resolvedValue ?? 0,
      inflictMain: main?.kind.mainStatus,
      inflictMainChance: main?.resolvedChance ?? 0,
      inflictMainTurns: main?.turns ?? 0,
      inflictMainValue: main?.value ?? 0,
      inflictDebuff: debuff?.kind.debuff,
      inflictDebuffChance: debuff?.resolvedChance ?? 0,
      inflictDebuffTurns: debuff?.turns ?? 0,
      inflictDebuffValue: debuff?.value ?? 0,
      selfBuff: buff?.kind.selfBuff,
      selfBuffTurns: buff?.turns ?? 0,
      selfBuffValue: buff?.value ?? 0,
      selfPenaltyStat: cost?.kind.penaltyStat,
      selfPenaltyMult: cost == null ? 1.0 : 1 - cost.resolvedValue,
      selfPenaltyTurns: cost?.resolvedTurns ?? 1,
      regenValue: regen?.resolvedValue ?? 0,
      regenTurns: regen?.turns ?? 0,
      recoilValue: recoil?.resolvedValue ?? 0,
      apCost: apCost,
    );
  }

  /// The AP this move costs: the author's explicit [apCost] when set, else the
  /// value derived from power/effects. (CombatEngine.abilityApCost delegates
  /// here.)
  int get resolvedApCost =>
      apCost > 0 ? apCost.clamp(1, kMaxActionPoints) : _derivedApCost;

  /// The move's total POWER — its damage plus what every effect on it is worth,
  /// in one unit (user 2026-07-30: "gib den einzelnen Effekten je nach
  /// stärkegrad auch einen powerwert, damit es vergleichbar wird mit den AP").
  ///
  /// This is the number [_derivedApCost] prices, and the number the Dev-Mode form
  /// shows per effect and as a total. A self-cost counts NEGATIVE — see
  /// [AbilityEffect.power].
  double get totalPower {
    var total = kind == AbilityKind.damage ? power.toDouble() : 0.0;
    for (final e in effects) {
      total += e.power;
    }
    return total;
  }

  /// Cost ≈ power / 13, clamped 2–[kMaxActionPoints].
  ///
  /// Effects used to be FLAT surcharges here: +8 for a status, +8 for a debuff,
  /// +20 for any lifesteal, and a status move was then clamped to 4 AP however
  /// strong it was. Once a move could set its own duration and magnitude
  /// (2026-07-30) that became a hole with a floor under it — a nine-turn burn at
  /// triple damage cost exactly what a standard one did. Every effect is worth
  /// its own power now, chance included, so the clamp is gone and the price
  /// follows the move.
  ///
  /// Typical authored moves barely moved: a status at a 30 % chance prices out
  /// near the old +8. What DID get dearer is precisely what should — the
  /// guaranteed, long, heavy effects that were free before.
  int get _derivedApCost {
    final strength = totalPower + kPriorityPower * priority;
    // ONE exchange rate for every ability (a dial since 2026-07-30 — it used to
    // be a bare 13 in here, which made the number governing every cost in the
    // game the one number Dev Mode could not turn).
    final raw = (strength / kPowerPerAp).round();
    // A buff's FLOOR is its own dial (user 2026-07-17: buffs should be something
    // you want to play). It used to be its fixed PRICE, which quietly made the
    // dial inert the moment effects carried power: a stock Haste and a +60 %/
    // 4-turn one both cost 2.
    final floor = kind == AbilityKind.buff ? kBuffApCost : kMinAbilityApCost;
    return raw.clamp(floor, kMaxActionPoints);
  }

  /// Whether this move is stronger than the largest AP pool can pay for — then
  /// its price is pinned at [kMaxActionPoints] and every point of power above
  /// [kMaxPricedPower] is FREE.
  ///
  /// Exactly the hole the flat effect surcharges left, one step further out, so
  /// it is reported rather than hidden: the ability form says so, and says by how
  /// much. Only meaningful on an auto-priced move — an explicit [apCost] is the
  /// author overruling the formula on purpose.
  bool get isOverPricedOut => apCost == 0 && totalPower > kMaxPricedPower;

  /// A copy with a forced explicit [apCost] — used to cap a starting ability to
  /// its unlock stage's AP ceiling (Combatant._resolveAbilities).
  AbilityDef withApCost(int cost) => AbilityDef(
    id: id,
    name: name,
    description: description,
    element: element,
    kind: kind,
    target: target,
    power: power,
    priority: priority,
    healPct: healPct,
    lifestealPct: lifestealPct,
    inflictMain: inflictMain,
    inflictMainChance: inflictMainChance,
    inflictMainTurns: inflictMainTurns,
    inflictMainValue: inflictMainValue,
    inflictDebuff: inflictDebuff,
    inflictDebuffChance: inflictDebuffChance,
    inflictDebuffTurns: inflictDebuffTurns,
    inflictDebuffValue: inflictDebuffValue,
    selfBuff: selfBuff,
    selfBuffTurns: selfBuffTurns,
    selfBuffValue: selfBuffValue,
    selfPenaltyStat: selfPenaltyStat,
    selfPenaltyMult: selfPenaltyMult,
    selfPenaltyTurns: selfPenaltyTurns,
    regenValue: regenValue,
    regenTurns: regenTurns,
    recoilValue: recoilValue,
    apCost: cost,
  );

  factory AbilityDef.fromDefRow(Map<String, dynamic> row) => AbilityDef(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    description: row['description'] as String? ?? '',
    // Every ability has a type now (user request). A legacy row with no element
    // was "universal" → that maps to the new NEUTRAL type (no bonus damage);
    // named elements parse as before.
    element: row['element'] == null
        ? CreatureElement.neutral
        : CreatureElement.fromName(row['element'] as String),
    kind: AbilityKind.fromName(row['kind'] as String?),
    target: AbilityTarget.fromName(row['target'] as String?),
    power: (row['power'] as num?)?.toInt() ?? 0,
    priority: (row['priority'] as num?)?.toInt() ?? 0,
    healPct: (row['heal_pct'] as num?)?.toDouble() ?? 0,
    lifestealPct: (row['lifesteal_pct'] as num?)?.toDouble() ?? 0,
    inflictMain: row['inflict_main'] == null
        ? null
        : MainStatusKind.values.firstWhere(
            (k) => k.name == row['inflict_main'],
            orElse: () => MainStatusKind.burn,
          ),
    inflictMainChance: (row['inflict_main_chance'] as num?)?.toDouble() ?? 0,
    // 0 (or a pre-0031 row with no column) = the catalog default, so every
    // ability authored before per-move numbers existed keeps its old behaviour.
    inflictMainTurns: (row['inflict_main_turns'] as num?)?.toInt() ?? 0,
    inflictMainValue: (row['inflict_main_value'] as num?)?.toDouble() ?? 0,
    inflictDebuff: row['inflict_debuff'] == null
        ? null
        : SecondaryDebuffKind.values.firstWhere(
            (k) => k.name == row['inflict_debuff'],
            orElse: () => SecondaryDebuffKind.blind,
          ),
    inflictDebuffChance:
        (row['inflict_debuff_chance'] as num?)?.toDouble() ?? 0,
    inflictDebuffTurns: (row['inflict_debuff_turns'] as num?)?.toInt() ?? 0,
    inflictDebuffValue: (row['inflict_debuff_value'] as num?)?.toDouble() ?? 0,
    selfBuff: row['self_buff'] == null
        ? null
        : SelfBuffKind.values.firstWhere(
            (k) => k.name == row['self_buff'],
            orElse: () => SelfBuffKind.armor,
          ),
    selfBuffTurns: (row['self_buff_turns'] as num?)?.toInt() ?? 0,
    selfBuffValue: (row['self_buff_value'] as num?)?.toDouble() ?? 0,
    selfPenaltyStat: row['self_penalty_stat'] == null
        ? null
        : SelfPenaltyStat.values.firstWhere(
            (s) => s.name == row['self_penalty_stat'],
            orElse: () => SelfPenaltyStat.defense,
          ),
    selfPenaltyMult: (row['self_penalty_mult'] as num?)?.toDouble() ?? 1.0,
    selfPenaltyTurns: (row['self_penalty_turns'] as num?)?.toInt() ?? 1,
    // Absent on a pre-0032 row → the move simply has no regen/recoil.
    regenValue: (row['regen_value'] as num?)?.toDouble() ?? 0,
    regenTurns: (row['regen_turns'] as num?)?.toInt() ?? 0,
    recoilValue: (row['recoil_value'] as num?)?.toDouble() ?? 0,
    // 0 (or a pre-migration row with no column) = auto-derive.
    apCost: (row['ap_cost'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toDefRow() => {
    'id': id,
    'name': name,
    'description': description,
    'element': element.name,
    'kind': kind.name,
    'target': target.name,
    'power': power,
    'priority': priority,
    'heal_pct': healPct,
    'lifesteal_pct': lifestealPct,
    'inflict_main': inflictMain?.name,
    'inflict_main_chance': inflictMainChance,
    'inflict_main_turns': inflictMainTurns,
    'inflict_main_value': inflictMainValue,
    'inflict_debuff': inflictDebuff?.name,
    'inflict_debuff_chance': inflictDebuffChance,
    'inflict_debuff_turns': inflictDebuffTurns,
    'inflict_debuff_value': inflictDebuffValue,
    'self_buff': selfBuff?.name,
    'self_buff_turns': selfBuffTurns,
    'self_buff_value': selfBuffValue,
    'self_penalty_stat': selfPenaltyStat?.name,
    'self_penalty_mult': selfPenaltyMult,
    'self_penalty_turns': selfPenaltyTurns,
    'regen_value': regenValue,
    'regen_turns': regenTurns,
    'recoil_value': recoilValue,
    'ap_cost': apCost,
  };
}

/// Live ability defs, loaded from Supabase by CreatureDefsController (same
/// in-place-overwrite pattern as kBuildingDefs). Empty until the DB rows
/// exist — there is no bundled fallback content for creatures.
final Map<String, AbilityDef> kAbilityDefs = {};
