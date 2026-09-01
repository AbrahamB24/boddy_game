import '../settlement/data/resource_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../common/widgets/parchment_kit.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/recess_bar.dart';
import '../onboarding/intro_flow.dart';
import '../settlement/data/gather_defs.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/scroll_paper.dart'
    show parchmentButton, parchmentButtonInk;
import 'capture_encounter_screen.dart';
import 'expedition_launch_sheet.dart';
import 'models/area.dart';
import 'models/expedition.dart';
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import 'services/expedition_targets.dart';

// ── The Expeditions hub (rebuilt 2026-07-25, redrawn 2026-07-29) ────────────
//
// One screen for the whole activity, reached from the main screen's nav bar —
// NOT from the map any more (user: "der Zugang zu den Expeditionen soll über
// den Hauptbildschirm sein und nicht über die Karte"). The map went back to
// being the campaign: numbered battles and their boss, nothing else.
//
// Two sections, in the order the player thinks in:
//
//   OUT NOW   what is already away, with its countdown, and what to do when it
//             lands (collect happens by itself; a hunt still wants playing)
//   TARGETS   every spot and hunt in every unlocked region, with the stock
//             actually left in the ground — tap one to pick a group
//
// ── The 2026-07-29 redraw ──
// User: "designe den expeditions screen mitsamt hunt und gatherscreens komplett
// neu. Benutze dabei die Element von anderen bereits designten screens."
//
// It sat on a ParchmentPage and then printed DARK panels, dark buttons and a
// near-black confirm dialog onto it — two materials in one frame, and the one
// screen still doing it. Everything visual here now comes from the shared kit
// (parchment_kit.dart), which is itself lifted from the screens that were
// already right, so this hub finally matches the building dialog and the
// healing hut instead of approximating them.
//
// The LAYOUT changed with it, not just the colours:
//  • the running head carries the slot count ENGRAVED into the band, and a
//    second line naming what the count means when nothing can be sent;
//  • a trip is one card with the countdown as its headline, because "when is
//    it back" is the only thing you open this screen to learn;
//  • targets are grouped by region under a rule, and a blocked one says WHY on
//    the tile instead of waiting to be tapped for a snackbar.

/// The hub AS ITS OWN PAGE — a thin wrapper. Everything is in
/// [ExpeditionsBody], because the Management hub's Trips tab shows the very
/// same thing inline (user 2026-07-29: manage leads with Trips, "dadurch kann
/// der Trips button vom main screen verschwinden"). A tab that merely linked
/// onwards to this page would have made the shortcut longer than the button it
/// replaced.
class ExpeditionsScreen extends StatelessWidget {
  const ExpeditionsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ParchmentPage(
    title: 'Expeditions',
    // The slot count is the first thing that decides whether you can send
    // anything at all, so it rides in the bar rather than down the page.
    trailing: ExpeditionSlotChip(),
    child: ExpeditionsBody(),
  );
}

/// The slot readout — "2/3 🧭", cut into the running head. Its own widget so
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
  Widget build(BuildContext context) => ParchmentHeaderChip(
    text: '${_ctrl.activeCount}/${_ctrl.maxSlots} 🧭',
    alert: _ctrl.slotsFull,
  );
}

/// The three kinds of thing a group can be sent after — how [_categoryTabs]
/// splits the Targets list (user 2026-08-30: "Ev. würde es sich lohnen,
/// mehrere Reiter zu machen für Ressourcen, Luxusressourcen" — every unlocked
/// region used to print ALL of its spots plus its hunt in one long run, so
/// finding "is there a nearby fish spot" meant reading past every region's
/// wood and stone on the way).
enum _TargetCategory {
  resources('Resources', '🪵'),
  luxury('Luxury', '🐟'),
  hunt('Hunt', '🪤');

  final String label;
  final String emoji;
  const _TargetCategory(this.label, this.emoji);
}

/// Wood, stone and gold are the settlement's own fields, never a [GoodsDef] —
/// everything else gatherable is a supply good (fish, meat, …), and a hunt is
/// neither. [ExpeditionTarget.spot] is only null for a hunt, so the base-set
/// check never runs against it.
const _kBaseResources = {'wood', 'stone', 'gold'};

_TargetCategory _categoryOf(ExpeditionTarget t) {
  if (t.isHunt) return _TargetCategory.hunt;
  return _kBaseResources.contains(t.spot!.resource)
      ? _TargetCategory.resources
      : _TargetCategory.luxury;
}

