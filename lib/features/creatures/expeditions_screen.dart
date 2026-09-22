import '../settlement/data/resource_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/strategy_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_kit.dart' show parchmentConfirm;
import '../onboarding/intro_flow.dart';
import '../settlement/data/gather_defs.dart';
import '../settlement/settlement_controller.dart';
import 'capture_encounter_screen.dart';
import 'expedition_launch_sheet.dart';
import 'models/area.dart';
import 'models/expedition.dart';
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import 'services/expedition_targets.dart';
import '../../core/ui/pressable.dart';

// ── The Expeditions hub (rebuilt 2026-07-25, redrawn 2026-07-29, reskinned
// 2026-09-17, restructured 2026-09-17, landscape 2026-09-18) ───────────────
//
// One screen for the whole activity, reached from the main screen's nav bar —
// NOT from the map any more (user: "der Zugang zu den Expeditionen soll über
// den Hauptbildschirm sein und nicht über die Karte"). The map went back to
// being the campaign: numbered battles and their boss, nothing else.
//
// ── The 2026-09-18 landscape pass ──
// The whole app switched to landscape and to the strategy-HUD look this
// session built out on the Settlement screen first (see
// core/theme/strategy_theme.dart). Two things actually moved here, not just
// recoloured:
//
//  • OUT NOW is a plain vertical list in its OWN narrow column now, not a
//    swipeable carousel — landscape hands this screen height it didn't have
//    in portrait, and a narrow column can stack several short cards in that
//    height without needing a PageView/dots to page between them at all.
//  • TARGETS keep their per-region rails, but now live in the wider column
//    beside "Out now" instead of below it — the two no longer compete for
//    the same vertical space the way they did stacked in portrait.

/// The hub AS ITS OWN PAGE — a thin wrapper. [ManagementScreen] renders the
/// exact same [ExpeditionsBody] under its own title/entry point.
///
/// A MENU over the dimmed map (user 2026-09-18: the whole UI takes the building
/// dialog as its template) — push it with [pushMenu].
class ExpeditionsScreen extends StatelessWidget {
  const ExpeditionsScreen({super.key});

  @override
  Widget build(BuildContext context) => const MenuScaffold(
    title: 'Expeditions',
    // The slot count is the first thing that decides whether you can send
    // anything at all, so it rides in the bar rather than down the page.
    trailing: ExpeditionSlotChip(),
    child: ExpeditionsBody(),
  );
}

/// The slot readout — a gem badge + "2/3" in the header. Its own widget so
/// either host can show it without owning the count.
class ExpeditionSlotChip extends StatefulWidget {
  const ExpeditionSlotChip({super.key});

  @override
  State<ExpeditionSlotChip> createState() => _ExpeditionSlotChipState();
}

class _ExpeditionSlotChipState extends State<ExpeditionSlotChip> {
  final _ctrl = ExpeditionController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      GemBadge(
        size: 30,
        color: _ctrl.slotsFull ? Strategy.coral : Strategy.gold,
        child: const Text('🧭', style: TextStyle(fontSize: 13)),
      ),
      const SizedBox(width: 5),
      // Navy, not white: the readout sits on a cream title card now.
      Text(
        '${_ctrl.activeCount}/${_ctrl.maxSlots}',
        style: const TextStyle(
          color: kBoxInk,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ],
  );
}

/// The two kinds of thing a group can be sent after — how the filter chips
/// split the Targets list. Luxury used to be a third, separate drawer (user
/// 2026-08-30), but merged back into Resources (user 2026-09-12, once the
/// region ladder dropped to one luxury per region: "dann kann ich bei
/// Management die Luxury aufheben und zu Resources nehmen, da 3 nebeneinander
/// Platz haben, dadurch wird es auch aufgeräumter").
enum ExpeditionTargetCategory {
  resources('Resources', '🪵'),
  hunt('Hunt', '🪤');

