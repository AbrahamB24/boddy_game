import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/path_node.dart';
import '../../creatures/models/species_def.dart' show kSpeciesDefs;
import '../../creatures/services/overworld_path.dart'
    show enemyCountForBattle, enemyLevelForBattle;
import '../services/game_defs_controller.dart';
import '../services/game_defs_service.dart';
import 'dev_theme.dart';
import 'path_node_form.dart';
import 'path_species_sheet.dart';

// The Dev-Mode "Pfad" tab (user 2026-07-25): the linear overworld path as an
// editable, REORDERABLE list of battle nodes. Drag to move a node (also between
// others); "+ Neuer Knoten" appends one; tap to edit its enemies + rewards.
// Reordering renumbers PathNode.order and persists the changed rows to Supabase.
class PathEditorTab extends StatefulWidget {
  const PathEditorTab({super.key});

  @override
  State<PathEditorTab> createState() => _PathEditorTabState();
}

class _PathEditorTabState extends State<PathEditorTab> {
  final _svc = GameDefsService();
  final _rng = math.Random();
  bool _busy = false;

  // ── Gesamtlevel direkt in der Liste (user 2026-07-31) ───────
  // "lass mich das Gesamtlevel hier direkt eingeben."
  //
  // Tuning a difficulty curve means comparing battle 7 against 6 and 8, and the
  // node form shows you exactly one node at a time. The number that decides a
  // fight's strength therefore lives HERE, next to its neighbours, and the form
  // keeps the same field for when you are editing the rest of the node.
  //
  // Only nodes with authored enemies take the field: a pool-generated node has
  // nothing to spread a total over, and silently conjuring three monsters
  // because you typed a number is not what typing a number means. Open it and
  // roll — that is one tap away.
  Future<void> _setTotal(PathNode n, int total) async {
    if (n.enemies.isEmpty) return;
    final levels = spreadLevels(
      total: total,
      count: n.enemies.length,
      rng: _rng,
    );
    final updated = n.copyWith(enemies: [
      for (var i = 0; i < n.enemies.length; i++)
        PathEnemy(speciesId: n.enemies[i].speciesId, level: levels[i]),
    ]);
    setState(() => _busy = true);
    try {
      await _svc.upsertPathNode(updated);
      await GameDefsController().load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final list = pathNodesInOrder();
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);

    // Renumber 1..N; persist only the nodes whose order actually changed.
    final changed = <PathNode>[];
    for (var i = 0; i < list.length; i++) {
      if (list[i].order != i + 1) changed.add(list[i].copyWith(order: i + 1));
    }
    if (changed.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final n in changed) {
        await _svc.upsertPathNode(n);
      }
      await GameDefsController().load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Reorder failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(PathNode? node) async {
    final nextOrder = kPathNodes.isEmpty
        ? 1
        : kPathNodes.values.map((n) => n.order).reduce((a, b) => a > b ? a : b) +
            1;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PathNodeForm(existing: node, nextOrder: nextOrder),
      ),
    );
    if (mounted) setState(() {});
  }


  /// The per-era species breakdown, with the dice that fills a region.
  ///
  /// A separate widget (path_species_sheet.dart) rather than a closure here: it
  /// has tabs, it writes to the path and it has to rebuild after a roll, none of
  /// which a builder inside a list row should be doing.
  void _showSpecies() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: FoE.panelDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (_, _) => const PathSpeciesSheet(),
    ),
  ).then((_) {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final nodes = pathNodesInOrder();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _open(null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: FoE.btn(active: true),
                    alignment: Alignment.center,
                    child: Text('+ Neuer Knoten',
                        style:
                            FoE.label(size: 15).copyWith(color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // The counterpart to the dice in the node form: what the path is
              // actually made of, across every node at once.
              GestureDetector(
                onTap: _showSpecies,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: FoE.btn(),
                  child: Text('📊 Monster',
                      style: FoE.label(size: 13).copyWith(color: FoE.gold)),
                ),
              ),
              const SizedBox(width: 10),
              if (_busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: FoE.goldBright),
                )
              else
                Text('${nodes.length}',
                    style: FoE.label(size: 13).copyWith(color: FoE.gold)),
            ],
          ),
        ),
        Expanded(
          child: nodes.isEmpty
              ? Center(child: Text('Keine Knoten', style: FoE.dim(size: 12)))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: nodes.length,
                  onReorder: _onReorder,
                  itemBuilder: (_, i) => _row(nodes[i], i),
                ),
        ),
      ],
    );
  }

  /// The node's enemies, named, each in its rarity's ink. Falls back to a note
  /// for a node whose fight is still generated from the area pool.
  Widget _enemyLine(PathNode n) {
    if (n.enemies.isEmpty) {
      return Text('aus dem Pool erzeugt', style: FoE.dim(size: 11));
    }
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      children: [
        for (final e in n.enemies)
          Text(
            '${kSpeciesDefs[e.speciesId]?.name ?? e.speciesId} ${e.level}',
            style: FoE.label(size: 11)
                .copyWith(color: speciesNameColor(e.speciesId)),
          ),
      ],
    );
  }

  Widget _row(PathNode n, int index) {
    final label = n.name.isNotEmpty ? n.name : 'Battle ${n.order}';
    final total = n.enemies.fold<int>(0, (s, e) => s + e.level);
    final parts = <String>[
      if (n.rewards.buildings.isNotEmpty) '🏛 ${n.rewards.buildings.length}',
      // Packages and plain items are both `items`; the row counts them together
      // — the node form is where the split matters.
      if (n.rewards.items.isNotEmpty) '🎁 ${n.rewards.items.length}',
      if (n.rewards.expansions > 0) '🗺 ${n.rewards.expansions}',
    ];
    return Padding(
      key: ValueKey(n.id),
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => _open(n),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: FoE.panel(radius: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                alignment: Alignment.center,
                child: Text('${n.order}',
                    style: FoE.value(size: 14).copyWith(color: FoE.goldBright)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (n.isBoss) const Text('👑 '),
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: FoE.label(size: 14)
                                  .copyWith(color: FoE.parchment)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // WHO you fight here, by name and in the RARITY's colour
                    // (user 2026-07-30). "3 enemies" was a count of something
                    // unnamed — the one thing this list is for is seeing what a
                    // region is made of without opening nineteen nodes.
                    _enemyLine(n),
                    if (parts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(parts.join(' · '), style: FoE.dim(size: 11)),
                    ],
                  ],
                ),
              ),
              if (n.enemies.isEmpty)
                SizedBox(
                  width: 58,
                  child: Text(
                    // What the formula would field here — greyed, because there
                    // is nothing authored to change yet.
                    'Lv ${enemyLevelForBattle(n.order) * enemyCountForBattle(n.order)}',
                    textAlign: TextAlign.center,
                    style: FoE.dim(size: 12),
                  ),
                )
              else
                _TotalLevelField(
                  // Keyed by node AND value, so a re-roll or an edit in the form
                  // shows up here instead of leaving a stale number in a field
                  // Flutter would otherwise happily reuse.
                  key: ValueKey('${n.id}_$total'),
                  total: total,
                  onCommit: (v) => _setTotal(n, v),
                ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(Icons.drag_handle, color: FoE.textDim),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one number that decides how hard a node is, editable in place.
///
/// Commits on ENTER or when it loses focus, never per keystroke: every commit
/// re-spreads the levels and writes the node to Supabase, and doing that while
/// someone is still typing "120" would save 1, then 12, then 120 — and re-roll
/// the spread three times.
class _TotalLevelField extends StatefulWidget {
  final int total;
  final ValueChanged<int> onCommit;
  const _TotalLevelField({super.key, required this.total, required this.onCommit});

  @override
  State<_TotalLevelField> createState() => _TotalLevelFieldState();
}

class _TotalLevelFieldState extends State<_TotalLevelField> {
  late final _ctrl = TextEditingController(text: '${widget.total}');
  late final _focus = FocusNode()..addListener(_onFocus);

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    final v = int.tryParse(_ctrl.text.trim());
    if (v == null || v == widget.total) {
      // Unparseable or unchanged: put the node's own number back rather than
      // leaving a half-typed one standing where it looks authoritative.
      _ctrl.text = '${widget.total}';
      return;
    }
    widget.onCommit(v.clamp(1, 99999));
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 58,
    child: TextField(
      controller: _ctrl,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      style: FoE.value(size: 13).copyWith(color: FoE.gold),
      decoration: InputDecoration(
        isDense: true,
        // NOT 'Σ': the app's font has no Greek, and a glyph it cannot draw
        // costs a Noto-fallback hunt and an exception per frame (2026-08-01).
        prefixText: 'Lv ',
        prefixStyle: FoE.dim(size: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: FoE.panelMid),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: FoE.gold),
        ),
      ),
    ),
  );
}
