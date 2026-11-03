import '../settlement/data/resource_icons.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/strategy_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_kit.dart' show parchmentConfirm;
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../settlement/resources_screen.dart' show romanNumeral;
import '../settlement/settlement_controller.dart';
import 'capture_encounter_screen.dart';
import 'expedition_launch_sheet.dart';
import 'models/area.dart';
import 'models/creature_enums.dart' show maxHuntOptionCount;
import 'models/expedition.dart';
import 'services/capture_math.dart' show kCaptureHuntOptions;
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import 'services/expedition_targets.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/voxel_kit.dart' show vr;

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
    title: 'Expedition',
    // No slot chip up here any more (user 2026-09-29: "Icon oben rechts
    // neben dem 'x' und n/n löschen") — the same reading now lives on the
    // "Expeditions" card itself, the one thing it is actually about.
    child: ExpeditionsBody(),
  );
}

/// What is out, and everywhere you could send a group — one page, never a
/// scrollbar ("Variante 10" of ten proposals, user 2026-09-29): a narrow "out
/// now" column, then every unlocked region's own row of resources — always
/// the era's fixed 3, since that is how many every era actually has — scaled
/// down AS A WHOLE to fit however many regions are open, the same technique
/// the Breeding page's gene table and the victory screen use. Hunt sits in
/// its own panel beside it, because it isn't a 4th resource: it is its OWN
/// system, 6 fixed DURATIONS (user 2026-09-29: "Hunt ist losgelöst von den
/// Äras … mit der 3er Spalte lösbar") gated by the Scout Post's level, not by
/// which era happens to be open. A region chip there only picks which
/// species pool a hunt draws from.
class ExpeditionsBody extends StatefulWidget {
  const ExpeditionsBody({super.key});

  @override
  State<ExpeditionsBody> createState() => _ExpeditionsBodyState();
}

class _ExpeditionsBodyState extends State<ExpeditionsBody> {
  final _ctrl = ExpeditionController();
  final _settlement = SettlementController();
  Timer? _ticker;

  /// Which region's species pool the Hunt panel draws from — null until the
  /// player picks one, which reads as "the first unlocked region".
  String? _huntAreaId;

  /// The composer's own type choice (user 2026-10-02, "Konzept 24" of the
  /// full-hub redesign: creating an expedition is the screen's whole job
  /// now, not something a separate tile grid hands off to a sheet). Null
  /// means "not decided yet" — [_composerKindOrDefault] then falls back to
  /// whichever the settlement can actually do (gather if anything is
  /// unlocked, since that's the everyday trip; hunt otherwise, which is
  /// also what a brand-new tutorial account needs before it has ever built
  /// a gathering hut).
  ExpeditionTargetKind? _composerKind;

  /// Composer, gather only: which chip is selected, by [ExpeditionTarget.id]
  /// — re-resolved against the live target list every build rather than
  /// cached as an [ExpeditionTarget] itself, so a spot that empties out or
  /// starts being worked by another trip is never silently kept selected.
  String? _composerGatherTargetId;

  /// Composer, hunt only: which [kCaptureHuntOptions] variant is selected.
  int _composerHuntOptionIndex = 0;

  /// True for the whole of firstCapture — it covers BOTH halves of this step:
  /// picking the shortest hunt (500 steps), then speeding up the hunt that
  /// comes out of it with gold (user 2026-10-01: "bitte die 10min Hunt
  /// highlighten, damit ich nur diese anwählen kann. Im Anschluss soll diese
  /// wieder mit Gold beschleunigt werden" — the hunt itself moved from a
  /// 10-minute timer to 500 real steps on 2026-10-02, but the two-phase
  /// script is unchanged: gold is still how the tutorial gets through it).
  bool get _huntTutorial => _settlement.introStep == IntroStep.firstCapture;

  /// The hunt THIS step's own script put out, once it exists — null before
  /// the player has picked a duration. Only ever one: [maxHuntOptionCount]
  /// caps this account at a single Scout-Post-free slot this early.
  Expedition? get _tutorialHunt => _huntTutorial
      ? _ctrl.expeditions
            .where((e) => e.type == ExpeditionType.capture)
            .firstOrNull
      : null;

