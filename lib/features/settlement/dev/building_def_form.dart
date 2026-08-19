import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_art.dart';
import '../data/building_definitions.dart';
import '../data/iso_grid.dart';
import '../data/era_definitions.dart';
import '../data/goods_definitions.dart';
import '../services/game_defs_controller.dart';
import '../services/game_defs_service.dart';
import '../settlement_controller.dart';
import '../widgets/building_icon.dart';
import 'dev_theme.dart';
import 'effects_editor.dart';

// Create/edit form for a single BuildingDef. `existing == null` means
// creating a new one. Three tabs — Basis, Bau, Kosten & Effekte.
//
// Redesign 2026-07-24 (user): the id is editable even when editing (a rename
// writes a new Supabase row + deletes the old, like SpeciesDefForm); Color and
// Housing left the form; era became a single "ab welcher Ära baubar" dropdown;
// the tech gate is a searchable dropdown; costs are authored EXPLICITLY per
// level (good picked from a dropdown), with the Cost ×/Level factor as an
// autofill helper.
//
// The Main-Hall / Unique / Build-Plot flags left the form in that redesign too
// ("special-cased buildings, edited elsewhere — their values are preserved on
// save"). They are BACK under Platzierung (2026-07-26): preserving a field
// while hiding it means a def that has one set can never be turned back into an
// ordinary building here, and the only symptom is its card behaving oddly in
// the Build menu — a stone camp that painted roads is what found this.
class BuildingDefForm extends StatefulWidget {
  final BuildingDef? existing;
  const BuildingDefForm({super.key, this.existing});

  @override
  State<BuildingDefForm> createState() => _BuildingDefFormState();
}

