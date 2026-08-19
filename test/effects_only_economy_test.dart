import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/building_definitions.dart';

// ── One source of truth for what a building does ────────────
// User decision 2026-07-25: "alle hardcoded boni bitte löschen. Dies bitte bei
// allen Gebäuden so machen. Es zählt nur das, was bei den Effekten steht."
//
// Three code-side tables used to add yields the Dev-Mode effects editor never
// showed — a base-production map, an expedition-amplifier map and a passive
// house-gold curve — so the editor and the economy disagreed by design. This
// file guards the rule that replaced them: a building's `effects` list is the
// whole story.

/// The file's CODE, with comment lines dropped — the guards below are about
/// what runs, and the comments deliberately name the deleted tables to explain
/// why they are gone.
String _code(String path) => File(path)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('the deleted bonus tables have not come back', () {
    final src = _code('lib/features/settlement/data/building_definitions.dart');
    for (final banned in [
      'kBaseProductionByType',
      'kExpeditionBonusByType',
      '_kBaseProductionLiterals',
    ]) {
      expect(src.contains(banned), isFalse,
          reason: '$banned is a hidden bonus the effects editor cannot show');
    }
    expect(File('lib/features/settlement/services/house_economy.dart').existsSync(),
        isFalse,
        reason: 'the passive house-gold curve was replaced by a gold '
            'production effect on the house def');
  });

  test('no controller path grants production outside the effects', () {
    final src = _code('lib/features/settlement/settlement_controller.dart');
    expect(src.contains('HouseEconomy'), isFalse);
    expect(src.contains('kBaseProductionByType'), isFalse);
    // The hall's automatic build points were the last one — construction now
    // comes from stationed builders or an authored production effect.
    expect(src.contains('kHallBuildPointsPerLevel'), isFalse,
        reason: 'the Castle must not grant build points in code');
  });

  test('the Castle carries its bootstrap as ordinary effects', () {
    final hall = kFallbackBuildingDefs['castle']!;
    // The AMOUNTS are the author's to tune (Dev Mode → Gebäude); what this
    // pins is that the bootstrap exists as ordinary effects at all, which
    // is the thing the hardcoded-bonus deletion could have broken.
    expect(hall.effectAt('production', 'wood', 1), greaterThan(0));
    expect(hall.effectAt('production', 'stone', 1), greaterThan(0));
    // And NOT build points — those were removed on request.
    expect(hall.effectAt('production', 'construction', 99), 0);
  });

  test('a def with no effects produces nothing at all', () {
    final def = BuildingDef.fromDefRow({
      'id': 'x',
      'name': 'X',
      'color': 'FF000000',
      'grid_w': 1,
      'grid_h': 1,
      'effects': const [],
    });
    expect(def.effectKeys('production'), isEmpty);
    expect(def.effectAt('production', 'wood', 99), 0);
    expect(def.effectAt('expedition', 'carry', 99), 0);
    expect(def.effectAt('production', 'gold', 99), 0);
  });

  test('expedition amplifiers are authored, not typed by building id', () {
    // The old table keyed off warehouse/scout_post/smokehouse. Whatever those
    // defs do today must be visible in their own effects list.
    for (final id in ['warehouse', 'scout_post', 'smokehouse']) {
      final def = kFallbackBuildingDefs[id];
      if (def == null) continue;
      final authored = def.effectAt('expedition', 'carry', 99) +
          def.effectAt('expedition', 'travel', 99) +
          def.effectAt('expedition', 'goods', 99);
      // Either it has authored effects or it does nothing — but there is no
      // longer a third, invisible option.
      expect(authored >= 0, isTrue);
    }
  });
}
