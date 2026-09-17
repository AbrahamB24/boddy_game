import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import '../creatures/services/creatures_controller.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'widgets/building_icon.dart';

/// Its own screen (2026-09-11), split out of the Management hub — the Castle
/// already opens it directly through its own "Workers" button, so it did not
/// need to be a Management tab too. Same layout Housing settled on: a header
/// line (n/n, a sort pill) over one compact row per building, tapping a row
/// into the same [showBuildingDetailDialog] the map itself uses.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key});

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  final _settlement = SettlementController();
  final _creatures = CreaturesController();
  static final PillPalette _pills = PillPalette.parchment;

  // null = by posts staffed (the default), 'level' or 'name' otherwise —
  // picking the same field again flips the direction.
  String? _sort;
  bool _descending = true;

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: 'Work',
    child: ListenableBuilder(
      listenable: Listenable.merge([_settlement, _creatures]),
      builder: (context, _) => _body(),
    ),
  );

  Widget _body() {
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
            if (workshops.isNotEmpty) Flexible(child: _sortPill()),
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

  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: switch (_sort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Posts',
    },
    engaged: _sort != null || !_descending,
    value: _sort ?? '',
    entries: const [
      MapEntry('', 'Posts'),
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
