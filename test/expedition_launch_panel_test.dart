import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/common/widgets/parchment_kit.dart';
import 'package:boddygame/features/creatures/expedition_launch_sheet.dart';
import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/creatures/services/expedition_targets.dart';

// Regression for the reported "RenderFlex overflowed… Column <- ExpeditionLaunchPanel"
// AND for the user's explicit follow-up (2026-10-02: "es sollte alles auf einem Screen
// ohne scrollen sichtbar sein") — a SHORT SLOT (the composer's Expanded panel area)
// must show everything, Send button included, with no scrolling at all. The body
// used to be a SingleChildScrollView; it's a FittedBox-scaled column now (see
// ExpeditionLaunchPanel._body's own doc comment), so there must be no scrollable in
// it any more, and the Send bar must actually be laid out (not pushed past the fold).
void main() {
  final species = SpeciesDef(
    id: 's',
    name: 'Mouse',
    element: CreatureElement.fire,
    rarity: CreatureRarity.common,
    catchRate: 1,
    stats: const {},
    stages: const [
      SpeciesStage(name: 's'),
      SpeciesStage(name: 's'),
      SpeciesStage(name: 's'),
    ],
  );

  CreatureInstance monster(String id) => CreatureInstance(
    id: id,
    userId: 'u',
    speciesId: 's',
    gender: CreatureGender.male,
    statBase: {CreatureStat.hp: 40},
    statSlope: const {},
    currentHp: 40,
  );

  setUp(() => kSpeciesDefs['s'] = species);
  tearDown(() => kSpeciesDefs.remove('s'));

  Future<void> mount(WidgetTester t, double height, {int? optionIndex}) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    CreaturesController().creatures = [
      for (var i = 0; i < 24; i++) monster('m$i'),
    ];
    const target = ExpeditionTarget(
      kind: ExpeditionTargetKind.hunt,
      area: AreaDef(
        id: 'a1',
        name: 'Test Wood',
        emoji: '🌲',
        order: 1,
        battleStage: 1,
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: height,
              child: ExpeditionLaunchPanel(
                target: target,
                initialOptionIndex: optionIndex,
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('inline hunt panel fits a short slot with no scrolling', (
    t,
  ) async {
    await mount(t, 240);
    expect(t.takeException(), isNull);
    // The real hunt body is up, not the "No species" placeholder.
    expect(find.text('LENGTH'), findsOneWidget);
    // Scaled to fit, not scrolled — there must be nothing scrollable to miss.
    expect(find.byType(SingleChildScrollView), findsNothing);
    // The Send bar is actually laid out within the slot, not pushed off it
    // (the slot itself is centred in a taller test viewport, so the bound is
    // the slot's own bottom edge, not an absolute pixel count).
    expect(find.byType(ParchmentButton), findsOneWidget);
    final slot = t.getRect(find.byType(ExpeditionLaunchPanel));
    expect(
      t.getRect(find.byType(ParchmentButton)).bottom,
      lessThanOrEqualTo(slot.bottom),
    );
  });

  testWidgets(
    'the longest hunt (5 group slots) still fits a short slot with no '
    'scrolling',
    (t) async {
      // kCaptureHuntOptions[4] = 10.000 Schritte, groupCap 5 — the tallest
      // group grid this panel ever has to show.
      await mount(t, 240, optionIndex: 4);
      expect(t.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ParchmentButton), findsOneWidget);
      final slot = t.getRect(find.byType(ExpeditionLaunchPanel));
      expect(
        t.getRect(find.byType(ParchmentButton)).bottom,
        lessThanOrEqualTo(slot.bottom),
      );
    },
  );
}
