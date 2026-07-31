import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/ability_def.dart';
import '../../creatures/models/combatant.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/services/combat_engine.dart';
import '../../creatures/services/combat_tuning.dart';

// Dev Mode ▸ Combat Lab (user request 2026-07-17): tune the attack-vs-defense
// damage formula with live sliders, and simulate a fight between two monsters
// you pick. Phone-first — one vertical scroll, every control finger-sized,
// every number explained in plain words.
//
// The duel runs the REAL CombatEngine, so it honours the dials above it: move
// a slider, run the duel again, see the difference immediately.
class CombatLabScreen extends StatefulWidget {
  const CombatLabScreen({super.key});

  @override
  State<CombatLabScreen> createState() => _CombatLabScreenState();
}

class _CombatLabScreenState extends State<CombatLabScreen> {
  final _tuning = CombatTuning();

  // Working copies of the dials — applied to the live game only on "Apply".
  late double _damageScale = _tuning.damageScale;
  late double _defenseWeight = _tuning.defenseWeight;

  // The formula preview's sample fighters (so the effect is concrete).
  double _sampleAtk = 100;
  double _sampleDef = 100;

  // Duel picks.
  SpeciesDef? _speciesA;
  SpeciesDef? _speciesB;
  int _levelA = 10;
  int _levelB = 10;
  _DuelReport? _duel;

