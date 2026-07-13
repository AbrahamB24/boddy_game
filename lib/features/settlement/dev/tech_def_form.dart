import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/tech_definitions.dart';
import '../services/game_defs_service.dart';
import 'dev_theme.dart';
import 'effects_editor.dart';

// Create/edit form for a single TechDef. col/row are never set here — they
// don't round-trip through toDefRow()/fromDefRow() at all, since
// GameDefsController recomputes the whole tree's layout from `prerequisites`
// on every load (see game_defs_controller.dart's _computeLayout). Dummy 0/0
// values are passed to the constructors below purely to satisfy required
// params; they're discarded before anything is persisted or rendered.
class TechDefForm extends StatefulWidget {
  final TechDef? existing;
  const TechDefForm({super.key, this.existing});

  @override
  State<TechDefForm> createState() => _TechDefFormState();
}

class _TechDefFormState extends State<TechDefForm> {
  final _svc = GameDefsService();
  bool _saving = false;

  late String _id;
  late String _name;
  late String _emoji;
  late String _description;
  late int _bpCost;
  late double _researchSeconds;
  late Set<String> _prerequisites;
  String? _unlocksBuilding;
  String? _eraId;
  late List<Map<String, dynamic>> _effects;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _emoji = d?.emoji ?? '🔬';
    _description = d?.description ?? '';
    _bpCost = d?.bpCost ?? 10;
    _researchSeconds = d?.researchSeconds ?? (_bpCost * 72).toDouble();
    _prerequisites = Set.of(d?.prerequisites ?? const []);
    _unlocksBuilding = d?.unlocksBuilding;
    _eraId =
        d?.eraId ??
        (kEraDefs.values.isEmpty
            ? null
            : (kEraDefs.values.toList()
                    ..sort((a, b) => a.order.compareTo(b.order)))
                  .first
                  .id);
    _effects = d == null
        ? []
        : ((d.toDefRow()['effects'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
  }

  // Does adding `newPrereqs` to `techId` make techId reachable from one of
  // its own (possibly transitive) prerequisites? Checked against the live
  // kTechDefs graph with techId's entry overridden to the candidate list —
  // covers both direct self-reference and longer cycles. See
  // game_defs_controller.dart's _computeLayout for the sibling algorithm
  // that would otherwise silently mis-place a cyclic tech.
  bool _wouldCreateCycle(String techId, List<String> newPrereqs) {
    final graph = <String, List<String>>{
      for (final t in kTechDefs.values) t.id: t.prerequisites,
    };
    graph[techId] = newPrereqs;

    final visited = <String>{};
    bool canReach(String from, String target) {
      if (from == target) return true;
      if (!visited.add(from)) return false;
      for (final p in graph[from] ?? const []) {
        if (canReach(p, target)) return true;
      }
      return false;
    }

    for (final p in newPrereqs) {
      if (canReach(p, techId)) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    final prereqList = _prerequisites.toList();
    if (_wouldCreateCycle(_id.trim(), prereqList)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'These prerequisites would create a cycle — remove one that depends on this tech',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final base = TechDef(
      id: _id.trim(),
      name: _name.trim(),
      emoji: _emoji.trim(),
      description: _description.trim(),
      bpCost: _bpCost,
      researchSeconds: _researchSeconds,
      col: 0,
      row: 0,
      prerequisites: prereqList,
      unlocksBuilding: _unlocksBuilding,
      eraId: _eraId,
    );
    final row = base.toDefRow();
    row['effects'] = _effects;
    final finalDef = TechDef.fromDefRow(row, col: 0, row: 0);

    try {
      await _svc.upsertTechDef(finalDef);
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
    // Warn if other techs still list this one as a prerequisite — deleting
    // leaves a dangling id, which GameDefsController's layout algorithm
    // already tolerates (ignored as a "dangling prerequisite"), but the
    // dependent tech would silently lose that gating.
    final dependents = kTechDefs.values
        .where((t) => t.id != _id && t.prerequisites.contains(_id))
        .map((t) => t.name)
        .toList();
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete tech?',
      message:
          'This removes "$_id" for every player immediately.'
          '${dependents.isEmpty ? '' : '\n\nStill required by: ${dependents.join(', ')}'}',
    );
    if (!ok) return;
    await _svc.deleteTechDef(_id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final otherTechIds = kTechDefs.keys.where((id) => id != _id).toList();

    return Theme(
      data: buildDevModeTheme(),
      child: Scaffold(
        backgroundColor: FoE.bg,
        appBar: AppBar(
          title: Text(
            _isNew ? 'New Tech' : 'Edit Tech',
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
              'Id (slug, e.g. primitive_woodworking)',
              _id,
              enabled: _isNew,
              onChanged: (v) => _id = v,
            ),
            _textRow('Name', _name, onChanged: (v) => _name = v),
            _textRow(
              'Description',
              _description,
              maxLines: 3,
              onChanged: (v) => _description = v,
            ),
            Row(
              children: [
                Expanded(
                  child: _textRow(
                    'Emoji',
                    _emoji,
                    onChanged: (v) => _emoji = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'BP cost',
                    _bpCost,
                    onChanged: (v) {
                      _bpCost = v;
                      setState(() {}); // refresh the auto-suggest hint below
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _numRow(
                    'Research seconds',
                    _researchSeconds,
                    isDouble: true,
                    onChanged: (v) => _researchSeconds = v,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(
                    () => _researchSeconds = (_bpCost * 72).toDouble(),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                    decoration: FoE.btn(),
                    child: Text(
                      'Auto (×72)',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: FoE.goldBright),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _eraDropdown(),
            const SizedBox(height: 8),
            _dropdownRow(
              'Unlocks building',
              _unlocksBuilding,
              kBuildingDefs.keys.toList(),
              (v) => setState(() => _unlocksBuilding = v),
            ),
            const SizedBox(height: 16),
            Text(
              'Prerequisites',
              style: FoE.label(size: 14).copyWith(color: FoE.gold),
            ),
            const SizedBox(height: 6),
            if (otherTechIds.isEmpty)
              Text(
                'No other tech exists yet.',
                style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: otherTechIds.map((id) {
                  final selected = _prerequisites.contains(id);
                  return FilterChip(
                    label: Text(
                      kTechDefs[id]?.name ?? id,
                      style: FoE.label(size: 13).copyWith(
                        color: selected ? Colors.black : FoE.parchment,
                      ),
                    ),
                    selected: selected,
                    selectedColor: FoE.gold,
                    backgroundColor: FoE.panelMid,
                    side: const BorderSide(color: FoE.border),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _prerequisites.add(id);
                      } else {
                        _prerequisites.remove(id);
                      }
                    }),
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),
            EffectsEditor(
              initialEffects: _effects,
              mode: EffectsMode.tech,
              onChanged: (e) => _effects = e,
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

  Widget _textRow(
    String label,
    String value, {
    bool enabled = true,
    int maxLines = 1,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: value,
        enabled: enabled,
        maxLines: maxLines,
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
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.numberWithOptions(decimal: isDouble),
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: InputDecoration(labelText: label),
      onChanged: (v) {
        final parsed = isDouble ? double.tryParse(v) : int.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  // Only this tech's own era's tech is ever shown/researchable in
  // research_screen.dart — this is what makes the "advance once this era's
  // tree is done" check well-defined (see EraDef/advanceEra).
  Widget _eraDropdown() {
    final eras = kEraDefs.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return DropdownButtonFormField<String?>(
      initialValue: eras.any((e) => e.id == _eraId) ? _eraId : null,
      decoration: const InputDecoration(labelText: 'Era'),
      dropdownColor: FoE.panelDark,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      items: eras
          .map(
            (e) => DropdownMenuItem(
              value: e.id,
              child: Text('${e.emoji} ${e.name}'),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _eraId = v),
    );
  }

  Widget _dropdownRow(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String?>(
      initialValue: options.contains(value) ? value : null,
      decoration: InputDecoration(labelText: label),
      dropdownColor: FoE.panelDark,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        ...options.map((o) => DropdownMenuItem(value: o, child: Text(o))),
      ],
      onChanged: onChanged,
    );
  }
}
