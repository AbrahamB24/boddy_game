import 'package:flutter/material.dart';

import 'data/resource_icons.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/duration_format.dart';
import '../creatures/models/creature_enums.dart'
    show kTrainingXpPerHour, workXpPerHourAt;
import '../onboarding/intro_flow.dart' show introBuildTarget;
import '../onboarding/intro_spotlight.dart';
import 'data/building_definitions.dart';
import 'data/workshop_role_effects.dart';
import 'sheets/building_upgrade_sheet.dart';
import 'settlement_controller.dart';
import 'widgets/building_icon.dart';
import '../common/widgets/parchment_page.dart';
import 'widgets/scroll_paper.dart';

/// What the player picked in the Build menu, handed back through
/// Navigator.pop. The menu itself performs nothing: what it returns is acted on
/// by the SCREEN (which buys and places the building) or becomes a MAP mode
/// (roads, and a build plot's placement) — either way the map is what you return
/// to.
sealed class BuildChoice {
  const BuildChoice();
}

/// Build [typeId] — the settlement PLACES it and hands you move mode with it
/// selected (user 2026-07-30: "wenn ich beim app ein gebäude baue, soll dies
/// einfach auf die map kommen, damit ich es dann verschieben kann").
///
/// A BUILDING PLOT is the exception and still puts the map into placement mode:
/// it cannot be moved afterwards and which new ground it claims is its whole
/// purpose. See SettlementScreen._buildAndPlace.
class BuildPlace extends BuildChoice {
  final String typeId;
  const BuildPlace(this.typeId);
}

class BuildRoads extends BuildChoice {
  const BuildRoads();
}
// There is no BuildMove: moving is not a menu item any more (user 2026-07-20).
// You long-press a building ON THE MAP and it drops straight into move mode,
// which is both fewer steps and the gesture people already try first.

// ── Building card colours (user 2026-07-23) ──
// The blue tiles clashed with the parchment scroll, so a buildable card now
// wears the settlement's action GREEN — the same language as the buttons and
// the land — and an unbuildable one a faded parchment. The ink flips to match:
// near-white on the green, dark on the pale paper.
final _cardActive = kActionGreen; // the SAME lawn green as the buttons
final _cardInactive = kParchmentInk.withValues(alpha: 0.10);

const _inkOnActive = Color(0xFFF3F7EF); // near-white on the green
final _inkOnInactive = kParchmentInk.withValues(alpha: 0.55);

/// The inset panel inside a card (the stats box) — a deeper shade of whichever
/// card it sits on, so it reads as a recess rather than as a new colour.
final _insetActive = kActionGreenDeep.withValues(alpha: 0.55);
final _insetInactive = kParchmentInk.withValues(alpha: 0.10);

/// [buildable] picks the card's whole colour scheme.
Color _ink(bool buildable) => buildable ? _inkOnActive : _inkOnInactive;

// The menu's groups ARE BuildingCategory (user 2026-07-26: "diese kategorien so
// auch im Build menü übernehmen"). This file used to declare its own private
// enum and infer each building's group from what it did, so the drawer a
// building appeared in was a UI opinion the author could not overrule. It is a
// field on the def now — see BuildingCategory / categoryOfBuilding.

/// Opens the Build menu and resolves to the player's choice (null when the
/// player backs out).
///
/// ── A SCREEN, NOT A POPUP (user 2026-07-31: "build menü soll auch ein eigener
/// screen sein") ──
///
/// It was a sheet across the bottom of the map, on the argument that building is
/// something you do TO the map and the map should stay visible behind it. What
/// the sheet actually showed of the map was the strip above 74 % of the screen —
/// not the tile you were aiming at, which the sheet was covering — and the price
/// was a whole second layout: a hand-driven slide, a barrier, a PopScope that
/// had to finish an animation before it was allowed to pop, and a guard against
/// two exits racing each other. All of that is gone; a page arrives and leaves
/// the way every other page does.
Future<BuildChoice?> showBuildMenu(
  BuildContext context,
  SettlementController ctrl,
) => Navigator.push<BuildChoice>(
  context,
  MaterialPageRoute(builder: (_) => BuildMenuScreen(ctrl: ctrl)),
);

