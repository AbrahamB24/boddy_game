import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/widgets/creature_sprite.dart';
import 'package:boddygame/features/creatures/widgets/monster_sheet.dart';

// The baked 3D monsters (tool/blender/monster_anim_pro.py) are played from
// WebP sheets. What is pinned: the registry hands out art only to species that
// have it, every sheet it names is really bundled and decodable, and the
// player runs without throwing and advances its frame.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('only species with baked art get a sheet set', () {
    expect(MonsterSheets.battle('tidelord', 0, back: false), isNotNull);
    expect(MonsterSheets.battle('tidelord', 0, back: true), isNotNull);
    expect(MonsterSheets.battle('tidelord', 3, back: false), isNull);
    expect(MonsterSheets.battle('somebody_else', 0, back: false), isNull);
    expect(MonsterSheets.battle(null, 0, back: false), isNull);
    for (var stage = 0; stage < 3; stage++) {
      for (final h in ['se', 'ne', 'nw', 'sw']) {
        expect(
          MonsterSheets.map('tidelord', stage, h),
          isNotNull,
          reason: '$stage $h',
        );
      }
    }
    expect(MonsterSheets.map('tidelord', 3, 'se'), isNull);
    expect(MonsterSheets.map('tidelord', 0, 'up'), isNull);
  });

  test('every animation names a bundled sheet with a sane frame count', () {
    final sets = <MonsterSheetSet>[
      MonsterSheets.battle('tidelord', 0, back: false)!,
      MonsterSheets.battle('tidelord', 0, back: true)!,
      for (var stage = 0; stage < 3; stage++)
        for (final mine in [true, false])
          MonsterSheets.battleSide('tidelord', stage, mine: mine)!,
      for (var stage = 0; stage < 3; stage++)
        for (final h in ['se', 'ne', 'nw', 'sw'])
          MonsterSheets.map('tidelord', stage, h)!,
    ];
    for (final s in sets) {
      for (final a in s.anims.values) {
        expect(File(a.asset).existsSync(), isTrue, reason: a.asset);
        expect(a.frames, inInclusiveRange(2, 32));
        expect(a.fps, inInclusiveRange(4, 30));
        expect(
          (a.frames + s.cols - 1) ~/ s.cols,
          lessThanOrEqualTo(4),
          reason: '${a.asset} would need an absurd sheet height',
        );
      }
    }
  });

  testWidgets('the player decodes its sheet and keeps animating', (t) async {
    final set = MonsterSheets.battle('tidelord', 0, back: false)!;
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: MonsterSheetPlayer(set: set, height: 200),
        ),
      ),
    );
    // The WebP is decoded by the real codec, which needs real time.
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(MonsterSheetPlayer), findsOneWidget);
    expect(t.takeException(), isNull);

    // Switching animation restarts cleanly, and an unknown name falls back.
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: MonsterSheetPlayer(set: set, anim: 'attack', height: 200),
        ),
      ),
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpWidget(
      MaterialApp(
        home: Center(
          child: MonsterSheetPlayer(set: set, anim: 'nope', height: 200),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
  });

  test('a species picture URL finds its baked art, anything else does not', () {
    const base = 'https://x.supabase.co/storage/v1/object/public/creature-images';
    final front = MonsterSheets.forUrl('$base/tidelord_0.png?v=123');
    final back = MonsterSheets.forUrl('$base/tidelord_0_back.png?v=9');
    expect(front, isNotNull);
    expect(front!.back, isFalse);
    expect(back, isNotNull);
    expect(back!.back, isTrue);
    expect(MonsterSheets.forUrl('$base/tidelord_1.png'), isNotNull);
    expect(MonsterSheets.forUrl('$base/tidelord_2_back.png')!.back, isTrue);
    expect(MonsterSheets.battle('tidelord', 2, back: false)!.scale,
        greaterThan(MonsterSheets.battle('tidelord', 1, back: false)!.scale));
    expect(MonsterSheets.battle('tidelord', 3, back: false), isNull);
    expect(MonsterSheets.forUrl('$base/glimmergnaw_0.png'), isNull);
    expect(MonsterSheets.forUrl(null), isNull);
  });

  testWidgets('CreatureSprite draws baked art for a Tidelord URL', (t) async {
    const url =
        'https://x.supabase.co/storage/v1/object/public/creature-images/tidelord_0.png';
    await t.pumpWidget(
      const MaterialApp(
        home: Center(child: CreatureSprite(url: url, width: 160, height: 160)),
      ),
    );
    expect(find.byType(MonsterSheetPlayer), findsOneWidget);
    // big enough to idle; a thumbnail holds still
    expect(
      t.widget<MonsterSheetPlayer>(find.byType(MonsterSheetPlayer)).animate,
      isTrue,
    );
    await t.pumpWidget(
      const MaterialApp(
        home: Center(child: CreatureSprite(url: url, width: 34, height: 34)),
      ),
    );
    expect(
      t.widget<MonsterSheetPlayer>(find.byType(MonsterSheetPlayer)).animate,
      isFalse,
    );
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
