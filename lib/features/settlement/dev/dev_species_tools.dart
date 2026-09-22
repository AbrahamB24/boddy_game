import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/services/creature_defs_service.dart';
import '../../creatures/services/stat_budget.dart';
import 'dev_foe.dart';

// The two bulk tools on the species roster, now buttons on the Dev menu's
// Actions page (user 2026-09-20: every dev button lives in the Dev menu).

/// Rescales every off-budget species onto its TOTAL budget (user 2026-07-17)
/// — same [isOnTotalBudget] check the 🔴 flag uses, so list and fix can never
/// disagree. The combat/work split, per-stat distribution and evo bumps are
/// preserved (uniform scale); only the magnitude moves.
Future<void> normalizeSpeciesBudgets(BuildContext context) async {
  final svc = CreatureDefsService();
  var fixed = 0;
  for (final d in kSpeciesDefs.values.toList()) {
    if (isOnTotalBudget(stats: d.stats, rarity: d.rarity, tier: d.tier)) {
      continue;
    }
    final normalized = normalizeToTotalBudget(
      stats: d.stats,
      rarity: d.rarity,
      tier: d.tier,
    );
    await svc.upsertSpeciesDef(d.copyWithStats(normalized));
    fixed++;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        fixed == 0
            ? 'Every species is already on budget.'
            : '⚖️ $fixed species rebalanced onto their budgets.',
      ),
    ),
  );
}

/// Re-rolls the stat distribution of EVERY species for a varied roster (user
/// 2026-07-17). Totals stay on budget; evo bumps are re-applied so evolving
/// still matters.
///
/// Role assignment re-worked 2026-09-07 (user: "die Monster stats müssen so
/// verteilt werden, dass alle Rollen vorhanden sind (Kampf-Archetyp und Prio
/// 1-3)"): the old version grouped species by (rarity, element) and cycled
/// the archetype/priority index WITHIN each group — with only a handful of
/// species per rarity×element combo, almost every group had size 1, which
/// meant index 0 every time: the huge majority of the roster landed on
/// `allrounder` with a single Prio-1 work stat, and Prio 3 was literally
/// never reachable (the old `picks` list only ever had 1 or 2 entries).
///
/// Now it's a single pass over the WHOLE sorted roster: the 10 archetypes
/// are shuffled once and handed out round-robin (so every press still
/// varies who gets what, but a full cycle touches all 10), and EVERY
/// species gets all 3 work priorities filled — 3 freshly-shuffled, distinct
/// stats each time (a 0-3 cycling depth was tried first and immediately
/// flagged back: "die prios wurden nicht übernommen" — species that landed
/// on depth 0 looked broken in the editor, not intentionally generalist).
///
/// Each species also gets a random early-bloomer/late-bloomer maturity bias
/// (user 2026-09-07: "gerne fände ich es schön, wenn es slow starter gibt,
/// welche dafür aber mehr wachsen als andere") — picked from a small,
/// clearly-distinguishable set rather than a smooth continuous roll, so a
/// re-roll produces a mix of pronounced early/late bloomers and neutral
/// species instead of everyone landing on a barely-noticeable middle value.
Future<void> rerollAllStats(BuildContext context) async {
  final total = kSpeciesDefs.length;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Re-roll all stats?', style: FoE.title(size: 15)),
      content: Text(
        'Overwrites the stat curves of all $total species. The three '
        'fire/water/plant epic starters keep an identical combat:work ratio; '
        'everyone else gets a varied mix. This cannot be undone.',
        style: FoE.label(size: 13).copyWith(color: FoE.parchment),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: FoE.label(size: 13)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            '🎲 Re-roll',
            style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
          ),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final svc = CreatureDefsService();
  final rng = math.Random();
  final workStats = kNonCombatStats; // 9 stats
  const maturityChoices = [-1.0, -0.5, 0.0, 0.5, 1.0];

  // Evenly WITHIN each rarity tier (user 2026-09-08: "die Kampfrollen und
  // die Prioritäten der Monster pro Seltenheitsstufe gleichmässig
  // verteilt werden. Aktuell gibt es noch grosse Unterschiede, da es
  // vermutlich zufällig ist"). The old loop shuffled ONE archetype list
  // and one fresh priority-shuffle per species across ALL 30 at once — a
  // tier's own slice of that was whatever fell out, so one tier could get
  // Bulwark three times while another never saw it. Grouping by rarity
  // FIRST and giving each group its own shuffle fixes that structurally,
  // not by chance:
  //  * ARCHETYPE: CombatArchetype has exactly 10 values, cycling a
  //    per-GROUP shuffle means a 10-species tier (today: common) uses
  //    every archetype exactly once; a 6- or 2-species tier uses that
  //    many DISTINCT archetypes with no repeat within the tier.
  //  * PRIORITIES: workStats has exactly 9 stats = 3 species' worth of 3
  //    picks each. Consuming one freshly-shuffled permutation of the 9
  //    per batch of 3 species means those 3 species between them use
  //    every work stat exactly once — evenly spread AND no species has
  //    two of its own 3 slots be the same stat by construction (a plain
  //    per-species reshuffle-and-take(3) can't promise either).
  final byRarity = <CreatureRarity, List<SpeciesDef>>{
    for (final r in CreatureRarity.values) r: [],
  };
  for (final d
      in kSpeciesDefs.values.toList()..sort((a, b) => a.id.compareTo(b.id))) {
    byRarity[d.rarity]!.add(d);
  }

  var count = 0;
  for (final group in byRarity.values) {
    if (group.isEmpty) continue;
    final shuffledArchetypes = CombatArchetype.values.toList()..shuffle(rng);
    List<CreatureStat> priorityCycle = [];
    for (var i = 0; i < group.length; i++) {
      final d = group[i];
      final arch = shuffledArchetypes[i % shuffledArchetypes.length];
      // Refill with a fresh shuffled permutation every 3rd species — see
      // the doc comment above for why 3 (workStats.length ÷ 3 picks).
      if (priorityCycle.isEmpty) {
        priorityCycle = workStats.toList()..shuffle(rng);
      }
      final picks = priorityCycle.take(3).toList();
      priorityCycle = priorityCycle.skip(3).toList();
      final maturity = maturityChoices[rng.nextInt(maturityChoices.length)];
      // Starters keep the exact default budget; everyone else a jittered one.
      final budget = isStarterSpecies(d)
          ? defaultBudget(rarity: d.rarity, tier: d.tier)
          : rollBudget(rarity: d.rarity, tier: d.tier, rng: rng);
      final stats = rollCurves(
        combat: arch,
        workPriorities: picks,
        budget: budget,
        rng: rng,
        jitter: 0.6,
        maturityBias: maturity,
      );
      // Persist the assigned role so the editor (and the species list) can
      // show it again.
      await svc.upsertSpeciesDef(
        d.copyWithStats(
          withEvoBumps(stats),
          role: SpeciesDef.encodeRole(arch.name, picks, maturityBias: maturity),
        ),
      );
      count++;
    }
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '🎲 Re-rolled $count species — archetypes and work priorities are '
        'now spread evenly WITHIN each rarity tier, every species has '
        'Prio 1-3 set and a rolled early/late-bloomer bias.',
      ),
    ),
  );
}
