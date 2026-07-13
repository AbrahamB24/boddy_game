import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/tech_definitions.dart';
import '../services/game_defs_service.dart';
import '../widgets/building_icon.dart';
import 'dev_theme.dart';
import 'effects_editor.dart';
import 'resource_map_editor.dart';

// Create/edit form for a single BuildingDef. `existing == null` means
// creating a new one; the id field is then editable (and free-typed — no
// server-side existence check, matches this codebase's "single trusted
// author" convention for dev-mode content).
class BuildingDefForm extends StatefulWidget {
  final BuildingDef? existing;
  const BuildingDefForm({super.key, this.existing});

  @override
  State<BuildingDefForm> createState() => _BuildingDefFormState();
}

class _BuildingDefFormState extends State<BuildingDefForm> {
  final _svc = GameDefsService();
  bool _saving = false;
  bool _uploadingImage = false;

  late String _id;
  late String _name;
  String? _imageUrl;
  late String _colorHex;
  late int _gridW;
  late int _gridH;
  late double _constructionHours;
  late Set<String> _eraIds;
  late bool _isMainBuilding;
  late bool _isUnique;
  late bool _isRoad;
  late bool _isBuildPlot;
  String? _requiredTechId;
  late int _population;
  late int _workerRequirement;
  late int _maxLaborers;
  late int _maxCount;
  late Map<String, double> _resourceCost;
  late List<Map<String, dynamic>> _effects;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _imageUrl = d?.imageUrl;
    _colorHex = d == null
        ? 'FF7C5CBF'
        : d.color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');
    _gridW = d?.gridW ?? 1;
    _gridH = d?.gridH ?? 1;
    _constructionHours = d?.constructionHours ?? 0;
    _eraIds = Set.of(d?.eraIds ?? const []);
    _isMainBuilding = d?.isMainBuilding ?? false;
    _isUnique = d?.isUnique ?? false;
    _isRoad = d?.isRoad ?? false;
    _isBuildPlot = d?.isBuildPlot ?? false;
    _requiredTechId = d?.requiredTechId;
    _population = d?.population ?? 0;
    _workerRequirement = d?.workerRequirement ?? 0;
    _maxLaborers = d?.maxLaborers ?? 0;
    _maxCount = d?.maxCount ?? 1;
    _resourceCost = Map.of(d?.resourceCost ?? const {});
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

    // Build the non-effects fields via the normal constructor, dump to a
    // row, then splice in the edited effects and re-parse through
    // fromDefRow — the exact same translation path GameDefsController uses
    // on load, so the form never duplicates that logic.
    final base = BuildingDef(
      id: _id.trim(),
      name: _name.trim(),
      imageUrl: _imageUrl,
      color: Color(int.parse(_colorHex, radix: 16)),
      gridW: _gridW,
      gridH: _gridH,
      resourceCost: _resourceCost,
      constructionHours: _constructionHours,
      eraIds: _eraIds.toList(),
      isMainBuilding: _isMainBuilding,
      isUnique: _isUnique,
      isRoad: _isRoad,
      isBuildPlot: _isBuildPlot,
      requiredTechId: _requiredTechId,
      population: _population,
      workerRequirement: _workerRequirement,
      maxLaborers: _maxLaborers,
      maxCount: _maxCount,
    );
    final row = base.toDefRow();
    row['effects'] = _effects;
    final finalDef = BuildingDef.fromDefRow(row);

    try {
      await _svc.upsertBuildingDef(finalDef);
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

  Future<void> _uploadImage() async {
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

    setState(() => _uploadingImage = true);
    try {
      final url = await _svc.uploadBuildingImage(_id.trim(), bytes);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete building?',
      message: 'This removes "$_id" for every player immediately.',
    );
    if (!ok) return;
    await _svc.deleteBuildingDef(_id);
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
            _isNew ? 'New Building' : 'Edit Building',
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
              'Id (slug, e.g. lumber_camp)',
              _id,
              enabled: _isNew,
              onChanged: (v) => _id = v,
            ),
            _textRow('Name', _name, onChanged: (v) => _name = v),
            _imageRow(),
            const SizedBox(height: 12),
            _textRow(
              'Color (8-hex ARGB)',
              _colorHex,
              onChanged: (v) => _colorHex = v,
            ),
            Row(
              children: [
                Expanded(
                  child: _numRow(
                    'Grid width',
                    _gridW,
                    onChanged: (v) => _gridW = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'Grid height',
                    _gridH,
                    onChanged: (v) => _gridH = v,
                  ),
                ),
              ],
            ),
            _numRow(
              'Construction hours',
              _constructionHours,
              isDouble: true,
              onChanged: (v) => _constructionHours = v,
            ),
            _numRow(
              'Max count (0 = unlimited)',
              _maxCount,
              onChanged: (v) => _maxCount = v,
            ),
            _numRow(
              'Housing capacity (creatures sheltered)',
              _population,
              onChanged: (v) => _population = v,
            ),
            Text(
              'Add work stations via the Effects editor below '
              '(type "workshop"). Each staffs specific creatures whose civilian '
              'stat drives its output.',
              style: FoE.dim(size: 11),
            ),
            const SizedBox(height: 8),
            Text(
              'Eras (empty = available in every era)',
              style: FoE.label(size: 12).copyWith(color: FoE.gold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children:
                  (kEraDefs.values.toList()
                        ..sort((a, b) => a.order.compareTo(b.order)))
                      .map((era) {
                        final selected = _eraIds.contains(era.id);
                        return FilterChip(
                          label: Text(
                            '${era.emoji} ${era.name}',
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
                              _eraIds.add(era.id);
                            } else {
                              _eraIds.remove(era.id);
                            }
                          }),
                        );
                      })
                      .toList(),
            ),
            const SizedBox(height: 8),
            _dropdownRow(
              'Required tech',
              _requiredTechId,
              kTechDefs.keys.toList(),
              (v) => setState(() => _requiredTechId = v),
            ),
            const SizedBox(height: 12),
            _checkboxRow(
              'Main Hall',
              _isMainBuilding,
              (v) => setState(() => _isMainBuilding = v),
            ),
            _checkboxRow(
              'Unique (max 1)',
              _isUnique,
              (v) => setState(() => _isUnique = v),
            ),
            _checkboxRow('Road', _isRoad, (v) => setState(() => _isRoad = v)),
            _checkboxRow(
              'Build Plot (expands territory)',
              _isBuildPlot,
              (v) => setState(() => _isBuildPlot = v),
            ),
            const SizedBox(height: 16),
            Text(
              'Resource cost',
              style: FoE.label(size: 14).copyWith(color: FoE.gold),
            ),
            const SizedBox(height: 8),
            ResourceMapEditor(
              values: _resourceCost,
              onChanged: (m) => setState(() => _resourceCost = m),
            ),
            const SizedBox(height: 16),
            EffectsEditor(
              initialEffects: _effects,
              mode: EffectsMode.building,
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

  Widget _imageRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: FoE.panel(radius: 8),
            child: BuildingIcon(imageUrl: _imageUrl, size: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image (PNG)',
                  style: FoE.label(size: 12).copyWith(color: FoE.gold),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _uploadingImage ? null : _uploadImage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: FoE.btn(),
                    alignment: Alignment.center,
                    child: _uploadingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _imageUrl == null ? 'Upload PNG' : 'Replace PNG',
                            style: FoE.label(size: 13),
                          ),
                  ),
                ),
              ],
            ),
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

  Widget _dropdownRow(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
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

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: FoE.gold,
            ),
            Text(
              label,
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
            ),
          ],
        ),
      ),
    );
  }
}
