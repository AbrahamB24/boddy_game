import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/era_definitions.dart';
import 'package:boddygame/features/settlement/services/game_defs_controller.dart';

/// Regression: editing ONE def in Dev Mode wiped every other one.
///
/// Reported from a real session — "mir wurden die Gebäude gelöscht, als ich
/// bei der main hall ein png hinzugefügt habe". Uploading an image writes a
/// single `building_defs` row; the loader then saw a non-empty table, cleared
/// the live roster and refilled it from that ONE row. Every placed woodland
/// camp/quarry/hut instantly had no type (`kBuildingDefs[id]` → null → skipped
/// everywhere), so they vanished from the map and the economy. The rows in
/// `placed_buildings` were never touched — only their TYPE disappeared.
///
/// These tests exercise the merge rule the loader now follows. They rebuild
/// the maps the same way GameDefsController does rather than hitting Supabase.
void main() {
  /// THE REAL MERGE, not a copy of it (2026-07-31). This helper used to
  /// re-implement the three lines it was testing, which meant the test could
  /// only ever confirm that the test was right.
  ///
  /// Rows are handed over as a def-per-id map and turned into the row shape the
  /// loader sees, so a test stays about the RULE and not about column names.
  void mergeInto<T>(
    Map<String, T> live,
    Map<String, T> fallback,
    Map<String, T> dbRows, {
    Set<String> retired = const {},
    Set<String>? collectRetired,
  }) {
    final defs = <String, T>{...dbRows};
    GameDefsController.mergeDefRows<T>(
      live,
      fallback,
      [
        for (final id in {...dbRows.keys, ...retired})
          {'id': id, if (retired.contains(id)) 'retired': true},
      ],
      (row) => defs[row['id'] as String] as T,
      retired: collectRetired,
    );
  }

  tearDown(() {
    kBuildingDefs
      ..clear()
      ..addAll(kFallbackBuildingDefs);
    kEraDefs
      ..clear()
      ..addAll(kFallbackEraDefs);
  });

  group('one authored def must not wipe the roster', () {
    test('editing castle leaves every other building alive', () {
      final edited = kFallbackBuildingDefs['castle']!;
      // Exactly the shape of the bug: the DB holds ONE row.
      mergeInto(kBuildingDefs, kFallbackBuildingDefs, {'castle': edited});

      expect(kBuildingDefs.length, kFallbackBuildingDefs.length);
      for (final id in kFallbackBuildingDefs.keys) {
        expect(kBuildingDefs[id], isNotNull, reason: '$id went missing');
      }
      // And the buildings a player has placed still resolve — which is what
      // "my buildings were deleted" actually meant.
      for (final id in ['small_wood_camp', 'small_stone_camp', 'small_house', 'healing_hut']) {
        expect(kBuildingDefs[id], isNotNull, reason: id);
      }
    });

    test('the authored version wins for its own id', () {
      const custom = BuildingDef(
        id: 'castle',
        name: 'Edited Hall',
        color: Color(0xFF000000),
        gridW: 3,
        gridH: 3,
      );
      mergeInto(kBuildingDefs, kFallbackBuildingDefs, {'castle': custom});
      expect(kBuildingDefs['castle']!.name, 'Edited Hall');
    });

    test('a brand-new def is added without displacing anything', () {
      const extra = BuildingDef(
        id: 'watchtower',
        name: 'Watchtower',
        color: Color(0xFF000000),
        gridW: 2,
        gridH: 2,
      );
      mergeInto(kBuildingDefs, kFallbackBuildingDefs, {'watchtower': extra});
      expect(kBuildingDefs['watchtower'], isNotNull);
      expect(kBuildingDefs.length, kFallbackBuildingDefs.length + 1);
    });

    test('an empty table leaves the bundled content untouched', () {
      mergeInto(kBuildingDefs, kFallbackBuildingDefs, <String, BuildingDef>{});
      expect(kBuildingDefs.length, kFallbackBuildingDefs.length);
    });
  });

  group('the same rule holds for the other bundled maps', () {
    test('eras', () {
      final one = kFallbackEraDefs['era_1']!;
      mergeInto(kEraDefs, kFallbackEraDefs, {'era_1': one});
      expect(kEraDefs.length, kFallbackEraDefs.length);
      expect(kEraDefs['era_2'], isNotNull);
    });
  });

  // ── Ein generiertes Gebäude wirklich löschen (2026-07-31) ───
  // "ich kann von dir erstellte gebäude wie z.b primitive wood camp nicht
  //  löschen, das möchte ich aber können"
  //
  // The merge's whole job is that the bundled roster survives whatever the DB
  // says — which is exactly why removing one deliberately needs its own rule.
  // A tombstone is the one row that SUBTRACTS, so it is also the one row that
  // could bring the old wipe-the-roster bug back if it ever over-reached.
  group('a retired def', () {
    test('is gone even though the app bundles it', () {
      expect(kFallbackBuildingDefs.containsKey('small_wood_camp'), isTrue,
          reason: 'the seed this test is about');
      mergeInto(
        kBuildingDefs,
        kFallbackBuildingDefs,
        const {},
        retired: {'small_wood_camp'},
      );
      expect(kBuildingDefs.containsKey('small_wood_camp'), isFalse);
    });

    test('takes NOTHING else with it', () {
      // The failure mode that matters: one tombstone must not be read as "the
      // DB is authoritative, drop the rest".
      mergeInto(
        kBuildingDefs,
        kFallbackBuildingDefs,
        const {},
        retired: {'small_wood_camp'},
      );
      expect(kBuildingDefs.length, kFallbackBuildingDefs.length - 1);
      for (final id in kFallbackBuildingDefs.keys) {
        if (id == 'small_wood_camp') continue;
        expect(kBuildingDefs[id], isNotNull, reason: '$id went missing');
      }
    });

    test('is reported back, or Dev Mode could never restore it', () {
      final retired = <String>{};
      mergeInto(
        kBuildingDefs,
        kFallbackBuildingDefs,
        const {},
        retired: {'small_wood_camp', 'small_house'},
        collectRetired: retired,
      );
      expect(retired, {'small_wood_camp', 'small_house'});
    });

    test('comes back when the tombstone goes', () {
      // "Restore" is simply the row being deleted — the fallback then comes
      // through the merge again, which is what it always did.
      final retired = <String>{};
      mergeInto(kBuildingDefs, kFallbackBuildingDefs, const {},
          retired: {'small_wood_camp'}, collectRetired: retired);
      mergeInto(kBuildingDefs, kFallbackBuildingDefs, const {},
          collectRetired: retired);
      expect(kBuildingDefs['small_wood_camp'], isNotNull);
      expect(retired, isEmpty, reason: 'the strip must empty out too');
    });
  });
}
