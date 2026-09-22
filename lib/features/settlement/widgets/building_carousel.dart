import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/duration_format.dart';
import '../../../core/ui/pressable.dart';
import '../../onboarding/intro_flow.dart' show IntroStep, introBuildTarget;
import '../../onboarding/intro_spotlight.dart';
import '../data/building_definitions.dart';
import '../data/resource_icons.dart';
import '../data/road_tiles.dart';
import '../models/placed_building.dart';
import '../settlement_controller.dart';
import '../sheets/building_preview_dialog.dart';
import 'building_icon.dart';

// ── The Build menu, folded into the map (2026-09-18 redesign) ──────────────
//
// User: "das Baumenü kein eigener Screen ist, sondern unten die Gebäude
// gescrollt werden können wie dies bei rok der Fall ist." What used to be
// `BuildMenuScreen` — a full-screen page you navigated to and back from — is
// now a persistent strip docked at the bottom of the Settlement map itself,
// the same way Rise of Kingdoms' own build picker never leaves your city
// view. The strip picks a category, then scrolls its buildings sideways;
// tapping one hands the choice straight to the map (no page, no pop/await —
// see [SettlementScreen._buildAndPlace]/[SettlementScreen._enterRoadMode],
// which this widget's callbacks call directly).
//
// "Kompakter Streifen" (user 2026-09-19, picked from ten layouts, then
// adjusted): the cards are one row along the bottom, ~170 px tall, so the map
// stays almost entirely in view while you choose where a building goes. The
// CATEGORIES are round buttons stacked in a column at the left edge — the place
// the quick rail's Build tile stands while the menu is shut; the tile is hidden
// while the menu is open — with the build slots on top of them. A building's
// time, footprint and count sit UNDER its name, so the art can be as large as
// the card allows.
//
// What this drops relative to the old screen: the one-time "here's how the
// Build menu works" explainer card. The picker is simpler now (no full page
// to get lost in), and the tutorial's own row/category spotlight (still
// wired up below) already points at exactly what to tap.

/// The height of the CARD STRIP at the bottom of the settlement screen —
/// [SettlementScreen] lifts the quick rail above it when the tutorial forces the
/// menu open. The strip has no backdrop (user 2026-09-18), so the map runs
/// underneath.
///
/// A FRACTION of the screen's short axis (2026-09-18, responsiveness pass),
/// not a flat constant — landscape phones vary from ~375px tall (iPhone SE)
/// to the app's own 430px cap ([FoE.phoneMaxWidth], enforced by PhoneFrame),
/// a real ~15% swing. The floor is what one card still needs to keep its art,
/// name, facts and cost apart.
double buildingCarouselHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.40).clamp(166.0, 190.0);

/// The strip's left margin: the category column stands in it (36 wide plus the
/// rail's own 10 and a gap).
const double _kRailInset = 58;

/// The strip's right margin, the mirror image of [_kRailInset] — the
/// Umbaumodus button (user 2026-09-22: "ich will über das Baumenü in den
/// Umbaumodus kommen. Auf der rechten Seite den Button hinzufügen") stands in
/// it, the same one round-button size as a category.
const double _kRightInset = 58;

/// The category buttons' diameter and the gap between them.
const double _kDot = 36;
const double _kDotGap = 6;

class BuildingCarousel extends StatefulWidget {
  final SettlementController ctrl;
  final ValueChanged<String> onPlace;
  final VoidCallback onRoads;

  /// Opens Umbaumodus (user 2026-09-22) — the strip's own door into it, a
  /// round button standing at the right edge the way the categories stand at
  /// the left. Not shown while the guided tutorial is narrowing what this
  /// strip offers, and not shown in TRAY mode ([trayBuildings]) — there the
  /// right-edge button is [onCancelTray] instead.
  final VoidCallback onLayout;

  /// TRAY MODE (user 2026-09-22: "wenn ich recall all mache, sollen das
  /// Baumenü geöffnet werden, aber es befinden sich nur diese Gebäude zur
  /// Auswahl, welche gebaut wurden. So habe ich die genau gleiche
  /// Oberfläche, aber nur mit den gespeicherten Gebäuden"). Non-null swaps
  /// this widget from "what can I build" to "what's waiting in the
  /// Umbaumodus tray" — same categorised strip, same card look, sourced from
  /// these actual owned instances instead of [availableBuildings]. A tap
  /// calls [onPlaceStored] with the tapped building's id, never [onPlace]
  /// (nothing is bought; it already exists). See
  /// SettlementScreen._showTrayCarousel for when this is non-null.
  final List<PlacedBuilding>? trayBuildings;

