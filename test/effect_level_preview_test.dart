import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/dev/effects_editor.dart';

// Two things are checked here, and they belong together:
//
//  1. every effect type the EDITOR can author survives BuildingDef.fromDefRow.
//     A type missing from the parser is dropped silently on load — that is
//     exactly how the new `trade` effect went missing from the Trade Center's
//     DB row (2026-07-25), while the bundled code def kept working.
//  2. the Dev-Mode "Wirkung pro Stufe" preview prints what the runtime will
//     actually compute at that level.

Map<String, dynamic> _row(List<Map<String, dynamic>> effects) => {
  'id': 'x',
  'name': 'X',
  'color': 'FF000000',
  'grid_w': 1,
  'grid_h': 1,
  'effects': effects,
};

void main() {
  group('every authorable effect type survives a DB round-trip', () {
    test('trade is parsed, not dropped (the bug this test exists for)', () {
      final def = BuildingDef.fromDefRow(_row([
        {'type': 'trade', 'value': 5.0, 'era': 1},
      ]));
      expect(def.tradePercentAt(1), 5);
      expect(def.tradePercentAt(3), 10); // global +50%/level curve
    });

    test('a workshop role round-trips with its per-level slot steps', () {
      final def = BuildingDef.fromDefRow(_row([
        {
          'type': 'workshop',
          'stat': 'woodcutting',
          'resource': 'wood',
          'mult': 0.5,
          'slots': 4,
          'slotSteps': {'3': 2},
        },
      ]));
      expect(def.workshops, hasLength(1));
      expect(effectiveSlots(def.workshops.first, 2), 4);
      expect(effectiveSlots(def.workshops.first, 3), 6);
    });

    test('the palette list covers every per-era type the editor offers', () {
      // The editor's dropdown minus the two that are not BuildingEffects.
      const authorable = {
        'production', 'resource', 'expedition', 'expeditionSlots',
        // Caravans are their own pool and their own amplifiers since
        // 2026-07-29 — see expedition_slots_test.dart.
        'caravan', 'caravanSlots',
        // The Scout Post's hunt-length grant (user 2026-07-26) — the
        // replacement for the deleted hunt_length_2..6 feature unlocks.
        'huntOptions',
        'heal',
        // Two separate caps on the Healing Hut: how many it treats at once,
        // and how many may WAIT for one of those slots (user 2026-07-27).
        'healSlots', 'healQueue',
        // NO 'xp' (user 2026-07-30: "Jedes Gebäude gibt genau gleich viel EP")
        // — one settlement-wide work rate in Species-Budget → XP, so a
        // per-building XP row is dropped on load instead of being authorable.
        'housing', 'breeding', 'hatching', 'queueSlots',
        'buildSlots', 'trade',
        // The Workshop's bench count and its queue (user 2026-07-30).
        'craftSlots', 'craftQueue',
        // Per-resource storage ceilings, and the two era-I stores.
        'storage',
      };
      expect(BuildingEffect.paletteTypes, authorable);
      // And each one really comes back out of fromDefRow.
      for (final t in authorable) {
        final def = BuildingDef.fromDefRow(
          _row([{'type': t, 'value': 1.0, 'era': 1}]),
        );
        expect(def.hasEffect(t, 1), isTrue, reason: '$t was dropped on load');
      }
    });
  });

  group('the per-level preview shows the runtime numbers', () {
    Future<void> pump(WidgetTester tester, Map<String, dynamic> effect,
        {int maxLevel = 8}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EffectsEditor(
              initialEffects: [effect],
              mode: EffectsMode.building,
              maxLevel: maxLevel,
              onChanged: (_) {},
            ),
          ),
        ),
      ));
    }

    testWidgets('production follows the +50%/level curve', (tester) async {
      await pump(tester, {'type': 'production', 'key': 'wood', 'value': 12.0});
      expect(find.text('12 wood/h'), findsOneWidget); // L1
      expect(find.text('30 wood/h'), findsOneWidget); // L4 = 12 × 2.5
      expect(find.text('54 wood/h'), findsOneWidget); // L8 = 12 × 4.5
      expect(find.text('L8'), findsOneWidget);
    });

    testWidgets('an authored per-level % overrides the default curve',
        (tester) async {
      await pump(tester, {
        'type': 'production',
        'key': 'wood',
        'value': 100.0,
        'levelFactor': 1.1, // +10%/level, compounding
      });
      expect(find.text('100 wood/h'), findsOneWidget); // L1
      expect(find.text('121 wood/h'), findsOneWidget); // L3 = 100 × 1.1²
    });

    testWidgets('a workshop shows slots and a fully-staffed hourly figure',
        (tester) async {
      await pump(tester, {
        'type': 'workshop',
        'stat': 'woodcutting',
        'resource': 'wood',
        'mult': 0.5,
        'slots': 6,
      });
      // L1: 6 slots × 0.5 × 1.0 × stat 30 = 90/h. L4: ×2.5 = 225/h.
      expect(find.text('90 wood/h'), findsOneWidget);
      expect(find.text('225 wood/h'), findsOneWidget);
    });

    testWidgets('the reference stat says WHICH stat it is', (tester) async {
      // User 2026-07-26: "Heildauer 30 — sind das nicht die Statpunkte?" The
      // box sits next to the row title, so unlabelled it read as the row's
      // value instead of the input behind it.
      await pump(tester, {
        'type': 'workshop',
        'stat': 'medicine',
        'resource': WorkshopRole.kHealSpeed,
        'mult': 0.005,
        'slots': 2,
      }, maxLevel: 1);
      expect(find.textContaining('at Medicine'), findsOneWidget);
    });

    testWidgets('the reference stat is editable and recomputes the line',
        (tester) async {
      // The shared lens must not leak into the tests that follow.
      addTearDown(() => debugSetPreviewStat(30));
      await pump(tester, {
        'type': 'workshop',
        'stat': 'woodcutting',
        'resource': 'wood',
        'mult': 0.5,
        'slots': 6,
      });
      await tester.enterText(find.byKey(const Key('previewStat')), '60');
      await tester.pump();
      expect(find.text('180 wood/h'), findsOneWidget); // L1 at stat 60
      expect(find.text('450 wood/h'), findsOneWidget); // L4
      expect(find.text('90 wood/h'), findsNothing); // the old lens is gone
    });

    testWidgets('a half-typed stat keeps the last usable value',
        (tester) async {
      addTearDown(() => debugSetPreviewStat(30));
      await pump(tester, {
        'type': 'workshop',
        'stat': 'woodcutting',
        'resource': 'wood',
        'mult': 0.5,
        'slots': 6,
      });
      await tester.enterText(find.byKey(const Key('previewStat')), '');
      await tester.pump();
      // Not 0 everywhere — clearing the box must not blank the whole preview.
      expect(find.text('90 wood/h'), findsOneWidget);
    });

    testWidgets('a flat type says so instead of inventing a curve',
        (tester) async {
      await pump(tester, {'type': 'resource', 'key': 'all', 'value': 0.2});
      // resource is read via effectEntry: same +20% on every level.
      expect(find.text('+20 %'), findsNWidgets(8));
      expect(
        find.textContaining('does NOT scale this type per level'),
        findsOneWidget,
      );
    });

    testWidgets('explicit level steps are summed, not multiplied',
        (tester) async {
      await pump(tester, {
        'type': 'housing',
        'value': 4,
        'levelSteps': {'2': 2, '5': 4},
      });
      expect(find.text('4 seats'), findsOneWidget); // L1
      expect(find.text('6 seats'), findsNWidgets(3)); // L2..L4
      expect(find.text('10 seats'), findsNWidgets(4)); // L5..L8
    });

    // The COUNT effects grew the same ladder on 2026-07-29 (user: "hier will
    // ich auch bei jedem level angeben können, wieviel dazukommen"). The
    // runtime already preferred levelSteps over the percent factor — this is
    // the preview agreeing with it, which is the half that was missing.
    testWidgets('an expedition-slot ladder is summed, not multiplied',
        (tester) async {
      // The numbers are chosen so nothing else on screen can match them: the
      // preview prints the LEVEL in its own column, and the editor now prints
      // every authored step in an input field. Only the SUMS (18 and 24) are
      // unique — the base 13 also sits in a field, so asserting it would pass
      // for the wrong reason.
      await pump(tester, {
        'type': 'expeditionSlots',
        'value': 13,
        'levelSteps': {'4': 5, '8': 6},
      });
      expect(find.text('18'), findsNWidgets(4)); // L4..L7 = 13 + 5
      expect(find.text('24'), findsOneWidget); // L8 = 13 + 5 + 6
    });

    // A workshop role whose output feeds a SYSTEM used to print the same
    // "N resource/h" line as a lumber camp (user 2026-07-26: "ich sehe nicht,
    // wie diese zusammenspielen"). Each of these now states the effect in the
    // unit the player feels, computed through the runtime's own formula.
    group('a system role states its real effect, not a fake hourly rate', () {
      // The Breeding Hut and the Hatchery are separate buildings on separate
      // clocks (user 2026-07-26) — a breeder post must NOT advertise the
      // incubation it has nothing to do with, and vice versa.
      Map<String, dynamic> post(String resource) => {
        'type': 'workshop',
        'stat': 'breeding',
        'resource': resource,
        'mult': 1.0,
        'slots': 2,
      };

      testWidgets('a breeder post shows the MATING duration only',
          (tester) async {
        addTearDown(() {
          debugSetPreviewRarity(CreatureRarity.rare);
          kSpeciesBalance = defaultSpeciesBalance();
        });
        // Distinct bases so a line from the wrong phase would be obvious.
        kSpeciesBalance = SpeciesBalance(
          byRarity: {
            for (final r in CreatureRarity.values)
              r: defaultSpeciesBalance()
                  .of(r)
                  .copyWith(breedHours: 8, hatchHours: 12),
          },
        );
        await pump(tester, post(WorkshopRole.kBreeding), maxLevel: 1);

        // Power = 2 slots × 1.0 × 1.0 × stat 30 = 60 = kBreedingK, the
        // half-time point.
        expect(find.text('60'), findsOneWidget);
        expect(find.text('−50 %'), findsOneWidget);
        expect(find.text('💞 Mating time'), findsOneWidget);
        expect(find.text('4h'), findsOneWidget); // 8h × 0.5
        expect(find.text('🐣 Incubation time'), findsNothing);
        expect(find.text('6h'), findsNothing); // the hatchery's 12h × 0.5
        // And no invented "60 breeding/h" line anywhere.
        expect(find.textContaining('breeding/h'), findsNothing);
      });

      testWidgets('a hatcher post shows the INCUBATION duration only',
          (tester) async {
        addTearDown(() {
          debugSetPreviewRarity(CreatureRarity.rare);
          kSpeciesBalance = defaultSpeciesBalance();
        });
        kSpeciesBalance = SpeciesBalance(
          byRarity: {
            for (final r in CreatureRarity.values)
              r: defaultSpeciesBalance()
                  .of(r)
                  .copyWith(breedHours: 8, hatchHours: 12),
          },
        );
        await pump(tester, post(WorkshopRole.kHatching), maxLevel: 1);
        expect(find.text('🐣 Incubation time'), findsOneWidget);
        expect(find.text('6h'), findsOneWidget); // 12h × 0.5
        expect(find.text('💞 Mating time'), findsNothing);
        expect(find.text('4h'), findsNothing);
      });

      testWidgets('the rarity lens picks which base duration is shown',
          (tester) async {
        addTearDown(() => debugSetPreviewRarity(CreatureRarity.rare));
        await pump(tester, post(WorkshopRole.kBreeding), maxLevel: 1);
        expect(find.text('32h'), findsOneWidget); // rare 64h × 0.5

        await tester.ensureVisible(find.byKey(const Key('previewRarity')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('previewRarity')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Epic').last);
        await tester.pumpAndSettle();
        expect(find.text('2.7d'), findsOneWidget); // epic 128h × 0.5 = 64h
      });

      testWidgets('the level factor is spelled out, not left implicit',
          (tester) async {
        // The confusion it exists for (user 2026-07-26): 2 slots × mult 2 ×
        // stat 70 reads as 280 at L2, but the game also applies the default
        // +50 %/level to each worker's output — so it is 420.
        addTearDown(() => debugSetPreviewStat(30));
        await pump(tester, {
          'type': 'workshop',
          'stat': 'breeding',
          'resource': WorkshopRole.kBreeding,
          'mult': 2.0,
          'slots': 1,
          'slotSteps': {'2': 1},
        }, maxLevel: 2);
        await tester.enterText(find.byKey(const Key('previewStat')), '70');
        await tester.pump();
        expect(find.text('×1.5'), findsOneWidget); // L2 on the default curve
        expect(find.text('140'), findsOneWidget); // L1: 1 × 2 × 70
        expect(find.text('420'), findsOneWidget); // L2: 2 × 2 × 70 × 1.5
      });

      testWidgets('an authored 0 %/level makes the factor flat',
          (tester) async {
        addTearDown(() => debugSetPreviewStat(30));
        await pump(tester, {
          'type': 'workshop',
          'stat': 'breeding',
          'resource': WorkshopRole.kBreeding,
          'mult': 2.0,
          'slots': 1,
          'slotSteps': {'2': 1},
          'levelFactor': 1.0, // "Growth per level (%)" = 0
        }, maxLevel: 2);
        await tester.enterText(find.byKey(const Key('previewStat')), '70');
        await tester.pump();
        expect(find.text('×1'), findsNWidgets(2)); // flat on every level
        expect(find.text('280'), findsOneWidget); // L2: slots only
        expect(find.text('420'), findsNothing);
      });

      testWidgets('a healer post shows the healing-time cut', (tester) async {
        await pump(tester, {
          'type': 'workshop',
          'stat': 'medicine',
          'resource': WorkshopRole.kHealSpeed,
          'mult': 0.005,
          'slots': 2,
        }, maxLevel: 1);
        // 2 × 0.005 × 30 = 0.30 → −30% treatment time.
        expect(find.text('−30 %'), findsOneWidget);
      });

      testWidgets('a trader post shows the spread cut, capped', (tester) async {
        await pump(tester, {
          'type': 'workshop',
          'stat': 'trade',
          'resource': WorkshopRole.kTradeRate,
          'mult': 0.05, // 2 × 0.05 × 30 = 3.0, far past the 60% ceiling
          'slots': 2,
        }, maxLevel: 1);
        expect(find.text('−60 %'), findsOneWidget);
      });

      testWidgets('a warehouse post shows the carry bonus', (tester) async {
        await pump(tester, {
          'type': 'workshop',
          'stat': 'carry',
          'resource': WorkshopRole.kExpCarry,
          'mult': 0.004,
          'slots': 2,
        }, maxLevel: 1);
        // 2 × 0.004 × 30 = 0.24 → +24% load.
        expect(find.text('+24 %'), findsOneWidget);
      });

      testWidgets('a combined scout post previews all three dials apart',
          (tester) async {
        // User 2026-07-29: "exp carry capacity, exp goods und exp speed in
        // einem Effekt … welchen ich aber separat einstellen kann". One row,
        // three lines — each read from ITS own dial, so a preview that folded
        // them into one number would defeat the point of splitting them.
        await pump(tester, {
          'type': 'workshop',
          'stat': 'speed',
          'resource': WorkshopRole.kExpedition,
          'slots': 2,
          'mults': {'carry': 0.004, 'goods': 0.002, 'travel': 0.025},
        }, maxLevel: 1);
        expect(find.text('+24 %'), findsOneWidget); // 2 × 0.004 × 30 = 0.24
        expect(find.text('+12 %'), findsOneWidget); // 2 × 0.002 × 30 = 0.12
        // travel: 2 × 0.025 × 30 = 1.5 → 1.5/(1+1.5) = −60 %, uncapped shape.
        expect(find.text('−60 %'), findsOneWidget);
      });

      testWidgets('a builder post states the build-time CUT, not a factor',
          (tester) async {
        // User 2026-07-26: "nicht Bau-Tempo Beschleuniger, sondern um wieviel
        // Prozent wird die Bauzeit reduziert, wie bei anderen Menüs auch".
        await pump(tester, {
          'type': 'workshop',
          'stat': 'construction',
          'resource': WorkshopRole.kConstruction,
          'mult': 1.0,
          'slots': 2,
        }, maxLevel: 1);
        // 2 slots × mult 1 × stat 30 = 60 points, and points buy a percentage
        // off the authored time: 60/(60+100) = −37.5 %.
        expect(find.text('60'), findsOneWidget);
        expect(find.text('−37.5 %'), findsOneWidget);
        expect(find.textContaining('×3'), findsNothing);
      });

      testWidgets('a weak builder post still CUTS — it can never add time',
          (tester) async {
        // User 2026-07-26: points are a cut off the authored time, so the
        // authored time is the ceiling. The preview used to print "+233 %" for
        // a post below the old 20-point anchor; there is no anchor anymore.
        await pump(tester, {
          'type': 'workshop',
          'stat': 'construction',
          'resource': WorkshopRole.kConstruction,
          'mult': 0.1,
          'slots': 2,
        }, maxLevel: 1);
        // 2 × 0.1 × 30 = 6 points → 6/106.
        expect(find.text('−5.7 %'), findsOneWidget);
        expect(find.text('+233 %'), findsNothing);
      });

      testWidgets('the builder mult COUNTS — it used to be inert',
          (tester) async {
        // User 2026-07-26: "Bau-Punkte soll eine Wirkung haben, da ich dies
        // beim Hauptgebäude einfügen will". The runtime ignored both mult and
        // the building level for construction; now neither is a special case.
        await pump(tester, {
          'type': 'workshop',
          'stat': 'construction',
          'resource': WorkshopRole.kConstruction,
          'mult': 0.4,
          'slots': 2,
        }, maxLevel: 2);
        expect(find.text('24'), findsOneWidget); // L1: 2 × 0.4 × stat 30
        expect(find.text('36'), findsOneWidget); // L2: ×1.5 level curve
        expect(find.text('−19.4 %'), findsOneWidget); // L1: 24/(24+100)
        expect(find.text('−26.5 %'), findsOneWidget); // L2: 36/(36+100)
      });

      testWidgets('a legendary slot says the level does not scale it',
          (tester) async {
        await pump(tester, {
          'type': 'workshop',
          'stat': 'production',
          'resource': WorkshopRole.kLegendaryBoost,
          'mult': 0.25,
          'slots': 2,
        }, maxLevel: 4);
        // 2 slots × 25%, identical on every level.
        expect(find.text('+50 %'), findsNWidgets(4));
        expect(find.textContaining('does NOT grow'), findsOneWidget);
      });
    });

    testWidgets('passive construction is points, not units per hour',
        (tester) async {
      // User 2026-07-26: "das soll die passive Construction sein … wie wenn ein
      // Monster mit dieser Stufe dort arbeiten würde" — so a building's own
      // points and a stationed builder's land in the same pot, 1:1, and read
      // out as the same percentage off the build time.
      await pump(tester, {
        'type': 'production',
        'key': WorkshopRole.kConstruction,
        'value': 20.0,
      }, maxLevel: 3);
      expect(find.text('20 points'), findsOneWidget); // L1 — not "20 /h"
      expect(find.text('−16.7 %'), findsOneWidget); // 20/(20+100)
      // L3 on the default +50 %/level curve: 40 points.
      expect(find.text('40 points'), findsOneWidget);
      expect(find.text('−28.6 %'), findsOneWidget); // 40/(40+100)
      expect(find.textContaining('count exactly the same'), findsOneWidget);
    });

    testWidgets('a work post states the XP it pays, and that it is global',
        (tester) async {
      // The rate is not editable per building any more (user 2026-07-30), so
      // the preview is where the author reads it off — and it must say WHERE the
      // one number lives, or the missing field looks like a bug.
      await pump(tester, {
        'type': 'workshop',
        'stat': 'production',
        'resource': 'wood',
        'mult': 2.0,
        'slots': 1,
      }, maxLevel: 1);
      expect(
        find.text('${kXpBalance.workXpAt(1).round()} XP/h'),
        findsOneWidget,
      );
      expect(find.textContaining('EVERY building with a work post'),
          findsOneWidget);
    });

    testWidgets('a STORE post gets one dial and one preview line per resource',
        (tester) async {
      // User 2026-07-30: "Ich muss den output pro worker für jede Ressource
      // einzeln einstellen können." The keys come from the building's OWN
      // storage effects, so the form cannot offer a dial for something the
      // store does not hold — nor miss one it does.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EffectsEditor(
              initialEffects: [
                {
                  'type': 'workshop',
                  'stat': 'logistics',
                  'resource': WorkshopRole.kStorageRoom,
                  'mult': 10.0,
                  'mults': {'wood': 10.0, 'fish': 4.0},
                  'slots': 1,
                },
                {'type': 'storage', 'key': 'wood', 'value': 500.0, 'era': 1},
                {'type': 'storage', 'key': 'fish', 'value': 500.0, 'era': 1},
              ],
              mode: EffectsMode.building,
              maxLevel: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      ));
      // One editable dial per stored resource…
      expect(find.textContaining('Room per stat point · wood'), findsOneWidget);
      expect(find.textContaining('Room per stat point · Fish'), findsOneWidget);
      // …and no single flat field pretending to cover both.
      expect(find.textContaining('Output per stat point /h'), findsNothing);
      // The preview reads each resource's OWN dial: 1 slot × dial × ref stat 30.
      expect(find.text('+300 room'), findsOneWidget); // wood: 10 × 30
      expect(find.text('+120 room'), findsOneWidget); // fish: 4 × 30
    });
  });
}
