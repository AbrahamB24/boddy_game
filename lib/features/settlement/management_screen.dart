import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import '../creatures/expeditions_screen.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/creatures_controller.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'settlement_controller.dart';
import '../common/widgets/recess_bar.dart';

// The settlement "management" hub (user 2026-07-17): one place to run the
// people side of the town — WHO works WHERE (assign monsters straight to a
// building's work stations), the HOUSING budget, and the running EXPEDITIONS.
// Assignment on the map still works; this is the roster-first view of it.
class ManagementScreen extends StatefulWidget {
  /// Which tab to land on: 0 Trips, 1 Work, 2 Housing. The header's housing
  /// cell opens this screen ON housing — arriving on Trips and having to find
  /// the tab would make the shortcut barely a shortcut.
  final int initialTab;

  const ManagementScreen({super.key, this.initialTab = 0});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen>
    with SingleTickerProviderStateMixin {
  final _settlement = SettlementController();
  final _creatures = CreaturesController();
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 2),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Assignment helpers ────────────────────────────────────
  Future<void> _assign(
      String creatureId, PlacedBuilding b, WorkshopRole role) async {
    final err =
        await _settlement.assignCreatureToWorkshop(creatureId, b.id, role.stat);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err, style: FoE.label(size: 12))),
      );
    }
  }

  Future<void> _unassign(String creatureId) async {
    await _settlement.assignCreatureToWorkshop(creatureId, null, null);
  }

  static String _roleLabel(WorkshopRole role) => switch (role.resource) {
    WorkshopRole.kTraining => '🏋️ Training → XP',
    WorkshopRole.kConstruction => '🔨 ${role.stat.label} → Building',
    WorkshopRole.kCrafting => '⚒️ ${role.stat.label} → Crafting',
    _ => '${role.stat.label} → ${role.resource}',
  };

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: 'Management',
    child: Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: FoE.gold,
          unselectedLabelColor: FoE.textDim,
          indicatorColor: FoE.gold,
          // TRIPS LEADS (user 2026-07-29: "bei manage soll zunächst trips,
          // dann work und dann housing sein, dadurch kann der Trips button vom
          // main screen verschwinden"). It is the tab with a CLOCK on it —
          // something is out and coming back — where work assignments and the
          // housing budget are standing state you visit when you choose to.
          tabs: const [
            Tab(text: 'Trips'),
            Tab(text: 'Work'),
            Tab(text: 'Housing'),
          ],
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([_settlement, _creatures]),
            builder: (context, _) => TabBarView(
              controller: _tabs,
              children: [
                _tripsTab(),
                _workTab(),
                _housingTab(),
              ],
            ),
          ),
        ),
      ],
    ),
  );


  // ── Work tab ──────────────────────────────────────────────
  Widget _workTab() {
    final connected = _settlement.connectedBuildingIds;
    final workshops = [
      for (final b in _settlement.buildings)
        if (b.isComplete && connected.contains(b.id))
          if (kBuildingDefs[b.buildingTypeId] case final def?
              when def.workshops.isNotEmpty)
            (b, def),
    ];
    final idle = _creatures.creatures
        .where((c) =>
            c.assignedBuildingId == null && !_creatures.isOnExpedition(c.id))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Idle roster summary.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: FoE.panel(radius: 10),
          child: Row(
            children: [
              const Text('💤', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  idle.isEmpty
                      ? 'Everyone has a posting.'
                      : '${idle.length} idle monster${idle.length == 1 ? '' : 's'} — assign them to a station below.',
                  style: FoE.dim(size: 12).copyWith(
                    color: idle.isEmpty ? FoE.textDim : FoE.gold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (workshops.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No functional workshops yet — build (and road-connect) a work '
              'building first.',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 12),
            ),
          ),
        for (final (b, def) in workshops) ...[
          _buildingCard(b, def),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildingCard(PlacedBuilding b, BuildingDef def) => Container(
    padding: const EdgeInsets.all(12),
    decoration: FoE.panel(radius: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(def.name, style: FoE.title(size: 14)),
            const Spacer(),
            if (b.level > 1)
              Text('Lv ${b.level}', style: FoE.dim(size: 11).copyWith(color: FoE.gold)),
          ],
        ),
        const SizedBox(height: 8),
        for (final role in def.workshops) _roleRow(b, role),
      ],
    ),
  );

  Widget _roleRow(PlacedBuilding b, WorkshopRole role) {
    final assigned = _creatures.creatures
        .where((c) =>
            c.assignedBuildingId == b.id && c.assignedStat == role.stat)
        .toList();
    final slotCap = effectiveSlots(role, b.level);
    final free = slotCap - assigned.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: FoE.panel(radius: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_roleLabel(role),
                      style: FoE.label(size: 12).copyWith(color: FoE.gold)),
                ),
                Text('${assigned.length}/$slotCap',
                    style: FoE.dim(size: 11)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in assigned) _workerChip(c),
                if (free > 0) _assignBtn(b, role),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _workerChip(CreatureInstance c) => GestureDetector(
    onTap: () => _unassign(c.id),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: FoE.panelDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FoE.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.displayName,
              style: FoE.label(size: 11).copyWith(color: FoE.parchment)),
          const SizedBox(width: 4),
          const Icon(Icons.close, size: 12, color: FoE.textDim),
        ],
      ),
    ),
  );

  Widget _assignBtn(PlacedBuilding b, WorkshopRole role) => GestureDetector(
    onTap: () => _openPicker(b, role),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: FoE.btn(active: true),
      child: Text('+ Assign',
          style: FoE.label(size: 11).copyWith(color: Colors.white)),
    ),
  );

  // Picker: every monster, ranked by aptitude for this role's stat (training
  // ranks lowest level first — the same XP/h buys a low-level one the most).
  void _openPicker(PlacedBuilding b, WorkshopRole role) {
    final training = role.resource == WorkshopRole.kTraining;
    showModalBottomSheet(
      context: context,
      backgroundColor: FoE.panelDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ListenableBuilder(
        listenable: _creatures,
        builder: (context, _) {
          final list = [..._creatures.creatures]..sort((x, y) => training
              ? x.level.compareTo(y.level)
              : y.statValue(role.stat).compareTo(x.statValue(role.stat)));
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            builder: (_, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    training
                        ? 'Assign to Training'
                        : 'Assign to ${role.stat.label}',
                    style: FoE.title(size: 15),
                  ),
                ),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text('No monsters yet.',
                              style: FoE.dim(size: 12)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (_, i) =>
                              _pickerRow(b, role, list[i], training),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pickerRow(PlacedBuilding b, WorkshopRole role, CreatureInstance c,
      bool training) {
    final here = c.assignedBuildingId == b.id && c.assignedStat == role.stat;
    // Where it currently works, if anywhere else.
    String? posting;
    if (!here && c.assignedBuildingId != null) {
      final def = kBuildingDefs[
          _settlement.buildings
              .firstWhere((x) => x.id == c.assignedBuildingId,
                  orElse: () => b)
              .buildingTypeId];
      posting = def?.name;
    }
    return GestureDetector(
      onTap: here
          ? null
          : () async {
              await _assign(c.id, b, role);
              if (mounted) Navigator.of(context).pop();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: FoE.panel(radius: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.displayName,
                      style: FoE.label(size: 13).copyWith(color: FoE.parchment)),
                  Text(
                    training
                        ? 'Lv ${c.level}'
                        : '${role.stat.label} ${c.statValue(role.stat)}'
                            '${posting != null ? ' · at $posting' : c.assignedBuildingId == null ? ' · idle' : ''}',
                    style: FoE.dim(size: 10),
                  ),
                ],
              ),
            ),
            if (here)
              const Icon(Icons.check_circle, color: FoE.gold, size: 18)
            else
              Text('Assign',
                  style: FoE.label(size: 12).copyWith(color: FoE.goldBright)),
          ],
        ),
      ),
    );
  }

  // ── Housing tab ───────────────────────────────────────────
  Widget _housingTab() {
    final used = _settlement.housingUsed;
    final cap = _settlement.housingCapacity;
    final frac = cap > 0 ? (used / cap).clamp(0.0, 1.0) : 1.0;
    final houses = [
      for (final b in _settlement.buildings)
        if (b.isComplete)
          if (kBuildingDefs[b.buildingTypeId] case final def?
              when def.housingCapacity > 0)
            (b, def),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: FoE.panel(radius: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Housing', style: FoE.title(size: 14)),
                  const Spacer(),
                  Text('$used / $cap',
                      style: FoE.value(size: 14).copyWith(
                          color: used >= cap ? FoE.danger : FoE.goldBright)),
                ],
              ),
              const SizedBox(height: 8),
              RecessBar(
                value: frac,
                color: used >= cap ? FoE.danger : FoE.positive,
                height: 12,
              ),
              const SizedBox(height: 6),
              Text(
                used >= cap
                    ? 'Full — build more housing to catch, hatch or adopt more.'
                    : '${cap - used} slot${cap - used == 1 ? '' : 's'} free.',
                style: FoE.dim(size: 11).copyWith(
                    color: used >= cap ? FoE.danger : FoE.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Housing buildings', style: FoE.title(size: 13)),
        const SizedBox(height: 8),
        if (houses.isEmpty)
          Text('Only the Tribal Center houses monsters so far.',
              style: FoE.dim(size: 12)),
        for (final (_, def) in houses)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: FoE.panel(radius: 8),
              child: Row(
                children: [
                  Expanded(child: Text(def.name, style: FoE.label(size: 13))),
                  Text('🛏 ${def.housingCapacity}',
                      style: FoE.value(size: 12).copyWith(color: FoE.gold)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Trips tab ─────────────────────────────────────────────
  /// THE EXPEDITIONS HUB ITSELF, INLINE (user 2026-07-29). It used to be a
  /// shim: a card counting the running trips and a button that pushed the real
  /// screen. With the corner pad's Trips button gone, that shim would have been
  /// the only road to expeditions — one tap longer than the button it replaced,
  /// for a page you then had to leave twice.
  Widget _tripsTab() => const ExpeditionsBody();
}