/// The Build popup: a sheet across the bottom of the map — a title bar with the
/// build-slot readout, a row of CATEGORY PILLS under it, and the category's
/// buildings in a two-column GRID (user layout 2026-07-22, replacing the
/// left rail + horizontal strip).
///
/// Why the grid: the strip showed two and a half cards and hid the rest behind
/// a sideways scroll nobody could see was there. A grid shows six at a glance,
/// which is what choosing between buildings actually needs. The one thing kept
/// verbatim is the art standing OUT of its tile.
///
/// It decides nothing: it pops a [BuildChoice] and the settlement screen puts
/// the map into the matching mode.
class BuildMenuScreen extends StatefulWidget {
  final SettlementController ctrl;

  const BuildMenuScreen({super.key, required this.ctrl});

  @override
  State<BuildMenuScreen> createState() => _BuildMenuScreenState();
}

class _BuildMenuScreenState extends State<BuildMenuScreen> {
  SettlementController get ctrl => widget.ctrl;

  /// Horizontal breathing room between the page's margin and its content.
  static const double _contentInset = 8;

  // ── Ink on the parchment ──
  // The panel is a light parchment surface, so everything written on it uses
  // this dark ink — the app's white/silver would be invisible on paper.
  static const Color _paperInk = kParchmentInk;

  BuildingCategory? _selected;

  /// Kept only to rewind the strip when the category changes — without a
  /// controller the ListView would hold the previous category's offset and open
  /// the new one already scrolled. Nothing reads the position: the tile colour
  /// is driven by BUILDABILITY (user 2026-07-20), not by which tile is at the
  /// left edge, so there is no scroll state to track.
  final _cardScroll = ScrollController();

  @override
  void dispose() {
    _cardScroll.dispose();
    super.dispose();
  }

