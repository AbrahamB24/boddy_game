import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/building_effects.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/data/workshop_role_effects.dart';

// The effect SHAPE is code now (user 2026-07-29: "schreibe die aktuellen
// Effekte in den Code zu den Gebäuden, ich muss nicht neue Effekte hinzufügen
// können, diese nur einstellen"), seeded from the author's live database.
//
// So the Dev-Mode form can no longer add, delete or retype an effect — which
// means a shape lost HERE is lost everywhere, with no way to put it back from
// inside the game. These are the shapes that carry rules; the numbers are the
// author's business and deliberately not pinned.
void main() {
  BuildingDef def(String id) => kFallbackBuildingDefs[id]!;

  test('the table is the only source — no def carries its own effects', () {
    // Every def literal goes through withEffects(), so a leftover inline list
    // would be silently ignored. This is what makes that safe to rely on.
    for (final d in kFallbackBuildingDefs.values) {
      final authored = kBuildingEffects[d.id] ?? BuildingEffects.none;
      expect(d.workshops.length, authored.workshops.length, reason: d.id);
      expect(d.effects.length, authored.effects.length, reason: d.id);
    }
  });

  test('every authored id is a real building', () {
    // A typo'd key would author effects onto nothing, silently.
    for (final id in kBuildingEffects.keys) {
      expect(kFallbackBuildingDefs.containsKey(id), isTrue, reason: id);
    }
  });

  test('the Scout Post grants the hunts and the expedition slots', () {
    // Nothing else grants either since the feature unlocks were deleted, and
    // the base slot count is 0 — lose these two and expeditions cease to exist.
    final scout = def('scout_post');
    expect(scout.effectKeys('huntOptions'), isNotEmpty);
    expect(scout.effectKeys('expeditionSlots'), isNotEmpty);
    expect(buildingEffectValueAt(scout, 'expeditionSlots', '', 1, 1),
        greaterThan(0));
  });

  test('every civil service has the post that drives it', () {
    // Each of these systems is staffed-only: an empty building raises nothing,
    // so a missing post makes the whole system unreachable.
    final expected = {
      'healing_hut': WorkshopRole.kHealSpeed,
      'trading_post': WorkshopRole.kTradeRate,
      'breeding_hut': WorkshopRole.kBreeding,
      'hatchery': WorkshopRole.kHatching,
      'builder_camp': WorkshopRole.kConstruction,
      'warehouse': WorkshopRole.kExpCarry,
      'smokehouse': WorkshopRole.kExpGoods,
      'caravanserai': WorkshopRole.kCaravan,
      'training_grounds': WorkshopRole.kTraining,
    };
    for (final e in expected.entries) {
      expect(
        def(e.key).workshops.map((w) => w.resource),
        contains(e.value),
        reason: e.key,
      );
    }
  });

  test('the housing buildings actually house someone', () {
    for (final id in ['castle', 'small_house', 'large_house']) {
      expect(def(id).effectKeys('housing'), isNotEmpty, reason: id);
    }
  });

  test('a work post reads a stat a monster can be assigned to', () {
    // A post whose stat is not postable can never be staffed — the assign
    // sheet would list it and no creature would ever match.
    for (final d in kFallbackBuildingDefs.values) {
      for (final w in d.workshops) {
        expect(kPostableStats, contains(w.stat), reason: '${d.id}/${w.resource}');
      }
    }
  });

  test('XP is not a per-building number any more', () {
    // User 2026-07-30: "Jedes Gebäude, welches Monster «anstellt» soll EP geben.
    // Jedes Gebäude gibt genau gleich viel EP."
    //
    // The rule lives in CreaturesController.xpRatePerHour and the rate in
    // XpConfig, so an `xp` effect coming back HERE would be a second, silent
    // answer to the same question — and the one the game no longer reads.
    for (final d in kFallbackBuildingDefs.values) {
      expect(d.effectKeys('xp'), isEmpty, reason: d.id);
    }
    expect(BuildingEffect.paletteTypes, isNot(contains('xp')));
    expect(kEffectRowTypes, isNot(contains('xp')));
  });

  test('every building with a work post pays the same XP', () {
    // The thing that used to be impossible to hold true by hand: eleven era-I
    // buildings carried an `xp` effect and the ~40 later ones with posts did
    // not, so a clay pit or a refinery levelled nobody. With one rate for every
    // post it is true by construction — this pins that there IS a post to pay
    // it in every era, so no era is a dead stretch for levelling by work.
    for (final era in [1, 2, 3, 4, 5, 6, 7, 8]) {
      final staffed = kFallbackBuildingDefs.values.where(
        (d) => d.workshops.isNotEmpty && d.startEraOrder <= era,
      );
      expect(staffed, isNotEmpty, reason: 'era $era has nothing to work in');
    }
    // Same rate at the same building level, whatever the building is or makes.
    for (final level in [1, 5, 10]) {
      expect(workXpPerHourAt(level), kXpBalance.workXpAt(level));
    }
    // And it grows only weakly with the building's level (user 2026-07-30:
    // "wächst mit level, aber nicht sehr stark" — the primary sources are
    // fighting and the Training Grounds).
    expect(workXpPerHourAt(10), greaterThan(workXpPerHourAt(1)));
    expect(workXpPerHourAt(24), lessThan(workXpPerHourAt(1) * 5));
    expect(workXpPerHourAt(1), lessThan(kTrainingXpPerHour));
  });

  test('no post produces a resource that does not exist', () {
    for (final d in kFallbackBuildingDefs.values) {
      for (final w in d.workshops) {
        if (!w.producesResource) continue;
        final known = const {'wood', 'stone', 'gold'}.contains(w.resource) ||
            kGoodsDefs.containsKey(w.resource);
        expect(known, isTrue, reason: '${d.id} makes "${w.resource}"');
      }
    }
  });
}
