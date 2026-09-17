import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../models/placed_building.dart';
import '../widgets/building_icon.dart';

/// A minimal, DISPLAY-ONLY building popup for the read-only "visit a
/// friend's city" screen — modelled on creature_detail_screen.dart's
/// `previewCreature`/`_isPreview` pattern: a plain data snapshot in, no
/// action footer out. Deliberately NOT `building_detail_dialog.dart` (2440
/// lines, tightly wired to the live, mutable SettlementController for pause/
/// upgrade/manage-workers/etc.) — retrofitting a read-only flag through that
/// file would be threading a needle through code built for the opposite job.
Future<void> showBuildingInfoPopup(
  BuildContext context,
  PlacedBuilding building,
  BuildingDef def,
) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      width: 260,
      decoration: FoE.panel(radius: 14),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BuildingIcon(imageUrl: def.imageUrl, defId: def.id, size: 72),
          const SizedBox(height: 10),
          Text(def.name, style: FoE.title(size: 15), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            building.isComplete ? 'Level ${building.level}' : 'Under construction',
            style: FoE.label(size: 12).copyWith(color: FoE.textDim),
          ),
          if (building.isComplete && building.isPaused) ...[
            const SizedBox(height: 4),
            Text('Paused', style: FoE.label(size: 11).copyWith(color: FoE.danger)),
          ],
          if (def.population > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Shelters ${def.population} monsters',
              style: FoE.dim(size: 11).copyWith(color: FoE.textDim),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(backgroundColor: FoE.gold),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
  ),
);
