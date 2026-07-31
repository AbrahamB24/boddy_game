import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/dev/dev_theme.dart';
import '../models/ability_def.dart';
import '../models/creature_enums.dart';
import '../services/combat_engine.dart' show CombatEngine;
import '../services/creature_defs_service.dart';

// Create/edit form for one AbilityDef. Same conventions as BuildingDefForm:
// `existing == null` = new (id editable, free-typed — single trusted author).
// Fields shown depend on `kind`: damage moves get power/priority/lifesteal/
// status-infliction/self-penalty; heal moves get healPct; buff moves get a
// self-buff pick.
class AbilityDefForm extends StatefulWidget {
  final AbilityDef? existing;
  const AbilityDefForm({super.key, this.existing});

  @override
  State<AbilityDefForm> createState() => _AbilityDefFormState();
}

class _AbilityDefFormState extends State<AbilityDefForm> {
  final _svc = CreatureDefsService();
  bool _saving = false;

  late String _id;
  late String _name;
  late String _description;
  late CreatureElement _element;
  late AbilityKind _kind;
  late AbilityTarget _target;
  late int _power;
  late int _priority;
  late int _apCost;
  /// EVERY effect this ability carries, in one editable list (user 2026-07-30:
  /// "Effekt wählen (alle effekte in einer Liste)").
  ///
  /// The four separate pickers this replaced — main status, secondary debuff,
  /// self buff, self-cost — asked the author to know the engine's internal
  /// families before choosing anything, and heal/lifesteal were numbers in a
  /// different part of the form entirely. AbilityDef.effects / withEffects map
  /// this list onto those slots, so the storage and the engine are untouched.
  late List<AbilityEffect> _effects;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _description = d?.description ?? '';
    _element = d?.element ?? CreatureElement.neutral;
    _kind = d?.kind ?? AbilityKind.damage;
    _target = d?.target ?? AbilityTarget.enemy;
    _power = d?.power ?? 70;
    _priority = d?.priority ?? 0;
    _apCost = d?.apCost ?? 0;
    _effects = [...?d?.effects];
  }

  /// The def as the form currently stands — the ONE place the fields turn back
  /// into an ability, so the save button and the live "what this does" preview
  /// can never describe different things.
  AbilityDef get _draft => AbilityDef(
    id: _id.trim(),
    name: _name.trim(),
    description: _description.trim(),
    element: _element,
    kind: _kind,
    target: _target,
    power: _kind == AbilityKind.damage ? _power : 0,
    priority: _priority,
    apCost: _apCost,
  ).withEffects(_allowedEffects);

  /// The effects this KIND can actually carry. A heal move that also burns would
  /// silently never burn (the engine only rolls infliction on a damage hit), so
  /// the form drops what cannot fire instead of saving a lie — and says so in the
  /// list, rather than in a snackbar after the fact.
  List<AbilityEffect> get _allowedEffects =>
      [for (final e in _effects) if (_allows(e.kind)) e];

  bool _allows(AbilityEffectKind kind) => switch (kind.family) {
    // Landing something on the target needs a hit to land it with.
    AbilityEffectFamily.mainStatus ||
    AbilityEffectFamily.debuff ||
    AbilityEffectFamily.lifesteal ||
    AbilityEffectFamily.recoil ||
    AbilityEffectFamily.selfPenalty =>
      _kind == AbilityKind.damage,
    AbilityEffectFamily.heal => _kind == AbilityKind.heal,
    AbilityEffectFamily.selfBuff => _kind == AbilityKind.buff,
    // A trickle of healing is something you set up, on either kind of
    // supporting move (user 2026-07-30) — a Wish or a hardening stance.
    AbilityEffectFamily.regen =>
      _kind == AbilityKind.heal || _kind == AbilityKind.buff,
  };

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    setState(() => _saving = true);
    final def = _draft;
    try {
      await _svc.upsertAbilityDef(def);
      // Return the saved id so a caller (e.g. the species form's inline
      // "New ability") can assign it straight away.
      if (mounted) Navigator.pop(context, def.id);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete ability?',
      message:
          'This removes "$_id" for every player immediately. Species still '
          'referencing it will simply skip it.',
    );
    if (!ok) return;
    await _svc.deleteAbilityDef(_id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildDevModeTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isNew ? 'New Ability' : 'Edit Ability',
            style: FoE.title(size: 16),
          ),
          actions: [
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            // ── Three blocks, in the order you fill them (user 2026-07-30: "Das
            // Menü darf noch übersichtlicher werden") ──
            // WHAT IT IS · HOW IT HITS · WHAT IT DOES. The fields were one flat
            // run of eleven inputs where the identity, the combat maths and the
            // effects were indistinguishable, and the effects — the interesting
            // part — sat at the very bottom behind four separate pickers.
            _sectionLabel('What it is'),
            _textRow(
              'Id (slug, e.g. flammenstoss)',
              _id,
              enabled: _isNew,
              onChanged: (v) => _id = v,
            ),
            _textRow('Name', _name, onChanged: (v) => _name = v),
            _textRow(
              'Description (shown to the player)',
              _description,
              onChanged: (v) => _description = v,
            ),
            _sectionLabel('How it hits'),
            _dropdownRow<AbilityKind>(
              'Kind',
              _kind,
              AbilityKind.values
                  .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                  .toList(),
              (v) => setState(() => _kind = v ?? _kind),
            ),
            const SizedBox(height: 12),
            _dropdownRow<CreatureElement>(
              'Element (drives STAB and type advantage)',
              _element,
              CreatureElement.values
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text('${e.emoji} ${e.label}'),
                    ),
                  )
                  .toList(),
              (v) => setState(() => _element = v ?? _element),
            ),
            const SizedBox(height: 12),
            _dropdownRow<AbilityTarget>(
              'Target',
              _target,
              AbilityTarget.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              (v) => setState(() => _target = v ?? _target),
            ),
            const SizedBox(height: 12),
            if (_kind == AbilityKind.damage)
              _numRow('Power', _power, onChanged: (v) => _power = v as int),
            Row(
              children: [
                Expanded(
                  child: _numRow(
                    'Priority (0 = normal)',
                    _priority,
                    onChanged: (v) => setState(() => _priority = v as int),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'AP cost (0 = auto)',
                    _apCost,
                    onChanged: (v) => setState(() => _apCost = v as int),
                  ),
                ),
              ],
            ),
            _costCard(),
            ..._effectsSection(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: FoE.btn(active: true),
                  alignment: Alignment.center,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: FoE.goldBright,
                          ),
                        )
                      : Text(
                          'Save',
                          style: FoE.label(
                            size: 14,
                          ).copyWith(color: Colors.white),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: FoE.dim(size: 10).copyWith(
        color: FoE.gold,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  /// What this move COSTS, read back as the rules that produce the figure —
  /// including the two places where power stops buying anything (user 2026-07-30).
  ///
  /// Every number here comes from a dial or from the def, never from a repeated
  /// literal: this card is the only explanation of the pricing the author gets,
  /// so a stale sentence in it is worse than no sentence.
  Widget _costCard() {
    final def = _draft;
    final ap = def.resolvedApCost;
    final effectPower = def.effects.fold<double>(0, (a, e) => a + e.power);
    final autoAp = AbilityDef(
      id: '_',
      name: '_',
      element: _element,
      kind: _kind,
      target: _target,
      power: def.power,
      priority: _priority,
    ).withEffects(_allowedEffects).resolvedApCost;
    final stageCap = maxActionPointsForStage(0);
    final lines = <String>[
      _apCost > 0
          ? 'Costs $ap AP — the number you set. Its own power says '
                '${def.totalPower.round()}, which would price it at $autoAp AP.'
          : 'Costs $ap AP = power ${def.totalPower.round()} ÷ $kPowerPerAp '
                '(Power pro AP)'
                '${_priority > 0 ? ', priority $_priority adding ${kPriorityPower * _priority}' : ''}.',
      if (def.effects.isNotEmpty)
        'That power is '
            '${def.kind == AbilityKind.damage ? 'damage ${def.power}' : 'no damage'} '
            '${effectPower >= 0 ? '+' : '−'} ${effectPower.abs().round()} from '
            '${def.effects.length} effect(s) — each card below shows its own '
            'share, chance included.',
      // WHERE POWER STOPS COUNTING, both places, with the number attached. Left
      // unsaid, these are exactly the holes the flat effect surcharges were.
      if (def.isOverPricedOut)
        '⚠ Stronger than any monster can pay for: the price is pinned at '
            '$kMaxActionPoints AP (the final form\'s whole pool), so '
            '${(def.totalPower - kMaxPricedPower).round()} power above '
            '$kMaxPricedPower is FREE. Split the move or set the AP by hand.',
      if (_apCost == 0 && autoAp > stageCap)
        '⚠ As a STARTING ability (unlocked at the base form) it is capped at '
            '$stageCap AP instead of $autoAp — the base form only banks '
            '$stageCap, so it has to be affordable. Give it to a later stage to '
            'make it cost what it is worth.',
      'A base form banks $stageCap AP and regains ${apRegenForStage(0)} per '
          'turn; the final form ${maxActionPointsForStage(2)} and '
          '${apRegenForStage(2)}. Unspent AP carry over, so a turn can save up '
          'for this.',
      if (_priority > 0)
        'Priority $_priority also pulls the user’s NEXT turn '
            '${(30 * _priority).clamp(0, 90)} % closer in the turn order.',
      if (_kind == AbilityKind.damage)
        'No single hit may remove more than '
            '${(CombatEngine.kMaxHitHpFraction * 100).round()} % of the target’s '
            'max HP, whatever the power says.',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 6, side: BorderSide(color: FoE.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cost and turn order',
            style: FoE.label(size: 11).copyWith(color: FoE.gold),
          ),
          const SizedBox(height: 4),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('• $l', style: FoE.dim(size: 11)),
            ),
        ],
      ),
    );
  }

  // ── The EFFECT LIST (user 2026-07-30) ──────────────────────
  // "Effekt wählen (alle effekte in einer Liste), Dauer (0 default, falls es
  // nicht auf Zeit ist), Wert des Effekts (bsp wieviel HP burn verursacht)."
  //
  // One card per effect: what it is, how strong, how long, how likely — and
  // underneath, in prose, exactly what that does in a fight. The prose comes
  // from the same numbers the engine applies ([describeAbilityEffect]), so it
  // cannot promise something the fight does not deliver, and it names the parts
  // that are NOT authorable too: picking Burn used to buy a −20 % attack debuff
  // nobody could see.
  List<Widget> _effectsSection() {
    final dropped = _effects.length - _allowedEffects.length;
    return [
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Text(
              'Effects',
              style: FoE.label(size: 15).copyWith(color: FoE.goldBright),
            ),
          ),
          if (_addableKinds.isNotEmpty)
            GestureDetector(
              onTap: () => setState(
                () => _effects.add(AbilityEffect(kind: _addableKinds.first)),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: FoE.btn(),
                child: Text(
                  '+ Add effect',
                  style: FoE.label(size: 12).copyWith(color: FoE.parchment),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        _addableKinds.isEmpty && _effects.isNotEmpty
            ? 'A ${_kind.label} move already carries every effect it can.'
            : 'Value 0 = the effect’s standard strength, duration 0 = its '
                'standard length. Each card says what its numbers do in a fight.',
        style: FoE.dim(size: 11),
      ),
      if (_effects.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            _kind == AbilityKind.damage
                ? 'No effects — this move only deals its damage.'
                : 'No effects yet — a ${_kind.label} move does nothing without '
                    'one.',
            style: FoE.dim(size: 12),
          ),
        ),
      for (var i = 0; i < _effects.length; i++) _effectCard(i),
      if (dropped > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '⚠ $dropped effect(s) above cannot fire on a ${_kind.label} move '
            'and will NOT be saved. Change the Kind, or remove them.',
            style: FoE.dim(size: 11).copyWith(color: Colors.redAccent),
          ),
        ),
    ];
  }

  /// The effects this move could still take on — the flat list minus the
  /// families it already fills (one each; see AbilityDef.withEffects) and minus
  /// what its kind could never apply.
  List<AbilityEffectKind> get _addableKinds {
    final taken = {for (final e in _effects) e.kind.family};
    return [
      for (final k in AbilityEffectKind.values)
        if (_allows(k) && !taken.contains(k.family)) k,
    ];
  }

  Widget _effectCard(int i) {
    final e = _effects[i];
    final usable = _allows(e.kind);
    // Its OWN family stays selectable even though it is taken — that is how you
    // swap Burn for Frost without deleting the row first.
    final options = <AbilityEffectKind>[
      for (final k in AbilityEffectKind.values)
        if ((_allows(k) || k == e.kind) &&
            (k.family == e.kind.family ||
                !_effects.any((o) => o.kind.family == k.family)))
          k,
    ];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _dropdownRow<AbilityEffectKind>(
                  'Effect',
                  e.kind,
                  [
                    for (final k in options)
                      DropdownMenuItem(
                        value: k,
                        child: Text('${k.emoji} ${k.label}'),
                      ),
                  ],
                  (v) => setState(() {
                    if (v != null) _effects[i] = e.copyWith(kind: v);
                  }),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () => setState(() => _effects.removeAt(i)),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // The label names the UNIT per effect — that is what makes one
                // list workable: "% of max HP per turn" for burn, "% speed lost"
                // for frost, "% of the damage dealt" for lifesteal.
                child: _numRow(
                  '${e.kind.valueLabel} · 0 = ${_pctText(e.kind.defaultValue)}',
                  _asPercent(e.value),
                  isDouble: true,
                  onChanged: (v) => setState(
                    () => _effects[i] = e.copyWith(value: (v as double) / 100),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: e.kind.isTimed
                    ? _numRow(
                        'Duration in turns · 0 = ${e.kind.defaultTurns}',
                        e.turns,
                        onChanged: (v) => setState(
                          () => _effects[i] = e.copyWith(turns: v as int),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 12),
                        child: Text(
                          'Not on a timer — it happens once and is over.',
                          style: FoE.dim(size: 11),
                        ),
                      ),
              ),
            ],
          ),
          if (e.kind.rollsChance)
            _numRow(
              'Chance in % (0 = always lands)',
              _asPercent(e.chance),
              isDouble: true,
              onChanged: (v) => setState(
                () => _effects[i] = e.copyWith(chance: (v as double) / 100),
              ),
            ),
          // WHAT IT MEANS IN COMBAT — the request itself, answered live.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 6, side: BorderSide(color: FoE.border))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'In combat',
                        style: FoE.label(size: 11).copyWith(color: FoE.gold),
                      ),
                    ),
                    // WHAT IT IS WORTH, in the same unit as Power (user
                    // 2026-07-30: "damit es vergleichbar wird mit den AP") — the
                    // number the AP price is actually derived from.
                    //
                    // An effect this kind cannot fire contributes NOTHING, and
                    // says so: printing its power would put a figure on screen
                    // that the total below deliberately leaves out.
                    Text(
                      usable
                          ? '${e.power >= 0 ? '+' : ''}${e.power.round()} power'
                          : 'not counted',
                      style: FoE.label(size: 11).copyWith(
                        color: !usable
                            ? Colors.redAccent
                            : e.power >= 0
                                ? FoE.goldBright
                                : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final line in describeAbilityEffect(e))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('• $line', style: FoE.dim(size: 11)),
                  ),
                if (!usable)
                  Text(
                    '⚠ A ${_kind.label} move never applies this — it needs a '
                    '${_neededKind(e.kind).label} move.',
                    style: FoE.dim(size: 11).copyWith(color: Colors.redAccent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The move kind an effect needs — for the warning on a mismatched card.
  AbilityKind _neededKind(AbilityEffectKind kind) => switch (kind.family) {
    AbilityEffectFamily.heal => AbilityKind.heal,
    AbilityEffectFamily.selfBuff => AbilityKind.buff,
    _ => AbilityKind.damage,
  };

  /// Fractions are stored, PERCENTAGES are typed: 0.05 in the row, "5" in the
  /// field. Every effect in the list speaks percent, so the author never has to
  /// remember which of them wanted a fraction and which a multiplier.
  static num _asPercent(double fraction) {
    final p = fraction * 100;
    return p == p.roundToDouble() ? p.round() : (p * 10).round() / 10;
  }

  static String _pctText(double fraction) => '${_asPercent(fraction)} %';

  Widget _textRow(
    String label,
    String value, {
    bool enabled = true,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        enabled: enabled,
        style: FoE.label(size: 15).copyWith(color: FoE.parchment),
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
  }

  Widget _numRow(
    String label,
    num value, {
    bool isDouble = false,
    required ValueChanged<dynamic> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value.toString(),
        keyboardType: TextInputType.numberWithOptions(decimal: isDouble),
        style: FoE.label(size: 15).copyWith(color: FoE.parchment),
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          final parsed = isDouble ? double.tryParse(v) : int.tryParse(v);
          if (parsed != null) onChanged(parsed);
        },
      ),
    );
  }

  Widget _dropdownRow<T>(
    String label,
    T value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      dropdownColor: FoE.panelDark,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      items: items,
      onChanged: onChanged,
    );
  }
}
