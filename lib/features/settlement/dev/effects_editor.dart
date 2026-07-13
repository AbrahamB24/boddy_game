import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/creature_enums.dart';

// Reusable editor for the generic `effects` JSON vocabulary shared by
// BuildingDef.fromDefRow/toDefRow, TechDef.fromDefRow/toDefRow and
// EraDef.fromDefRow/toDefRow (see building_definitions.dart /
// tech_definitions.dart / era_definitions.dart). One widget, reused
// unchanged across building_def_form.dart, tech_def_form.dart and
// era_def_form.dart — only the allowed `type`/`target` options differ per
// mode. era uses the same 'bonus' targets as tech (wood/stone/food/all/
// buildSpeed/workoutBp) — EraDef's one-time grants are a separate, simpler
// resource map (see ResourceMapEditor), not part of this vocabulary.
enum EffectsMode { building, tech, era }

class EffectsEditor extends StatefulWidget {
  final List<Map<String, dynamic>> initialEffects;
  final EffectsMode mode;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  const EffectsEditor({
    super.key,
    required this.initialEffects,
    required this.mode,
    required this.onChanged,
  });

  @override
  State<EffectsEditor> createState() => _EffectsEditorState();
}

class _EffectsEditorState extends State<EffectsEditor> {
  late List<Map<String, dynamic>> _effects;

  @override
  void initState() {
    super.initState();
    _effects = widget.initialEffects
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<String> get _typeOptions => switch (widget.mode) {
    // 'production'/'gold' are legacy (ignored by the creature-worker economy)
    // but kept selectable so old building rows still display/remove cleanly.
    EffectsMode.building => const [
      'workshop',
      'bonus',
      'need',
      'production',
      'gold',
    ],
    EffectsMode.tech => const ['bonus', 'slots'],
    EffectsMode.era => const ['bonus'],
  };

  void _addEffect() {
    setState(() => _effects.add(_defaultFor(_typeOptions.first)));
    widget.onChanged(_effects);
  }

  void _removeAt(int i) {
    setState(() => _effects.removeAt(i));
    widget.onChanged(_effects);
  }

  void _updateAt(int i, Map<String, dynamic> next) {
    setState(() => _effects[i] = next);
    widget.onChanged(_effects);
  }

  Map<String, dynamic> _defaultFor(String type) => switch (type) {
    'workshop' => {
      'type': 'workshop',
      'stat': 'woodcutting',
      'resource': 'wood',
      'mult': 0.1,
      'slots': 1,
    },
    'production' => {
      'type': 'production',
      'resource': 'wood',
      'base': 0.0,
      'perWorker': 0.0,
    },
    'gold' => {'type': 'gold', 'perHour': 0.0},
    'bonus' => {
      'type': 'bonus',
      'target': widget.mode == EffectsMode.building ? 'buildSpeed' : 'wood',
      'value': 0.0,
    },
    'slots' => {'type': 'slots', 'target': 'build', 'amount': 0},
    'need' => {
      'type': 'need',
      'goodId': 'fish',
      'populationBonus': 0.0,
      'woodBonus': 0.0,
      'stoneBonus': 0.0,
      'goldBonus': 0.0,
      'consumptionPerHour': 0.0,
    },
    _ => {'type': type},
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Effects', style: FoE.label(size: 14).copyWith(color: FoE.gold)),
        const SizedBox(height: 8),
        for (int i = 0; i < _effects.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _EffectRow(
              key: ValueKey(i),
              effect: _effects[i],
              mode: widget.mode,
              typeOptions: _typeOptions,
              onChanged: (e) => _updateAt(i, e),
              onRemove: () => _removeAt(i),
              defaultFor: _defaultFor,
            ),
          ),
        GestureDetector(
          onTap: _addEffect,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: FoE.btn(),
            alignment: Alignment.center,
            child: Text(
              '+ Add Effect',
              style: FoE.label(size: 14).copyWith(color: FoE.goldBright),
            ),
          ),
        ),
      ],
    );
  }
}

