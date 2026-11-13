import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/voxel_kit.dart'
    show VoxelBackdrop, VoxelBar, VoxelShape, Voxel, vr;
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart' show kMonsterTileAspect;
import '../settlement/settlement_controller.dart';
import 'bestiary_screen.dart';
import 'hatchery_screen.dart';
import 'lair_screen.dart';
import 'services/lair_controller.dart';
import 'creature_detail_screen.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'starter_preview_screen.dart';
import 'teams_screen.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_family.dart' show CreatureFigure, creatureHpColor;
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

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

  /// The pills' own palette on the blue card — the shared look the egg picker and
  /// the breeding screen wear.
  static final PillPalette _pills = PillPalette.cream;

  /// Starter preview drafts, one per species, cached so the picker's tile
  /// doesn't reroll a new gender/genes on every rebuild — see [_starterDraft].
  final Map<String, CreatureInstance> _starterDrafts = {};

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
    // Lairs: settle finished upgrades and collect what trainers earned.
    LairController().load();
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
    builder: (context, _) {
      // No "Monsters · housing" header while there is nothing to count yet
      // and nowhere earlier to close back to (user 2026-10-01: "der ganze
      // Header kannst du bei diesem Screen löschen") — exactly the branch
      // below that renders [_starterPicker] instead of the grid.
      final showingStarterPicker = !_ctrl.isLoading && _ctrl.creatures.isEmpty;
      return MenuScaffold(
        showHeader: !showingStarterPicker,
        bare: true,
        title: 'Monsters',
        trailing: _headerTools(),
        // No card of its own any more (user 2026-09-30, spotting the outer
        // card still wrapping the grid+hubs Row: "die grosse Kachel...
        // braucht es nicht" — MenuScaffold is already the one card on
        // screen). Grid and hubs ARE different Gebiete — browsing versus
        // where else to go — so the hubs keep a [zoneBox] of their own; the
        // three hubs inside it are all the same KIND of thing (a shortcut),
        // so they're plain [raisedTile] rows, not a card each.
        // No bottom Padding around this Row any more (used to add a dead
        // 10px strip below both the grid and the hubs panel, on top of
        // MenuScaffold's own card padding) — trimmed so the grid gets that
        // space too, see [_collectionGrid].
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _content()),
            // The doors: one small button each. Nothing to show until there is
            // a first monster.
            if (_ctrl.creatures.isNotEmpty) ...[
              const SizedBox(width: 10),
              SizedBox(width: 54, child: _hubs()),
            ],
          ],
        ),
      );
    },
  );

  Widget _content() => Column(
    children: [
      if (_searchOpen && _ctrl.creatures.isNotEmpty) _searchRow(),
      Expanded(
        child: _ctrl.isLoading && _ctrl.creatures.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: CreamPalette.gold),
              )
            : _ctrl.creatures.isEmpty
            ? _starterPicker()
            : _collectionGrid(),
      ),
    ],
  );

  /// "14 · housing 12/16" at the right of the title card — how many monsters
  /// you have and how many the settlement can shelter.
  Widget _housingReadout() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    // A recess in the card, like the cells of the main screen.
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.22),
      borderRadius: vr(8),
      border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.6)),
    ),
    child: Text(
      '${_ctrl.creatures.length} · housing '
      '${_settlement.housingUsed}/${_settlement.housingCapacity}',
      style: FoE.value(size: 12).copyWith(color: kBoxInk),
    ),
  );

  // ── The three hubs ─────────────────────────────────────────
  // All three read down to ONE stat now (user 2026-09-30: "n Teams" /
  // "n/n" / "13%", nothing else written) — each sits in the SAME slot
  // (line1, beside the title) so the three cards read as one family at a
  // glance instead of each inventing its own second line.
  Widget _hubs() {
    final teams = _ctrl.battleTeams;
    final mating = _breeding.matingJobs;
    final ready = mating.where((j) => j.isReady).length;
    final bestiary = bestiaryProgress(_ctrl.creatures);
    final bestiaryPct = bestiary.total == 0
        ? 0
        : (bestiary.seen / bestiary.total * 100).round();
    final lairs = lairHubLine();

    return SingleChildScrollView(
      child: Column(
        children: [
          _hub(
            icon: Icons.shield,
            tip: teams.isEmpty ? 'Teams · none yet' : 'Teams · ${teams.length}',
            stat: '${teams.length}',
            onTap: () async {
              await pushMenu(context, const TeamsScreen());
              if (mounted) setState(() {});
            },
          ),
          _hub(
            icon: Icons.egg,
            tip: 'Breeding · ${mating.length}/${_breeding.breedingSlots}',
            stat: '${mating.length}/${_breeding.breedingSlots}',
            // Something to collect: the gold button.
            highlight: ready > 0,
            onTap: () => pushMenu(
              context,
              const HatcheryScreen(startOn: NurseryTab.breeding),
            ),
          ),
          _hub(
            icon: Icons.castle,
            tip: 'Lairs · $lairs',
            stat: lairs.split(' ').first,
            onTap: () async {
              await pushMenu(context, const LairScreen());
              if (mounted) setState(() {});
            },
          ),
          _hub(
            icon: Icons.menu_book,
            tip: 'Bestiary · $bestiaryPct%',
            stat: '$bestiaryPct%',
            onTap: () => pushMenu(context, const BestiaryScreen()),
          ),
        ],
      ),
    );
  }

  /// One hub = ONE small button (user 2026-11-10): the door's glyph with its
  /// one figure underneath; the full name is the tooltip.
  Widget _hub({
    required IconData icon,
    required String tip,
    required String stat,
    required VoidCallback onTap,
    bool highlight = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Tooltip(
      message: tip,
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: highlight ? goldButton() : menuButton(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PixelIcon(
                icon,
                size: 20,
                color: highlight ? CreamPalette.ink : kBoxInk,
              ),
              const SizedBox(height: 3),
              Text(
                stat,
                maxLines: 1,
                style: FoE.label(size: 10).copyWith(
                  color: highlight ? CreamPalette.ink : kBoxInkFaint,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // ── Starter pick (empty collection) ────────────────────────
  /// An unsaved, rolled stand-in for a not-yet-adopted species — the same
  /// trick [StarterPreviewScreen]'s own `_draft` uses — so the picker's tile
  /// can go through the real [CreatureCard] like every other monster tile in
  /// the app, instead of a one-off display. Cached per species: a fresh
  /// draft every build would reroll gender and genes each time, flickering
  /// the tile's ⚡ power and gender mark as the picker animates.
  CreatureInstance _starterDraft(SpeciesDef species) =>
      _starterDrafts.putIfAbsent(species.id, () {
        final rng = math.Random();
        return CreatureInstance(
          id: '',
          userId: '',
          speciesId: species.id,
          gender: rng.nextBool() ? CreatureGender.male : CreatureGender.female,
          level: 1,
          statBase: CreatureInstance.rollBaseGenes(species, rng),
          statSlope: CreatureInstance.rollSlopeGenes(species, rng),
          isStarter: true,
          learnedAbilityIds: null,
        )..backfillAbilities();
      });

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
    // Triptych (user 2026-10-01, picked from 10 mockups): three fanned
    // cards rather than a plain grid — the centre one stands forward, the
    // outer two tilt and sit back a little. Every card is tappable, not
    // just the centre one; "forward" is a visual cue, not a selection
    // state the player has to set up first.
    final centerIndex = (species.length - 1) / 2;
    // Centred, not left-aligned (user 2026-10-01, once the header above it
    // was gone: "dafür den Text zentrieren") — with no title row left to
    // line up against, a left-stuck headline just reads as stray.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          child: Text(
            'Choose your starter!',
            textAlign: TextAlign.center,
            style: FoE.title(size: 18).copyWith(color: kBoxInk),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Your first creature — the three starters are fire, water and '
            'plant; pick your element.',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12).copyWith(color: kBoxInkFaint),
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < species.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _triptychCard(species[i], i - centerIndex),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One fanned card. [offset] is this card's distance from the centre of
  /// the fan (0 = centre, ±1 = one step out) — tilt, lift and scale all
  /// read off it, so the fan still makes sense whatever [species] turns out
  /// to hold (today always 3, see [starterChoices]).
  ///
  /// The monster itself is the shared [CreatureCard] tile — the Monsters
  /// screen's own — in place of a one-off display built for this screen
  /// alone (user 2026-10-01: "nimm hier die Monsterkacheln, welche bereits
  /// bestehen"). No frame around it any more (user, same day: "mach die
  /// Kacheln noch grösser, dafür braucht es keinen Rahmen" — bigger, the
  /// fan's own scale/lift/opacity already carries the centre card forward
  /// without a border drawn on top of the tile's own element-coloured foot).
  Widget _triptychCard(SpeciesDef species, double offset) {
    final center = offset == 0;
    final dist = offset.abs().clamp(0.0, 2.0);
    final draft = _starterDraft(species);
    return Transform.translate(
      offset: Offset(0, center ? -14 : 8.0 * dist),
      child: Transform.rotate(
        angle: offset.clamp(-1.4, 1.4) * 0.08,
        child: Transform.scale(
          scale: center ? 1.0 : (1 - 0.07 * dist).clamp(0.8, 1.0),
          child: Opacity(
            opacity: center ? 1 : 0.88,
            child: SizedBox(
              width: 230,
              child: AspectRatio(
                aspectRatio: kMonsterTileAspect,
                child: CreatureCard(
                  creature: draft,
                  onTap: () => _previewStarter(species),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerTools() {
    if (_ctrl.creatures.isEmpty) return _housingReadout();
    return Row(
      mainAxisSize: MainAxisSize.min,
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
          tooltip: _searchQuery.isEmpty ? 'Search' : 'Search: "$_searchQuery"',
          engaged: _searchOpen || _searchQuery.isNotEmpty,
        ),
        CompositedTransformTarget(link: _filterLink, child: _filterGlyphBtn()),
        _sortGlyphBtn(),
        // What the order is, in words — the icon alone never said.
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            '${_sort.label}${_sortReversed ? ' ↑' : ''}',
            style: FoE.label(size: 12).copyWith(color: kBoxInkFaint),
          ),
        ),
        _housingReadout(),
      ],
    );
  }

  /// The search field, under the header while the lens is open.
  Widget _searchRow() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 280,
        child: SearchPill(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          palette: _pills,
        ),
      ),
    ),
  );

  /// A 34 px plate with a glyph: the main menu's blue, gold when [engaged].
  Widget _plate(IconData icon, bool engaged) => Container(
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: engaged ? goldButton() : menuButton(),
    child: PixelIcon(
      icon,
      size: 17,
      color: engaged ? CreamPalette.ink : kBoxInk,
    ),
  );

  /// One small button: blue plate, gold when engaged.
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
        // The main menu's plate; gold while the control is doing something
        // (a filter, a search).
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _plate(icon, engaged),
            if (badge != null) ...[
              const SizedBox(width: 3),
              Text(
                badge,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: kBoxInk,
                ),
              ),
            ],
          ],
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
            borderRadius: vr(8),
            side: const BorderSide(color: CreamPalette.tan, width: 2),
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
                          fontWeight: FontWeight.w400,
                          color: mode == _sort ? CreamPalette.warn : kBoxInk,
                        ),
                      ),
                    ),
                    if (mode == _sort)
                      Text(
                        _sortReversed ? '↑' : '↓',
                        style: const TextStyle(
                          fontSize: 13,
                          color: CreamPalette.warn,
                        ),
                      ),
                  ],
                ),
              ),
          ],
          // A plain decorated box — PopupMenuButton already wraps this in its
          // own tap handler to open the menu.
          child: _plate(Icons.swap_vert, engaged),
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
        child: DecoratedBox(
          decoration: raisedTile(),
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
          PixelIcon(
            active ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: active ? (color ?? CreamPalette.warn) : kBoxInkFaint,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            // A rarity row shows its colour on the tick box (the pale rarity
            // colours do not read as text on plaster); the others follow the
            // active/inactive scheme.
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: active && color == null ? CreamPalette.warn : kBoxInk,
            ),
          ),
        ],
      ),
    ),
  );

  // ── Designs 1 and 6 ────────────────────────────────────────

  /// The element filter as a rail of pixel-icon buttons. Never scrolls: the
  /// nine buttons share whatever height there is (user 2026-11-10), the icons
  /// shrinking with them.
  Widget _elementRail() {
    final entries = <(String, String, bool, VoidCallback)>[
      (
        'All',
        'star',
        _elementFilters.isEmpty,
        () {
          setState(_elementFilters.clear);
        },
      ),
      for (final e in CreatureElement.values)
        if (e != CreatureElement.neutral)
          (
            e.label,
            _elementIconKey(e),
            _elementFilters.length == 1 && _elementFilters.contains(e),
            () => setState(() {
              _elementFilters
                ..clear()
                ..add(e);
            }),
          ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 4.0;
        final n = entries.length;
        final side = ((box.maxHeight - gap * (n - 1)) / n).clamp(22.0, 40.0);
        final icon = side >= 34 ? 24.0 : 16.0;
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(height: gap),
              Tooltip(
                message: entries[i].$1,
                child: Pressable(
                  onTap: entries[i].$4,
                  child: Container(
                    width: side + 4,
                    height: side,
                    alignment: Alignment.center,
                    // The kit's stepped plate: gold while this element is on.
                    decoration: entries[i].$3 ? goldButton() : menuButton(),
                    child: GameIcon(entries[i].$2, size: icon),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static String _elementIconKey(CreatureElement e) => switch (e) {
    CreatureElement.fire => 'flame',
    CreatureElement.ice => 'ice',
    CreatureElement.plant => 'sprout',
    CreatureElement.lightning => 'bolt',
    CreatureElement.water => 'drop',
    CreatureElement.stone => 'stone',
    CreatureElement.light => 'sun',
    CreatureElement.shadow => 'moon',
    CreatureElement.neutral => 'star',
  };

  void _openCreature(CreatureInstance c) =>
      pushMenu(context, CreatureDetailScreen(creatureId: c.id));

  Widget _nothingMatches() => Center(
    child: Text(
      'Nothing matches the filter.',
      style: TextStyle(color: kBoxInkFaint, fontSize: 12),
    ),
  );

  /// Element rail at the left, then a scrolling grid of trading cards
  /// (user 2026-11-10): a foil frame in the rarity colour, the monster on a
  /// glow of its element, name and facts on a dark band underneath.
  Widget _collectionGrid() {
    final list = _visibleCreatures();
    if (list.isEmpty) return _nothingMatches();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 46, child: _elementRail()),
        const SizedBox(width: 10),
        Expanded(
          // Cards scroll up to the hairline under the title: the viewport's
          // own clip would cut them 8 px below it (the hairline's gap), so
          // the grid paints unclipped and this clip reaches up to the line.
          child: ClipRect(
            clipper: const _ReachUpClipper(8),
            child: GridView.builder(
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(top: 14, bottom: 10, right: 6),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 156,
                childAspectRatio: 0.7,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _tradingCard(list[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tradingCard(CreatureInstance c) {
    final rarity = c.species?.rarity;
    final rc = rarity?.color ?? const Color(0xFF9FB0BD);
    final element = c.species?.element ?? CreatureElement.fire;
    final ko = c.isKo;
    final hp = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    Widget badge(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xCC061219),
        borderRadius: vr(8),
      ),
      child: child,
    );
    return _HoverLift(
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openCreature(c),
        child: Container(
          // Neutral steel frame, tinted a little by the TYPE (no rarity glow).
          decoration: ShapeDecoration(
            shape: VoxelShape(notch: 3, light: Voxel.rim),
            gradient: Voxel.shaded(
              Color.lerp(CreamPalette.tileTop, element.color, 0.55)!,
            ),
            shadows: const [
              BoxShadow(color: Color(0x73000000), offset: Offset(3, 3)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(1, 4, 1, 4),
          child: ClipRRect(
            borderRadius: vr(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(element.color, Colors.black, 0.7),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // TRY-OUT (user 2026-11-10): the card's picture sits on
                        // the block tiles in the monster's own colour, replacing
                        // the painted element scene.
                        Positioned.fill(
                          child: VoxelBackdrop(
                            color: element.color,
                            vignette: 0.7,
                            darken: 0.22,
                            cell: 18,
                          ),
                        ),
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 18, 6, 4),
                            child: Opacity(
                              opacity: ko ? 0.35 : 1,
                              child: CreatureFigure(
                                imageUrl: c.imageUrl,
                                element: element,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 5,
                          left: 5,
                          child: badge(
                            Text(
                              'Lv ${c.level}',
                              style: FoE.value(
                                size: 11,
                              ).copyWith(color: const Color(0xFFE6F4F8)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 7,
                          child: Text(
                            c.gender.symbol,
                            style: TextStyle(
                              color: Color.lerp(
                                c.gender.color,
                                Colors.white,
                                0.3,
                              ),
                              fontSize: 17,
                              shadows: const [
                                Shadow(color: Colors.black87, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                        if (c.canEvolve)
                          const Positioned(
                            right: 4,
                            bottom: 2,
                            child: PixelIcon(
                              Icons.arrow_upward_rounded,
                              size: 22,
                              color: Color(0xFF2FD37A),
                              shadows: [
                                Shadow(
                                  color: Color(0xCC000000),
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        if (ko)
                          Positioned.fill(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: ShapeDecoration(
                                  color: FoE.danger,
                                  shape: FoE.facet(radius: 6),
                                ),
                                child: Text(
                                  'K.O.',
                                  style: FoE.title(
                                    size: 11,
                                  ).copyWith(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // The name band.
                  Container(
                    color: Color.alphaBlend(
                      const Color(0x73040E14),
                      Color.lerp(element.color, Colors.black, 0.7)!,
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          c.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.title(size: 14).copyWith(color: kBoxInk),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Rarity: a small gem and the word — the only place
                            // the rarity colour shows on the card.
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: BoxDecoration(
                                color: rc,
                                border: Border.all(color: Voxel.outline),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                (rarity?.label ?? '').toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FoE.dim(size: 8.5).copyWith(
                                  color: Color.lerp(rc, Colors.white, 0.35),
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            Text(
                              '⚡${totalPower(c)}',
                              style: FoE.value(
                                size: 12,
                              ).copyWith(color: const Color(0xFFFFD45A)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // HP as the blocky bar of the monster detail screen.
                  Container(
                    color: Color.alphaBlend(
                      const Color(0x73040E14),
                      Color.lerp(element.color, Colors.black, 0.7)!,
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    child: VoxelBar(
                      value: hp,
                      color: creatureHpColor(hp),
                      height: 8,
                      block: 6,
                      onDark: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clips to the child's box, but [up] pixels taller at the top.
class _ReachUpClipper extends CustomClipper<Rect> {
  final double up;
  const _ReachUpClipper(this.up);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, -up, size.width, size.height + up);

  @override
  bool shouldReclip(_ReachUpClipper old) => old.up != up;
}

/// Lifts its child a few pixels while the mouse is over it (web/desktop);
/// a no-op on touch.
class _HoverLift extends StatefulWidget {
  final Widget child;
  const _HoverLift({required this.child});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _over = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _over = true),
    onExit: (_) => setState(() => _over = false),
    child: AnimatedSlide(
      offset: _over ? const Offset(0, -0.03) : Offset.zero,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}
