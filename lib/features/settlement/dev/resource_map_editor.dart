import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';

// Simple key(resource id)/value(amount) editor for a flat Map<String,double>
// — used for BuildingDef.resourceCost, EraDef.advancementCost and
// EraDef.grantResources. Separate from EffectsEditor since these are plain
// maps, not the tagged-union effects vocabulary.
class ResourceMapEditor extends StatefulWidget {
  final Map<String, double> values;
  final String hintText;
  final ValueChanged<Map<String, double>> onChanged;
  const ResourceMapEditor({
    super.key,
    required this.values,
    required this.onChanged,
    this.hintText = 'resource id (wood, stone, grain, ...)',
  });

  @override
  State<ResourceMapEditor> createState() => _ResourceMapEditorState();
}

class _ResourceMapEditorState extends State<ResourceMapEditor> {
  late Map<String, double> _values;
  final _newKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _values = Map.of(widget.values);
  }

  @override
  void dispose() {
    _newKeyController.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_values);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in _values.entries.toList())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    entry.key,
                    style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: entry.value.toString(),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        setState(() => _values[entry.key] = parsed);
                        _emit();
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  onPressed: () {
                    setState(() => _values.remove(entry.key));
                    _emit();
                  },
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _newKeyController,
                style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                final key = _newKeyController.text.trim();
                if (key.isEmpty || _values.containsKey(key)) return;
                setState(() {
                  _values[key] = 0;
                  _newKeyController.clear();
                });
                _emit();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: FoE.btn(),
                child: Text(
                  'Add',
                  style: FoE.label(size: 14).copyWith(color: FoE.goldBright),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