  final String label;
  final String emoji;
  const ExpeditionTargetCategory(this.label, this.emoji);
}

ExpeditionTargetCategory _categoryOf(ExpeditionTarget t) => t.isHunt
    ? ExpeditionTargetCategory.hunt
    : ExpeditionTargetCategory.resources;

/// What is out, and everywhere you could send a group — one page, no tabs:
/// a narrow "out now" column, a Resources/Hunt filter, and every unlocked
/// region's targets as its own horizontally-scrolling rail beside it.
class ExpeditionsBody extends StatefulWidget {
  const ExpeditionsBody({super.key});

  @override
  State<ExpeditionsBody> createState() => _ExpeditionsBodyState();
}

class _ExpeditionsBodyState extends State<ExpeditionsBody> {
  final _ctrl = ExpeditionController();
  final _creatures = CreaturesController();
  final _settlement = SettlementController();
  Timer? _ticker;

  // One-time explanation on the tutorial's own catch step (user 2026-08-24:
  // "Trips erklären, Ressourcen sammeln, dass diese regenerieren").
  bool _showTripsIntro = false;

  /// Which target drawer the rails show. Resources leads — it is the
  /// everyday trip, same reasoning [targetsIn] already gives the hunt for
  /// sorting last within one area.
  ExpeditionTargetCategory _category = ExpeditionTargetCategory.resources;

