import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';

// The research→crafting rename (BP removal, 2026-07-16) is a DATA migration,
// not just a symbol rename: genes are persisted by stat NAME, so a creature
// saved before the rename holds `stat_base: {"research": …}`. Without the
// legacy alias those rolls stop being found and _backfillGenes refills them
// from the species mean — silently destroying an individual roll. These tests
// exist to stop anyone "tidying up" that alias away.

void main() {
  test('crafting reads a gene stored under the old research key', () {
    final c = CreatureInstance.fromRow({
      'id': 'c',
      'user_id': 'u',
      'species_id': 's',
      'gender': 'male',
      'level': 5,
      'xp': 0,
      'stage': 0,
      'stat_base': {'research': 42.0, 'mining': 7.0},
      'stat_slope': {'research': 1.5},
      'current_hp': -1,
      'current_energy': 100,
      'caught_at': '2026-01-01T00:00:00Z',
    });
    expect(c.statBase[CreatureStat.crafting], 42.0);
    expect(c.statSlope[CreatureStat.crafting], 1.5);
    // 'mining' is a RETIRED gene (user 2026-07-25: the four era-I work stats
    // were replaced and their genes are re-rolled from the species curve, not
    // carried over) — so it must NOT show up under the new stat.
    expect(c.statBase[CreatureStat.production], isNull);
    expect(c.needsGeneBackfill, isTrue,
        reason: 'the missing new genes are what triggers the re-roll');
  });

  test('the new key wins when both are present', () {
    final c = CreatureInstance.fromRow({
      'id': 'c',
      'user_id': 'u',
      'species_id': 's',
      'gender': 'male',
      'level': 1,
      'xp': 0,
      'stage': 0,
      'stat_base': {'crafting': 10.0, 'research': 99.0},
      'stat_slope': const {},
      'current_hp': -1,
      'current_energy': 100,
      'caught_at': '2026-01-01T00:00:00Z',
    });
    expect(c.statBase[CreatureStat.crafting], 10.0);
  });

  test('writes always use the new key, so a row heals on save', () {
    final c = CreatureInstance.fromRow({
      'id': 'c',
      'user_id': 'u',
      'species_id': 's',
      'gender': 'male',
      'level': 1,
      'xp': 0,
      'stage': 0,
      'stat_base': {'research': 42.0},
      'stat_slope': const {},
      'current_hp': -1,
      'current_energy': 100,
      'caught_at': '2026-01-01T00:00:00Z',
    });
    final base = c.toRow()['stat_base'] as Map;
    expect(base['crafting'], 42.0);
    expect(base.containsKey('research'), isFalse);
  });

  test('only crafting carries a legacy key', () {
    // A blanket alias would let any stat silently read a foreign value.
    for (final stat in CreatureStat.values) {
      expect(
        stat.legacyKey,
        stat == CreatureStat.crafting ? 'research' : isNull,
        reason: stat.name,
      );
    }
  });
}
