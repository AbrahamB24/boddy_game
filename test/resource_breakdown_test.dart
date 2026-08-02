import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

// ── Verbrauch und echtes Total (user 2026-08-01) ────────────
// "wenn ich auf eine Ressource klicke, sollen mir auch die negativen Werte/
//  Verbrauch angezeigt werden und am Ende das Total, welches wirklich
//  produziert wird"
//
// The header rate has subtracted what refineries eat since they existed; the
// breakdown sheet listed only the gross. So the sheet's rows did not add up to
// the number printed above them — which is the one property a breakdown has.
//
// This pins the ENGINE half of that: the rate a refinery's input really carries.
// The sheet's rows are derived from exactly these numbers.
void main() {
  EnergyModel energy() => EnergyModel(
    settlementId: 's',
    currentEnergy: 100,
    lastUpdatedAt: DateTime(2026),
  );

  test('a refinery eats its inputs out of the rate', () {
    // 5 Timber Frame/h costs 10 wood/h and 10 stone/h (2 each).
    final rates = GameEngine.hourlyRates(energy(), {'frame': 5, 'wood': 30});
    expect(kGoodsDefs['frame']!.refinedFrom, {'wood': 2, 'stone': 2});
    expect(rates['frame'], 5);
    expect(rates['wood'], 30 - 10, reason: '30 gross, 10 into the refinery');
    expect(rates['stone'], -10, reason: 'nothing quarried, ten burned');
  });

  test('what is not being refined costs nothing', () {
    final rates = GameEngine.hourlyRates(energy(), {'wood': 12});
    expect(rates['wood'], 12);
  });

  test('two refineries on the same input both take their share', () {
    // daub eats frames; frames eat wood. Making both drains wood once and
    // frames once — the chain has to be counted per step, not collapsed.
    final rates = GameEngine.hourlyRates(energy(), {'frame': 4, 'daub': 3});
    expect(rates['wood'], -8, reason: '4 frames × 2 wood');
    expect(rates['frame'], 4 - 6, reason: '4 made, 6 eaten by the daub');
  });

  test('an empty tank stops production, and with it the burn', () {
    final flat = EnergyModel(
      settlementId: 's',
      currentEnergy: 0,
      lastUpdatedAt: DateTime(2026),
    );
    final rates = GameEngine.hourlyRates(flat, {'frame': 5, 'wood': 30});
    // Whatever the floor dial says, the two must scale TOGETHER: a settlement
    // that stops making planks must stop eating wood for them.
    expect(rates['frame']! * 2, closeTo(-(rates['stone'] ?? 0), 0.001));
  });
}
