import '../../settlement/data/building_definitions.dart';
import '../../settlement/data/item_definitions.dart';
import '../models/path_node.dart';
import 'overworld_path.dart';

/// One reward line shown before/after a battle: an emoji + a short label.
class RewardLine {
  final String emoji;
  final String text;

  /// Set only for a "new building" line. Lets a screen that wants to show
  /// the building's own preview picture instead of the emoji+text pair find
  /// it (user 2026-08-28: battle_prep_screen's brief now does this) without
  /// every OTHER reader of [RewardLine] — battle_screen's victory list still
  /// reads emoji/text and needs no change.
  final String? buildingId;
  const RewardLine(this.emoji, this.text, {this.buildingId});
}

/// What CLEARING [battleNumber] unlocks — the things worth previewing before the
/// fight and celebrating after it (user 2026-07-24): a bigger battle party, new
/// buildings and, on a
/// boss, the region legendary + the next region.
///
/// XP is granted to every participant regardless of the battle, so it isn't a
/// "reward" listed here — the battle screen already shows the XP/level-ups.
/// Returns empty for a re-fight (nothing new to unlock).
List<RewardLine> battleRewardsFor(int battleNumber) {
  final lines = <RewardLine>[];
  final node = pathNodeAtOrder(battleNumber);

  // A wider battle party (still a rule of position on the line).
  if (battleNumber > 1 &&
      partySizeForBattle(battleNumber) > partySizeForBattle(battleNumber - 1)) {
    lines.add(
      RewardLine(
        '👥',
        'Bring ${partySizeForBattle(battleNumber)} monsters into battle',
      ),
    );
  }

  if (node != null) {
    // Authored rewards on the node.
    // Raw resources are gone (user 2026-07-30) — everything material arrives as
    // an item, and a resource PACKAGE says what it opens into so the briefing
    // still promises a number rather than a parcel.
    for (final e in node.rewards.items.entries) {
      final def = kItemDefs[e.key];
      final count = e.value > 1 ? ' ×${e.value}' : '';
      final holds = def != null && def.kind == ItemKind.resourcePack
          ? ' (${def.magnitude.toStringAsFixed(0)} ${def.resourceId})'
          : '';
      lines.add(
        RewardLine(def?.emoji ?? '🎁', '${def?.name ?? e.key}$count$holds'),
      );
    }
    for (final id in node.rewards.buildings) {
      final def = kBuildingDefs[id];
      lines.add(
        RewardLine('🏛️', 'New building: ${def?.name ?? id}', buildingId: id),
      );
    }
    if (node.rewards.expansions > 0) {
      lines.add(
        RewardLine(
          '🗺️',
          '+${node.rewards.expansions} territory expansion'
              '${node.rewards.expansions > 1 ? 's' : ''}',
        ),
      );
    }
    if (node.rewards.huntOptions > 0) {
      lines.add(
        RewardLine(
          '🪤',
          '+${node.rewards.huntOptions} longer hunt'
              '${node.rewards.huntOptions > 1 ? 's' : ''} unlocked',
        ),
      );
    }
  } else {
    // No authored node (path emptied) — fall back to the legacy unlock tables.
    for (final e in kBuildingUnlockBattle.entries) {
      if (e.value != battleNumber) continue;
      final def = kBuildingDefs[e.key];
      if (def != null) {
        lines.add(
          RewardLine('🏛️', 'New building: ${def.name}', buildingId: e.key),
        );
      }
    }
  }

  // The era gate.
  if (node?.isBoss ?? isBossBattle(battleNumber)) {
    lines.add(
      const RewardLine('👑', 'Region legendary + the next region opens'),
    );
  }

  return lines;
}