class _EffectRow extends StatelessWidget {
  final Map<String, dynamic> effect;
  final EffectsMode mode;
  final List<String> typeOptions;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;
  final Map<String, dynamic> Function(String type) defaultFor;

  const _EffectRow({
    super.key,
    required this.effect,
    required this.mode,
    required this.typeOptions,
    required this.onChanged,
    required this.onRemove,
    required this.defaultFor,
  });

  List<String> get _bonusTargets => mode == EffectsMode.building
      ? const ['buildSpeed', 'population', 'queueSlots']
      : const ['wood', 'stone', 'food', 'all', 'buildSpeed', 'workoutBp'];

  @override
  Widget build(BuildContext context) {
    final type = effect['type'] as String? ?? typeOptions.first;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _dropdown(
                  'Type',
                  type,
                  typeOptions,
                  (v) => onChanged(defaultFor(v!)),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: onRemove,
              ),
            ],
          ),
          ..._fieldsFor(type),
        ],
      ),
    );
  }

  List<Widget> _fieldsFor(String type) {
    switch (type) {
      case 'workshop':
        return [
          _dropdown(
            'Worker stat (which civilian stat drives output)',
            (effect['stat'] as String?) ?? kCivilianStats.first.name,
            kCivilianStats.map((s) => s.name).toList(),
            (v) => onChanged({...effect, 'stat': v}),
          ),
          _textField(
            'Output (wood, stone, gold, fish, fur, construction, research)',
            'resource',
          ),
          Row(
            children: [
              Expanded(child: _numField('Output per stat point /h', 'mult')),
              const SizedBox(width: 8),
              Expanded(child: _numField('Worker slots', 'slots', isInt: true)),
            ],
          ),
        ];
      case 'production':
        return [
          _textField(
            'Resource id (wood, stone, buildSpeed, researchSpeed, or any good id)',
            'resource',
          ),
          Row(
            children: [
              Expanded(child: _numField('Base /h', 'base')),
              const SizedBox(width: 8),
              Expanded(child: _numField('Per worker /h', 'perWorker')),
            ],
          ),
        ];
      case 'gold':
        return [_numField('Gold /h', 'perHour')];
      case 'bonus':
        return [
          _dropdown(
            'Target',
            (effect['target'] as String?) ?? _bonusTargets.first,
            _bonusTargets,
            (v) => onChanged({...effect, 'target': v}),
          ),
          _numField('Value (0.30 = +30%)', 'value'),
        ];
      case 'slots':
        return [
          _dropdown(
            'Target',
            (effect['target'] as String?) ?? 'build',
            const ['build', 'queue'],
            (v) => onChanged({...effect, 'target': v}),
          ),
          _numField('Amount', 'amount', isInt: true),
        ];
      case 'need':
        return [
          _textField('Good id required in stock', 'goodId'),
          _numField('Population bonus', 'populationBonus'),
          Row(
            children: [
              Expanded(child: _numField('Wood bonus', 'woodBonus')),
              const SizedBox(width: 8),
              Expanded(child: _numField('Stone bonus', 'stoneBonus')),
            ],
          ),
          _numField('Gold bonus', 'goldBonus'),
          _numField(
            'Real consumption/h (upkeep, drains the good regardless of bonus)',
            'consumptionPerHour',
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(labelText: label, isDense: true),
        dropdownColor: FoE.panelDark,
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _textField(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        initialValue: (effect[key] as String?) ?? '',
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) => onChanged({...effect, key: v}),
      ),
    );
  }

  Widget _numField(String label, String key, {bool isInt = false}) {
    final current = effect[key];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        initialValue: current == null ? '0' : (current as num).toString(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) {
          final parsed = isInt ? int.tryParse(v) : double.tryParse(v);
          onChanged({...effect, key: parsed ?? 0});
        },
      ),
    );
  }
}
