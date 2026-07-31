import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/data/goods_definitions.dart' show goodsForEra;
import '../../settlement/dev/dev_theme.dart';
import '../models/creature_enums.dart';
import '../models/heal_balance.dart';
import '../models/species_balance.dart';
import '../services/creature_defs_service.dart';

/// Global species-balance config (user 2026-07-24). Per rarity: the combat/civil
/// BASE and GROWTH point budgets, one per-category LIMIT each (base + growth,
/// applied to every attribute of that category), and the rarity's catch rate.
/// Persisted in game_config; read by the stat-budget system.
///
/// Two more tabs since 2026-07-26: Breeding (mating AND hatching hours, with a
/// "target time → required breeding power" reading so a duration can be
/// authored without doing the soft-cap algebra by hand) and XP (the level
/// curve and the passive earn rates).
class SpeciesBalanceForm extends StatefulWidget {
  const SpeciesBalanceForm({super.key});

  @override
  State<SpeciesBalanceForm> createState() => _SpeciesBalanceFormState();
}

class _SpeciesBalanceFormState extends State<SpeciesBalanceForm> {
  final _svc = CreatureDefsService();
  bool _saving = false;
  // Bumped on "reset to defaults" so the fields re-seed; a keystroke does NOT
  // bump it, so typing never resets the field mid-edit.
  int _gen = 0;

  late Map<CreatureRarity, RarityConfig> _cfg;
  late XpConfig _xp;
  late HealConfig _heal;

  /// Reference max-HP the healing preview is read for — a lens on the config,
  /// not part of it (same contract as [_targetHours]).
  double _refMaxHp = 60;

  /// Target durations the author is asking about, per rarity and phase — the
  /// "wie viel Power brauche ich für X Stunden?" lens. NOT saved: it asks a
  /// question about the config, it isn't part of it (same contract as the
  /// effects editor's reference stat).
  final Map<String, double> _targetHours = {};

  @override
  void initState() {
    super.initState();
    _cfg = {...kSpeciesBalance.byRarity};
    _xp = kXpBalance;
    _heal = kHealBalance;
  }

  void _update(CreatureRarity r, RarityConfig c) =>
      setState(() => _cfg[r] = c);

