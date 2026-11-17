import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/guild/guild_crest.dart';

void main() {
  test('a crest survives its own json, and bad json falls back to the name', () {
    const c = GuildCrest(shape: 2, pattern: 5, symbol: 7, c1: 3, c2: 8, c3: 11);
    expect(GuildCrest.fromJson(c.toJson(), 'x'), c);
    expect(GuildCrest.fromJson(null, 'Wolves'), GuildCrest.fromName('Wolves'));
    final wild = GuildCrest.fromJson({'s': 99, 'c1': -4, 'y': 500}, 'Wolves');
    expect(wild.shape, 0);
    expect(wild.symbol, -1);
  });

  testWidgets('every shape, pattern and symbol draws, and the creator builds', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(
              children: [
                for (var s = 0; s < kCrestShapeNames.length; s++)
                  for (var p = 0; p < kCrestPatternNames.length; p++)
                    CrestView(GuildCrest(shape: s, pattern: p, symbol: (s * 8 + p) % 12)),
                for (var y = -1; y < kCrestSymbolNames.length; y++)
                  CrestView(GuildCrest(symbol: y)),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    var crest = GuildCrest.random(math.Random(3));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: StatefulBuilder(
              builder: (_, set) => CrestCreator(
                crest: crest,
                onChanged: (c) => set(() => crest = c),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
