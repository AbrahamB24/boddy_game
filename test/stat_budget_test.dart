import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/stat_budget.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';

/// Curves exactly on the Common budget: an allrounder combat spread + even
/// work spread, scaled to whatever the per-rarity totals currently are, with
/// +10/+20 evolution stage bumps so combatBaseByStage is testable.
Map<CreatureStat, StatCurve> _onBudget() {
  final b = defaultBudget(rarity: CreatureRarity.common);
  final combatWeights = kCombatArchetypeWeights[CombatArchetype.allrounder]!;
  final combatSum = combatWeights.values.reduce((a, c) => a + c);
  final result = <CreatureStat, StatCurve>{};
  for (final e in combatWeights.entries) {
    final base0 = e.value / combatSum * b.combatBase;
    result[e.key] = StatCurve(
      stageBase: [base0, base0 + 10, base0 + 20],
      growth: e.value / combatSum * b.combatGrowth,
    );
  }
  final work = kNonCombatStats;
  final eachBase = b.workBase / work.length;
  final eachGrowth = b.workGrowth / work.length;
  for (final s in work) {
    result[s] = StatCurve(
      stageBase: [eachBase, eachBase + 10, eachBase + 20],
      growth: eachGrowth,
    );
  }
  return result;
}

void main() {
  group('prioritised work role + roll (user design 2026-07-17)', () {
    final workStats =
        CreatureStat.values.where((s) => s.isCivilian).toList();

    test('work weights sum to the budget and rank by priority', () {
      final w = workRoleWeights([
        CreatureStat.gathering,
        CreatureStat.production,
        CreatureStat.crafting,
      ]);
      expect(w.values.reduce((a, b) => a + b),
          closeTo(kNonCombatBudgetTarget, 1e-9));
      expect(w[CreatureStat.gathering]!, greaterThan(w[CreatureStat.production]!));
      expect(w[CreatureStat.production]!, greaterThan(w[CreatureStat.crafting]!));
      // A non-priority stat keeps a small base, below every priority.
      expect(w[CreatureStat.crafting]!, greaterThan(w[CreatureStat.breeding]!));
    });

    test('empty priorities = the even generalist spread', () {
      final w = workRoleWeights([]);
      final vals = w.values.toList();
      for (final v in vals) {
        expect(v, closeTo(vals.first, 1e-9));
      }
    });

    test('buildCurves lands exactly on budget', () {
      final budget = defaultBudget(rarity: CreatureRarity.rare, tier: 2);
      final curves = buildCurves(
        combat: CombatArchetype.glassCannon,
        workPriorities: [CreatureStat.crafting, CreatureStat.construction],
        budget: budget,
      );
      final report = auditStatBudget(
        stats: curves,
        rarity: CreatureRarity.rare,
        tier: 2,
        targets: budget,
      );
      expect(report.isWithinTolerance, isTrue);
    });

    test('roll stays on-budget but two rolls differ', () {
      final budget = defaultBudget(rarity: CreatureRarity.common);
      Map<CreatureStat, StatCurve> roll(int seed) => rollCurves(
        combat: CombatArchetype.allrounder,
        workPriorities: [CreatureStat.production],
        budget: budget,
        rng: math.Random(seed),
      );
      final a = roll(1);
      final b = roll(2);
      // Both spend the budget…
      expect(auditStatBudget(
              stats: a, rarity: CreatureRarity.common, targets: budget)
          .isWithinTolerance, isTrue);
      expect(auditStatBudget(
              stats: b, rarity: CreatureRarity.common, targets: budget)
          .isWithinTolerance, isTrue);
      // …but not identical (some stat differs).
      final differs = workStats.any((s) =>
          (a[s]!.baseAt(0) - b[s]!.baseAt(0)).abs() > 0.5);
      expect(differs, isTrue, reason: 'two rolls should make different monsters');
    });

    // The base and the slope must be INDEPENDENT draws (user 2026-07-27: "dann
    // soll nicht automatisch der Anstieg und der Startwert hoch sein").
    //
    // The old code fed ONE jittered weight vector to both halves, which made
    // growth an exact multiple of the base: every stat in a group shared the
    // same growth/base ratio (= growthTotal / baseTotal), whatever the roll did.
    // So the ratios SPREADING is precisely the property that was missing.
    test('roll draws base and growth independently', () {
      final budget = defaultBudget(rarity: CreatureRarity.common);
      var sawSpread = 0;
      for (var seed = 0; seed < 20; seed++) {
        final c = rollCurves(
          combat: CombatArchetype.bulwark,
          workPriorities: [CreatureStat.production],
          budget: budget,
          rng: math.Random(seed),
        );
        final ratios = [
          for (final s in kCombatStats)
            if (c[s]!.baseAt(0) > 0) c[s]!.growth / c[s]!.baseAt(0),
        ];
        final spread = ratios.reduce(math.max) / ratios.reduce(math.min);
        // Coupled rolls give exactly 1.0 for every seed.
        if (spread > 1.3) sawSpread++;
      }
      expect(sawSpread, greaterThan(15),
          reason: 'growth should not track the base');
    });

    test('a custom budget makes a stronger monster (more combat base)', () {
      final rich = defaultBudget(rarity: CreatureRarity.common);
      final richer = (
        combatBase: rich.combatBase * 1.5,
        combatGrowth: rich.combatGrowth,
        workBase: rich.workBase,
        workGrowth: rich.workGrowth,
      );
      final curves = buildCurves(
        combat: CombatArchetype.allrounder,
        workPriorities: const [],
        budget: richer,
      );
      final report = auditStatBudget(
        stats: curves,
        rarity: CreatureRarity.common,
        targets: richer,
      );
      expect(report.isWithinTolerance, isTrue);
      expect(report.lines.first.actual,
          closeTo(rich.combatBase * 1.5, 1e-6)); // combat base scaled up
    });
  });

  group('derived helpers', () {
    test('catch rate falls as rarity rises', () {
      double prev = 99;
      for (final r in CreatureRarity.values) {
        final c = catchRateForRarity(r);
        expect(c, lessThan(prev), reason: r.name);
        expect(c, inInclusiveRange(0.5, 1.5)); // stays in the qte clamp
        prev = c;
      }
    });

    test('statBaseMax is the configured per-category cap', () {
      // The per-attribute max is a global per-rarity/category limit (user
      // 2026-07-24) and CARRIES A REAL VALUE since 2026-07-29 — without one
      // the whole budget could sit in a single attribute. Its clamping is
      // covered in species_budget_test.
      expect(
        statBaseMax(CreatureStat.hp, CreatureRarity.common),
        kSpeciesBalance.of(CreatureRarity.common).combatMaxBase,
      );
      // Rarer never gets a tighter ceiling than commoner.
      expect(
        statBaseMax(CreatureStat.hp, CreatureRarity.legendary)!,
        greaterThanOrEqualTo(
          statBaseMax(CreatureStat.hp, CreatureRarity.common)!,
        ),
      );
    });

    test('the budget splits the per-rarity total by the default combat share',
        () {
      final t = defaultBudget(rarity: CreatureRarity.common);
      final tb = budgetBaseTotal(rarity: CreatureRarity.common);
      final tg = budgetGrowthTotal(rarity: CreatureRarity.common);
      expect(t.combatBase, closeTo(tb * kDefaultCombatShare, 1e-9));
      expect(t.workBase, closeTo(tb * (1 - kDefaultCombatShare), 1e-9));
      expect(t.combatGrowth, closeTo(tg * kDefaultCombatShare, 1e-9));
    });

    test('totals are fixed per rarity (common 270 base / 9 growth)', () {
      // User 2026-07-17: base/growth are per-rarity totals (tier-1 spec); only
      // the combat/work SPLIT is free, not the total.
      expect(budgetBaseTotal(rarity: CreatureRarity.common), closeTo(270, 1e-9));
      expect(
          budgetGrowthTotal(rarity: CreatureRarity.common), closeTo(9, 1e-9));
      for (final share in [0.35, 0.6, 0.8]) {
        final b = budgetFromSplit(
          rarity: CreatureRarity.common,
          baseShare: share,
          growthShare: share,
        );
        expect(b.combatBase + b.workBase, closeTo(270, 1e-9));
        expect(b.combatGrowth + b.workGrowth, closeTo(9, 1e-9));
        expect(b.combatBase, closeTo(270 * share, 1e-9));
      }
    });

    test('a rolled split keeps the totals', () {
      final b = rollBudget(
        rarity: CreatureRarity.rare,
        tier: 2,
        rng: math.Random(5),
      );
      final tb = budgetBaseTotal(rarity: CreatureRarity.rare, tier: 2);
      final tg = budgetGrowthTotal(rarity: CreatureRarity.rare, tier: 2);
      expect(b.combatBase + b.workBase, closeTo(tb, 1e-6));
      expect(b.combatGrowth + b.workGrowth, closeTo(tg, 1e-6));
    });
  });

  test('an on-budget common passes every line', () {
    final report = auditStatBudget(
      stats: _onBudget(),
      rarity: CreatureRarity.common,
    );
    expect(report.isWithinTolerance, isTrue);
    for (final line in report.lines) {
      expect(line.deviation.abs(), lessThan(1e-9), reason: line.label);
    }
    // Stage bumps are reported (5 combat stats × +10 / +20 — catchRate
    // joined the combat group 2026-07-22).
    expect(
      report.combatBaseByStage[1] - report.combatBaseByStage[0],
      closeTo(50, 1e-9),
    );
  });

  test('overspending combat base gets flagged', () {
    final stats = _onBudget();
    stats[CreatureStat.attack] = const StatCurve(
      stageBase: [140, 140, 140], // +100 over the allrounder 40
      growth: 1,
    );
    final report = auditStatBudget(
      stats: stats,
      rarity: CreatureRarity.common,
    );
    expect(report.isWithinTolerance, isFalse);
    final combat = report.lines.firstWhere((l) => l.label == 'Combat base');
    expect(combat.deviation, greaterThan(kBudgetTolerance));
  });

  test('rarity raises the target — the same curves read as underspent', () {
    final commonReport = auditStatBudget(
      stats: _onBudget(),
      rarity: CreatureRarity.common,
    );
    final legendaryReport = auditStatBudget(
      stats: _onBudget(),
      rarity: CreatureRarity.legendary,
    );
    final commonLine = commonReport.lines.first;
    final legendaryLine = legendaryReport.lines.first;
    // Driven by the per-rarity base table, not a hardcoded factor — the rarity
    // curve is a balance dial and tuning it must not break this test.
    expect(
      legendaryLine.target,
      closeTo(
        commonLine.target *
            (budgetBaseTotal(rarity: CreatureRarity.legendary) /
                budgetBaseTotal(rarity: CreatureRarity.common)),
        1e-9,
      ),
    );
    // Under-target, but since the 2026-07-22 compression (+5/step) the
    // legendary/common gap (~7%) sits INSIDE the 10% tolerance — deliberately:
    // rarity is flavour now, so common curves merely read as slightly light.
    expect(legendaryLine.deviation, lessThan(0));
  });

  group('archetypes', () {
    test('every archetype spends exactly the budget — none is stronger', () {
      for (final combat in CombatArchetype.values) {
        for (final civil in CivilArchetype.values) {
          final curves = buildArchetypeCurves(
            combat: combat,
            civil: civil,
            rarity: CreatureRarity.common,
          );
          final report = auditStatBudget(
            stats: curves,
            rarity: CreatureRarity.common,
          );
          expect(
            report.isWithinTolerance,
            isTrue,
            reason: '${combat.name}/${civil.name} must be on budget',
          );
        }
      }
    });

    test('a specialist really specialises vs the generalist', () {
      Map<CreatureStat, StatCurve> curves(CivilArchetype c) =>
          buildArchetypeCurves(
            combat: CombatArchetype.allrounder,
            civil: c,
            rarity: CreatureRarity.common,
          );
      final generalCarry =
          curves(CivilArchetype.generalist)[CreatureStat.carry]!.baseAt(0);
      final carrierCarry =
          curves(CivilArchetype.carrier)[CreatureStat.carry]!.baseAt(0);
      expect(carrierCarry, greaterThan(generalCarry * 3));
      // ...and pays for it elsewhere.
      expect(
        curves(CivilArchetype.carrier)[CreatureStat.crafting]!.baseAt(0),
        lessThan(curves(CivilArchetype.generalist)[CreatureStat.crafting]!
            .baseAt(0)),
      );
    });

    test('catchRate is a combat capability (user 2026-07-22)', () {
      // It moved INTO the combat group/budget; its function is unchanged
      // (drives catching only). Every archetype carries its flat weight.
      expect(CreatureStat.catchRate.isCombat, isTrue);
      expect(CreatureStat.catchRate.isCivilian, isFalse);
      expect(CreatureStat.catchRate.isWorkRole, isFalse);
      for (final w in kCombatArchetypeWeights.values) {
        expect(w[CreatureStat.catchRate], isNotNull);
      }
    });

    test('rarity scales an archetype up and it stays on ITS budget', () {
      final legendary = buildArchetypeCurves(
        combat: CombatArchetype.allrounder,
        civil: CivilArchetype.generalist,
        rarity: CreatureRarity.legendary,
      );
      final common = buildArchetypeCurves(
        combat: CombatArchetype.allrounder,
        civil: CivilArchetype.generalist,
        rarity: CreatureRarity.common,
      );
      expect(
        legendary[CreatureStat.hp]!.baseAt(0),
        greaterThan(common[CreatureStat.hp]!.baseAt(0)),
      );
      expect(
        auditStatBudget(
          stats: legendary,
          rarity: CreatureRarity.legendary,
        ).isWithinTolerance,
        isTrue,
      );
    });
  });

  test('rarer monsters distribute a bit more — but only a bit', () {
    double budget(CreatureRarity r) => budgetBaseTotal(rarity: r);
    var prev = 0.0;
    for (final r in CreatureRarity.values) {
      final b = budget(r);
      expect(b, greaterThan(prev), reason: '${r.name} must out-budget the tier below');
      prev = b;
    }
    // User 2026-07-17 "seltene nur ein bisschen besser": the whole spread stays
    // TIGHT — legendary is only modestly above common, not a different league.
    expect(
      budget(CreatureRarity.legendary),
      lessThan(budget(CreatureRarity.common) * 1.25),
    );
    // ...and well inside the ceiling the boss fight can survive: the region
    // boss is a legendary with a x1.2 elite bonus on top, and budget scales
    // ~cubically (docs/balancing.md §4c). Past ~1.5 the boss stops being
    // beatable at all — this guard is what keeps the era gate passable.
    expect(
      budget(CreatureRarity.legendary) / budget(CreatureRarity.common) * 1.2,
      lessThan(1.8),
      reason: 'legendary x elite must stay beatable — re-run the Monte-Carlo',
    );
  });

  test('tier is the tier-1 spec for now — higher tiers reuse it', () {
    // Tier 2+ budgets are defined later (user 2026-07-17); until then every
    // tier uses the tier-1 per-rarity totals, so an on-budget curve stays on
    // budget at any tier.
    expect(
      budgetBaseTotal(rarity: CreatureRarity.common, tier: 3),
      closeTo(budgetBaseTotal(rarity: CreatureRarity.common), 1e-9),
    );
    final t3 = auditStatBudget(
      stats: _onBudget(),
      rarity: CreatureRarity.common,
      tier: 3,
    );
    expect(t3.isWithinTolerance, isTrue);
  });

  test('missing curves count as zero, not as phantom defaults', () {
    final report = auditStatBudget(stats: {}, rarity: CreatureRarity.common);
    for (final line in report.lines) {
      expect(line.actual, 0, reason: line.label);
    }
    expect(report.isWithinTolerance, isFalse);
  });

  group('normalizeStatBudget (the dev "fix red budgets" action)', () {
    test('any off-budget species lands back inside tolerance', () {
      // Grossly over combat budget, under civil budget, lopsided growth —
      // the worst dev-authored red case.
      final lopsided = <CreatureStat, StatCurve>{
        CreatureStat.hp: const StatCurve(stageBase: [300, 340, 400], growth: 2),
        CreatureStat.attack:
            const StatCurve(stageBase: [200, 220, 260], growth: 30),
        CreatureStat.defense:
            const StatCurve(stageBase: [50, 55, 60], growth: 0.5),
        CreatureStat.production:
            const StatCurve(stageBase: [10, 10, 10], growth: 0.1),
        CreatureStat.carry: const StatCurve(stageBase: [5, 5, 5], growth: 0),
      };
      for (final rarity in CreatureRarity.values) {
        for (final tier in [1, 2, 3]) {
          final fixed = normalizeStatBudget(
            stats: lopsided,
            rarity: rarity,
            tier: tier,
          );
          final report = auditStatBudget(
            stats: fixed,
            rarity: rarity,
            tier: tier,
          );
          expect(
            report.isWithinTolerance,
            isTrue,
            reason:
                '${rarity.name} t$tier: '
                '${report.lines.map((l) => '${l.label}=${l.deviation.toStringAsFixed(2)}').join(', ')}',
          );
        }
      }
    });

    test('preserves the distribution and the evolution bumps', () {
      final fixed = normalizeStatBudget(
        stats: {
          CreatureStat.hp: const StatCurve(stageBase: [90, 120, 150], growth: 3),
          CreatureStat.attack:
              const StatCurve(stageBase: [30, 40, 50], growth: 1),
        },
        rarity: CreatureRarity.common,
      );
      // hp:attack stayed 3:1 at stage 0…
      expect(
        fixed[CreatureStat.hp]!.baseAt(0) / fixed[CreatureStat.attack]!.baseAt(0),
        closeTo(3.0, 1e-9),
      );
      // …and the evo bump ratio (stage1/stage0) survived the rescale.
      expect(
        fixed[CreatureStat.hp]!.baseAt(1) / fixed[CreatureStat.hp]!.baseAt(0),
        closeTo(120 / 90, 1e-9),
      );
    });

    test('an empty group gets the even generalist spread, on budget', () {
      final fixed = normalizeStatBudget(
        stats: {
          CreatureStat.hp: const StatCurve(stageBase: [60, 60, 60], growth: 1.5),
        },
        rarity: CreatureRarity.common,
      );
      final report = auditStatBudget(stats: fixed, rarity: CreatureRarity.common);
      expect(report.isWithinTolerance, isTrue);
    });
  });
}
