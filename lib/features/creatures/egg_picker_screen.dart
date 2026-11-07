import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart';
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creature_power.dart';
import 'widgets/egg_card.dart';
import 'widgets/picker_detail_panel.dart';
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

/// Choosing which egg goes into the Hatchery — A SCREEN OF ITS OWN (user
/// 2026-07-27: "Das Eimenü soll kein pop up sein, sondern ein eigener screen,
/// dann gibt es mehr Platz").
///
/// It was a bottom sheet capped at 560 px, and the cap was the problem: the
/// three controls, the grid and the sheet's own margins split that between
/// them, so a bag of a dozen eggs showed about one row at a time. A route gets
/// the whole window, which is what a grid of tiles wants.
///
/// Pops with the chosen egg's id, or with null when you back out — so the
/// caller reads it exactly like the sheet it replaces.
class EggPickerScreen extends StatefulWidget {
  /// The egg already in the Hatchery's slot, marked in the grid so you can see
  /// what you are about to change.
  final String? selectedEggId;

  const EggPickerScreen({super.key, this.selectedEggId});

  @override
  State<EggPickerScreen> createState() => _EggPickerScreenState();
}

class _EggPickerScreenState extends State<EggPickerScreen> {
  static final Color _inkSoft = kBoxInkSoft;
  static const Color _accent = CreamPalette.goldDeep;

  /// This page is parchment, so its pills are.
  static final PillPalette _pills = PillPalette.cream;

  final _breeding = BreedingController();
  final _search = TextEditingController();

  String _query = '';
  String? _filterSpeciesId; // null = every species in the bag
  CreatureStat? _sortStat; // null = the gene TOTAL, the default ranking
  bool _descending = true; // best first