class _BuildingDefFormState extends State<BuildingDefForm>
    with SingleTickerProviderStateMixin {
  final _svc = GameDefsService();
  bool _saving = false;
  bool _uploadingImage = false;

  /// The three editor sections — Basis, Bau, Kosten & Effekte.
  late final TabController _tabs;

  late String _id;
  // The id as loaded — a RENAME deletes this old Supabase row on save.
  late String _originalId;
  late String _name;
  String? _imageUrl;
  // Preserved but no longer edited here (user 2026-07-24): a building keeps its
  // colour, housing column and special flags; they are authored in code / other
  // screens, so the form just carries them through untouched on save.
  // ── Wo die Grundfläche im Bild sitzt (user 2026-08-01) ──
  // Generated art comes back square with the building somewhere inside it, so
  // the map has to be told where the BASE is before it can stand the building
  // on its tiles. Three numbers, edited right under the upload because they
  // describe the PICTURE — change the PNG and they change with it.
  late double _artBaseWidth;
  late double _artAnchorX;
  late double _artLift;

  late String _colorHex;
  late int _population;
  late bool _isMainBuilding;
  late bool _isUnique;
  late bool _isBuildPlot;

  late int _gridW;
  late int _gridH;
  late double _constructionHours;
  // The era ORDER this building first becomes buildable in (null = every era,
  // for Road/Main Hall). Stored as the contiguous era-id suffix in eraIds.
  int? _startEraOrder;
  late bool _isRoad;
  String? _requiredTechId;
  late int _maxCount;
  /// Which Build-menu drawer this building appears in. Null = "Automatic",
  /// i.e. let categoryOfBuilding derive it — the state every bundled building
  /// starts in, so nothing had to be hand-sorted for the field to exist.
  BuildingCategory? _category;
  late double _costFactor;
  late double _timeFactor;
  late Map<int, int> _maxLevelPerEra;
  // Per-ERA build resources while editing: era order → {resource → base amount}.
  // The factor scales them per level within each era's band (see the Kosten tab).
  late Map<int, Map<String, double>> _costByEra;
  late List<Map<String, dynamic>> _effects;
  // Build-time calculator inputs. `_calcPassivePoints` used to be a hall LEVEL
  // times a hardcoded per-level rate; nothing in code grants that anymore
  // (effects-only economy, 2026-07-25), so it is now what it always really was:
  // however many points the settlement's buildings hand over passively.
  // `_calcMult` is the "Bau-Punkte pro Statpunkt" dial the builder post carries.
  int _calcPassivePoints = 0;
  double _calcMult = 1.0;
  final List<({int count, int stat})> _builders = [];
  // Construction time entered as H:M:S — folds into _constructionHours.
  late int _ch;
  late int _cm;
  late int _cs;

  bool get _isNew => widget.existing == null;

  void _recomputeHours() => _constructionHours = _ch + _cm / 60 + _cs / 3600;

  /// Sorted era list — reused by the "ab Ära" dropdown and max-level editor.
  List<EraDef> get _eras =>
      kEraDefs.values.toList()..sort((a, b) => a.order.compareTo(b.order));

  /// Highest level to author costs / preview build time for: the highest
  /// per-era cap (that value IS the building's maximum level, user 2026-07-24),
  /// or just level 1 when no cap is set at all.
  int get _previewMaxLevel {
    if (_maxLevelPerEra.values.isEmpty) return 1;
    return _maxLevelPerEra.values.reduce(math.max).clamp(1, 99);
  }

  /// Every resource an author can charge for: the settlement raws + all goods.
  List<String> get _allResourceIds => ['wood', 'stone', 'gold', ...kGoodsDefs.keys];

  String _resourceLabel(String id) {
    final g = kGoodsDefs[id];
    if (g != null) return '${g.emoji} ${g.name}';
    return const {
          'wood': '🪵 Wood',
          'stone': '🪨 Stone',
          'gold': '🪙 Gold',
        }[id] ??
        id;
  }

  /// The era that introduces a resource — a good's own [GoodsDef.eraOrder], and
  /// era 1 for the base settlement resources (wood/stone/gold).
  int _resourceEra(String id) => kGoodsDefs[id]?.eraOrder ?? 1;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _originalId = _id;
    _name = d?.name ?? '';
    _imageUrl = d?.imageUrl;
    _artBaseWidth = d?.artBaseWidth ?? 1.0;
    _artAnchorX = d?.artAnchorX ?? 0.5;
    _artLift = d?.artLift ?? 0.0;
    _colorHex = d == null
        ? 'FF7C5CBF'
        : d.color.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');
    _population = d?.population ?? 0;
    _isMainBuilding = d?.isMainBuilding ?? false;
    _isUnique = d?.isUnique ?? false;
    _isBuildPlot = d?.isBuildPlot ?? false;
    _gridW = d?.gridW ?? 1;
    _gridH = d?.gridH ?? 1;
    _constructionHours = d?.constructionHours ?? 0;
    final totalSec = (_constructionHours * 3600).round();
    _ch = totalSec ~/ 3600;
    _cm = (totalSec % 3600) ~/ 60;
    _cs = totalSec % 60;
    // First buildable era = the lowest era order in eraIds (empty = every era).
    final orders = (d?.eraIds ?? const [])
        .map((id) => kEraDefs[id]?.order)
        .whereType<int>();
    _startEraOrder = orders.isEmpty ? null : orders.reduce(math.min);
    _isRoad = d?.isRoad ?? false;
    _requiredTechId = d?.requiredTechId;
    _maxCount = d?.maxCount ?? 1;
    _category = d?.category;
    _costFactor = d?.costFactor ?? 1.6;
    _timeFactor = d?.timeFactor ?? 1.6;
    _maxLevelPerEra = Map.of(d?.maxLevelPerEra ?? const {});
    _costByEra = _seedCosts(d);
    _effects = d == null
        ? []
        : ((d.toDefRow()['effects'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
    // Surface the flat HOUSING (the legacy `population` column) as a real,
    // editable `housing` effect so it shows up in the Effects tab like every
    // other effect (user 2026-07-24: "Housing bei den Häusern ist nicht bei den
    // Effekten abgedeckt"). Behaviour-preserving: GameEngine.housingCapacity
    // already prefers a `housing` effect over the population column, and an
    // effect with no per-level factor scales by the same global curve the
    // column fallback used. Migrated to the effect as the single source, so the
    // column is cleared on save.
    if (_population > 0 && !_effects.any((e) => e['type'] == 'housing')) {
      _effects.add({'type': 'housing', 'value': _population, 'era': 1});
      _population = 0;
    }
    // Every HOUSE also gets a passive GOLD production effect auto-added, if it
    // doesn't already have one (user 2026-07-24: "füge bei allen Häusern
    // automatisch diese beiden Effekte hinzu, falls nicht schon gemacht").
    // A house is anything with a housing effect (the block above guarantees one
    // for every dwelling). There is no global gold trickle behind it any more
    // (user 2026-07-25) — what this effect says is what the house pays.
    final isHouse = _effects.any((e) => e['type'] == 'housing');
    final hasGold = _effects.any(
        (e) => e['type'] == 'production' && e['key'] == 'gold');
    if (isHouse && !hasGold) {
      // A starting point to edit, not a hidden rule: the passive house-gold
      // curve used to live in code (HouseEconomy) and was invisible here. It is
      // an ordinary authored effect now — change or delete it freely.
      _effects.add({
        'type': 'production',
        'key': 'gold',
        'value': 2.0,
        'levelFactor': 1.35,
        'era': 1,
      });
    }
    // BREEDING buildings (Breeding Hut + Hatchery) auto-get their three effects
    // (user 2026-07-24): breeder WORK POSTS (breeding stat), the XP factor per
    // worker, and the CONCURRENT-JOB cap — so they show up editable like every
    // other effect, each only if not already present ("falls nicht schon
    // gemacht").
    //
    // Each gets its OWN keys (user 2026-07-26): the hut works in `breeding`,
    // the Hatchery in `hatching`. Same three effects, same shape — but two
    // buildings that are staffed and capped independently.
    if (_id == 'breeding_hut' || _id == 'hatchery') {
      final hatchery = _id == 'hatchery';
      final post = hatchery ? WorkshopRole.kHatching : WorkshopRole.kBreeding;
      final jobs = hatchery ? 'hatching' : 'breeding';
      if (!_effects.any((e) => e['type'] == 'workshop')) {
        _effects.add({
          'type': 'workshop',
          'stat': 'breeding', // the same civilian stat drives both posts
          'resource': post,
          'mult': 1.0,
          'slots': 2,
        });
      }
      // (No `xp` effect any more — since 2026-07-30 every building with a work
      // post pays one settlement-wide rate, so there is nothing per-building
      // left to seed. See XpConfig.workPerHour.)
      if (!_effects.any((e) => e['type'] == jobs)) {
        _effects.add({'type': jobs, 'value': 1, 'era': 1});
      }
    }
    _tabs = TabController(length: 4, vsync: this);
  }

  /// Seeds the per-ERA cost table: [costPerEra] if the def has it, else the flat
  /// [resourceCost] as the start era's base (so an old factor-based building
  /// opens already populated and editable).
  Map<int, Map<String, double>> _seedCosts(BuildingDef? d) {
    if (d == null) return {};
    if (d.costPerEra.isNotEmpty) {
      return {for (final e in d.costPerEra.entries) e.key: Map.of(e.value)};
    }
    if (d.resourceCost.isEmpty) return {};
    return {d.startEraOrder: Map.of(d.resourceCost)};
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// True when this building has a render bundled with the app.
  bool get _hasModel => kBundledBuildingArt.contains(_id.trim());

  /// Pull the footprint and the art placement out of the MODEL.
  ///
  /// ── Why this exists (user 2026-08-12) ──
  /// The renderer measures both of them and writes them into
  /// building_art_box.dart, and until now the only way into a live database
  /// was building_roster.sql — which deletes all 89 rows and rewrites them,
  /// taking every hand-tuned value with it. This changes one building.
  ///
  /// image_url is cleared on purpose: a bundled picture already beats it (see
  /// building_art.dart), so a URL left behind is a value that looks live,
  /// previews in this form, and is never drawn on the map again.
  void _applyFromModel() {
    final id = _id.trim();
    final def = kFallbackBuildingDefs[id];
    final box = kBundledArtBox[id];
    if (def == null || box == null) return;
    setState(() {
      _gridW = def.gridW;
      _gridH = def.gridH;
      _artBaseWidth = box.$1;
      _artAnchorX = box.$2;
      _artLift = box.$3;
      _imageUrl = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$id: ${def.gridW} x ${def.gridH}, Basis ${box.$1}/'
          '${box.$2}/${box.$3} — noch nicht gespeichert',
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    setState(() => _saving = true);

    // Contiguous era suffix from the chosen start era (null = every era).
    final eraIds = _startEraOrder == null
        ? const <String>[]
        : [
            for (final e in _eras)
              if (e.order >= _startEraOrder!) e.id,
          ];

    // Per-era build resources → {era: {resource: base amount}} (drop empties),
    // plus the FIRST era's map as the flat resource_cost column (level-1 cost,
    // for backward-compat + canAfford). Only eras that actually have a level
    // band are kept, so a no-level era leaves no stale cost behind.
    final bandEras = {for (final b in _costBands()) b.era};
    final costPerEra = <int, Map<String, double>>{};
    for (final e in _costByEra.entries) {
      if (!bandEras.contains(e.key)) continue;
      final m = {
        for (final r in e.value.entries)
          if (r.value > 0) r.key: r.value,
      };
      if (m.isNotEmpty) costPerEra[e.key] = m;
    }
    final firstEra = costPerEra.keys.isEmpty
        ? null
        : (costPerEra.keys.toList()..sort()).first;
    final resourceCost =
        firstEra == null ? const <String, double>{} : costPerEra[firstEra]!;

    // Build the non-effects fields via the normal constructor, dump to a row,
    // splice in the edited effects and re-parse through fromDefRow — the exact
    // translation path GameDefsController uses on load.
    final base = BuildingDef(
      id: _id.trim(),
      name: _name.trim(),
      imageUrl: _imageUrl,
      artBaseWidth: _artBaseWidth,
      artAnchorX: _artAnchorX,
      artLift: _artLift,
      color: Color(int.parse(_colorHex, radix: 16)),
      gridW: _gridW,
      gridH: _gridH,
      resourceCost: resourceCost,
      constructionHours: _constructionHours,
      eraIds: eraIds,
      isMainBuilding: _isMainBuilding,
      isUnique: _isUnique,
      isRoad: _isRoad,
      isBuildPlot: _isBuildPlot,
      requiredTechId: _requiredTechId,
      population: _population,
      maxCount: _maxCount,
      category: _category,
      maxLevelPerEra: _maxLevelPerEra,
      costFactor: _costFactor,
      timeFactor: _timeFactor,
      costPerEra: costPerEra,
    );
    final row = base.toDefRow();
    row['effects'] = _effects;
    final finalDef = BuildingDef.fromDefRow(row);

    try {
      await GameDefsController().saveBuildingDef(finalDef);
      // RENAME (user 2026-07-24): the id is the primary key, so a rename is a
      // new row under the new id + delete of the old one.
      if (!_isNew && finalDef.id != _originalId && _originalId.isNotEmpty) {
        await GameDefsController().deleteBuildingDef(_originalId);
      }
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
    // WHAT IT REALLY DOES, in the dialog (user 2026-07-31). A bundled building
    // is retired rather than deleted — the fallback is code, so absence cannot
    // express "gone" — and that is reversible. A custom one is not.
    final bundled = kFallbackBuildingDefs.containsKey(_id);
    final placed = SettlementController()
        .buildings
        .where((b) => b.buildingTypeId == _id)
        .length;
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete building?',
      message: [
        'This removes "$_id" for every player immediately.',
        if (placed > 0)
          '$placed already stand in your settlement and will stop working.',
        if (bundled)
          'It is a bundled building, so it is RETIRED and can be brought back '
              'from the roster list.'
        else
          'It is a custom building, so this cannot be undone.',
      ].join('\n\n'),
    );
    if (!ok) return;
    // A FAILED DELETE MUST SAY SO (user 2026-07-31: "wenn ich auf delete
    // drücke, passiert nichts bei den gebäuden"). The await used to stand bare:
    // any error — a missing `retired` column on a database that has not run
    // migration 0034, an RLS refusal, no connection — threw past this method as
    // an unhandled async error. The form simply stayed open, which is
    // indistinguishable from a button that does nothing.
    setState(() => _saving = true);
    try {
      await GameDefsController().deleteBuildingDef(_id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
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
            _isNew ? 'New Building' : 'Edit Building',
            style: FoE.title(size: 16),
          ),
          actions: [
            _saving
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FoE.goldBright,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.save_outlined, color: FoE.goldBright),
                    tooltip: 'Save',
                    onPressed: _save,
                  ),
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Delete',
                onPressed: _delete,
              ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            labelColor: FoE.goldBright,
            unselectedLabelColor: FoE.textDim,
            indicatorColor: FoE.gold,
            tabs: const [
              Tab(text: 'Basis'),
              Tab(text: 'Build'),
              Tab(text: 'Cost'),
              Tab(text: 'Effekte'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _tabBody(_basicsTab()),
            _tabBody(_constructionTab()),
            _tabBody(_costTab()),
            _tabBody(_effectsTab()),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(List<Widget> children) => ListView(
    // Generous bottom room so the LAST fields (e.g. a housing effect's per-level
    // list + the era picker + "+ Add Effect") can scroll clear of the phone
    // frame's rounded bottom instead of being clipped there (user 2026-07-24).
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 140),
    children: children,
  );

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
  );

  // ── Tab 1: Basis ────────────────────────────────────────────
  List<Widget> _basicsTab() => [
    _sectionLabel('Identity'),
    _textRow(
      _isNew
          ? 'Id (slug, e.g. lumber_camp)'
          : 'Id (renaming deletes the old Supabase row on save)',
      _id,
      onChanged: (v) => _id = v,
    ),
    _textRow('Name', _name, onChanged: (v) => _name = v),
    _imageRow(),
    const SizedBox(height: 12),
    _sectionLabel('Type'),
    _categoryDropdown(),
    const SizedBox(height: 12),
    _sectionLabel('Size & limits'),
    Row(
      children: [
        Expanded(
          child: _numRow('Grid width', _gridW, onChanged: (v) => _gridW = v),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _numRow('Grid height', _gridH, onChanged: (v) => _gridH = v),
        ),
      ],
    ),
    _numRow(
      'Max count (0 = unlimited)',
      _maxCount,
      onChanged: (v) => _maxCount = v,
    ),
    const SizedBox(height: 12),
    _sectionLabel('Placement'),
    // ALL FOUR flags, not just Road (user 2026-07-26). The form carried
    // isBuildPlot / isMainBuilding / isUnique through every save while showing
    // none of them — so a def that had one set could not be turned back into an
    // ordinary building here, and the only symptom was its card behaving
    // strangely in the Build menu. A field the editor preserves but never shows
    // is a field you can only get wrong once.
    _checkboxRow(
      'Road (painted, not placed)',
      _isRoad,
      (v) => setState(() => _isRoad = v),
    ),
    _checkboxRow(
      'Build plot (expands territory, occupies no space)',
      _isBuildPlot,
      (v) => setState(() => _isBuildPlot = v),
    ),
    _checkboxRow(
      'Main building (auto-placed, no work posts)',
      _isMainBuilding,
      (v) => setState(() => _isMainBuilding = v),
    ),
    _checkboxRow(
      'Unique (only one per settlement)',
      _isUnique,
      (v) => setState(() => _isUnique = v),
    ),
    const SizedBox(height: 12),
    _sectionLabel('Availability'),
    _eraDropdown(),
    const SizedBox(height: 12),
    // Map unlock (which battle/node makes this building buildable) is authored
    // in the Path editor now, not here (user 2026-07-25). Shown read-only.
    _mapUnlockNote(),
  ];

  /// Which drawer of the Build menu this building appears in (user 2026-07-26:
  /// "hier muss ich wählen können, welche typ von Gebäude es ist … diese
  /// kategorien so auch im Build menü übernehmen").
  ///
  /// "Automatic" is kept as a real option and is the default: the menu used
  /// to infer every category from what a def did, and 80-odd bundled buildings
  /// already sit where that inference put them. Choosing it explicitly is how
  /// you DISAGREE with the inference — so the row also states where a building
  /// would land on its own, otherwise "Automatic" says nothing.
  Widget _categoryDropdown() {
    // Road / Build Plot / Main Hall are Special by RULE — they don't place like
    // a building, so the menu treats their cards differently and moving one
    // into another drawer would put a road-painting card among the camps. Say
    // so instead of offering a choice that categoryOfBuilding then ignores.
    if (_isRoad || _isBuildPlot || _isMainBuilding) {
      // NAME the flag. "Is Special" on a building the author thinks is an
      // ordinary camp is a dead end unless it also says which checkbox below
      // put it there (user 2026-07-26 — a stone camp that painted roads).
      final why = _isRoad
          ? 'Road'
          : _isBuildPlot
          ? 'Build plot'
          : 'Main building';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Building type (Build-menu category)',
          ),
          child: Text(
            'Locked to «Special» because «$why» is ticked under Placement. '
            'Those three are not placed like a building (a road paints), '
            'so they stay in this category. Untick it to categorise the '
            'building normally.',
            style: FoE.dim(size: 13).copyWith(color: FoE.gold),
          ),
        ),
      );
    }
    final derived = categoryOfBuilding(
      BuildingDef(
        id: _id,
        name: _name,
        color: const Color(0xFF000000),
        gridW: _gridW,
        gridH: _gridH,
        population: _population,
        workshops: [
          for (final e in _effects)
            if (e['type'] == 'workshop')
              WorkshopRole.fromJson(Map<String, dynamic>.from(e)),
        ],
      ),
    );
    return DropdownButtonFormField<BuildingCategory?>(
      initialValue: _category,
      // A dropdown sizes itself to its WIDEST item, so at phone width
      // "Automatic → Production" pushed the arrow off the edge. isExpanded
      // hands the item the row's real width and lets it ellipsize instead.
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Building type (Build-menu category)',
      ),
      dropdownColor: FoE.panelDark,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      items: [
        DropdownMenuItem(
          value: null,
          child: Text(
            'Automatic → ${derived.label}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final c in BuildingCategory.values)
          DropdownMenuItem(
            value: c,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(c.icon, size: 16, color: FoE.gold),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(c.label, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) => setState(() => _category = v),
    );
  }

  /// "Ab welcher Ära baubar" — a single start era (or every era). Stored as the
  /// contiguous era-id suffix, which is what the placement gate reads.
  Widget _eraDropdown() {
    return DropdownButtonFormField<int?>(
      initialValue: _eras.any((e) => e.order == _startEraOrder)
          ? _startEraOrder
          : null,
      // Same reason as the category dropdown: an era named "🏺 ab Ära 1 ·
      // Stone Age" is wider than a phone row, and the dropdown sizes to its
      // widest item whether or not that item is the selected one.
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'First buildable in era',
      ),
      dropdownColor: FoE.panelDark,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      items: [
        const DropdownMenuItem(value: null, child: Text('Always (every era)')),
        for (final e in _eras)
          DropdownMenuItem(
            value: e.order,
            child: Text(
              '${e.emoji} from era ${e.order} · ${e.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => setState(() => _startEraOrder = v),
    );
  }

  /// Read-only note: WHICH path node unlocks this building — derived live from
  /// the authored path (a node's building reward). Set it in the Pfad editor.
  Widget _mapUnlockNote() {
    final battle = _id.trim().isEmpty ? 0 : buildingUnlockBattle(_id.trim());
    final text = battle > 0
        ? 'Unlocked at node $battle. Change it in the Path editor '
            '(node reward → buildings).'
        : 'Buildable from its era. Set it as a node reward in the Path '
            'editor to unlock it later.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Map unlock (set in the Path editor)',
        ),
        child: Text(text, style: FoE.dim(size: 13)),
      ),
    );
  }

  // ── Tab 2: Bau ──────────────────────────────────────────────
  List<Widget> _constructionTab() => [
    _timeAndPowerSection(),
    const SizedBox(height: 8),
    _sectionLabel('Bauzeit-Skalierung'),
    _numRow(
      'Time ×/level (build time TO level L = base × factor^(L−1))',
      _timeFactor,
      isDouble: true,
      onChanged: (v) => setState(() => _timeFactor = (v as num).toDouble()),
    ),
    const SizedBox(height: 4),
    _maxLevelPerEraEditor(),
    const SizedBox(height: 12),
    _buildTimePreview(),
  ];

  // ── Tab 3: Kosten (per era) ─────────────────────────────────
  List<Widget> _costTab() => [
    _sectionLabel('Build cost per era'),
    Text(
      'Pick the upgrade resources per era — era 2 and later use different '
      'materials. The amount is what the FIRST level of that era costs; the '
      'factor scales it up per level. The level bands come from '
      '"Build" → max level per era.',
      style: FoE.dim(size: 11),
    ),
    const SizedBox(height: 10),
    _numRow(
      'Cost ×/level (factor)',
      _costFactor,
      isDouble: true,
      onChanged: (v) => setState(() => _costFactor = (v as num).toDouble()),
    ),
    for (final band in _costBands()) _costEraCard(band),
    const SizedBox(height: 12),
    _costPreview(),
  ];

  // ── Tab 4: Effekte ──────────────────────────────────────────
  List<Widget> _effectsTab() => [
    _sectionLabel('Effekte'),
    Text(
      'EVERY effect a building has is set here. The form follows the type — '
      'you only fill in what that type reads. "workshop" = staffed '
      'production; "housing" = seats (a house\'s capacity shows up as a '
      'housing effect automatically and is editable here); "heal" = cut '
      'healing time/cost; XP per stationed monster is NOT here — it is one '
      'rate for every building with a post, in Species budget → XP; the per-era '
      'palette (production/resource/expedition/expeditionSlots/heal/housing) '
      'applies from the chosen era on. "Growth per level (%)" says how much '
      'the effect grows per building level (empty = the default +50 %/level).',
      style: FoE.dim(size: 11),
    ),
    const SizedBox(height: 8),
    EffectsEditor(
      initialEffects: _effects,
      mode: EffectsMode.building,
      // Drives the per-level housing inputs (one field per level).
      maxLevel: _previewMaxLevel,
      onChanged: (e) => _effects = e,
    ),
  ];

  /// The level bands per era, derived from maxLevelPerEra (era E covers
  /// prevMax+1 … maxLevelPerEra[E]). No caps at all → a single level-1 band on
  /// the building's start era.
  List<({int era, int first, int last})> _costBands() {
    if (_maxLevelPerEra.isEmpty) {
      final era = _startEraOrder ?? 1;
      return [(era: era, first: 1, last: 1)];
    }
    final entries = _maxLevelPerEra.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final bands = <({int era, int first, int last})>[];
    var prev = 0;
    for (final e in entries) {
      // Only eras that actually UNLOCK new levels get a cost band (user
      // 2026-07-24) — an era whose cap equals the previous one adds nothing.
      if (e.value > prev) {
        bands.add((era: e.key, first: prev + 1, last: e.value));
        prev = e.value;
      }
    }
    return bands;
  }

  EraDef? _eraByOrder(int order) {
    for (final e in _eras) {
      if (e.order == order) return e;
    }
    return null;
  }

  Widget _costEraCard(({int era, int first, int last}) band) {
    final eraDef = _eraByOrder(band.era);
    final res = _costByEra[band.era] ?? const {};
    final range = band.first == band.last
        ? 'Level ${band.first}'
        : 'Levels ${band.first}–${band.last}';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${eraDef?.emoji ?? '📦'} Era ${band.era} · $range',
            style: FoE.label(size: 13).copyWith(color: FoE.gold),
          ),
          const SizedBox(height: 6),
          for (final good in res.keys.toList()) _costResourceRow(band, good),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _addCostResource(band.era),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: FoE.btn(),
              alignment: Alignment.center,
              child: Text('+ Resource',
                  style: FoE.label(size: 12).copyWith(color: FoE.goldBright)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _costResourceRow(({int era, int first, int last}) band, String good) {
    final map = _costByEra[band.era] ?? const {};
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: good,
              decoration:
                  const InputDecoration(labelText: 'Resource', isDense: true),
              dropdownColor: FoE.panelDark,
              isExpanded: true,
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              items: [
                for (final id in _allResourceIds)
                  if (id == good || !map.containsKey(id))
                    DropdownMenuItem(
                      value: id,
                      // Show WHICH era introduces the resource (user 2026-07-24).
                      child: Text('${_resourceLabel(id)} · era ${_resourceEra(id)}'),
                    ),
              ],
              onChanged: (v) => _renameCostResource(band.era, good, v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            // Stable key (no value in it) so typing keeps focus while the
            // preview below rebuilds live on every keystroke (user 2026-07-24).
            child: TextFormField(
              key: ValueKey('cost-${band.era}-$good'),
              initialValue: (map[good] ?? 0) == 0
                  ? ''
                  : (map[good] ?? 0).toStringAsFixed(0),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              decoration: InputDecoration(
                labelText: 'Amount @level ${band.first}',
                isDense: true,
              ),
              onChanged: (v) => setState(() =>
                  (_costByEra[band.era] ??= {})[good] = double.tryParse(v) ?? 0),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            onPressed: () => setState(() => _costByEra[band.era]?.remove(good)),
          ),
        ],
      ),
    );
  }

  void _addCostResource(int era) {
    final map = _costByEra[era] ??= {};
    final free = _allResourceIds.firstWhere(
      (id) => !map.containsKey(id),
      orElse: () => '',
    );
    if (free.isEmpty) return; // every resource already added
    setState(() => map[free] = 0);
  }

  void _renameCostResource(int era, String from, String? to) {
    if (to == null || to == from) return;
    final map = _costByEra[era] ??= {};
    if (map.containsKey(to)) return;
    setState(() => map[to] = map.remove(from) ?? 0);
  }

  /// A per-level preview of the resolved cost — the SAME per-era + factor math
  /// resourceCostAt uses at runtime, so what you author is what it charges.
  Widget _costPreview() {
    final bands = _costBands();
    ({int era, int first, int last}) bandFor(int lvl) {
      for (final b in bands) {
        if (lvl >= b.first && lvl <= b.last) return b;
      }
      return bands.last;
    }

    final rows = <Widget>[];
    for (var lvl = 1; lvl <= _previewMaxLevel; lvl++) {
      final b = bandFor(lvl);
      final base = _costByEra[b.era] ?? const {};
      final f = math.pow(_costFactor, lvl - b.first).toDouble();
      final parts = [
        for (final e in base.entries)
          if (e.value > 0) '${_resourceLabel(e.key)} ${(e.value * f).round()}',
      ];
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 76,
                child: Text('L$lvl · era ${b.era}',
                    style: FoE.label(size: 12).copyWith(color: FoE.gold)),
              ),
              Expanded(
                child: Text(
                  parts.isEmpty ? '—' : parts.join('   ·   '),
                  style: FoE.label(size: 12).copyWith(color: FoE.parchment),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cost per level (preview)',
              style: FoE.label(size: 13).copyWith(color: FoE.gold)),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  // ── Max level per era (monotonic non-decreasing by era) ─────
  Widget _maxLevelPerEraEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Max level per era — the number is the HIGHEST building level in that '
          'era (not how many levels it adds). 0 = no cap of its own. Enter n '
          'anywhere and every LATER era becomes at least n too (still raisable) '
          '— a later era is never lower than an earlier one. With no cap at all '
          'the effective build time only shows level 1.',
          style: FoE.dim(size: 11),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final era in _eras)
              SizedBox(
                width: 150,
                child: TextFormField(
                  key: ValueKey(
                    'maxlvl-${era.order}-${_maxLevelPerEra[era.order] ?? 0}',
                  ),
                  initialValue: (_maxLevelPerEra[era.order] ?? 0).toString(),
                  keyboardType: TextInputType.number,
                  style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                  decoration: InputDecoration(
                    labelText: '${era.emoji} Era ${era.order}',
                    isDense: true,
                  ),
                  onChanged: (v) => _setMaxLevel(era.order, int.tryParse(v) ?? 0),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Sets era [order]'s cap to [n] and enforces the monotonic invariant: the
  /// entered value can't dip below an earlier era's cap, and every LATER era is
  /// raised to at least [n] (still freely raisable higher).
  void _setMaxLevel(int order, int n) {
    setState(() {
      if (n <= 0) {
        _maxLevelPerEra.remove(order);
      } else {
        // Can't go below an earlier era's cap.
        final earlierMax = [
          for (final e in _eras)
            if (e.order < order) _maxLevelPerEra[e.order] ?? 0,
        ].fold<int>(0, math.max);
        final v = math.max(n, earlierMax).clamp(1, 99);
        _maxLevelPerEra[order] = v;
        // Fill every later era to at least v.
        for (final e in _eras) {
          if (e.order <= order) continue;
          final cur = _maxLevelPerEra[e.order] ?? 0;
          if (cur < v) _maxLevelPerEra[e.order] = v;
        }
      }
    });
  }

  int _calcGen = 0;

  double _calcPoints() {
    var p = _calcPassivePoints.toDouble();
    for (final m in _builders) {
      p += m.count * m.stat * _calcMult;
    }
    return p;
  }

  /// The real wait at building [level]. Points cut a PERCENTAGE off the entered
  /// time (user 2026-07-26) — so zero points is not a standstill anymore, it is
  /// exactly the time typed in above.
  double _effSeconds(int level) {
    final work = _constructionHours * 3600 * math.pow(_timeFactor, level - 1);
    return work / buildSpeedFromPoints(_calcPoints());
  }

  Widget _timeAndPowerSection() {
    final points = _calcPoints();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Build time (without a single build point — the full, uncut time)',
            style: FoE.label(size: 13).copyWith(color: FoE.gold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _intField('Hrs', _ch, (v) {
                  setState(() {
                    _ch = v;
                    _recomputeHours();
                  });
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _intField('Min', _cm, (v) {
                  setState(() {
                    _cm = v;
                    _recomputeHours();
                  });
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _intField('Sec', _cs, (v) {
                  setState(() {
                    _cs = v;
                    _recomputeHours();
                  });
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '🛠 Build-time calculator (construction points)',
                style: FoE.label(size: 13).copyWith(color: FoE.gold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.info_outline, color: FoE.gold),
                tooltip: 'How are construction points calculated?',
                onPressed: _showPowerInfo,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _intField(
                  'Passive points (building effects)',
                  _calcPassivePoints,
                  (v) => setState(
                    () => _calcPassivePoints = v.clamp(0, 99999),
                  ),
                  keyId: 'passive-$_calcGen',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _intField(
                  'Points per stat point',
                  _calcMult.round(),
                  (v) => setState(
                    () => _calcMult = v.clamp(0, 999).toDouble(),
                  ),
                  keyId: 'mult-$_calcGen',
                ),
              ),
            ],
          ),
          for (var i = 0; i < _builders.length; i++) _builderRow(i),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() {
              _builders.add((count: 1, stat: 40));
              _calcGen++;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: FoE.btn(),
              alignment: Alignment.center,
              child: Text('+ Monster (construction stat)',
                  style: FoE.label(size: 12)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Total: ${points.toStringAsFixed(0)} construction points '
            '= −${(buildTimeCut(points) * 100).toStringAsFixed(1)} % build time',
            style: FoE.label(size: 13).copyWith(color: FoE.gold),
          ),
          Row(
            children: [
              Text(
                'Effective build time (level 1): ',
                style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              ),
              Text(
                _fmtSeconds(_effSeconds(1)),
                style: FoE.label(size: 15).copyWith(color: FoE.goldBright),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _builderRow(int i) {
    final m = _builders[i];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: _intField(
              'Count',
              m.count,
              (v) => setState(
                () => _builders[i] = (count: v.clamp(0, 999), stat: m.stat),
              ),
              keyId: 'cnt-$i-$_calcGen',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _intField(
              'Construction stat',
              m.stat,
              (v) => setState(
                () => _builders[i] = (count: m.count, stat: v.clamp(0, 999)),
              ),
              keyId: 'stat-$i-$_calcGen',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Colors.redAccent, size: 20),
            onPressed: () => setState(() {
              _builders.removeAt(i);
              _calcGen++;
            }),
          ),
        ],
      ),
    );
  }

  Widget _intField(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    String? keyId,
  }) => TextFormField(
    key: keyId == null ? null : ValueKey(keyId),
    initialValue: value.toString(),
    keyboardType: TextInputType.number,
    style: FoE.label(size: 15).copyWith(color: FoE.parchment),
    decoration: InputDecoration(labelText: label, isDense: true),
    onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
  );

  void _showPowerInfo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: buildDevModeTheme(),
        child: AlertDialog(
            title: Text('Construction points', style: FoE.title(size: 15)),
          content: SingleChildScrollView(
            child: Text(
              'Building is measured in CONSTRUCTION POINTS — every point counts '
              'as exactly 1, wherever it comes from:\n\n'
              '•  Passive: whatever a building\'s `production`/`construction` '
              'effects give (entered 1:1 as points).\n'
              '•  Stationed: construction stat × "Build points per stat '
              'point" (the post\'s mult) × the building\'s level factor.\n\n'
              'Total points = passive + sum monsters.\n\n'
              'Points cut the entered build time by a percentage:\n'
              '    cut = P / (P + ${kBuildPointsForHalfTime.toStringAsFixed(0)})\n\n'
              '0 points = −0 %, i.e. EXACTLY the entered time (an unstaffed '
              'site no longer stands still). '
              '${kBuildPointsForHalfTime.toStringAsFixed(0)} points = −50 %, '
              '${buildPointsForCut(0.8)!.toStringAsFixed(0)} = −80 %, '
              '${buildPointsForCut(0.9)!.toStringAsFixed(0)} = −90 %. Die Kurve '
              'flacht ab, hat aber KEINEN Deckel — jeder weitere Punkt bringt '
              'something, and the time never reaches 0.\n\n'
              'Every active site builds at FULL speed (no splitting). Empty '
              'energy × 0.30. Tech/era buildSpeed bonuses multiply on top.',
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'OK',
                style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Per-level preview of the effective build time (uses the calculator points).
  /// Cost column removed (user 2026-07-24: costs live on the Kosten tab now).
  Widget _buildTimePreview() {
    final rows = <Widget>[];
    for (var level = 1; level <= _previewMaxLevel; level++) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  'L$level',
                  style: FoE.label(size: 13).copyWith(color: FoE.gold),
                ),
              ),
              Expanded(
                child: Text(
                  _fmtSeconds(_effSeconds(level)),
                  style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Effective build time per level',
              style: FoE.label(size: 13).copyWith(color: FoE.gold)),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }

  String _fmtSeconds(double s) {
    if (s.isInfinite || s.isNaN) return '∞';
    final total = s.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  Widget _imageRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      // A COLUMN holding the picture row and, under it, the three numbers that
      // place its base. They were appended to the ROW itself, which put a Row
      // of Expanded children inside another Row — unbounded width, and Flutter
      // says so a hundred times over (2026-08-01).
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: FoE.panel(radius: 8),
            // defId, so the BUNDLED render previews here exactly as the map
            // draws it — the upload is the fallback now, not the source.
            child: BuildingIcon(
              imageUrl: _imageUrl,
              defId: _id.trim(),
              size: 40,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasModel ? 'Bild — Modell mitgeliefert' : 'Image (PNG)',
                  style: FoE.label(size: 12).copyWith(color: FoE.gold),
                ),
                const SizedBox(height: 6),
                if (_hasModel) ...[
                  Text(
                    'Dieses Gebäude bringt seinen Render mit. Der Knopf setzt '
                    'Grundfläche und Bildlage auf die Werte, die der Renderer '
                    'gemessen hat — und löscht die hochgeladene URL, weil das '
                    'mitgelieferte Bild sie ohnehin überstimmt.',
                    style: FoE.dim(size: 11),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _applyFromModel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: FoE.btn(),
                      alignment: Alignment.center,
                      child: Text('Vom Modell übernehmen',
                          style: FoE.label(size: 13)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
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
          if (_imageUrl != null || _hasModel) ...[
            const SizedBox(height: 10),
            Text(
              'Where the base sits in the picture. 1 / 0.5 / 0 means it fills '
              'the width and touches the bottom edge — what the art contract '
              'asks for. BELOW 1 draws the building bigger (the base is only '
              'part of the picture), ABOVE 1 smaller.',
              style: FoE.dim(size: 11),
            ),
            const SizedBox(height: 8),
            // ── THE PREVIEW (user 2026-08-01: "das Gebäude ist ein bisschen
            //    verschoben. Man sieht es an allen Ecken") ──
            //
            // Three numbers you cannot see the effect of are three numbers you
            // guess at, save, walk to the map for, and come back to. The same
            // tiles the map draws, at the same 2:1, with the art placed by the
            // current values — dial it here and the answer is under your thumb.
            _BasePreview(
              imageUrl: _imageUrl,
              defId: _id.trim(),
              gridW: _gridW,
              gridH: _gridH,
              baseWidth: _artBaseWidth,
              anchorX: _artAnchorX,
              lift: _artLift,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _numRow(
                    'Base width',
                    _artBaseWidth,
                    isDouble: true,
                    // ABOVE 1 IS ALLOWED (user 2026-08-01: "base with muss
                    // mehr als bis 1 gehen, damit ich alles einstellen kann").
                    // It was capped at 1 on the assumption that a base can only
                    // be narrower than its picture. It can also be WIDER — art
                    // whose base overshoots, or a building you simply want to
                    // read smaller than its plot. 1.2 draws the image at five
                    // sixths of the footprint; the geometry never cared.
                    onChanged: (v) => setState(
                      () => _artBaseWidth = (v as double).clamp(0.05, 4.0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'Anchor X',
                    _artAnchorX,
                    isDouble: true,
                    onChanged: (v) => setState(
                      () => _artAnchorX = (v as double).clamp(0.0, 1.0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow(
                    'Lift',
                    _artLift,
                    isDouble: true,
                    onChanged: (v) => setState(
                      () => _artLift = (v as double).clamp(-1.0, 1.0),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
            // Expanded + wrapping: these labels explain what the flag DOES
            // ("Bauplatz (erweitert Gebiet, belegt keinen Platz)"), so they are
            // sentences, not words, and an unconstrained Text overflowed the
            // row at phone width.
            Expanded(
              child: Text(
                label,
                style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A searchable single-choice picker dialog: a filter field over a list of
/// id→label entries. Pops the chosen id or [cancelled] when dismissed.
class _SearchPickerDialog extends StatefulWidget {
  final String title;
  final String? current;
  final Map<String, String> items;
  const _SearchPickerDialog({
    required this.title,
    required this.current,
    required this.items,
  });

  /// Sentinel popped when the user dismisses without choosing.
  static const String cancelled = ' cancelled';

  @override
  State<_SearchPickerDialog> createState() => _SearchPickerDialogState();
}

class _SearchPickerDialogState extends State<_SearchPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final entries = widget.items.entries
        .where((e) =>
            q.isEmpty ||
            e.value.toLowerCase().contains(q) ||
            e.key.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Theme(
      data: buildDevModeTheme(),
      child: AlertDialog(
        title: Text(widget.title, style: FoE.title(size: 15)),
        content: SizedBox(
          width: 360,
          height: 420,
          child: Column(
            children: [
              TextField(
                autofocus: true,
                style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                decoration: const InputDecoration(
                  hintText: 'Suchen…',
                  prefixIcon: Icon(Icons.search, color: FoE.gold),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final e in entries)
                      _row(e.value, e.key == widget.current, () {
                        Navigator.pop(context, e.key);
                      }),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _SearchPickerDialog.cancelled),
            child: Text('Abbrechen',
                style: FoE.label(size: 13).copyWith(color: FoE.textDim)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, bool selected, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      color: selected ? FoE.panelMid : null,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? FoE.gold : FoE.textDim,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: FoE.label(size: 14).copyWith(color: FoE.parchment)),
          ),
        ],
      ),
    ),
  );
}

/// The building on its own tiles, at the size the map draws it — so the three
/// art numbers can be dialled in by eye instead of by walking to the map
/// (2026-08-01).
///
/// Deliberately the SAME geometry the map uses (iso_grid.dart), not a lookalike:
/// a preview that computes the placement its own way would agree with the map
/// only until one of the two changed.
class _BasePreview extends StatelessWidget {
  final String? imageUrl;

  /// So a BUNDLED render previews here too — it is the one the map will
  /// actually draw, and previewing the upload instead was showing the wrong
  /// picture for every modelled building.
  final String? defId;
  final int gridW;
  final int gridH;
  final double baseWidth;
  final double anchorX;
  final double lift;

  const _BasePreview({
    required this.imageUrl,
    required this.defId,
    required this.gridW,
    required this.gridH,
    required this.baseWidth,
    required this.anchorX,
    required this.lift,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = isoLocalBounds(gridW, gridH);
    final art = artPlacement(
      bounds,
      baseWidth: baseWidth,
      anchorX: anchorX,
      lift: lift,
    );
    // Room above for a tall building and around for art wider than its base.
    final boxW = math.max(bounds.width, art.width) + 24;
    final boxH = bounds.height * 2 + 120;
    return Container(
      height: boxH,
      alignment: Alignment.bottomCenter,
      decoration: ShapeDecoration(
        color: const Color(0xFF3E6B45), // the era-I ground, so it reads as map
        shape: FoE.facet(radius: 8),
      ),
      child: SizedBox(
        width: boxW,
        height: boxH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The footprint, where the map would put it.
            Positioned(
              left: (boxW - bounds.width) / 2,
              bottom: 24,
              width: bounds.width,
              height: bounds.height,
              child: CustomPaint(
                painter: _PreviewFootprint(w: gridW, h: gridH),
              ),
            ),
            Positioned(
              left: (boxW - bounds.width) / 2 + art.left,
              bottom: 24 + (bounds.height - art.bottom),
              width: art.width,
              child: BuildingIcon(
                imageUrl: imageUrl,
                defId: defId,
                width: art.width,
                anchorBottomOverflowTop: true,
              ),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Text(
                '${gridW}x$gridH · base ${bounds.width.toInt()}px · '
                'image ${art.width.toInt()}px',
                style: FoE.dim(size: 10).copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The footprint's cells, drawn the way the map draws them so the eye can line
/// the building up against something real.
class _PreviewFootprint extends CustomPainter {
  final int w;
  final int h;
  const _PreviewFootprint({required this.w, required this.h});

  @override
  void paint(Canvas canvas, Size size) {
    final path = footprintPathLocal(w, h);
    canvas
      ..drawPath(path, Paint()..color = Colors.white.withValues(alpha: 0.10))
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: 0.75),
      );
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.35);
    for (final (from, to) in footprintSeams(w, h)) {
      canvas.drawLine(from, to, seam);
    }
  }

  @override
  bool shouldRepaint(_PreviewFootprint old) => old.w != w || old.h != h;
}
