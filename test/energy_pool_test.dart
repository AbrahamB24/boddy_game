import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/tuning/game_tuning.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/models/energy_model.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/services/game_engine.dart';

// ENERGY IS A POOL (user 2026-09-20): "Wenn ich Schritte mache, dann soll die
// Energie hochgehen. Bei 5000 Schritten ist es auf 100 %, bei 10 000 auf 125 %
// und es geht wirklich runter auf 0. 5000 Schritte reichen für 24 h und 10 000
// für 30 h. Mehr als 10 000 kann ich nicht haben und die weiteren Schritte
// verfallen. Sobald die Energie fällt, zählen die Schritte wieder."
//
// These are the numbers the player was promised, so they are pinned as numbers.
void main() {
  setUp(() => GameTuning.i.debugClear());
  tearDown(() => GameTuning.i.debugClear());

  group('filling: what steps are worth', () {
    test('5000 steps fill an empty pool to 100 %', () {
      expect(energyAfterSteps(0, 5000), closeTo(100, 1e-9));
    });

    test('10 000 steps fill it to the ceiling, 125 %', () {
      expect(energyAfterSteps(0, 10000), closeTo(125, 1e-9));
      expect(kEnergyMaxPercent, closeTo(125, 1e-9));
    });

    test('a step is felt at once: 1000 steps are +20 % below 100 %', () {
      expect(energyAfterSteps(0, 1000), closeTo(20, 1e-9));
      expect(energyAfterSteps(50, 1000), closeTo(70, 1e-9));
    });

    test('above 100 % a step is worth a quarter as much (+5 % per 1000)', () {
      expect(energyAfterSteps(100, 1000), closeTo(105, 1e-9));
    });

    test('a single walk that crosses 100 % is priced in both zones', () {
      // 60 % → needs 2000 steps to reach 100 %; the other 3000 are worth 15 %.
      expect(energyAfterSteps(60, 5000), closeTo(115, 1e-9));
    });

    test(
      'steps beyond 10 000 are lost — the pool never passes the ceiling',
      () {
        expect(energyAfterSteps(0, 15000), closeTo(125, 1e-9));
        expect(energyAfterSteps(125, 5000), closeTo(125, 1e-9));
        expect(energyAfterSteps(124, 1000), closeTo(125, 1e-9));
      },
    );

    test('no steps change nothing', () {
      expect(energyAfterSteps(37, 0), 37);
    });
  });

  group('emptying: what time costs', () {
    test('100 % lasts 24 h, 125 % lasts 30 h', () {
      expect(kEnergyFullHours, 24);
      expect(energyDrain(100, 24).endPercent, closeTo(0, 1e-9));
      expect(energyDrain(125, 30).endPercent, closeTo(0, 1e-9));
      // …and 125 % is just 6 h of 100 %'s worth on top.
      expect(energyDrain(125, 6).endPercent, closeTo(100, 1e-9));
      expect(
        EnergyModel(
          settlementId: 's',
          energyPct: 100,
          lastUpdatedAt: DateTime(2026),
        ).hoursLeft,
        closeTo(24, 1e-9),
      );
      expect(
        EnergyModel(
          settlementId: 's',
          energyPct: 125,
          lastUpdatedAt: DateTime(2026),
        ).hoursLeft,
        closeTo(30, 1e-9),
      );
    });

    test('it goes all the way down to 0 and stays there', () {
      expect(energyDrain(100, 100).endPercent, 0);
      expect(energyDrain(0, 5).endPercent, 0);
    });

    test('the window is priced at the FALLING rate, not the starting one', () {
      // 100 % → 0 over 24 h with no floor (the default): the rate falls
      // linearly from 1 to 0, so the day is worth half of its 24 hours.
      final r = energyDrain(100, 24);
      expect(r.effectiveHours, closeTo(12, 1e-9));
      expect(r.effectiveHours, lessThan(24));
    });

    test('a floor keeps the settlement crawling once the pool is empty', () {
      // The dial (default 0) set to 25 %: the pool's fraction down to the floor
      // (18 h, averaging 62.5 %), then the floor rate for the last 6 h.
      GameTuning.i.set(Dials.energyFloorMultiplier, 0.25);
      final r = energyDrain(100, 24);
      expect(r.effectiveHours, closeTo(18 * 0.625 + 6 * 0.25, 1e-9));
    });

    test('an empty pool does no work by default', () {
      expect(energyDrain(0, 10).effectiveHours, 0);
    });

    test('a short window is about the starting rate', () {
      final r = energyDrain(100, 0.01);
      expect(r.effectiveHours, closeTo(0.01, 1e-4));
    });

    test('an empty pool works at the floor rate for the whole window', () {
      final r = energyDrain(0, 10);
      expect(r.effectiveHours, closeTo(10 * kEnergyFloorMultiplier, 1e-9));
    });

    test('a bigger pool earns more over the same time', () {
      expect(
        energyDrain(125, 10).effectiveHours,
        greaterThan(energyDrain(100, 10).effectiveHours),
      );
    });

    test('the pool runs at its own fraction: 125 % is a x1.25 rate', () {
      expect(energyMultiplierForPercent(125), closeTo(1.25, 1e-9));
      expect(energyMultiplierForPercent(100), closeTo(1.0, 1e-9));
      expect(energyMultiplierForPercent(50), closeTo(0.5, 1e-9));
      expect(
        energyMultiplierForPercent(0),
        closeTo(kEnergyFloorMultiplier, 1e-9),
      );
    });
  });

  group('the two together', () {
    test(
      'steps at the ceiling are lost, and count again once it has dropped',
      () {
        final t0 = DateTime.utc(2026, 3, 1, 8);
        var e = EnergyModel(
          settlementId: 's',
          energyPct: 125,
          lastUpdatedAt: t0,
        );
        expect(e.isFull, isTrue);

        // Walking while full buys nothing.
        e = GameEngine.addSteps(e, 2000, t0);
        expect(e.energyPct, closeTo(125, 1e-9));
        expect(e.stepsToday, 2000); // it still counts what you walked

        // An hour later it has run down by 1/24 of 100 % …
        final later = GameEngine.tick(
          e,
          // No production is asked for; only the energy matters here.
          _emptyResources(t0),
          const [],
          t0.add(const Duration(hours: 1)),
          workshopPower: const {},
        ).energy;
        expect(later.energyPct, closeTo(125 - 100 / 24, 1e-9));
        expect(later.isFull, isFalse);

        // … and now the next steps count again.
        final refilled = GameEngine.addSteps(
          later,
          1000,
          t0.add(const Duration(hours: 1)),
        );
        expect(
          refilled.energyPct,
          closeTo(125, 1e-9),
        ); // 4.17 % of room, +5 % offered
        final small = GameEngine.addSteps(
          later,
          100,
          t0.add(const Duration(hours: 1)),
        );
        expect(small.energyPct, closeTo(later.energyPct + 0.5, 1e-9));
      },
    );

    test('the drain speed is a dial: 48 h makes 100 % last 48 h', () {
      GameTuning.i.set(Dials.energyFullHours, 48);
      expect(energyDrain(100, 48).endPercent, closeTo(0, 1e-9));
      expect(energyDrain(125, 60).endPercent, closeTo(0, 1e-9));
    });

    test(
      'a nonsense drain dial freezes the pool instead of dividing by zero',
      () {
        GameTuning.i.set(Dials.energyFullHours, 0);
        final r = energyDrain(80, 10);
        expect(r.endPercent, 80);
        expect(r.effectiveHours, closeTo(8, 1e-9));
      },
    );
  });

  group('persistence', () {
    test('round-trips through its row', () {
      final e = EnergyModel(
        settlementId: 's',
        energyPct: 87.5,
        stepsToday: 4321,
        stepsDayKey: '2026-09-20',
        lastUpdatedAt: DateTime.utc(2026, 9, 20, 7),
      );
      final back = EnergyModel.fromMap(e.toMap());
      expect(back.energyPct, 87.5);
      expect(back.stepsToday, 4321);
      expect(back.stepsDayKey, '2026-09-20');
    });

    test('a row from before the pool starts full, not empty', () {
      final back = EnergyModel.fromMap({
        'settlement_id': 's',
        'steps_today': 10,
        'last_updated_at': DateTime.utc(2026).toIso8601String(),
      });
      expect(back.energyPct, kEnergyStartPercent);
    });
  });
}

ResourceModel _emptyResources(DateTime at) =>
    ResourceModel(settlementId: 's', wood: 0, stone: 0, lastUpdatedAt: at);
