import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/era_definitions.dart';
import '../services/game_defs_controller.dart';
import 'dev_theme.dart';
import 'effects_editor.dart';
import 'resource_map_editor.dart';

// Create/edit form for a single EraDef. `order` (1-based, matches
// SettlementModel.eraIndex directly) determines the progression sequence —
// SettlementController.advanceEra() looks up "order == current + 1" for the
// next era, so two eras sharing an order silently shadow each other. Not
// validated here (single trusted author, matches this codebase's dev-mode
// convention) — be deliberate with the number.
class EraDefForm extends StatefulWidget {
  final EraDef? existing;
  const EraDefForm({super.key, this.existing});

  @override
  State<EraDefForm> createState() => _EraDefFormState();
}

class _EraDefFormState extends State<EraDefForm> {
  bool _saving = false;

  late String _id;
  late String _name;
  late String _emoji;
  late int _order;
  late Map<String, double> _advancementCost;
  late Map<String, double> _grantResources;
  late List<Map<String, dynamic>> _effects;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _emoji = d?.emoji ?? '🌅';
    _order =
        d?.order ??
        (kEraDefs.values.isEmpty
            ? 1
            : kEraDefs.values
                      .map((e) => e.order)
                      .reduce((a, b) => a > b ? a : b) +
                  1);
    _advancementCost = Map.of(d?.advancementCost ?? const {});
    _grantResources = Map.of(d?.grantResources ?? const {});
    _effects = d == null
        ? []
        : ((d.toDefRow()['effects'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    setState(() => _saving = true);

    // Same translation-layer trick as building/tech forms: build the
    // non-effects fields via the constructor, dump to a row, splice in the
    // edited effects, re-parse through fromDefRow so the form never
    // duplicates GameDefsController's parsing logic.
    final base = EraDef(
      id: _id.trim(),
      name: _name.trim(),
      emoji: _emoji.trim(),
      order: _order,
      advancementCost: _advancementCost,
      grantResources: _grantResources,
    );
    final row = base.toDefRow();
    row['effects'] = _effects;
    final finalDef = EraDef.fromDefRow(row);

    try {
      await GameDefsController().saveEraDef(finalDef);
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
      title: 'Delete era?',
      message:
          'This removes "$_id" for every player immediately. Buildings/tech '
          'assigned to this era will no longer be available/researchable.',
    );
    if (!ok) return;
    // Same silent-failure trap as the building form (user 2026-07-31).
    try {
      await GameDefsController().deleteEraDef(_id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildDevModeTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isNew ? 'New Era' : 'Edit Era',
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
              'Id (slug, e.g. era_2)',
              _id,
              enabled: _isNew,
              onChanged: (v) => _id = v,
            ),
            _textRow('Name', _name, onChanged: (v) => _name = v),
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
                    'Order (progression sequence)',
                    _order,
                    onChanged: (v) => _order = v,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Advancement cost',
              style: FoE.label(size: 14).copyWith(color: FoE.gold),
            ),
            const SizedBox(height: 8),
            ResourceMapEditor(
              values: _advancementCost,
              onChanged: (m) => setState(() => _advancementCost = m),
            ),
            const SizedBox(height: 16),
            Text(
              'One-time grant on advancement',
              style: FoE.label(size: 14).copyWith(color: FoE.gold),
            ),
            const SizedBox(height: 8),
            ResourceMapEditor(
              values: _grantResources,
              hintText: 'resource id',
              onChanged: (m) => setState(() => _grantResources = m),
            ),
            const SizedBox(height: 16),
            EffectsEditor(
              initialEffects: _effects,
              mode: EffectsMode.era,
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
}