  bool get _dirty =>
      _damageScale != _tuning.damageScale ||
      _defenseWeight != _tuning.defenseWeight;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        _intro(),
        const SizedBox(height: 16),
        _formulaCard(),
        const SizedBox(height: 16),
        _duelCard(),
      ],
    );
  }

  // ── Intro ───────────────────────────────────────────────────
  Widget _intro() => _card(
    accent: FoE.accentBlue,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Combat Lab', style: FoE.title(size: 16)),
        const SizedBox(height: 6),
        Text(
          'Two tools:\n'
          '1) Tune how hard hits land and how much defense blocks — the '
          'exact formula is shown and updates as you drag.\n'
          '2) Pick two monsters and watch them fight, to see the tuning in '
          'action.\n\n'
          'Changes here affect the WHOLE game once you press Apply.',
          style: FoE.dim(size: 12),
        ),
      ],
    ),
  );

  // ── Formula card ────────────────────────────────────────────
  Widget _formulaCard() {
    // A basic hit (move power = 40 = the basic-attack power) for the sample
    // ATK/DEF, computed with the WORKING dials so the preview reacts live.
    final dmg = _sampleHitDamage();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('① Damage formula', style: FoE.title(size: 14)),
          const SizedBox(height: 10),

          // The formula, in plain terms.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FoE.panelDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FoE.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Damage per hit =',
                  style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                ),
                const SizedBox(height: 4),
                Text(
                  '(Power ÷ 40) × ATK × ATK ÷ (ATK + DEF × w) × scale + 2',
                  style: FoE.label(size: 12).copyWith(color: FoE.parchment),
                ),
                const SizedBox(height: 8),
                Text(
                  '• Power — the move\'s strength (a basic attack = 40)\n'
                  '• ATK — the attacker\'s Attack stat\n'
                  '• DEF — the defender\'s Defense stat\n'
                  '• w = Defense weight (the slider below)\n'
                  '• scale = Damage scale (the slider below)\n'
                  '• On top of this: same-type ×1.5, type advantage ×2, '
                  'critical ×1.5, and a small random 0.85–1.0.\n'
                  '• Safety limit: one hit never removes more than '
                  '${(CombatEngine.kMaxHitHpFraction * 100).round()}% of the '
                  'target\'s HP — a one-shot from full health is impossible.',
                  style: FoE.dim(size: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Damage scale.
          _slider(
            label: '⚡ Damage scale',
            value: _damageScale,
            min: 0.1,
            max: 1.5,
            help:
                'The overall power of every hit. Higher = shorter, deadlier '
                'fights. Calibrated default: '
                '${CombatTuning.kDefaultDamageScale.toStringAsFixed(2)}.',
            onChanged: (v) => setState(() => _damageScale = v),
          ),
          const SizedBox(height: 14),

          // Defense weight.
          _slider(
            label: '🛡 Defense weight',
            value: _defenseWeight,
            min: 0.0,
            max: 3.0,
            help:
                'How much Defense blocks. 1.0 = balanced. Above 1, defense '
                'matters more and hits get softer. Below 1, attack wins and '
                'hits get harder. Calibrated default: '
                '${CombatTuning.kDefaultDefenseWeight.toStringAsFixed(2)}.',
            onChanged: (v) => setState(() => _defenseWeight = v),
          ),
          const SizedBox(height: 16),

          // Live example.
          Text(
            'Try it: one basic hit, attacker vs. defender',
            style: FoE.label(size: 12).copyWith(color: FoE.gold),
          ),
          const SizedBox(height: 8),
          _sampleStepper(
            '⚔ Attacker ATK',
            _sampleAtk,
            (v) => setState(() => _sampleAtk = v),
          ),
          const SizedBox(height: 8),
          _sampleStepper(
            '🛡 Defender DEF',
            _sampleDef,
            (v) => setState(() => _sampleDef = v),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FoE.panelMid,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FoE.borderGold),
            ),
            child: Text(
              '→ ${dmg.round()} damage per basic hit\n'
              '(before type/crit/random; those can up to ~4.5× it)',
              style: FoE.value(size: 14).copyWith(color: FoE.goldBright),
            ),
          ),
          const SizedBox(height: 16),

          // Apply / reset.
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  _dirty ? '✔ Apply to game' : 'Applied',
                  active: _dirty,
                  onTap: _dirty ? _apply : null,
                ),
              ),
              const SizedBox(width: 10),
              _actionBtn('↺ Reset', active: false, onTap: _resetDials),
            ],
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Not applied yet — the game still uses the old values. The '
                'duel below already previews these new ones.',
                style: FoE.dim(size: 10).copyWith(color: FoE.gold),
              ),
            ),
        ],
      ),
    );
  }

  /// One basic hit with the WORKING dials (not the applied ones), so the
  /// preview and the duel below reflect what you're dragging. Mirrors
  /// CombatEngine._rollDamage's deterministic core (no crit/type/random).
  double _sampleHitDamage() {
    const power = 40.0; // basic attack
    final atk = _sampleAtk;
    final def = math.max(1.0, _sampleDef) * _defenseWeight;
    return (power / 40) * atk * (atk / (atk + def)) * _damageScale + 2;
  }

  Future<void> _apply() async {
    final err = await _tuning.save(
      damageScale: _damageScale,
      defenseWeight: _defenseWeight,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? '✔ Applied to the whole game.')),
    );
  }

  Future<void> _resetDials() async {
    await _tuning.resetToDefaults();
    if (!mounted) return;
    setState(() {
      _damageScale = _tuning.damageScale;
      _defenseWeight = _tuning.defenseWeight;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('↺ Back to the calibrated defaults.')),
    );
  }

  // ── Duel card ───────────────────────────────────────────────
  Widget _duelCard() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('② Duel simulator', style: FoE.title(size: 14)),
        const SizedBox(height: 4),
        Text(
          'Pick two monsters and fight them. Uses full-strength stats (no '
          'wild handicap) and the dials above, so it\'s a fair "who would '
          'win" test.',
          style: FoE.dim(size: 11),
        ),
        const SizedBox(height: 12),
        _fighterPicker('🟦 Monster A', _speciesA, _levelA, isA: true),
        const SizedBox(height: 6),
        Center(
          child: Text('VS', style: FoE.title(size: 15).copyWith(color: FoE.gold)),
        ),
        const SizedBox(height: 6),
        _fighterPicker('🟥 Monster B', _speciesB, _levelB, isA: false),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                '⚔ Fight once',
                active: _speciesA != null && _speciesB != null,
                onTap: _speciesA != null && _speciesB != null
                    ? _fightOnce
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionBtn(
                '📊 Simulate 100×',
                active: _speciesA != null && _speciesB != null,
                onTap: _speciesA != null && _speciesB != null
                    ? _simulateMany
                    : null,
              ),
            ),
          ],
        ),
        if (_duel != null) ...[
          const SizedBox(height: 14),
          _duelResult(_duel!),
        ],
      ],
    ),
  );

  Widget _fighterPicker(
    String label,
    SpeciesDef? picked,
    int level, {
    required bool isA,
  }) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: FoE.panelDark,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: isA ? FoE.accentBlue : FoE.danger),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FoE.label(size: 12).copyWith(color: FoE.gold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickSpecies(isA),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: FoE.btn(),
            child: Text(
              picked == null
                  ? 'Tap to choose a monster'
                  : '${picked.element.emoji} ${picked.name} · ${picked.rarity.label}',
              style: FoE.label(size: 13).copyWith(
                color: picked == null ? FoE.textDim : FoE.parchment,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _levelStepper(level, (v) => setState(() {
          if (isA) {
            _levelA = v;
          } else {
            _levelB = v;
          }
        })),
      ],
    ),
  );

  Widget _levelStepper(int level, ValueChanged<int> onChanged) => Row(
    children: [
      Text('Level', style: FoE.dim(size: 12)),
      const Spacer(),
      _stepBtn('−', () => onChanged((level - 1).clamp(1, kCreatureMaxLevel))),
      Container(
        width: 44,
        alignment: Alignment.center,
        child: Text(
          '$level',
          style: FoE.value(size: 15).copyWith(color: FoE.goldBright),
        ),
      ),
      _stepBtn('+', () => onChanged((level + 1).clamp(1, kCreatureMaxLevel))),
    ],
  );

  Future<void> _pickSpecies(bool isA) async {
    final all = kSpeciesDefs.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final chosen = await showModalBottomSheet<SpeciesDef>(
      context: context,
      backgroundColor: FoE.panelDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Choose ${isA ? 'Monster A' : 'Monster B'}',
                style: FoE.title(size: 15),
              ),
            ),
            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'No species defined yet — create some in the Species tab.',
                  style: FoE.dim(size: 12),
                ),
              ),
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: all.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final s = all[i];
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: FoE.panel(radius: 8),
                      child: Row(
                        children: [
                          Text(
                            s.element.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.name,
                              style: FoE.label(size: 13),
                            ),
                          ),
                          Text(
                            s.rarity.label,
                            style: FoE.dim(size: 11).copyWith(
                              color: s.rarity.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      if (isA) {
        _speciesA = chosen;
      } else {
        _speciesB = chosen;
      }
    });
  }

  Widget _duelResult(_DuelReport r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FoE.panelMid,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FoE.borderGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.headline, style: FoE.title(size: 14).copyWith(color: FoE.goldBright)),
          const SizedBox(height: 6),
          Text(r.detail, style: FoE.dim(size: 12)),
          if (r.log.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Blow by blow:', style: FoE.label(size: 11).copyWith(color: FoE.gold)),
            const SizedBox(height: 4),
            for (final line in r.log)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $line', style: FoE.dim(size: 10)),
              ),
          ],
        ],
      ),
    );
  }

  // ── Duel engine ─────────────────────────────────────────────
  // Full-quality (mean-gene) combatant: species stat curve at [level], no
  // wild handicap and no boss bonus — a straight species-vs-species test.
  Combatant _fighter(SpeciesDef sp, int level, String id, bool player) {
    final stage = level >= sp.evoLevel2
        ? 2
        : level >= sp.evoLevel1
        ? 1
        : 0;
    final stats = {
      for (final s in CreatureStat.values)
        s: math.max(1, (() {
          final c = sp.statCurve(s);
          return (c.baseAt(stage) + c.growth * (level - 1)).round();
        })()),
    };
    return Combatant(
      id: id,
      name: sp.stageAt(stage).name,
      element: sp.element,
      rarity: sp.rarity,
      isPlayerSide: player,
      level: level,
      stats: stats,
      abilities: [
        for (final sa in sp.abilitiesAt(stage))
          if (kAbilityDefs[sa.abilityId] != null) kAbilityDefs[sa.abilityId]!,
      ],
    );
  }

  /// One duel, [seed]-deterministic. Returns the outcome plus a short log.
  ({CombatOutcome outcome, int actions, List<String> log}) _runDuel(int seed) {
    final engine = CombatEngine(
      players: [_fighter(_speciesA!, _levelA, 'A', true)],
      enemies: [_fighter(_speciesB!, _levelB, 'B', false)],
      rng: math.Random(seed),
    );
    final log = <String>[];
    var actions = 0;
    while (engine.outcome == null && actions < 300) {
      engine.performAutoAction();
      if (engine.lastAction.isNotEmpty &&
          (log.isEmpty || log.last != engine.lastAction)) {
        log.add(engine.lastAction);
      }
      actions++;
    }
    engine.dispose();
    return (
      outcome: engine.outcome ?? CombatOutcome.fled,
      actions: actions,
      log: log,
    );
  }

  void _fightOnce() {
    final r = _runDuel(42);
    final aWon = r.outcome == CombatOutcome.victory;
    final winner = aWon ? _speciesA! : _speciesB!;
    setState(() {
      _duel = _DuelReport(
        headline: '🏆 ${winner.name} wins!',
        detail:
            '${_speciesA!.name} (Lv $_levelA) vs ${_speciesB!.name} '
            '(Lv $_levelB) — decided in ${r.actions} actions. '
            'Uses the CURRENT dials shown above.',
        log: r.log.length > 14 ? r.log.sublist(r.log.length - 14) : r.log,
      );
    });
  }

  void _simulateMany() {
    const runs = 100;
    var aWins = 0;
    var totalActions = 0;
    for (var i = 0; i < runs; i++) {
      final r = _runDuel(i);
      if (r.outcome == CombatOutcome.victory) aWins++;
      totalActions += r.actions;
    }
    final aPct = (aWins / runs * 100).round();
    setState(() {
      _duel = _DuelReport(
        headline: '📊 ${_speciesA!.name} wins $aPct% of 100 fights',
        detail:
            '${_speciesA!.name} (Lv $_levelA) $aWins  ·  '
            '${_speciesB!.name} (Lv $_levelB) ${runs - aWins}.\n'
            'Average length: ${(totalActions / runs).round()} actions. '
            '50% ≈ an even match; far from 50% means one is stronger at '
            'these levels.',
        log: const [],
      );
    });
  }

  // ── Small shared widgets ────────────────────────────────────
  Widget _card({required Widget child, Color accent = FoE.borderGold}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: FoE.panel(radius: 12, overrideBorder: accent),
        child: child,
      );

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String help,
    required ValueChanged<double> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(label, style: FoE.label(size: 13).copyWith(color: FoE.gold)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: FoE.panelDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: FoE.borderGold),
            ),
            child: Text(
              value.toStringAsFixed(2),
              style: FoE.value(size: 14).copyWith(color: FoE.goldBright),
            ),
          ),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: ((max - min) / 0.05).round(),
        activeColor: FoE.gold,
        onChanged: onChanged,
      ),
      Text(help, style: FoE.dim(size: 10)),
    ],
  );

  Widget _sampleStepper(String label, double value, ValueChanged<double> onChanged) =>
      Row(
        children: [
          Expanded(child: Text(label, style: FoE.dim(size: 12))),
          _stepBtn('−', () => onChanged((value - 10).clamp(1, 999))),
          Container(
            width: 52,
            alignment: Alignment.center,
            child: Text(
              value.round().toString(),
              style: FoE.value(size: 14).copyWith(color: FoE.parchment),
            ),
          ),
          _stepBtn('+', () => onChanged((value + 10).clamp(1, 999))),
        ],
      );

  Widget _stepBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: FoE.btn(),
      child: Text(label, style: FoE.title(size: 18).copyWith(color: FoE.gold)),
    ),
  );

  Widget _actionBtn(String label, {required bool active, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            alignment: Alignment.center,
            decoration: FoE.btn(active: active),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: FoE.label(size: 13).copyWith(
                color: active ? Colors.white : FoE.parchment,
              ),
            ),
          ),
        ),
      );
}

class _DuelReport {
  final String headline;
  final String detail;
  final List<String> log;
  const _DuelReport({
    required this.headline,
    required this.detail,
    required this.log,
  });
}
