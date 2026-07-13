import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../../creatures/services/creatures_controller.dart';
import '../data/building_definitions.dart';
import '../models/placed_building.dart';
import '../services/game_engine.dart';
import '../settlement_controller.dart';
import '../widgets/building_icon.dart';

// Housing & workforce overview — opened from the 🏠 header cell. Captured
// creatures ARE the population now: housing buildings cap how many you can
// own, workshops turn stationed creatures into production. This sheet shows
// both at a glance (capacity used, where it comes from, and how each workshop
// is staffed). Assigning creatures happens in the building's own dialog on the
// map; this is a read-only summary.
class PopulationOverviewSheet extends StatefulWidget {
  final SettlementController ctrl;
  const PopulationOverviewSheet({super.key, required this.ctrl});

  @override
  State<PopulationOverviewSheet> createState() =>
      _PopulationOverviewSheetState();
}

class _PopulationOverviewSheetState extends State<PopulationOverviewSheet> {
  SettlementController get ctrl => widget.ctrl;

  List<PlacedBuilding> get _workshops {
    final connected = ctrl.connectedBuildingIds;
    return ctrl.buildings.where((b) {
      if (!b.isComplete || !connected.contains(b.id)) return false;
      final def = kBuildingDefs[b.buildingTypeId];
      return def != null && def.workshops.isNotEmpty;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: FoE.panelGradient,
            border: Border(top: BorderSide(color: FoE.borderGold, width: 1.5)),
          ),
          child: AnimatedBuilder(
            animation: ctrl,
            builder: (context, _) {
              final used = ctrl.housingUsed;
              final cap = ctrl.housingCapacity;
              final sources = ctrl.housingSources;
              final workshops = _workshops;

              return Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FoE.borderGold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text('🏠', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Housing', style: FoE.title(size: 16)),
                          ),
                          Text(
                            '$used / $cap',
                            style: FoE.value(size: 14).copyWith(
                              color:
                                  used >= cap ? Colors.redAccent : FoE.goldBright,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        used >= cap
                            ? 'Full — build more housing to catch or hatch more creatures.'
                            : '${cap - used} free slot(s) for new creatures.',
                        style: FoE.dim(size: 11).copyWith(
                          color: used >= cap ? Colors.redAccent : FoE.textDim,
                        ),
                      ),
                      FoE.divider(vPad: 8),
                      if (sources.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No housing built yet.',
                            style:
                                FoE.dim(size: 11).copyWith(color: FoE.textDim),
                          ),
                        )
                      else
                        ...sources.map(_sourceRow),
                      const SizedBox(height: 14),
                      Text('Workshops', style: FoE.title(size: 14)),
                      const SizedBox(height: 8),
                      if (workshops.isEmpty)
                        Text(
                          'No connected workshop yet. Build one and station '
                          'creatures in it from its dialog on the map.',
                          style: FoE.dim(size: 11).copyWith(color: FoE.textDim),
                        )
                      else
                        ...workshops.map(_workshopRow),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sourceRow(ProductionSource s) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        BuildingIcon(imageUrl: s.imageUrl, emoji: s.emoji, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            s.count > 1 ? '${s.label} ×${s.count}' : s.label,
            style: FoE.label(size: 13),
          ),
        ),
        Text(
          '${s.amount.toStringAsFixed(0)} slots',
          style: FoE.value(size: 12).copyWith(color: FoE.gold),
        ),
      ],
    ),
  );

  Widget _workshopRow(PlacedBuilding b) {
    final def = kBuildingDefs[b.buildingTypeId]!;
    final creatures = CreaturesController();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BuildingIcon(imageUrl: def.imageUrl, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.name, style: FoE.label(size: 13)),
                for (final role in def.workshops)
                  Builder(builder: (_) {
                    final n = creatures.creatures
                        .where((c) =>
                            c.assignedBuildingId == b.id &&
                            c.assignedStat == role.stat)
                        .length;
                    return Text(
                      '${role.stat.label} → ${role.resource}: $n/${role.slots}',
                      style: FoE.dim(size: 10).copyWith(
                        color: n > 0 ? FoE.gold : FoE.textDim,
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
