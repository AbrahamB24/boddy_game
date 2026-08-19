import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/resource_icons.dart';
import '../../core/ui/feel_button.dart';
import '../../core/orientation_lock.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/number_format.dart';
import '../../core/ui/duration_format.dart';
import 'data/building_definitions.dart';
import 'data/era_definitions.dart';
import 'data/goods_definitions.dart';
import 'dev/dev_mode_screen.dart';
import 'services/daily_tasks.dart';
import 'services/game_engine.dart';
import 'services/step_tracker_service.dart';
import 'settlement_controller.dart';
import 'build_menu_screen.dart';
import 'sheets/energy_sheet.dart';
import 'bag_screen.dart';
import 'sheets/resource_breakdown_sheet.dart';
import 'widgets/meander_strip.dart';
import 'widgets/quick_pad.dart';
import 'widgets/scroll_paper.dart';
import 'widgets/settlement_map.dart';
import '../common/events/game_events.dart';
import '../common/widgets/parchment_page.dart';
import '../common/events/notification_button.dart';
import '../creatures/battle_screen.dart';
import '../creatures/collection_screen.dart';
import 'management_screen.dart';
import '../creatures/expeditions_screen.dart';
import '../creatures/models/combatant.dart';
import '../creatures/models/creature_enums.dart' show kHealingHutBuildingId;
import '../creatures/models/species_def.dart';
import '../creatures/overworld_screen.dart';
import '../creatures/services/combat_engine.dart';
import '../creatures/services/creatures_controller.dart';
import '../onboarding/intro_card_panel.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../common/widgets/recess_bar.dart';

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with OrientationLock<SettlementScreen>, WidgetsBindingObserver {
  final _ctrl = SettlementController();
  // Lets the tutorial's CTAs open a building's dialog directly (heal step,
  // assign step) instead of asking a brand-new player to find it on the map.
  final _mapKey = GlobalKey<SettlementMapState>();
  String? _pendingTypeId;
  bool _editMode = false;

  bool _roadMode = false;

  // PORTRAIT. This screen used to force landscape, which is flatly at odds
  // with everything else: the phone frame, the header, the sheets and the
  // quick menu are all built for a 430-wide portrait viewport, and a player
  // would have had the device flip under them on the home screen alone.
  // The map itself doesn't need the width — it lives in an InteractiveViewer,
  // so it pans and zooms.
  @override
  List<DeviceOrientation> get lockedOrientations => const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_rebuild);
    _ctrl.load();
    // Real step counter: watches the hardware sensor and credits steps as
    // energy automatically (user 2026-07-18).
    StepTrackerService().start();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_rebuild);
    _ctrl.stopTicker();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-subscribing on resume forces a fresh cumulative reading, so steps
    // walked while the app was backgrounded credit immediately (the hardware
    // counter keeps counting on its own).
    if (state == AppLifecycleState.resumed) {
      StepTrackerService().start();
    }
  }

  void _rebuild() => setState(() {});

  // ── Navigation ────────────────────────────────────────────
  void _showExpeditions() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ExpeditionsScreen()),
  );

  void _showCreatures() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CollectionScreen()),
  );

  void _showManagement({int initialTab = 0}) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ManagementScreen(initialTab: initialTab)),
  );

  // Overworld — the front door to expeditions (gather/capture/battle). Battle
  // routes into the existing dungeon run per area; the quick-menu button is
  // the interim entrance until a placeable map/portal building exists.
  void _showOverworld() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const OverworldScreen()),
  );

  void _showDevMode() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const DevModeScreen()),
  );

  /// Opens Build and applies whatever the player picked.
  ///
  /// A POPUP over the map (user 2026-07-20), not a page: building is something
  /// you do TO the map, so the map has to stay visible behind the menu. It
  /// returns a choice rather than firing callbacks: each one puts the MAP into
  /// a mode, so the menu's job ends the moment it closes — and the modes are
  /// mutually exclusive, which a set of independent callbacks left it possible
  /// to get wrong.
  Future<void> _showBuildMenu() async {
    // No nav destinations to hand it any more (user 2026-07-29): the menu used
    // to carry a copy of the nav bar so you could jump straight from it to
    // Map/Monsters/Manage. With the bar gone everywhere, the menu closes and
    // the corner pad is right there.
    final choice = await showBuildMenu(context, _ctrl);
    if (!mounted) return;
    if (choice == null) return; // backed out
    switch (choice) {
      case BuildPlace(:final typeId):
        await _buildAndPlace(typeId);
      case BuildRoads():
        _enterRoadMode();
    }
  }

  /// Hands the building to the MAP to be aimed (user 2026-08-09: "Wenn ich ein
  /// Gebäude ausgewählt habe, dann erscheint es mittig im Screen … Über dem
  /// Gebäude gibt es ein gutzeichen und ein X").
  ///
  /// It is not bought here and it is not placed here. The map opens it in the
  /// middle of the view as a ghost, and its ✓ is the single point where the
  /// resources are spent — so backing out of a placement costs nothing.
  ///
  /// The two previous designs each got half of this right: aiming first asked
  /// for the spot while the thing being placed was an outline under your thumb,
  /// and auto-placing bought the building the moment you tapped its card. The
  /// ghost is the outline AND the decision, which is why one flow can now cover
  /// ordinary buildings, plots and roads alike.
  Future<void> _buildAndPlace(String typeId) async {
    if (kBuildingDefs[typeId] == null) return;
    setState(() {
      _pendingTypeId = typeId;
      _editMode = false;
      _roadMode = false;
    });
  }

  /// Long-pressing a building on the map drops straight into move mode (user
  /// 2026-07-20) — and STAYS there after the drop, so several buildings can be
  /// rearranged in one go. It replaced the menu's Move button entirely.
  void _enterEditMode() => setState(() {
    _editMode = true;
    _roadMode = false;
    _pendingTypeId = null;
  });

  void _enterRoadMode() => setState(() {
    _roadMode = true;
    _editMode = false;
    _pendingTypeId = null;
  });

  void _showEnergyOverview() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EnergySheet(ctrl: _ctrl),
  );

  void _showResourceBreakdown({
    required String emoji,
    required String title,
    required double total,
    required String unit,
    required List<ProductionSource> sources,
    double? stored,
    double? capacity,
    List<ProductionSource> capacitySources = const [],
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ResourceBreakdownSheet(
      emoji: emoji,
      title: title,
      total: total,
      unit: unit,
      sources: sources,
      stored: stored,
      capacity: capacity,
      capacitySources: capacitySources,
    ),
  );

  /// Whether the bar is unfolded to show every era's resources.
  bool _erasOpen = false;

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Welcome-back digest: queued by load() when the player was away a while;
    // shown exactly once, after this frame so the sheet has a laid-out screen
    // under it.
    final digest = _ctrl.pendingDigest;
    if (digest != null && !_ctrl.isLoading) {
      _ctrl.pendingDigest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDigest(digest);
      });
    }
    return Scaffold(
      // The map fills this itself; the colour only shows while it loads and
      // behind the edges, so it is the page tone like everywhere else.
      backgroundColor: kParchmentMid,
      body: _ctrl.isLoading
          ? _loading()
          : _ctrl.error != null
          ? _error()
          : _layout(),
    );
  }

  /// "While you were away" — the passive economy, experienced instead of
  /// silently accrued (user 2026-07-21).
  ///
  /// A CENTRED PARCHMENT BOX in the build menu's style (user 2026-07-27), no
  /// longer a dark sheet crawling up from the bottom edge: this is the first
  /// thing you see on opening the game, and it belongs on the same paper as the
  /// rest of the settlement's UI.
  ///
  /// It also reports WHAT HAPPENED, not just what was gathered (user
  /// 2026-07-27). The resources were only half the story — expeditions
  /// resolving, eggs hatching, monsters levelling up and casualties all landed
  /// silently in the bell, and the digest just said "N new events" and left you
  /// to go looking.
  void _showDigest(WelcomeDigest d) {
    final hours = d.awayHours;
    final awayLabel = hours >= 48
        ? '${(hours / 24).toStringAsFixed(1)} days'
        : hours >= 1.5
        ? '${hours.toStringAsFixed(1)} hours'
        : '${(hours * 60).round()} minutes';
    // EVERYTHING THE BELL WOULD SHOW YOU (user 2026-07-27: "alles was bei den
    // notifications angezeigt wird, soll auch beim while you were away screen
    // sein") — the unread feed, whole and uncut.
    //
    // Two things were wrong before. It cut the list at eight and pointed at the
    // bell for the rest, so the screen whose entire job is "here is what
    // happened" sent you somewhere else to finish reading it. And it selected
    // by TIME WINDOW — events newer than the away period — which quietly
    // dropped anything still unread from an earlier session: the bell counted
    // it, this never mentioned it.
    //
    // Reading the same [GameEventLog.unreadEvents] the badge counts makes the
    // two incapable of disagreeing.
    final log = GameEventLog();
    final events = log.unreadEvents;

    const ink = kParchmentInk;
    final inkSoft = kParchmentInk.withValues(alpha: 0.78);
    final inkFaint = kParchmentInk.withValues(alpha: 0.55);
    final ornament = kParchmentInk.withValues(alpha: 0.22);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
            child: Material(
              color: Colors.transparent,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: kParchmentMid,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // The build menu's own bands, as wallpaper.
                    Positioned(
                      left: 4,
                      top: 0,
                      bottom: 0,
                      width: 14,
                      child: MeanderStrip(color: ornament),
                    ),
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      width: 14,
                      child: MeanderStrip(color: ornament, flip: true),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(30, 18, 30, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // No moon (user 2026-07-27).
                          Text(
                            'While you were away',
                            style: FoE.title(size: 16).copyWith(color: ink),
                          ),
                          Text(
                            awayLabel,
                            style: FoE.dim(size: 11).copyWith(color: inkFaint),
                          ),
                          const SizedBox(height: 14),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _digestHeading('Gathered', ink),
                                  const SizedBox(height: 6),
                                  if (d.gained.isEmpty)
                                    Text(
                                      'Nothing came in — station monsters in '
                                      'your buildings so the settlement works '
                                      'while you are gone.',
                                      style: FoE.dim(
                                        size: 12,
                                      ).copyWith(color: inkSoft),
                                    )
                                  else
                                    Wrap(
                                      spacing: 14,
                                      runSpacing: 8,
                                      children: [
                                        for (final e in d.gained.entries)
                                          Text(
                                            '${resourceEmoji(e.key)} '
                                            '+${e.value.toStringAsFixed(0)}',
                                            style: FoE.value(
                                              size: 15,
                                            ).copyWith(color: ink),
                                          ),
                                      ],
                                    ),
                                  const SizedBox(height: 16),
                                  _digestHeading('What happened', ink),
                                  const SizedBox(height: 6),
                                  if (events.isEmpty)
                                    Text(
                                      'Nothing else to report.',
                                      style: FoE.dim(
                                        size: 12,
                                      ).copyWith(color: inkSoft),
                                    )
                                  else
                                    // ALL of them. The box already scrolls
                                    // (Flexible + SingleChildScrollView), so a
                                    // long night away is a scroll, not a
                                    // truncation and a redirect.
                                    for (final e in events)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.kind.emoji,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                e.message,
                                                style: FoE.label(
                                                  size: 12,
                                                ).copyWith(color: inkSoft),
                                              ),
                                            ),
                                            // WHEN, as the bell prints it —
                                            // part of what the notifications
                                            // show, and the only way to tell an
                                            // expedition that landed an hour
                                            // ago from one that landed as you
                                            // opened the game.
                                            const SizedBox(width: 8),
                                            Text(
                                              _digestAgo(e.at),
                                              style: FoE.dim(
                                                size: 10,
                                              ).copyWith(color: inkFaint),
                                            ),
                                          ],
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            // Dismissing MARKS THEM READ. This screen has just
                            // shown the same set the bell would, so leaving the
                            // badge nagging about it would send the player to
                            // read a second time what they have already read
                            // once (user 2026-07-27).
                            onTap: () {
                              log.markAllRead();
                              Navigator.pop(ctx);
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              alignment: Alignment.center,
                              decoration: parchmentButton(),
                              child: Text(
                                'Continue',
                                style: FoE.label(
                                  size: 13,
                                ).copyWith(color: parchmentButtonInk()),
                              ),
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
      ),
    );
  }

  /// How long ago, the bell's own wording — the two lists print the same event
  /// the same way.
  static String _digestAgo(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Widget _digestHeading(String label, Color ink) => Text(
    label.toUpperCase(),
    style: FoE.label(
      size: 10,
    ).copyWith(color: ink.withValues(alpha: 0.6), letterSpacing: 1),
  );

  Widget _loading() =>
      Center(child: CircularProgressIndicator(color: FoE.gold));

  Widget _error() => Center(
    child: Text(_ctrl.error!, style: const TextStyle(color: Colors.redAccent)),
  );

  Widget _layout() => Stack(
    children: [
      Positioned.fill(
        child: SettlementMap(
          key: _mapKey,
          ctrl: _ctrl,
          pendingTypeId: _pendingTypeId,
          editMode: _editMode,
          roadMode: _roadMode,
          onPlacementDone: () => setState(() => _pendingTypeId = null),
          onEnterEditMode: _enterEditMode,
          onExitEditMode: () => setState(() => _editMode = false),
          onExitRoadMode: () => setState(() => _roadMode = false),
          onOpenBuildMenu: _showBuildMenu,
        ),
      ),
      // Stacked rather than each Positioned at a guessed offset: the top bar's
      // height now depends on the device's safe area, so a hardcoded `top: 50`
      // for the debug row would sit under it on a notched phone.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _topBar(),
            // Under the bar, not on it: the dev tools on the left, and on the
            // right the bell — AN ICON, not one of the pad's keys (user
            // 2026-07-29: "News ist kein Button sondern nur ein Icon oben
            // rechts unter dem header"). It is a thing that HAPPENED, not a
            // place you go, so it does not belong among the destinations.
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _debugRow()),
                  if (_ctrl.saveFailed) _syncWarning(),
                  // Mute in ONE tap from wherever you are (user 2026-07-30, with
                  // the sound); long-press for the vibration switch too.
                  const FeelButton(),
                  const NotificationButton(),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
      // One bottom stack instead of three things fighting for the corner: at
      // phone width (430) a bottom-left card and a bottom-right menu simply
      // overlap. Stacking them also keeps everything inside thumb reach.
      // Full-bleed: the quick menu is a bar fixed to the bottom edge now, so
      // the stack owns the whole width and the cards indent themselves.
      Positioned(left: 0, right: 0, bottom: 0, child: _bottomStack()),
      // Guided tutorial: dim and dead-zone everything except the intro card
      // — its CTA is the one lit path forward, its ✕ still offers the exit.
      // Off during placement (the map is the target then) and map modes.
      if (_ctrl.introStep.isActive && !_mapModeActive && _pendingTypeId == null)
        const IntroSpotlightOverlay(anchorName: 'intro-panel'),
    ],
  );

  /// True while the map owns the bottom of the screen: aiming, road building
  /// and move/edit mode each show their own banner down there (with the button
  /// that LEAVES the mode), so the quick menu has to get out of the way or
  /// they stack on top of each other.
  ///
  /// Placement counts too now (2026-08-09): the map's own banner explains the
  /// ✓/✗ that are sitting over the building, and a second banner underneath it
  /// saying roughly the same thing is one too many.
  bool get _mapModeActive =>
      _roadMode || _editMode || _pendingTypeId != null;

  Widget _bottomStack() {
    // The Build menu no longer needs a mention here (2026-07-31): it is a page
    // now, so it covers this screen rather than sharing the bottom edge with it.
    if (_mapModeActive) return const SizedBox.shrink();
    // SafeArea now: the bar that used to paint its own background into the
    // gesture inset is gone, so the loose buttons have to keep off the glass
    // themselves.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ctrl.introStep.isActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: KeyedSubtree(
                // The spotlight's hole — the card (CTA + skip) is the only
                // living UI while the tutorial overlay is up.
                key: IntroSpotlightAnchors.of('intro-panel'),
                child: IntroCardPanel(
                  ctrl: _ctrl,
                  onNavigate: _goToIntroTarget,
                ),
              ),
            ),
          _quickPad(),
        ],
      ),
    );
  }

  void _goToIntroTarget(IntroDestination target) => switch (target) {
    IntroDestination.collection => _showCreatures(),
    IntroDestination.map => _showOverworld(),
    IntroDestination.trips => _showExpeditions(),
    IntroDestination.build => _showBuildMenu(),
    IntroDestination.practiceFight => _startPracticeFight(),
    IntroDestination.healingHut =>
      _mapKey.currentState?.openBuildingByType(kHealingHutBuildingId),
    IntroDestination.mainHall =>
      _mapKey.currentState?.openBuildingByType('castle'),
  };

  /// The tutorial's scripted first battle: the starter against a rival far
  /// out of its league. The loss is the LESSON — it produces the K.O. that
  /// the Healing Hut step then fixes. Advances only once the starter is
  /// actually down, so fleeing (or a miracle win) just re-offers the fight.
  Future<void> _startPracticeFight() async {
    final creatures = CreaturesController();
    if (creatures.creatures.isEmpty) return;
    final starter = creatures.creatures.first;
    final species = kSpeciesDefs[starter.speciesId];
    if (species == null) return;
    final rival = Combatant.fromSpecies(
      species,
      level: starter.level + kIntroPracticeLevelBonus,
      id: 'practice_rival',
      statScale: kIntroPracticeStatScale,
    );
    final outcome = await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: [starter],
          enemies: [rival],
          title: 'Practice Fight',
        ),
      ),
    );
    if (!mounted) return;
    if (outcome == CombatOutcome.defeat || starter.isKo) {
      await _ctrl.advanceIntro(IntroStep.practiceFight);
    }
  }

  // ── Top bar ───────────────────────────────────────────────
  /// THE FIGURES, AND NOTHING ELSE (user 2026-07-29: "Alles auf der Zeile von
  /// 'era I' kann gelöscht werden").
  ///
  /// The band had a running head over the strip — the era's numeral and name,
  /// with the bag, tasks and bell on its right. The three icons moved to the
  /// corner pad, which left a whole row of header carrying one line of text
  /// that never changes between eras. The era is still named, in the eras menu,
  /// where it is the thing you went to look at.
  ///
  /// The strip itself used to be everything the settlement had ever unlocked,
  /// wrapped over as many rows as it took: era III was fourteen cells and three
  /// rows of header, and by era VIII it would have been twenty-two. It is
  /// exactly seven cells in EVERY era now — this era's two build resources,
  /// this era's two luxuries, gold, energy, housing — because that is what a
  /// decision on this screen is made of. Everything older is one tap away in
  /// the eras menu at the end of the row, which is the whole reason the strip
  /// can afford to be this short.
  ///
  /// SafeArea, not a fixed height: pinned to the very top, so on a notched
  /// phone it would otherwise sit under the cutout.
  /// ── Der Header klappt auf (user 2026-07-31) ──
  /// "baue den Pfeil in den Header ein, so dass es einen übergang gibt. Wenn ich
  ///  diesen drücke klappt der Header nach unten auf und zeigt alle Ressourcen."
  ///
  /// The older eras used to live in a POPUP hanging off the end of the strip: a
  /// card that flew in over the map, with its own surface, its own shadow and no
  /// relation to the bar it came from. They are the same reading as the seven
  /// cells above them — just the ones this era does not spend — so the bar
  /// simply gets taller and shows them.
  ///
  /// The TAB is drawn before the band and tucked under it, so the band's own
  /// edge and shadow fall across its top: no seam, no second surface, one piece
  /// of material with a pull on it.
  Widget _topBar() => SafeArea(
    bottom: false,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: -(_kErasTabH - _kErasTabTuck),
          child: Center(child: _erasTab()),
        ),
        ParchmentHeader.band(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [_resourceRow(), _erasPanel()],
          ),
        ),
      ],
    ),
  );

  /// How far the tab hangs below the band, and how much of it hides behind it.
  static const double _kErasTabH = 26;
  static const double _kErasTabTuck = 8;

  /// The pull that unfolds the bar. Cut from the band's own gradient with only
  /// its bottom corners rounded — the top edge is meant to disappear into the
  /// band above it.
  Widget _erasTab() => GestureDetector(
    onTap: () => setState(() => _erasOpen = !_erasOpen),
    behavior: HitTestBehavior.opaque,
    child: Container(
      width: 64,
      height: _kErasTabH + _kErasTabTuck,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: ParchmentHeader.bandFill,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
        boxShadow: ParchmentHeader.bandShadow,
      ),
      child: AnimatedRotation(
        // The arrow turns to point back at the bar it just pulled open — the
        // one thing that says "this closes again" without a second glyph.
        turns: _erasOpen ? 0.5 : 0,
        duration: const Duration(milliseconds: 180),
        child: Icon(
          Icons.expand_more_rounded,
          size: 26,
          color: ParchmentHeader.engravedInk,
          shadows: ParchmentHeader.engraved(depth: 1),
        ),
      ),
    ),
  );

  /// Everything the settlement holds, era by era — the bar's second half, shown
  /// only when it is unfolded.
  ///
  /// [AnimatedSize] rather than a fixed height: the list is as long as the eras
  /// you have reached, and a hardcoded height would clip era VIII or leave a gap
  /// in era I.
  Widget _erasPanel() {
    final eras = kEraDefs.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final currentEra = _ctrl.settlement?.eraIndex ?? 1;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !_erasOpen
          ? const SizedBox(width: double.infinity)
          : Padding(
              // Clear of the tab, which hangs over the band's bottom edge.
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final era in eras)
                    _eraMenuRow(era, era.order == currentEra),
                ],
              ),
            ),
    );
  }

  static const _kRomans = [
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];

  static String _roman(int n) =>
      n >= 1 && n <= _kRomans.length ? _kRomans[n - 1] : '$n';

  /// Shown only when the last save FAILED for a real reason (network/RLS). Local
  /// progress is kept and retried every tick, so this is a heads-up, not an
  /// error — it clears itself the moment a write lands again.
  Widget _syncWarning() => Tooltip(
    message: 'Not saved — it will retry automatically.\n'
        'Your progress is kept locally.',
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 4),
    child: Container(
      constraints: const BoxConstraints(minHeight: FoE.tapTarget),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: const Icon(Icons.cloud_off_rounded,
          color: Colors.orangeAccent, size: 20),
    ),
  );

  void _showDailyTasks() => showModalBottomSheet(
    context: context,
    backgroundColor: FoE.panelDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final tasks = _ctrl.dailyTasks.tasks;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            16 + MediaQuery.of(ctx).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Today\'s goals', style: FoE.title(size: 15)),
              const SizedBox(height: 4),
              Text(
                'Three fresh goals every day — small rewards for playing a '
                'round of everything.',
                style: FoE.dim(size: 11),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < tasks.length; i++)
                _dailyTaskRow(i, tasks[i], setLocal),
            ],
          ),
        );
      },
    ),
  );

  Widget _dailyTaskRow(int index, DailyTask t, StateSetter setLocal) {
    final rewardText = t.reward.entries
        .map(
          (e) =>
              '${resourceEmoji(e.key)} '
              '${e.value.toStringAsFixed(0)}',
        )
        .join('  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: FoE.panel(radius: 10),
      child: Row(
        children: [
          Text(t.kind.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.kind.label, style: FoE.label(size: 13)),
                const SizedBox(height: 3),
                RecessBar(
                  value: t.target == 0 ? 1 : t.progress / t.target,
                  color: t.done ? FoE.positive : FoE.gold,
                  height: 9,
                  onDark: true,
                ),
                const SizedBox(height: 3),
                Text(
                  '${t.progress}/${t.target} · reward: $rewardText',
                  style: FoE.dim(size: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (t.claimed)
            Text('✓', style: FoE.label(size: 15).copyWith(color: FoE.positive))
          else
            TextButton(
              onPressed: t.claimable
                  ? () async {
                      await _ctrl.claimDailyTask(index);
                      setLocal(() {});
                    }
                  : null,
              child: Text(
                'Claim',
                style: FoE.label(size: 12).copyWith(
                  color: t.claimable ? FoE.gold : FoE.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// SEVEN CELLS, ONE ROW, EVERY ERA. Not scrollable and no longer wrapping:
  /// each cell takes an equal share of the width, so the bar is the same height
  /// in era VIII as in era I and nothing is ever hidden behind a scroll.
  ///
  /// Order is the order you spend in: what you build with, what you pay sinks
  /// with, then the three standing totals (gold, energy, housing).
  Widget _resourceRow() {
    final rates = _ctrl.hourlyRates;
    final era = _ctrl.settlement?.eraIndex ?? 1;
    // Eight cells while a refinery is unlocked but its era has not arrived —
    // see [_eraResources]. Every cell is an Expanded, so the row still fits.

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 2, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final r in _eraResources(era, cleared: _ctrl.battlesCleared))
            Expanded(
              child: _resCell(
                r.emoji,
                r.name,
                r.id,
                _amountOf(r.id),
                rates[r.id] ?? 0,
              ),
            ),
          Expanded(
            child: _resCell(
              '🪙',
              'Gold',
              'gold',
              _amountOf('gold'),
              rates['gold'] ?? 0,
            ),
          ),
          Expanded(child: _energyCell()),
          Expanded(child: _housingCell()),
        ],
      ),
    );
  }

  /// What era [era] itself deals in: its two build resources and its two
  /// luxuries. Era I's build pair is wood and stone — ResourceModel's own
  /// fields rather than goods, which is why they are spelled out here and
  /// [buildGoodsOfEra] returns nothing for it.
  ///
  /// Plus, since 2026-07-31, whatever a REFINERY you have already won is about
  /// to make (user: "die rafinery wird jeweils beim zweitletzten Knotenpunkt
  /// freigeschalten. Ab diesem Zeitpunkt, soll oben diese Ressource ebenfalls
  /// angezeigt werden"). See [_previewedGoods].
  ///
  /// [cleared] is only passed for the strip. The eras MENU passes nothing: it
  /// lists what each era deals in as a reference table, and a preview cell in
  /// era II's row would be answering a question nobody asked there.
  List<({String id, String emoji, String name})> _eraResources(
    int era, {
    int cleared = 0,
  }) => [
    if (era <= 1) ...[
      (id: 'wood', emoji: '🪵', name: 'Wood'),
      (id: 'stone', emoji: '🪨', name: 'Stone'),
    ] else
      for (final g in buildGoodsOfEra(era))
        (id: g.id, emoji: g.emoji, name: g.name),
    // Right after the build pair, because that is what it IS — a build
    // material, one era early.
    for (final g in _previewedGoods(era, cleared))
      (id: g.id, emoji: g.emoji, name: g.name),
    for (final g in luxuriesOfEra(era))
      (id: g.id, emoji: g.emoji, name: g.name),
  ];

  /// The materials of a LATER era that the path has already handed you the
  /// means to make.
  ///
  /// The refinery is won near the end of an era, and until now the element it
  /// produces stayed invisible until the boss fell — so the building you had
  /// just unlocked made a resource the header refused to admit existed. It is
  /// asked of the ROSTER (which building makes this, and has the path unlocked
  /// it) rather than of a hardcoded "next era's element": if a node is
  /// re-authored in Dev Mode, the strip follows without being told.
  ///
  /// Only ELEMENTS preview. A later era's raw is dug on that era's map spots, so
  /// there is no way to hold any before ascending — and a cell that can only
  /// ever read 0 is noise.
  List<GoodsDef> _previewedGoods(int era, int cleared) {
    if (cleared <= 0) return const [];
    final out = <GoodsDef>[];
    for (final g in kGoodsDefs.values) {
      if (!g.isElement || g.eraOrder <= era) continue;
      // Null = no node gates a producer, so the material arrives with its era —
      // the rule the strip already follows, not a preview.
      final at = producerUnlockBattle(g.id);
      if (at == null || cleared < at) continue;
      out.add(g);
    }
    out.sort((a, b) => a.eraOrder.compareTo(b.eraOrder));
    return out;
  }

  /// One accessor for "how much of X do we hold", whether X is one of the
  /// settlement's own fields or a good in the store.
  double _amountOf(String id) {
    final res = _ctrl.resources;
    if (res == null) return 0;
    return switch (id) {
      'wood' => res.wood,
      'stone' => res.stone,
      'gold' => res.gold,
      _ => res.goods[id] ?? 0,
    };
  }

  // Shared sizing for every header cell so icons and text lines all match up.
  static const _kHeaderIconSize = 14.0;
  static const _kHeaderSubSize = 9.0;

  /// Header numbers are SHORT (`1.2k`, `12k`, `1.4M`). At a seventh of a phone
  /// each, a cell has room for about four glyphs — and a five-digit pile of wood
  /// is a magnitude, not a figure you read digit by digit.
  ///
  /// Shared with every other surface since 2026-07-30 (core/ui/number_format) —
  /// this used to be the only place in the app that shortened anything.
  static String _short(double v) => shortNumber(v);

  /// Every header cell is tappable (it opens the resource breakdown), so each
  /// one gets a real hit area instead of being a bare Padding you have to aim
  /// at.
  Widget _headerCell({required VoidCallback onTap, required Widget child}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FoE.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [child],
          ),
        ),
      );

  Widget _resCell(
    String emoji,
    String title,
    String resourceId,
    double amount,
    double rate,
  ) => _headerCell(
    onTap: () => _showResourceBreakdown(
      emoji: emoji,
      title: title,
      total: rate,
      unit: '/h',
      sources: _ctrl.productionSources(resourceId),
      // The CEILING, next to the rate (user 2026-07-30). Production stops at
      // it, so a rate on its own can describe something that is not happening.
      stored: amount,
      capacity: _ctrl.storageCapacity(resourceId),
      capacitySources: _ctrl.storageSources(resourceId),
    ),
    child: Builder(
      builder: (_) {
        // "+12/h" while the store has been full for an hour describes
        // something that is not happening — production STOPS at the ceiling.
        // So a full cell says FULL instead, in the colour that means "act on
        // this", and the sheet behind it says which building fixes it.
        final cap = _ctrl.storageCapacity(resourceId);
        final full = cap > 0 && amount >= cap;
        // OVER the ceiling is its own state since resource packs exist (user
        // 2026-07-30): a redeemed package may overfill a store on purpose, and
        // "full" would understate it — the cell has to say that this is a
        // surplus being spent down, not a store that has simply stopped.
        final over = cap > 0 && amount > cap;
        // A NET LOSS SAYS SO (user 2026-08-01: "wenn eine Ressource minus macht,
        // dann bitte nicht +- schreiben im header sondern nur -" + "und rot
        // markieren"). The '+' used to be printed unconditionally, so a
        // shrinking pile read "+-1.2/h" — a sign that cancels itself out on the
        // one number where the direction is the whole point.
        final losing = rate < 0;
        final digits = rate.abs() >= 10 ? 0 : 1;
        return _cellBody(
          emoji: emoji,
          value: _short(amount),
          sub: over
              ? 'over ${_short(cap)}'
              : full
              ? 'full'
              : '${losing ? '' : '+'}${rate.toStringAsFixed(digits)}/h',
          subColor: losing
              ? FoE.danger
              : full
                  ? const Color(0xFF9B3B22)
                  : null,
        );
      },
    ),
  );

  /// The shape every cell in the strip shares: THE GLYPH ON TOP, the figure
  /// under it, the rate under that (user 2026-07-29: "Die Icons der
  /// Ressourcen/Housing etc. soll über der Zahl sein").
  ///
  /// Stacked, not side by side. Glyph-then-number ate the cell's width — a
  /// seventh of a phone had to hold both, so `12.4k` was already clipping.
  /// Stacked, the full width belongs to the number, and the glyphs line up as a
  /// row of icons you scan across rather than seven separate little pairs.
  Widget _cellBody({
    required String emoji,
    required String value,
    required String sub,
    Color? valueColor,
    Color? subColor,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(emoji, style: const TextStyle(fontSize: _kHeaderIconSize)),
      // STAMPED, in the band's own hand (user 2026-07-29: "jetzt den Header im
      // gleichen stil"). The corner keys' full letterpress — the glyph in the
      // material's own colour, carried entirely by two hairlines — is not
      // available here: that works at 34px, and these are figures at 12 and 9
      // that have to be READ, not recognised. So the ink stays and only the
      // cut comes over, which is what the two treatments share anyway.
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FoE.value(size: 12).copyWith(
          color: valueColor,
          shadows: ParchmentHeader.engraved(depth: 0.8),
        ),
      ),
      Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FoE.dim(size: _kHeaderSubSize).copyWith(
          color: subColor,
          shadows: ParchmentHeader.engraved(depth: 0.6),
        ),
      ),
    ],
  );

  /// HOUSING, PROMOTED INTO THE STRIP (user 2026-07-29). It used to live only
  /// in the Castle's dialog, which meant the one number that decides
  /// whether a catch, a hatch or an adoption is even possible was three taps
  /// and a map pan away — and you found out it was full at the moment it cost
  /// you the monster.
  Widget _housingCell() {
    final used = _ctrl.housingUsed;
    final cap = _ctrl.housingCapacity;
    final full = used >= cap;
    return _headerCell(
      // Tab 2 — Trips, Work, Housing (the order changed on 2026-07-29).
      onTap: () => _showManagement(initialTab: 2),
      child: _cellBody(
        emoji: '🛏',
        value: '$used/$cap',
        sub: full ? 'full' : '${cap - used} free',
        valueColor: full ? FoE.danger : null,
        subColor: full ? FoE.danger : null,
      ),
    );
  }

  /// THE ERAS MENU (user 2026-07-29: "die Ressourcen aller Zeitalter zu sehen
  /// durch ein Dropdown menü"). The price of a strip that only shows this era:
  /// everything it left out has to be one tap away, and it is — every era, its
  /// build pair and its luxuries, with what you hold of each.
  ///
  /// A real dropdown rather than a sheet, because it belongs to the strip it
  /// abbreviates: it opens against it and closes when you look away.
  Widget _eraMenuRow(EraDef era, bool current) {
    final items = <({String id, String emoji, String name})>[
      ..._eraResources(era.order),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: current ? FoE.positive.withValues(alpha: 0.10) : null,
        border: Border(
          top: BorderSide(color: kParchmentInk.withValues(alpha: 0.13)),
          // The era you are in is called out by a bar down its left edge, so
          // it is findable in a list of eight without reading any of them.
          left: BorderSide(
            color: current ? FoE.positive : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(era.displayEmoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_roman(era.order)} · ${era.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 11).copyWith(
                    color: current ? FoE.positive : FoE.parchment,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final r in items) _eraChip(r.id, r.emoji, r.name),
            ],
          ),
        ],
      ),
    );
  }

  Widget _eraChip(String id, String emoji, String name) {
    final amount = _amountOf(id);
    final has = amount > 0;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _showResourceBreakdown(
          emoji: emoji,
          title: name,
          total: _ctrl.hourlyRates[id] ?? 0,
          unit: '/h',
          sources: _ctrl.productionSources(id),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: ShapeDecoration(// An era you have not reached holds nothing, and its chips say so by
          // fading rather than by disappearing — the ladder stays readable.
          color: kParchmentInk.withValues(alpha: has ? 0.07 : 0.03), shape: FoE.facet(radius: 8, side: BorderSide(color: kParchmentInk.withValues(alpha: has ? 0.20 : 0.10)))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text(
              _short(amount),
              style: FoE.value(size: 10).copyWith(
                color: has ? FoE.parchment : FoE.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _energyCell() {
    // Energy is loaded separately from the settlement, so it can genuinely be
    // absent for the first frames. The strip keeps the cell's SLOT either way —
    // the row's seven columns must not reflow the moment it arrives.
    final energy = _ctrl.energy;
    if (energy == null) {
      return _headerCell(
        onTap: _showEnergyOverview,
        child: _cellBody(emoji: '⚡', value: '—', sub: ''),
      );
    }
    final pct = energy.currentEnergy;
    final isEmpty = pct <= 0;
    // Remaining-time estimate at the current tick's snapshot — no dedicated
    // 1s ticker needed here (unlike EnergySheet's live countdown): at this
    // drain rate (kMaxEnergy/kDrainPerHour = 24h), fmtDuration only shows
    // minute resolution, so the screen's normal 5s-tick rebuild is already
    // more than fine-grained enough for it to read as live.
    final hoursLeft = GameEngine.hoursUntilEmpty(pct);
    return _headerCell(
      onTap: _showEnergyOverview,
      // Ink, not white: the strip is a LIT PARCHMENT band now, and white on
      // cream is a number you cannot read.
      child: _cellBody(
        emoji: '⚡',
        value: pct.toStringAsFixed(0),
        sub: isEmpty ? 'empty' : fmtDuration(hoursLeft * 3600),
        valueColor: isEmpty ? FoE.danger : null,
        subColor: isEmpty ? FoE.danger : null,
      ),
    );
  }

  // ── Debug row (under header, under settlement name) ────────
  /// DEV ONLY — the whole row. Gated on the account flag (profiles.is_dev)
  /// rather than kDebugMode: it works in real builds, but only for the flagged
  /// dev account. It hands out only the STOCKPILE plus Reset and the Dev Mode
  /// editor — nothing that lets a player tap past the docs' balance numbers.
  ///
  /// The ⚡ energy and 🗺 expansion buttons are gone (user 2026-07-26). One
  /// resource button that fills the yard is what testing a build actually
  /// needs; the other two handed out things you can also reach by playing.
  Widget _debugRow() {
    if (!_ctrl.isDev) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gold gates nothing (it only ever removes waiting) and wood/stone are
        // what every build costs, so a thousand of each costs no balance — it
        // just means a building under test doesn't wait on a gather trip.
        _debugBtn(
          '🪙 +${kDevResetFloat.toInt()}',
          () => _ctrl.grantResources({
            'gold': kDevResetFloat,
            'wood': kDevResetFloat,
            'stone': kDevResetFloat,
          }),
        ),
        const SizedBox(width: 6),
        _debugBtn('🔄 Reset', _confirmReset),
        const SizedBox(width: 6),
        _debugBtn('🛠 Dev Mode', _showDevMode),
      ],
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 260,
          decoration: FoE.panel(radius: 12),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Reset EVERYTHING?', style: FoE.title(size: 14)),
              const SizedBox(height: 10),
              Text(
                'Wipes this account back to a first launch: every monster you '
                'own, all buildings, resources, tech gates, breeding, '
                'expeditions, and your level and region progress. The intro '
                'starts over.\n\n'
                'Dev Mode content (monsters, buildings, techs, areas you have '
                'authored) is kept.\n\nThis cannot be undone.',
                textAlign: TextAlign.center,
                style: FoE.label().copyWith(color: FoE.textDim),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: FoE.btn(),
                      child: Text(
                        'Cancel',
                        style: FoE.label().copyWith(color: FoE.textDim),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: ShapeDecoration(color: Colors.red.shade900.withValues(alpha: 0.4), shape: FoE.facet(radius: 6, side: BorderSide(color: Colors.red.shade700))),
                      child: Text(
                        'Reset',
                        style: FoE.label().copyWith(color: Colors.red.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await _ctrl.resetSettlement();
  }

  Widget _debugBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: const Color(0xFF1A1206), shape: FoE.facet(radius: 4, side: BorderSide(color: FoE.border))),
      child: Text(label, style: FoE.dim(size: 9).copyWith(color: FoE.gold)),
    ),
  );

  // ── Quick pad (loose buttons, bottom-right) ─────────────────
  /// EIGHT BUTTONS, ONE PLACE (user 2026-07-29: "bag, notification und
  /// tägliche ziele sind zusammen mit den Buttons build, map, trips, monster
  /// und manage einzelne Buttons ohne Footer unten rechts").
  ///
  /// Ordered by reach: [QuickPad] lays its first item into the bottom-right
  /// corner and fills outwards, so Build — the thing you press most on a
  /// settlement screen — sits under the thumb and the bell ends up furthest.
  ///
  /// Dev Mode deliberately NOT here: it lives in the debug row with the other
  /// dev tools. This pad is the player's.
  ///
  /// SIX KEYS. Trips is gone (user 2026-07-29): the Management hub leads with
  /// its Trips tab now, and that tab IS the expeditions hub — so the button was
  /// a second door into a room that already had one. News is gone too; it is an
  /// icon under the header, not a destination.
  ///
  /// Every glyph is a SOLID one (user 2026-07-29: "Fülle die Icons jeweils
  /// aus"). With the labels gone the glyph is the whole button, so the two
  /// outline ones had to be swapped: the bag for its filled twin, and the
  /// daily tasks from a ticked circle — which reads as "already done" — to a
  /// flag, which is what a goal is.
  Widget _quickPad() => QuickPad(
    items: [
      QuickPadItem(Icons.construction, 'Build', _showBuildMenu),
      QuickPadItem(Icons.map, 'Map', _showOverworld),
      QuickPadItem(Icons.pets, 'Monsters', _showCreatures),
      // The Management hub: what is out on the road, who works where, and the
      // housing budget. Research used to be a key here — the overworld IS
      // research now (techs are places on it), so it would have been two doors
      // into one room.
      QuickPadItem(Icons.assignment, 'Manage', _showManagement),
      QuickPadItem(
        Icons.backpack,
        'Bag',
        () => openBag(context),
        badge: _ctrl.items.values.fold<int>(0, (s, n) => s + n),
      ),
      QuickPadItem(
        Icons.flag,
        'Daily tasks',
        _showDailyTasks,
        badge: _ctrl.dailyTasks.claimableCount,
      ),
    ],
  );
}
