import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/dev/dev_theme.dart';
import '../models/ability_def.dart';
import '../models/creature_enums.dart';
import '../models/status_effects.dart';
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
  CreatureElement? _element;
  late AbilityKind _kind;
  late AbilityTarget _target;
  late int _energyCost;
  late int _power;
  late int _priority;
  late double _healPct;
  late double _lifestealPct;
  MainStatusKind? _inflictMain;
  late double _inflictMainChance;
  SecondaryDebuffKind? _inflictDebuff;
  late double _inflictDebuffChance;
  SelfBuffKind? _selfBuff;
  SelfPenaltyStat? _selfPenaltyStat;
  late double _selfPenaltyMult;
  late int _selfPenaltyTurns;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _description = d?.description ?? '';
    _element = d?.element;
    _kind = d?.kind ?? AbilityKind.damage;
    _target = d?.target ?? AbilityTarget.enemy;
    _energyCost = d?.energyCost ?? 18;
    _power = d?.power ?? 70;
    _priority = d?.priority ?? 0;
    _healPct = d?.healPct ?? 0;
    _lifestealPct = d?.lifestealPct ?? 0;
    _inflictMain = d?.inflictMain;
    _inflictMainChance = d?.inflictMainChance ?? 0;
    _inflictDebuff = d?.inflictDebuff;
    _inflictDebuffChance = d?.inflictDebuffChance ?? 0;
    _selfBuff = d?.selfBuff;
    _selfPenaltyStat = d?.selfPenaltyStat;
    _selfPenaltyMult = d?.selfPenaltyMult ?? 1.0;
    _selfPenaltyTurns = d?.selfPenaltyTurns ?? 1;
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    setState(() => _saving = true);
    final def = AbilityDef(
      id: _id.trim(),
      name: _name.trim(),
      description: _description.trim(),
      element: _element,
      kind: _kind,
      target: _target,
      energyCost: _energyCost,
      power: _kind == AbilityKind.damage ? _power : 0,
      priority: _priority,
      healPct: _kind == AbilityKind.heal ? _healPct : 0,
      lifestealPct: _kind == AbilityKind.damage ? _lifestealPct : 0,
      inflictMain: _kind == AbilityKind.damage ? _inflictMain : null,
      inflictMainChance: _kind == AbilityKind.damage ? _inflictMainChance : 0,
      inflictDebuff: _kind == AbilityKind.damage ? _inflictDebuff : null,
      inflictDebuffChance: _kind == AbilityKind.damage
          ? _inflictDebuffChance
          : 0,
      selfBuff: _kind == AbilityKind.buff ? _selfBuff : null,
      selfPenaltyStat: _kind == AbilityKind.damage ? _selfPenaltyStat : null,
      selfPenaltyMult: _selfPenaltyMult,
      selfPenaltyTurns: _selfPenaltyTurns,
    );
    try {
      await _svc.upsertAbilityDef(def);
      if (mounted) Navigator.pop(context);
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
        backgroundColor: FoE.bg,
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
            _textRow(
              'Id (slug, e.g. flammenstoss)',
              _id,
              enabled: _isNew,
              onChanged: (v) => _id = v,
            ),
            _textRow('Name', _name, onChanged: (v) => _name = v),
            _textRow(
              'Description',
              _description,
              onChanged: (v) => _description = v,
            ),
            _dropdownRow<CreatureElement?>(
              'Element (None = universal)',
              _element,
              [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...CreatureElement.values.map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text('${e.emoji} ${e.label}'),
                  ),
                ),
              ],
              (v) => setState(() => _element = v),
            ),
            const SizedBox(height: 12),
            _dropdownRow<AbilityKind>(
              'Kind',
              _kind,
              AbilityKind.values
                  .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                  .toList(),
              (v) => setState(() => _kind = v ?? _kind),
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
            Row(
              children: [
                Expanded(
                  child: _numRow(
                    'Energy cost',
                    _energyCost,
                    onChanged: (v) => _energyCost = v as int,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'Priority (0 = normal)',
                    _priority,
                    onChanged: (v) => _priority = v as int,
                  ),
                ),
              ],
            ),
            if (_kind == AbilityKind.damage) ..._damageFields(),
            if (_kind == AbilityKind.heal) ..._healFields(),
            if (_kind == AbilityKind.buff) ..._buffFields(),
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
                          ).copyWith(color: FoE.goldBright),
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

  List<Widget> _damageFields() => [
    _numRow('Power', _power, onChanged: (v) => _power = v as int),
    const SizedBox(height: 8),
    _numRow(
      'Lifesteal % of damage dealt (0 = none)',
      _lifestealPct,
      isDouble: true,
      onChanged: (v) => _lifestealPct = v as double,
    ),
    const SizedBox(height: 12),
    Text('Status effect (optional)', style: FoE.label(size: 13).copyWith(color: FoE.gold)),
    const SizedBox(height: 6),
    _dropdownRow<MainStatusKind?>(
      'Main status',
      _inflictMain,
      [
        const DropdownMenuItem(value: null, child: Text('None')),
        ...MainStatusKind.values.map(
          (k) => DropdownMenuItem(
            value: k,
            child: Text('${k.emoji} ${k.label}'),
          ),
        ),
      ],
      (v) => setState(() => _inflictMain = v),
    ),
    if (_inflictMain != null) ...[
      const SizedBox(height: 8),
      _numRow(
        'Chance (0.0-1.0)',
        _inflictMainChance,
        isDouble: true,
        onChanged: (v) => _inflictMainChance = v as double,
      ),
    ],
    const SizedBox(height: 8),
    _dropdownRow<SecondaryDebuffKind?>(
      'Secondary debuff',
      _inflictDebuff,
      [
        const DropdownMenuItem(value: null, child: Text('None')),
        ...SecondaryDebuffKind.values.map(
          (k) => DropdownMenuItem(
            value: k,
            child: Text('${k.emoji} ${k.label}'),
          ),
        ),
      ],
      (v) => setState(() => _inflictDebuff = v),
    ),
    if (_inflictDebuff != null) ...[
      const SizedBox(height: 8),
      _numRow(
        'Chance (0.0-1.0)',
        _inflictDebuffChance,
        isDouble: true,
        onChanged: (v) => _inflictDebuffChance = v as double,
      ),
    ],
    const SizedBox(height: 12),
    Text(
      "Self-cost (optional, e.g. Power Surge/Gaia's Wrath)",
      style: FoE.label(size: 13).copyWith(color: FoE.gold),
    ),
    const SizedBox(height: 6),
    _dropdownRow<SelfPenaltyStat?>(
      'Self penalty stat',
      _selfPenaltyStat,
      [
        const DropdownMenuItem(value: null, child: Text('None')),
        ...SelfPenaltyStat.values.map(
          (s) => DropdownMenuItem(value: s, child: Text(s.name)),
        ),
      ],
      (v) => setState(() => _selfPenaltyStat = v),
    ),
    if (_selfPenaltyStat != null) ...[
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: _numRow(
              'Mult (0.90 = -10%)',
              _selfPenaltyMult,
              isDouble: true,
              onChanged: (v) => _selfPenaltyMult = v as double,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _numRow(
              'Turns',
              _selfPenaltyTurns,
              onChanged: (v) => _selfPenaltyTurns = v as int,
            ),
          ),
        ],
      ),
    ],
  ];

  List<Widget> _healFields() => [
    _numRow(
      'Heal % of max HP (0.35 = Regeneration)',
      _healPct,
      isDouble: true,
      onChanged: (v) => _healPct = v as double,
    ),
  ];

  List<Widget> _buffFields() => [
    _dropdownRow<SelfBuffKind?>(
      'Self buff',
      _selfBuff,
      [
        const DropdownMenuItem(value: null, child: Text('None')),
        ...SelfBuffKind.values.map(
          (k) => DropdownMenuItem(
            value: k,
            child: Text('${k.emoji} ${k.label}'),
          ),
        ),
      ],
      (v) => setState(() => _selfBuff = v),
    ),
  ];

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
