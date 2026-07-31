import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/dev/dev_theme.dart';
import '../models/ability_def.dart';
import '../models/creature_enums.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';
import '../services/creature_defs_controller.dart';
import '../services/creature_defs_service.dart';
import '../services/stat_budget.dart';
import 'ability_def_form.dart';

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

class _SpeciesDefFormState extends State<SpeciesDefForm>
    with SingleTickerProviderStateMixin {
  final _svc = CreatureDefsService();
  bool _saving = false;
  // Which stage's FRONT / BACK png is currently uploading (null = none).
  int? _uploadingStage;
  int? _uploadingBackStage;

  /// The four editor sections — Basics, Evolution, Stats, Abilities.
  late final TabController _tabs;

  late String _id;
  late String _name;
  late String _description;
  late CreatureElement _element;
  late CreatureRarity _rarity;
  late int _evoLevel1;
  late int _evoLevel2;
  late int _tier;
  late Map<CreatureStat, StatCurve> _stats;
  final _rng = math.Random();
  // Seeded from the rarity's GLOBAL budget; the Roll button re-spreads onto it.
  late BudgetTargets _budget;
  // The id as loaded — so a RENAME can delete the old Supabase row on save.
  late String _originalId;
  late List<String> _stageNames;
  late List<String?> _stageImages;
  late List<String?> _stageBackImages;
  late List<SpeciesAbility> _abilities;
  // The ROLES the stat spread is built from (user 2026-07-24: the archetype menu
  // is back): one combat archetype + up to 3 prioritised work stats. "Anwenden"
  // rebuilds the curves exactly on budget; "Roll" jitters within the same roles.
  CombatArchetype _combatArch = CombatArchetype.allrounder;
  final List<CreatureStat?> _workPriorities = [null, null, null];

  List<CreatureStat> get _definedPriorities =>
      [for (final s in _workPriorities) if (s != null) s];

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _id = d?.id ?? '';
    _originalId = _id;
    _name = d?.name ?? '';
    _description = d?.description ?? '';
    // Prefill the role menu from the stored role encoding (user 2026-07-24).
    _combatArch = CombatArchetype.values.firstWhere(
      (a) => a.name == (d?.roleArchetype ?? ''),
      orElse: () => CombatArchetype.allrounder,
    );
    final storedPrios = d?.roleWorkPriorities ?? const <CreatureStat>[];
    for (var i = 0; i < 3; i++) {
      _workPriorities[i] = i < storedPrios.length ? storedPrios[i] : null;
    }
    _element = d?.element ?? CreatureElement.fire;
    _rarity = d?.rarity ?? CreatureRarity.common;
    _evoLevel1 = d?.evoLevel1 ?? 25;
    _evoLevel2 = d?.evoLevel2 ?? 50;
    _tier = d?.tier ?? 1;
    // The rarity's GLOBAL budget (combat/civil base + growth are set per rarity
    // in the Species-dev config now).
    _budget = defaultBudget(rarity: _rarity, tier: _tier);
    final defaults = _defaultCurves();
    _stats = {
      for (final stat in CreatureStat.values)
        stat: d?.stats[stat] ?? defaults[stat]!,
    };
    _stageNames = List.generate(3, (i) => d?.stageAt(i).name ?? '');
    _stageImages = List.generate(3, (i) => d?.stageAt(i).imageUrl);
    _stageBackImages = List.generate(3, (i) => d?.stageAt(i).backImageUrl);
    _abilities = List.of(d?.abilities ?? const []);
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // New species start EXACTLY on the docs/balancing.md §3 budgets, as a plain
  // allrounder/generalist — the author then picks an ARCHETYPE pair (or shifts
  // points by hand) to make a specialist, watched live by the budget panel.
  // Stage 2/3 bases get the auto evo-bump when it's on (the default).
  Map<CreatureStat, StatCurve> _defaultCurves() => _withEvoBumps(
    buildCurves(
      combat: CombatArchetype.allrounder,
      workPriorities: const [],
      budget: _budget,
    ),
  );

  /// Rolls a fresh individual on budget from the chosen roles — always honours
  /// the combat archetype + prioritised work stats above, and spreads the rest
  /// with a HIGH jitter so non-priority stats genuinely vary (user 2026-07-24:
  /// some higher, some lower — not all stuck on the same base).
  void _rollRoles() {
    setState(() {
      _budget = defaultBudget(rarity: _rarity, tier: _tier);
      _stats = _finalizeAll(
        _withEvoBumps(
          rollCurves(
            combat: _combatArch,
            workPriorities: _definedPriorities,
            budget: _budget,
            rng: _rng,
            jitter: 0.6,
          ),
        ),
      );
    });
  }

  /// The automatic per-evolution-stage bump (user 2026-07-24: always on — the
  /// jump is automatic, no toggle). S2 = S1·(1+p), S3 = S1·(1+p)². Growth is
  /// untouched (the balance spec fixes the slope; only the socket moves).
  static const double _evoBumpPct = kEvoBumpPct;

  Map<CreatureStat, StatCurve> _withEvoBumps(
    Map<CreatureStat, StatCurve> stats,
  ) => {
    for (final e in stats.entries)
      e.key: StatCurve(
        stageBase: [
          e.value.stageBase[0],
          e.value.stageBase[0] * (1 + _evoBumpPct),
          e.value.stageBase[0] * (1 + _evoBumpPct) * (1 + _evoBumpPct),
        ],
        growth: e.value.growth,
      ),
  };

  /// Rounds + clamps every stat to the whole-number / 0.1-growth rules and the
  /// per-category caps for the current rarity.
  Map<CreatureStat, StatCurve> _finalizeAll(Map<CreatureStat, StatCurve> s) => {
    for (final e in s.entries) e.key: _finalizeCurve(e.key, e.value),
  };

  Future<void> _save() async {
    if (_id.trim().isEmpty || _name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('id and name are required')));
      return;
    }
    // Evolution is stage-by-level (a creature at Lv N is stage 2 if N ≥ evo2,
    // stage 1 if N ≥ evo1, else 0). Two invariants the editor never checked
    // before — a dev-authored evo1 below 2 (or above evo2) made a monster
    // spawn already-evolved (the "Waveshark at Lv 5" report, 2026-07-17):
    //  • evo1 ≥ 2 so a Lv-1 creature is always the base stage 0.
    //  • evo1 < evo2 so the two thresholds don't cross.
    if (_evoLevel1 < 2 || _evoLevel2 <= _evoLevel1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Evolution levels must be: Evo 1 ≥ 2, and Evo 1 < Evo 2.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final def = SpeciesDef(
      id: _id.trim(),
      name: _name.trim(),
      description: _description.trim(),
      // Persist the chosen role (archetype + priorities) so it shows on re-edit.
      role: SpeciesDef.encodeRole(_combatArch.name, _definedPriorities),
      element: _element,
      rarity: _rarity,
      // Catch rate is global per rarity now (Species-dev config) — stored on the
      // row for compatibility, always the rarity's configured value.
      catchRate: catchRateForRarity(_rarity),
      evoLevel1: _evoLevel1,
      evoLevel2: _evoLevel2,
      tier: _tier,
      // Persist whole-number bases (clamped to each attribute's hard cap) and
      // 0.1-step growth (user 2026-07-24).
      stats: {for (final e in _stats.entries) e.key: _finalizeCurve(e.key, e.value)},
      stages: List.generate(
        3,
        (i) => SpeciesStage(
          name: _stageNames[i].trim().isEmpty
              ? _name.trim()
              : _stageNames[i].trim(),
          imageUrl: _stageImages[i],
          backImageUrl: _stageBackImages[i],
        ),
      ),
      abilities: _abilities.where((a) => a.abilityId.isNotEmpty).toList(),
    );
    try {
      await _svc.upsertSpeciesDef(def);
      // RENAME (user 2026-07-24): the id is the primary key, so a rename is a
      // new row under the new id + delete of the old row. The stage sprite URLs
      // are absolute and carried over unchanged, so the art still shows.
      if (!_isNew && def.id != _originalId && _originalId.isNotEmpty) {
        await _svc.deleteSpeciesDef(_originalId);
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

  /// Uploads a PNG for [stage]. [back] = the battle back-view (else the normal
  /// front view shown everywhere).
  Future<void> _uploadImage(int stage, {bool back = false}) async {
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

    setState(() {
      if (back) {
        _uploadingBackStage = stage;
      } else {
        _uploadingStage = stage;
      }
    });
    try {
      final url = await _svc.uploadStageImage(_id.trim(), stage, bytes,
          back: back);
      if (mounted) {
        setState(() {
          if (back) {
            _stageBackImages[stage] = url;
          } else {
            _stageImages[stage] = url;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (back) {
            _uploadingBackStage = null;
          } else {
            _uploadingStage = null;
          }
        });
      }
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
        appBar: AppBar(
          title: Text(
            _isNew ? 'New Species' : 'Edit Species',
            style: FoE.title(size: 16),
          ),
          // Save (and Delete) live in the app bar so they stay visible on every
          // tab — no scrolling to the bottom of a section to save.
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
              Tab(text: 'Evolution'),
              Tab(text: 'Stats'),
              Tab(text: 'Abilities'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _tabBody(_basicsTab()),
            _tabBody(_evolutionTab()),
            _tabBody(_statsTab()),
            _tabBody(_abilitiesTab()),
          ],
        ),
      ),
    );
  }

  /// Wraps one tab's fields in a padded, scrollable list — every tab shares the
  /// same padding and trailing breathing room.
  Widget _tabBody(List<Widget> children) => ListView(
    padding: const EdgeInsets.all(14),
    children: [...children, const SizedBox(height: 24)],
  );

  // ── Tab 1: Basics (up to and including region tier) ─────────
  List<Widget> _basicsTab() => [
    _textRow(
      _isNew
          ? 'Id (slug, e.g. flammkitz)'
          : 'Id (renaming deletes the old Supabase row on save)',
      _id,
      // Editable now (user 2026-07-24): a rename updates Supabase (new row +
      // delete of the old id) on save.
      onChanged: (v) => _id = v,
    ),
    _textRow('Species name', _name, onChanged: (v) => _name = v),
    _textRow('Description', _description, onChanged: (v) => _description = v),
    _dropdownRow<CreatureElement>(
      'Element',
      _element,
      // Neutral is an ability-only type, not a creature type.
      CreatureElement.values
          .where((e) => e != CreatureElement.neutral)
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
      (v) => setState(() {
        _rarity = v ?? _rarity;
        // Budget, caps and catch rate are GLOBAL per rarity now — re-seed the
        // budget and re-clamp the stats to the new rarity's caps.
        _budget = defaultBudget(rarity: _rarity, tier: _tier);
        _stats = {
          for (final e in _stats.entries) e.key: _finalizeCurve(e.key, e.value),
        };
      }),
    ),
    const SizedBox(height: 12),
    _numRow(
      'Region tier (1 = first region)',
      _tier,
      onChanged: (v) => setState(() {
        _tier = (v as int).clamp(1, 99);
        _budget = defaultBudget(rarity: _rarity, tier: _tier);
      }),
    ),
  ];

  // ── Tab 2: Evolution (levels + stage name/art) ──────────────
  List<Widget> _evolutionTab() => [
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
    const SizedBox(height: 6),
    Text(
      'Stage follows level: a creature at level ≥ Evo 1 shows its '
      'evolved (stage 1) form, ≥ Evo 2 the final form. Wild monsters '
      'spawn at level 5 in region 1 (then +8 per region), so keep '
      'Evo 1 ABOVE the wild level of the earliest region this species '
      'appears in — otherwise it spawns there already evolved.',
      style: FoE.dim(size: 10).copyWith(color: FoE.gold),
    ),
    const SizedBox(height: 8),
    _sectionLabel('Evolution stages (name + PNG)'),
    for (var i = 0; i < 3; i++) _stageBlock(i),
  ];

  // ── Tab 3: Stats (roles/budget/curves) ──────────────────────
  List<Widget> _statsTab() => [
    // Budget, split, evo-jump and catch rate are GLOBAL now (Species-dev config
    // + automatic evolution). Here you define the ROLES and Apply/Roll a spread
    // within the rarity's budget, or edit the stats by hand.
    _rolesCard(),
    // Split the stats into combat + civil groups for readability (user
    // 2026-07-24). Civil covers every non-combat stat, incl. the carry utility
    // stat that no workshop offers (so kCivilianStats' 7 would miss it).
    _sectionLabel('⚔ Kampf'),
    for (final stat in CreatureStat.values.where((s) => s.isCombat))
      _statRow(stat),
    const SizedBox(height: 4),
    _sectionLabel('🛠 Zivil'),
    for (final stat in CreatureStat.values.where((s) => s.isCivilian))
      _statRow(stat),
  ];

  /// The ROLE definition menu (user 2026-07-24): the combat archetype + up to 3
  /// prioritised work stats the roll is built from. Each option shows, in
  /// parentheses, how many OTHER species of the current rarity already carry
  /// that role/priority (inferred from their stat curves) — so roles can be
  /// spread evenly. "Roll" always honours these picks.
  Widget _rolesCard() {
    final work = kNonCombatStats;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roles — archetype + work priorities  ·  (N) = ${_rarity.label} '
            'with that role',
            style: FoE.label(size: 13).copyWith(color: FoE.gold),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<CombatArchetype>(
            initialValue: _combatArch,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Kampf-Archetyp',
              isDense: true,
            ),
            dropdownColor: FoE.panelDark,
            style: FoE.label(size: 13).copyWith(color: FoE.parchment),
            items: [
              for (final a in CombatArchetype.values)
                DropdownMenuItem(
                  value: a,
                  child: Text('${a.label}  (${_archCount(a)})'),
                ),
            ],
            onChanged: (v) => setState(() => _combatArch = v ?? _combatArch),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: DropdownButtonFormField<CreatureStat?>(
                    initialValue: _workPriorities[i],
                    isDense: true,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Prio ${i + 1}',
                      isDense: true,
                    ),
                    dropdownColor: FoE.panelDark,
                    style: FoE.label(size: 12).copyWith(color: FoE.parchment),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final s in work)
                        DropdownMenuItem(
                          value: s,
                          child: Text('${s.label} (${_prioCount(s)})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _workPriorities[i] = v),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _rollRoles,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: FoE.btn(active: true),
                alignment: Alignment.center,
                child: Text('🎲 Roll (with these roles)',
                    style: FoE.label(size: 14).copyWith(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A species' combat archetype — the STORED role when present (authored via a
  /// roll/save), else inferred from its stat curves.
  CombatArchetype _speciesArch(SpeciesDef d) {
    for (final a in CombatArchetype.values) {
      if (a.name == d.roleArchetype) return a;
    }
    return inferCombatArchetype(d.stats);
  }

  /// A species' work priorities — the stored role when present, else inferred.
  List<CreatureStat> _speciesPrios(SpeciesDef d) {
    final stored = d.roleWorkPriorities;
    return stored.isNotEmpty ? stored : inferWorkPriorities(d.stats);
  }

  /// Species of the current rarity (excluding the one being edited) whose combat
  /// archetype is [a].
  int _archCount(CombatArchetype a) => kSpeciesDefs.values
      .where((d) =>
          d.id != _originalId && d.rarity == _rarity && _speciesArch(d) == a)
      .length;

  /// Species of the current rarity (excluding the one being edited) whose work
  /// priorities include [s].
  int _prioCount(CreatureStat s) => kSpeciesDefs.values
      .where((d) =>
          d.id != _originalId &&
          d.rarity == _rarity &&
          _speciesPrios(d).contains(s))
      .length;

  // ── Tab 4: Abilities ────────────────────────────────────────
  List<Widget> _abilitiesTab() => [
    _sectionLabel('Abilities (unlocked per evolution stage)'),
    const SizedBox(height: 6),
    ..._abilities.asMap().entries.map((e) => _abilityRow(e.key, e.value)),
    Row(
      children: [
        // Assign an EXISTING ability (disabled when none exist yet).
        Expanded(
          child: GestureDetector(
            onTap: kAbilityDefs.isEmpty
                ? null
                : () => setState(
                    () => _abilities.add(
                      SpeciesAbility(abilityId: kAbilityDefs.keys.first),
                    ),
                  ),
            child: Container(
              margin: const EdgeInsets.only(top: 4, right: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: FoE.btn(active: kAbilityDefs.isNotEmpty),
              alignment: Alignment.center,
              child: Text(
                kAbilityDefs.isEmpty ? 'No abilities yet' : '+ Add existing',
                style: FoE.label(size: 13),
              ),
            ),
          ),
        ),
        // Create a NEW ability right here and assign it (user 2026-07-24).
        Expanded(
          child: GestureDetector(
            onTap: () => _newAbility(),
            child: Container(
              margin: const EdgeInsets.only(top: 4, left: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: FoE.btn(active: true),
              alignment: Alignment.center,
              child: Text('✎ New ability',
                  style: FoE.label(size: 13).copyWith(color: Colors.white)),
            ),
          ),
        ),
      ],
    ),
  ];

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
  );

  Widget _stageBlock(int stage) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: _stageNames[stage],
            style: FoE.label(size: 14).copyWith(color: FoE.parchment),
            decoration: InputDecoration(
              labelText: 'Stage ${stage + 1} name',
              isDense: true,
            ),
            onChanged: (v) => _stageNames[stage] = v,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Front view — shown everywhere (collection, bestiary, enemy in
              // battle).
              Expanded(
                child: _imageSlot(
                  label: 'Front (Vorderseite)',
                  url: _stageImages[stage],
                  uploading: _uploadingStage == stage,
                  onTap: () => _uploadImage(stage),
                ),
              ),
              const SizedBox(width: 10),
              // Back view — the player's own monster seen from behind in
              // battle (falls back to the front view if left empty).
              Expanded(
                child: _imageSlot(
                  label: 'Back (rear view, battle)',
                  url: _stageBackImages[stage],
                  uploading: _uploadingBackStage == stage,
                  onTap: () => _uploadImage(stage, back: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One image slot: a thumbnail (or placeholder) + an upload/replace button.
  Widget _imageSlot({
    required String label,
    required String? url,
    required bool uploading,
    required VoidCallback onTap,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: FoE.dim(size: 10)),
      const SizedBox(height: 4),
      Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: FoE.panel(radius: 8),
            child: url == null
                ? const Icon(Icons.pets, color: FoE.gold, size: 22)
                : Image.network(
                    url,
                    filterQuality: FilterQuality.none,
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image, color: FoE.gold),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: uploading ? null : onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                alignment: Alignment.center,
                decoration: FoE.btn(),
                child: uploading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(url == null ? 'PNG' : 'Replace',
                        style: FoE.label(size: 12)),
              ),
            ),
          ),
        ],
      ),
    ],
  );


  /// Whole-number bases clamped to the rarity's per-category cap, growth in 0.1
  /// steps clamped to the rarity's growth cap (user 2026-07-24).
  StatCurve _finalizeCurve(CreatureStat stat, StatCurve c) => StatCurve(
    stageBase: [
      for (final b in c.stageBase)
        kSpeciesBalance.clampBase(stat, _rarity, b.roundToDouble()),
    ],
    growth: kSpeciesBalance.clampGrowth(
      stat,
      _rarity,
      (c.growth * 10).roundToDouble() / 10,
    ),
  );

  Widget _statRow(CreatureStat stat) {
    final curve = _stats[stat]!;
    final maxBase = statBaseMax(stat, _rarity);
    final base0 = curve.stageBase[0];
    final inRange = maxBase == null || base0 <= maxBase + 0.5;

    // The wild spread a real individual rolls around these species MEANS: base
    // ±2σ (σ=8%) and growth ±2σ (σ=6%), independently, clamped — see
    // CreatureInstance._sample. Two envelopes are shown: the fresh catch (base
    // stage, Lv 1) and the strongest end-state (fully evolved, max level, where
    // the flat evo bonus S3−S1 is already added on top of the base gene).
    final baseSpread = kBaseSigmaPct * kSigmaClampFactor; // ±0.16
    final slopeSpread = kSlopeSigmaPct * kSigmaClampFactor; // ±0.12
    final g = curve.growth;
    final evoDelta = curve.stageBase[2] - base0; // flat bonus at final stage
    final freshLo = base0 * (1 - baseSpread);
    final freshHi = base0 * (1 + baseSpread);
    final maxLvl = kCreatureMaxLevel;
    final finalLo = freshLo + evoDelta + g * (1 - slopeSpread) * (maxLvl - 1);
    final finalHi = freshHi + evoDelta + g * (1 + slopeSpread) * (maxLvl - 1);

    void updateBase(int stage, double value) {
      final bases = List.of(curve.stageBase);
      // Whole numbers, clamped to the category cap for this rarity.
      bases[stage] =
          kSpeciesBalance.clampBase(stat, _rarity, value.roundToDouble());
      setState(() => _stats[stat] = StatCurve(stageBase: bases, growth: curve.growth));
    }

    void updateGrowth(double value) {
      // 0.1 steps, clamped to the category growth cap for this rarity.
      final g = kSpeciesBalance.clampGrowth(
        stat,
        _rarity,
        (value * 10).roundToDouble() / 10,
      );
      setState(
        () => _stats[stat] = StatCurve(stageBase: curve.stageBase, growth: g),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compact header on ONE line: name + global per-category MAX on the
          // left, the wild spread (fresh @Lv1 → fully evolved @max) on the right
          // (user 2026-07-24: kompakter).
          Row(
            children: [
              Text(
                stat.label,
                style: FoE.label(size: 12).copyWith(color: FoE.parchment),
              ),
              const SizedBox(width: 6),
              // Amber if the base is over the global cap for this rarity.
              Text(
                maxBase == null ? 'max —' : 'max ${maxBase.toStringAsFixed(0)}',
                style: FoE.dim(size: 9).copyWith(
                  color: inRange ? FoE.textDim : FoE.gold,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'wild ${freshLo.toStringAsFixed(0)}–${freshHi.toStringAsFixed(0)}'
                  ' → ${finalLo.toStringAsFixed(0)}–${finalHi.toStringAsFixed(0)}'
                  ' @Lv$maxLvl',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 9).copyWith(color: FoE.textDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Base per stage + shared growth all on ONE line (user 2026-07-24).
          Row(
            children: [
              for (var stage = 0; stage < 3; stage++) ...[
                if (stage > 0) const SizedBox(width: 6),
                Expanded(
                  child: TextFormField(
                    key: ValueKey(
                      '${stat.name}-base$stage-${curve.stageBase[stage].toStringAsFixed(0)}',
                    ),
                    initialValue: curve.stageBase[stage].toStringAsFixed(0),
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
              const SizedBox(width: 6),
              Expanded(
                child: TextFormField(
                  key: ValueKey('${stat.name}-growth-${g.toStringAsFixed(1)}'),
                  initialValue: g.toStringAsFixed(1),
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
        ],
      ),
    );
  }

  Widget _abilityRow(int index, SpeciesAbility ability) {
    final def = kAbilityDefs[ability.abilityId];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Tappable searchable picker (user 2026-07-24) — opens a filtered
              // list with a live preview of each ability.
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () => _pickAbility(index),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Ability',
                      isDense: true,
                      suffixIcon: Icon(Icons.search, color: FoE.gold, size: 18),
                    ),
                    child: Text(
                      def?.name ?? 'Pick an ability…',
                      style: FoE.label(size: 14).copyWith(
                        color: def == null ? FoE.textDim : FoE.parchment,
                      ),
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
              // Edit the picked ability DIRECTLY from here (user 2026-07-24) —
              // opens the full ability editor, then refreshes the preview.
              IconButton(
                icon: const Icon(Icons.edit, color: FoE.gold, size: 18),
                tooltip: 'Edit this ability',
                onPressed: def == null ? null : () => _editAbility(def),
              ),
              IconButton(
                icon:
                    const Icon(Icons.close, color: Colors.redAccent, size: 18),
                onPressed: () => setState(() => _abilities.removeAt(index)),
              ),
            ],
          ),
          // A live preview of the picked ability, right under the row.
          if (def != null) ...[
            const SizedBox(height: 6),
            _abilityPreview(def),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAbility(int index) async {
    if (kAbilityDefs.isEmpty) return;
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _AbilityPickerDialog(
        current: _abilities[index].abilityId,
      ),
    );
    if (id == null) return; // cancelled
    setState(
      () => _abilities[index] = SpeciesAbility(
        abilityId: id,
        unlockStage: _abilities[index].unlockStage,
      ),
    );
  }

  /// Opens the full ability editor for [def], then reloads the ability defs so
  /// the inline preview reflects the edit immediately (user 2026-07-24).
  Future<void> _editAbility(AbilityDef def) async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AbilityDefForm(existing: def)),
    );
    await CreatureDefsController().load();
    if (mounted) setState(() {});
  }

  /// Creates a BRAND-NEW ability from here and, once saved, assigns it to this
  /// species. [index] null = add a new ability slot; otherwise replace that row.
  Future<void> _newAbility({int? index}) async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AbilityDefForm()),
    );
    await CreatureDefsController().load();
    if (!mounted) return;
    setState(() {
      if (id == null) return; // cancelled — nothing to assign
      if (index != null) {
        _abilities[index] = SpeciesAbility(
          abilityId: id,
          unlockStage: _abilities[index].unlockStage,
        );
      } else {
        _abilities.add(SpeciesAbility(abilityId: id));
      }
    });
  }

  /// A compact, at-a-glance summary of an ability — reused in the picker rows
  /// and the inline preview.
  static List<String> abilitySummary(AbilityDef a) => [
    '${a.element.emoji} ${a.kind.label}',
    a.target.label,
    if (a.kind == AbilityKind.damage && a.power > 0) 'Power ${a.power}',
    if (a.kind == AbilityKind.heal && a.healPct > 0)
      'Heal ${(a.healPct * 100).round()}%',
    '${a.resolvedApCost} AP',
    if (a.priority != 0) 'Prio ${a.priority}',
    // One chip per effect, in the shared vocabulary (user 2026-07-30) — these
    // used to be four hand-written lines that printed a name and a chance, and
    // said nothing about how hard or how long. An ability carries its own
    // duration and magnitude now, so the chip has to carry them too.
    for (final e in a.effects) summariseAbilityEffect(e),
  ];

  Widget _abilityPreview(AbilityDef a) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final b in abilitySummary(a))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: FoE.panel(radius: 6),
              child: Text(b, style: FoE.dim(size: 10)),
            ),
        ],
      ),
      if (a.description.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(a.description, style: FoE.dim(size: 10)),
        ),
    ],
  );

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

/// A searchable ability picker: a filter field over every AbilityDef, each row
/// showing the ability's name + a compact stat preview (type, kind, power, AP,
/// effects). Pops the chosen id, or null when cancelled.
class _AbilityPickerDialog extends StatefulWidget {
  final String? current;
  const _AbilityPickerDialog({required this.current});

  @override
  State<_AbilityPickerDialog> createState() => _AbilityPickerDialogState();
}

class _AbilityPickerDialogState extends State<_AbilityPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = kAbilityDefs.values.where((a) {
      if (q.isEmpty) return true;
      return a.name.toLowerCase().contains(q) ||
          a.id.toLowerCase().contains(q) ||
          a.element.label.toLowerCase().contains(q) ||
          a.kind.label.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Theme(
      data: buildDevModeTheme(),
      child: AlertDialog(
        title: Text('Pick an ability', style: FoE.title(size: 15)),
        content: SizedBox(
          width: 380,
          height: 460,
          child: Column(
            children: [
              TextField(
                autofocus: true,
                style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                decoration: const InputDecoration(
                  hintText: 'Search name, type or species…',
                  prefixIcon: Icon(Icons.search, color: FoE.gold),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text('Keine Treffer', style: FoE.dim(size: 12)),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) {
                          final a = list[i];
                          final selected = a.id == widget.current;
                          return InkWell(
                            onTap: () => Navigator.pop(context, a.id),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: ShapeDecoration(
                                color: selected ? FoE.panelLight : FoE.panelMid,
                                shape: FoE.facet(
                                  radius: 8,
                                  side: const BorderSide(color: FoE.border),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (selected)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 6),
                                          child: Icon(Icons.check,
                                              color: FoE.gold, size: 16),
                                        ),
                                      Expanded(
                                        child: Text(
                                          a.name,
                                          style: FoE.label(size: 14).copyWith(
                                              color: FoE.parchment),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      for (final b
                                          in _SpeciesDefFormState.abilitySummary(
                                              a))
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: FoE.panel(radius: 6),
                                          child: Text(b, style: FoE.dim(size: 10)),
                                        ),
                                    ],
                                  ),
                                  if (a.description.trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(a.description,
                                          style: FoE.dim(size: 10)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen',
                style: FoE.label(size: 13).copyWith(color: FoE.textDim)),
          ),
        ],
      ),
    );
  }
}
