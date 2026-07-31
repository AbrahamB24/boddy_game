import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/settlement_controller.dart';
import 'bestiary_screen.dart';
import 'breeding_screen.dart';
import 'creature_detail_screen.dart';
import 'models/creature_enums.dart';
import 'services/creature_power.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creatures_controller.dart';
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

// The player's creature collection (FoE look, opened from the settlement's
// quick menu). Empty collection = one-time starter pick from all defined
// species; afterwards new creatures come from catching (phase 5) and
// breeding (phase 6).
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();

  // Sort + filter state (user request 2026-07-17). Null filter = show all.
  // Picking the already-active sort mode flips the direction (user request:
  // second tap = reversed order); picking a different mode resets to that
  // mode's natural direction.
  _SortMode _sort = _SortMode.newest;
  bool _sortReversed = false;
  // Multi-select filters (user 2026-07-18): the filter dropdown stays open and
  // lets you toggle any number of elements/rarities; empty set = no constraint.
  final Set<CreatureElement> _elementFilters = {};
  final Set<CreatureRarity> _rarityFilters = {};

  // The filter dropdown is a custom overlay (not a PopupMenu) so it can stay
  // open across multiple toggles and only dismiss when tapping outside its box.
  final LayerLink _filterLink = LayerLink();
  OverlayEntry? _filterOverlay;

  // Name search (user 2026-07-18): a non-empty query filters the grid by
  // display name. The field is ALWAYS on screen since the pills landed (user
  // 2026-07-27) — it was behind a toggle to save a row, and the pills spend
  // that row anyway.
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  /// The page is parchment, so its pills are — the same shared look the egg
  /// picker and the breeding screen wear.
  static final PillPalette _pills = PillPalette.parchment;

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
    BreedingController().load();
  }

  @override
  void dispose() {
    _filterOverlay?.remove();
    _filterOverlay = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _adoptStarter(SpeciesDef species) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FoE.panelDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: FoE.borderGold),
        ),
        title: Text('Choose ${species.name}?', style: FoE.title(size: 15)),
        content: Text(
          'Your starter accompanies you from the very beginning. This choice is final!',
          style: FoE.label(size: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: FoE.dim(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Choose',
              style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final created = await _ctrl.adoptStarter(species);
    if (created != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatureDetailScreen(creatureId: created.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) => ParchmentPage(
      title: 'Monsters',
      trailing: _barActions(),
      child: Column(
        children: [
          if (_ctrl.creatures.isNotEmpty) _sortFilterBar(),
          Expanded(
            child: _ctrl.isLoading && _ctrl.creatures.isEmpty
                ? const Center(child: CircularProgressIndicator(color: FoE.gold))
                : _ctrl.creatures.isEmpty
                ? _starterPicker()
                : _collectionGrid(),
          ),
        ],
      ),
    ),
  );


  // One row of ICON buttons (user decision 2026-07-17): Teams, Breeding and
  // dev-Heal to the left of Bestiary, which sits rightmost and carries the
  // collection count — the old "N collected" label in one glyph. Tooltips
  // carry the names the labels used to. The training battle moved to the
  // Training Grounds building (kTrainingGroundsBuildingId).
  /// The bar's right-hand end: Teams, Breeding and dev-Heal, then Bestiary
  /// carrying the collection count — the old "N collected" label in one glyph.
  /// Tooltips carry the names the labels used to.
  Widget _barActions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _iconBtn('🛡️', tooltip: 'Teams', () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TeamsScreen()),
        );
        if (mounted) setState(() {});
      }),
      if (_ctrl.creatures.isNotEmpty)
        _iconBtn('🥚', tooltip: 'Breeding', () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BreedingScreen()),
        )),
      if (_settlement.isDev && _ctrl.creatures.isNotEmpty)
        // free: this is the dev tool — it deliberately skips the goods cost AND
        // the wait the Healing Hut charges players.
        _iconBtn('🛠', tooltip: 'Heal all (dev)', () =>
            _ctrl.healAll(free: true)),
      _iconBtn(
        '📖',
        tooltip: 'Bestiary',
        badge: '${_ctrl.creatures.length}',
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BestiaryScreen()),
        ),
      ),
    ],
  );

  Widget _iconBtn(
    String emoji,
    VoidCallback onTap, {
    required String tooltip,
    String? badge,
    bool gold = false,
  }) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FoE.radiusSmall),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: FoE.btn(active: gold),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 15)),
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    badge,
                    style: FoE.value(size: 11)
                        .copyWith(color: gold ? Colors.white : FoE.goldBright),
                  ),
                ],
              ],
            ),
          ),
        ),
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
            style: FoE.label(size: 13),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
          child: Text('Choose your starter!', style: FoE.title(size: 18)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Your first creature — it starts at Level 5. The three starters '
            'are fire, water and plant; pick your element.',
            style: FoE.dim(size: 12),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
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
    return GestureDetector(
      onTap: () => _adoptStarter(species),
      child: Container(
        decoration: FoE.panel(radius: 10, overrideBorder: species.rarity.color),
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
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
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
  // THE EGG PICKER'S PILLS (user 2026-07-27: "alle filter und
  // sortierfunktionien sollen so aussehen wie bei den eggs") — the shared
  // widgets in features/common/widgets/filter_pills.dart, in the DARK palette
  // because this page is FoE's panels, not parchment.
  //
  // Two rows now, laid out exactly as over there: the search full width, the
  // filter and the sort beside each other under it. It was one row of icon
  // squares with the search field folded away behind a toggle — a row that
  // showed three glyphs and no values, so "is anything filtered?" took a tap to
  // answer. The pills spend a line to say it outright.
  Widget _sortFilterBar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
    child: Column(
      children: [
        SearchPill(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          palette: _pills,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _filterPill()),
            const SizedBox(width: 8),
            Expanded(child: _sortPill()),
          ],
        ),
      ],
    ),
  );

  /// The sort pill. The direction toggle predates the pills here (user
  /// 2026-07-18) and survives unchanged — the pill just shows the arrow on its
  /// face instead of only inside the menu.
  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: _sort.label,
    engaged: _sort != _SortMode.newest || _sortReversed,
    value: _sort.name,
    entries: [
      for (final mode in _SortMode.values) MapEntry(mode.name, mode.label),
    ],
    trailing: Icon(
      _sortReversed ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: FoE.goldBright,
    ),
    selectedTrailing: _sortReversed ? '↑' : '↓',
    onSelected: (name) => setState(() {
      final mode = _SortMode.values.byName(name);
      if (mode == _sort) {
        _sortReversed = !_sortReversed;
      } else {
        _sort = mode;
        _sortReversed = false;
      }
    }),
  );

  // Filter: a CUSTOM overlay dropdown (not a PopupMenu) so it stays open across
  // multiple toggles and dismisses only when you tap outside its box (user
  // 2026-07-18). Multiple elements/rarities can be active at once — which is
  // why this one is an [ActionPill] and not a [MenuPill]: a popup menu picks
  // ONE value, and this control's whole point is that it does not.
  Widget _filterPill() {
    final count = _elementFilters.length + _rarityFilters.length;
    return CompositedTransformTarget(
      link: _filterLink,
      child: ActionPill(
        palette: _pills,
        icon: count > 0 ? Icons.filter_alt : Icons.filter_alt_outlined,
        // Names the ONE filter when there is one, counts them when there are
        // several — "3 filters" beats a lit icon that hides which three.
        label: switch (count) {
          0 => 'All monsters',
          1 => _elementFilters.isNotEmpty
              ? _elementFilters.first.label
              : _rarityFilters.first.label,
          _ => '$count filters',
        },
        engaged: count > 0,
        onTap: _toggleFilterMenu,
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
      child: Container(
        width: 220,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: ShapeDecoration(color: FoE.panelMid, shape: FoE.facet(radius: 10, side: BorderSide(color: FoE.borderGold))),
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
              if (elements.isNotEmpty && rarities.length > 1) _menuDivider(),
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
    );
  }

  Widget _menuDivider() => Container(
    height: 1,
    color: FoE.border,
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
            color: active ? (color ?? FoE.goldBright) : FoE.textDim,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            // A rarity row (color != null) always shows its name in the rarity
            // colour; other rows follow the active/inactive scheme (user
            // 2026-07-18).
            style: FoE.label(size: 12).copyWith(
              color: color ?? (active ? FoE.goldBright : FoE.parchment),
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
          style: FoE.dim(size: 12),
        ),
      );
    }
    return GridView.builder(
      // Side padding clears the meander bands (2026-07-27); the bottom keeps
      // the last row off the screen edge.
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        // Exactly 3 tiles per row (user 2026-07-17).
        crossAxisCount: 3,
        // Row gap = column gap (user 2026-07-18): the art box is confined to its
        // own cell, so this is the GUARANTEED minimum clearance between a card
        // and the next row's popped-out monster — they can never overlap.
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Shorter tiles than before so a square sprite nearly fills the art area
        // — this shrinks the empty space above the sprite that used to push the
        // rows apart (user 2026-07-18).
        childAspectRatio: 0.70,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => CreatureCard(
        creature: list[i],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CreatureDetailScreen(creatureId: list[i].id),
          ),
        ),
      ),
    );
  }

  Widget _creatureImage(String? url, {Alignment alignment = Alignment.center}) =>
      url == null
      ? const Center(child: Icon(Icons.pets, color: FoE.gold, size: 40))
      : CreatureSprite(
          url: url,
          alignment: alignment,
          fallback:
              const Center(child: Icon(Icons.pets, color: FoE.gold, size: 40)),
        );
}