  /// Tapping an egg only PREVIEWS it here (user 2026-10-05, "Konzept 4") —
  /// the detail panel's own button is what actually picks it.
  BreedingJob? _preview;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _breeding,
    builder: (context, _) {
      final options = _pickerEggs();
      return MenuScaffold(
        // No emoji in a title (user 2026-07-27) — here and on every page's bar.
        title: 'Choose an egg',
        trailing: Text(
          '${_breeding.eggs.length} in the bag',
          style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
        ),
        // No card of its own any more (user 2026-09-30, "hier und
        // andernorts sind noch die alten Kästchen vorhanden") —
        // MenuScaffold is already the one card on screen.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(flex: 3, child: _searchPill()),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _sortPill()),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _filterPill()),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _detail(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: options.isEmpty
                          ? Text(
                              _breeding.eggs.isEmpty
                                  ? 'No eggs in the bag.'
                                  : 'No egg matches.',
                              style: FoE.dim(
                                size: 12,
                              ).copyWith(color: _inkSoft),
                            )
                          // Fixed-width cells (the shared tile size), not a
                          // max-extent grid that hands a tile any width up to
                          // its cap.
                          : SingleChildScrollView(
                              padding: const EdgeInsets.only(
                                top: 14,
                                bottom: 16,
                              ),
                              child: Wrap(
                                spacing: kMonsterTileSpacing,
                                runSpacing: kMonsterTileSpacing,
                                children: [
                                  for (final egg in options)
                                    SizedBox(
                                      width: monsterTileWidth(context),
                                      height: monsterTileHeight(context),
                                      child: pickerPreviewFrame(
                                        active: egg.id == _preview?.id,
                                        child: EggCard(
                                          job: egg,
                                          selected:
                                              egg.id == widget.selectedEggId,
                                          onTap: () =>
                                              setState(() => _preview = egg),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// The list: what the search box and the species filter leave, in the chosen
  /// field and direction.
  ///
  /// Ranked on the egg's FROZEN CHILD (`childBase`) — the creature that will
  /// actually come out. An egg laid before those genes existed scores below
  /// everything: it has no figure to rank on, which is not the same as a low
  /// one, and burying it beats pretending it is the worst.
  List<BreedingJob> _pickerEggs() {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final j in _breeding.eggs)
        if ((_filterSpeciesId == null || j.speciesId == _filterSpeciesId) &&
            (q.isEmpty ||
                (kSpeciesDefs[j.speciesId]?.name ?? j.speciesId)
                    .toLowerCase()
                    .contains(q)))
          j,
    ];
    double score(BreedingJob j) {
      if (!j.hasChildGenes) return double.negativeInfinity;
      return _sortStat == null
          ? genePower(j.childBase).toDouble()
          : (j.childBase[_sortStat] ?? 0);
    }

    list.sort(
      (a, b) => _descending
          ? score(b).compareTo(score(a))
          : score(a).compareTo(score(b)),
    );
    return list;
  }

  /// The left panel: what this egg will hatch into — species, rarity, gene
  /// power — rather than anything about health or combat, which an egg has
  /// none of yet.
  Widget _detail() {
    final job = _preview;
    if (job == null) {
      return const PickerDetailPanel(
        placeholder: 'Tap an egg to see what it will hatch into.',
      );
    }
    final species = kSpeciesDefs[job.speciesId];
    final chosen = job.id == widget.selectedEggId;
    return PickerDetailPanel(
      artHeight: 90,
      art: EggGlyph(job: job),
      title: species?.name ?? job.speciesId,
      subtitle: job.hasChildGenes ? '⚡ ${genePower(job.childBase)}' : '⚡ ?',
      rows: [
        pickerStatRow('Rarity', species?.rarity.label ?? '—'),
        pickerStatRow('Type', species?.element.label ?? '—'),
      ],
      action: pickerChooseButton(
        label: chosen ? 'Already in the slot' : 'Choose this egg',
        onTap: chosen ? null : () => Navigator.pop(context, job.id),
      ),
    );
  }

  // ── The controls ──────────────────────────────────────────────────────
  // The shared pills (features/common/widgets/filter_pills.dart). This screen
  // is where that look was designed; it now imports it like everywhere else so
  // there is one copy to change.

  Widget _searchPill() => SearchPill(
    controller: _search,
    onChanged: (v) => setState(() => _query = v),
    palette: _pills,
  );

  /// WHICH monster: the species actually present in the bag, or all of them.
  /// Listing species you hold no egg of would offer empty results.
  Widget _filterPill() {
    final ids = <String>{for (final j in _breeding.eggs) j.speciesId}.toList()
      ..sort(
        (a, b) =>
            (kSpeciesDefs[a]?.name ?? a).compareTo(kSpeciesDefs[b]?.name ?? b),
      );
    final chosen = ids.contains(_filterSpeciesId) ? _filterSpeciesId : null;
    return MenuPill<String>(
      palette: _pills,
      icon: Icons.filter_alt_outlined,
      label: chosen == null
          ? 'All monsters'
          : (kSpeciesDefs[chosen]?.name ?? chosen),
      engaged: chosen != null,
      value: chosen ?? '',
      entries: [
        const MapEntry('', 'All monsters'),
        for (final id in ids) MapEntry(id, kSpeciesDefs[id]?.name ?? id),
      ],
      onSelected: (v) =>
          setState(() => _filterSpeciesId = v.isEmpty ? null : v),
    );
  }

  /// Order by any single gene, or by the total. Which one matters depends on
  /// what you are breeding FOR, so no fixed order can be right for everyone.
  ///
  /// The pill carries the DIRECTION arrow — that is where re-picking the same
  /// field shows up, and the menu repeats it on the current entry so a second
  /// tap on it reads as "flip", not as "nothing happened".
  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: _sortStat?.label ?? 'Total power',
    // A flipped direction counts as engaged too — otherwise the default field
    // in ascending order would look like the untouched default.
    engaged: _sortStat != null || !_descending,
    value: _sortStat?.name ?? '',
    entries: [
      const MapEntry('', 'Total power'),
      for (final s in CreatureStat.values) MapEntry(s.name, s.label),
    ],
    trailing: PixelIcon(
      _descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: _accent,
    ),
    selectedTrailing: _descending ? '↓' : '↑',
    onSelected: (v) {
      final picked = v.isEmpty ? null : CreatureStat.values.byName(v);
      setState(() {
        // SAME PICK FLIPS THE ORDER (user 2026-07-27: "Wenn ich ein zweites mal
        // auf das gleiche Drücke ändert sich die Sortierreihenfolge"). A new
        // field always starts best-first, which is the answer you want the
        // first time you ask.
        if (picked == _sortStat) {
          _descending = !_descending;
        } else {
          _sortStat = picked;
          _descending = true;
        }
      });
    },
  );
}