  Future<void> _save() async {
    setState(() => _saving = true);
    final balance = SpeciesBalance(byRarity: _cfg);
    try {
      await _svc.saveSpeciesBalance(balance);
      await _svc.saveXpBalance(_xp);
      await _svc.saveHealBalance(_heal);
      kSpeciesBalance = balance; // live effect without waiting for a reload
      kXpBalance = _xp;
      kHealBalance = _heal;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  void _resetDefaults() {
    setState(() {
      _cfg = {...defaultSpeciesBalance().byRarity};
      _xp = const XpConfig();
      _heal = const HealConfig();
      _gen++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildDevModeTheme(),
      child: DefaultTabController(
        length: 5,
        child: Scaffold(
            appBar: AppBar(
            title: Text('Species-Budget', style: FoE.title(size: 16)),
            actions: [
              TextButton(
                onPressed: _resetDefaults,
                child: Text('↺ Defaults', style: FoE.label(size: 11)),
              ),
            ],
            bottom: const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Budget & Limits'),
                Tab(text: 'Fang'),
                Tab(text: 'Breeding'),
                Tab(text: '⭐ XP'),
                Tab(text: '🩹 Heilung'),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: TabBarView(
                  children: [
                    _budgetTab(),
                    _catchTab(),
                    _breedTab(),
                    _xpTab(),
                    _healTab(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: _saveButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _budgetTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Text(
        'Per rarity: the points handed out (base/growth) and ONE cap each for '
        'combat and civil — it applies to every stat in that group. '
        '0 = no cap.',
        style: FoE.dim(size: 11),
      ),
      const SizedBox(height: 8),
      for (final r in CreatureRarity.values) _rarityCard(r),
    ],
  );

  Widget _catchTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Text(
        'Per rarity: how OFTEN it shows up on catch expeditions (encounter '
        'weight, relative within the pool), how HARD it is to catch (ring '
        'hits needed), and the catch window (slipperiness — higher = a '
        'wider target zone).',
        style: FoE.dim(size: 11),
      ),
      const SizedBox(height: 10),
      for (final r in CreatureRarity.values) _catchCard(r),
    ],
  );

  Widget _catchCard(CreatureRarity r) {
    final c = _cfg[r]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.label, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
          const SizedBox(height: 2),
          Text('Encounter weight', style: FoE.dim(size: 10)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _numField(
                  'ewb-${r.name}',
                  'Gewicht (Gefahr 1)',
                  c.encounterWeightBase,
                  (v) => _update(r, c.copyWith(encounterWeightBase: v)),
                  decimals: 1,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numField(
                  'ewp-${r.name}',
                  '± pro Gefahrstufe',
                  c.encounterWeightPerDanger,
                  (v) => _update(r, c.copyWith(encounterWeightPerDanger: v)),
                  decimals: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Fangschwierigkeit', style: FoE.dim(size: 10)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _numField(
                  'hits-${r.name}',
                  'Ring hits needed',
                  c.catchHits.toDouble(),
                  (v) => _update(r, c.copyWith(catchHits: v.round())),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numField(
                  'catch-${r.name}',
                  'Fang-Fenster',
                  c.catchRate,
                  (v) => _update(r, c.copyWith(catchRate: v)),
                  decimals: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breedTab() => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Text(
        'Two separate clocks per rarity: MATING in the Breeding Hut and '
        'INCUBATING the egg in the Hatchery — the rarer, the longer. '
        'Legendaries cannot be bred.',
        style: FoE.dim(size: 11),
      ),
      const SizedBox(height: 6),
      Text(
        'The stationed workers shorten it through their breeding power = '
        'Σ(breeding stat × role multiplier × level factor). Enter a wished-for '
        'duration on the right and it says how much power the building needs '
        'for it. There is no ceiling; the curve only flattens, so every '
        'further percent costs more power.',
        style: FoE.dim(size: 11),
      ),
      const SizedBox(height: 12),
      _cutScale(),
      const SizedBox(height: 12),
      for (final r in CreatureRarity.values) _breedCard(r),
    ],
  );

  /// The rarity-INDEPENDENT half of the answer: how much power buys which
  /// speed-up. Handy as an at-a-glance ruler, because the cut depends only on
  /// the power, never on the base duration.
  Widget _cutScale() {
    // Spread across the whole range now that nothing stops at −50 %: the point
    // of the ruler is to show how steeply the price climbs at the top end.
    const cuts = [0.25, 0.50, 0.75, 0.90, 0.95];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Power → time saved (the same for every rarity)',
              style: FoE.label(size: 12).copyWith(color: FoE.gold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in cuts)
                _pill(
                  '−${(c * 100).round()} %',
                  // Any base works — the cut is a pure function of power.
                  _fmtPower(breedingPowerForHours(100, 100 * (1 - c))),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breedCard(CreatureRarity r) {
    final c = _cfg[r]!;
    if (!rarityCanBreed(r)) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: FoE.panel(radius: 8),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(r.label,
                  style: FoE.label(size: 14).copyWith(color: FoE.textDim)),
            ),
            Expanded(
              child: Text('— cannot be bred —',
                  style: FoE.dim(size: 12)),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.label, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
          const SizedBox(height: 6),
          _phaseRow(
            '💞 Mating',
            'breed-${r.name}',
            c.breedHours,
            (v) => _update(r, c.copyWith(breedHours: v)),
          ),
          const SizedBox(height: 8),
          _phaseRow(
            '🐣 Incubation',
            'hatch-${r.name}',
            c.hatchHours,
            (v) => _update(r, c.copyWith(hatchHours: v)),
          ),
          const SizedBox(height: 8),
          // What one mating COSTS (user 2026-07-27). Billed in the goods of the
          // era the PARENTS come from, so this one number covers every era —
          // it is the amount of supplies, not a named good.
          Text('💰 Price', style: FoE.dim(size: 11).copyWith(color: FoE.gold)),
          const SizedBox(height: 4),
          _numField(
            'breedgoods-${r.name}',
            'Supplies per mating',
            c.breedGoods,
            (v) => _update(r, c.copyWith(breedGoods: v)),
          ),
          const SizedBox(height: 4),
          Text(
            'Paid in the supplies of the PARENTS\' era (region tier), richest '
            'good first — like healing.',
            style: FoE.dim(size: 10),
          ),
        ],
      ),
    );
  }

  /// One phase of one rarity: its base duration, the wished-for duration, and
  /// the power that wish costs.
  Widget _phaseRow(
    String label,
    String id,
    double baseHours,
    ValueChanged<double> onSet,
  ) {
    final target = _targetHours[id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FoE.dim(size: 11).copyWith(color: FoE.gold)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _numField(id, 'Basisdauer (h)', baseHours, onSet,
                  decimals: 1),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextFormField(
                key: ValueKey('target-$id-$_gen'),
                initialValue: '',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
                decoration: const InputDecoration(
                  labelText: 'Wunschdauer (h)',
                  isDense: true,
                ),
                onChanged: (v) => setState(() {
                  final p = double.tryParse(v);
                  if (p == null) {
                    _targetHours.remove(id);
                  } else {
                    _targetHours[id] = p;
                  }
                }),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  target == null
                      ? 'power needed: —'
                      : 'power needed: '
                          '${_fmtPower(breedingPowerForHours(baseHours, target))}',
                  style: FoE.label(size: 12).copyWith(
                    color: target != null &&
                            breedingPowerForHours(baseHours, target) == null
                        ? Colors.redAccent
                        : FoE.parchment,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A required-power figure. null = the wish is below the hard floor, which is
  /// a real answer ("unmöglich"), not an error state to hide.
  static String _fmtPower(double? p) {
    if (p == null) return 'impossible';
    if (p <= 0) return '0 (no workers needed)';
    if (p >= 100) return p.round().toString();
    final r = (p * 10).round() / 10; // one decimal, no trailing .0
    return r == r.roundToDouble() ? r.round().toString() : r.toString();
  }

  Widget _pill(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: FoE.panelMid,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: FoE.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: FoE.dim(size: 10).copyWith(color: FoE.textMuted)),
        const SizedBox(width: 5),
        Text(value, style: FoE.label(size: 12).copyWith(color: FoE.parchment)),
      ],
    ),
  );

  // ── XP ────────────────────────────────────────────────────
  /// Everything that decides how fast a monster levels (user 2026-07-26). Each
  /// field is followed by what it MEANS: a bare "6 · L^2.5" or "+20 XP/h" says
  /// nothing until you see the hours it costs per level.
  Widget _xpTab() {
    final levels = [1, 5, 10, 20, 40, kCreatureMaxLevel];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'The level curve applies to EVERY monster: XP from level L to L+1 = '
          'factor × L^exponent. The level cap is tied to the eras '
          '(era N = level N×$kLevelsPerEra, max $kCreatureMaxLevel) and is '
          'not set here.',
          style: FoE.dim(size: 11),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: FoE.panel(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Levelkurve',
                  style: FoE.label(size: 14).copyWith(color: FoE.gold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      'xp-factor',
                      'Faktor',
                      _xp.curveFactor,
                      (v) => setState(() => _xp = _xp.copyWith(curveFactor: v)),
                      decimals: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _numField(
                      'xp-exponent',
                      'Exponent',
                      _xp.curveExponent,
                      (v) =>
                          setState(() => _xp = _xp.copyWith(curveExponent: v)),
                      decimals: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _chipLine(
                'XP for the next level',
                [for (final l in levels) ('L$l', '${_xp.xpToNext(l)}')],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: FoE.panel(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('XP pro besiegtem Monster',
                  style: FoE.label(size: 14).copyWith(color: FoE.gold)),
              const SizedBox(height: 2),
              Text(
                'By the enemy\'s LEVEL: factor × level^exponent, summed over the '
                'enemy team and then split across your own group. Fighting is '
                'the main way to level.',
                style: FoE.dim(size: 10),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      'xp-kill-factor',
                      'Faktor',
                      _xp.killFactor,
                      (v) => setState(() => _xp = _xp.copyWith(killFactor: v)),
                      decimals: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _numField(
                      'xp-kill-exponent',
                      'Exponent',
                      _xp.killExponent,
                      (v) =>
                          setState(() => _xp = _xp.copyWith(killExponent: v)),
                      decimals: 2,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _numField(
                      'xp-boss',
                      'Boss ×',
                      _xp.bossMultiplier,
                      (v) =>
                          setState(() => _xp = _xp.copyWith(bossMultiplier: v)),
                      decimals: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _chipLine(
                'XP for ONE enemy of that level',
                [
                  for (final l in levels)
                    ('L$l', _xp.killXp(l).round().toString()),
                ],
              ),
              _chipLine(
                'as a boss',
                [
                  for (final l in levels)
                    ('L$l', _xp.killXp(l, boss: true).round().toString()),
                ],
              ),
              _chipLine(
                'Wins until level-up (same level, 1 enemy, solo)',
                [
                  for (final l in levels)
                    if (l < kCreatureMaxLevel)
                      (
                        'L$l',
                        '${(_xp.xpToNext(l) / _xp.killXp(l)).ceil()}×',
                      ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: FoE.panel(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Training Grounds',
                  style: FoE.label(size: 14).copyWith(color: FoE.gold)),
              const SizedBox(height: 2),
              Text(
                'The higher of the two automatic rates, and the reason the '
                'Training Grounds exists: a trainee produces nothing, so this '
                'is paid for in economy output.',
                style: FoE.dim(size: 10),
              ),
              const SizedBox(height: 6),
              _numField(
                'xp-training',
                'Training (XP/h)',
                _xp.trainingPerHour,
                (v) => setState(() => _xp = _xp.copyWith(trainingPerHour: v)),
                decimals: 1,
              ),
              const SizedBox(height: 8),
              _chipLine(
                'Time per level in training',
                [
                  for (final l in levels)
                    if (l < kCreatureMaxLevel)
                      ('L$l', _fmtHours(
                          _xp.hoursToNextLevel(l, _xp.trainingPerHour))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ── Arbeit: ONE rate for every building with a work post ──
        // User 2026-07-30: "Jedes Gebäude, welches Monster «anstellt» soll EP
        // geben. Jedes Gebäude gibt genau gleich viel EP." This is that number.
        // It replaced the per-building `xp` effect, which paid on eleven era-I
        // buildings and on none of the ~40 later ones.
        Container(
          padding: const EdgeInsets.all(10),
          decoration: FoE.panel(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Arbeit (jedes Gebäude mit Monster-Slots)',
                  style: FoE.label(size: 14).copyWith(color: FoE.gold)),
              const SizedBox(height: 2),
              Text(
                'What a monster earns just for holding a post — the SAME in '
                'every building that stations monsters, whatever it produces. '
                'A trickle, not a route: fighting and the Training Grounds are '
                'the ways to level. Growth per building level should stay '
                'small.',
                style: FoE.dim(size: 10),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      'xp-work',
                      'Arbeit (XP/h, Gebäude Lv 1)',
                      _xp.workPerHour,
                      (v) => setState(() => _xp = _xp.copyWith(workPerHour: v)),
                      decimals: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _numField(
                      'xp-work-growth',
                      'pro Gebäudelevel ×',
                      _xp.workLevelGrowth,
                      (v) => setState(
                          () => _xp = _xp.copyWith(workLevelGrowth: v)),
                      decimals: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // By BUILDING level, not creature level — the one thing that
              // changes this rate.
              _chipLine(
                'XP/h by building level',
                [
                  for (final l in const [1, 5, 10, 15, 24])
                    ('Geb. L$l', _xp.workXpAt(l).toStringAsFixed(1)),
                ],
              ),
              _chipLine(
                'Time per monster level at a Lv 1 building',
                [
                  for (final l in levels)
                    if (l < kCreatureMaxLevel)
                      ('L$l', _fmtHours(
                          _xp.hoursToNextLevel(l, _xp.workXpAt(1)))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Heilung ───────────────────────────────────────────────
  /// The two prices of healing (user 2026-07-26). Both are per point of MISSING
  /// HP, so the tab answers the only question that matters — what a real wound
  /// costs — for a reference monster the author can retune.
  Widget _healTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Healing costs TWO things, both per missing HP: time and goods. HP '
          'never regenerate on their own, so this is the game\'s most frequent '
          'sink — it decides whether a lost fight is a shrug or a lost '
          'afternoon.',
          style: FoE.dim(size: 11),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: FoE.panel(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _numField(
                      'heal-ko',
                      'K.O. factor (on time AND price)',
                      _heal.koMultiplier,
                      (v) => setState(
                          () => _heal = _heal.copyWith(koMultiplier: v)),
                      decimals: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 84,
                    child: TextFormField(
                      key: ValueKey('heal-refhp-$_gen'),
                      initialValue: _refMaxHp.toStringAsFixed(0),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: FoE.label(size: 13)
                          .copyWith(color: FoE.goldBright),
                      decoration: const InputDecoration(
                        labelText: 'Vorschau: Max-HP',
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final p = double.tryParse(v);
                        // A half-typed box keeps the last usable lens instead
                        // of collapsing every row to zero.
                        if (p == null || p <= 0) return;
                        setState(() => _refMaxHp = p);
                      },
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'K.O. 1.0 = going down costs the same as surviving on 1 HP — and '
                  'then there is no reason to retreat. Applies to every '
                  'rarity.',
                  style: FoE.dim(size: 10),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Per rarity, per missing HP — next to it, what that means for a '
          'monster with ${_refMaxHp.toStringAsFixed(0)} max HP: a trial '
          '(−55 %) and a K.O.',
          style: FoE.dim(size: 11),
        ),
        const SizedBox(height: 8),
        for (final r in CreatureRarity.values) _healCard(r),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: FoE.panel(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Which resources',
                  style: FoE.label(size: 14).copyWith(color: FoE.gold)),
              const SizedBox(height: 4),
              Text(
                'You pay in the luxury goods of the MONSTER\'s era, not the '
                'settlement\'s: a monster from region 1 always costs era-1 '
                'goods, one from region 3 the era-3 ones — however far along '
                'you are. A monster\'s era is its species\' tier.',
                style: FoE.dim(size: 11),
              ),
              const SizedBox(height: 6),
              for (var era = 1; era <= kMaxEras; era++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Era $era: ${goodsForEra(era).map((g) => '${g.emoji} ${g.name}').join(' · ')}',
                    style: FoE.dim(size: 10),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'The list is cumulative and billed richest-first, always out of '
                'what you HAVE — never one of each, which is why healing can '
                'never block. Which goods an era brings is maintained in the '
                'goods defs, not here.',
                style: FoE.dim(size: 11),
              ),
              const SizedBox(height: 8),
              Text('Discounts come from buildings',
                  style: FoE.label(size: 12).copyWith(color: FoE.gold)),
              Text(
                'A heal effect (target speed/cost) on the building and a staffed '
                'healer post (medicine) both cut these — together up to '
                '−90 %. You set both on the building.',
                style: FoE.dim(size: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One rarity's two heal prices, with the concrete wound they produce next to
  /// them — a rate per HP means nothing until it is multiplied out.
  Widget _healCard(CreatureRarity r) {
    final c = _cfg[r]!;
    // The trial anchor (docs/balancing.md §4b) and the worst case.
    final trialHp = _refMaxHp * 0.55;
    final trialTime = trialHp * c.healSecondsPerHp;
    final trialGoods = trialHp * c.healGoodsPerHp;
    final koTime = _refMaxHp * c.healSecondsPerHp * _heal.koMultiplier;
    final koGoods = _refMaxHp * c.healGoodsPerHp * _heal.koMultiplier;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.label, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _numField(
                  'healsec-${r.name}',
                  'Seconds per HP',
                  c.healSecondsPerHp,
                  (v) => _update(r, c.copyWith(healSecondsPerHp: v)),
                  decimals: 1,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _numField(
                  'healgoods-${r.name}',
                  'Goods per HP',
                  c.healGoodsPerHp,
                  (v) => _update(r, c.copyWith(healGoodsPerHp: v)),
                  decimals: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _pill('−55 %', '${_fmtHours(trialTime / 3600)} · '
                  '${trialGoods.toStringAsFixed(1)} goods'),
              _pill('K.O.', '${_fmtHours(koTime / 3600)} · '
                  '${koGoods.toStringAsFixed(1)} goods'),
            ],
          ),
        ],
      ),
    );
  }

  static String _fmtHours(double h) {
    if (!h.isFinite) return '∞';
    if (h < 1) return '${(h * 60).round()}m';
    if (h < 48) return '${h.toStringAsFixed(h < 10 ? 1 : 0)}h';
    return '${(h / 24).toStringAsFixed(1)}d';
  }

  Widget _chipLine(String label, List<(String, String)> entries) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FoE.dim(size: 10)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final e in entries) _pill(e.$1, e.$2)],
        ),
      ],
    ),
  );

  Widget _rarityCard(CreatureRarity r) {
    final c = _cfg[r]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.label, style: FoE.label(size: 14).copyWith(color: FoE.gold)),
          const SizedBox(height: 6),
          _catRow('Kampf', r, c, isCombat: true),
          const SizedBox(height: 6),
          _catRow('Civil', r, c, isCombat: false),
        ],
      ),
    );
  }

  Widget _catRow(
    String label,
    CreatureRarity r,
    RarityConfig c, {
    required bool isCombat,
  }) {
    final base = isCombat ? c.combatBase : c.workBase;
    final growth = isCombat ? c.combatGrowth : c.workGrowth;
    final maxBase = isCombat ? c.combatMaxBase : c.workMaxBase;
    final maxGrowth = isCombat ? c.combatMaxGrowth : c.workMaxGrowth;
    RarityConfig setBase(double v) =>
        isCombat ? c.copyWith(combatBase: v) : c.copyWith(workBase: v);
    RarityConfig setGrowth(double v) =>
        isCombat ? c.copyWith(combatGrowth: v) : c.copyWith(workGrowth: v);
    RarityConfig setMaxBase(double v) =>
        isCombat ? c.copyWith(combatMaxBase: v) : c.copyWith(workMaxBase: v);
    RarityConfig setMaxGrowth(double v) => isCombat
        ? c.copyWith(combatMaxGrowth: v)
        : c.copyWith(workMaxGrowth: v);
    final tag = isCombat ? 'c' : 'w';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FoE.dim(size: 11).copyWith(color: FoE.gold)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _numField('base-$tag-${r.name}', 'Base', base,
                  (v) => _update(r, setBase(v))),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _numField('grow-$tag-${r.name}', 'Growth', growth,
                  (v) => _update(r, setGrowth(v)), decimals: 1),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _numField('maxb-$tag-${r.name}', 'Max Base', maxBase,
                  (v) => _update(r, setMaxBase(v))),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _numField('maxg-$tag-${r.name}', 'Max Growth', maxGrowth,
                  (v) => _update(r, setMaxGrowth(v)), decimals: 1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numField(
    String id,
    String label,
    double value,
    ValueChanged<double> onSet, {
    int decimals = 0,
  }) => TextFormField(
    key: ValueKey('$id-$_gen'),
    initialValue: value.toStringAsFixed(decimals),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
    decoration: InputDecoration(labelText: label, isDense: true),
    onChanged: (v) {
      final p = double.tryParse(v);
      if (p != null) onSet(p);
    },
  );

  Widget _saveButton() => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: _saving ? null : _save,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: FoE.btn(active: true),
        alignment: Alignment.center,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FoE.goldBright,
                ),
              )
            : Text(
                'Save',
                style: FoE.label(size: 14).copyWith(color: Colors.white),
              ),
      ),
    ),
  );
}