  /// Tray mode only: a tray card was tapped — aim THIS specific building
  /// (not a def) at a new spot. The screen turns this into
  /// [SettlementMap.selectBuildingId] rather than a fresh purchase.
  final ValueChanged<String>? onPlaceStored;

  /// Tray mode only: the right-edge button there ("Cancel", not "Layout") —
  /// undoes the whole rearrange and leaves Umbaumodus, same as closing it
  /// early anywhere else (see SettlementController.cancelRecall).
  final VoidCallback? onCancelTray;

  /// The category to open on (a page other than the map asked for it — see
  /// BuildMenuRequest); null = the first one that has anything.
  final BuildingCategory? initialCategory;

  const BuildingCarousel({
    super.key,
    required this.ctrl,
    required this.onPlace,
    required this.onRoads,
    required this.onLayout,
    this.trayBuildings,
    this.onPlaceStored,
    this.onCancelTray,
    this.initialCategory,
  });

  @override
  State<BuildingCarousel> createState() => _BuildingCarouselState();
}

class _BuildingCarouselState extends State<BuildingCarousel> {
  SettlementController get ctrl => widget.ctrl;

  BuildingCategory? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialCategory;
  }

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
    final tray = widget.trayBuildings;
    if (tray != null) return _buildTray(tray);

    final stock = ctrl.resources?.asMap ?? {};
    final available = availableBuildings(
      ctrl.dungeonMaxStage,
      ctrl.battlesCleared,
    );
    final sections = _sections(available);
    if (sections.isEmpty) return const SizedBox.shrink();

    final introTarget = introBuildTarget(ctrl.introStep);
    final spotlightTarget =
        introTarget != null &&
        sections.any((s) => s.defs.any((d) => d.id == introTarget));
    final requiresManualCategory = ctrl.introStep == IntroStep.buildRoad;
    final targetCategory = spotlightTarget
        ? categoryOfBuilding(kBuildingDefs[introTarget]!)
        : null;
    final selected = _resolveSelected(
      sections,
      spotlightTarget && !requiresManualCategory ? introTarget : null,
    );
    final categorySpotlight =
        spotlightTarget && requiresManualCategory && selected != targetCategory;
    final rowSpotlight = spotlightTarget && !categorySpotlight;

    final defs = sections
        .firstWhere(
          (s) => s.cat == selected,
          orElse: () => (cat: selected, defs: <BuildingDef>[]),
        )
        .defs;

    // The column is taller than the card strip, and it stands above it at the
    // left edge — so the widget claims the column's height, and only the strip
    // and the column themselves take hits (the map between them stays live).
    final columnH =
        _SlotChips.height +
        8 +
        sections.length * _kDot +
        (sections.length - 1) * _kDotGap;
    return SizedBox(
      height: columnH + 10,
      child: Stack(
        children: [
          Positioned(
            left: _kRailInset,
            // Room for the Umbaumodus button on the right (2026-09-22),
            // mirroring the category column's own inset on the left.
            right: ctrl.introStep.isActive ? 0 : _kRightInset,
            bottom: 0,
            height: buildingCarouselHeight(context),
            // NOT opaque (user 2026-09-19: "immer wenn ich auf die Karte drücke,
            // soll sich das aktuelle Menü schliessen … auch wenn dort später einmal
            // Gebäude sein könnten"): only a card takes a tap. The empty part of
            // the strip — right of the last card, the gaps between cards — is
            // map, and a tap there closes the menu (see SettlementScreen). No
            // backdrop either (user 2026-09-18: "mache beim Baumenü keinen
            // Background") — the cards float straight over the map.
            child: _cardRow(defs, stock, introTarget),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: _categoryColumn(
              sections,
              selected,
              spotlightCategory: categorySpotlight ? targetCategory : null,
            ),
          ),
          // Umbaumodus's own door (user 2026-09-22) — hidden while the guided
          // tutorial is still narrowing this strip down to one spotlighted
          // card at a time; a rearrange tool has no place in that script.
          if (!ctrl.introStep.isActive)
            Positioned(right: 10, bottom: 10, child: _layoutButton()),
          if (rowSpotlight)
            const IntroSpotlightOverlay(anchorName: 'build-target-row'),
          if (categorySpotlight)
            IntroSpotlightOverlay(
              anchorName: 'build-category-row',
              hint: 'Tap ${targetCategory!.label} — that\'s where the road is',
            ),
        ],
      ),
    );
  }

  // ── TRAY MODE (user 2026-09-22) ───────────────────────────────
  // The exact same strip — category column, scrolling card row, same card
  // look — just sourced from what's actually sitting in the Umbaumodus tray
  // instead of "what can I build". No tutorial spotlighting (Umbaumodus
  // never runs during the guided intro) and no Layout button (already IN
  // Umbaumodus); its corner holds Cancel instead.
  Widget _buildTray(List<PlacedBuilding> tray) {
    final sections = _traySections(tray);
    if (sections.isEmpty) return const SizedBox.shrink();
    final selected = _resolveTraySelected(sections);
    final items = sections
        .firstWhere(
          (s) => s.cat == selected,
          orElse: () => (cat: selected, items: const <PlacedBuilding>[]),
        )
        .items;

    final columnH =
        _SlotChips.height +
        8 +
        sections.length * _kDot +
        (sections.length - 1) * _kDotGap;
    return SizedBox(
      height: columnH + 10,
      child: Stack(
        children: [
          Positioned(
            left: _kRailInset,
            right: _kRightInset,
            bottom: 0,
            height: buildingCarouselHeight(context),
            child: _trayCardRow(items),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: _trayCategoryColumn(sections, selected),
          ),
          Positioned(right: 10, bottom: 10, child: _cancelTrayButton()),
        ],
      ),
    );
  }

  Widget _trayCategoryColumn(
    List<({BuildingCategory cat, List<PlacedBuilding> items})> sections,
    BuildingCategory selected,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SlotChips(ctrl: ctrl),
      const SizedBox(height: 8),
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: _kDotGap),
        _categoryButton(
          sections[i].cat,
          sections[i].items.length,
          sections[i].cat == selected,
        ),
      ],
    ],
  );

  /// The tray's own right-edge button: "Cancel", not "Layout" — the same
  /// round-button shape and cream-tile look, since we are already inside
  /// Umbaumodus and this is the way OUT of it, not the way in.
  Widget _cancelTrayButton() => Tooltip(
    message: 'Cancel — put everything back',
    child: Semantics(
      label: 'Cancel and put everything back',
      button: true,
      child: Pressable(
        onTap: widget.onCancelTray,
        child: Container(
          width: _kDot,
          height: _kDot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
            ),
            boxShadow: [
              BoxShadow(
                color: CreamPalette.tanShadow,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.close, size: 18, color: CreamPalette.ink),
        ),
      ),
    ),
  );

  Widget _trayCardRow(List<PlacedBuilding> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final height = (c.maxHeight - 14).clamp(120.0, 190.0);
        final width = (height * 0.72).clamp(96.0, 132.0);
        return ListView.separated(
          controller: _cardScroll,
          scrollDirection: Axis.horizontal,
          hitTestBehavior: HitTestBehavior.translucent,
          padding: const EdgeInsets.fromLTRB(0, 4, 10, 10),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final b = items[i];
            final def = kBuildingDefs[b.buildingTypeId];
            if (def == null) return const SizedBox.shrink();
            return _TrayCard(
              def: def,
              width: width,
              height: height,
              onTap: () => widget.onPlaceStored?.call(b.id),
            );
          },
        );
      },
    );
  }

  List<({BuildingCategory cat, List<PlacedBuilding> items})> _traySections(
    List<PlacedBuilding> tray,
  ) {
    final buckets = {
      for (final cat in BuildingCategory.values) cat: <PlacedBuilding>[],
    };
    for (final b in tray) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      buckets[categoryOfBuilding(def)]!.add(b);
    }
    return [
      for (final cat in BuildingCategory.values)
        if (buckets[cat]!.isNotEmpty) (cat: cat, items: buckets[cat]!),
    ];
  }

  BuildingCategory _resolveTraySelected(
    List<({BuildingCategory cat, List<PlacedBuilding> items})> sections,
  ) {
    if (sections.isEmpty) return BuildingCategory.civic;
    final picked = _selected;
    if (picked != null && sections.any((s) => s.cat == picked)) return picked;
    return sections.first.cat;
  }

  // ── Category buttons, stacked down the left edge ─────────────
  /// The build slots on top, then one round button per category. Flush with the
  /// cards' bottom edge (10 below), where the quick rail's own tiles stand.
  Widget _categoryColumn(
    List<({BuildingCategory cat, List<BuildingDef> defs})> sections,
    BuildingCategory selected, {
    BuildingCategory? spotlightCategory,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SlotChips(ctrl: ctrl),
      const SizedBox(height: 8),
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: _kDotGap),
        _categoryButton(
          sections[i].cat,
          sections[i].defs.length,
          sections[i].cat == selected,
          anchorKey: sections[i].cat == spotlightCategory
              ? IntroSpotlightAnchors.of('build-category-row')
              : null,
        ),
      ],
    ],
  );

  /// A round button carrying the category's glyph; the name (with how many
  /// buildings it holds) is its tooltip and its accessible label.
  Widget _categoryButton(
    BuildingCategory cat,
    int count,
    bool active, {
    Key? anchorKey,
  }) {
    final button = Tooltip(
      message: '${cat.label} $count',
      child: Semantics(
        label: '${cat.label} $count',
        button: true,
        selected: active,
        child: Pressable(
          onTap: () => _selectCategory(cat),
          child: Container(
            width: _kDot,
            height: _kDot,
            decoration: active
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: CreamPalette.gold,
                    boxShadow: [
                      BoxShadow(
                        color: CreamPalette.goldDeep,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  )
                : BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CreamPalette.tanShadow,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
            child: Icon(cat.icon, size: 18, color: CreamPalette.ink),
          ),
        ),
      ),
    );
    return anchorKey == null
        ? button
        : KeyedSubtree(key: anchorKey, child: button);
  }

  /// The strip's OWN door into Umbaumodus (user 2026-09-22), standing at the
  /// right edge the way the categories stand at the left — same size, same
  /// round-button shape, but never gold (that colour means "this category is
  /// selected" here, and this is not a category).
  Widget _layoutButton() => Tooltip(
    message: 'Rearrange buildings',
    child: Semantics(
      label: 'Rearrange buildings',
      button: true,
      child: Pressable(
        onTap: widget.onLayout,
        child: Container(
          width: _kDot,
          height: _kDot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
            ),
            boxShadow: [
              BoxShadow(
                color: CreamPalette.tanShadow,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.open_with, size: 18, color: CreamPalette.ink),
        ),
      ),
    ),
  );

  // ── The building cards, scrolling sideways ──────────────────
  Widget _cardRow(
    List<BuildingDef> defs,
    Map<String, double> stock,
    String? introTarget,
  ) {
    if (defs.isEmpty) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _darkPill(
            child: Text(
              'Nothing here yet — research opens new buildings.',
              style: FoE.label(size: 12).copyWith(color: CreamPalette.paperTop),
            ),
          ),
        ),
      );
    }
    // The card's own height is derived from whatever room is actually left
    // (2026-09-18, responsiveness pass) rather than a flat constant — the
    // strip's height is itself a fraction of the screen (see
    // [buildingCarouselHeight]), so a fixed card size that fit the largest
    // phone could run taller than the row on a small one and get clipped.
    return LayoutBuilder(
      builder: (context, c) {
        // Minus the list's own vertical padding (4 top + 10 bottom).
        final height = (c.maxHeight - 14).clamp(120.0, 190.0);
        final width = (height * 0.72).clamp(96.0, 132.0);
        return ListView.separated(
          controller: _cardScroll,
          scrollDirection: Axis.horizontal,
          // A scrollable is opaque by default, which would swallow the taps on
          // its empty stretch; translucent lets them fall through to the map
          // (dragging still scrolls).
          hitTestBehavior: HitTestBehavior.translucent,
          // 10 below matches the rail's own bottom padding, so the cards and the
          // rail's tiles sit on one line.
          padding: const EdgeInsets.fromLTRB(0, 4, 10, 10),
          itemCount: defs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final def = defs[i];
            final card = _CarouselCard(
              def: def,
              stock: stock,
              ctrl: ctrl,
              width: width,
              height: height,
              onTap: () =>
                  def.isRoad ? widget.onRoads() : widget.onPlace(def.id),
              // The (i): what it does, BEFORE you build it (user 2026-09-20).
              // Not for a road (nothing to compare) and not while the guided
              // intro runs — its one lit control must stay the only way on.
              onInfo: def.isRoad || ctrl.introStep.isActive
                  ? null
                  : () => showBuildingPreview(
                      context,
                      ctrl,
                      def,
                      onBuild: () => widget.onPlace(def.id),
                    ),
            );
            return def.id == introTarget
                ? KeyedSubtree(
                    key: IntroSpotlightAnchors.of('build-target-row'),
                    child: card,
                  )
                : card;
          },
        );
      },
    );
  }

  // ── Grouping (same rules as the old BuildMenuScreen) ─────────
  List<({BuildingCategory cat, List<BuildingDef> defs})> _sections(
    List<BuildingDef> available,
  ) {
    final buckets = {
      for (final cat in BuildingCategory.values) cat: <BuildingDef>[],
    };
    for (final def in kBuildingDefs.values.where((d) => d.isRoad)) {
      buckets[categoryOfBuilding(def)]!.add(def);
    }
    for (final def in available) {
      buckets[categoryOfBuilding(def)]!.add(def);
    }
    // Civic: the two things you place most often stand first — Road, then
    // Building Plot — before every building (user 2026-09-19).
    int civicRank(BuildingDef d) => d.isRoad ? 0 : (d.isBuildPlot ? 1 : 2);
    final civic = buckets[BuildingCategory.civic]!;
    // Stable: same-rank defs keep the order they came in.
    final ranked = civic.asMap().entries.toList()
      ..sort((a, b) {
        final r = civicRank(a.value).compareTo(civicRank(b.value));
        return r != 0 ? r : a.key.compareTo(b.key);
      });
    buckets[BuildingCategory.civic] = [for (final e in ranked) e.value];
    return [
      for (final cat in BuildingCategory.values)
        if (buckets[cat]!.isNotEmpty) (cat: cat, defs: buckets[cat]!),
    ];
  }

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

