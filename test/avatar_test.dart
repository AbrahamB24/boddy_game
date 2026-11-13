import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/avatar/avatar_catalog.dart';
import 'package:boddygame/features/avatar/avatar_creator_screen.dart';
import 'package:boddygame/features/avatar/avatar_layers.g.dart';
import 'package:boddygame/features/avatar/avatar_spec.dart';
import 'package:boddygame/features/avatar/avatar_view.dart';

// The player avatar (user 2026-11-13): a spec of part ids + colour indices that
// the app stacks from layer pictures rendered by tool/blender/avatar.py.
void main() {
  group('AvatarSpec', () {
    test('survives a JSON round trip', () {
      const s = AvatarSpec(hair: 'long', hat: 'cap', skinC: 5, hairC: 9);
      expect(AvatarSpec.fromJson(s.toJson()), s);
    });

    test('anything unknown or out of range falls back to the default', () {
      final s = AvatarSpec.fromJson({
        'hair': 'nonsense',
        'top': 7, // wrong type
        'skinC': 99,
        'hairC': -1,
        'eyes': 'big',
      });
      expect(s.hair, AvatarSpec.defaults.hair);
      expect(s.top, AvatarSpec.defaults.top);
      expect(s.skinC, AvatarSpec.defaults.skinC);
      expect(s.hairC, AvatarSpec.defaults.hairC);
      expect(s.eyes, 'big');
      expect(AvatarSpec.fromJson(null), AvatarSpec.defaults);
      expect(AvatarSpec.fromJson('x'), AvatarSpec.defaults);
    });

    test('a random look only uses unlocked parts', () {
      const none = AvatarProgress();
      for (var i = 0; i < 60; i++) {
        final s = AvatarSpec.random(none);
        for (final c in AvatarCategory.values) {
          final p = partFor(c, s.partOf(c));
          if (c == AvatarCategory.skin) continue;
          expect(p, isNotNull, reason: '${c.name} ${s.partOf(c)}');
          expect(p!.unlock.isMet(none), isTrue, reason: '${c.name}/${p.id}');
        }
      }
    });
  });

  group('catalog and art agree', () {
    test('every part has its picture for the layers it uses', () {
      final missing = <String>[];
      void need(String layer, String id) {
        if (!kAvatarLayerFiles.contains('$layer/$id')) missing.add('$layer/$id');
      }

      for (final p in kParts[AvatarCategory.hair]!) {
        if (p.id == 'none') continue;
        need('hair_front', p.id); // some hair has a back layer too, never required
      }
      for (final p in kParts[AvatarCategory.eyes]!) {
        need('eyes', p.id);
        need('brows', p.id);
      }
      for (final p in kParts[AvatarCategory.mouth]!) {
        need('mouth', p.id);
      }
      for (final p in kParts[AvatarCategory.beard]!) {
        if (p.id != 'none') need('beard', p.id);
      }
      for (final p in kParts[AvatarCategory.top]!) {
        need('top', p.id);
        need('top_trim', p.id);
      }
      for (final p in kParts[AvatarCategory.bottom]!) {
        need('bottom', p.id);
      }
      for (final p in kParts[AvatarCategory.shoes]!) {
        need('shoes', p.id);
      }
      for (final p in kParts[AvatarCategory.hat]!) {
        if (p.id == 'none') continue;
        need('hat', p.id);
        need('hat_trim', p.id);
      }
      for (final p in kParts[AvatarCategory.extra]!) {
        if (p.id == 'none') continue;
        expect(
          kAvatarLayerFiles.contains('acc_front/${p.id}') ||
              kAvatarLayerFiles.contains('acc_back/${p.id}'),
          isTrue,
          reason: p.id,
        );
      }
      expect(missing, isEmpty);
    });

    test('the figure itself is there', () {
      expect(kAvatarLayerFiles, containsAll(['body/base', 'head/base']));
    });

    test('unlock rules read well', () {
      expect(const AvatarUnlock(battles: 10).isMet(const AvatarProgress(battles: 9)), isFalse);
      expect(const AvatarUnlock(battles: 10).isMet(const AvatarProgress(battles: 10)), isTrue);
      expect(const AvatarUnlock(guild: true).isMet(const AvatarProgress()), isFalse);
      expect(const AvatarUnlock(battles: 5, guild: true).hint, 'Unlock: clear 5 battles and join a guild');
    });
  });

  group('rendering', () {
    testWidgets('the composer stacks the layers into one picture', (t) async {
      await t.runAsync(() async {
        final full = await AvatarComposer.instance.compose(AvatarSpec.defaults);
        final bust = await AvatarComposer.instance.compose(
          AvatarSpec.defaults,
          bust: true,
        );
        expect(full, isNotNull);
        expect(bust, isNotNull);
        expect(full!.width, full.height);
        // Not empty: some pixels are opaque.
        final px = (await full.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        ))!.buffer.asUint8List();
        var opaque = 0;
        for (var i = 3; i < px.length; i += 4) {
          if (px[i] > 200) opaque++;
        }
        expect(opaque, greaterThan(full.width * full.height ~/ 10));
      });
    });

    testWidgets('the creator fits a phone in landscape', (t) async {
      t.view.physicalSize = const Size(932, 430);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const AvatarCreatorScreen(
              start: AvatarSpec(hair: 'long', hat: 'wizard', top: 'robe'),
              progress: AvatarProgress.all,
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.takeException(), isNull);
      expect(find.text('Hair'), findsOneWidget);
      // Every category can be opened without overflow.
      for (final c in AvatarCategory.values) {
        // The chips scroll sideways and are built on demand.
        if (find.text(c.label).evaluate().isEmpty) {
          await t.drag(find.byType(ListView).first, const Offset(-400, 0));
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.tap(find.text(c.label).first);
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull, reason: c.label);
      }
      await t.drag(find.byType(ListView).first, const Offset(600, 0));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.text('Top').first);
      for (var i = 0; i < 12; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 50));
      }
      final out = Platform.environment['AVATAR_SHOT'];
      if (out != null) {
        await t.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage();
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          File(out).writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    });
  });
}
