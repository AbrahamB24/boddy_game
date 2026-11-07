import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:boddygame/core/theme/game_icon_data.dart';
import 'package:boddygame/core/theme/voxel_kit.dart' show VoxelTextScaler;
import 'package:boddygame/core/ui/game_text.dart';

void main() {
  test('every icon key has its picture and every emoji maps to one', () {
    for (final k in kGameIconKeys) {
      expect(File('assets/images/icons/$k.webp').existsSync(), isTrue,
          reason: 'missing assets/images/icons/$k.webp');
    }
    for (final e in kEmojiToIcon.entries) {
      expect(kGameIconKeys.contains(e.value), isTrue, reason: e.key);
    }
  });

  test('emojiSpans swaps known emoji and leaves plain text alone', () {
    expect(emojiSpans('plain text', 14), isNull);
    expect(emojiSpans('♂ and ↔ stay', 14), isNull);
    final s = emojiSpans('+5 🪙 gold', 14)!;
    expect(s.length, 3);
    expect(s[1], isA<EmojiSpan>());
    // variation selector is swallowed
    final v = emojiSpans('⚔️ fight', 14)!;
    expect(v.whereType<WidgetSpan>().length, 1);
    expect((v.last as TextSpan).text, ' fight');
  });

  testWidgets('Text draws an icon for an emoji and keeps its label', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Text('3 🪵 wood'))));
    expect(find.byType(Image), findsOneWidget);
    expect(find.bySemanticsLabel('3 🪵 wood'), findsOneWidget);
  });

  testWidgets('the icon follows the app text scaler, not a constant', (t) async {
    await t.pumpWidget(MaterialApp(
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: const VoxelTextScaler()),
        child: w!,
      ),
      home: const Scaffold(
        body: Text('🪙', style: TextStyle(fontSize: 15)),
      ),
    ));
    final size = t.getSize(find.byType(Image));
    // 15 px text scaled by 1.1, icon a little larger than the text: ~20 px.
    expect(size.width, inInclusiveRange(15, 26));
  });
}
