import 'creature_enums.dart';
import 'status_effects.dart';

/// What an ability fundamentally does. `damage` always rolls ATK vs. DEF
/// (no physical/magic split, per the balance pass); `heal` restores a flat
/// % of max HP with no damage component; `buff` applies one of the 3 named
/// self buffs. Status infliction, lifesteal and self-penalties are optional
/// add-ons layered onto a `damage` move (see fields below), not separate
/// kinds — matching how the balance doc's move pool actually composes them
/// (e.g. Bloodletting = damage + lifesteal; Prism Beam = damage + blind%).
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

  /// null = universal/elementless (no STAB, no element multiplier).
  final CreatureElement? element;
  final AbilityKind kind;
  final AbilityTarget target;

  /// Energy burned on use. The 4 balance-pass cost classes (Basis 0 /
  /// Standard 18 / Stark 35 / Ultimate 65) are a naming convention for
  /// content authors — this field just holds whatever value was set.
  final int energyCost;

  /// Damage magnitude (`kind == damage`), scaled by the user's ATK stat in
  /// the combat formula. Unused for heal/buff.
  final int power;

  /// CTB queue nudge: a priority move pulls the user's NEXT turn forward a
  /// bit (approximating discrete priority tiers inside the continuous CTB
  /// queue we kept — see combat_engine.dart's _priorityNudgeFactor). 0 =
  /// normal move.
  final int priority;

  /// `kind == heal`: heals this fraction of the user's own max HP
  /// (Regeneration = 0.35). 0 for non-heal kinds.
  final double healPct;

  /// `kind == damage` only: heals the ATTACKER this fraction of the damage
  /// just dealt (Aderlass 0.30, Wurzelgriff 0.25). 0 = no lifesteal.
  final double lifestealPct;

  /// `kind == damage` only: chance to inflict this main status on the
  /// target (burn/frost/poison/fear — mutually exclusive with whatever
  /// status the target already has).
  final MainStatusKind? inflictMain;
  final double inflictMainChance;

  /// `kind == damage` only: chance to inflict this secondary debuff on the
  /// target (blind/speed-down — stacks independently of main status).
  final SecondaryDebuffKind? inflictDebuff;
  final double inflictDebuffChance;

  /// `kind == buff` only: which of the 3 named self buffs this applies.
  final SelfBuffKind? selfBuff;

  /// A one-off cost-of-use penalty the user inflicts on THEMSELVES
  /// (Kraftakt: -10% Def 1 turn; Gaia-Zorn: -Speed next turn). Always
  /// applies (no chance roll) when the ability is used.
  final SelfPenaltyStat? selfPenaltyStat;
  final double selfPenaltyMult;
  final int selfPenaltyTurns;

  const AbilityDef({
    required this.id,
    required this.name,
    this.description = '',
    this.element,
    required this.kind,
    required this.target,
    required this.energyCost,
    this.power = 0,
    this.priority = 0,
    this.healPct = 0,
    this.lifestealPct = 0,
    this.inflictMain,
    this.inflictMainChance = 0,
    this.inflictDebuff,
    this.inflictDebuffChance = 0,
    this.selfBuff,
    this.selfPenaltyStat,
    this.selfPenaltyMult = 1.0,
    this.selfPenaltyTurns = 1,
  });

  factory AbilityDef.fromDefRow(Map<String, dynamic> row) => AbilityDef(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    description: row['description'] as String? ?? '',
    element: row['element'] == null
        ? null
        : CreatureElement.fromName(row['element'] as String),
    kind: AbilityKind.fromName(row['kind'] as String?),
    target: AbilityTarget.fromName(row['target'] as String?),
    energyCost: (row['energy_cost'] as num?)?.toInt() ?? 0,
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
    inflictDebuff: row['inflict_debuff'] == null
        ? null
        : SecondaryDebuffKind.values.firstWhere(
            (k) => k.name == row['inflict_debuff'],
            orElse: () => SecondaryDebuffKind.blind,
          ),
    inflictDebuffChance:
        (row['inflict_debuff_chance'] as num?)?.toDouble() ?? 0,
    selfBuff: row['self_buff'] == null
        ? null
        : SelfBuffKind.values.firstWhere(
            (k) => k.name == row['self_buff'],
            orElse: () => SelfBuffKind.armor,
          ),
    selfPenaltyStat: row['self_penalty_stat'] == null
        ? null
        : SelfPenaltyStat.values.firstWhere(
            (s) => s.name == row['self_penalty_stat'],
            orElse: () => SelfPenaltyStat.defense,
          ),
    selfPenaltyMult: (row['self_penalty_mult'] as num?)?.toDouble() ?? 1.0,
    selfPenaltyTurns: (row['self_penalty_turns'] as num?)?.toInt() ?? 1,
  );

  Map<String, dynamic> toDefRow() => {
    'id': id,
    'name': name,
    'description': description,
    'element': element?.name,
    'kind': kind.name,
    'target': target.name,
    'energy_cost': energyCost,
    'power': power,
    'priority': priority,
    'heal_pct': healPct,
    'lifesteal_pct': lifestealPct,
    'inflict_main': inflictMain?.name,
    'inflict_main_chance': inflictMainChance,
    'inflict_debuff': inflictDebuff?.name,
    'inflict_debuff_chance': inflictDebuffChance,
    'self_buff': selfBuff?.name,
    'self_penalty_stat': selfPenaltyStat?.name,
    'self_penalty_mult': selfPenaltyMult,
    'self_penalty_turns': selfPenaltyTurns,
  };
}

/// Live ability defs, loaded from Supabase by CreatureDefsController (same
/// in-place-overwrite pattern as kBuildingDefs). Empty until the DB rows
/// exist — there is no bundled fallback content for creatures.
final Map<String, AbilityDef> kAbilityDefs = {};
