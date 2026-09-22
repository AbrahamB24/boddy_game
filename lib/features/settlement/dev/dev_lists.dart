import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/ui/pressable.dart';
import '../../creatures/dev/species_def_form.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_def.dart';
import '../../creatures/services/stat_budget.dart';
import '../data/building_art.dart';
import '../data/building_definitions.dart';
import '../data/item_definitions.dart';
import '../services/game_defs_controller.dart';
import '../widgets/building_icon.dart';
import 'area_def_form.dart';
import 'building_def_form.dart';
import 'item_def_form.dart';

// ── The Dev menu's lists, "Variante 3": list left, form right ──────────────
// (user 2026-09-20). A list on a narrow cream card, and beside it a pane that
// holds the form of whatever is picked — no page change, so going down the list
// is a tap each. The forms are the same Scaffold pages they always were; the
// pane is a Navigator of its own, so their `Navigator.pop` after Save/Delete
// simply closes the pane.

/// What a list hands its rows: open [form] in the pane and mark [id] picked.
typedef DevOpen = void Function(String? id, Widget form);

/// The list card and, beside it, the pane the picked form opens in.
class DevMasterDetail extends StatefulWidget {
  /// Builds the list; call `open` from a row (or the "+ New" button).
  final Widget Function(BuildContext context, DevOpen open, String? selected)
  list;

  /// Shown in the pane while nothing is open.
  final String hint;

  const DevMasterDetail({super.key, required this.list, required this.hint});

  @override
  State<DevMasterDetail> createState() => _DevMasterDetailState();
}

class _DevMasterDetailState extends State<DevMasterDetail> {
  final _nav = GlobalKey<NavigatorState>();
  String? _selected;
  late final _observer = _PaneObserver(() {
    if (mounted && _selected != null) setState(() => _selected = null);
  });

  void _open(String? id, Widget form) {
    setState(() => _selected = id);
    // Replace whatever is open: one form at a time.
    _nav.currentState?.pushAndRemoveUntil(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => form,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (r) => r.isFirst,
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: 292,
        child: creamCard(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: widget.list(context, _open, _selected),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: creamCard(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Navigator(
              key: _nav,
              observers: [_observer],
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.hint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: kBoxInkSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Tells the list when the pane is back at its hint (a form saved or closed).
class _PaneObserver extends NavigatorObserver {
  final VoidCallback onBackToHint;
  _PaneObserver(this.onBackToHint);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute?.isFirst ?? false) onBackToHint();
  }
}

// ── Shared pieces ───────────────────────────────────────────

/// The search well: a magnifier and a hint, on the cream card.
class DevSearch extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const DevSearch({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: CreamPalette.tan.withValues(alpha: 0.55),
        width: 1.5,
      ),
    ),
    child: Row(
      children: [
        Icon(Icons.search, size: 15, color: kBoxInkFaint),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            onChanged: onChanged,
            cursorColor: kBoxInk,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: kBoxInk,
            ),
            decoration: InputDecoration.collapsed(
              hintText: 'Search name or id…',
              hintStyle: TextStyle(fontSize: 12, color: kBoxInkFaint),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A compact dropdown in the same well.
class DevDrop<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const DevDrop({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: const EdgeInsets.only(left: 9, right: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: CreamPalette.tan.withValues(alpha: 0.55),
        width: 1.5,
      ),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        isDense: true,
        isExpanded: true,
        iconSize: 18,
        icon: Icon(Icons.arrow_drop_down, color: kBoxInkFaint),
        dropdownColor: CreamPalette.paperBottom,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: kBoxInk,
        ),
      ),
    ),
  );
}

/// The gold "+ New" pill at the head of a list.
class DevNewButton extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  const DevNewButton({super.key, required this.onTap, this.label = '+ New'});

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: goldButton(),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: goldButtonInk(),
        ),
      ),
    ),
  );
}

/// One row of a list: a tile with a leading picture, a title, a side note and a
/// chevron; the picked one wears the gold rim.
Widget devRow({
  required Widget leading,
  required String title,
  required VoidCallback onTap,
  Widget? flag,
  String? note,
  Color? noteColor,
  bool selected = false,
}) => Pressable(
  onTap: onTap,
  child: Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: raisedTile(lit: selected, radius: 10),
    child: Row(
      children: [
        SizedBox(width: 28, height: 28, child: Center(child: leading)),
        const SizedBox(width: 9),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: kBoxInk,
                  ),
                ),
              ),
              if (flag != null) ...[const SizedBox(width: 6), flag],
            ],
          ),
        ),
        if (note != null)
          Text(
            note,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: noteColor ?? kBoxInkSoft,
            ),
          ),
        const SizedBox(width: 2),
        Icon(Icons.chevron_right, size: 16, color: kBoxInkFaint),
      ],
    ),
  ),
);

