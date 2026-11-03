import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
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
import 'widgets/creature_card.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

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
      final showingStarterPicker =
          !_ctrl.isLoading && _ctrl.creatures.isEmpty;
      return MenuScaffold(
        showHeader: !showingStarterPicker,
        title: 'Monsters',
        trailing: _housingReadout(),
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
            Expanded(
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
            // The three doors, with their state. Nothing to show until
            // there is a first monster.
            if (_ctrl.creatures.isNotEmpty) ...[
              const SizedBox(width: 10),
              SizedBox(
                // Narrower still (user 2026-09-30: "können noch schmaler
                // werden, so dass noch ein Monster mehr Platz hat pro
                // Zeile") — the hubs' own text already ellipsized at 176, so
                // shaving more off here just hands the grid another column's
                // worth of room instead of sitting unused in this panel.
                width: 132,
                child: zoneBox(padding: const EdgeInsets.all(7), child: _hubs()),
              ),
            ],
          ],
        ),
      );
    },
  );

  /// "14 · housing 12/16" at the right of the title card — how many monsters
  /// you have and how many the settlement can shelter.
  Widget _housingReadout() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(9),
    ),
    child: Text(
      '${_ctrl.creatures.length} · housing '
      '${_settlement.housingUsed}/${_settlement.housingCapacity}',
      style: FoE.value(size: 11).copyWith(color: kBoxInk),
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

    return Column(
      children: [
        Expanded(
          child: _hub(
            icon: Icons.shield,
            title: 'Teams',
            // Shows once the first team exists — before that there is
            // nothing to count.
            line1: teams.isEmpty ? 'No team yet' : '${teams.length} Teams',
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
            line1: '${mating.length}/${_breeding.breedingSlots}',
            // Something to collect is what the amber rim is for — no text
            // needed alongside it any more.
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
            line1: '$bestiaryPct%',
            // Directly under the "13%" now that line2 is gone — same slot
            // the other two hubs' progress bar would sit in, if they had one.
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
  /// One hub: a round amber glyph, the door's name and its ONE stat beside
  /// it — same slot for all three hubs (2026-09-30 redesign, narrower boxes),
  /// so "n Teams" / "n/n" / "13%" line up at the same height. The Bestiary's
  /// progress bar sits directly under that row; the other two have none.
  Widget _hub({
    required IconData icon,
    required String title,
    required String line1,
    required VoidCallback onTap,
    double? progress,
    bool highlight = false,
  }) => Pressable(
    onTap: onTap,
    // A raised tile, not a card of its own — the three hubs are all the
    // same kind of thing (a shortcut), standing on the shared [zoneBox]
    // the way a trip or a target tile stands on its page.
    child: Container(
      decoration: raisedTile(lit: highlight, radius: 12),
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  color: CreamPalette.gold,
                  boxShadow: [
                    BoxShadow(
                      color: CreamPalette.goldDeep,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: PixelIcon(icon, size: 15, color: CreamPalette.ink),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.title(size: 12).copyWith(color: kBoxInk),
                    ),
                    Text(
                      line1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(size: 11).copyWith(
                        color: highlight ? kBoxAccent : kBoxInkSoft,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: vr(4),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 7,
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
            style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
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

  // ── Search + filter + sort bar ─────────────────────────────
  Widget _sortFilterBar() => Padding(
    padding: const EdgeInsets.fromLTRB(14, 3, 14, 0),
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
              PixelIcon(icon, size: 18, color: kBoxInk),
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
            borderRadius: vr(12),
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
            child: const PixelIcon(Icons.swap_vert, size: 18, color: kBoxInk),
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
          PixelIcon(
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
  static const _gridSpacing = 10.0;
  static const _gridHPad = 14.0;
  static const _gridVPad = 8.0;

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
    // Auto-flowing (2026-09-18, landscape) — see this file's own doc comment
    // on why the shared monsterTileWidth/kMonsterTileCols convention doesn't
    // fit here any more.
    //
    // Row height is worked out by hand, not left to [childAspectRatio] (user
    // 2026-10-04: "Monsterkacheln bis zum unteren Bildschirmrand anzeigen"
    // — the fixed aspect ratio made the last row run past the bottom of a
    // short landscape window and get clipped mid-tile, since GridView just
    // crops to its viewport). If the rows a full collection needs are only
    // a little taller than the space available, shrink them just enough
    // that the last one lands flush on the edge instead of being cut off; a
    // collection too big for that stays at the natural tile size and
    // scrolls normally — a cut-off row while actively scrolling is normal,
    // only the UNSCROLLED first screen showing one is the bug.
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - _gridHPad * 2;
        final columns = math.max(1, (availW / 112).ceil());
        final tileW = (availW - _gridSpacing * (columns - 1)) / columns;
        final naturalH = tileW / kMonsterTileAspect;
        final availH = constraints.maxHeight - _gridVPad * 2;
        final rowsNeeded = (list.length / columns).ceil();
        final rowsThatFit = math.max(
          1,
          ((availH + _gridSpacing) / (naturalH + _gridSpacing)).floor(),
        );
        var tileH = naturalH;
        if (rowsNeeded > rowsThatFit) {
          final fitted =
              (availH - _gridSpacing * (rowsNeeded - 1)) / rowsNeeded;
          if (fitted >= naturalH * 0.82) tileH = fitted;
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            _gridHPad,
            _gridVPad,
            _gridHPad,
            _gridVPad,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: _gridSpacing,
            crossAxisSpacing: _gridSpacing,
            mainAxisExtent: tileH,
          ),
          itemCount: list.length,
          itemBuilder: (_, i) => CreatureCard(
            creature: list[i],
            onTap: () => pushMenu(
              context,
              CreatureDetailScreen(creatureId: list[i].id),
            ),
          ),
        );
      },
    );
  }
}
