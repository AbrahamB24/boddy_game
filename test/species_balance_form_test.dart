import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/dev/species_balance_form.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/heal_balance.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';

// The Species-Budget screen's two answering tabs (user 2026-07-26). Both exist
// because a raw config number told the author nothing on its own:
//
//  * Breeding: "ich gebe eine Zeit an und du zeigst mir die benötigte Power" —
//    the screen has to invert the soft-cap curve, not just store hours.
//  * XP: a factor and an exponent are meaningless until the screen says how
//    many XP and how many hours they cost per level.
/// A tall viewport, because these tabs are lists: the assertions are about
/// rows for EVERY rarity / era, and a 600px surface would only ever build the
/// first one.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: SpeciesBalanceForm()));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    kSpeciesBalance = defaultSpeciesBalance();
    kXpBalance = const XpConfig();
    kHealBalance = const HealConfig();
  });

  group('Heilung tab', () {
    testWidgets('every rarity gets its own two prices', (tester) async {
      await _pump(tester);
      await _openTab(tester, '🩹 Heilung');
      expect(find.text('Seconds per HP'), findsNWidgets(5));
      expect(find.text('Goods per HP'), findsNWidgets(5));
    });

    testWidgets('each rarity states what a real wound costs', (tester) async {
      await _pump(tester);
      await _openTab(tester, '🩹 Heilung');
      // Common at 60 max-HP: a −55 % trial is 33 HP × 25 s ≈ 13.8 min and
      // 33 × 0.2 = 6.6 goods; a K.O. is 60 × 25 × 2 = 50 min and 24 goods.
      expect(find.text('14m · 6.6 goods'), findsOneWidget);
      expect(find.text('50m · 24.0 goods'), findsOneWidget);
      // Legendary is the slow AND dear end: 33 × 75 s ≈ 41 min, 33 × 0.4.
      expect(find.text('41m · 13.2 goods'), findsOneWidget);
    });

    testWidgets('editing one rarity leaves the others alone', (tester) async {
      await _pump(tester);
      await _openTab(tester, '🩹 Heilung');
      await tester.enterText(
          find.byKey(const ValueKey('healgoods-common-0')), '1');
      await tester.pump();
      expect(find.text('14m · 33.0 goods'), findsOneWidget); // common
      expect(find.text('41m · 13.2 goods'), findsOneWidget); // legendary intact
    });

    testWidgets('it names the goods of EVERY era, not just the current one',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, '🩹 Heilung');
      // The rule the list exists for.
      expect(find.textContaining("MONSTER's era"), findsOneWidget);
      // Era 1 has exactly the two starter supplies; era 2 adds its own.
      expect(find.textContaining('Era 1: 🐟 Fish · 🦫 Fur'), findsOneWidget);
      expect(find.textContaining('Era 2: 🐟 Fish · 🦫 Fur · '), findsOneWidget);
    });
  });

  group('Breeding tab: a wished-for duration answers with a power', () {
    testWidgets('both phases are authorable per rarity', (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Breeding');
      expect(find.text('💞 Mating'), findsNWidgets(4)); // legendary excluded
      expect(find.text('🐣 Incubation'), findsNWidgets(4));
      expect(find.text('— cannot be bred —'), findsOneWidget);
    });

    testWidgets('the price of a mating is authorable per rarity',
        (tester) async {
      // Breeding costs supplies since 2026-07-27, and the number has to be
      // tunable where its duration is — otherwise the only way to rebalance it
      // is a code change.
      await _pump(tester);
      await _openTab(tester, 'Breeding');
      final field = find.byKey(const ValueKey('breedgoods-rare-0'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '42');
      await tester.pump();
      expect(kSpeciesBalance.of(CreatureRarity.rare).breedGoods, isNot(42),
          reason: 'not applied until saved');
      expect(find.text('Supplies per mating'), findsNWidgets(4));
    });

    testWidgets('a target time is turned into the required power',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Breeding');
      // Rare mates in 64h by default; 32h is the half-time point, reached at
      // exactly kBreedingK (60).
      final field = find.byKey(const ValueKey('target-breed-rare-0'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '32');
      await tester.pump();
      expect(find.text('power needed: 60'), findsOneWidget);
    });

    testWidgets('past the old −50 % wall it quotes a price, not "impossible"',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Breeding');
      final field = find.byKey(const ValueKey('target-breed-rare-0'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '16'); // 64h → 16h: a −75 % cut
      await tester.pump();
      expect(find.text('power needed: 180'), findsOneWidget);
    });

    testWidgets('only a zero duration has no answer', (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Breeding');
      final field = find.byKey(const ValueKey('target-breed-rare-0'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '0');
      await tester.pump();
      expect(find.text('power needed: impossible'), findsOneWidget);
    });

    testWidgets('the power→speed-up ruler is shown up front', (tester) async {
      await _pump(tester);
      await _openTab(tester, 'Breeding');
      // −75% costs power 180: 60 · 0.75/0.25.
      expect(find.text('−75 %'), findsOneWidget);
      expect(find.text('180'), findsOneWidget);
    });
  });

  group('XP tab', () {
    testWidgets('the curve is stated in XP and in hours', (tester) async {
      await _pump(tester);
      await _openTab(tester, '⭐ XP');
      expect(find.text('6'), findsOneWidget); // L1 = 6 · 1^2.5
      // 6 · 10^2.5 = 1897 XP; at the 250 XP/h training rate ≈ 7.6h.
      expect(find.text('1897'), findsOneWidget);
      expect(find.text('7.6h'), findsOneWidget);
    });

    testWidgets('editing the curve recomputes the preview', (tester) async {
      await _pump(tester);
      await _openTab(tester, '⭐ XP');
      await tester.enterText(find.byKey(const ValueKey('xp-exponent-0')), '2');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('xp-factor-0')), '10');
      await tester.pump();
      expect(find.text('1000'), findsOneWidget); // 10 · 10²
    });

    testWidgets('a defeated monster is priced by its level', (tester) async {
      // User 2026-07-26: "wieviel xp besiegte Monster geben nach Stufe".
      await _pump(tester);
      await _openTab(tester, '⭐ XP');
      expect(find.text('9'), findsOneWidget); // L1 = 9 · 1^1.3
      expect(find.text('180'), findsOneWidget); // L10 = 9 · 10^1.3
      expect(find.text('539'), findsOneWidget); // the same L10 as a boss (×3)
    });

    testWidgets('editing the kill reward recomputes the levelling pace',
        (tester) async {
      await _pump(tester);
      await _openTab(tester, '⭐ XP');
      await tester.enterText(
          find.byKey(const ValueKey('xp-kill-factor-0')), '1');
      await tester.enterText(
          find.byKey(const ValueKey('xp-kill-exponent-0')), '1');
      await tester.pump();
      // L10 kill = 10 XP against a 1897 XP level → 190 wins.
      expect(find.text('190×'), findsOneWidget);
    });

    testWidgets('the deleted dials are gone from the tab', (tester) async {
      await _pump(tester);
      await _openTab(tester, '⭐ XP');
      // The per-era catch-up multiplier stays deleted. The old passive floor's
      // successor is NOT the same dial: it is a rate every work post pays, not
      // a floor under every stationed monster — see the next test.
      expect(find.text('Base per era'), findsNothing);
    });

    testWidgets('work XP is one rate, previewed per BUILDING level',
        (tester) async {
      // User 2026-07-30: "Jedes Gebäude, welches Monster «anstellt» soll EP
      // geben. Jedes Gebäude gibt genau gleich viel EP" — so this tab is the
      // only place the number lives, and it must read back in the unit that
      // moves it: the building's level, not the monster's.
      await _pump(tester);
      await _openTab(tester, '⭐ XP');
      expect(find.text('Arbeit (XP/h, Gebäude Lv 1)'), findsOneWidget);
      expect(find.text('Geb. L1'), findsOneWidget);
      // The default rate at Lv 1 — in the field AND in the first chip.
      expect(find.text('10.0'), findsAtLeastNWidgets(1));
      // Raising the rate moves the preview — and the growth stays weak.
      await tester.enterText(find.byKey(const ValueKey('xp-work-0')), '20');
      await tester.pump();
      expect(find.text('20.0'), findsOneWidget);
      expect(find.text('Geb. L24'), findsOneWidget);
    });
  });
}