/// What is out, and everywhere you could send a group. Hosted by
/// [ExpeditionsScreen] as a page and by the Management hub as its Trips tab.
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

  /// Which of the three target drawers is open. Resources leads — it is the
  /// everyday trip, same reasoning [targetsIn] already gives the hunt for
  /// sorting last within one area.
  _TargetCategory _category = _TargetCategory.resources;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
    // Deferred a frame (user 2026-08-31, "Unexpected null value" storm +
    // "setState() or markNeedsBuild() called during build"): this body is now
    // also one of the Management screen's TabBarView children, built inside
    // ITS OWN ListenableBuilder — so when a trip happens to already be due
    // the moment this mounts, collectFinished()'s notifyListeners() fires
    // while that ancestor is still mid-build, which is illegal. A post-frame
    // callback still pulls the reward forward, just one frame later, after
    // the build that mounted this widget has actually finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.collectFinished();
    });
    _showTripsIntro = _settlement.introStep == IntroStep.firstCapture;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_ctrl.expeditions.any((e) => e.isReadyToCollect(DateTime.now()))) {
        _ctrl.collectFinished();
      }
      _flushResults();
      if (mounted) setState(() {});
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
        _list(running, areas),
        if (_showTripsIntro) _tripsIntroOverlay(),
      ],
    );
  }

  Widget _list(List<Expedition> running, List<AreaDef> areas) {
    final visible = _visibleAreas(areas);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ParchmentPage.kParchmentPagePad,
        10,
        ParchmentPage.kParchmentPagePad,
        28,
      ),
      children: [
        // WHY NOTHING CAN GO, before the list of things that can't (user
        // 2026-07-29: the base pool is 0, so a settlement with no Scout Post
        // has an empty screen and no idea it is missing a building).
        if (_ctrl.noSlots) ...[_noSlotsBanner(), const SizedBox(height: 14)],
        // The caption counts who is still AWAY, not how many cards are listed
        // (user 2026-07-27): a hunt that has landed keeps its card until you
        // play its encounter, but it stopped occupying a slot and its party is
        // home and free.
        ParchmentSectionHeader(title: 'Out now', hint: _outHint(running)),
        if (running.isEmpty)
          _emptyOut()
        else
          for (final e in running) ...[
            _tripCard(e),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 16),
        ParchmentSectionHeader(
          title: 'Targets',
          hint: '${_creatures.availableForExpedition().length} monsters free',
        ),
        if (areas.isEmpty)
          Text(
            'No region is open yet — win your first battles.',
            style: FoE.dim(size: 12).copyWith(color: kInkFaint),
          )
        else ...[
          _categoryTabs(areas),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Nothing in ${_category.label.toLowerCase()} yet.',
                style: FoE.dim(size: 12).copyWith(color: kInkFaint),
              ),
            )
          else
            for (final (a, targets) in visible) _areaBlock(a, targets),
        ],
      ],
    );
  }

  /// Each unlocked area, paired with only the targets [_category] shows —
  /// areas with none in this drawer (a region with no fish spot, say) are
  /// left out entirely rather than printing an empty header.
  List<(AreaDef, List<ExpeditionTarget>)> _visibleAreas(List<AreaDef> areas) =>
      [
        for (final a in areas)
          (a, targetsIn(a).where((t) => _categoryOf(t) == _category).toList()),
      ]..removeWhere((e) => e.$2.isEmpty);

  /// The Resources / Luxury / Hunt drawers, in the bag's own tab style (user
  /// 2026-08-30) — a row of pills, each naming what it holds and how much of
  /// it, so switching drawers is a tap instead of a long scroll past whatever
  /// this region's OTHER spots happen to be.
  Widget _categoryTabs(List<AreaDef> areas) {
    final all = [for (final a in areas) ...targetsIn(a)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final cat in _TargetCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _category = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: parchmentButton(active: _category == cat),
                    child: Text(
                      '${cat.emoji} ${cat.label} '
                      '${all.where((t) => _categoryOf(t) == cat).length}',
                      style: FoE.label(size: 12).copyWith(
                        color: parchmentButtonInk(active: _category == cat),
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

  Widget _tripsIntroOverlay() => Positioned.fill(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showTripsIntro = false),
      child: Container(
        color: const Color(0xB3000000),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: FoE.panel(overrideBorder: FoE.borderGold, glow: true),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Trips', style: FoE.title(size: 15)),
              const SizedBox(height: 8),
              Text(
                'Send monsters out to gather resources or hunt a wild one. '
                'A spot you empty out regenerates over time, so it is worth '
                'a return trip later.',
                style: FoE.label(size: 12),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tap anywhere to continue',
                  style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                ),
              ),
            ],
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
  Widget _noSlotsBanner() => ParchmentCard(
    highlight: true,
    child: Row(
      children: [
        const Text('🧭', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No expedition slots',
                style: FoE.title(size: 14).copyWith(color: kInk),
              ),
              const SizedBox(height: 2),
              Text(
                'A Scout Post is what grants them — build one, or level it up.',
                style: FoE.dim(size: 11).copyWith(color: kInkSoft),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _emptyOut() => ParchmentCard(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
    child: Text(
      'No group is out. Pick a target below — gathering fills the storehouse, '
      'a hunt brings monsters home.',
      style: FoE.dim(size: 11).copyWith(color: kInkSoft),
    ),
  );

  // ── Out now ───────────────────────────────────────────────
  Widget _tripCard(Expedition e) {
    final area = areaById(e.areaId);
    final now = DateTime.now();
    final ready = e.isReadyToCollect(now);
    return ParchmentCard(
      highlight: ready,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.type.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tripTitle(e),
                      style: FoE.title(size: 14).copyWith(color: kInk),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${area?.emoji ?? '🗺️'} ${area?.name ?? e.areaId} · '
                      '${e.memberIds.length} 🐾',
                      style: FoE.dim(size: 10).copyWith(color: kInkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The COUNTDOWN is the headline — it is what the screen is
              // opened for, so it gets the biggest type on the card.
              ParchmentFact(
                label: ready ? 'back' : 'remaining',
                value: ready ? 'Ready' : fmtTripDuration(e.remaining(now)),
                color: ready ? kAccent : kInk,
              ),
            ],
          ),
          const SizedBox(height: 10),
          RecessBar(
            value: e.progress(now),
            color: ready ? kAccent : kParchmentGo,
            height: 10,
          ),
          const SizedBox(height: 8),
          _tripDetail(e, ready),
          const SizedBox(height: 12),
          Row(
            children: [
              if (e.type == ExpeditionType.capture && ready)
                ParchmentButton(
                  label: '▶️ Play the catch',
                  primary: true,
                  onTap: () => _openEncounter(e),
                ),
              if (!ready) _skipBtn(e),
              if (_settlement.isDev && !ready) ...[
                const SizedBox(width: 6),
                ParchmentButton(
                  label: '⏩ Dev',
                  onTap: () => _ctrl.devFinishNow(e),
                ),
              ],
              const Spacer(),
              ParchmentButton(
                label: 'Recall',
                danger: true,
                onTap: () => _confirmCancel(e),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _tripTitle(Expedition e) {
    if (e.type == ExpeditionType.gather) {
      final resource = e.payload['resource'] as String?;
      return resource == null ? e.type.label : 'Gathering $resource';
    }
    return 'Hunting';
  }

  Widget _tripDetail(Expedition e, bool ready) {
    if (e.type == ExpeditionType.gather) {
      final resource = e.payload['resource'] as String?;
      final amount = (e.payload['amount'] as num?)?.toDouble() ?? 0;
      if (resource == null) return const SizedBox.shrink();
      return Text(
        ready
            ? '${resourceEmoji(resource)} ${amount.toStringAsFixed(0)} '
                  '$resource delivered'
            : 'Bringing back ${resourceEmoji(resource)} '
                  '${amount.toStringAsFixed(0)} $resource',
        style: FoE.label(size: 12).copyWith(color: kInkSoft),
      );
    }
    // The finds stay hidden until the player opens the encounters.
    final total = e.captureFindSpeciesIds.length;
    final done = e.captureFindsDone;
    return Text(
      ready
          ? (done > 0
                ? '🪤 Encounter ${done + 1}/$total awaits!'
                : '🪤 Something took the bait — '
                      '$total encounter${total > 1 ? 's' : ''} await!')
          : '🪤 Tracking… ($total find${total > 1 ? 's' : ''} ahead)',
      style: FoE.label(size: 12).copyWith(color: kInkSoft),
    );
  }

  // ── Targets ───────────────────────────────────────────────
  // The area name + danger badge header used to run above each region's
  // targets — removed (user 2026-08-31: "Dies löschen bei Management"). The
  // category tabs already narrow the list to one kind of target; a name and
  // a danger number for each region on top of that was a second heading for
  // information the cards below don't need to repeat.
  Widget _areaBlock(AreaDef area, List<ExpeditionTarget> targets) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _targetsGrid(targets, _busySpotIds),
  );

  /// The tile shape every monster card in the game shares (user 2026-08-30,
  /// pasting a [CreatureCard]: "mache bei diesem Screen bitte auch boxen wie
  /// diese... aber anstelle des Monsters, soll die Ressource sein") — the
  /// shared [monsterTileGrid] size (user 2026-08-31: "sollen immer genau
  /// gleich hoch sein, überall in der gesamten App").
  Widget _targetsGrid(List<ExpeditionTarget> targets, Set<String> busy) =>
      monsterTileGrid([
        for (final t in targets)
          _targetCard(t, busy: busy.contains(t.spot?.id)),
      ]);

  /// The bottom strip's ink — white, with a soft dark shadow to hold on the
  /// palest resource colour (gold), the same pairing [CreatureCard] uses for
  /// exactly the same reason.
  static const List<Shadow> _cardShadow = [
    Shadow(color: Color(0x66000000), blurRadius: 0, offset: Offset(0, 1)),
  ];

  /// A hunt is not a resource, so it wears no resource colour — a deep
  /// mystery purple instead, distinct from every wood/stone/gold/fish/meat
  /// tile it sits beside.
  static const Color _huntColor = Color(0xFF6B5B95);

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
        ? 'A group is working this spot'
        : empty
        ? 'Mined out — it regrows'
        : full
        ? (_ctrl.noSlots ? 'Needs a Scout Post' : 'Every slot is busy')
        : null;

    final color = t.isHunt ? _huntColor : resourceColor(spot!.resource);
    final title = t.isHunt ? 'Hunt' : resourceName(spot!.resource);
    final top = Color.lerp(color, Colors.white, 0.22)!;
    final bottom = Color.lerp(color, Colors.black, 0.30)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTarget(t, busy: busy, empty: empty, full: full),
      child: Opacity(
        opacity: blocked ? 0.6 : 1,
        // The SAME top reserve [CreatureCard] leaves for its sprite to pop
        // into (user 2026-08-31: "diese Kacheln wirken aber viel länger") —
        // without it this card's colour ran edge to edge in a box shaped for
        // one that doesn't, and a flat-topped card in the Monster tile's own
        // tall/narrow proportions reads as far more elongated than the
        // Monster tile itself ever does, even at the identical footprint.
        child: LayoutBuilder(
          builder: (context, c) => Padding(
            padding: EdgeInsets.only(top: c.maxHeight * 0.17),
            child: Container(
              clipBehavior: Clip.antiAlias,
              // radius 22, not 18 (2026-08-31 audit) — this card's own
              // comment above says it deliberately matches CreatureCard's
              // shape/footprint; CreatureCard's outer radius is 22, so the
              // corner itself hadn't actually matched what the comment
              // claims.
              decoration: ShapeDecoration(shape: FoE.facet(radius: 22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The "art" — no sprite to show, so the resource's own emoji
                  // stands in for it, big, on the resource's own colour.
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [top, bottom],
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(t.emoji, style: const TextStyle(fontSize: 40)),
                          // The stock — the one number worth reading at a glance,
                          // in [CreatureCard]'s own top-right power-badge spot.
                          if (spot != null)
                            Positioned(
                              top: 6,
                              right: 8,
                              child: Text(
                                stock.toStringAsFixed(0),
                                style: FoE.value(size: 14).copyWith(
                                  color: Colors.white,
                                  shadows: _cardShadow,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
                    color: bottom,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.label(size: 12).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            shadows: _cardShadow,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (reason != null)
                          Text(
                            reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FoE.dim(size: 9).copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              shadows: _cardShadow,
                            ),
                          )
                        else if (dials != null) ...[
                          RecessBar(
                            value: dials.spotCapacity <= 0
                                ? 0
                                : (stock / dials.spotCapacity).clamp(0.0, 1.0),
                            color: kParchmentGo,
                            height: 5,
                            onDark: true,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '+${dials.regenPerHour.toStringAsFixed(0)}/h',
                            style: FoE.dim(size: 9).copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              shadows: _cardShadow,
                            ),
                          ),
                        ] else
                          Text(
                            'Caught by hand on return',
                            maxLines: 2,
                            style: FoE.dim(size: 9).copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                              shadows: _cardShadow,
                            ),
                          ),
                      ],
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
  Widget _skipBtn(Expedition e) {
    final cost = _ctrl.goldSkipCost(e);
    final canPay = _settlement.gold >= cost;
    return ParchmentButton(
      label: '🪙 $cost',
      sub: canPay ? 'finish now' : 'not enough gold',
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
