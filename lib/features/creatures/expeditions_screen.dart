import '../settlement/data/resource_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_kit.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/recess_bar.dart';
import '../settlement/data/gather_defs.dart';
import '../settlement/settlement_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
    _ctrl.collectFinished(); // pull any already-due rewards forward
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
        if (_ctrl.noSlots) ...[
          _noSlotsBanner(),
          const SizedBox(height: 14),
        ],
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
        else
          for (final a in areas) _areaBlock(a),
      ],
    );
  }

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
  Widget _areaBlock(AreaDef area) {
    final busy = _busySpotIds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Row(
              children: [
                Text(area.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(
                  area.name,
                  style: FoE.title(size: 13).copyWith(color: kInk),
                ),
                const SizedBox(width: 8),
                // Danger keeps its own colour — it is the one thing on the
                // page that is a warning rather than a fact.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(color: dangerColor(area.dangerLevel).withValues(alpha: 0.18), shape: FoE.facet(radius: 5)),
                  child: Text(
                    'Danger ${area.dangerLevel}',
                    style: FoE.label(size: 9).copyWith(
                      color: dangerColor(area.dangerLevel),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final t in targetsIn(area))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _targetTile(t, busy: busy.contains(t.spot?.id)),
            ),
        ],
      ),
    );
  }

  Widget _targetTile(ExpeditionTarget t, {required bool busy}) {
    final spot = t.spot;
    final stock = spot == null ? 0.0 : _ctrl.availableStock(spot);
    final dials = spot == null ? null : gatherDefFor(spot.resource);
    final full = _ctrl.slotsFull;
    // A depleted spot is shown, not hidden: it regrows, and knowing WHICH rock
    // is empty is what makes the regen rate meaningful.
    final empty = spot != null && stock < 1;
    final blocked = full || busy || empty;
    // WHY it is blocked, on the tile. It used to take a tap to find out, which
    // meant tapping every dead tile in turn to learn the same thing.
    final reason = busy
        ? 'A group is working this spot'
        : empty
            ? 'Mined out — it regrows'
            : full
                ? (_ctrl.noSlots ? 'Needs a Scout Post' : 'Every slot is busy')
                : null;

    return ParchmentCard(
      padding: const EdgeInsets.all(11),
      muted: blocked,
      onTap: () => _openTarget(t, busy: busy, empty: empty, full: full),
      child: Row(
        children: [
          Text(t.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.isHunt ? 'Hunt for monsters' : 'Gather ${t.label}',
                  style: FoE.value(size: 13).copyWith(color: kInk),
                ),
                const SizedBox(height: 3),
                if (reason != null)
                  Text(
                    reason,
                    style: FoE.dim(size: 10).copyWith(
                      color: empty ? const Color(0xFF9B3B22) : kInkFaint,
                    ),
                  )
                else if (spot != null) ...[
                  Text(
                    '${stock.toStringAsFixed(0)} / '
                    '${dials!.spotCapacity.toStringAsFixed(0)} left · '
                    '+${dials.regenPerHour.toStringAsFixed(0)}/h',
                    style: FoE.dim(size: 10).copyWith(color: kInkFaint),
                  ),
                  const SizedBox(height: 5),
                  RecessBar(
                    value: dials.spotCapacity <= 0
                        ? 0
                        : (stock / dials.spotCapacity).clamp(0.0, 1.0),
                    color: kParchmentGo,
                    height: 5,
                  ),
                ] else
                  Text(
                    'Finds are caught by hand when the group returns',
                    style: FoE.dim(size: 10).copyWith(color: kInkFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: blocked ? kInkFaint : kAccent,
          ),
        ],
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
