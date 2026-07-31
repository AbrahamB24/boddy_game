import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/path_node.dart';
import '../../creatures/models/species_def.dart' show SpeciesDef, kSpeciesDefs;
import '../../creatures/services/capture_math.dart' show eligibleSpecies;
import '../../creatures/services/overworld_path.dart'
    show enemyCountForBattle, enemyLevelForBattle, eraForBattle;
import '../services/game_defs_controller.dart';
import 'dev_theme.dart';

// ── Welche Monster stehen im Pfad? (user 2026-07-30) ────────
// "Monster im Pfad, bitte nach ära unterteilen in Tabs oben. Zudem will ich dort
// einen Button haben, welcher die Monster neu würfelt."
//
// The sheet used to list every species across the whole path in one column,
// which answered "is anything unused" and nothing else. A REGION is the unit
// that matters: each one draws from its own pool, and "Verdant Hollow leans on
// three of its eight monsters" is a content decision — invisible in a global
// tally, obvious per era.
//
// The dice lives here rather than in the node form because this is the only
// screen that can judge its result: roll, and the bars under your thumb move.
class PathSpeciesSheet extends StatefulWidget {
  const PathSpeciesSheet({super.key});

  @override
  State<PathSpeciesSheet> createState() => _PathSpeciesSheetState();
}

class _PathSpeciesSheetState extends State<PathSpeciesSheet> {
  final _rng = math.Random();
  bool _busy = false;
  String? _note;

  /// The eras the path actually has nodes in — not every authored era, so a
  /// truncated path (kLastPathBattle) shows only what exists.
  List<int> get _eras {
    final out = <int>{
      for (final n in pathNodesInOrder()) eraForBattle(n.order),
    }.toList()
      ..sort();
    return out;
  }

  List<PathNode> _nodesOf(int era) =>
      [for (final n in pathNodesInOrder()) if (eraForBattle(n.order) == era) n];

  AreaDef? _areaOf(int era) {
    for (final a in kAreaDefs.values) {
      if (a.battleStage == era) return a;
    }
    return null;
  }

  /// The monsters a region may field — its OWN pool, the same one the game
  /// draws from for a node with no authored enemies.
  List<SpeciesDef> _poolOf(int era) {
    final area = _areaOf(era);
    if (area == null) return const [];
    return eligibleSpecies(area, includeLegendary: false);
  }

