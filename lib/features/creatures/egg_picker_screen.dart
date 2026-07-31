import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/widgets/scroll_paper.dart'
    show kParchmentInk;
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creature_power.dart';
import 'widgets/egg_card.dart';

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
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static const Color _accent = FoE.gold;

  /// The Monsters-grid cell shape — the Hatchery slot uses the same.
  static const double _kTileAspect = 0.70;

  /// This page is parchment, so its pills are.
  static final PillPalette _pills = PillPalette.parchment;

  final _breeding = BreedingController();
  final _search = TextEditingController();

  String _query = '';
  String? _filterSpeciesId; // null = every species in the bag
  CreatureStat? _sortStat; // null = the gene TOTAL, the default ranking
  bool _descending = true; // best first

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
      return ParchmentPage(
        // No emoji in a title (user 2026-07-27) — here and on every page's bar.
        title: 'Eggs',
        trailing: Text(
          '${_breeding.eggs.length}',
          style: FoE.value(size: 12).copyWith(color: _accent),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 10, ParchmentPage.kParchmentPagePad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchPill(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _filterPill()),
                  const SizedBox(width: 8),
                  Expanded(child: _sortPill()),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: options.isEmpty
                    ? Text(
                        _breeding.eggs.isEmpty
                            ? 'No eggs in the bag.'
                            : 'No egg matches.',
                        style: FoE.dim(size: 12).copyWith(color: _inkSoft),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: _kTileAspect,
                        ),
                        itemCount: options.length,
                        itemBuilder: (_, i) => EggCard(
                          job: options[i],
                          selected: options[i].id == widget.selectedEggId,
                          onTap: () => Navigator.pop(context, options[i].id),
                        ),
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
    trailing: Icon(
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