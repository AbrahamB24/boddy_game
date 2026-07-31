import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/tuning/game_tuning.dart';
import 'package:boddygame/features/creatures/models/combatant.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/creatures/services/capture_math.dart';
import 'package:boddygame/features/creatures/services/combat_engine.dart';
import 'package:boddygame/features/creatures/services/expedition_risk.dart';
import 'package:boddygame/features/creatures/services/gather_math.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/services/trade_center.dart';

// Every gameplay constant became a DIAL on 2026-07-29. That conversion is the
// kind that breaks silently — a getter reading the wrong id still compiles, and
// the game just plays differently. So the contract is pinned twice over:
//
//   1. the DEFAULTS still produce exactly the numbers the code shipped, and
//   2. turning a dial actually moves the game value it claims to.
//
// A dial that fails (1) changed the balance by accident. One that fails (2) is
// wired to nothing and would look editable while doing nothing at all.
void main() {
  setUp(() => GameTuning.i.debugClear());
  tearDown(() => GameTuning.i.debugClear());

  group('the registry itself', () {
    test('every id is unique', () {
      final ids = kDials.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every dial is renderable — label, help and a group', () {
      for (final d in kDials) {
        expect(d.label.trim(), isNotEmpty, reason: d.id);
        expect(d.help.trim(), isNotEmpty, reason: d.id);
        expect(d.section.trim(), isNotEmpty, reason: d.id);
      }
    });

    test('every group has dials — no empty menu', () {
      for (final g in TuningGroup.values) {
        expect(kDials.where((d) => d.group == g), isNotEmpty, reason: g.name);
      }
    });

    test('an untouched dial reports itself as untouched', () {
      expect(GameTuning.i.isOverridden(Dials.energyMax), isFalse);
      GameTuning.i.set(Dials.energyMax, 50);
      expect(GameTuning.i.isOverridden(Dials.energyMax), isTrue);
      GameTuning.i.reset(Dials.energyMax);
      expect(GameTuning.i.isOverridden(Dials.energyMax), isFalse);
      expect(kMaxEnergy, 100);
    });

    test('the field conversions round-trip', () {
      for (final d in kDials) {
        expect(d.fromField(d.toField(d.def)), closeTo(d.def, 1e-9),
            reason: d.id);
      }
    });

    test('a stored value for a dial nobody declares is ignored', () {
      // Guards the rename hazard: a dropped dial must not resurrect as a
      // number no getter reads.
      expect(GameTuning.i.raw('nonexistentDial'), 0);
    });
  });

  group('the defaults are exactly what the code used to hardcode', () {
    test('settlement', () {
      expect(kBaseExpeditionSlots, 0);
      expect(kBaseCaravanSlots, 0);
      expect(kBaseBuildSlots, 1);
      expect(kBaseQueueSlots, 0);
      // The +50 %/level curve: L1 ×1, L2 ×1.5, L5 ×3.
      expect(buildingYieldFactor(1), 1.0);
      expect(buildingYieldFactor(2), 1.5);
      expect(buildingYieldFactor(5), 3.0);
      expect(kBuildPointsForHalfTime, 100);
      expect(buildTimeCut(100), closeTo(0.5, 1e-9));
      expect(kBreedingK, 60);
      expect(breedingTimeCut(60), closeTo(0.5, 1e-9));
      expect(kMaxEnergy, 100);
      expect(kEnergyPerStep, closeTo(0.01, 1e-9));
      expect(kDrainPerHour, closeTo(100 / 24, 1e-9));
      expect(kEnergyFloorRate, 0);
      expect(kMaxTradeDiscount, 0.6);
      expect(kGoodsBuyMarkup, 2.5);
      expect(kBarterFee, 0.25);
    });

    test('campaign', () {
      expect(kBattlesBeforeBoss, 18);
      expect(kBattlesPerEra, 19);
      expect(kBossLevelBonus, 3);
      expect(kMaxPartySize, 6);
      // The old ladder was [6, 15, era2Start, +6, +12] with era2Start = 20.
      expect(partySizeThresholds(), [6, 15, 20, 26, 32]);
      expect(partySizeForBattle(1), 1);
      expect(partySizeForBattle(6), 2);
      expect(partySizeForBattle(15), 3);
      expect(kTravelSecondsPerDanger, 300);
      expect(kMaxTripSeconds, 24 * 3600);
      expect(kThreatPerDanger, 60);
    });

    test('monster', () {
      expect(kMaxEras, 8);
      expect(kLevelsPerEra, 10);
      expect(kCreatureMaxLevel, 80);
      expect(kActionPointsByStage, [4, 6, 8]);
      expect(kApRegenByStage, [3, 4, 5]);
      expect(kBaseActionPoints, 4);
      expect(kMaxActionPoints, 8);
      expect(kBasicAttackApCost, 3);
      expect(kSwitchApCost, 2);
      expect(kBuffApCost, 2);
      expect(kStartApFirst, 2);
      expect(kStartApSecond, 3);
      expect(CombatEngine.kFieldSlots, 3);
      expect(CombatEngine.kBaseAccuracy, 0.92);
      expect(CombatEngine.kMaxHitHpFraction, 0.5);
      expect(kWildStatMult, 0.85);
      expect(kBaseSigmaPct, 0.08);
      expect(kSlopeSigmaPct, 0.06);
      expect(kSigmaClampFactor, 2.0);
      expect(kBreedingFavoredChance, 0.60);
      expect(kCaptureWildStatMult, 0.75);
      expect(kQteRoundSpeedup, 0.80);
      expect(kQteWindowCenter, 0.35);
      expect(kQteWindowCatchK, 100);
      expect(kQteMaxWidthBonus, 1.2);
    });
  });

  group('turning a dial actually moves the game', () {
    test('the level curve', () {
      GameTuning.i.set(Dials.buildingLevelGrowth, 0.1);
      expect(buildingYieldFactor(3), closeTo(1.2, 1e-9));
    });

    test('base expedition slots', () {
      GameTuning.i.set(Dials.baseExpeditionSlots, 3);
      expect(kBaseExpeditionSlots, 3);
    });

    test('the energy budget stays internally consistent', () {
      GameTuning.i.set(Dials.energyMax, 200);
      GameTuning.i.set(Dials.energyEmptyHours, 10);
      GameTuning.i.set(Dials.energyStepsPerPoint, 50);
      expect(kMaxEnergy, 200);
      expect(kDrainPerHour, closeTo(20, 1e-9));
      expect(kEnergyPerStep, closeTo(0.02, 1e-9));
    });

    test('the party ladder — and out-of-order entries still rise', () {
      GameTuning.i.set(Dials.partyStep2, 30);
      GameTuning.i.set(Dials.partyStep3, 2);
      expect(partySizeThresholds().first, 2);
      expect(partySizeForBattle(2), 2);
      // The cap still wins over the ladder.
      GameTuning.i.set(Dials.maxPartySize, 2);
      expect(partySizeForBattle(999), 2);
    });

    test('the boss bonus', () {
      GameTuning.i.set(Dials.bossLevelBonus, 10);
      final boss = bossBattleForEra(1);
      expect(enemyLevelForBattle(boss) - enemyLevelForBattle(boss - 1),
          greaterThanOrEqualTo(10));
    });

    test('the AP table', () {
      GameTuning.i.set(Dials.apCapacity3, 12);
      expect(kActionPointsByStage, [4, 6, 12]);
      expect(kMaxActionPoints, 12);
      expect(maxActionPointsForStage(2), 12);
    });

    test('the level cap', () {
      GameTuning.i.set(Dials.maxEras, 3);
      GameTuning.i.set(Dials.levelsPerEra, 5);
      expect(kCreatureMaxLevel, 15);
      expect(creatureLevelCap(99), 15);
    });

    test('the trade spread', () {
      GameTuning.i.set(Dials.goodsBuyMarkup, 4);
      expect(goodsBuyMarkup(0), closeTo(4, 1e-9));
    });

    test('the loot penalty ceiling', () {
      final many = [
        for (var i = 0; i < 20; i++)
          Casualty(creatureId: '$i', hpLost: 1, ko: true),
      ];
      expect(lootPenalty(many), closeTo(0.4, 1e-9));
      GameTuning.i.set(Dials.lootPenaltyMax, 0.9);
      expect(lootPenalty(many), closeTo(0.9, 1e-9));
    });
  });
}
