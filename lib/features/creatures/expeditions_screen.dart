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
    show
        kActionGreen,
        kPageShadow,
        kParchmentInk,
        parchmentButton,
        parchmentButtonInk;
import 'capture_encounter_screen.dart';
import 'expedition_launch_sheet.dart';
import 'models/area.dart';
import 'models/expedition.dart';
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import 'services/expedition_targets.dart';
import '../../core/ui/pressable.dart';

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

/// The two kinds of thing a group can be sent after — how [_categoryTabs]
/// splits the Targets list. Luxury used to be a third, separate drawer (user
/// 2026-08-30), but merged back into Resources (user 2026-09-12, once the
/// region ladder dropped to one luxury per region: "dann kann ich bei
/// Management die Luxury aufheben und zu Resources nehmen, da 3 nebeneinander
/// Platz haben, dadurch wird es auch aufgeräumter") — with only one luxury
/// spot per region instead of two, a merged list still fits the grid without
/// crowding, and Management goes back to three tabs instead of four.
enum ExpeditionTargetCategory {
  resources('Resources', '🪵'),
  hunt('Hunt', '🪤');

  final String label;
  final String emoji;
  const ExpeditionTargetCategory(this.label, this.emoji);
}

ExpeditionTargetCategory _categoryOf(ExpeditionTarget t) =>
    t.isHunt ? ExpeditionTargetCategory.hunt : ExpeditionTargetCategory.resources;

/// What is out, and everywhere you could send a group. Hosted by
/// [ExpeditionsScreen] as a full page (out-now plus a switcher between both
/// target drawers), and by the Management hub as three separate tabs — two
/// narrowed to one fixed [onlyCategory] each, plus one [onlyTrips]
/// (2026-09-11: Work and Housing left Management for their own Castle-opened
/// screens, and the room they left went to promoting these drawers to tabs
/// in their own right instead of a switcher buried in one Trips tab).
class ExpeditionsBody extends StatefulWidget {
  /// Locks this instance to one target drawer, with no switcher and no
  /// "out now" section.
  final ExpeditionTargetCategory? onlyCategory;

  /// Shows only what is currently away — no targets at all.
  final bool onlyTrips;

  const ExpeditionsBody({super.key, this.onlyCategory, this.onlyTrips = false});

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
  /// sorting last within one area. Fixed for the life of the widget when
  /// [ExpeditionsBody.onlyCategory] is set.
  late ExpeditionTargetCategory _category =
      widget.onlyCategory ?? ExpeditionTargetCategory.resources;

  /// Whether the "out now" section shows at all.
  bool get _showOutNow => widget.onlyCategory == null;

  /// Whether the targets section shows at all.
  bool get _showTargets => !widget.onlyTrips;

  /// Whether this instance is locked to one drawer (no switcher, no "Out
  /// now" — one of Management's Resources/Luxury/Hunt tabs).
  bool get _targetsOnly => widget.onlyCategory != null;

