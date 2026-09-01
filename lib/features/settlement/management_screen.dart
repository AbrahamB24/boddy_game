import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_kit.dart' show ParchmentDivider;
import '../common/widgets/parchment_page.dart';
import '../creatures/expeditions_screen.dart';
import '../creatures/services/creatures_controller.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'services/game_engine.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'widgets/building_icon.dart';

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

  static final PillPalette _pills = PillPalette.parchment;

  // Housing tab sort: null = by housing contributed (the default — the
  // number the whole tab is about), 'level' or 'name' otherwise. Picking the
  // same field again FLIPS the direction (2026-07-27 convention, same as the
  // egg picker and breeding screen's own sort pills).
  String? _housingSort;
  bool _housingDescending = true;

  // Work tab sort — same convention, null = by posts staffed (the default).
  String? _workSort;
  bool _workDescending = true;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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
        // The app's own section rule (user 2026-08-31) — see
        // [ParchmentDivider] for why it stops short of the bands.
        const ParchmentDivider(),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([_settlement, _creatures]),
            builder: (context, _) => TabBarView(
              controller: _tabs,
              children: [_tripsTab(), _workTab(), _housingTab()],
            ),
          ),
        ),
      ],
    ),
  );

  // ── Work tab ──────────────────────────────────────────────
  // Rebuilt to the Housing tab's own layout (user 2026-08-31: "genau gleich
  // Aufbau wie bei Housing, aber mit angepassten Informationen") — one
  // header line (title, an n/n count, the sort pill) over one compact row
  // per building (its own asset, name, level, a trailing number), tapping a
  // row into the SAME [showBuildingDetailDialog] Housing now opens. That
  // dialog already has its own "Manage" button into staffing every post a
  // building has, so the inline chips-and-picker UI this tab used to carry
  // (assign/unassign right here, a bottom-sheet roster per role) is gone
  // entirely rather than duplicated — one door into staffing, not two that
  // could drift apart.
  Widget _workTab() {
    final connected = _settlement.connectedBuildingIds;
    final workshops = <(PlacedBuilding, BuildingDef, int, int)>[];
    var assignedTotal = 0;
    var capTotal = 0;
    for (final b in _settlement.buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || def.workshops.isEmpty) continue;
      var assigned = 0;
      var cap = 0;
      for (final role in def.workshops) {
        cap += effectiveSlots(role, b.level);
        assigned += _creatures.creatures
            .where(
              (c) =>
                  c.assignedBuildingId == b.id && c.assignedStat == role.stat,
            )
            .length;
      }
      workshops.add((b, def, assigned, cap));
      assignedTotal += assigned;
      capTotal += cap;
    }
    workshops.sort((a, b) {
      final cmp = switch (_workSort) {
        'level' => a.$1.level.compareTo(b.$1.level),
        'name' => a.$2.name.compareTo(b.$2.name),
        // The default: posts STAFFED, same role the housing amount plays —
        // the number the whole tab is about (2026-08-31).
        _ => a.$3.compareTo(b.$3),
      };
      return _workDescending ? -cmp : cmp;
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ParchmentPage.kParchmentPagePad,
        12,
        ParchmentPage.kParchmentPagePad,
        12,
      ),
      children: [
        Row(
          children: [
            Text('Work', style: FoE.title(size: 14)),
            const SizedBox(width: 8),
            // Being FULLY staffed is a good state here, unlike Housing's
            // used/cap (where hitting the cap blocks new creatures) — so
            // this count never turns [FoE.danger], only gold.
            Text(
              '$assignedTotal/$capTotal',
              style: FoE.value(size: 14).copyWith(color: FoE.goldBright),
            ),
            const Spacer(),
            if (workshops.isNotEmpty) Flexible(child: _workSortPill()),
          ],
        ),
        const SizedBox(height: 10),
        if (workshops.isEmpty)
          Text(
            'No functional workshops yet — build (and road-connect) a work '
            'building first.',
            style: FoE.dim(size: 12),
          ),
        for (final (b, def, assigned, cap) in workshops)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            // Tapping a row opens the same building detail dialog the map
            // uses (user 2026-08-31) — same as the Housing tab's rows, and
            // where "Manage" actually staffs the posts this row counts.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showBuildingDetailDialog(context, _settlement, b),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: FoE.panel(radius: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: Center(
                        child: BuildingIcon(
                          imageUrl: def.imageUrl,
                          defId: def.id,
                          size: 56,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(def.name, style: FoE.label(size: 13)),
                          Text(
                            'Lv ${b.level}',
                            style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                          ),
                        ],
                      ),
                    ),
                    // Posts staffed / posts total — the Work tab's own
                    // number, in the housing row's own spot.
                    Text(
                      '$assigned/$cap',
                      style: FoE.value(size: 12).copyWith(color: FoE.gold),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Order the work list by posts staffed, by level, or by name — same
  /// field-picks-then-flips control as the Housing tab's own sort pill.
  Widget _workSortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: switch (_workSort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Posts',
    },
    engaged: _workSort != null || !_workDescending,
    value: _workSort ?? '',
    entries: const [
      MapEntry('', 'Posts'),
      MapEntry('level', 'Level'),
      MapEntry('name', 'Name'),
    ],
    trailing: Icon(
      _workDescending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: FoE.gold,
    ),
    selectedTrailing: _workDescending ? '↓' : '↑',
    onSelected: (v) {
      final picked = v.isEmpty ? null : v;
      setState(() {
        if (picked == _workSort) {
          _workDescending = !_workDescending;
        } else {
          _workSort = picked;
          _workDescending = true;
        }
      });
    },
  );

  // ── Housing tab ───────────────────────────────────────────
  Widget _housingTab() {
    final used = _settlement.housingUsed;
    final cap = _settlement.housingCapacity;
    // ONE ROW PER BUILDING, not grouped by type (user 2026-08-31: "die
    // Gebäude einzeln stehen mit dem Level, da sie je nachdem mehr Housing
    // bekommen werden, wenn sie auflefeln") — [housingSources] summed same-
    // type buildings into one count, which hid that two Houses at different
    // levels contribute different amounts. This mirrors its per-building math
    // (a `housing` EFFECT overrides the flat `population` column per era —
    // see [GameEngine.housingCapacity], the source [cap] above sums by) but
    // keeps every instance, and its level, on its own line.
    final eraOrder = _settlement.settlement?.eraIndex ?? 1;
    final connected = _settlement.connectedBuildingIds;
    final functional = _settlement.buildings
        .where((b) => GameEngine.functional(b, connected))
        .toList();
    double bonusTotal = 0;
    for (final b in functional) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def != null) {
        bonusTotal += def.populationBonus * buildingYieldFactor(b.level);
      }
    }
    final houses = <(PlacedBuilding, BuildingDef, double)>[];
    for (final b in functional) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null || !def.sheltersMonsters(eraOrder)) continue;
      final baseCap = def.hasEffect('housing', eraOrder)
          ? def.effectAt('housing', '', eraOrder, level: b.level)
          : def.housingCapacity * buildingYieldFactor(b.level);
      if (baseCap <= 0) continue;
      houses.add((b, def, baseCap * (1 + bonusTotal)));
    }
    houses.sort((a, b) {
      final cmp = switch (_housingSort) {
        'level' => a.$1.level.compareTo(b.$1.level),
        'name' => a.$2.name.compareTo(b.$2.name),
        _ => a.$3.compareTo(b.$3),
      };
      return _housingDescending ? -cmp : cmp;
    });
    // NO BAR, NO "slots free" LINE (user 2026-08-31: "braucht es nicht...
    // eigentlich nur n/n") — the panel that used to hold them is gone too;
    // the count now sits right on the section header the list already had,
    // so the tab opens on ONE header line instead of a card plus a second
    // title repeating the word "Housing".
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ParchmentPage.kParchmentPagePad,
        12,
        ParchmentPage.kParchmentPagePad,
        12,
      ),
      children: [
        Row(
          children: [
            Text('Housing', style: FoE.title(size: 14)),
            const SizedBox(width: 8),
            Text(
              '$used/$cap',
              style: FoE.value(
                size: 14,
              ).copyWith(color: used >= cap ? FoE.danger : FoE.goldBright),
            ),
            const Spacer(),
            // Flexible, not bare (2026-08-31 crash: "RenderFlex children
            // have non-zero flex but incoming width constraints are
            // unbounded") — [MenuPill] has an Expanded label INSIDE it, so
            // it needs a bounded width from whatever Row it sits in, same as
            // every other MenuPill in the app (always Expanded/Flexible).
            if (houses.isNotEmpty) Flexible(child: _housingSortPill()),
          ],
        ),
        const SizedBox(height: 10),
        if (houses.isEmpty)
          Text(
            'Only the Castle houses monsters so far.',
            style: FoE.dim(size: 12),
          ),
        for (final (b, def, amount) in houses)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            // Tapping a row opens the same building detail dialog the map
            // uses (user 2026-08-31) — the Housing tab used to be a dead
            // end you could only look at, with no way into the building's
            // own Effects/Upgrade card short of finding it on the map.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showBuildingDetailDialog(context, _settlement, b),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: FoE.panel(radius: 8),
                child: Row(
                  children: [
                    // The building's own asset, centred and bigger still (user
                    // 2026-08-31: "noch etwas grösser, so dass sie fast den
                    // gesamten Balken einnehmen und schön zentriert in der
                    // Höhe") — the row's own padding is thinner now too, so the
                    // icon (the tallest thing in the row) drives the bar's
                    // height and nearly fills it; Row's default
                    // crossAxisAlignment.center does the vertical centring.
                    SizedBox(
                      width: 64,
                      child: Center(
                        child: BuildingIcon(
                          imageUrl: def.imageUrl,
                          defId: def.id,
                          size: 56,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(def.name, style: FoE.label(size: 13)),
                          // THE LEVEL (user 2026-08-31): each building now
                          // stands on its own line because a levelled-up one
                          // shelters more than a fresh one of the same type —
                          // the level is what explains why two rows of the
                          // same building show two different numbers.
                          Text(
                            'Lv ${b.level}',
                            style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                          ),
                        ],
                      ),
                    ),
                    // No leaf glyph (user 2026-08-31: "rechts die Blätter
                    // löschen. Nur die effektive Zahl notieren") — just the
                    // number of slots this building contributes.
                    Text(
                      amount.toStringAsFixed(0),
                      style: FoE.value(size: 12).copyWith(color: FoE.gold),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Order the housing list by what it contributes, by level, or by name —
  /// same field-picks-then-flips control as the egg picker and breeding
  /// screen's own sort pills (2026-07-27 convention).
  Widget _housingSortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: switch (_housingSort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Housing',
    },
    engaged: _housingSort != null || !_housingDescending,
    value: _housingSort ?? '',
    entries: const [
      MapEntry('', 'Housing'),
      MapEntry('level', 'Level'),
      MapEntry('name', 'Name'),
    ],
    trailing: Icon(
      _housingDescending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: FoE.gold,
    ),
    selectedTrailing: _housingDescending ? '↓' : '↑',
    onSelected: (v) {
      final picked = v.isEmpty ? null : v;
      setState(() {
        if (picked == _housingSort) {
          _housingDescending = !_housingDescending;
        } else {
          _housingSort = picked;
          _housingDescending = true;
        }
      });
    },
  );

  // ── Trips tab ─────────────────────────────────────────────
  /// THE EXPEDITIONS HUB ITSELF, INLINE (user 2026-07-29). It used to be a
  /// shim: a card counting the running trips and a button that pushed the real
  /// screen. With the corner pad's Trips button gone, that shim would have been
  /// the only road to expeditions — one tap longer than the button it replaced,
  /// for a page you then had to leave twice.
  Widget _tripsTab() => const ExpeditionsBody();
}
