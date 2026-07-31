// Region-progression redesign: the procedural Slay-the-Spire dungeon (paths,
// catch/heal nodes, the DungeonMap graph) is gone — each region now has ONE
// fixed battles-only dungeon (services/region_dungeon.dart). What survives
// here is the stage→level mapping shared by the region dungeon, the capture
// encounter and the combat Monte-Carlo. A region's "stage" is its
// AreaDef.battleStage.

/// Highest region reached; a region unlocks once dungeonMaxStage >= its
/// battleStage (SettlementController.dungeonMaxStage). Kept as a wide cap so
/// content isn't gated by an arbitrary ladder length.
const int kMaxDungeonStage = 99;

/// Wild level for a stage: 5 + (stage-1)·8 — S1=5, S2=13, S3=21 … Bosses sit
/// +6 above, using the level range up to the cap.
int wildLevelForStage(int stage) => 5 + (stage - 1) * 8;
int bossLevelForStage(int stage) => wildLevelForStage(stage) + 6;
