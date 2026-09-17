import 'package:flutter/material.dart';

import '../creature_detail_screen.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart' show kCreatureMaxLevel;
import '../models/creature_instance.dart';

/// Opens [CreatureDetailScreen] as a read-only preview of a WILD combatant's
/// own already-rolled genes (user 2026-09-14: seeing a find's stats before
/// deciding whether it's worth catching — first from the catch encounter's
/// intro screen, then "auch während des Kampfes" for an enemy mid-battle).
///
/// Nothing is re-rolled: [Combatant.wildStatBase]/[wildStatSlope] are copied
/// verbatim into the draft — the SAME genes [CreaturesController.captureWild]
/// keeps on an actual catch, so the preview is exactly what you'd get.
/// Defaults the Stats tab to MAX level: the decision this preview exists for
/// is "is this wild's ceiling worth it", not what it looks like at whatever
/// level this encounter/battle happens to be fought at.
///
/// No-op (returns false) if [c] has no wild genes to preview — a player-side
/// combatant, or a null-species enemy.
bool openWildPreview(BuildContext context, Combatant c) {
  final speciesId = c.speciesId;
  final base = c.wildStatBase;
  final slope = c.wildStatSlope;
  if (speciesId == null || base == null || slope == null) return false;
  final draft = CreatureInstance(
    id: '',
    userId: '',
    speciesId: speciesId,
    gender: c.gender,
    level: c.level,
    stage: c.stage,
    statBase: Map.of(base),
    statSlope: Map.of(slope),
    learnedAbilityIds: null,
  )..backfillAbilities();
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CreatureDetailScreen(
        previewCreature: draft,
        initialRefLevel: kCreatureMaxLevel,
      ),
    ),
  );
  return true;
}
