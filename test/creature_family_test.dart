import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/widgets/battle_scene.dart'
    show TypePodium;
import 'package:boddygame/features/creatures/widgets/creature_family.dart';

// The monster family (user 2026-09-20: "Monsterkacheln müssen vereinheitlicht
// werden" → "Variante 1, aber die HP Balken sind bei allen wie bei der Kachel"
// and "Nimm die Sockelkachel für den Kampf", then 2026-09-21: "nimm für die ganz
// kleinen Monsterkacheln (Chip) die Sockel"): one small podium (the Sockel) for
// every small monster, the foot for the big tile.
void main() {
  CreatureFace face({
    double hp = 1,
    CreatureElement el = CreatureElement.fire,
  }) => CreatureFace(imageUrl: null, element: el, hp: hp);

  Future<void> show(WidgetTester t, Widget w) => t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: w)),
    ),
  );

  group('CreatureAvatar (the small monster, everywhere)', () {
    testWidgets('is exactly the size it is given', (t) async {
      await show(t, CreatureAvatar(face(), size: 36));
      expect(t.getSize(find.byType(CreatureAvatar)), const Size(36, 36));
    });

    testWidgets('is the Sockel: the monster on its podium, HP as the rim', (
      t,
    ) async {
      await show(t, CreatureAvatar(face(hp: 0.2), size: 44));
      final podium = t.widget<TypePodium>(find.byType(TypePodium));
      expect(podium.hpFraction, 0.2);
      expect(podium.element, CreatureElement.fire);
      // Coral for a monster about to go down, not the healthy colour.
      expect(creatureHpColor(0.2), isNot(creatureHpColor(0.9)));
      expect(creatureHpColor(0.2), isNot(creatureHpColor(0.5)));
    });

    testWidgets(
      'showHp: false leaves the rim bare (a hauler, a breeding parent)',
      (t) async {
        await show(t, CreatureAvatar(face(), size: 44, showHp: false));
        expect(
          t.widget<TypePodium>(find.byType(TypePodium)).hpFraction,
          isNull,
        );
      },
    );

    testWidgets('a knocked-out monster says so from 40 px, not on a tiny one', (
      t,
    ) async {
      await show(t, CreatureAvatar(face(hp: 0), size: 44));
      expect(find.text('K.O.'), findsOneWidget);
      await show(t, CreatureAvatar(face(hp: 0), size: 30));
      expect(find.text('K.O.'), findsNothing);
    });
  });
  group('SockelAvatar (the battle)', () {
    testWidgets('stands on the arena podium with its HP as the rim', (t) async {
      await show(t, SockelAvatar(face(hp: 0.5), size: 34));
      final podium = t.widget<TypePodium>(find.byType(TypePodium));
      expect(podium.hpFraction, 0.5);
      expect(podium.element, CreatureElement.fire);
      // Thin on a small monster, so a rim stays a rim.
      expect(podium.gauge, lessThan(5));
    });

    testWidgets('takes the battle\'s own colour scale for the rim', (t) async {
      const mine = Color(0xFF123456);
      await show(
        t,
        SockelAvatar(face(hp: 0.5), size: 34, hpColor: (_) => mine),
      );
      expect(t.widget<TypePodium>(find.byType(TypePodium)).hpColor, mine);
    });

    testWidgets(
      'the small monster has no half-sphere; only the arena adds it',
      (t) async {
        await show(t, SockelAvatar(face(), size: 34));
        expect(t.widget<TypePodium>(find.byType(TypePodium)).bowl, isFalse);
        await show(
          t,
          const SizedBox(
            width: 200,
            child: TypePodium(
              element: CreatureElement.fire,
              width: 180,
              hpFraction: 0.6,
              bowl: true,
            ),
          ),
        );
        expect(t.widget<TypePodium>(find.byType(TypePodium)).bowl, isTrue);
        expect(t.takeException(), isNull);
      },
    );
  });
}
