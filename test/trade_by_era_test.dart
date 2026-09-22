import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/services/trade_center.dart';

// The Market lays one ERA's resources side by side (user 2026-09-20: "alle drei
// Ressourcen pro Stufe nebeneinander"). This pins the grouping it draws from.
void main() {
  test('region I is one row: wood, stone and its luxury', () {
    final eras = tradeableByEra(1);
    expect(eras, hasLength(1));
    expect(eras.single.era, 1);
    expect(eras.single.resources, ['wood', 'stone', 'fish']);
  });

  test('every era is three resources, newest era first', () {
    final eras = tradeableByEra(4);
    expect(eras.map((e) => e.era), [4, 3, 2, 1]);
    for (final e in eras) {
      expect(e.resources, hasLength(3), reason: 'era ${e.era}');
    }
  });

  test('nothing is lost or doubled by the grouping', () {
    for (var region = 1; region <= 8; region++) {
      final flat = [
        for (final e in tradeableByEra(region)) ...e.resources,
      ];
      expect(flat.toSet(), tradeableResources(region).toSet());
      expect(flat, hasLength(tradeableResources(region).length));
    }
  });
}