/// A small dark plate for text that sits straight on the map, where bare cream
/// text would vanish — the build slots, the empty-category note.
Widget _darkPill({required Widget child, EdgeInsetsGeometry? padding}) =>
    Container(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: CreamPalette.ink.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );

/// Active/queued build-slot readout: builders working and builds waiting, SIDE BY
/// SIDE and with no plate behind them (user 2026-09-19: "Box bei Warteliste und
/// Bauarbeiter löschen, dafür nebeneinander"). They stand straight on the map, so
/// the glyphs and figures carry a hard dark edge to stay legible on any ground.
class _SlotChips extends StatelessWidget {
  final SettlementController ctrl;
  const _SlotChips({required this.ctrl});

  /// One 16 px line.
  static const double height = 18;

  @override
  Widget build(BuildContext context) {
    final active = ctrl.activeConstructionCount;
    final queued = ctrl.queuedConstructionCount;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(
            Icons.engineering,
            '$active/${ctrl.maxBuildSlots}',
            active >= ctrl.maxBuildSlots,
          ),
          const SizedBox(width: 12),
          _chip(
            Icons.hourglass_bottom,
            '$queued/${ctrl.maxQueueSlots}',
            queued >= ctrl.maxQueueSlots,
          ),
        ],
      ),
    );
  }

  static const _edge = [
    Shadow(color: Color(0xCC000000), blurRadius: 3),
    Shadow(color: Color(0x99000000), offset: Offset(0, 1)),
  ];

  Widget _chip(IconData icon, String count, bool full) {
    final tint = full ? FoE.coral : CreamPalette.paperTop;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: tint, shadows: _edge),
        const SizedBox(width: 3),
        Text(
          count,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: tint,
            shadows: _edge,
          ),
        ),
      ],
    );
  }
}

