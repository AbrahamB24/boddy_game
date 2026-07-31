import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/widgets/creature_backdrop.dart';
import 'package:boddygame/features/creatures/widgets/battle_scene.dart';

// ── Der Kampfplatz statt der Typ-Kachel (user 2026-07-31) ───
// "Jetzt kann der Hintergrund nicht mehr der Typ sein, da es mehrere haben kann.
//  Welche Lösung gibt es?"
//
// The background answers WHERE, the podium under each monster answers WHAT — so
// a rank of three types is fully described, which the half-wide element tile
// could never manage. The risk in a scene is the day it has no art: "no image
// yet" must look finished, never broken.
void main() {
  testWidgets('a region with no art borrows the overworld ground',
      (tester) async {
    // User 2026-07-31: "nimm den Hintergrund von der Overworld vorerst als
    // Hintergrund für den Kampfscreen" — the trail you walked in on, under the
    // fight it led to.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BattleScene(era: 3))),
    );
    await tester.pump();
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<AssetImage>());
    expect((img.image as AssetImage).assetName, kOverworldGroundAsset);
    // And the era palette stays under it as the last resort.
    expect(find.byType(BattleScene), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a region WITH art uses it instead of the stand-in',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BattleScene(imageUrl: 'https://example.test/x.png', era: 2),
        ),
      ),
    );
    await tester.pump();
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<NetworkImage>(),
        reason: 'the region overrides the borrowed ground');
  });

  test('every era has its own palette, and none of them crash', () {
    final seen = <List<Color>>[];
    for (var era = 1; era <= 8; era++) {
      final p = BattleScene.paletteFor(era);
      expect(p, hasLength(2));
      seen.add(p);
    }
    // Eight chapters, eight different worlds — a shared palette would make the
    // fallback look like a bug rather than a place.
    expect(seen.map((p) => p.first.toARGB32()).toSet(), hasLength(8));
  });

  test('an era beyond the painted ones falls back instead of throwing', () {
    // Era count is content and grows; the palette is code and will lag behind.
    expect(BattleScene.paletteFor(99), BattleScene.paletteFor(8));
    expect(BattleScene.paletteFor(0), BattleScene.paletteFor(1));
    expect(BattleScene.paletteFor(-3), BattleScene.paletteFor(1));
  });

  testWidgets('the type platform renders per monster, not per side',
      (tester) async {
    // Three platforms, three types — the thing the old shared tile could not do,
    // and the reason the type had to leave the background at all.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TypePodium(element: CreatureElement.fire, width: 60),
              TypePodium(element: CreatureElement.water, width: 60),
              TypePodium(
                  element: CreatureElement.plant, width: 60, dim: true),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(TypePodium), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the platform IS the monster card surface', (tester) async {
    // User 2026-07-31: "Die Farbe soll genau so sein wie der Hintergrund der
    // Monstercard". Pinned as the widget, not as a colour: hand-mixing the same
    // gradient here is exactly how the two would drift apart the first time the
    // card changed.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TypePodium(element: CreatureElement.fire, width: 60),
        ),
      ),
    );
    final backdrop = tester.widget<CreatureBackdrop>(
      find.byType(CreatureBackdrop),
    );
    expect(backdrop.element, CreatureElement.fire);
    expect(backdrop.baseColor, isNull,
        reason: 'no override — the element decides, exactly as on the card');
    // The type glyph is embossed INTO the surface (watermarkLeft, so the
    // monster does not stand on its own symbol).
    expect(backdrop.watermarkLeft, isTrue);
  });

  test('an area carries its own battlefield art through the DB row', () {
    const area = AreaDef(
      id: 'verdant_hollow',
      name: 'Verdant Hollow',
      emoji: '🌲',
      imageUrl: 'https://example.test/area_verdant_hollow.png',
      order: 1,
      battleStage: 1,
    );
    final row = area.toDefRow();
    expect(row['image_url'], 'https://example.test/area_verdant_hollow.png');
    expect(AreaDef.fromDefRow(row).imageUrl, area.imageUrl);
    // And a row written before the column existed simply has none.
    expect(AreaDef.fromDefRow({'id': 'x'}).imageUrl, isNull);
  });

  // ── Der HP-Balken ist der Rand (user 2026-07-31) ────────────
  // "der hp balken wird zum Rand der Plattform, wobei dieser ein Halbkreis
  //  bleibt"
  //
  // A gauge painted on a shape that is already there costs no space on a field
  // holding six monsters. What has to hold: it is the FRONT half only (a full
  // ring would have no empty end to read against), and a platform with nobody on
  // it is still a platform.
  group('the platform rim', () {
    testWidgets('an empty platform paints no gauge and does not crash',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TypePodium(element: CreatureElement.fire, width: 60),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every level of health paints, including the extremes',
        (tester) async {
      for (final hp in [0.0, 0.001, 0.5, 0.999, 1.0, -1.0, 2.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TypePodium(
                element: CreatureElement.water,
                width: 60,
                hpFraction: hp,
                hpColor: Colors.red,
              ),
            ),
          ),
        );
        // Out-of-range values are clamped rather than drawn as a rim that wraps
        // past its own end — a negative sweep would paint the gauge backwards.
        expect(tester.takeException(), isNull, reason: 'hp $hp');
      }
    });
  });
}