  // ── Tile art ──────────────────────────────────────────────
  // "Bild-Kachel" (user 2026-09-30: "Sie wirken zu leer und langweilig" —
  // VC, the chosen one of six proposals for the Hunt/Resources/Expedition
  // tiles). Every tile used to be one flat cream block with an emoji
  // floating on it; now each gets its own coloured ART ZONE — a little
  // painted "place" the glyph actually stands in — over the same cream BAND
  // the rest of the app's tiles use for their text, so it still reads as
  // this game rather than a random photo card.
  //
  // A fixed, hand-picked palette rather than one colour per resource: the
  // roster (wood/stone/fish plus whatever Dev Mode's goods add) is open-
  // ended, so a resource's colour is looked up by hashing its key into this
  // list instead of naming every one — stable across a session, no upkeep
  // as the roster grows.
  static const List<List<Color>> _kArtGradients = [
    [Color(0xFF8AA85E), Color(0xFF3A4E26)], // moss
    [Color(0xFF7E8FA6), Color(0xFF384252)], // slate
    [Color(0xFF3C8CA8), Color(0xFF1B4E63)], // teal
    [Color(0xFFC97B4A), Color(0xFF6E3E22)], // clay
    [Color(0xFFB85C6B), Color(0xFF5C2530)], // berry
    [Color(0xFF9CAA55), Color(0xFF4B5729)], // olive
    [Color(0xFFD9A441), Color(0xFF7A5218)], // amber
  ];

  /// Hunt isn't a resource — it gets its own fixed colour (a "danger/wild"
  /// violet) rather than a hashed one, so every hunt tile reads as the same
  /// system at a glance the way the resource tiles read as an era.
  static const List<Color> _kHuntGradient = [
    Color(0xFF6B4394),
    Color(0xFF33204F),
  ];

  List<Color> _artFor(String key) =>
      _kArtGradients[key.hashCode.abs() % _kArtGradients.length];

