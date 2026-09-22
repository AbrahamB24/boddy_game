import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/duration_format.dart';
import '../../core/ui/number_format.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart' show kMonsterTileAspect;
import '../settlement/settlement_controller.dart';
import 'bestiary_screen.dart';
import 'hatchery_screen.dart';
import 'creature_detail_screen.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'starter_preview_screen.dart';
import 'teams_screen.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_sprite.dart';

/// Sort orders for the collection grid (user request 2026-07-17). `newest`
/// is the controller's own order — catch order — so the default costs no
/// sort at all.
enum _SortMode {
  newest('Newest'),
  power('Power'),
  level('Level'),
  name('Name'),
  rarity('Rarity');

  final String label;
  const _SortMode(this.label);
}

// The player's creature collection (opened from the settlement's quick
// menu). Empty collection = one-time starter pick from all defined species;
// afterwards new creatures come from catching (phase 5) and breeding
// (phase 6).
//
// "Hubs rechts" (user 2026-09-19, picked from ten layouts): a full-screen menu
// in the cream kit. The grid of type-coloured tiles fills the left; at the right
// stand three cards that are the doors to Teams, Breeding and the Bestiary AND
// show their state — the active team and its power, the matings running and
// when the first is ready, how much of the Bestiary is filled in — so you see
// that something is done without opening it.
//
// The grid's own cell sizing is NEW (not [monsterTileWidth]/[kMonsterTileCols]):
// that shared helper reads the device's raw width, which in landscape is this
// screen's long axis (up to 932px) — feeding it 3 fixed columns would size a
// tile taller than the whole screen. An auto-flowing max-cross-axis-extent grid
// picks however many columns actually fit instead.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();
  final _breeding = BreedingController();

  // Sort + filter state (user request 2026-07-17). Null filter = show all.
  // Picking the already-active sort mode flips the direction (user request:
  // second tap = reversed order); picking a different mode resets to that
  // mode's natural direction.
  _SortMode _sort = _SortMode.newest;
  bool _sortReversed = false;
  // Search folded away behind its own icon (user 2026-08-28: "den Filter und
  // die Such- und Sortierfunktion in Icons umwandeln").
  bool _searchOpen = false;
  // Multi-select filters (user 2026-07-18): the filter dropdown stays open and
  // lets you toggle any number of elements/rarities; empty set = no constraint.
  final Set<CreatureElement> _elementFilters = {};
  final Set<CreatureRarity> _rarityFilters = {};

  // The filter dropdown is a custom overlay (not a PopupMenu) so it can stay
  // open across multiple toggles and only dismiss when tapping outside its box.
  final LayerLink _filterLink = LayerLink();
  OverlayEntry? _filterOverlay;

  // Name search (user 2026-07-18): a non-empty query filters the grid by
  // display name.
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// The pills' own palette on a cream card — the shared look the egg picker and
  /// the breeding screen wear.
  static final PillPalette _pills = PillPalette.cream;

  /// The grid's list: filtered, then sorted. A creature whose species def
  /// was removed has no element/rarity to match, so any active filter hides
  /// it rather than crashing on null.
  List<CreatureInstance> _visibleCreatures() {
    final query = _searchQuery.trim().toLowerCase();
    final list = _ctrl.creatures.where((c) {
      final species = c.species;
      if (_elementFilters.isNotEmpty &&
          !_elementFilters.contains(species?.element)) {
        return false;
      }
      if (_rarityFilters.isNotEmpty &&
          !_rarityFilters.contains(species?.rarity)) {
        return false;
      }
      if (query.isNotEmpty && !c.displayName.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
    int byPower(CreatureInstance a, CreatureInstance b) =>
        totalPower(b).compareTo(totalPower(a));
    switch (_sort) {
      case _SortMode.newest:
        break; // controller order IS catch order
      case _SortMode.power:
        list.sort(byPower);
      case _SortMode.level:
        list.sort((a, b) {
          final byLevel = b.level.compareTo(a.level);
          return byLevel != 0 ? byLevel : byPower(a, b);
        });
      case _SortMode.name:
        list.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      case _SortMode.rarity:
        list.sort((a, b) {
          final byRarity = (b.species?.rarity.index ?? -1).compareTo(
            a.species?.rarity.index ?? -1,
          );
          return byRarity != 0 ? byRarity : byPower(a, b);
        });
    }
    return _sortReversed ? list.reversed.toList() : list;
  }

  @override
  void initState() {
    super.initState();
    _ctrl.load();
    // Blocks breeding parents out of the training-battle team.
    _breeding.load();
  }

  @override
  void dispose() {
    _filterOverlay?.remove();
    _filterOverlay = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  void _previewStarter(SpeciesDef species) {
    pushMenu(context, StarterPreviewScreen(species: species));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_ctrl, _breeding, _settlement]),
    builder: (context, _) => MenuScaffold(
      title: 'Monsters',
      trailing: _housingReadout(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The whole collection on one cream card.
            Expanded(
              child: creamCard(
                child: Column(
                  children: [
                    if (_ctrl.creatures.isNotEmpty) _sortFilterBar(),
                    Expanded(
                      child: _ctrl.isLoading && _ctrl.creatures.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: CreamPalette.gold,
                              ),
                            )
                          : _ctrl.creatures.isEmpty
                          ? _starterPicker()
                          : _collectionGrid(),
                    ),
                  ],
                ),
              ),
            ),
            // The three doors, with their state. Nothing to show until there is
            // a first monster.
            if (_ctrl.creatures.isNotEmpty) ...[
              const SizedBox(width: 12),
              SizedBox(width: 204, child: _hubs()),
            ],
          ],
        ),
      ),
    ),
  );

  /// "14 · housing 12/16" at the right of the title card — how many monsters
  /// you have and how many the settlement can shelter.
  Widget _housingReadout() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      '${_ctrl.creatures.length} · housing '
      '${_settlement.housingUsed}/${_settlement.housingCapacity}',
      style: FoE.value(size: 11).copyWith(color: kBoxInk),
    ),
  );

  // ── The three hubs ─────────────────────────────────────────
  Widget _hubs() {
    final team = _ctrl.activeTeam;
    final members = team == null
        ? const <CreatureInstance>[]
        : [
            for (final id in team.memberIds)
              ..._ctrl.creatures.where((c) => c.id == id),
          ];
    final teamPower = members.fold<int>(0, (s, c) => s + totalPower(c));

    final mating = _breeding.matingJobs;
    final eggs = _breeding.eggs;
    final ready = mating.where((j) => j.isReady).length;
    final soonest = mating
        .where((j) => !j.isReady)
        .fold<Duration?>(
          null,
          (best, j) => best == null || j.remaining < best ? j.remaining : best,
        );

    final bestiary = bestiaryProgress(_ctrl.creatures);

    return Column(
      children: [
        Expanded(
          child: _hub(
            icon: Icons.shield,
            title: 'Teams',
            line1: team == null
                ? 'No team yet'
                : '${team.name} · ${members.length}/${_ctrl.teamSizeCap}',
            line2: team == null
                ? 'Tap to set one up'
                : 'Power ${shortNumber(teamPower)}',
            onTap: () async {
              await pushMenu(context, const TeamsScreen());
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 9),
        Expanded(
          child: _hub(
            icon: Icons.egg,
            title: 'Breeding',
            line1: mating.isEmpty
                ? 'Nothing running'
                : '${mating.length} mating${mating.length == 1 ? '' : 's'} running',
            line2: ready > 0
                ? 'Ready — collect it'
                : soonest != null
                ? 'Ready in ${fmtDuration(soonest.inSeconds.toDouble())}'
                : eggs.isNotEmpty
                ? '${eggs.length} egg${eggs.length == 1 ? '' : 's'} waiting'
                : 'Pair two monsters',
            // Something to collect is what the amber is for.
            highlight: ready > 0,
            onTap: () => pushMenu(
              context,
              const HatcheryScreen(startOn: NurseryTab.breeding),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Expanded(
          child: _hub(
            icon: Icons.menu_book,
            title: 'Bestiary',
            line1: '${bestiary.seen} of ${bestiary.total} seen',
            line2: bestiary.total == 0
                ? ''
                : '${(bestiary.seen / bestiary.total * 100).round()} % complete',
            progress: bestiary.total == 0
                ? null
                : bestiary.seen / bestiary.total,
            onTap: () => pushMenu(context, const BestiaryScreen()),
          ),
        ),
      ],
    );
  }

  /// One hub: a round amber glyph, the door's name and a line of state, a
  /// chevron, and under it the number that matters (and, for the Bestiary, how
  /// far along it is). The whole card is the tap target.
  Widget _hub({
    required IconData icon,
    required String title,
    required String line1,
    required String line2,
    required VoidCallback onTap,
    double? progress,
    bool highlight = false,
  }) => Pressable(
    onTap: onTap,
    child: creamCard(
      deep: highlight ? CreamPalette.goldDeep : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CreamPalette.gold,
                  boxShadow: [
                    BoxShadow(
                      color: CreamPalette.goldDeep,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 18, color: CreamPalette.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: FoE.title(size: 14).copyWith(color: kBoxInk),
                    ),
                    Text(
                      line1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: kBoxAccent),
            ],
          ),
          const SizedBox(height: 7),
          if (line2.isNotEmpty)
            Text(
              line2,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 11.5).copyWith(
                color: highlight ? kBoxAccent : kBoxInk,
                fontWeight: FontWeight.w800,
              ),
            ),
          if (progress != null) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                color: CreamPalette.gold,
                backgroundColor: kBoxInk.withValues(alpha: 0.15),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  // ── Starter pick (empty collection) ────────────────────────
  Widget _starterPicker() {
    final species = starterChoices();
    if (species.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            kSpeciesDefs.isEmpty
                ? 'No species defined yet.\n'
                      'Create them in Dev Mode (Species tab).'
                // Species exist but no fire/water/plant epic: the starter pool
                // is those three, so say THAT rather than "none defined".
                : 'No starter species defined yet.\n'
                      'Starters are the three fire/water/plant epics — add '
                      'them in Dev Mode (Species tab).',
            textAlign: TextAlign.center,
            style: FoE.label(size: 13).copyWith(color: kBoxInk),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
          child: Text(
            'Choose your starter!',
            style: FoE.title(size: 18).copyWith(color: kBoxInk),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Your first creature — it starts at Level 5. The three starters '
            'are fire, water and plant; pick your element.',
            style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 170,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: species.length,
            itemBuilder: (_, i) => _speciesCard(species[i]),
          ),
        ),
      ],
    );
  }

  Widget _speciesCard(SpeciesDef species) {
    return Pressable(
      onTap: () => _previewStarter(species),
      child: Container(
        // A raised tile with the rarity's colour as its rim.
        decoration: raisedTile().copyWith(
          border: Border.all(color: species.rarity.color, width: 2.5),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(
              child: CreatureBackdrop(
                element: species.element,
                child: _creatureImage(species.stageAt(0).imageUrl),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              species.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.label(size: 13).copyWith(color: kBoxInk),
            ),
            const SizedBox(height: 2),
            Text(
              '${species.element.emoji} ${species.element.label} · ${species.rarity.label}',
              style: FoE.dim(size: 10).copyWith(color: species.rarity.color),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search + filter + sort bar ─────────────────────────────
  Widget _sortFilterBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _glyphBtn(
              _searchOpen ? Icons.search_off : Icons.search,
              () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen && _searchQuery.isNotEmpty) {
                  _searchCtrl.clear();
                  _searchQuery = '';
                }
              }),
              tooltip: _searchQuery.isEmpty
                  ? 'Search'
                  : 'Search: "$_searchQuery"',
              engaged: _searchOpen || _searchQuery.isNotEmpty,
            ),
            CompositedTransformTarget(
              link: _filterLink,
              child: _filterGlyphBtn(),
            ),
            _sortGlyphBtn(),
            const SizedBox(width: 2),
            // What the order is, in words — the icon alone never said.
            Text(
              '${_sort.label}${_sortReversed ? ' ↑' : ''}',
              style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
            ),
          ],
        ),
        if (_searchOpen) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 280,
            child: SearchPill(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              palette: _pills,
            ),
          ),
        ],
      ],
    ),
  );

  /// One small button: raised cream, amber when engaged.
  Widget _glyphBtn(
    IconData icon,
    VoidCallback onTap, {
    required String tooltip,
    String? badge,
    bool engaged = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: engaged ? goldButton() : raisedTile(radius: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: kBoxInk),
              if (badge != null) ...[
                const SizedBox(width: 4),
                Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kBoxInk,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  // Filter: a CUSTOM overlay dropdown (not a PopupMenu) so it stays open across
  // multiple toggles and dismisses only when you tap outside its box (user
  // 2026-07-18). Multiple elements/rarities can be active at once, which is
  // why a tap opens [_openFilterMenu] rather than a single-choice PopupMenu.
  String get _filterTooltip {
    final count = _elementFilters.length + _rarityFilters.length;
    return switch (count) {
      0 => 'All monsters',
      1 =>
        _elementFilters.isNotEmpty
            ? _elementFilters.first.label
            : _rarityFilters.first.label,
      _ => '$count filters',
    };
  }

  Widget _filterGlyphBtn() {
    final count = _elementFilters.length + _rarityFilters.length;
    return _glyphBtn(
      count > 0 ? Icons.filter_alt : Icons.filter_alt_outlined,
      _toggleFilterMenu,
      tooltip: _filterTooltip,
      engaged: count > 0,
      badge: count > 0 ? '$count' : null,
    );
  }

  /// The sort trigger. Its own [PopupMenuButton] rather than [_glyphBtn]
  /// because the menu IS the tap target here — only the face is bare instead of
  /// carrying the mode's name.
  Widget _sortGlyphBtn() {
    final engaged = _sort != _SortMode.newest || _sortReversed;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Sort: ${_sort.label}${_sortReversed ? ' (reversed)' : ''}',
        child: PopupMenuButton<String>(
          tooltip: '',
          color: CreamPalette.paperTop,
          elevation: 10,
          position: PopupMenuPosition.under,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: CreamPalette.tan, width: 1.5),
          ),
          onSelected: (name) => setState(() {
            final mode = _SortMode.values.byName(name);
            if (mode == _sort) {
              _sortReversed = !_sortReversed;
            } else {
              _sort = mode;
              _sortReversed = false;
            }
          }),
          itemBuilder: (_) => [
            for (final mode in _SortMode.values)
              PopupMenuItem<String>(
                value: mode.name,
                height: 40,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        mode.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: mode == _sort ? kBoxAccent : kBoxInk,
                        ),
                      ),
                    ),
                    if (mode == _sort)
                      Text(
                        _sortReversed ? '↑' : '↓',
                        style: TextStyle(fontSize: 13, color: kBoxAccent),
                      ),
                  ],
                ),
              ),
          ],
          // A plain decorated box — PopupMenuButton already wraps this in its
          // own tap handler to open the menu.
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: engaged ? goldButton() : raisedTile(radius: 12),
            child: const Icon(Icons.swap_vert, size: 18, color: kBoxInk),
          ),
        ),
      ),
    );
  }

  void _toggleFilterMenu() =>
      _filterOverlay != null ? _closeFilterMenu() : _openFilterMenu();

  void _closeFilterMenu() {
    _filterOverlay?.remove();
    _filterOverlay = null;
  }

  void _openFilterMenu() {
    final elements = <CreatureElement>{
      for (final c in _ctrl.creatures)
        if (c.species != null) c.species!.element,
    }.toList()..sort((a, b) => a.index.compareTo(b.index));
    final rarities = <CreatureRarity>{
      for (final c in _ctrl.creatures)
        if (c.species != null) c.species!.rarity,
    }.toList()..sort((a, b) => a.index.compareTo(b.index));

    _filterOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Full-screen barrier: a tap anywhere outside the box closes it.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeFilterMenu,
            ),
          ),
          CompositedTransformFollower(
            link: _filterLink,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 6),
            // StatefulBuilder lets a toggle refresh the box's checkmarks
            // without closing/reopening the overlay.
            child: StatefulBuilder(
              builder: (_, setInner) =>
                  _filterMenuBox(elements, rarities, setInner),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_filterOverlay!);
  }

  Widget _filterMenuBox(
    List<CreatureElement> elements,
    List<CreatureRarity> rarities,
    StateSetter setInner,
  ) {
    final hasFilter = _elementFilters.isNotEmpty || _rarityFilters.isNotEmpty;
    // Toggle helper: mutate the set, refresh the grid AND the open box.
    void toggle(VoidCallback mutate) {
      setState(mutate);
      setInner(() {});
    }

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 220,
        // A cream card of its own, on top of the page — the kit's, not a
        // separate material.
        child: creamCard(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in elements)
                    _filterRow(
                      label: '${e.emoji} ${e.label}',
                      active: _elementFilters.contains(e),
                      onTap: () => toggle(() {
                        if (!_elementFilters.remove(e)) _elementFilters.add(e);
                      }),
                    ),
                  // A single-rarity collection can't be narrowed by rarity.
                  if (elements.isNotEmpty && rarities.length > 1)
                    _menuDivider(),
                  if (rarities.length > 1)
                    for (final r in rarities)
                      _filterRow(
                        label: r.label,
                        color: r.color,
                        active: _rarityFilters.contains(r),
                        onTap: () => toggle(() {
                          if (!_rarityFilters.remove(r)) _rarityFilters.add(r);
                        }),
                      ),
                  if (hasFilter) ...[
                    _menuDivider(),
                    _filterRow(
                      label: 'Clear filters',
                      active: false,
                      onTap: () => toggle(() {
                        _elementFilters.clear();
                        _rarityFilters.clear();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuDivider() => Container(
    height: 1,
    color: CreamPalette.tan.withValues(alpha: 0.6),
    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
  );

  Widget _filterRow({
    required String label,
    required bool active,
    required VoidCallback onTap,
    Color? color,
  }) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: active ? (color ?? kBoxAccent) : kBoxInkFaint,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            // A rarity row (color != null) always shows its name in the rarity
            // colour; other rows follow the active/inactive scheme (user
            // 2026-07-18).
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color ?? (active ? kBoxAccent : kBoxInk),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Collection grid ────────────────────────────────────────
  Widget _collectionGrid() {
    final list = _visibleCreatures();
    if (list.isEmpty) {
      return Center(
        child: Text(
          'Nothing matches the filter.',
          style: TextStyle(color: kBoxInkSoft, fontSize: 12),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      // Auto-flowing (2026-09-18, landscape) — see this file's own doc
      // comment on why the shared monsterTileWidth/kMonsterTileCols
      // convention doesn't fit here any more.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 112,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: kMonsterTileAspect,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => CreatureCard(
        creature: list[i],
        onTap: () =>
            pushMenu(context, CreatureDetailScreen(creatureId: list[i].id)),
      ),
    );
  }

  Widget _creatureImage(
    String? url, {
    Alignment alignment = Alignment.center,
  }) => url == null
      ? const Center(child: Icon(Icons.pets, color: CreamPalette.tan, size: 40))
      : CreatureSprite(
          url: url,
          alignment: alignment,
          fallback: const Center(
            child: Icon(Icons.pets, color: CreamPalette.tan, size: 40),
          ),
        );
}