/// A TRAY card (user 2026-09-22): the same "art rises out of the top, text
/// below" shape as [_CarouselCard], deliberately simpler — nothing here is
/// being bought, so there is no cost, no afford-check dimming and no (i).
/// It already exists; it only needs a new spot.
class _TrayCard extends StatelessWidget {
  final BuildingDef def;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _TrayCard({
    required this.def,
    required this.width,
    required this.height,
    required this.onTap,
  });

  static const double _textH = 46;

  @override
  Widget build(BuildContext context) {
    final artBottom = height - _textH;
    final panelTop = artBottom * 0.42;
    final artW = width - 12;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: panelTop,
              bottom: 0,
              child: creamCard(child: const SizedBox.expand()),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: artBottom,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: def.isRoad
                    ? Image.asset(roadAsset(15), width: artW)
                    : ShadowedBuildingIcon(
                        imageUrl: def.imageUrl,
                        defId: def.id,
                        width: artW,
                      ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              height: _textH - 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: kBoxInk,
                    ),
                  ),
                  Text(
                    'Tap to place',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: kBoxInkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One building, small: the art stands on a line and rises out of the card's top
/// edge, everything written sits BELOW that line in its own fixed-height band —
/// name, then time / footprint / how many you have, then the cost — so the text
/// never runs into the art (user 2026-09-18) and the art gets all the rest.
class _CarouselCard extends StatelessWidget {
  final BuildingDef def;
  final Map<String, double> stock;
  final SettlementController ctrl;
  final VoidCallback onTap;

  /// Opens the building's preview; null hides the (i) (roads, the tutorial).
  final VoidCallback? onInfo;
  final double width;
  final double height;

  const _CarouselCard({
    required this.def,
    required this.stock,
    required this.ctrl,
    required this.onTap,
    required this.width,
    required this.height,
    this.onInfo,
  });

  /// Height of the written band: name + facts row + cost/reason + padding.
  static const double _textH = 58;

  @override
  Widget build(BuildContext context) {
    final status = BuildStatus.of(ctrl, def, stock);
    final enabled = status.enabled;
    final reason = status.reason;
    final ink = enabled ? kBoxInk : kBoxInkFaint;

    // Where the art's feet are: everything below is text.
    final artBottom = height - _textH;
    final panelTop = artBottom * 0.42;
    final artW = width - 12;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      // A long press is the same door as the (i), for a thumb already resting
      // on the card.
      onLongPress: onInfo,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: panelTop,
              bottom: 0,
              child: enabled
                  ? creamCard(child: const SizedBox.expand())
                  : DecoratedBox(
                      decoration: raisedTile(locked: true, radius: 14),
                    ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: artBottom,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _art(enabled, artW),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              height: _textH - 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text(
                    def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                  _factsRow(ink, placed: status.placed, max: status.max),
                  if (reason != null)
                    Text(
                      reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: CreamPalette.warn,
                      ),
                    )
                  else
                    _costRow(def.resourceCost, stock, enabled),
                ],
              ),
            ),
            // On top of everything, so its tap never falls through to "build".
            if (onInfo != null)
              Positioned(
                right: 0,
                top: panelTop,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onInfo,
                  child: Semantics(
                    label: 'About ${def.name}',
                    button: true,
                    // A 32 px hit area around a 20 px badge: the badge is small
                    // so the art stays clear, the target is not.
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: CreamPalette.gold,
                            boxShadow: [
                              BoxShadow(
                                color: CreamPalette.goldDeep,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: const Text(
                            'i',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: CreamPalette.ink,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _art(bool enabled, double artW) => def.isRoad
      ? Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Image.asset(roadAsset(15), width: artW),
        )
      : ShadowedBuildingIcon(
          imageUrl: def.imageUrl,
          defId: def.id,
          width: artW,
          dimmed: !enabled,
        );

  /// The three facts a player weighs before building: how long it takes, how
  /// much ground it covers, and how many of it you have (of the allowed cap,
  /// when there is one — roads are laid freely, so they show none).
  Widget _factsRow(Color ink, {required int placed, required int? max}) {
    Widget fact(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: ink),
        const SizedBox(width: 2),
        Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ],
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          fact(Icons.schedule, fmtDuration(def.constructionSeconds)),
          const SizedBox(width: 6),
          fact(Icons.crop_square, '${def.gridW}×${def.gridH}'),
          if (!def.isRoad) ...[
            const SizedBox(width: 6),
            fact(Icons.home_work, max == null ? '$placed' : '$placed/$max'),
          ],
        ],
      ),
    );
  }

  Widget _costRow(
    Map<String, double> cost,
    Map<String, double> stock,
    bool enabled,
  ) {
    if (cost.isEmpty) {
      return Text(
        'Free',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: enabled ? kBoxInk : kBoxInkFaint,
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final e in cost.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    resourceEmoji(e.key),
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${e.value.toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      // Only the resource you are SHORT of turns red.
                      color: (stock[e.key] ?? 0) >= e.value
                          ? kBoxInk
                          : CreamPalette.warn,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
