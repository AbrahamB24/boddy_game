import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/area.dart' show kResourceEmoji;
import '../../creatures/models/creature_enums.dart' show CreatureStat;
import '../data/item_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/resource_icons.dart';
import '../services/game_defs_controller.dart';
import 'dev_theme.dart';

// Create/edit one craftable/tradeable ItemDef (user 2026-07-25). Same
// trusted-single-author dev pattern as AreaDefForm / PathNodeForm; saved to
// Supabase `item_defs`. Recipes name concrete luxury ingredients.
class ItemDefForm extends StatefulWidget {
  final ItemDef? existing;
  const ItemDefForm({super.key, this.existing});

  @override
  State<ItemDefForm> createState() => _ItemDefFormState();
}

class _IngredientDraft {
  String key;
  double amount;
  _IngredientDraft({required this.key, required this.amount});
}

class _ItemDefFormState extends State<ItemDefForm> {
  bool _saving = false;

  late String _id;
  late String _name;
  late String _emoji;
  late String _description;
  late ItemKind _kind;
  late double _magnitude;
  CreatureStat? _buffStat;
  String? _resourceId;
  late bool _battleUsable;
  late List<_IngredientDraft> _ingredients;
  late double _supplyCost;
  late double _craftSeconds;
  late int _buyPrice;
  late int _sellPrice;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _emoji = d?.emoji ?? '🧪';
    _description = d?.description ?? '';
    _kind = d?.kind ?? ItemKind.heal;
    _magnitude = d?.magnitude ?? 40;
    _buffStat = d?.buffStat;
    _resourceId = d?.resourceId;
    _battleUsable = d?.battleUsable ?? false;
    _ingredients = [
      for (final e in (d?.ingredients ?? const {}).entries)
        _IngredientDraft(key: e.key, amount: e.value),
    ];
    _supplyCost = d?.supplyCost ?? 0;
    _craftSeconds = d?.craftSeconds ?? 1200;
    _buyPrice = d?.buyPrice ?? 0;
    _sellPrice = d?.sellPrice ?? 0;
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      _snack('id and name are required');
      return;
    }
    setState(() => _saving = true);
    final def = ItemDef(
      id: _id.trim(),
      name: _name.trim(),
      emoji: _emoji.trim().isEmpty ? '🧪' : _emoji.trim(),
      description: _description.trim(),
      kind: _kind,
      magnitude: _magnitude,
      buffStat: _kind == ItemKind.buff ? _buffStat : null,
      resourceId: _kind == ItemKind.resourcePack
          ? (_resourceId ?? _packResources.first)
          : null,
      battleUsable: _battleUsable,
      ingredients: {
        for (final i in _ingredients)
          if (i.key.isNotEmpty && i.amount != 0) i.key: i.amount,
      },
      supplyCost: _supplyCost,
      craftSeconds: _craftSeconds,
      buyPrice: _buyPrice,
      sellPrice: _sellPrice,
    );
    try {
      await GameDefsController().saveItemDef(def);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Save failed: $e');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete item?',
      message: 'This removes "$_id" for every player.',
    );
    if (!ok) return;
    try {
      await GameDefsController().deleteItemDef(_id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack('Delete failed: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String _magnitudeLabel() => switch (_kind) {
    ItemKind.heal => 'HP restored',
    ItemKind.revive => 'Revive fraction (0.5 = 50% HP)',
    ItemKind.buff => 'Buff fraction (0.30 = +30%)',
    ItemKind.catchBoost => 'Catch-window bonus (0.25 = +25%)',
    ItemKind.expeditionYield => 'Haul bonus (0.20 = +20%)',
    ItemKind.breedSpeed => 'Time cut (0.30 = −30%)',
    ItemKind.resourcePack => 'Amount granted (units of the resource below)',
  };

  /// The resource a PACK contains. Every ResourceModel key: the three the
  /// settlement holds itself, plus every good.
  List<String> get _packResources => [
    'wood',
    'stone',
    'gold',
    ...kGoodsDefs.keys,
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildDevModeTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New Item' : 'Edit Item',
              style: FoE.title(size: 16)),
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
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _textRow('Id', _id,
                      enabled: _isNew, onChanged: (v) => _id = v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _textRow('Emoji', _emoji, onChanged: (v) => _emoji = v),
                ),
              ],
            ),
            _textRow('Name', _name, onChanged: (v) => _name = v),
            _textRow('Description', _description,
                onChanged: (v) => _description = v),
            _kindDropdown(),
            _numRow(_magnitudeLabel(), _magnitude,
                isDouble: true, onChanged: (v) => _magnitude = v.toDouble()),
            if (_kind == ItemKind.buff) _buffStatDropdown(),
            if (_kind == ItemKind.resourcePack) _packResourceDropdown(),
            _checkboxRow('Usable in battle', _battleUsable,
                (v) => setState(() => _battleUsable = v)),
            const SizedBox(height: 14),

            _sectionLabel('Recipe ingredients (concrete goods)'),
            const SizedBox(height: 8),
            ..._ingredients.map(_ingredientRow),
            _addButton('+ Zutat', () {
              setState(() => _ingredients.add(
                  _IngredientDraft(key: kResourceEmoji.keys.first, amount: 2)));
            }),
            const SizedBox(height: 8),
            _numRow('Craft-Sekunden (Workshop-Arbeit)', _craftSeconds,
                isDouble: true, onChanged: (v) => _craftSeconds = v.toDouble()),
            _numRow('Supply cost (fallback when there are no ingredients)', _supplyCost,
                isDouble: true, onChanged: (v) => _supplyCost = v.toDouble()),
            const SizedBox(height: 14),

            _sectionLabel('Trade (gold)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _numRow('Buy price (0 = not for sale)', _buyPrice,
                      onChanged: (v) => _buyPrice = v.toInt()),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow('Sell price', _sellPrice,
                      onChanged: (v) => _sellPrice = v.toInt()),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _saveButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _kindDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<ItemKind>(
      initialValue: _kind,
      dropdownColor: FoE.panelMid,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: const InputDecoration(labelText: 'Effekt'),
      items: [
        for (final k in ItemKind.values)
          DropdownMenuItem(value: k, child: Text(k.name)),
      ],
      onChanged: (v) => setState(() => _kind = v ?? _kind),
    ),
  );

  /// Which resource the pack holds. A pack with no resource would be an item
  /// that grants nothing, so this always has a value.
  Widget _packResourceDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: _resourceId ?? _packResources.first,
      decoration: const InputDecoration(labelText: 'Resource in the package'),
      dropdownColor: FoE.panelDark,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      items: [
        for (final r in _packResources)
          DropdownMenuItem(
            value: r,
            child: Text('${resourceEmoji(r)} ${resourceName(r)}'),
          ),
      ],
      onChanged: (v) => setState(() => _resourceId = v),
    ),
  );

  Widget _buffStatDropdown() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<CreatureStat>(
      initialValue: _buffStat ?? CreatureStat.attack,
      dropdownColor: FoE.panelMid,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: const InputDecoration(labelText: 'Buff-Stat'),
      items: [
        for (final s in CreatureStat.values)
          DropdownMenuItem(value: s, child: Text(s.label)),
      ],
      onChanged: (v) => setState(() => _buffStat = v),
    ),
  );

  Widget _ingredientRow(_IngredientDraft i) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: FoE.panel(radius: 8),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: kResourceEmoji.containsKey(i.key)
                ? i.key
                : kResourceEmoji.keys.first,
            isExpanded: true,
            dropdownColor: FoE.panelMid,
            style: FoE.label(size: 13).copyWith(color: FoE.parchment),
            decoration: const InputDecoration(labelText: 'Gut', isDense: true),
            items: [
              for (final k in kResourceEmoji.keys)
                DropdownMenuItem(value: k, child: Text('${kResourceEmoji[k]} $k')),
            ],
            onChanged: (v) => setState(() => i.key = v ?? i.key),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue:
                i.amount % 1 == 0 ? i.amount.toInt().toString() : i.amount.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: FoE.label(size: 14).copyWith(color: FoE.parchment),
            decoration: const InputDecoration(labelText: 'Amount', isDense: true),
            onChanged: (v) => i.amount = double.tryParse(v) ?? i.amount,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
          onPressed: () => setState(() => _ingredients.remove(i)),
        ),
      ],
    ),
  );

  // ── Shared widgets (same style as PathNodeForm) ──
  Widget _sectionLabel(String text) =>
      Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold));

  Widget _addButton(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: FoE.panel(radius: 8),
      child: Text(label, style: FoE.label(size: 13).copyWith(color: FoE.gold)),
    ),
  );

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged) =>
      GestureDetector(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(value ? Icons.check_box : Icons.check_box_outline_blank,
                  color: value ? FoE.gold : FoE.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: FoE.label(size: 14).copyWith(color: FoE.parchment)),
              ),
            ],
          ),
        ),
      );

  Widget _saveButton() => SizedBox(
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
                    strokeWidth: 2, color: FoE.goldBright),
              )
            : Text('Save',
                style: FoE.label(size: 14).copyWith(color: Colors.white)),
      ),
    ),
  );

  Widget _textRow(
    String label,
    String value, {
    bool enabled = true,
    required ValueChanged<String> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: value,
      enabled: enabled,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );

  Widget _numRow(
    String label,
    num value, {
    bool isDouble = false,
    required ValueChanged<num> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: isDouble ? value.toString() : value.toInt().toString(),
      keyboardType: TextInputType.numberWithOptions(decimal: isDouble),
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (v) {
        final parsed = isDouble ? double.tryParse(v) : int.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    ),
  );
}