  /// Fixed tile size for a region rail's target cards — deliberately its
  /// OWN constant rather than the shared monster-tile grid's (that one
  /// reads the device's raw WIDTH, which is now this screen's long axis in
  /// landscape and would size a tile taller than the whole screen).
  static const double _tileW = 92;
  static const double _tileH = 126;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
    // Deferred a frame (user 2026-08-31, "Unexpected null value" storm +
    // "setState() or markNeedsBuild() called during build"): a trip already
    // due the moment this mounts must not fire collectFinished()'s
    // notifyListeners() while an ancestor (the settlement screen's own
    // ListenableBuilder) is still mid-build. A post-frame callback still
    // pulls the reward forward, just one frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.collectFinished();
    });
    _showTripsIntro = _settlement.introStep == IntroStep.firstCapture;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ctrl.expeditions.any((e) => e.isReadyToCollect(DateTime.now()))) {
        _ctrl.collectFinished();
      }
      _flushResults();
      // Nothing out on a trip means no countdown to redraw.
      if (mounted && _ctrl.expeditions.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _flushResults() {
    for (final r in _ctrl.drainResults()) {
      context.snack(r);
    }
  }

  /// Spots already being mined by a trip that is out — shown as busy so two
  /// groups aren't sent to the same rock. A gather trip stores its spot in
  /// [Expedition.targetId] (the payload only carries the resource + haul).
  Set<String> get _busySpotIds => {
    for (final e in _ctrl.expeditions)
      if (e.type == ExpeditionType.gather && e.targetId != null) e.targetId!,
  };

  @override
  Widget build(BuildContext context) {
    // CARAVANS ARE NOT EXPEDITIONS (user 2026-07-29: "unterscheide expeditions
    // und karawanen für den Markt"). A trade run is still one of these records
    // — same table, same timer — but it has its own seats, its own amplifiers
    // and its own page. The Market lists what is on the market road; this hub
    // lists what is out in the world.
    final running = [
      for (final e in _ctrl.expeditions)
        if (!ExpeditionController.isCaravan(e)) e,
    ];
    final areas = unlockedAreas(_settlement.dungeonMaxStage);
    return Stack(
      children: [
        _layout(running, areas),
        if (_showTripsIntro) _tripsIntroOverlay(),
      ],
    );
  }

  Widget _layout(List<Expedition> running, List<AreaDef> areas) => Padding(
    // The menu frame already pads; only the bottom needs a little air here.
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // WHY NOTHING CAN GO, before the list of things that can't (user
        // 2026-07-29: the base pool is 0, so a settlement with no Scout Post
        // has an empty screen and no idea it is missing a building).
        if (_ctrl.noSlots) ...[_noSlotsBanner(), const SizedBox(height: 10)],
        Expanded(
          // The left column's width is a FRACTION of what's actually
          // available (2026-09-18, responsiveness pass), not a flat 220px —
          // a landscape phone's long axis runs anywhere from ~667px (iPhone
          // SE) to this app's own 932px cap, and a fixed width either ate
          // more of a narrow phone's room than intended or left a small
          // phone's target column cramped.
          child: LayoutBuilder(
            builder: (context, c) {
              final outNowWidth = (c.maxWidth * 0.26).clamp(190.0, 260.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Each column is a cream card of its own, with a flat
                  // heading — text stands on cards, never on the map.
                  SizedBox(
                    width: outNowWidth,
                    child: sectionCard(
                      title: 'Out now',
                      icon: Icons.explore,
                      trailing: Flexible(
                        child: Text(
                          _outHint(running),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kBoxInkFaint,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      expand: true,
                      child: _outNowColumn(running),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: sectionCard(
                      title: 'Targets',
                      icon: Icons.travel_explore,
                      expand: true,
                      child: _targetsColumn(areas),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );

  /// Resources this settlement can actually gather — a spot doesn't show
  /// until something producing it has been built (user 2026-09-12: "Fish
  /// sobald fishing hut gebaut wurde, Holz sobald Holzfäller gebaut wurde
  /// etc."). Only COMPLETE buildings count — one still under construction
  /// doesn't produce anything yet either.
  Set<String> get _unlockedResources => resourcesProducedBy([
    for (final b in _settlement.buildings)
      if (b.isComplete) b.buildingTypeId,
  ]);

  /// Each unlocked area, paired with only the targets [_category] shows —
  /// areas with none in this drawer (a region with no fish spot, say) are
  /// left out entirely rather than printing an empty rail.
  List<(AreaDef, List<ExpeditionTarget>)> _visibleAreas(List<AreaDef> areas) =>
      [
        for (final a in areas)
          (
            a,
            targetsIn(
              a,
              unlockedResources: _unlockedResources,
            ).where((t) => _categoryOf(t) == _category).toList(),
          ),
      ]..removeWhere((e) => e.$2.isEmpty);

  /// The one hunt target in [visible], or null when there is more than one
  /// (or the drawer open isn't Hunt at all — every target in it would fail
  /// `isHunt` then, same result). [visible] is already filtered to
  /// [_category] by [_visibleAreas], so when it IS Hunt every target here
  /// already is one.
  ExpeditionTarget? _soleHunt(List<(AreaDef, List<ExpeditionTarget>)> visible) {
    if (_category != ExpeditionTargetCategory.hunt) return null;
    final hunts = [for (final (_, targets) in visible) ...targets];
    return hunts.length == 1 ? hunts.first : null;
  }

  // ── Left column: what's out ──────────────────────────────
  // The heading and the hint live on the card's own title row now.
  Widget _outNowColumn(List<Expedition> running) => running.isEmpty
      ? _emptyOut()
      : ListView.separated(
          padding: const EdgeInsets.only(bottom: 4),
          itemCount: running.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _tripCard(running[i]),
        );

  // ── Right column: everywhere you can send a group ────────
  Widget _targetsColumn(List<AreaDef> areas) {
    if (areas.isEmpty) {
      return Text(
        'No region is open yet — win your first battles.',
        style: TextStyle(color: kBoxInkSoft, fontSize: 12),
      );
    }
    final visible = _visibleAreas(areas);
    final soleHunt = _soleHunt(visible);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterRow(areas),
        const SizedBox(height: 10),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    'Nothing in ${_category.label.toLowerCase()} yet.',
                    style: TextStyle(color: kBoxInkSoft, fontSize: 12),
                  ),
                )
              : soleHunt != null
              // Exactly one hunt on offer: nothing left to pick between, so
              // its own launch panel replaces the rails (user 2026-09-08:
              // "Ich möchte, dass der Inhalt von diesem Overlay auf dieser
              // Seite angezeigt wird"). More than one hunt still shows the
              // rails — which one was meant is a real question there.
              ? ExpeditionLaunchPanel(
                  key: ValueKey('hunt_inline_${soleHunt.area.id}'),
                  target: soleHunt,
                  inline: true,
                )
              : ListView(
                  children: [
                    for (final (a, targets) in visible) _regionRail(a, targets),
                  ],
                ),
        ),
      ],
    );
  }

  /// The Resources / Hunt switch — a pair of live filter chips, each naming
  /// what it holds and how much of it, plus how many monsters are free to
  /// send right now.
  Widget _filterRow(List<AreaDef> areas) {
    final all = [
      for (final a in areas)
        ...targetsIn(a, unlockedResources: _unlockedResources),
    ];
    final free = _creatures.availableForExpedition().length;
    return Row(
      children: [
        for (final cat in ExpeditionTargetCategory.values) ...[
          SelectChip(
            emoji: cat.emoji,
            label: cat.label,
            count: all.where((t) => _categoryOf(t) == cat).length,
            active: _category == cat,
            onTap: () => setState(() => _category = cat),
          ),
          const SizedBox(width: 8),
        ],
        const Spacer(),
        Text(
          '🐾 $free free',
          style: TextStyle(
            color: kBoxInkSoft,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _tripsIntroOverlay() => Positioned.fill(
    child: Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showTripsIntro = false),
      // In the cream kit, like the one Battle Prep shows (2026-09-21) — this
      // was the last tutorial overlay still built out of `Strategy.*` and a
      // navy scrim, from the step of the redesign before the cream kit
      // existed. Both cards appear in the same run of the tutorial, minutes
      // apart, so they cannot look like two different games.
      child: Container(
        color: CreamPalette.dim,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: creamCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trips',
                  style: FoE.title(size: 15).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 8),
                Text(
                  'Send monsters out to gather resources or hunt a wild one. '
                  'A spot you empty out regenerates over time, so it is worth '
                  'a return trip later.',
                  style: FoE.label(size: 12).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap anywhere to continue',
                    style: FoE.dim(size: 11).copyWith(color: kBoxAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  String _outHint(List<Expedition> running) {
    final away = _ctrl.activeCount;
    final home = _ctrl.awaitingPlay
        .where((e) => !ExpeditionController.isCaravan(e))
        .length;
    if (running.isEmpty) return 'nobody is away';
    if (away == 0) return '$home back — play ${home > 1 ? 'them' : 'it'}';
    return home == 0 ? '$away on the road' : '$away on the road · $home back';
  }

  /// The one thing worth saying when the settlement cannot send anything at
  /// all. A row of tiles that all refuse to open is not an explanation.
  Widget _noSlotsBanner() => SizedBox(
    width: double.infinity,
    // A cream card with a gold underside, not a gold button-lookalike: it is
    // a notice, and only pressable things are gold.
    child: creamCard(
      padding: const EdgeInsets.all(12),
      deep: Strategy.goldDeep,
      child: Row(
        children: [
          const Text('🧭', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No expedition slots',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Strategy.outline,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'A Scout Post is what grants them — build one, or level it up.',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Strategy.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _emptyOut() => Text(
    'No group is out. Pick a target — gathering fills the storehouse, a '
    'hunt brings monsters home.',
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: kBoxInkSoft,
    ),
  );

  // ── Out now ───────────────────────────────────────────────
  // A plain card in its own scrolling column now (2026-09-18 landscape
  // pass) — the [RadialTimer] dial still halves the height a trip card
  // needs versus a linear bar, but landscape's own extra height meant the
  // swipeable carousel this replaced was solving a problem that no longer
  // existed once "Out now" got its own column instead of sharing width
  // with the targets below it.
  Widget _tripCard(Expedition e) {
    final now = DateTime.now();
    final ready = e.isReadyToCollect(now);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      // A raised tile on the card; READY earns the gold rim.
      decoration: raisedTile(lit: ready),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadialTimer(
            value: e.progress(now),
            emoji: e.type.emoji,
            ready: ready,
            size: 46,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tripTitle(e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Strategy.outline,
                  ),
                ),
                const SizedBox(height: 3),
                PillBadge(
                  text: ready ? 'READY' : fmtTripDuration(e.remaining(now)),
                  color: ready ? Strategy.cyan : Strategy.outline,
                ),
                const SizedBox(height: 4),
                Text(
                  _tripDetailText(e, ready),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: Strategy.outline.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (e.type == ExpeditionType.capture && ready)
                      _miniChip(
                        '▶️ Play',
                        color: Strategy.cyan,
                        deep: Strategy.cyanDeep,
                        onTap: () => _openEncounter(e),
                      )
                    else if (!ready)
                      _skipChip(e),
                    const SizedBox(width: 4),
                    _miniChip(
                      '✕',
                      color: Strategy.coral,
                      deep: Strategy.coralDeep,
                      onTap: () => _confirmCancel(e),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(
    String label, {
    required Color color,
    required Color deep,
    VoidCallback? onTap,
  }) => ChunkyButton(
    onTap: onTap,
    fill: color,
    deep: deep,
    radius: 10,
    shadowOffset: 3,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: strategyTextOn(color),
      ),
    ),
  );

  String _tripTitle(Expedition e) {
    if (e.type == ExpeditionType.gather) {
      final resource = e.payload['resource'] as String?;
      return resource == null ? e.type.label : 'Gathering $resource';
    }
    return 'Hunting';
  }

  String _tripDetailText(Expedition e, bool ready) {
    if (e.type == ExpeditionType.gather) {
      final resource = e.payload['resource'] as String?;
      final amount = (e.payload['amount'] as num?)?.toDouble() ?? 0;
      if (resource == null) return '';
      return ready
          ? '${resourceEmoji(resource)} ${amount.toStringAsFixed(0)} '
                '$resource delivered'
          : 'Bringing back ${resourceEmoji(resource)} '
                '${amount.toStringAsFixed(0)} $resource';
    }
    // The finds stay hidden until the player opens the encounters.
    final total = e.captureFindSpeciesIds.length;
    final done = e.captureFindsDone;
    return ready
        ? (done > 0
              ? '🪤 Encounter ${done + 1}/$total awaits!'
              : '🪤 Something took the bait — '
                    '$total encounter${total > 1 ? 's' : ''} await!')
        : '🪤 Tracking… ($total find${total > 1 ? 's' : ''} ahead)';
  }

  // ── Targets ───────────────────────────────────────────────
  // Grouped into per-region RAILS — a header naming the region, a
  // horizontally-scrolling row of its own spots — stacked vertically in
  // the right-hand column now that "out now" has its own column beside it.
  Widget _regionRail(AreaDef area, List<ExpeditionTarget> targets) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Row(
            children: [
              Text(area.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(
                area.name,
                style: TextStyle(
                  color: kBoxAccent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: _tileH,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: targets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox(
              width: _tileW,
              child: _targetCard(
                targets[i],
                busy: _busySpotIds.contains(targets[i].spot?.id),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _targetCard(ExpeditionTarget t, {required bool busy}) {
    final spot = t.spot;
    final stock = spot == null ? 0.0 : _ctrl.availableStock(spot);
    final dials = spot == null ? null : gatherDefFor(spot.resource);
    final full = _ctrl.slotsFull;
    // A depleted spot is shown, not hidden: it regrows, and knowing WHICH rock
    // is empty is what makes the regen rate meaningful.
    final empty = spot != null && stock < 1;
    final blocked = full || busy || empty;
    // WHY it is blocked, on the card. It used to take a tap to find out, which
    // meant tapping every dead tile in turn to learn the same thing.
    final reason = busy
        ? 'Working'
        : empty
        ? 'Mined out'
        : full
        ? (_ctrl.noSlots ? 'Needs a Scout Post' : 'Slots full')
        : null;

    final title = t.isHunt ? 'Hunt' : resourceName(spot!.resource);
    final ink = blocked ? kBoxInkFaint : kBoxInk;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTarget(t, busy: busy, empty: empty, full: full),
      child: Container(
        clipBehavior: Clip.antiAlias,
        // The same raised tile as a trip; greyed when it cannot be used.
        decoration: raisedTile(locked: blocked, radius: 14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: blocked ? 0.5 : 1,
                      child: Text(
                        t.emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                    if (blocked)
                      const Positioned(
                        bottom: 0,
                        child: Text('🔒', style: TextStyle(fontSize: 14)),
                      ),
                    if (spot != null)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: PillBadge(
                          text: stock.toStringAsFixed(0),
                          color: blocked ? Strategy.locked : Strategy.gold,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 3),
              if (reason != null)
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                )
              else if (dials != null)
                ChunkyBar(
                  value: dials.spotCapacity <= 0
                      ? 0
                      : (stock / dials.spotCapacity).clamp(0.0, 1.0),
                  color: Strategy.gold,
                  height: 6,
                )
              else
                Text(
                  'By hand',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTarget(
    ExpeditionTarget t, {
    required bool busy,
    required bool empty,
    required bool full,
  }) async {
    // The tile already says WHY (see `reason` above); the tap repeats it as a
    // snackbar for the case where the caption was scrolled past.
    if (busy) {
      context.snack('A group is already working this spot.');
      return;
    }
    if (empty) {
      context.snack('This spot is mined out — it regrows over time.');
      return;
    }
    if (full) {
      // "All 0 slots are busy" is not an answer (user 2026-07-29): with no
      // Scout Post there is no party to recall, so the tile names the building
      // instead of blaming an imaginary queue.
      context.snack(
        _ctrl.noSlots
            ? 'No expedition slots — build a Scout Post to open them.'
            : 'All ${_ctrl.maxSlots} expedition slots are busy. Recall one, '
                  'or wait.',
      );
      return;
    }
    final sent = await showExpeditionLaunchSheet(context, t);
    if (!mounted) return;
    if (sent == true) context.snack('Off they go!');
    setState(() {});
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _openEncounter(Expedition e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CaptureEncounterScreen(expedition: e)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _confirmCancel(Expedition e) async {
    final members = e.memberIds
        .map((id) => CreaturesController().byId(id)?.displayName ?? id)
        .join(', ');
    final ok = await parchmentConfirm(
      context,
      title: 'Recall expedition?',
      message: 'Frees $members immediately with no reward.',
      confirmLabel: 'Recall',
      danger: true,
    );
    if (ok) _ctrl.cancel(e);
  }

  /// Bring a trip home with gold. Priced on the time LEFT (gold_economy.dart),
  /// so it gets cheaper as the trip runs — waiting is always the thrifty play
  /// and gold stays a convenience.
  ///
  /// It ends the TRAVEL only: a hunt still has to be played by hand afterwards.
  /// Gold buys time, never a result.
  Widget _skipChip(Expedition e) {
    final cost = _ctrl.goldSkipCost(e);
    final canPay = _settlement.gold >= cost;
    return _miniChip(
      '🪙 $cost',
      color: Strategy.gold,
      deep: Strategy.goldDeep,
      onTap: canPay
          ? () async {
              final err = await _ctrl.skipWithGold(e);
              if (!mounted || err == null) return;
              context.snack(err);
            }
          : null,
    );
  }
}