  /// Re-rolls every regular fight of [era].
  ///
  /// Three deliberate limits:
  ///  • the BOSS is left alone. A region's boss is its identity (AreaDef
  ///    .bossSpeciesId), not something to shuffle.
  ///  • the COUNT per node is what the game would have spawned anyway
  ///    (enemyCountForBattle) — so a node that had no authored enemies gains
  ///    exactly the fight it already had, now explicit and re-rollable.
  ///  • the node's TOTAL level is kept and re-spread over the new pack, so a
  ///    hand-tuned difficulty curve survives a shuffle of names.
  Future<void> _reroll(int era) async {
    final pool = _poolOf(era);
    if (pool.isEmpty) {
      setState(() => _note = 'Region ${_roman(era)} hat keinen Monster-Pool.');
      return;
    }
    setState(() {
      _busy = true;
      _note = null;
    });
    final ids = [for (final s in pool) s.id];
    final changed = <PathNode>[];
    // A RUNNING TALLY across the whole region (user 2026-07-30: "Die Verteilung
    // soll etwa gleichmässig sein"). Rolling each node in isolation is uniform
    // random, and uniform random clumps: over seventeen fights it reliably
    // leaves a monster unused while another shows up five times. Every node is
    // drawn from the least-used end of what this roll has already placed, so the
    // region comes out flat.
    //
    // Starts at zero rather than from the region's current distribution — this
    // is a re-roll, so what stood here a moment ago is not a claim on anything.
    final usage = <String, int>{for (final id in ids) id: 0};
    for (final n in _nodesOf(era)) {
      if (n.isBoss) continue;
      final count = n.enemies.isNotEmpty
          ? n.enemies.length
          : enemyCountForBattle(n.order);
      // The node's TOTAL level is what survives a re-roll (user 2026-07-30:
      // "den Gesamtlevel ... einigermassen gleichmässig auf alle Monster
      // verteilt"), re-spread over whatever the dice produced. A node nobody
      // authored is worth what the formula would have spawned there.
      final total = n.enemies.isNotEmpty
          ? n.enemies.fold<int>(0, (s, e) => s + e.level)
          : enemyLevelForBattle(n.order) * count;
      final levels = spreadLevels(total: total, count: count, rng: _rng);
      final rolled = rollPathEnemies(
        poolIds: ids,
        count: count,
        keepLevels: levels,
        rng: _rng,
        usage: usage,
      );
      for (final e in rolled) {
        usage[e.speciesId] = (usage[e.speciesId] ?? 0) + 1;
      }
      changed.add(n.copyWith(enemies: rolled));
    }
    try {
      await GameDefsController().savePathNodes(changed);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = '${changed.length} Kämpfe neu gewürfelt '
            '(Boss unverändert).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = 'Speichern fehlgeschlagen: $e';
      });
    }
  }

  static String _roman(int era) => const [
    '',
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
  ].elementAtOrNull(era) ?? '$era';

  @override
  Widget build(BuildContext context) {
    final eras = _eras;
    if (eras.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Keine Knoten im Pfad.', style: FoE.dim(size: 12)),
      );
    }
    return DefaultTabController(
      length: eras.length,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Monster im Pfad', style: FoE.title(size: 15)),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FoE.goldBright,
                    ),
                  ),
              ],
            ),
          ),
          TabBar(
            isScrollable: eras.length > 4,
            labelColor: FoE.gold,
            unselectedLabelColor: FoE.textDim,
            indicatorColor: FoE.gold,
            tabs: [for (final e in eras) Tab(text: 'Ära ${_roman(e)}')],
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(_note!, style: FoE.dim(size: 11)),
            ),
          Expanded(
            child: TabBarView(
              children: [for (final e in eras) _eraTab(e)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _eraTab(int era) {
    final nodes = _nodesOf(era);
    final dist = pathSpeciesDistribution(nodes);
    final placed = nodes.fold<int>(0, (a, n) => a + n.enemies.length);
    final pool = _poolOf(era);
    // Sorted by how much of the region a species occupies.
    final used = dist.entries.toList()
      ..sort((a, b) {
        final byTotal = b.value.total.compareTo(a.value.total);
        return byTotal != 0 ? byTotal : _nameOf(a.key).compareTo(_nameOf(b.key));
      });
    // UNUSED is asked of the REGION's pool, not of every species in the game:
    // "Verdant Hollow never fields three of its own eight" is the finding; "era
    // VIII's monsters are missing from era I" is noise.
    final unused = pool.where((s) => !dist.containsKey(s.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final maxTotal = used.isEmpty ? 1 : used.first.value.total;
    final area = _areaOf(era);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        Text(
          '${area?.name ?? 'Region $era'} · ${nodes.length} Knoten · '
          '$placed Gegner · ${dist.length}/${pool.length} Arten benutzt',
          style: FoE.dim(size: 11),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _busy ? null : () => _reroll(era),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: FoE.btn(active: !_busy),
            child: Text(
              '🎲 Monster dieser Region neu würfeln',
              style: FoE.label(size: 13).copyWith(
                color: _busy ? FoE.textDim : Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Aus dem Pool der Region, mit der Gegnerzahl, die der Kampf ohnehin '
          'hätte. Boss und Gesamtlevel der Knoten bleiben.',
          style: FoE.dim(size: 10),
        ),
        const SizedBox(height: 14),
        if (used.isEmpty)
          Text(
            'Kein Kampf dieser Region hat gesetzte Gegner — sie werden aus dem '
            'Pool erzeugt. Würfle einmal, um sie festzuschreiben.',
            style: FoE.dim(size: 11),
          )
        else
          for (final e in used)
            _row(e.key, e.value.total, e.value.nodes, maxTotal),
        if (unused.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Kommt in dieser Region nicht vor (${unused.length})',
            style: FoE.label(size: 12).copyWith(color: Colors.redAccent),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in unused)
                Text(
                  s.name,
                  // Rarity in the ink, here too — an unused LEGENDARY and an
                  // unused common are not the same omission.
                  style: FoE.label(size: 11)
                      .copyWith(color: speciesNameColor(s.id)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _nameOf(String speciesId) => kSpeciesDefs[speciesId]?.name ?? speciesId;

  Widget _row(String speciesId, int total, int nodes, int maxTotal) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            _nameOf(speciesId),
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 12)
                .copyWith(color: speciesNameColor(speciesId)),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: maxTotal == 0 ? 0 : total / maxTotal,
              minHeight: 8,
              backgroundColor: FoE.panelDark,
              valueColor: AlwaysStoppedAnimation(speciesNameColor(speciesId)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 74,
          child: Text(
            '$total× · $nodes Knoten',
            textAlign: TextAlign.right,
            style: FoE.dim(size: 10),
          ),
        ),
      ],
    ),
  );
}
