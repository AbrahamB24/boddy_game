import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/dev/ability_def_form.dart';
import '../../creatures/dev/species_balance_form.dart';
import '../../creatures/dev/species_def_form.dart';
import '../../creatures/dev/species_matrix_view.dart';
import '../../creatures/models/ability_def.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/services/creature_defs_controller.dart';
import '../../creatures/services/creature_defs_service.dart';
import '../../creatures/services/stat_budget.dart';
import '../data/building_art.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../services/game_defs_controller.dart';
import '../settlement_controller.dart';
import '../widgets/building_icon.dart';
import 'area_def_form.dart';
import 'building_def_form.dart';
import 'combat_lab_screen.dart';
import 'dev_theme.dart';
import 'era_def_form.dart';
import 'item_def_form.dart';
import 'gather_defs_tab.dart';
import 'dev_export_sheet.dart';
import 'path_editor_tab.dart';
import 'tuning_tab.dart';
import '../../../core/tuning/game_tuning.dart';
import '../data/item_definitions.dart';

// All tabs are fully wired: Buildings -> BuildingDefForm, Eras -> EraDefForm,
// Species -> SpeciesDefForm, Abilities -> AbilityDefForm.
class DevModeScreen extends StatelessWidget {
  const DevModeScreen({super.key});

  void _openBuildingForm(BuildContext context, BuildingDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BuildingDefForm(existing: existing)),
    );
  }

  void _openItemForm(BuildContext context, ItemDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ItemDefForm(existing: existing)),
    );
  }

  void _openEraForm(BuildContext context, EraDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EraDefForm(existing: existing)),
    );
  }

  void _openSpeciesForm(BuildContext context, SpeciesDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SpeciesDefForm(existing: existing)),
    );
  }

  void _openAbilityForm(BuildContext context, AbilityDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AbilityDefForm(existing: existing)),
    );
  }

  void _openAreaForm(BuildContext context, AreaDef? existing) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AreaDefForm(existing: existing)),
    );
  }

  /// Rescales every off-budget species onto its TOTAL budget (user 2026-07-17)
  /// — same [isOnTotalBudget] check the 🔴 flag uses, so list and fix can never
  /// disagree. The combat/work split, per-stat distribution and evo bumps are
  /// preserved (uniform scale); only the magnitude moves.
  Future<void> _normalizeSpeciesBudgets(BuildContext context) async {
    final svc = CreatureDefsService();
    var fixed = 0;
    for (final d in kSpeciesDefs.values.toList()) {
      if (isOnTotalBudget(stats: d.stats, rarity: d.rarity, tier: d.tier)) {
        continue;
      }
      final normalized = normalizeToTotalBudget(
        stats: d.stats,
        rarity: d.rarity,
        tier: d.tier,
      );
      await svc.upsertSpeciesDef(d.copyWithStats(normalized));
      fixed++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fixed == 0
              ? 'Every species is already on budget.'
              : '⚖️ $fixed species rebalanced onto their budgets.',
        ),
      ),
    );
  }

  /// Re-rolls the stat distribution of EVERY species for a varied roster (user
  /// 2026-07-17). The three fire/water/plant epic STARTERS share the same
  /// combat:work ratio (the default split) and differ only WITHIN each category
  /// — a distinct combat archetype and work focus each, plus jitter. Every
  /// other species rolls both a random split AND a random focus, for a good mix
  /// of fighters and workers. Totals stay on budget; evo bumps are re-applied
  /// so evolving still matters.
  Future<void> _rerollAllStats(BuildContext context) async {
    final total = kSpeciesDefs.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Re-roll all stats?', style: FoE.title(size: 15)),
        content: Text(
          'Overwrites the stat curves of all $total species. The three '
          'fire/water/plant epic starters keep an identical combat:work ratio; '
          'everyone else gets a varied mix. This cannot be undone.',
          style: FoE.label(size: 13).copyWith(color: FoE.parchment),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: FoE.label(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '🎲 Re-roll',
              style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final svc = CreatureDefsService();
    final rng = math.Random();
    final workStats = kNonCombatStats;
    final combat = CombatArchetype.values;

    // Group by (rarity, TYPE/element) and spread the combat archetype + primary
    // work priority EVENLY within each group (user 2026-07-24) — a
    // deterministic round-robin per bucket, so every rarity/type covers the
    // roles uniformly instead of clumping. A second focus on odd slots plus the
    // high roll jitter keep individuals varied.
    final groups = <String, List<SpeciesDef>>{};
    for (final d in (kSpeciesDefs.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id)))) {
      groups
          .putIfAbsent('${d.rarity.name}|${d.element.name}', () => [])
          .add(d);
    }
    var count = 0;
    for (final group in groups.values) {
      for (var i = 0; i < group.length; i++) {
        final d = group[i];
        final arch = combat[i % combat.length];
        final picks = <CreatureStat>[
          workStats[i % workStats.length],
          if (i.isOdd) workStats[(i + 3) % workStats.length],
        ];
        // Starters keep the exact default budget; everyone else a jittered one.
        final budget = isStarterSpecies(d)
            ? defaultBudget(rarity: d.rarity, tier: d.tier)
            : rollBudget(rarity: d.rarity, tier: d.tier, rng: rng);
        final stats = rollCurves(
          combat: arch,
          workPriorities: picks,
          budget: budget,
          rng: rng,
          jitter: 0.6,
        );
        // Persist the assigned role so the editor can show it again.
        await svc.upsertSpeciesDef(d.copyWithStats(
          withEvoBumps(stats),
          role: SpeciesDef.encodeRole(arch.name, picks),
        ));
        count++;
      }
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '🎲 Re-rolled $count species — roles spread evenly per rarity & '
          'Typ verteilt.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildDevModeTheme(),
      // SIX menus plus Gebäude (user 2026-07-29). It used to be seven flat
      // tabs named after tables — Buildings, Pfad, Items, Eras, Species, Areas,
      // Resources — which meant "where do I set the party size" had no answer
      // and half the game's numbers had no tab at all. The grouping is by
      // SUBJECT now, and each subject that has loose numbers carries a
      // "⚙️ Werte" sub-tab holding them.
      child: DefaultTabController(
        length: 7,
        child: Scaffold(
            appBar: AppBar(
            title: Text('Dev Mode', style: FoE.title(size: 16)),
            actions: [
              // Migration 0005 backfills every existing account to
              // IntroStep.done, so without this there is no way to see the
              // new-player flow again on an account that has progress.
              TextButton(
                onPressed: () async {
                  await SettlementController().restartIntro();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Intro restarted — jumpstart is back on.'),
                    ),
                  );
                },
                child: Text('↺ Intro', style: FoE.label(size: 11)),
              ),
              // The way the tuned state gets OUT (user 2026-07-29) — see
              // DevExportSheet. In the app bar rather than in a tab because it
              // covers every tab.
              TextButton(
                onPressed: () => DevExportSheet.show(context),
                child: Text('📋 Export', style: FoE.label(size: 11)),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: '🏛 Settlement'),
                Tab(text: '🐾 Monster'),
                Tab(text: '🗺 Kampagne'),
                Tab(text: '🏠 Gebäude'),
                Tab(text: '🎒 Items'),
                Tab(text: '⛏ Ressourcen'),
                Tab(text: '🏺 Äras'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              // 1 · Settlement — the global numbers, and nothing else: there is
              // no settlement DEF to list, the buildings are their own menu.
              const TuningTab(group: TuningGroup.settlement),
              // 2 · Monster — species, budgets, abilities, the lab, and the
              // loose combat/gene/catch numbers.
              // Rebuilds on def edits/realtime so the 🔴 off-budget flags and
              // the fix button's result show without reopening the tab.
              AnimatedBuilder(
                animation: CreatureDefsController(),
                builder: (context, _) => _SpeciesHub(
                  onNewSpecies: () => _openSpeciesForm(context, null),
                  onOpenSpecies: (d) => _openSpeciesForm(context, d),
                  onFix: () => _normalizeSpeciesBudgets(context),
                  onReroll: () => _rerollAllStats(context),
                  onNewAbility: () => _openAbilityForm(context, null),
                  onOpenAbility: (d) => _openAbilityForm(context, d),
                ),
              ),
              // 3 · Kampagne — the path, the areas it runs through, and the
              // numbers that govern both. Areas moved in here from their own
              // top-level tab: an area only exists as a stop on the path.
              _SubTabs(
                labels: const ['Pfad', 'Gebiete', '⚙️ Werte'],
                children: [
                  // Reorderable battle nodes with enemies + rewards. Rebuilds
                  // on def edits/realtime so a saved node shows.
                  AnimatedBuilder(
                    animation: GameDefsController(),
                    builder: (context, _) => const PathEditorTab(),
                  ),
                  _DefList(
                    items:
                        (kAreaDefs.values.toList()
                              ..sort((a, b) => a.order.compareTo(b.order)))
                            .map(
                              (d) => _DefRow(
                                emoji: d.emoji,
                                name: '${d.order}. ${d.name} · '
                                    'S${d.battleStage}',
                                id: d.id,
                              ),
                            )
                            .toList(),
                    onNew: () => _openAreaForm(context, null),
                    onTap: (id) => _openAreaForm(context, kAreaDefs[id]),
                  ),
                  const TuningTab(group: TuningGroup.campaign),
                ],
              ),
              // 4 · Gebäude. Rebuilds on def edits/realtime so a saved building
              // (and its era) shows without reopening the tab.
              AnimatedBuilder(
                animation: GameDefsController(),
                builder: (context, _) => _BuildingsTab(
                  onNew: () => _openBuildingForm(context, null),
                  onOpen: (d) => _openBuildingForm(context, d),
                ),
              ),
              // 5 · Items — craftable/tradeable. Rebuilds on def edits.
              AnimatedBuilder(
                animation: GameDefsController(),
                builder: (context, _) => _DefList(
                  items: (kItemDefs.values.toList()
                        ..sort((a, b) => a.name.compareTo(b.name)))
                      .map((d) => _DefRow(
                          emoji: d.emoji,
                          name: '${d.name} · ${d.kind.name}',
                          id: d.id))
                      .toList(),
                  onNew: () => _openItemForm(context, null),
                  onTap: (id) => _openItemForm(context, kItemDefs[id]),
                ),
              ),
              // 6 · Ressourcen — the per-resource gathering dials (user
              // 2026-07-25): carry weight, mining speed, spot size and
              // regrowth, i.e. whether an expedition is worth sending.
              AnimatedBuilder(
                animation: GameDefsController(),
                builder: (context, _) => const GatherDefsTab(),
              ),
              // 7 · Äras.
              _DefList(
                items:
                    (kEraDefs.values.toList()
                          ..sort((a, b) => a.order.compareTo(b.order)))
                        .map(
                          (d) => _DefRow(
                            emoji: d.emoji,
                            name: '${d.order}. ${d.name}',
                            id: d.id,
                          ),
                        )
                        .toList(),
                onNew: () => _openEraForm(context, null),
                onTap: (id) => _openEraForm(context, kEraDefs[id]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One menu's sub-tabs — the same strip the Monster hub uses, extracted so
/// Kampagne (and anything after it) doesn't grow a second copy of it.
class _SubTabs extends StatelessWidget {
  final List<String> labels;
  final List<Widget> children;
  const _SubTabs({required this.labels, required this.children});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: labels.length,
    child: Column(
      children: [
        Material(
          color: FoE.bg,
          child: TabBar(
            isScrollable: true,
            labelColor: FoE.goldBright,
            unselectedLabelColor: FoE.textDim,
            indicatorColor: FoE.gold,
            tabs: [for (final l in labels) Tab(text: l)],
          ),
        ),
        Expanded(child: TabBarView(children: children)),
      ],
    ),
  );
}

/// The Monster hub (user 2026-07-24): sub-tabs for the species list, the global
/// budgets/attribute-limits form, the ability list, the combined ⚗️ Lab &
/// Balance-Matrix — and, since 2026-07-29, the ⚙️ Werte tab holding every
/// combat, gene and catch number that used to be a `const`.
class _SpeciesHub extends StatelessWidget {
  final VoidCallback onNewSpecies;
  final ValueChanged<SpeciesDef?> onOpenSpecies;
  final VoidCallback onFix;
  final VoidCallback onReroll;
  final VoidCallback onNewAbility;
  final ValueChanged<AbilityDef?> onOpenAbility;
  const _SpeciesHub({
    required this.onNewSpecies,
    required this.onOpenSpecies,
    required this.onFix,
    required this.onReroll,
    required this.onNewAbility,
    required this.onOpenAbility,
  });

  @override
  Widget build(BuildContext context) {
    return _SubTabs(
      labels: const [
        'Arten',
        '⚖️ Budgets & Grenzen',
        '⚙️ Werte',
        'Abilities',
        '⚗️ Lab & Matrix',
      ],
      children: [
        _SpeciesTab(
          onNew: onNewSpecies,
          onOpen: onOpenSpecies,
          onFix: onFix,
          onReroll: onReroll,
        ),
        // Its own Scaffold/tabs (Budget & Limits / Catch Rate) — embeds
        // fine inside the sub-tab.
        const SpeciesBalanceForm(),
        const TuningTab(group: TuningGroup.monster),
        _DefList(
          items: kAbilityDefs.values
              .map(
                (d) => _DefRow(
                  emoji: d.element.emoji,
                  name: '${d.name} · ${d.kind.label}',
                  id: d.id,
                ),
              )
              .toList(),
          onNew: onNewAbility,
          onTap: (id) => onOpenAbility(kAbilityDefs[id]),
        ),
        const _LabAndMatrix(),
      ],
    );
  }
}

/// The combined ⚗️ Lab & Balance-Matrix sub-tab (user 2026-07-24): a simple
/// toggle between the combat Lab and the species Balance-Matrix. The old
/// Expedition/Combat balance simulator was dropped.
class _LabAndMatrix extends StatefulWidget {
  const _LabAndMatrix();

  @override
  State<_LabAndMatrix> createState() => _LabAndMatrixState();
}

class _LabAndMatrixState extends State<_LabAndMatrix> {
  bool _showMatrix = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: _toggle('⚗️ Lab', !_showMatrix,
                    () => setState(() => _showMatrix = false)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _toggle('Balance Matrix', _showMatrix,
                    () => setState(() => _showMatrix = true)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _showMatrix
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SpeciesMatrixView(),
                )
              : const CombatLabScreen(),
        ),
      ],
    );
  }

  Widget _toggle(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: FoE.btn(active: active),
          alignment: Alignment.center,
          child: Text(
            label,
            style: FoE.label(size: 13)
                .copyWith(color: active ? Colors.white : FoE.textDim),
          ),
        ),
      );
}

/// Sort orders for the species list.
enum _SpeciesSort {
  name('Name A–Z'),
  rarity('Rarity'),
  tier('Region-Tier'),
  element('Element');

  final String label;
  const _SpeciesSort(this.label);
}

/// The Species dev tab: the same list as the other tabs, but with a search box
/// plus element/rarity/tier/off-budget filters and a sort selector on top
/// (user request 2026-07-17) — the content grows large enough that scanning it
/// raw got impractical.
class _SpeciesTab extends StatefulWidget {
  final VoidCallback onNew;
  final ValueChanged<SpeciesDef?> onOpen;
  final VoidCallback onFix;
  final VoidCallback onReroll;
  const _SpeciesTab({
    required this.onNew,
    required this.onOpen,
    required this.onFix,
    required this.onReroll,
  });

  @override
  State<_SpeciesTab> createState() => _SpeciesTabState();
}

class _SpeciesTabState extends State<_SpeciesTab> {
  String _search = '';
  CreatureElement? _element;
  CreatureRarity? _rarity;
  int? _tier;
  _SpeciesSort _sort = _SpeciesSort.name;

  bool _offBudget(SpeciesDef d) =>
      !isOnTotalBudget(stats: d.stats, rarity: d.rarity, tier: d.tier);

  /// The current filter + sort applied to every species def.
  List<SpeciesDef> _visible() {
    final q = _search.trim().toLowerCase();
    final list = kSpeciesDefs.values.where((d) {
      if (q.isNotEmpty &&
          !d.name.toLowerCase().contains(q) &&
          !d.id.toLowerCase().contains(q)) {
        return false;
      }
      if (_element != null && d.element != _element) return false;
      if (_rarity != null && d.rarity != _rarity) return false;
      if (_tier != null && d.tier != _tier) return false;
      return true;
    }).toList();
    int cmp(SpeciesDef a, SpeciesDef b) => switch (_sort) {
      _SpeciesSort.name => 0,
      _SpeciesSort.rarity => a.rarity.index.compareTo(b.rarity.index),
      _SpeciesSort.tier => a.tier.compareTo(b.tier),
      _SpeciesSort.element => a.element.index.compareTo(b.element.index),
    };
    // Name is always the tie-breaker so the list is stable within a group.
    list.sort((a, b) {
      final c = cmp(a, b);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    // Region tiers that actually exist, for the tier dropdown.
    final tiers = (kSpeciesDefs.values.map((d) => d.tier).toSet().toList()
      ..sort());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: _filterBar(visible.length, tiers),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text('Keine Arten', style: FoE.dim(size: 12)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _speciesRow(visible[i]),
                ),
        ),
      ],
    );
  }

  /// A tidy species card (user 2026-07-24): sprite · name (+ off-budget dot) ·
  /// element/rarity/tier tags on their own muted line.
  Widget _speciesRow(SpeciesDef d) {
    final off = _offBudget(d);
    return GestureDetector(
      onTap: () => widget.onOpen(kSpeciesDefs[d.id]),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: FoE.panel(radius: 8),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: BuildingIcon(
                imageUrl: d.stageAt(0).imageUrl,
                emoji: d.element.emoji,
                size: 30,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          d.name,
                          overflow: TextOverflow.ellipsis,
                          style:
                              FoE.label(size: 14).copyWith(color: FoE.parchment),
                        ),
                      ),
                      if (off) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Off-Budget — "Fix red budgets" repariert es',
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: FoE.danger,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _tag('${d.element.emoji} ${d.element.label}'),
                      _tag(d.rarity.label, color: FoE.gold),
                      _tag('Tier ${d.tier}'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: FoE.textDim, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _tag(String s, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 4)),
    child: Text(
      s,
      style: FoE.dim(size: 10).copyWith(color: color ?? FoE.textDim),
    ),
  );

  Widget _filterBar(int shown, List<int> tiers) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: widget.onNew,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: FoE.btn(active: true),
                alignment: Alignment.center,
                child: Text('+ Neue Art',
                    style:
                        FoE.label(size: 14).copyWith(color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$shown / ${kSpeciesDefs.length}',
            style: FoE.label(size: 12).copyWith(color: FoE.gold),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextField(
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, color: FoE.gold, size: 20),
          hintText: 'Search name or id…',
          hintStyle: FoE.label(size: 13).copyWith(color: FoE.textDim),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _dropdown<CreatureElement?>(
            value: _element,
            hint: 'Element',
            items: [
              const DropdownMenuItem(value: null, child: Text('Alle Elemente')),
              // Neutral is an ability-only type, never a creature's element.
              for (final e in CreatureElement.values
                  .where((e) => e != CreatureElement.neutral))
                DropdownMenuItem(value: e, child: Text('${e.emoji} ${e.label}')),
            ],
            onChanged: (v) => setState(() => _element = v),
          ),
          _dropdown<CreatureRarity?>(
            value: _rarity,
            hint: 'Rarity',
            items: [
              const DropdownMenuItem(value: null, child: Text('All rarities')),
              for (final r in CreatureRarity.values)
                DropdownMenuItem(value: r, child: Text(r.label)),
            ],
            onChanged: (v) => setState(() => _rarity = v),
          ),
          _dropdown<int?>(
            value: _tier,
            hint: 'Tier',
            items: [
              const DropdownMenuItem(value: null, child: Text('Alle Tiers')),
              for (final t in tiers)
                DropdownMenuItem(value: t, child: Text('Tier $t')),
            ],
            onChanged: (v) => setState(() => _tier = v),
          ),
          _dropdown<_SpeciesSort>(
            value: _sort,
            hint: 'Sortierung',
            items: [
              for (final s in _SpeciesSort.values)
                DropdownMenuItem(value: s, child: Text('↕ ${s.label}')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? _sort),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: widget.onFix,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: FoE.btn(),
                child: Center(
                  child: Text('⚖️ Fix red budgets',
                      style: FoE.label(size: 13)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: widget.onReroll,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: FoE.btn(active: true),
                child: Center(
                  child: Text(
                    '🎲 Re-roll all',
                    style: FoE.label(size: 13).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );

  /// A compact themed dropdown used for each filter/sort control.
  Widget _dropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: FoE.panel(radius: 8),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isDense: true,
        dropdownColor: FoE.bg,
        style: FoE.label(size: 13).copyWith(color: FoE.parchment),
        icon: const Icon(Icons.arrow_drop_down, color: FoE.gold),
        hint: Text(
          hint,
          style: FoE.label(size: 13).copyWith(color: FoE.textDim),
        ),
        items: items,
        onChanged: onChanged,
      ),
    ),
  );
}

/// The Buildings dev tab: the same list as the other tabs, plus a search box
/// and an ERA filter (user 2026-07-24) — WHICH ERA a building first becomes
/// buildable in. The generated Ära 3–8 roster made the list long enough to need
/// it.
class _BuildingsTab extends StatefulWidget {
  final VoidCallback onNew;
  final ValueChanged<BuildingDef?> onOpen;
  const _BuildingsTab({required this.onNew, required this.onOpen});

  @override
  State<_BuildingsTab> createState() => _BuildingsTabState();
}

class _BuildingsTabState extends State<_BuildingsTab> {
  String _search = '';
  int? _era;

  /// The era ORDER a building first becomes buildable in. Empty eraIds means
  /// "every era" (Main Hall, Road), so it is buildable from era 1 on.
  int _firstEra(BuildingDef d) {
    if (d.eraIds.isEmpty) return 1;
    final orders = d.eraIds.map((id) => kEraDefs[id]?.order).whereType<int>();
    return orders.isEmpty ? 1 : orders.reduce(math.min);
  }

  /// Row tag: the concrete era, or "Immer" for the always-available structures.
  String _eraLabel(BuildingDef d) =>
      d.eraIds.isEmpty ? 'Always' : 'Era ${_firstEra(d)}';

  List<BuildingDef> _visible() {
    final q = _search.trim().toLowerCase();
    final list = kBuildingDefs.values.where((d) {
      if (q.isNotEmpty &&
          !d.name.toLowerCase().contains(q) &&
          !d.id.toLowerCase().contains(q)) {
        return false;
      }
      if (_era != null && _firstEra(d) != _era) return false;
      return true;
    }).toList();
    // First-buildable era, then name — a stable, scannable order.
    list.sort((a, b) {
      final c = _firstEra(a).compareTo(_firstEra(b));
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    final eras = kEraDefs.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return _DefList(
      items: visible
          .map(
            (d) => _DefRow(
              imageUrl: d.imageUrl,
              name: '${d.name} · ${_eraLabel(d)}',
              id: d.id,
            ),
          )
          .toList(),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filterBar(visible.length, eras),
          const SizedBox(height: 8),
          _ApplyModelsButton(),
        ],
      ),
      onNew: widget.onNew,
      onTap: (id) => widget.onOpen(kBuildingDefs[id]),
    );
  }

  Widget _filterBar(int shown, List<EraDef> eras) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      TextField(
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, color: FoE.gold, size: 20),
          hintText: 'Search name or id…',
          hintStyle: FoE.label(size: 13).copyWith(color: FoE.textDim),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: FoE.panel(radius: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _era,
                isDense: true,
                dropdownColor: FoE.bg,
                style: FoE.label(size: 13).copyWith(color: FoE.parchment),
                icon: const Icon(Icons.arrow_drop_down, color: FoE.gold),
                hint: Text(
                  'First era',
                  style: FoE.label(size: 13).copyWith(color: FoE.textDim),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All eras'),
                  ),
                  for (final e in eras)
                    DropdownMenuItem(
                      value: e.order,
                      child: Text('${e.emoji} Era ${e.order} · ${e.name}'),
                    ),
                ],
                onChanged: (v) => setState(() => _era = v),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$shown / ${kBuildingDefs.length}',
            style: FoE.label(size: 12).copyWith(color: FoE.gold),
          ),
        ],
      ),
      _retiredStrip(),
    ],
  );

  // ── Gelöschte Gebäude (user 2026-07-31) ─────────────────────
  // "ich kann von dir erstellte gebäude wie z.b primitive wood camp nicht
  //  löschen, das möchte ich aber können"
  //
  // A bundled building is retired rather than deleted (see GameDefsController),
  // and a retired def is invisible BY DESIGN — which would make it unreachable
  // for good. This strip is the way back: everything you have removed, one tap
  // from returning.
  Widget _retiredStrip() {
    final ids = GameDefsController.retiredBuildingIds.toList()..sort();
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gelöscht (${ids.length}) — tippen zum Zurückholen',
            style: FoE.dim(size: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final id in ids)
                GestureDetector(
                  onTap: () => _restore(id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: FoE.panel(radius: 8),
                    child: Text(
                      '⟵ ${kFallbackBuildingDefs[id]?.name ?? id}',
                      style: FoE.label(size: 12).copyWith(color: FoE.textDim),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(String id) async {
    try {
      await GameDefsController().restoreBuildingDef(id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Zurückholen fehlgeschlagen: $e')));
      }
    }
  }
}

class _DefRow {
  final String emoji;
  final String? imageUrl;
  final String name;
  final String id;
  const _DefRow({
    this.emoji = '',
    this.imageUrl,
    required this.name,
    required this.id,
  });
}

/// "Alle N übernehmen": push every bundled render's own numbers into the DB.
///
/// ── Why this is not building_roster.sql (user 2026-08-12) ──
/// That script deletes all 89 rows and rewrites them from code, so using it to
/// fix a footprint also throws away every value tuned in this editor. This
/// touches exactly the fields the RENDERER measured — grid_w, grid_h and the
/// three placement numbers — on exactly the buildings that have a model, and
/// leaves costs, effects, era gates and everything else alone.
///
/// One reload at the end rather than one per building: saveBuildingDef()
/// re-reads every def table after each write, and twenty of those is twenty
/// round trips for one answer.
class _ApplyModelsButton extends StatefulWidget {
  @override
  State<_ApplyModelsButton> createState() => _ApplyModelsButtonState();
}

class _ApplyModelsButtonState extends State<_ApplyModelsButton> {
  bool _busy = false;

  /// The buildings whose live def disagrees with what the renderer measured.
  List<BuildingDef> _stale() {
    final out = <BuildingDef>[];
    for (final id in kBundledBuildingArt) {
      final live = kBuildingDefs[id];
      final model = kFallbackBuildingDefs[id];
      final box = kBundledArtBox[id];
      if (live == null || model == null || box == null) continue;
      final same = live.gridW == model.gridW &&
          live.gridH == model.gridH &&
          (live.artBaseWidth - box.$1).abs() < 0.0005 &&
          (live.artAnchorX - box.$2).abs() < 0.0005 &&
          (live.artLift - box.$3).abs() < 0.0005 &&
          (live.imageUrl == null || live.imageUrl!.isEmpty);
      if (!same) out.add(live);
    }
    return out;
  }

  Future<void> _apply() async {
    final stale = _stale();
    if (stale.isEmpty) return;
    setState(() => _busy = true);
    try {
      await GameDefsController().saveBuildingDefs([
        for (final live in stale)
          live.withModelArt(
            gridW: kFallbackBuildingDefs[live.id]!.gridW,
            gridH: kFallbackBuildingDefs[live.id]!.gridH,
            artBaseWidth: kBundledArtBox[live.id]!.$1,
            artAnchorX: kBundledArtBox[live.id]!.$2,
            artLift: kBundledArtBox[live.id]!.$3,
          ),
      ]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${stale.length} Gebäude auf die '
            'Modellwerte gesetzt'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _stale().length;
    return GestureDetector(
      onTap: _busy || n == 0 ? null : _apply,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: FoE.btn(),
        alignment: Alignment.center,
        child: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                n == 0
                    ? 'Renders & Grössen: alle aktuell'
                    : 'Renders & Grössen übernehmen ($n)',
                style: FoE.label(size: 13),
              ),
      ),
    );
  }
}

class _DefList extends StatelessWidget {
  final List<_DefRow> items;
  final VoidCallback onNew;
  final ValueChanged<String> onTap;

  /// Optional extra action rendered under "+ New" (e.g. the species tab's
  /// budget-fix button).
  final Widget? header;

  const _DefList({
    required this.items,
    required this.onNew,
    required this.onTap,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                GestureDetector(
                  onTap: onNew,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: FoE.btn(active: true),
                    child: Center(
                      child: Text(
                        '+ New',
                        style: FoE.label(
                          size: 15,
                        ).copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),
                if (header != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: header),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final item = items[i];
              return GestureDetector(
                onTap: () => onTap(item.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: FoE.panel(radius: 8),
                  child: Row(
                    children: [
                      BuildingIcon(
                        // The same list shows buildings, eras and elements;
                        // buildingAsset() returns null for everything that is
                        // not a modelled building, so this is free.
                        imageUrl: item.imageUrl,
                        defId: item.id,
                        emoji: item.emoji,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: FoE.label(
                                size: 15,
                              ).copyWith(color: FoE.parchment),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.id,
                              style: FoE.label(
                                size: 12,
                              ).copyWith(color: FoE.gold),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: FoE.parchment,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

