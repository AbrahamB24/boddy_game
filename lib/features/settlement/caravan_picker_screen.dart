import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/creature_card.dart';
import 'widgets/scroll_paper.dart'
    show kParchmentInk;

/// Filling ONE PLACE in the Market's caravan — the egg picker's twin (the
/// Hatchery fills its slot from a SCREEN, not a popup, and the Market follows
/// the Hatchery).
///
/// It began as a `CheckboxListTile` list in a bottom sheet, then as a
/// multi-select grid with a Done button. Both asked you to build the whole
/// party in one go: to change a single hauler you rebuilt all of it.
///
/// Since 2026-07-27 the Market shows one place per seat the caravan has ("ich
/// möchte oben jeweils ein + … für jeden Platz, … so dass ich die Monster
/// einzeln hinzufügen kann"), so this answers exactly one of them: TAP A TILE
/// AND YOU ARE BACK. No selection state, no Done — the tap is the answer.
///
/// Pops with the chosen monster (as a one-element list, which is what the
/// caller appends), or with null when you back out.
class CaravanPickerScreen extends StatefulWidget {
  /// Who is already loaded. Shown with a check and not pickable again — they
  /// are part of the caravan you are looking at, and hiding them would make the
  /// grid reshuffle under your finger every time you filled a place.
  final List<CreatureInstance> selected;

  const CaravanPickerScreen({super.key, this.selected = const []});

  @override
  State<CaravanPickerScreen> createState() => _CaravanPickerScreenState();
}

class _CaravanPickerScreenState extends State<CaravanPickerScreen> {
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static const Color _accent = FoE.gold;

  /// The Monsters-grid cell shape — the Hatchery slot and the egg picker use
  /// the same constant.
  static const double _kTileAspect = 0.70;

  /// Room UNDER a tile for its carry/speed line, on top of the tile's own
  /// height. See the grid's comment: a caption must not cost tile.
  static const double _kCaptionHeight = 17;

  static final PillPalette _pills = PillPalette.parchment;

  final _creatures = CreaturesController();
  final _search = TextEditingController();

  String _query = '';

  /// Which stat the list is ranked by. Carry first: it is the stat that decides
  /// whether a trade is worth sending at all.
  CreatureStat _sortStat = CreatureStat.carry;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  int get _cap => _creatures.teamSizeCap;

  /// Already in the caravan — shown, but not pickable twice.
  bool _loaded(CreatureInstance c) => widget.selected.any((p) => p.id == c.id);

  List<CreatureInstance> get _options {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final c in _creatures.availableForExpedition())
        if (q.isEmpty || c.displayName.toLowerCase().contains(q)) c,
    ];
    // Best first — a hauler is picked on one number, and scrolling for it is
    // the job the sort exists to save.
    list.sort(
      (a, b) => b.statValue(_sortStat).compareTo(a.statValue(_sortStat)),
    );
    return list;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _creatures,
    builder: (context, _) {
      final options = _options;
      return ParchmentPage(
        title: 'Add a hauler',
        // How full the caravan is — the cap grows with the linear path, so it
        // is worth seeing while you pick rather than discovering when a place
        // stops appearing.
        trailing: Text(
          '${widget.selected.length}/$_cap',
          style: FoE.value(size: 12).copyWith(color: _accent),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 10, ParchmentPage.kParchmentPagePad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(flex: 3, child: _searchPill()),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _sortPill()),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: options.isEmpty
                    ? Text(
                        _query.isEmpty
                            ? 'Nobody is free to travel.'
                            : 'No monster matches.',
                        style: FoE.dim(size: 12).copyWith(color: _inkSoft),
                      )
                    : LayoutBuilder(
                        // THE CAPTION IS EXTRA (user 2026-07-27): the
                        // carry/speed line used to live INSIDE the 0.70 cell,
                        // so it ate its height off the tile and every monster
                        // here stood squashed next to the same monster on the
                        // Monsters screen. mainAxisExtent is the only way to
                        // say "the tile's height, and then some".
                        builder: (context, box) {
                          const gap = 12.0;
                          final cell = (box.maxWidth - gap * 2) / 3;
                          return GridView.builder(
                            padding: const EdgeInsets.only(top: 4, bottom: 16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: gap,
                              crossAxisSpacing: gap,
                              mainAxisExtent:
                                  cell / _kTileAspect + _kCaptionHeight,
                            ),
                            itemCount: options.length,
                            itemBuilder: (_, i) => _tile(options[i]),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// One candidate: the Monsters-screen tile, with THE TWO STATS THAT MATTER
  /// HERE under it — 🏋 carry decides how much fits, 🥾 speed how long the trip
  /// takes. No XP arc and no HP bar: a hauler is picked on those two, and
  /// neither its level progress nor its wounds are part of that.
  Widget _tile(CreatureInstance c) {
    final loaded = _loaded(c);
    return Opacity(
      opacity: loaded ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The tile at its OWN height; the caption below is what made the cell
          // taller, so nothing here has to give any of it back.
          AspectRatio(
            aspectRatio: _kTileAspect,
            child: Stack(
              children: [
                Positioned.fill(
                  // THE tile, with nothing switched off (user 2026-07-27:
                  // "genau diese Kachel"): the place it lands in on the Market
                  // is the same tile, so the one you are comparing against here
                  // has to be too.
                  child: CreatureCard(
                    creature: c,
                    onTap: loaded ? null : () => Navigator.pop(context, [c]),
                  ),
                ),
                if (loaded)
                  const Positioned(
                    top: 0,
                    left: 0,
                    child: Icon(Icons.check_circle, size: 18, color: _accent),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: _kCaptionHeight,
            child: Center(
              child: Text(
                '🏋 ${c.statValue(CreatureStat.carry)}   '
                '🥾 ${c.statValue(CreatureStat.speed)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.dim(size: 10).copyWith(color: _inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchPill() => SearchPill(
    controller: _search,
    onChanged: (v) => setState(() => _query = v),
    palette: _pills,
  );

  /// Rank by carry or by speed — the two ends of the same decision (more cargo
  /// per trip, or more trips). Power and level are deliberately not offered:
  /// neither moves a number on the Market.
  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: _sortStat.label,
    engaged: _sortStat != CreatureStat.carry,
    value: _sortStat.name,
    entries: const [
      MapEntry('carry', 'Carry'),
      MapEntry('speed', 'Speed'),
    ],
    onSelected: (v) =>
        setState(() => _sortStat = CreatureStat.values.byName(v)),
  );
}
