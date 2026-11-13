import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/avatar/player_portrait.dart';
import 'package:boddygame/features/avatar/portrait_picker_screen.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';

// A player's picture is a monster portrait from the bestiary (user 2026-11-13).
SpeciesDef species(String id, String name) => SpeciesDef(
  id: id,
  name: name,
  element: CreatureElement.fire,
  rarity: CreatureRarity.common,
  stats: {
    for (final s in CreatureStat.values)
      s: const StatCurve(stageBase: [20, 24, 28], growth: 1),
  },
  stages: [
    for (var i = 0; i < 3; i++)
      SpeciesStage(
        name: '$name $i',
        imageUrl: 'https://x.supabase.co/storage/v1/object/public/creature-images/${id}_$i.png',
      ),
  ],
);

void main() {
  setUp(() {
    kSpeciesDefs['blazeling'] = species('blazeling', 'Cinderchick');
    kSpeciesDefs['droplet'] = species('droplet', 'Quackling');
  });
  tearDown(() {
    kSpeciesDefs.remove('blazeling');
    kSpeciesDefs.remove('droplet');
  });

  test('PortraitRef round-trips and rejects what it does not know', () {
    const id = 'blazeling';
    expect(PortraitRef.parse('$id:1'), PortraitRef(id, 1));
    expect(PortraitRef(id, 2).code, '$id:2');
    expect(PortraitRef.parse('nonsense:1'), isNull);
    expect(PortraitRef.parse('$id:7'), isNull);
    expect(PortraitRef.parse('$id:x'), isNull);
    expect(PortraitRef.parse(null), isNull);
    expect(PortraitRef.parse(12), isNull);
    expect(PortraitRef(id, 0).imageUrl, isNotNull);
  });

  testWidgets('the picker offers the stages the bestiary has seen', (t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const ids = ['blazeling', 'droplet'];
    CreatureInstance mon(String id, String sp, int stage) => CreatureInstance(
      id: id,
      userId: 'u',
      speciesId: sp,
      gender: CreatureGender.male,
      statBase: const {},
      statSlope: const {},
      stage: stage,
    );
    // Species A reached stage 2 (three portraits), species B only stage 0.
    CreaturesController().creatures = [
      mon('a', ids[0], 2),
      mon('b', ids[1], 0),
    ];
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: PortraitPickerScreen(start: PortraitRef(ids[0], 1)),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    // 3 stages of A + 1 of B, each in a grid tile (plus the big preview).
    expect(find.byType(PortraitView), findsNWidgets(3 + 1 + 1));
    final out = Platform.environment['PORTRAIT_SHOT'];
    if (out != null) {
      await t.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage();
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File(out).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }
  });
}
