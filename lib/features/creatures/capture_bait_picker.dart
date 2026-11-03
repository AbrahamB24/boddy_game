import '../settlement/data/item_definitions.dart';

/// Synthetic stand-in for the tutorial's guaranteed practice throw — never
/// persisted, never consumed. The real choice happens in the command
/// deck's bait page now (user 2026-10-04 — see BattleScreen._baitPage),
/// not a bottom sheet; this file just keeps that page's one constant.
final ItemDef practiceBait = ItemDef(
  id: 'practice_bait',
  name: 'Practice Bait',
  emoji: '🥅',
  description: 'Tutorial only — never leaves the bag.',
  kind: ItemKind.catchBoost,
  magnitude: 0.10,
  craftSeconds: 0,
);