  LinearGradient _artGradient(List<Color> stops) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: stops,
  );

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
    final tutorialHunt = _tutorialHunt;
    return Stack(
      children: [
        _layout(running, areas),
        // firstCapture, phase 1: the Trips explainer and the spotlight on the
        // 10-minute hunt tile now show TOGETHER (user 2026-10-01: "soll der
        // Text Trips gleichzeitig wie das gehighlightete Huntbutton
        // erscheinen, d.h. tap anywhere to continue ist nicht mehr nötig") —
        // this used to be a blocking "tap anywhere to continue" card the
        // player had to dismiss FIRST, with the spotlight only appearing
        // after. Nothing else on this screen is reachable until the hunt
        // tile is picked (user 2026-10-01: "damit ich nur diese anwählen
        // kann").
        if (_huntTutorial && tutorialHunt == null) ...[
          const IntroSpotlightOverlay(
            anchorName: 'hunt-10min-option',
            hint: 'Tap to send a hunt.',
          ),
          _tripsNarrationCard(),
        ],
        // Phase 2: the hunt is out — the one thing left to teach is that gold
        // speeds it up too, same as it did for the Healing Hut (user
        // 2026-10-01: "im Anschluss soll diese wieder mit Gold beschleunigt
        // werden").
        if (tutorialHunt != null &&
            !tutorialHunt.isReadyToCollect(DateTime.now()))
          const IntroSpotlightOverlay(
            anchorName: 'hunt-skip-gold',
            hint: 'Gold speeds this up too.',
          ),
      ],
    );
  }

  // Out now only shows up once something IS out (user 2026-10-02, "Konzept
  // 24" of ten full-hub proposals: creating an expedition is the screen's
  // whole job now, not a tile grid beside a monitoring column). With nothing
  // running, [_composer] gets the entire card; the moment a trip starts, a
  // slim rail slides in beside it. (MenuScaffold itself is the one card now
  // — no [pageCard] here any more, or this would nest a card inside its
  // card.)
  Widget _layout(List<Expedition> running, List<AreaDef> areas) {
    if (areas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          'No region is open yet — win your first battles.',
          style: TextStyle(color: kBoxInkSoft, fontSize: 12),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // WHY NOTHING CAN GO, before the composer (user 2026-07-29: the base
        // pool is 0, so a settlement with no Scout Post has an empty screen
        // and no idea it is missing a building).
        if (_ctrl.noSlots) ...[_noSlotsBanner(), const SizedBox(height: 10)],
        Expanded(
          child: running.isEmpty
              ? _composer(areas)
              // The rail's width is a FRACTION of what's actually available
              // (same reasoning as the old "out now" column's). Floored at
              // 200 rather than the old 190 (2026-10-02 regression, caught by
              // a widget test): a trip card's own skip/cancel chip row
              // overflowed a narrower rail — it's secondary to the composer
              // now, but still has to fit its own content.
              : LayoutBuilder(
                  builder: (context, c) {
                    final railWidth = (c.maxWidth * 0.22).clamp(200.0, 230.0);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _composer(areas)),
                        const SizedBox(width: 14),
                        SizedBox(
                          width: railWidth,
                          child: zoneBox(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                sectionLabel(
                                  'Out now',
                                  trailing: Text(
                                    '${_ctrl.activeCount}/${_ctrl.maxSlots}',
                                    style: const TextStyle(
                                      color: kBoxInk,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(child: _outNowColumn(running)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
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

  /// Gather targets only — every area contributes exactly one Hunt entry too
  /// (see [targetsIn]), but that's picked through [_huntPickerSection]
  /// instead.
  List<ExpeditionTarget> _gatherTargets(AreaDef a) => targetsIn(
    a,
    unlockedResources: _unlockedResources,
  ).where((t) => !t.isHunt).toList();

  // ── The rail: what's out ──────────────────────────────────
  // Only ever built once [running] is non-empty — see [_layout].
  Widget _outNowColumn(List<Expedition> running) => ListView.separated(
    padding: const EdgeInsets.only(bottom: 4),
    itemCount: running.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, i) => _tripCard(running[i]),
  );

  // ── The composer: "New Expedition" ───────────────────────
  // Picking a kind and a target used to live in a tile grid that handed off
  // to a sheet ([showExpeditionLaunchSheet]); now the composer picks the
  // target itself and renders the SAME [ExpeditionLaunchPanel] right here,
  // inline (user 2026-10-02, "Konzept 24"). [_layout] decides how much
  // screen this gets.

  /// Every gather target across every unlocked area, flattened — the
  /// composer doesn't group by era the way the old Resources column did;
  /// "I'm gathering wood" doesn't need to know which region it's gathered in
  /// first.
  List<ExpeditionTarget> _allGatherTargets(List<AreaDef> areas) => [
    for (final a in areas) ..._gatherTargets(a),
  ];

  /// [_composerKind] if the player has chosen one; otherwise whichever kind
  /// the settlement can actually do — gather (the everyday trip) if anything
  /// is unlocked, hunt otherwise. A brand-new tutorial account has usually
  /// built nothing that produces a resource yet, so this already lands on
  /// Hunt for it with no extra gating needed for the firstCapture spotlight
  /// below.
  ExpeditionTargetKind _composerKindOrDefault(
    List<ExpeditionTarget> gatherTargets,
  ) =>
      _composerKind ??
      (gatherTargets.isEmpty
          ? ExpeditionTargetKind.hunt
          : ExpeditionTargetKind.gather);

  /// The selected chip, re-resolved every build rather than cached as an
  /// [ExpeditionTarget] — a spot that empties out or starts being worked by
  /// another trip must never stay silently selected. Prefers one that's
  /// actually sendable so the composer never opens on a target it would
  /// immediately have to explain is blocked.
  ExpeditionTarget? _currentGatherTarget(List<ExpeditionTarget> gatherTargets) {
    if (gatherTargets.isEmpty) return null;
    final id = _composerGatherTargetId;
    if (id != null) {
      for (final t in gatherTargets) {
        if (t.id == id) return t;
      }
    }
    for (final t in gatherTargets) {
      if (!_busySpotIds.contains(t.spot?.id) &&
          _ctrl.availableStock(t.spot!) >= 1) {
        return t;
      }
    }
    return gatherTargets.first;
  }

  AreaDef _resolvedHuntArea(List<AreaDef> areas) =>
      areas.firstWhere((a) => a.id == _huntAreaId, orElse: () => areas.first);

  Widget _composer(List<AreaDef> areas) {
    final gatherTargets = _allGatherTargets(areas);
    final kind = _composerKindOrDefault(gatherTargets);
    final showTypeSwitch = gatherTargets.isNotEmpty;
    final target = kind == ExpeditionTargetKind.gather
        ? _currentGatherTarget(gatherTargets)
        : ExpeditionTarget(
            kind: ExpeditionTargetKind.hunt,
            area: _resolvedHuntArea(areas),
          );
    return zoneBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionLabel('New Expedition'),
          const SizedBox(height: 10),
          if (showTypeSwitch) ...[
            _typeSwitch(kind),
            const SizedBox(height: 10),
          ],
          kind == ExpeditionTargetKind.gather
              ? _gatherChipsRow(gatherTargets, selectedId: target?.id)
              : _huntPickerSection(areas),
          const SizedBox(height: 12),
          // The SAME panel every target tile used to open as a sheet — see
          // that widget's own doc comment. Keyed on the target + variant so
          // picking a different chip gets a fresh group/send state instead
          // of carrying over a selection made for a different trip.
          Expanded(
            child: target == null
                ? Center(
                    child: Text(
                      'Nothing to send yet.',
                      style: TextStyle(color: kBoxInkSoft, fontSize: 12),
                    ),
                  )
                : ExpeditionLaunchPanel(
                    key: ValueKey(
                      '${target.id}_'
                      '${kind == ExpeditionTargetKind.hunt ? _composerHuntOptionIndex : 0}',
                    ),
                    target: target,
                    initialOptionIndex: kind == ExpeditionTargetKind.hunt
                        ? _composerHuntOptionIndex
                        : null,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _typeSwitch(ExpeditionTargetKind kind) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: kBoxInk.withValues(alpha: 0.07),
      borderRadius: vr(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: _typeSwitchOption(
            '⛏️ Gather',
            active: kind == ExpeditionTargetKind.gather,
            onTap: () =>
                setState(() => _composerKind = ExpeditionTargetKind.gather),
          ),
        ),
        Expanded(
          child: _typeSwitchOption(
            '🪤 Hunt',
            active: kind == ExpeditionTargetKind.hunt,
            onTap: () =>
                setState(() => _composerKind = ExpeditionTargetKind.hunt),
          ),
        ),
      ],
    ),
  );

  Widget _typeSwitchOption(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? Strategy.gold : Colors.transparent,
        borderRadius: vr(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: active ? kBoxInk : kBoxInkFaint,
        ),
      ),
    ),
  );

  Widget _gatherChipsRow(
    List<ExpeditionTarget> targets, {
    required String? selectedId,
  }) => SizedBox(
    height: 70,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: targets.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) =>
          _gatherChip(targets[i], selected: targets[i].id == selectedId),
    ),
  );

  /// One resource, as a chip rather than a full tile — the composer's job is
  /// picking WHICH target, not explaining it at length; [ExpeditionLaunchPanel]
  /// below already shows the haul/carry/duration figures once one is chosen.
  Widget _gatherChip(ExpeditionTarget t, {required bool selected}) {
    final spot = t.spot!;
    final stock = _ctrl.availableStock(spot);
    final busy = _busySpotIds.contains(spot.id);
    final empty = stock < 1;
    final blocked = busy || empty;
    final reason = busy
        ? 'Working'
        : empty
        ? 'Mined out'
        : null;
    final ink = blocked ? kBoxInkFaint : kBoxInk;
    return Pressable(
      onTap: blocked
          ? null
          : () => setState(() {
              _composerKind = ExpeditionTargetKind.gather;
              _composerGatherTargetId = t.id;
            }),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: raisedTile(
          radius: 10,
          locked: blocked,
          lit: selected && !blocked,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 3),
            Text(
              resourceName(spot.resource),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text(
              reason ?? '${stock.toStringAsFixed(0)} left',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
                color: kBoxInkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// HUNT — its own system (user 2026-09-29): a region chip row (which
  /// species pool) over a scrolling row of the 5 step-count variants
  /// ([kCaptureHuntOptions]), locked past however many the Scout Post has
  /// opened. Picking a chip feeds [ExpeditionLaunchPanel] below with that
  /// variant already chosen — the team is still picked there, same as
  /// before.
  Widget _huntPickerSection(List<AreaDef> areas) {
    final area = _resolvedHuntArea(areas);
    final unlocked = maxHuntOptionCount(
      _settlement.buildingHuntOptions + _settlement.pathHuntOptions,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (areas.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final a in areas)
                  _huntAreaChip(a, active: a.id == area.id),
              ],
            ),
          ),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kCaptureHuntOptions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _huntDurationChip(
              i,
              locked: i >= unlocked,
              // The tutorial's own lit control (user 2026-10-01) — only the
              // shortest variant ever carries it, and only until the hunt it
              // starts actually exists.
              spotlight: i == 0 && _huntTutorial && _tutorialHunt == null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _huntAreaChip(AreaDef a, {required bool active}) => Pressable(
    onTap: () => setState(() => _huntAreaId = a.id),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: raisedTile(radius: 8, locked: !active),
      child: Text(
        '${a.emoji} Level ${romanNumeral(a.order)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: active ? kBoxInk : kBoxInkFaint,
        ),
      ),
    ),
  );

  Widget _huntDurationChip(
    int i, {
    required bool locked,
    bool spotlight = false,
  }) {
    final option = kCaptureHuntOptions[i];
    final selected = _composerHuntOptionIndex == i;
    final ink = locked ? kBoxInkFaint : kBoxInk;
    return GestureDetector(
      key: spotlight ? IntroSpotlightAnchors.of('hunt-10min-option') : null,
      behavior: HitTestBehavior.opaque,
      onTap: locked
          ? null
          : () => setState(() {
              _composerKind = ExpeditionTargetKind.hunt;
              _composerHuntOptionIndex = i;
            }),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: raisedTile(
          radius: 10,
          locked: locked,
          lit: selected && !locked,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(locked ? '🔒' : '🪤', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 3),
            Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            Text(
              locked
                  ? 'Locked'
                  : '${option.finds} find${option.finds > 1 ? 's' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Narration alongside the spotlighted shortest-hunt tile, not a blocking
  /// modal of its own any more (user 2026-10-01: "soll der Text Trips
  /// gleichzeitig wie das gehighlightete Huntbutton erscheinen, d.h. tap
  /// anywhere to continue ist nicht mehr nötig") — the player's one action
  /// here is tapping that tile, so a SECOND tap just to dismiss this first
  /// was a step the tutorial never needed. [IgnorePointer] lets that tap (and
  /// everything the spotlight scrim already blocks) pass straight through;
  /// pinned to the top-LEFT, narrower than the old centred 360px card, so it
  /// never sits over the Hunt panel docked at the screen's own right edge.
  Widget _tripsNarrationCard() => Positioned(
    top: 8,
    left: 8,
    child: IgnorePointer(
      child: SizedBox(
        width: 340,
        child: creamCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trips',
                style: FoE.title(size: 15).copyWith(color: kBoxInk),
              ),
              const SizedBox(height: 6),
              Text(
                'Send monsters out to gather resources or hunt a wild one. '
                'A spot you empty out regenerates over time, so it is worth '
                'a return trip later.',
                style: FoE.label(size: 12).copyWith(color: kBoxInk),
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
    // Same art zone the targets use, coloured by what is actually out there —
    // the resource being gathered, or the hunt violet.
    final art = e.type == ExpeditionType.gather
        ? _artFor((e.payload['resource'] as String?) ?? e.type.name)
        : _kHuntGradient;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      // A raised tile on the card; READY earns the gold rim.
      decoration: raisedTile(lit: ready),
      // IntrinsicHeight (2026-09-30 fix): this card sits in a ListView now
      // (`_outNowColumn`, since the 2026-09-18 landscape pass replaced a
      // fixed-size carousel with a plain scrolling column), which hands the
      // Row an UNBOUNDED height — `stretch` then tries to pass that
      // infinity straight down to its children ("BoxConstraints forces an
      // infinite height", crashed live for a user with an expedition
      // actually out; a QA pass with an empty `running` list never hit this
      // branch). IntrinsicHeight gives the Row a real, finite height to
      // stretch to instead, sized off its own content.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: _artGradient(art)),
              // The timer's own ring reads its colours (ink track, gold/cyan
              // fill) against CREAM — a cream medallion behind it keeps that
              // contrast on top of whatever the art zone's colour is, rather
              // than recolouring the dial itself.
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.rectangle,
                  color: CreamPalette.tileTop,
                ),
                child: RadialTimer(
                  value: e.progress(now),
                  emoji: e.type.emoji,
                  ready: ready,
                  size: 40,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
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
                      text: ready
                          ? 'READY'
                          : e.isStepGated
                          ? '${e.stepsWalked}/${e.stepsTarget} Schritte'
                          : fmtTripDuration(e.remaining(now)),
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
                          // The tutorial's own second lit control, once this
                          // IS that hunt (user 2026-10-01) — see
                          // [_tutorialHunt]'s own doc comment.
                          _tutorialHunt?.id == e.id
                              ? KeyedSubtree(
                                  key: IntroSpotlightAnchors.of(
                                    'hunt-skip-gold',
                                  ),
                                  child: _skipChip(e),
                                )
                              : _skipChip(e),
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
            ),
          ],
        ),
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