/// The red dot for "off budget".
const Widget devRedDot = SizedBox(
  width: 8,
  height: 8,
  child: DecoratedBox(
    decoration: BoxDecoration(color: Color(0xFFC9432B), shape: BoxShape.circle),
  ),
);

Widget _emptyNote(String text) => Center(
  child: Text(text, style: TextStyle(fontSize: 12, color: kBoxInkSoft)),
);

// ── Species ─────────────────────────────────────────────────

enum _SpeciesSort {
  name('↕ Name'),
  rarity('↕ Rarity'),
  tier('↕ Tier'),
  element('↕ Element');

  final String label;
  const _SpeciesSort(this.label);
}

/// The species roster: search, three filters, one row per species, a red dot on
/// the ones off their stat budget.
class SpeciesListPane extends StatefulWidget {
  final DevOpen open;
  final String? selected;
  const SpeciesListPane({super.key, required this.open, this.selected});

  @override
  State<SpeciesListPane> createState() => _SpeciesListPaneState();
}

class _SpeciesListPaneState extends State<SpeciesListPane> {
  String _search = '';
  CreatureElement? _element;
  CreatureRarity? _rarity;
  _SpeciesSort _sort = _SpeciesSort.name;

  bool _off(SpeciesDef d) =>
      !isOnTotalBudget(stats: d.stats, rarity: d.rarity, tier: d.tier);

