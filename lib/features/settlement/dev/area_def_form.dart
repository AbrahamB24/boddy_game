import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/widgets/battle_scene.dart';
import '../services/game_defs_service.dart';
import 'dev_theme.dart';

// Create/edit form for a single overworld AreaDef — same trusted-single-author
// dev-content pattern as EraDefForm. `battle_stage` doubles as the unlock gate
// (an area unlocks once dungeonMaxStage reaches it), so keep the stages a
// sensible ascending sequence across areas. An empty species pool means "every
// defined species is catchable here".
class AreaDefForm extends StatefulWidget {
  final AreaDef? existing;
  const AreaDefForm({super.key, this.existing});

  @override
  State<AreaDefForm> createState() => _AreaDefFormState();
}

class _SpotDraft {
  String id;
  String resource;
  _SpotDraft({
    required this.id,
    required this.resource,
  });
}

class _AreaDefFormState extends State<AreaDefForm> {
  final _svc = GameDefsService();
  bool _saving = false;

  late String _id;
  late String _name;
  late String _emoji;

  /// The battlefield art for fights in this region (user 2026-07-31). Null =
  /// the era gradient, which is a finished look rather than a missing one.
  String? _imageUrl;
  bool _uploading = false;
  late int _order;
  late String _description;
  late int _battleStage;
  late int _dangerLevel;
  late List<_SpotDraft> _spots;
  late Set<String> _pool;
  String? _bossSpeciesId;
  int _spotSeq = 0;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _name = d?.name ?? '';
    _emoji = d?.emoji ?? '🗺️';
    _imageUrl = d?.imageUrl;
    _order = d?.order ??
        (kAreaDefs.values.isEmpty
            ? 1
            : kAreaDefs.values.map((a) => a.order).reduce((a, b) => a > b ? a : b) + 1);
    _description = d?.description ?? '';
    _battleStage = d?.battleStage ?? _order;
    _dangerLevel = d?.dangerLevel ?? 1;
    _spots = [
      for (final s in d?.spots ?? const <ResourceSpotDef>[])
        _SpotDraft(
          id: s.id,
          resource: s.resource,
        ),
    ];
    _pool = {...?d?.speciesPoolIds};
    _bossSpeciesId = d?.bossSpeciesId;
  }

  void _addSpot() {
    setState(() {
      _spots.add(_SpotDraft(
        id: '${_id.isEmpty ? 'area' : _id}_s${_spotSeq++}',
        resource: 'wood',
      ));
    });
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('id and name are required')),
      );
      return;
    }
    setState(() => _saving = true);
    final def = AreaDef(
      id: _id.trim(),
      name: _name.trim(),
      emoji: _emoji.trim(),
      imageUrl: _imageUrl,
      order: _order,
      description: _description.trim(),
      battleStage: _battleStage,
      dangerLevel: _dangerLevel,
      spots: [
        for (final s in _spots)
          ResourceSpotDef(
            id: s.id.trim().isEmpty ? '${_id.trim()}_s${_spots.indexOf(s)}' : s.id.trim(),
            resource: s.resource,
          ),
      ],
      speciesPoolIds: _pool.toList(),
      bossSpeciesId: _bossSpeciesId,
    );
    try {
      await _svc.upsertAreaDef(def);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  /// Uploads this region's battlefield scene.
  ///
  /// Same bucket as the building art (public, dev-gated writes) under an
  /// `area_` prefix — a second bucket would have meant a second storage policy
  /// for the same trust boundary.
  Future<void> _pickImage() async {
    if (_id.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set the id first — it names the file.')),
      );
      return;
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    final bytes = result?.files.single.bytes;
    if (bytes == null) return; // picker cancelled
    setState(() => _uploading = true);
    try {
      final url = await _svc.uploadBuildingImage('area_${_id.trim()}', bytes);
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// The scene row: a preview of what a fight here will look like, the upload
  /// button, and a way to drop back to the gradient.
  Widget _imageRow() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 92,
            height: 56,
            child: _imageUrl == null
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: BattleScene.paletteFor(_battleStage),
                      ),
                    ),
                    child: Center(
                      child: Text('Ära $_battleStage', style: FoE.dim(size: 10)),
                    ),
                  )
                : Image.network(_imageUrl!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _imageUrl == null
                ? 'Kein Bild — der Kampf nutzt den Verlauf dieser Ära.'
                : 'Kampfplatz-Bild gesetzt.',
            style: FoE.dim(size: 11),
          ),
        ),
        if (_uploading)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: FoE.goldBright,
            ),
          )
        else ...[
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: FoE.btn(active: true),
              child: Text('Bild',
                  style: FoE.label(size: 12).copyWith(color: Colors.white)),
            ),
          ),
          if (_imageUrl != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
              onPressed: () => setState(() => _imageUrl = null),
            ),
        ],
      ],
    ),
  );

  Future<void> _delete() async {
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete area?',
      message: 'This removes "$_id" from the overworld for every player.',
    );
    if (!ok) return;
    try {
      await _svc.deleteAreaDef(_id);
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
    final species = kSpeciesDefs.values.toList();
    return Theme(
      data: buildDevModeTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New Area' : 'Edit Area', style: FoE.title(size: 16)),
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
            _textRow('Id (slug, e.g. verdant_hollow)', _id,
                enabled: _isNew, onChanged: (v) => _id = v),
            _textRow('Name', _name, onChanged: (v) => _name = v),
            Row(
              children: [
                Expanded(child: _textRow('Emoji', _emoji, onChanged: (v) => _emoji = v)),
                const SizedBox(width: 8),
                Expanded(child: _numRow('Order', _order, onChanged: (v) => _order = v)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _numRow('Battle stage (unlock gate)', _battleStage,
                      onChanged: (v) => _battleStage = v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow('Danger (1-5)', _dangerLevel,
                      onChanged: (v) => setState(() => _dangerLevel = v.clamp(1, 5))),
                ),
              ],
            ),
            _imageRow(),
            _textRow('Description', _description, onChanged: (v) => _description = v),
            const SizedBox(height: 16),
            _sectionLabel('Resource spots'),
            const SizedBox(height: 8),
            ..._spots.map(_spotRow),
            _addButton('+ Add spot', _addSpot),
            const SizedBox(height: 16),
            _sectionLabel('Catch pool (empty = every species)'),
            const SizedBox(height: 8),
            if (species.isEmpty)
              Text('No species defined yet.',
                  style: FoE.label(size: 12).copyWith(color: FoE.textDim))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in species)
                    _chip(
                      '${s.element.emoji} ${s.name}',
                      _pool.contains(s.id),
                      () => setState(() =>
                          _pool.contains(s.id) ? _pool.remove(s.id) : _pool.add(s.id)),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            _sectionLabel('Boss species (optional)'),
            const SizedBox(height: 8),
            if (species.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('None', _bossSpeciesId == null,
                      () => setState(() => _bossSpeciesId = null)),
                  for (final s in species)
                    _chip('${s.element.emoji} ${s.name}', _bossSpeciesId == s.id,
                        () => setState(() => _bossSpeciesId = s.id)),
                ],
              ),
            const SizedBox(height: 20),
            _saveButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _spotRow(_SpotDraft s) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: FoE.panel(radius: 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: s.resource,
                dropdownColor: FoE.panelMid,
                style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                decoration: const InputDecoration(labelText: 'Resource'),
                items: [
                  for (final r in kResourceEmoji.keys)
                    DropdownMenuItem(value: r, child: Text('${kResourceEmoji[r]} $r')),
                ],
                onChanged: (v) => setState(() => s.resource = v ?? s.resource),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
              onPressed: () => setState(() => _spots.remove(s)),
            ),
          ],
        ),
        // Kapazität, Nachfüllrate und Abbaugeschwindigkeit stehen NICHT mehr
        // pro Spot (user 2026-07-25) — ein Spot sagt nur noch, welche Ressource
        // hier liegt. Die Zahlen kommen aus Dev Mode → Ressourcen.
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Amount, refill rate & mining speed: Dev Mode → Resources',
            style: FoE.dim(size: 10),
          ),
        ),
      ],
    ),
  );

  Widget _sectionLabel(String text) =>
      Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold));

  Widget _chip(String label, bool selected, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: FoE.btn(active: selected),
      child: Text(label,
          style: FoE.label(size: 12)
              .copyWith(color: selected ? Colors.white : FoE.parchment)),
    ),
  );

  Widget _addButton(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: FoE.panel(radius: 8),
      child: Text(label, style: FoE.label(size: 13).copyWith(color: FoE.gold)),
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
                child: CircularProgressIndicator(strokeWidth: 2, color: FoE.goldBright),
              )
            : Text('Save', style: FoE.label(size: 14).copyWith(color: Colors.white)),
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
    required ValueChanged<dynamic> onChanged,
  }) => TextFormField(
    initialValue: isDouble ? value.toString() : value.toInt().toString(),
    keyboardType: TextInputType.numberWithOptions(decimal: isDouble),
    style: FoE.label(size: 15).copyWith(color: FoE.parchment),
    decoration: InputDecoration(labelText: label),
    onChanged: (v) {
      final parsed = isDouble ? double.tryParse(v) : int.tryParse(v);
      if (parsed != null) onChanged(parsed);
    },
  );
}
