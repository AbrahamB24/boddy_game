import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/data/workshop_role_effects.dart';
import 'package:boddygame/features/settlement/services/trade_center.dart';

// The shared "what does this post actually do" vocabulary (user 2026-07-26).
// Four screens read it — build menu, upgrade sheet, building dialog, Dev-Mode
// preview — so its job is to be the ONLY place that turns a role's power into
// words, with the same ceilings the runtime applies.
void main() {
  test('only the system roles are treated as non-stockpile', () {
    for (final r in [
      WorkshopRole.kBreeding,
      WorkshopRole.kHealSpeed,
      WorkshopRole.kTradeRate,
      WorkshopRole.kExpCarry,
      WorkshopRole.kExpTravel,
      WorkshopRole.kExpGoods,
    ]) {
      expect(workshopRoleFeedsSystem(r), isTrue, reason: r);
    }
    // Construction, crafting, training and legendary slots are special too, but
    // each already has its own display path — they must NOT be swept in here.
    for (final r in [
      'wood',
      'gold',
      WorkshopRole.kConstruction,
      WorkshopRole.kCrafting,
      WorkshopRole.kTraining,
      WorkshopRole.kLegendaryBoost,
    ]) {
      expect(workshopRoleFeedsSystem(r), isFalse, reason: r);
    }
  });

  test('a plain resource has no role name — the caller names it', () {
    expect(workshopRoleName('wood'), isNull);
    expect(workshopRoleName(WorkshopRole.kBreeding), isNotNull);
  });

  test('breeding reports the time cut, never a raw power', () {
    expect(workshopRoleEffect(WorkshopRole.kBreeding, 0), '−0 %');
    expect(workshopRoleEffect(WorkshopRole.kBreeding, kBreedingK), '−50 %');
    // No ceiling since 2026-07-26 — it keeps climbing toward, but never to, 100%.
    expect(workshopRoleEffect(WorkshopRole.kBreeding, kBreedingK * 9), '−90 %');
    expect(workshopRoleEffect(WorkshopRole.kBreeding, 1e9), '−100 %');
  });

  test('each percentage role honours its own ceiling', () {
    expect(workshopRoleEffect(WorkshopRole.kHealSpeed, 5.0), '−90 %');
    expect(
      workshopRoleEffect(WorkshopRole.kTradeRate, 5.0),
      '−${(kMaxTradeDiscount * 100).round()} %',
    );
    // Travel has NO ceiling since 2026-07-29 (user: "expeditions soll kein cap
    // bei 60% haben") — it climbs toward, but never to, an instant trip. It is
    // in this group because the shape is the same as breeding's: a hyperbola,
    // not a clamp.
    expect(workshopRoleEffect(WorkshopRole.kExpTravel, 1.5), '−60 %');
    expect(workshopRoleEffect(WorkshopRole.kExpTravel, 5.0), '−83 %');
    expect(workshopRoleEffect(WorkshopRole.kCarTravel, 1e9), '−100 %');
    // The two amplifiers are uncapped — they really do keep growing.
    expect(workshopRoleEffect(WorkshopRole.kExpCarry, 1.5), '+150 %');
    expect(workshopRoleEffect(WorkshopRole.kExpGoods, 0.24), '+24 %');
  });

  test('a stockpile role falls through to the hourly form', () {
    expect(workshopRoleEffect('wood', 12.5), '+12.5/h');
  });

  // ── Nothing a building does may go unsaid (user 2026-07-29) ──
  // The Scout Post granted expedition slots from the day it moved to era I, and
  // its Effects card listed nothing at all: the type was never in the set the
  // card prints from. The bug is not "one type was forgotten", it is that a new
  // effect type can work perfectly and still be invisible — so the roster
  // itself is the test.
  test('every effect type the roster authors is printable', () {
    // The three the card renders in its own dedicated rows, not as effect
    // lines: outputs, seats, and the work posts themselves.
    const shownElsewhere = {'production', 'housing', 'workshop', 'bonus'};
    final authored = <String>{
      for (final def in kFallbackBuildingDefs.values)
        for (final e in def.effects) e.type,
    };
    for (final type in authored.difference(shownElsewhere)) {
      expect(
        kEffectRowTypes,
        contains(type),
        reason: '$type is authored but no screen would print it',
      );
      // …and it must have words and a glyph of its own, or the row says
      // "expeditionSlots  1 📦".
      expect(buildingEffectLabel(type), isNot(type), reason: type);
      expect(buildingEffectEmoji(type), isNot('📦'), reason: type);
    }
  });

  // ── The Effects card covers EVERY effect (user 2026-07-30) ──
  // "schaue, dass jedes Gebäude wirklich jeden Effekt abdeckt im
  // Gebäudedetailscreen (wenn ich auf ein Gebäude drücke)."
  group('a building dialog leaves no authored effect unsaid', () {
    test('every building: one row per authored effect, none dropped', () {
      for (final def in kFallbackBuildingDefs.values) {
        for (final era in [1, 8]) {
          // What the card is REQUIRED to say: every effect authored for this
          // era, minus the three with dedicated rows of their own.
          final owed = <String>{
            for (final e in def.effects)
              if (e.era <= era &&
                  e.type != 'production' &&
                  e.type != 'housing' &&
                  e.type != 'storage')
                e.key.isEmpty
                    ? buildingEffectLabel(e.type)
                    : '${buildingEffectLabel(e.type)} · ${e.key}',
          };
          final said = {
            for (final r in buildingEffectCardRows(def, era, 1)) r.label,
          };
          expect(said, containsAll(owed), reason: '${def.id} in era $era');
        }
      }
    });

    test('an effect worth nothing yet says WHEN, instead of vanishing', () {
      // THE bug: the Builder Camp's two grants both start at 0 and arrive at a
      // level, so its Effects card was empty until Lv 3 while the Upgrade panel
      // right below it already promised them.
      final camp = kFallbackBuildingDefs['builder_camp']!;
      final atOne = {
        for (final r in buildingEffectCardRows(camp, 1, 1)) r.label: r,
      };
      final sites = atOne[buildingEffectLabel('buildSlots')]!;
      expect(sites.pending, isTrue);
      expect(sites.value, startsWith('from Lv '));
      expect(
        sites.value,
        contains('${firstLevelWithEffect(camp, 'buildSlots', '', 1)}'),
      );
      // …and once it HAS arrived the row states the number, not the level.
      final arrived = {
        for (final r in buildingEffectCardRows(camp, 1, 24)) r.label: r,
      };
      expect(arrived[buildingEffectLabel('buildSlots')]!.pending, isFalse);
      expect(
        arrived[buildingEffectLabel('buildSlots')]!.value,
        isNot(contains('from Lv')),
      );
    });

    test('a LATER era\'s effect is not promised in this one', () {
      // The one thing that must still be skipped: a special building's era-2
      // production is not an effect it has in era 1.
      final special = kFallbackBuildingDefs['special_materials_e2']!;
      expect(special.effects.any((e) => e.era == 2), isTrue);
      for (final row in buildingEffectCardRows(special, 1, 1)) {
        expect(row.label, isNot(contains('era 2')));
      }
    });

    test('every type the EDITOR can author would be printed', () {
      // Stronger than "every type currently authored": a type the Dev-Mode form
      // offers but no card prints is invisible the moment it is first used —
      // which is exactly how the Scout Post's expedition slots stayed silent.
      const shownElsewhere = {'production', 'housing'};
      for (final type in BuildingEffect.paletteTypes) {
        if (shownElsewhere.contains(type)) continue;
        expect(kEffectRowTypes, contains(type), reason: type);
        expect(buildingEffectLabel(type), isNot(type), reason: type);
      }
    });
  });

  test('the Scout Post says how many expeditions can run at once', () {
    final def = kFallbackBuildingDefs['scout_post']!;
    expect(def.effectKeys('expeditionSlots'), contains(''));
    expect(kEffectRowTypes, contains('expeditionSlots'));
    // Level 1 grants the settlement's ONLY slot (the base pool is 0), and
    // levelling adds more. The exact rungs are tuned in Dev Mode.
    expect(buildingEffectValueAt(def, 'expeditionSlots', '', 1, 1), 1);
    expect(
      buildingEffectValueAt(def, 'expeditionSlots', '', 1, 99),
      greaterThan(buildingEffectValueAt(def, 'expeditionSlots', '', 1, 1)),
    );
    expect(formatBuildingEffect('expeditionSlots', '', 2), '2');
    expect(buildingEffectLabel('expeditionSlots'), 'Expedition slots');
  });

  // The combined post's figures STACK in the building dialog and the upgrade
  // sheet (user 2026-07-29: "diese Effekte sollen übereinander stehen nicht
  // nebeneinander"), so both screens need the clauses unjoined. This pins the
  // contract they read: one entry per figure, in authoring order, zeroes out.
  group('a combined post reads as separate lines', () {
    const power = {
      WorkshopRole.kExpCarry: 0.01,
      WorkshopRole.kExpGoods: 0.07,
      WorkshopRole.kExpTravel: 0.05,
    };

    test('one clause per figure, glyph included', () {
      final parts = workshopPowerParts(power);
      expect(parts, hasLength(3));
      expect(parts[0], '+1 % 🎒');
      expect(parts[1], '+7 % 📦');
      expect(parts[2], '−5 % 🥾');
    });

    test('a dial turned off gets no line of its own', () {
      // The Scout Post leaves the goods yield to the Smokehouse; a "+0 %" line
      // would be a row that says nothing, forever.
      final parts = workshopPowerParts({...power, WorkshopRole.kExpGoods: 0});
      expect(parts, hasLength(2));
      expect(parts.any((p) => p.contains('📦')), isFalse);
    });

    test('the joined form is the same clauses, so the two cannot drift', () {
      expect(workshopPowerLabel(power), workshopPowerParts(power).join(' · '));
    });

    test('an ordinary post is still exactly one line', () {
      expect(workshopPowerParts({WorkshopRole.kHealSpeed: 0.3}), hasLength(1));
    });
  });
}
