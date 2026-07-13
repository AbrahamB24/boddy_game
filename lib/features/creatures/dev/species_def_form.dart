import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/dev/dev_theme.dart';
import '../models/ability_def.dart';
import '../models/creature_enums.dart';
import '../models/species_def.dart';
import '../services/creature_defs_service.dart';

// Create/edit form for one SpeciesDef: element/rarity/role, per-species
// evolution levels, the 6 stat curves (3-stage base + one shared growth
// each), 3 evolution stages (name + PNG upload each) and the species' fixed
// ability set (unlocked per STAGE, not level). Same conventions as
// BuildingDefForm.
class SpeciesDefForm extends StatefulWidget {
  final SpeciesDef? existing;
  const SpeciesDefForm({super.key, this.existing});

  @override
  State<SpeciesDefForm> createState() => _SpeciesDefFormState();
}

class _SpeciesDefFormState extends State<SpeciesDefForm> {
  final _svc = CreatureDefsService();
  bool _saving = false;
  int? _uploadingStage;

  late String _id;
  late String _name;
  late String _description;
  late String _role;
  late CreatureElement _element;
  late CreatureRarity _rarity;
  late double _catchRate;
  late int _evoLevel1;
  late int _evoLevel2;
  late Map<CreatureStat, StatCurve> _stats;
  late List<String> _stageNames;
  late List<String?> _stageImages;
  late List<SpeciesAbility> _abilities;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _description = d?.description ?? '';
    _role = d?.role ?? '';
    _element = d?.element ?? CreatureElement.fire;
    _rarity = d?.rarity ?? CreatureRarity.common;
    _catchRate = d?.catchRate ?? 1.0;
    _evoLevel1 = d?.evoLevel1 ?? 25;
    _evoLevel2 = d?.evoLevel2 ?? 50;
    _stats = {
      for (final stat in CreatureStat.values)
        stat: d?.stats[stat] ?? _defaultCurve(stat),
    };
    _stageNames = List.generate(3, (i) => d?.stageAt(i).name ?? '');
    _stageImages = List.generate(3, (i) => d?.stageAt(i).imageUrl);
    _abilities = List.of(d?.abilities ?? const []);
  }

  // Sensible starting numbers so a new species is playable before tuning:
  // pools are bigger than combat stats, catch rate is modest. Stage 2/3
  // bases start equal to stage 1 — the author raises them to define each
  // evolution's bonus (stage2 - stage1, stage3 - stage2).
  StatCurve _defaultCurve(CreatureStat stat) {
    final (base, growth) = switch (stat) {
      CreatureStat.hp => (40.0, 4.0),
      CreatureStat.energy => (30.0, 2.0),
      CreatureStat.speed => (10.0, 0.6),
      CreatureStat.catchRate => (8.0, 0.4),
      _ => (10.0, 1.0),
    };
    return StatCurve(stageBase: [base, base, base], growth: growth);
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    setState(() => _saving = true);
    final def = SpeciesDef(
      id: _id.trim(),
      name: _name.trim(),
      description: _description.trim(),
      role: _role.trim(),
      element: _element,
      rarity: _rarity,
      catchRate: _catchRate,
      evoLevel1: _evoLevel1,
      evoLevel2: _evoLevel2,
      stats: _stats,
      stages: List.generate(
        3,
        (i) => SpeciesStage(
          name: _stageNames[i].trim().isEmpty
              ? _name.trim()
              : _stageNames[i].trim(),
          imageUrl: _stageImages[i],
        ),
      ),
      abilities: _abilities.where((a) => a.abilityId.isNotEmpty).toList(),
    );
    try {
      await _svc.upsertSpeciesDef(def);
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

  Future<void> _uploadImage(int stage) async {
    if (_id.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set the id first — it names the file')),
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return; // picker cancelled

    setState(() => _uploadingStage = stage);
    try {
      final url = await _svc.uploadStageImage(_id.trim(), stage, bytes);
      if (mounted) setState(() => _stageImages[stage] = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingStage = null);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete species?',
      message: 'This removes "$_id" for every player immediately.',
    );
    if (!ok) return;
    await _svc.deleteSpeciesDef(_id);
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
            _isNew ? 'New Species' : 'Edit Species',
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
              'Id (slug, e.g. flammkitz)',
              _id,
              enabled: _isNew,
              onChanged: (v) => _id = v,
            ),
            _textRow('Species name', _name, onChanged: (v) => _name = v),
            _textRow(
              'Description',
              _description,
              onChanged: (v) => _description = v,
            ),
            _textRow(
              'Role (flavor only, e.g. "Glass Cannon")',
              _role,
              onChanged: (v) => _role = v,
            ),
            _dropdownRow<CreatureElement>(
              'Element',
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
            _dropdownRow<CreatureRarity>(
              'Rarity',
              _rarity,
              CreatureRarity.values
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                  .toList(),
              (v) => setState(() => _rarity = v ?? _rarity),
            ),
            const SizedBox(height: 12),
            _numRow(
              'Catch rate modifier (1.0 = normal)',
              _catchRate,
              isDouble: true,
              onChanged: (v) => _catchRate = v as double,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _numRow(
                    'Evolution 1 level',
                    _evoLevel1,
                    onChanged: (v) => _evoLevel1 = v as int,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'Evolution 2 level',
                    _evoLevel2,
                    onChanged: (v) => _evoLevel2 = v as int,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _sectionLabel('Evolution stages (name + PNG)'),
            for (var i = 0; i < 3; i++) _stageBlock(i),
            const SizedBox(height: 12),
            _sectionLabel(
              'Stats — base value per stage + shared growth/Lv',
            ),
            const SizedBox(height: 6),
            for (final stat in CreatureStat.values) _statRow(stat),
            const SizedBox(height: 12),
            _sectionLabel('Abilities (unlocked per evolution stage)'),
            const SizedBox(height: 6),
            ..._abilities.asMap().entries.map(
              (e) => _abilityRow(e.key, e.value),
            ),
            GestureDetector(
              onTap: kAbilityDefs.isEmpty
                  ? null
                  : () => setState(
                      () => _abilities.add(
                        SpeciesAbility(abilityId: kAbilityDefs.keys.first),
                      ),
                    ),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: FoE.btn(),
                alignment: Alignment.center,
                child: Text(
                  kAbilityDefs.isEmpty
                      ? 'No abilities defined yet (Abilities tab)'
                      : '+ Add ability',
                  style: FoE.label(size: 13),
                ),
              ),
            ),
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

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
  );

  Widget _stageBlock(int stage) {
    final uploading = _uploadingStage == stage;
    final url = _stageImages[stage];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: FoE.panel(radius: 8),
            child: url == null
                ? const Icon(Icons.pets, color: FoE.gold, size: 26)
                : Image.network(
                    url,
                    width: 44,
                    height: 44,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image, color: FoE.gold),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              initialValue: _stageNames[stage],
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              decoration: InputDecoration(
                labelText: 'Stage ${stage + 1} name',
                isDense: true,
              ),
              onChanged: (v) => _stageNames[stage] = v,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: uploading ? null : () => _uploadImage(stage),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: FoE.btn(),
              child: uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(url == null ? 'PNG' : 'Replace', style: FoE.label(size: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(CreatureStat stat) {
    final curve = _stats[stat]!;

    void updateBase(int stage, double value) {
      final bases = List.of(curve.stageBase);
      bases[stage] = value;
      setState(() => _stats[stat] = StatCurve(stageBase: bases, growth: curve.growth));
    }

    void updateGrowth(double value) {
      setState(
        () => _stats[stat] = StatCurve(stageBase: curve.stageBase, growth: value),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stat.label,
                  style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                ),
              ),
              SizedBox(
                width: 110,
                child: TextFormField(
                  key: ValueKey('${stat.name}-growth-${curve.growth}'),
                  initialValue: curve.growth.toString(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                  decoration: const InputDecoration(
                    labelText: 'Growth/Lv',
                    isDense: true,
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) updateGrowth(parsed);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var stage = 0; stage < 3; stage++) ...[
                if (stage > 0) const SizedBox(width: 6),
                Expanded(
                  child: TextFormField(
                    key: ValueKey(
                      '${stat.name}-base$stage-${curve.stageBase[stage]}',
                    ),
                    initialValue: curve.stageBase[stage].toString(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                    decoration: InputDecoration(
                      labelText: 'S${stage + 1} Base',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) updateBase(stage, parsed);
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _abilityRow(int index, SpeciesAbility ability) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              initialValue: kAbilityDefs.containsKey(ability.abilityId)
                  ? ability.abilityId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Ability',
                isDense: true,
              ),
              dropdownColor: FoE.panelDark,
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              items: kAbilityDefs.values
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(
                () => _abilities[index] = SpeciesAbility(
                  abilityId: v ?? '',
                  unlockStage: ability.unlockStage,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: ability.unlockStage,
              decoration: const InputDecoration(
                labelText: 'From Stage',
                isDense: true,
              ),
              dropdownColor: FoE.panelDark,
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              items: const [
                DropdownMenuItem(value: 0, child: Text('S1')),
                DropdownMenuItem(value: 1, child: Text('S2')),
                DropdownMenuItem(value: 2, child: Text('S3')),
              ],
              onChanged: (v) => setState(
                () => _abilities[index] = SpeciesAbility(
                  abilityId: ability.abilityId,
                  unlockStage: v ?? 0,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
            onPressed: () => setState(() => _abilities.removeAt(index)),
          ),
        ],
      ),
    );
  }

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