  void _selectCategory(BuildingCategory cat) {
    setState(() => _selected = cat);
    if (_cardScroll.hasClients) _cardScroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final currentEraId = ctrl.currentEra?.id ?? '';
    final stock = ctrl.resources?.asMap ?? {};
    final available = availableBuildings(currentEraId, ctrl.battlesCleared);
    final sections = _sections(available);

    // Guided tutorial: the step's target building is the only tappable card —
    // everything else is dimmed and dead by the spotlight overlay.
    final introTarget = introBuildTarget(ctrl.introStep);
    final spotlight =
        introTarget != null && available.any((d) => d.id == introTarget);

    // Land on a sensible category: the tutorial's, else the first non-empty.
    final selected = _resolveSelected(sections, spotlight ? introTarget : null);
    final defs = sections
        .firstWhere(
          (s) => s.cat == selected,
          orElse: () => (cat: selected, defs: <BuildingDef>[]),
        )
        .defs;

    return Stack(
      children: [
        // The PAGE every other screen is printed on — which brings the parchment
        // and the meander bordure with it, so the sheet's own copies of both are
        // gone. The build-slot readout moves into the bar, where a page's
        // running head carries its numbers.
        ParchmentPage(
          title: 'Build',
          trailing: _SlotChips(ctrl: ctrl, ink: _paperInk),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              _contentInset,
              6,
              _contentInset,
              8 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _categoryPills(sections, selected),
                Expanded(child: _cards(defs, stock, introTarget, 0)),
              ],
            ),
          ),
        ),
        if (spotlight)
          const IntroSpotlightOverlay(anchorName: 'build-target-row'),
      ],
    );
  }

  /// Leaves with [choice] — or with nothing, which is what the back arrow does.
  void _close([BuildChoice? choice]) => Navigator.of(context).pop(choice);

  // ── Category tabs, across the top ───────────────────────────
  /// ALL categories on one line, never scrolling (user 2026-07-22): a row of
  /// equal Expanded tabs. A sideways scroll here hid categories behind an edge
  /// exactly the way the old card strip hid buildings — and there are only ever
  /// a handful, so they fit.
  ///
  /// Icon ABOVE the label, which is what makes five of them fit a phone: the
  /// tab only has to be as wide as its icon, not as wide as "Materials".
  Widget _categoryPills(
    List<({BuildingCategory cat, List<BuildingDef> defs})> sections,
    BuildingCategory selected,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(_contentInset, 4, _contentInset, 6),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          for (final s in sections) ...[
            if (s != sections.first) const SizedBox(width: 6),
            Expanded(child: _categoryTab(s.cat, s.defs.length, s.cat == selected)),
          ],
        ],
      ),
    ),
  );

  Widget _categoryTab(BuildingCategory cat, int count, bool active) {
    // Same warm pill as every button (user 2026-07-23): the selected tab is the
    // gold chip, the rest faded parchment — so the tab strip, the dialog's
    // buttons and the menu's buttons all read as one language on the scroll.
    final ink = parchmentButtonInk(active: active);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectCategory(cat),
        child: Ink(
          decoration: parchmentButton(active: active),
          child: Center(
            // Every tab renders the same block at the same width, so the
            // scale-down factor is identical and no tab ends up with a visibly
            // smaller icon than its neighbour.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 58,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat.icon, size: 16, color: ink),
                    const SizedBox(height: 3),
                    Text(
                      // The count is why you'd tap a category you haven't opened.
                      '${cat.label} $count',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.dim(size: 9).copyWith(
                        color: ink,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── The grid of buildings ───────────────────────────────────
  Widget _cards(
    List<BuildingDef> defs,
    Map<String, double> stock,
    String? introTarget,
    double bottomInset,
  ) {
    if (defs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing here yet — research opens new buildings.',
            textAlign: TextAlign.center,
            // On the parchment, so ink rather than the app's silver.
            style: FoE.dim(size: 12).copyWith(
              color: _paperInk.withValues(alpha: 0.65),
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _cardScroll,
      padding: EdgeInsets.fromLTRB(
        _contentInset,
        4,
        _contentInset,
        14 + bottomInset,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 8,
        // The card carries its own headroom, so the grid never has to leave a
        // gap for the art or turn off clipping.
        mainAxisExtent: _BuildCard.height + _BuildCard.overhang,
      ),
      itemCount: defs.length,
      itemBuilder: (context, i) {
        final def = defs[i];
        final card = _BuildCard(
          def: def,
          stock: stock,
          ctrl: ctrl,
          // Through _close, so the scroll rolls back down before the map takes
          // over — picking a building is an exit like any other.
          onTap: () =>
              _close(def.isRoad ? const BuildRoads() : BuildPlace(def.id)),
        );
        return def.id == introTarget
            ? KeyedSubtree(
                key: IntroSpotlightAnchors.of('build-target-row'),
                child: card,
              )
            : card;
      },
    );
  }

  // ── Grouping ────────────────────────────────────────────────
  /// Sections in display order, empty ones dropped. The group comes from the
  /// def's authored [BuildingDef.category] (Dev Mode → Edit Building → Basis),
  /// falling back to the old derivation for anything never categorised — so a
  /// building always has a drawer, and the author decides which.
  List<({BuildingCategory cat, List<BuildingDef> defs})> _sections(
    List<BuildingDef> available,
  ) {
    final buckets = {
      for (final cat in BuildingCategory.values) cat: <BuildingDef>[],
    };
    // Roads are excluded from availableBuildings (they aren't placed, they are
    // painted) but the menu lists them all the same — tapping enters paint mode.
    for (final def in kBuildingDefs.values.where((d) => d.isRoad)) {
      buckets[categoryOfBuilding(def)]!.add(def);
    }
    for (final def in available) {
      buckets[categoryOfBuilding(def)]!.add(def);
    }
    return [
      for (final cat in BuildingCategory.values)
        if (buckets[cat]!.isNotEmpty) (cat: cat, defs: buckets[cat]!),
    ];
  }

  /// The category to show: the player's pick when it still has content, else
  /// the tutorial target's, else the first non-empty one.
  BuildingCategory _resolveSelected(
    List<({BuildingCategory cat, List<BuildingDef> defs})> sections,
    String? introTarget,
  ) {
    if (sections.isEmpty) return BuildingCategory.civic;
    final picked = _selected;
    if (picked != null && sections.any((s) => s.cat == picked)) return picked;
    if (introTarget != null) {
      final def = kBuildingDefs[introTarget];
      if (def != null) {
        final cat = categoryOfBuilding(def);
        if (sections.any((s) => s.cat == cat)) return cat;
      }
    }
    return sections.first.cat;
  }
}

// ── Build slots ───────────────────────────────────────────
/// How many builds are running and how many are queued: two ICON-only readouts
/// side by side at the HEAD of the rail (user 2026-07-20) — a builder's helmet
/// for the active sites, an hourglass for the queue. No tile behind them, and
/// one row rather than two, so the category tiles below keep the height.
///
/// The word labels are gone; the COUNTS stay, because a slot indicator with no
/// number says nothing about whether you can start another build. Full turns
/// the chip amber — that is the state you actually need to notice.
class _SlotChips extends StatelessWidget {
  final SettlementController ctrl;

  /// Ink of the readout. Passed in because these sit on the PARCHMENT sheet,
  /// which is the one light surface in the app — the white this used to
  /// hardcode would be invisible on it.
  final Color ink;

  const _SlotChips({required this.ctrl, required this.ink});

  @override
  Widget build(BuildContext context) {
    final active = ctrl.activeConstructionCount;
    final queued = ctrl.queuedConstructionCount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // Side by side (user 2026-07-20): one row instead of two hands the height
      // back to the category tiles below. FittedBox because the pair is a few
      // pixels wider than the rail at full size — shrinking slightly beats
      // overflowing, and it adapts if a slot count ever reaches two digits.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chip(
              Icons.engineering,
              '$active/${ctrl.maxBuildSlots}',
              active >= ctrl.maxBuildSlots,
            ),
            const SizedBox(width: 7),
            _chip(
              Icons.hourglass_bottom,
              '$queued/${ctrl.maxQueueSlots}',
              queued >= ctrl.maxQueueSlots,
            ),
          ],
        ),
      ),
    );
  }

  /// Bare icon + count — no tile behind it (user 2026-07-20). These are a
  /// read-out, not something you pick, so giving them a box would have made
  /// them look like two more categories.
  Widget _chip(IconData icon, String count, bool full) {
    // Full is the state you need to notice, so it keeps its own alert colour
    // (deepened, because amber on paper is nearly invisible).
    final tint = full ? Colors.deepOrange.shade800 : ink.withValues(alpha: 0.8);
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 3),
          Text(
            count,
            style: FoE.dim(size: 9).copyWith(
              color: tint,
              fontWeight: full ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Build card ────────────────────────────────────────────
/// One building, as a card in the grid: the art standing out of the tile's top
/// edge, then name, what it does, its price and its build stats.
class _BuildCard extends StatelessWidget {
  final BuildingDef def;
  final Map<String, double> stock;
  final SettlementController ctrl;
  final VoidCallback onTap;

  // Sized for the SCROLL's sheet (user 2026-07-23): the writable area is ~87%
  // of the screen wide, the roller's end caps taking the rest. Two cards fit
  // across it at roughly 170pt each.

  /// Height of the TILE. The card is this plus [overhang]; the grid sizes its
  /// cells from the sum, so every card in the grid keeps the same shape.
  static const double height = 164;

  /// The art's footprint inside the tile: the building stands on this band and
  /// grows upward out of it.
  static const double _artH = 44;

  /// Room the card reserves ABOVE the tile for the part of the art that rises
  /// past its top edge. It has to keep up with [_artW] — the art is
  /// width-driven, so wider art is also taller art.
  static const double overhang = 54;

  /// Width of the building art. Height follows its own aspect ratio, so the
  /// taller the art the further it rises over the tile's edge.
  static const double _artW = 98;

  const _BuildCard({
    required this.def,
    required this.stock,
    required this.ctrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placed = ctrl.buildings
        .where((b) => b.buildingTypeId == def.id)
        .length;
    // Build Plots use the map-progress limit (one per cleared point), not the
    // static maxCount.
    final effectiveMax = def.isBuildPlot ? ctrl.buildPlotLimit : def.maxCount;
    final capped = def.isBuildPlot || def.maxCount > 0;
    final atMax = capped && placed >= effectiveMax;
    final queueFull =
        def.constructionSeconds > 0 &&
        ctrl.activeConstructionCount >= ctrl.maxBuildSlots &&
        ctrl.queuedConstructionCount >= ctrl.maxQueueSlots;
    final poor = !def.canAfford(stock);
    final enabled = !atMax && !queueFull && !poor;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      // Opaque: the art rises above the tile, so parts of the hit area are
      // empty and the default (deferToChild) would drop taps that land there.
      behavior: HitTestBehavior.opaque,
      // The card OWNS its headroom (user 2026-07-22): the tile sits at the
      // bottom and the art rises into the reserved space above it, all inside
      // the card's own bounds. Nothing overflows any more, so the grid needs no
      // Clip.none and no phantom spacing — the look is identical, the layout is
      // no longer fragile.
      child: SizedBox(
        height: height + overhang,
        child: Stack(
          children: [
            // The two sampled tile blues (user 2026-07-20): a buildable tile
            // wears the LIGHT one, a spent/unaffordable one the mid blue.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  // Green when buildable, faded parchment when not (user
                  // 2026-07-23) — the scroll's own palette. A soft brown shadow
                  // so the card reads as LYING ON the paper.
                  color: enabled ? _cardActive : _cardInactive,
                  boxShadow: [
                    BoxShadow(
                      color: kPageShadow.withValues(alpha: 0.24),
                      blurRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  // Top padding = the art's footprint inside the tile, which
                  // the Stack draws over.
                  padding: const EdgeInsets.fromLTRB(10, _artH, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1) Name — centred under the art. The ink flips with the
                      // state: white would vanish on the light tile.
                      Text(
                        def.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: FoE.label(size: 13).copyWith(
                          color: _ink(enabled),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // 2) What it does — two lines, hard-capped so every card
                      // in the grid keeps the same shape.
                      SizedBox(
                        height: 24,
                        child: Text(
                          _bonusText(def),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: FoE.dim(size: 9).copyWith(
                            color: _ink(enabled).withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // 3) The price, as chips — each one turns red on its own
                      // when that is the resource you are short of.
                      _costRow(def.resourceCost, stock, enabled),
                      const SizedBox(height: 6),
                      // 4) Footprint · build time · count, in their own recess.
                      _statsBox(placed, effectiveMax, capped, atMax, enabled),
                    ],
                  ),
                ),
              ),
            ),
            // The building itself, standing on the tile and rising out of it.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: overhang + _artH,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _art(enabled),
              ),
            ),
            // Why a dead card is dead — one short tag, top-right, instead of
            // leaving the player to compare numbers.
            if (!enabled)
              Positioned(
                right: 6,
                top: overhang + 6,
                child: _blockedTag(atMax, queueFull),
              ),
            // "Full upgrade" peek (user 2026-07-24): shows the building's
            // effects at max level BEFORE you commit to building it. Its own tap
            // so it doesn't fire the build.
            Positioned(
              left: 4,
              top: overhang + 4,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showBuildingUpgradeSheet(context, def),
                // INVERTED, not a wash (user 2026-07-26: "besser sichtbar
                // machen im Vergleich zum Hintergrund"). A translucent dark
                // circle vanished on the green card — green on green. Filling
                // it with the card's INK and drawing the glyph in the card's
                // own colour guarantees contrast on both card states, buildable
                // (green) and not (pale parchment).
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _ink(enabled),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.query_stats,
                    size: 15,
                    // The circle wears the ink, so the glyph wears the paper:
                    // near-white circle on a green card takes the green back,
                    // dark circle on a pale card takes the parchment.
                    color: enabled ? kActionGreen : kParchmentLight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The one-word reason a card can't be tapped. Shortage needs no tag — the
  /// cost chip already turned red on the exact resource.
  Widget _blockedTag(bool atMax, bool queueFull) {
    final label = atMax ? 'MAX' : (queueFull ? 'QUEUE FULL' : null);
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: FoE.danger.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: FoE.dim(size: 8).copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// The building, standing on its own cast shadow and overflowing the tile's
  /// top edge — the shared look, see ShadowedBuildingIcon.
  Widget _art(bool enabled) =>
      ShadowedBuildingIcon(imageUrl: def.imageUrl, width: _artW, dimmed: !enabled);

  /// Footprint · build time · limit, in their own inset box at the foot of the
  /// tile — the reference's "Bauzeit / Erbaut" panel.
  Widget _statsBox(int placed, int max, bool capped, bool atMax, bool enabled) {
    final ink = _ink(enabled);
    // The inset panel is a shade of the tile it sits on — both sampled from the
    // reference — rather than a generic black wash, which went muddy on the
    // light blue.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: enabled ? _insetActive : _insetInactive,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stat(Icons.grid_on, '${def.gridW}×${def.gridH}', ink),
          Flexible(child: _stat(Icons.schedule, _buildTimeText(), ink)),
          // The limit doubles as the "why is this tile dead" answer once it
          // reads max/max, which is why it turns alert-coloured rather than
          // just greying.
          _stat(
            Icons.layers,
            // Uncapped buildings (housing, production — user 2026-07-22) still
            // report how many you have; the ∞ is what says "build another".
            capped ? '$placed/$max' : '$placed/∞',
            ink,
            alert: atMax ? FoE.danger : null,
          ),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, String text, Color ink, {Color? alert}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 10, color: alert ?? ink.withValues(alpha: 0.75)),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.dim(size: 9).copyWith(
            color: alert ?? ink.withValues(alpha: 0.9),
            fontWeight: alert != null ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
      ),
    ],
  );

  // Rate/duration formulas here mirror GameEngine.tick()'s construction math
  // (same buildRatePerHour). Every active site now builds at the FULL rate
  // (user 2026-07-24: no split). Energy only gates whether production runs at
  // all, never a fractional slowdown, so `energy.fraction` must NOT appear.
  String _buildTimeText() {
    if (def.isRoad) return 'Free · instant';
    if (def.constructionSeconds <= 0) return 'Instant';
    final e = ctrl.energy;
    if (e == null) return fmtDuration(def.constructionSeconds);
    final active = ctrl.activeConstructionCount;
    // buildRatePerHour ALREADY includes buildSpeedMultiplier — multiplying
    // again squares it.
    // Empty tank = floor rate, not zero (energy boosts, it no longer gates).
    final rate = ctrl.buildRatePerHour /
        3600.0 *
        (e.currentEnergy > 0 ? 1.0 : kEnergyFloorRate);
    if (rate <= 0) return active >= ctrl.maxBuildSlots ? 'Queued (∞)' : '∞';
    final dur = fmtDuration(def.constructionSeconds / rate);
    return active >= ctrl.maxBuildSlots ? 'Queued ~$dur' : dur;
  }

  String _bonusText(BuildingDef def) {
    if (def.isRoad) {
      return 'Connects buildings to the Tribal Center — paint as many as you '
          'like';
    }
    if (def.isBuildPlot) {
      return 'Expands buildable area by ${def.gridW}×${def.gridH}';
    }
    final parts = <String>[];
    // Expedition amplifiers sell what they actually do for trips — read off
    // the AUTHORED effects now (the code-side table is gone, 2026-07-25).
    final carry = def.effectAt('expedition', 'carry', 99);
    final travel = def.effectAt('expedition', 'travel', 99);
    final goods = def.effectAt('expedition', 'goods', 99);
    if (carry > 0) parts.add('+${(carry * 100).round()}% trip carry');
    if (travel > 0) parts.add('-${(travel * 100).round()}% travel time');
    if (goods > 0) parts.add('+${(goods * 100).round()}% goods hauls');
    if (def.housingCapacity > 0) parts.add('houses ${def.housingCapacity}');
    for (final w in def.workshops) {
      // Training roles read no stat — sell what the building actually does.
      // A system post is named by what it shortens, not by its internal key:
      // "Breeding → breeding" said nothing (user 2026-07-26).
      parts.add(
        w.resource == WorkshopRole.kTraining
            ? 'trains ${w.slots} monsters '
                  '(+${kTrainingXpPerHour.toStringAsFixed(0)} XP/h)'
            : '${w.stat.label} → '
                  '${workshopRoleName(w.resource) ?? w.resource} (${w.slots})',
      );
    }
    // Every building with a post pays the same work XP (user 2026-07-30), so the
    // card says it once for the whole building rather than per post — and says
    // it at level 1, which is what you are about to build.
    if (def.workshops.isNotEmpty &&
        !def.workshops.any((w) => w.resource == WorkshopRole.kTraining)) {
      parts.add('+${workXpPerHourAt(1).toStringAsFixed(0)} XP/h per worker');
    }
    if (def.buildSpeedBonus > 0) {
      parts.add('+${(def.buildSpeedBonus * 100).toInt()}% build speed');
    }
    if (def.queueSlotsBonus > 0) {
      parts.add('+${def.queueSlotsBonus} queue slot');
    }
    final queueSlots = def.effectAt('queueSlots', '', 99);
    if (queueSlots > 0) parts.add('+${queueSlots.round()} queue slot');
    final buildSlots = def.effectAt('buildSlots', '', 99);
    if (buildSlots > 0) parts.add('+${buildSlots.round()} build site');
    final healSlots = def.effectAt('healSlots', '', 99);
    if (healSlots > 0) parts.add('${healSlots.round()} heals at once');
    final healQueue = def.effectAt('healQueue', '', 99);
    if (healQueue > 0) parts.add('${healQueue.round()} can wait');
    return parts.isEmpty ? 'No bonus' : parts.join(' · ');
  }

  /// Cost as ICON + amount, centred (user 2026-07-20). The icon is the app's
  /// own resource glyph — kResourceEmoji is the single source every other
  /// screen (header, trade sheet, expeditions) already reads, so the build menu
  /// can't drift into its own symbol set.
  Widget _costRow(
    Map<String, double> cost,
    Map<String, double> stock,
    bool enabled,
  ) {
    if (cost.isEmpty) {
      return Text(
        'Free',
        textAlign: TextAlign.center,
        style: FoE.dim(
          size: 10,
        ).copyWith(color: _ink(enabled), fontWeight: FontWeight.w700),
      );
    }
    // Era-II costs already run to three entries (wood + stone + frame) and a
    // later era's will run to four. Scale-down keeps them on ONE line at any
    // count rather than overflowing the narrower grid card.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final e in cost.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _resourceIcon(e.key),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${e.value.toInt()}',
                    style: FoE.dim(size: 11).copyWith(
                      color: (stock[e.key] ?? 0) >= e.value
                          ? _ink(enabled)
                          : FoE.danger,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _resourceIcon(String key) =>
      resourceEmoji(key);
}
