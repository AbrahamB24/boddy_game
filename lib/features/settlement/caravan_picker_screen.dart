import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/creature_card.dart';
import '../creatures/widgets/picker_detail_panel.dart';
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

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
  static final Color _inkSoft = kBoxInkSoft;
  static const Color _accent = CreamPalette.goldDeep;

  /// Room UNDER a tile for its carry/speed line, on top of the tile's own
  /// height. See the grid's comment: a caption must not cost tile.
  static const double _kCaptionHeight = 17;

  static final PillPalette _pills = PillPalette.cream;

  final _creatures = CreaturesController();
  final _search = TextEditingController();

  String _query = '';

  /// Which stat the list is ranked by. Carry first: it is the stat that decides
  /// whether a trade is worth sending at all.
  CreatureStat _sortStat = CreatureStat.carry;

  /// Filter, added alongside search+sort everywhere a monster is picked (user
  /// 2026-09-11).
  CreatureElement? _filterElement;

  /// Tapping a tile only PREVIEWS it here (user 2026-10-05, "Konzept 4") —
  /// the detail panel's own button is what actually loads it.
  CreatureInstance? _preview;

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
        if ((_filterElement == null || c.species?.element == _filterElement) &&
            (q.isEmpty || c.displayName.toLowerCase().contains(q)))
          c,
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
      return MenuScaffold(
        title: 'Add a hauler',
        // How full the caravan is — the cap grows with the linear path, so it
        // is worth seeing while you pick rather than discovering when a place
        // stops appearing.
        trailing: Text(
          '${widget.selected.length}/$_cap',
          style: FoE.value(size: 12).copyWith(color: kBoxInk),
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
                              _query.isEmpty
                                  ? 'Nobody is free to travel.'
                                  : 'No monster matches.',
                              style: FoE.dim(
                                size: 12,
                              ).copyWith(color: _inkSoft),
                            )
                          : Builder(
                              // THE CAPTION IS EXTRA (user 2026-07-27): the
                              // carry/speed line used to live INSIDE the 0.70
                              // cell, so it ate its height off the tile and
                              // every monster here stood squashed next to the
                              // same monster on the Monsters screen.
                              // mainAxisExtent is the only way to say "the
                              // tile's height, and then some" — and the CARD
                              // portion of that height now comes from the
                              // shared [monsterTileHeight] (user 2026-08-31:
                              // "genau gleich gross sein wie die Kacheln beim
                              // Monstersscreen"), not this screen's own local
                              // width computation.
                              builder: (context) => SingleChildScrollView(
                                // Fixed-width cells (the shared tile width),
                                // not a max-extent grid: that one hands the
                                // tile ANY width up to its cap, and the
                                // tile's height follows its width — the
                                // caption row then no longer fitted.
                                padding: const EdgeInsets.only(
                                  top: 18,
                                  bottom: 16,
                                ),
                                child: Wrap(
                                  spacing: kMonsterTileSpacing,
                                  runSpacing: kMonsterTileSpacing,
                                  children: [
                                    for (final c in options)
                                      SizedBox(
                                        width: monsterTileWidth(context),
                                        height:
                                            monsterTileHeight(context) +
                                            _kCaptionHeight,
                                        child: _tile(c),
                                      ),
                                  ],
                                ),
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

  /// One candidate: the Monsters-screen tile, with THE TWO STATS THAT MATTER
  /// HERE under it — 🏋 carry decides how much fits, 🥾 speed how long the trip
  /// takes. No XP arc and no HP bar: a hauler is picked on those two, and
  /// neither its level progress nor its wounds are part of that. A tap only
  /// PREVIEWS it in [_detail] now (user 2026-10-05, "Konzept 4") — the panel's
  /// own button is what actually loads it.
  Widget _tile(CreatureInstance c) {
    final loaded = _loaded(c);
    final previewed = _preview?.id == c.id;
    return Opacity(
      opacity: loaded ? 0.4 : 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The tile at its OWN height; the caption below is what made the cell
          // taller, so nothing here has to give any of it back.
          AspectRatio(
            aspectRatio: kMonsterTileAspect,
            child: pickerPreviewFrame(
              active: previewed,
              child: Stack(
                children: [
                  Positioned.fill(
                    // THE tile, with nothing switched off (user 2026-07-27:
                    // "genau diese Kachel"): the place it lands in on the
                    // Market is the same tile, so the one you are comparing
                    // against here has to be too.
                    child: CreatureCard(
                      creature: c,
                      onTap: loaded
                          ? null
                          : () => setState(() => _preview = c),
                    ),
                  ),
                  if (loaded)
                    const Positioned(
                      top: 0,
                      left: 0,
                      child: PixelIcon(
                        Icons.check_circle,
                        size: 18,
                        color: _accent,
                      ),
                    ),
                ],
              ),
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

  /// The left panel: carry and speed — the two stats a hauler is actually
  /// picked on here, same as the tile's own caption.
  Widget _detail() {
    final c = _preview;
    if (c == null) {
      return const PickerDetailPanel(
        placeholder: 'Tap a monster to see its details.',
      );
    }
    final loaded = _loaded(c);
    return PickerDetailPanel(
      art: CreatureCard(creature: c, showHp: false),
      title: c.displayName,
      subtitle: 'Lv ${c.level}',
      rows: [
        pickerStatRow('Carry', '🏋 ${c.statValue(CreatureStat.carry)}'),
        pickerStatRow('Speed', '🥾 ${c.statValue(CreatureStat.speed)}'),
      ],
      action: pickerChooseButton(
        label: loaded ? 'Already loaded' : 'Add this hauler',
        onTap: loaded ? null : () => Navigator.pop(context, [c]),
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
    entries: const [MapEntry('carry', 'Carry'), MapEntry('speed', 'Speed')],
    onSelected: (v) =>
        setState(() => _sortStat = CreatureStat.values.byName(v)),
  );

  /// Filter, added alongside search+sort everywhere a monster is picked
  /// (user 2026-09-11).
  Widget _filterPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.filter_alt_outlined,
    label: _filterElement?.label ?? 'Every type',
    engaged: _filterElement != null,
    value: _filterElement?.name ?? '',
    entries: [
      const MapEntry('', 'Every type'),
      for (final e in CreatureElement.values)
        if (e != CreatureElement.neutral)
          MapEntry(e.name, '${e.emoji} ${e.label}'),
    ],
    onSelected: (v) => setState(
      () => _filterElement = v.isEmpty ? null : CreatureElement.fromName(v),
    ),
  );
}