  /// Whether the category switcher pills show — only the full hub (neither
  /// locked to one category nor trips-only) needs to switch between drawers.
  bool get _switchable => widget.onlyCategory == null && !widget.onlyTrips;

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
    final soleHunt = _soleHunt(visible);
    return ListView(
      // kMonsterTilePageMargin (24), not ParchmentPage.kParchmentPagePad (36)
      // — user 2026-09-11: "bitte 3 Boxen nebeneinander und nicht nur 2".
      // Every [monsterTileGrid] on this page (the target tiles, and the
      // inline hunt panel's group picker) sizes its tiles off the raw
      // device width assuming a 24px host margin, same as the Monsters
      // screen; hosting it at 36 left just short of room for a third tile
      // per row, same mismatch this file's OWN comments already flagged and
      // fixed once for the roster picker's GridView.
      padding: const EdgeInsets.fromLTRB(
        kMonsterTilePageMargin,
        10,
        kMonsterTilePageMargin,
        28,
      ),
      children: [
        // WHY NOTHING CAN GO, before the list of things that can't (user
        // 2026-07-29: the base pool is 0, so a settlement with no Scout Post
        // has an empty screen and no idea it is missing a building).
        if (_ctrl.noSlots) ...[_noSlotsBanner(), const SizedBox(height: 14)],
        if (_showOutNow) ...[
          // The caption counts who is still AWAY, not how many cards are
          // listed (user 2026-07-27): a hunt that has landed keeps its card
          // until you play its encounter, but it stopped occupying a slot
          // and its party is home and free.
          ParchmentSectionHeader(title: 'Out now', hint: _outHint(running)),
          if (running.isEmpty)
            _emptyOut()
          else
            // 6, not 10 (2026-09-11) — several of these will stack once more
            // than one hunt can run at once, so the gap between them shrank
            // along with each card's own height.
            for (final e in running) ...[
              _tripCard(e),
              const SizedBox(height: 6),
            ],
          if (_showTargets) const SizedBox(height: 16),
        ],
        if (_showTargets) ...[
          // Skipped when the inline launch panel below is about to show
          // (user 2026-09-11): it already carries its own "Hunt length"
          // header, so a second title plus a free-monster count read as a
          // stray bar sitting above it rather than a heading for anything.
          if (soleHunt == null)
            ParchmentSectionHeader(
              title: _targetsOnly ? _category.label : 'Targets',
              hint:
                  '${_creatures.availableForExpedition().length} monsters free',
            ),
          if (areas.isEmpty)
            Text(
              'No region is open yet — win your first battles.',
              style: FoE.dim(size: 12).copyWith(color: kInkFaint),
            )
          else ...[
            if (_switchable) _categoryTabs(areas),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Nothing in ${_category.label.toLowerCase()} yet.',
                  style: FoE.dim(size: 12).copyWith(color: kInkFaint),
                ),
              )
            else if (soleHunt case final hunt?)
              // Exactly one hunt on offer: nothing left to pick between, so
              // its own launch panel replaces the card-then-modal-sheet route
              // (user 2026-09-08: "Ich möchte, dass der Inhalt von diesem
              // Overlay auf dieser Seite angezeigt wird"). More than one hunt
              // (a second region unlocked) still shows the card grid below —
              // which one was meant is a real question there.
              ExpeditionLaunchPanel(
                key: ValueKey('hunt_inline_${hunt.area.id}'),
                target: hunt,
                inline: true,
              )
            else
              for (final (a, targets) in visible) _areaBlock(a, targets),
          ],
        ],
      ],
    );
  }

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
  /// left out entirely rather than printing an empty header.
  List<(AreaDef, List<ExpeditionTarget>)> _visibleAreas(List<AreaDef> areas) =>
      [
        for (final a in areas)
          (
            a,
            targetsIn(a, unlockedResources: _unlockedResources)
                .where((t) => _categoryOf(t) == _category)
                .toList(),
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

  /// The Resources / Hunt drawers, in the bag's own tab style (user
  /// 2026-08-30) — a row of pills, each naming what it holds and how much of
  /// it, so switching drawers is a tap instead of a long scroll past whatever
  /// this region's OTHER spots happen to be.
  Widget _categoryTabs(List<AreaDef> areas) {
    final all = [
      for (final a in areas) ...targetsIn(a, unlockedResources: _unlockedResources),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final cat in ExpeditionTargetCategory.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Pressable(
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
    child: Pressable(
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
  // Redesigned compact (user 2026-09-11: "'out now' neu gestalten, damit es
  // weniger Platz einnimmt. Es werden später mehrere Hunts parallel laufen")
  // — several of these will stack once more than one hunt can run at once, so
  // the per-trip footprint had to shrink: the area/region line is gone
  // entirely ("Das Gebiet kann gelöscht werden" — a hunt already isn't tied
  // to what it can find there, same reasoning as the launch sheet dropping
  // its own area row), the countdown moved into the title row instead of its
  // own two-line [ParchmentFact], the progress bar is thinner, and the
  // detail line now shares a row with icon-sized actions instead of each
  // getting a full [ParchmentButton] row of their own.
  Widget _tripCard(Expedition e) {
    final now = DateTime.now();
    final ready = e.isReadyToCollect(now);
    return ParchmentCard(
      highlight: ready,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(e.type.emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _tripTitle(e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.title(size: 13).copyWith(color: kInk),
                ),
              ),
              const SizedBox(width: 8),
              // The COUNTDOWN is the headline — it is what the card is read
              // for — right in the title row now rather than its own fact
              // block, which cost a whole extra line for a caption ("back" /
              // "remaining") the ready-state colour already implies.
              Text(
                ready ? 'Ready' : fmtTripDuration(e.remaining(now)),
                style: FoE.value(size: 13).copyWith(
                  color: ready ? kAccent : kInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RecessBar(
            value: e.progress(now),
            color: ready ? kAccent : kParchmentGo,
            height: 7,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _tripDetailText(e, ready),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 11).copyWith(color: kInkSoft),
                ),
              ),
              const SizedBox(width: 6),
              if (e.type == ExpeditionType.capture && ready)
                _miniAction('▶️ Play', primary: true, onTap: () => _openEncounter(e))
              else if (!ready) ...[
                _skipChip(e),
                if (_settlement.isDev) ...[
                  const SizedBox(width: 4),
                  _miniAction('⏩', onTap: () => _ctrl.devFinishNow(e)),
                ],
              ],
              const SizedBox(width: 4),
              _miniAction('✕', danger: true, onTap: () => _confirmCancel(e)),
            ],
          ),
        ],
      ),
    );
  }

  /// One icon-sized action — the [ParchmentButton] row this replaced cost a
  /// full extra line per trip and named actions ("Recall", "Dev") that read
  /// just as clearly as a symbol once several of these sit stacked.
  Widget _miniAction(
    String label, {
    VoidCallback? onTap,
    bool primary = false,
    bool danger = false,
  }) {
    final enabled = onTap != null;
    final ink = danger
        ? (enabled ? const Color(0xFF9B3B22) : kInkFaint)
        : parchmentButtonInk(active: primary && enabled);
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: parchmentButton(active: primary && enabled),
          child: Text(label, style: FoE.label(size: 11).copyWith(color: ink)),
        ),
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

  /// A string now, not a [Text] of its own (2026-09-11) — it shares a row
  /// with the trip's action icons, and that row owns the single [Text] that
  /// wraps it in `maxLines: 1` + ellipsis.
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

    final title = t.isHunt ? 'Hunt' : resourceName(spot!.resource);
    // Same state colour language as the Build Menu's own cards (user
    // 2026-09-12: "die Boxen sollen so gestaltet sein, wie die Boxen im
    // Baumenü") — a flat lawn green when you can act on it right now, a
    // faded parchment wash when you can't, ink flipping between near-white
    // and dimmed ink to stay readable on either. Replaces the old two-tone
    // cream→tan gradient, which never changed with the card's own state.
    final ink = blocked ? kParchmentInk.withValues(alpha: 0.55) : _kInkOnGreen;

    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTarget(t, busy: busy, empty: empty, full: full),
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
            decoration: ShapeDecoration(
              color: blocked ? kParchmentInk.withValues(alpha: 0.10) : kActionGreen,
              // The Build Menu's own hard-edged card shadow (blurRadius 0 —
              // it reads as a cast shadow, not a glow) — every card in the
              // grid now "lies on the paper" the same way.
              shadows: [
                BoxShadow(
                  color: kPageShadow.withValues(alpha: 0.24),
                  blurRadius: 0,
                  offset: const Offset(0, 3),
                ),
              ],
              // Radius 16, matching the Build Menu card — not the 22 this
              // used to borrow from CreatureCard.
              shape: FoE.facet(radius: 16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The "art" — no sprite to show, so the resource's own
                  // emoji stands in for it, big. Dimmed exactly like a
                  // blocked BuildingIcon (0.4 opacity) rather than the whole
                  // card, since an emoji is a baked-colour glyph immune to
                  // the ink swap around it.
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: blocked ? 0.4 : 1,
                          child: Text(
                            t.emoji,
                            style: const TextStyle(fontSize: 40),
                          ),
                        ),
                        // The stock — the one number worth reading at a glance,
                        // in [CreatureCard]'s own top-right power-badge spot.
                        if (spot != null)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Text(
                              stock.toStringAsFixed(0),
                              style: FoE.value(size: 14).copyWith(color: ink),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 12).copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (reason != null)
                    Text(
                      reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.dim(size: 9).copyWith(
                        color: ink.withValues(alpha: 0.85),
                      ),
                    )
                  else if (dials != null) ...[
                    RecessBar(
                      value: dials.spotCapacity <= 0
                          ? 0
                          : (stock / dials.spotCapacity).clamp(0.0, 1.0),
                      color: kParchmentGo,
                      height: 5,
                      onDark: !blocked,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '+${dials.regenPerHour.toStringAsFixed(0)}/h',
                      style: FoE.dim(size: 9).copyWith(
                        color: ink.withValues(alpha: 0.75),
                      ),
                    ),
                  ] else
                    Text(
                      'Caught by hand on return',
                      maxLines: 2,
                      style: FoE.dim(size: 9).copyWith(
                        color: ink.withValues(alpha: 0.75),
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

  /// Near-white on the green card — the Build Menu's own [_inkOnActive].
  static const _kInkOnGreen = Color(0xFFF3F7EF);

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
  ///
  /// An icon chip now, not a full [ParchmentButton] with its own "finish
  /// now" / "not enough gold" caption line (2026-09-11 compacting) — the
  /// dimmed opacity [_miniAction] already gives a disabled chip says
  /// "can't afford" clearly enough at this size.
  Widget _skipChip(Expedition e) {
    final cost = _ctrl.goldSkipCost(e);
    final canPay = _settlement.gold >= cost;
    return _miniAction(
      '🪙 $cost',
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
