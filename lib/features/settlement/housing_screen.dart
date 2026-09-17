import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'services/game_engine.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'widgets/building_icon.dart';

/// Its own screen (2026-09-11), split out of the Management hub — every
/// sheltering building (Castle included) already opens it directly through
/// its own "Population" button, so it did not need to be a Management tab
/// too.
class HousingScreen extends StatefulWidget {
  const HousingScreen({super.key});

  @override
  State<HousingScreen> createState() => _HousingScreenState();
}

class _HousingScreenState extends State<HousingScreen> {
  final _settlement = SettlementController();
  static final PillPalette _pills = PillPalette.parchment;

  // null = by housing contributed (the default), 'level' or 'name'
  // otherwise — picking the same field again flips the direction.
  String? _sort;
  bool _descending = true;

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: 'Housing',
    child: ListenableBuilder(
      listenable: _settlement,
      builder: (context, _) => _body(),
    ),
  );

  Widget _body() {
    final used = _settlement.housingUsed;
    final cap = _settlement.housingCapacity;
    // ONE ROW PER BUILDING, not grouped by type — two Houses at different
    // levels contribute different amounts, which grouping would hide.
    final eraOrder = _settlement.dungeonMaxStage;
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
      final cmp = switch (_sort) {
        'level' => a.$1.level.compareTo(b.$1.level),
        'name' => a.$2.name.compareTo(b.$2.name),
        _ => a.$3.compareTo(b.$3),
      };
      return _descending ? -cmp : cmp;
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
            Text('Housing', style: FoE.title(size: 14)),
            const SizedBox(width: 8),
            Text(
              '$used/$cap',
              style: FoE.value(
                size: 14,
              ).copyWith(color: used >= cap ? FoE.danger : FoE.goldBright),
            ),
            const Spacer(),
            if (houses.isNotEmpty) Flexible(child: _sortPill()),
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
            child: Pressable(
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

  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: switch (_sort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Housing',
    },
    engaged: _sort != null || !_descending,
    value: _sort ?? '',
    entries: const [
      MapEntry('', 'Housing'),
      MapEntry('level', 'Level'),
      MapEntry('name', 'Name'),
    ],
    trailing: Icon(
      _descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: FoE.gold,
    ),
    selectedTrailing: _descending ? '↓' : '↑',
    onSelected: (v) {
      final picked = v.isEmpty ? null : v;
      setState(() {
        if (picked == _sort) {
          _descending = !_descending;
        } else {
          _sort = picked;
          _descending = true;
        }
      });
    },
  );
}