  List<SpeciesDef> _visible() {
    final q = _search.trim().toLowerCase();
    final list = kSpeciesDefs.values.where((d) {
      if (q.isNotEmpty &&
          !d.name.toLowerCase().contains(q) &&
          !d.id.toLowerCase().contains(q)) {
        return false;
      }
      if (_element != null && d.element != _element) return false;
      if (_rarity != null && d.rarity != _rarity) return false;
      return true;
    }).toList();
    int cmp(SpeciesDef a, SpeciesDef b) => switch (_sort) {
      _SpeciesSort.name => 0,
      _SpeciesSort.rarity => a.rarity.index.compareTo(b.rarity.index),
      _SpeciesSort.tier => a.tier.compareTo(b.tier),
      _SpeciesSort.element => a.element.index.compareTo(b.element.index),
    };
    list.sort((a, b) {
      final c = cmp(a, b);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DevSearch(onChanged: (v) => setState(() => _search = v)),
            ),
            const SizedBox(width: 7),
            DevNewButton(
              onTap: () => widget.open(null, const SpeciesDefForm()),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DevDrop<CreatureElement?>(
                value: _element,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Element')),
                  for (final e in CreatureElement.values.where(
                    (e) => e != CreatureElement.neutral,
                  ))
                    DropdownMenuItem(
                      value: e,
                      child: Text('${e.emoji} ${e.label}'),
                    ),
                ],
                onChanged: (v) => setState(() => _element = v),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: DevDrop<CreatureRarity?>(
                value: _rarity,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Rarity')),
                  for (final r in CreatureRarity.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setState(() => _rarity = v),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: DevDrop<_SpeciesSort>(
                value: _sort,
                items: [
                  for (final s in _SpeciesSort.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _sort = v ?? _sort),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 5),
          child: Text(
            '${visible.length} / ${kSpeciesDefs.length}',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: kBoxAccent,
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _emptyNote('Keine Arten')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (_, i) {
                    final d = visible[i];
                    return devRow(
                      leading: BuildingIcon(
                        imageUrl: d.stageAt(0).imageUrl,
                        emoji: d.element.emoji,
                        size: 26,
                      ),
                      title: d.name,
                      flag: _off(d) ? devRedDot : null,
                      note: '${d.rarity.label} · T${d.tier}',
                      noteColor: d.rarity.color,
                      selected: widget.selected == d.id,
                      onTap: () =>
                          widget.open(d.id, SpeciesDefForm(existing: d)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Buildings ───────────────────────────────────────────────

/// The building roster: search, the first-region filter, the "retired" strip
/// and the models button.
class BuildingsListPane extends StatefulWidget {
  final DevOpen open;
  final String? selected;
  const BuildingsListPane({super.key, required this.open, this.selected});

  @override
  State<BuildingsListPane> createState() => _BuildingsListPaneState();
}

class _BuildingsListPaneState extends State<BuildingsListPane> {
  String _search = '';
  int? _era;

  /// The region ORDER a building first becomes buildable in. Empty eraIds
  /// means "every region" (Main Hall, Road), so it is buildable from region
  /// 1 on. Still `'era_N'` id strings — see building_definitions.dart's
  /// `_regionOrderOfId` doc for why the identifier itself didn't change.
  int _firstEra(BuildingDef d) {
    if (d.eraIds.isEmpty) return 1;
    final orders = d.eraIds
        .map((id) => int.tryParse(id.split('_').last))
        .whereType<int>();
    return orders.isEmpty ? 1 : orders.reduce(math.min);
  }

  String _eraLabel(BuildingDef d) =>
      d.eraIds.isEmpty ? 'Always' : 'Region ${_firstEra(d)}';

  List<BuildingDef> _visible() {
    final q = _search.trim().toLowerCase();
    final list = kBuildingDefs.values.where((d) {
      if (q.isNotEmpty &&
          !d.name.toLowerCase().contains(q) &&
          !d.id.toLowerCase().contains(q)) {
        return false;
      }
      if (_era != null && _firstEra(d) != _era) return false;
      return true;
    }).toList();
    // First-buildable era, then name — a stable, scannable order.
    list.sort((a, b) {
      final c = _firstEra(a).compareTo(_firstEra(b));
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    // 1..8, the fixed region ladder the goods/building generator uses (no
    // more EraDef table — see building_def_form.dart's `_RegionChoice`).
    final eras = [for (var order = 1; order <= 8; order++) order];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DevSearch(onChanged: (v) => setState(() => _search = v)),
            ),
            const SizedBox(width: 7),
            DevNewButton(
              onTap: () => widget.open(null, const BuildingDefForm()),
            ),
          ],
        ),
        const SizedBox(height: 6),
        DevDrop<int?>(
          value: _era,
          items: [
            const DropdownMenuItem(value: null, child: Text('All regions')),
            for (final order in eras)
              () {
                final area = kAreaDefs.values
                    .where((a) => a.battleStage == order)
                    .firstOrNull;
                final label = area == null
                    ? 'Region $order'
                    : 'Region $order · ${area.name}';
                return DropdownMenuItem(
                  value: order,
                  child: Text('${area?.emoji ?? '📍'} $label'),
                );
              }(),
          ],
          onChanged: (v) => setState(() => _era = v),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5, bottom: 5),
          child: Text(
            '${visible.length} / ${kBuildingDefs.length}',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: kBoxAccent,
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _emptyNote('Keine Gebäude')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (_, i) {
                    final d = visible[i];
                    return devRow(
                      leading: BuildingIcon(
                        imageUrl: d.imageUrl,
                        defId: d.id,
                        size: 24,
                      ),
                      title: d.name,
                      note: _eraLabel(d),
                      selected: widget.selected == d.id,
                      onTap: () =>
                          widget.open(d.id, BuildingDefForm(existing: d)),
                    );
                  },
                ),
        ),
        const SizedBox(height: 4),
        const _ApplyModelsButton(),
        _retiredStrip(),
      ],
    );
  }

  /// A bundled building is retired rather than deleted (see GameDefsController),
  /// and a retired def is invisible BY DESIGN — which would make it unreachable
  /// for good. This strip is the way back: everything you have removed, one tap
  /// to restore.
  Widget _retiredStrip() {
    final ids = GameDefsController.retiredBuildingIds.toList()..sort();
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gelöscht (${ids.length}) — tippen zum Zurückholen',
            style: TextStyle(fontSize: 10.5, color: kBoxInkSoft),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final id in ids)
                Pressable(
                  onTap: () => _restore(id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: raisedTile(radius: 9),
                    child: Text(
                      '⟵ ${kFallbackBuildingDefs[id]?.name ?? id}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: kBoxInk,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(String id) async {
    try {
      await GameDefsController().restoreBuildingDef(id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Zurückholen fehlgeschlagen: $e')),
        );
      }
    }
  }
}

/// Puts the bundled buildings' render sizes and grid back onto the live defs
/// where they have drifted.
class _ApplyModelsButton extends StatefulWidget {
  const _ApplyModelsButton();

  @override
  State<_ApplyModelsButton> createState() => _ApplyModelsButtonState();
}

class _ApplyModelsButtonState extends State<_ApplyModelsButton> {
  bool _busy = false;

  List<BuildingDef> _stale() {
    final out = <BuildingDef>[];
    for (final id in kBundledBuildingArt) {
      final live = kBuildingDefs[id];
      final model = kFallbackBuildingDefs[id];
      final box = kBundledArtBox[id];
      if (live == null || model == null || box == null) continue;
      final same =
          live.gridW == model.gridW &&
          live.gridH == model.gridH &&
          (live.artBaseWidth - box.$1).abs() < 0.0005 &&
          (live.artAnchorX - box.$2).abs() < 0.0005 &&
          (live.artLift - box.$3).abs() < 0.0005 &&
          (live.imageUrl == null || live.imageUrl!.isEmpty);
      if (!same) out.add(live);
    }
    return out;
  }

  Future<void> _apply() async {
    final stale = _stale();
    if (stale.isEmpty) return;
    setState(() => _busy = true);
    try {
      await GameDefsController().saveBuildingDefs([
        for (final live in stale)
          live.withModelArt(
            gridW: kFallbackBuildingDefs[live.id]!.gridW,
            gridH: kFallbackBuildingDefs[live.id]!.gridH,
            artBaseWidth: kBundledArtBox[live.id]!.$1,
            artAnchorX: kBundledArtBox[live.id]!.$2,
            artLift: kBundledArtBox[live.id]!.$3,
          ),
      ]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${stale.length} Gebäude auf die Modellwerte gesetzt'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _stale().length;
    return Pressable(
      onTap: _busy || n == 0 ? null : _apply,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: raisedTile(radius: 10, locked: n == 0),
        child: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                n == 0
                    ? 'Renders & Grössen: alle aktuell'
                    : 'Renders & Grössen übernehmen ($n)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: n == 0 ? kBoxInkFaint : kBoxInk,
                ),
              ),
      ),
    );
  }
}

// ── Items and areas ─────────────────────────────────────────

/// One row of a plain list.
class DevDefRow {
  final String id;
  final String name;
  final String emoji;
  final String? note;
  const DevDefRow({
    required this.id,
    required this.name,
    this.emoji = '',
    this.note,
  });
}

/// A plain def list — search, "+ New", one row per def. Items and areas.
class DefListPane extends StatefulWidget {
  final List<DevDefRow> Function() rows;
  final DevOpen open;
  final String? selected;
  final Widget Function(String? id) formFor;
  const DefListPane({
    super.key,
    required this.rows,
    required this.open,
    required this.formFor,
    this.selected,
  });

  @override
  State<DefListPane> createState() => _DefListPaneState();
}

class _DefListPaneState extends State<DefListPane> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final rows = [
      for (final r in widget.rows())
        if (q.isEmpty ||
            r.name.toLowerCase().contains(q) ||
            r.id.toLowerCase().contains(q))
          r,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DevSearch(onChanged: (v) => setState(() => _search = v)),
            ),
            const SizedBox(width: 7),
            DevNewButton(onTap: () => widget.open(null, widget.formFor(null))),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 5),
          child: Text(
            '${rows.length}',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: kBoxAccent,
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? _emptyNote('Nichts gefunden')
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return devRow(
                      leading: Text(
                        r.emoji.isEmpty ? '•' : r.emoji,
                        style: const TextStyle(fontSize: 17),
                      ),
                      title: r.name,
                      note: r.note,
                      selected: widget.selected == r.id,
                      onTap: () => widget.open(r.id, widget.formFor(r.id)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// The items list (name, kind), opening [ItemDefForm].
Widget itemsListPane(DevOpen open, String? selected) => DefListPane(
  open: open,
  selected: selected,
  rows: () => [
    for (final d
        in kItemDefs.values.toList()..sort((a, b) => a.name.compareTo(b.name)))
      DevDefRow(id: d.id, name: d.name, emoji: d.emoji, note: d.kind.name),
  ],
  formFor: (id) => ItemDefForm(existing: id == null ? null : kItemDefs[id]),
);

/// The areas list (order, name, stage), opening [AreaDefForm].
Widget areasListPane(DevOpen open, String? selected) => DefListPane(
  open: open,
  selected: selected,
  rows: () => [
    for (final d
        in kAreaDefs.values.toList()
          ..sort((a, b) => a.order.compareTo(b.order)))
      DevDefRow(
        id: d.id,
        name: '${d.order}. ${d.name}',
        emoji: d.emoji,
        note: 'S${d.battleStage}',
      ),
  ],
  formFor: (id) => AreaDefForm(existing: id == null ? null : kAreaDefs[id]),
);
