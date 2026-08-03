import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../models/ability_def.dart';
import '../models/species_def.dart';
import '../services/creature_defs_service.dart';
import '../services/species_balance.dart';

/// The species-vs-species balancing matrix (dev tool, user spec 2026-07-21):
/// rows = attacker (player side), columns = defender. Each cell runs
/// [kMatrixRuns] seeded 1v1 auto-battles at the chosen equal level and shows
/// the row species' win rate; a red corner flags fights outside the 3–10
/// total-actions band. Tap a cell for details — including the level the loser
/// needs to reach 50%. "Tune" proposes ONE previewable adjustment step.
///
/// Embedded as a mode of the Balance simulator screen; all computation lives
/// in services/species_balance.dart.
class SpeciesMatrixView extends StatefulWidget {
  const SpeciesMatrixView({super.key});

  @override
  State<SpeciesMatrixView> createState() => _SpeciesMatrixViewState();
}

class _SpeciesMatrixViewState extends State<SpeciesMatrixView> {
  int _level = 10;
  bool _running = false;
  int _done = 0;
  int _total = 0;

  /// Cell results keyed 'aId|bId'.
  final Map<String, PairingResult> _cells = {};
  List<SpeciesDef> _order = const [];

  Future<void> _run() async {
    final species = kSpeciesDefs.values.toList()
      ..sort((a, b) {
        final byRarity = a.rarity.index.compareTo(b.rarity.index);
        return byRarity != 0 ? byRarity : a.name.compareTo(b.name);
      });
    setState(() {
      _running = true;
      _cells.clear();
      _order = species;
      _done = 0;
      _total = species.length * species.length;
    });
    for (final a in species) {
      for (final b in species) {
        if (!mounted || !_running) return;
        _cells['${a.id}|${b.id}'] = simulatePairing(a, b, level: _level);
        _done++;
        // Yield to the UI every cell — 100 fights per cell is enough work per
        // frame that the progress bar would otherwise freeze.
        setState(() {});
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    if (kSpeciesDefs.isEmpty) {
      return Center(
        child: Text(
          'No species defined yet — author some in the Species tab first.',
          style: FoE.dim(size: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _controls(),
        const SizedBox(height: 8),
        if (_running)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(
              value: _total == 0 ? null : _done / _total,
              color: FoE.gold,
              backgroundColor: FoE.panelDark,
            ),
          ),
        if (_order.isNotEmpty) Expanded(child: _matrix()),
        if (_order.isEmpty)
          Expanded(
            child: Center(
              child: Text(
                '▶️ Run fights every species against every other — '
                '$kMatrixRuns seeded 1v1s per pairing, equal level, real '
                'engine (abilities, buffs, AP banking).',
                textAlign: TextAlign.center,
                style: FoE.dim(size: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _controls() => Row(
        children: [
          Text('Level', style: FoE.dim(size: 11)),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _level,
            dropdownColor: FoE.panelMid,
            style: FoE.value(size: 12),
            items: [
              for (final l in const [5, 10, 15, 20, 30, 40, 50, 60, 75])
                DropdownMenuItem(value: l, child: Text('$l')),
            ],
            onChanged: _running
                ? null
                : (v) => setState(() => _level = v ?? _level),
          ),
          const Spacer(),
          if (_running)
            TextButton(
              onPressed: () => setState(() => _running = false),
              child: Text('Stop', style: FoE.label(size: 12)),
            )
          else ...[
            TextButton(
              onPressed: _cells.isEmpty ? null : _proposeTune,
              child: Text('⚖ Tune', style: FoE.label(size: 12)),
            ),
            ElevatedButton(
              onPressed: _run,
              style: ElevatedButton.styleFrom(
                backgroundColor: FoE.gold,
                foregroundColor: Colors.black,
              ),
              child: Text('▶️ Run ($_doneLabel)'),
            ),
          ],
        ],
      );

  String get _doneLabel {
    final n = kSpeciesDefs.length;
    return '$n×$n · $kMatrixRuns runs';
  }

  // ── The table ─────────────────────────────────────────────
  Widget _matrix() {
    const cell = 54.0;
    const header = 76.0;
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: header,
                  child: Text('atk ↓ · def →', style: FoE.dim(size: 8)),
                ),
                for (final b in _order)
                  SizedBox(
                    width: cell,
                    child: Text(
                      b.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: FoE.dim(size: 8).copyWith(color: b.element.color),
                    ),
                  ),
              ],
            ),
            for (final a in _order)
              Row(
                children: [
                  SizedBox(
                    width: header,
                    child: Text(
                      '${a.name}\n${a.rarity.label}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.dim(size: 8).copyWith(color: a.element.color),
                    ),
                  ),
                  for (final b in _order) _cellWidget(a, b, cell),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cellWidget(SpeciesDef a, SpeciesDef b, double size) {
    final r = _cells['${a.id}|${b.id}'];
    if (r == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: Text('…', style: FoE.dim(size: 9))),
      );
    }
    final win = r.aWinRate;
    // Colour: blue = row wins, pink = row loses, dark = balanced. Mirror
    // matches read ~50% by construction.
    final off = (win - 0.5).abs() * 2; // 0 balanced … 1 extreme
    final base = win >= 0.5 ? FoE.accentBlue : FoE.danger;
    return GestureDetector(
      onTap: () => _showCell(a, b, r),
      child: Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(1),
        decoration: ShapeDecoration(color: Color.lerp(FoE.panelDark, base, 0.15 + off * 0.75), shape: FoE.facet(radius: 4)),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${(win * 100).round()}%',
                style: FoE.value(size: 11),
              ),
            ),
            // Length violations: red corner badge with the offending count.
            if (r.lengthViolated)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: ShapeDecoration(color: FoE.danger, shape: FoE.facet(radius: 4)),
                  child: Text(
                    r.tooShort > 0 && r.tooLong > 0
                        ? '≶'
                        : (r.tooShort > 0 ? '<3' : '>10'),
                    style: FoE.dim(size: 7).copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Cell detail (incl. the 50%-level answer) ──────────────
  Future<void> _showCell(SpeciesDef a, SpeciesDef b, PairingResult r) async {
    int? levelNeeded;
    var levelComputed = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: FoE.panelMid,
          title: Text('${a.name} vs ${b.name}', style: FoE.title(size: 14)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${a.name} wins ${(r.aWinRate * 100).round()}% of '
                  '${r.runs} fights at level $_level',
                  style: FoE.label(size: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  'Fight length: ${r.minActions}–${r.maxActions} actions '
                  '(median ${r.medianActions.toStringAsFixed(0)}) · '
                  'target $kMinFightActions–$kMaxFightActions\n'
                  '${r.tooShort} too short · ${r.tooLong} too long',
                  style: FoE.dim(size: 11).copyWith(
                    color: r.lengthViolated ? FoE.danger : FoE.textDim,
                  ),
                ),
                const SizedBox(height: 8),
                _usesBlock(a.name, r.aAbilityUses),
                _usesBlock(b.name, r.bAbilityUses),
                const SizedBox(height: 8),
                if ((r.aWinRate - 0.5).abs() < 0.001)
                  Text('Already even.', style: FoE.dim(size: 11))
                else if (!levelComputed)
                  TextButton(
                    onPressed: () {
                      final loser = r.aWinRate < 0.5 ? a : b;
                      final winner = r.aWinRate < 0.5 ? b : a;
                      final lvl = levelToWinHalf(
                        loser,
                        winner,
                        baseLevel: _level,
                      );
                      setLocal(() {
                        levelNeeded = lvl;
                        levelComputed = true;
                      });
                    },
                    child: Text(
                      'Compute level for the loser to reach 50%',
                      style: FoE.label(size: 12),
                    ),
                  )
                else
                  Text(
                    levelNeeded == null
                        ? '${(r.aWinRate < 0.5 ? a : b).name} never reaches '
                            '50% — not even at level 75 (hard counter).'
                        : '${(r.aWinRate < 0.5 ? a : b).name} needs level '
                            '$levelNeeded (vs level $_level) for ≥50%.',
                    style: FoE.label(size: 12).copyWith(color: FoE.gold),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: FoE.dim(size: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usesBlock(String name, Map<String, int> uses) {
    if (uses.isEmpty) {
      return Text(
        '$name: no abilities used (basic attacks only)',
        style: FoE.dim(size: 10),
      );
    }
    final parts = uses.entries
        .map((e) => '${kAbilityDefs[e.key]?.name ?? e.key} ×${e.value}')
        .join(', ');
    return Text('$name: $parts', style: FoE.dim(size: 10));
  }

  // ── Auto-tune: propose → preview diff → apply ─────────────
  Future<void> _proposeTune() async {
    final changes = proposeTuning(
      results: _cells.values.toList(),
      species: kSpeciesDefs,
      abilities: kAbilityDefs,
    );
    if (!mounted) return;
    if (changes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to tune — matrix looks good.')),
      );
      return;
    }
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelMid,
        title: Text(
          'Tuning proposal (${changes.length})',
          style: FoE.title(size: 14),
        ),
        content: SizedBox(
          width: 380,
          height: 320,
          child: ListView(
            children: [
              for (final c in changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.kind == 'species' ? '🐾' : '✨'} ${c.id} · '
                        '${c.field}: ${c.oldValue} → ${c.newValue}',
                        style: FoE.label(size: 12),
                      ),
                      Text(c.reason, style: FoE.dim(size: 10)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Discard', style: FoE.dim(size: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Apply to defs',
              style: FoE.label(size: 12).copyWith(color: FoE.gold),
            ),
          ),
        ],
      ),
    );
    if (apply != true || !mounted) return;
    final svc = CreatureDefsService();
    for (final c in changes) {
      if (c.species != null) {
        kSpeciesDefs[c.species!.id] = c.species!;
        await svc.upsertSpeciesDef(c.species!);
      }
      if (c.ability != null) {
        kAbilityDefs[c.ability!.id] = c.ability!;
        await svc.upsertAbilityDef(c.ability!);
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${changes.length} changes applied — run the matrix '
            'again to measure the effect.'),
      ),
    );
  }
}
