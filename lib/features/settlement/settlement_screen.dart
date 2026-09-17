import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/resource_icons.dart';
import '../../core/ui/feel_button.dart';
import '../../core/orientation_lock.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/number_format.dart';
import '../creatures/models/area.dart';
import '../creatures/models/species_def.dart' show kSpeciesDefs;
import '../creatures/services/overworld_layout.dart' show areaForRegion;
import 'data/building_art.dart' show kBundledBuildingArt, buildingAsset;
import 'data/building_definitions.dart';
import 'data/goods_definitions.dart';
// Deferred (user 2026-09-06: "performance deutlich verbessern") — Dev Mode
// is ~12.6k lines (every def form, the balance tools, the combat lab), all
// of which used to compile straight into the initial main.dart.js bundle
// for every player even though almost none of them ever open it. `loadLibrary`
// only fetches this chunk the first time _showDevMode is actually called.
import 'dev/dev_mode_screen.dart' deferred as dev_mode;
import 'services/daily_tasks.dart';
import 'services/new_items.dart';
import 'services/step_tracker_service.dart';
import 'settlement_controller.dart';
import 'build_menu_screen.dart';
import 'sheets/energy_sheet.dart';
import 'bag_screen.dart';
import 'profile_screen.dart';
import 'resource_detail_screen.dart';
import 'widgets/meander_strip.dart';
import 'widgets/parchment_sheet.dart';
import 'widgets/quick_pad.dart';
import 'widgets/scroll_paper.dart';
import 'widgets/settlement_map.dart';
import '../common/events/game_events.dart';
import '../common/widgets/parchment_page.dart';
import '../common/events/notification_button.dart';
import '../creatures/collection_screen.dart';
import 'housing_screen.dart';
import 'management_screen.dart';
import '../creatures/expeditions_screen.dart';
import '../creatures/models/creature_enums.dart' show kHealingHutBuildingId;
import '../creatures/overworld_screen.dart';
import '../onboarding/intro_card_panel.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/ui/pressable.dart';
import '../social/social_screen.dart';

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with
        OrientationLock<SettlementScreen>,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  final _ctrl = SettlementController();
  // Lets the tutorial's CTAs open a building's dialog directly (heal step,
  // assign step) instead of asking a brand-new player to find it on the map.
  final _mapKey = GlobalKey<SettlementMapState>();
  String? _pendingTypeId;
  bool _editMode = false;

  bool _roadMode = false;

  // Set by the pickStarter card's CTA (see IntroCardPanel.onPromptQuickMenu):
  // instead of navigating, it hands the spotlight to the real Monsters tile
  // in the quick menu. Reset once the step moves on, so a later replay of
  // the intro (skip/restart) starts the card fresh again.
  bool _pickStarterPrompted = false;

  // ── Eras panel expand/collapse (user 2026-09-06) ────────────
  // AnimatedSize looked instant no matter how long its duration ran —
  // [_erasPanel] sits as the size-determining child of a Stack that ALSO
  // has two full-height Positioned MeanderStrips in it, and something in
  // that combination was skipping the intermediate frames instead of
  // interpolating through them. A driven [SizeTransition] doesn't depend on
  // the parent re-measuring an implicitly-animated child at all — it clips
  // and scales a fixed-size child by its OWN controller's value every
  // frame, which is the actual "extends downward, retracts back up" reveal
  // that was asked for.
  late final AnimationController _erasCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

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
    NewItems().addListener(_rebuild);
    // Real step counter: watches the hardware sensor and credits steps as
    // energy automatically (user 2026-07-18).
    StepTrackerService().start();
    _bootstrap();
  }

  /// True once every picture the game's first frame (or a moment later) could
  /// need has actually finished decoding — [_loading] stays up until then, see
  /// [build].
  bool _assetsReady = false;

  /// Loads the game's DATA before showing it (user 2026-09-11: "vor dem
  /// Gamestart einen Ladescreen, bei welchem alles vorgeladen wird"), then
  /// precaches only the LOCAL art that first frame needs — every network
  /// picture keeps loading in the BACKGROUND after the game is already on
  /// screen.
  ///
  /// The first version of this (also 2026-09-11) awaited every picture in the
  /// game before flipping [_assetsReady] — every uploaded building's URL AND
  /// every species' art, front and back, every stage, whether this save has
  /// ever seen it or not. That is ~250+ network fetches blocking the very
  /// first frame, which is exactly the regression the player reported one
  /// message later ("die performance ist jetzt sehr schlecht"): the loading
  /// screen got dramatically SLOWER, not faster. Bundled building renders are
  /// local assets (fast, no network) and cover every building this save
  /// actually starts with, so those alone are worth blocking on; everything
  /// that needs the network is reference art for buildings not yet built and
  /// species this save may never even encounter — precaching THAT in the
  /// background is exactly as good for the player and does not hold the
  /// front door shut while it happens.
  Future<void> _bootstrap() async {
    await _ctrl.load();
    if (!mounted) return;
    if (_ctrl.error != null) {
      setState(() => _assetsReady = true);
      return;
    }
    final local = <Future<void>>[];
    for (final id in kBundledBuildingArt) {
      final asset = buildingAsset(id);
      if (asset != null) local.add(precacheImage(AssetImage(asset), context));
    }
    // One broken asset must not hang the loading screen forever.
    await Future.wait(local.map((f) => f.catchError((_) {})));
    if (!mounted) return;
    setState(() => _assetsReady = true);
    _precacheNetworkArtInBackground();
  }

  /// Everything that needs the network, fired AFTER the game is already
  /// showing — see [_bootstrap]. Fire-and-forget: nothing awaits this, it
  /// just warms the cache so the Bestiary/battle/build-menu don't hit a cold
  /// fetch the first time they draw a picture this save hasn't needed yet.
  ///
  /// THE PROVIDER MUST MATCH THE WIDGET (found auditing this 2026-09-12) —
  /// [BuildingIcon] draws every uploaded (non-bundled) picture through
  /// [CachedNetworkImage], never plain [Image.network]. Flutter's ImageCache
  /// keys on the ImageProvider's own type, so precaching a `NetworkImage`
  /// here populated a cache entry [CachedNetworkImageProvider] never looks
  /// up — every uploaded building has been fetched over the network TWICE
  /// since this precache first shipped (2026-09-06): once here, wastefully,
  /// and once for real the first time [BuildingIcon] actually drew it.
  /// [CachedNetworkImageProvider] is what actually lands in its cache (and,
  /// via flutter_cache_manager, on disk). Species art keeps the platform
  /// split [CreatureSprite] itself uses — `Image.network` on web, otherwise
  /// the same cached provider — for the same reason.
  void _precacheNetworkArtInBackground() {
    // The other ~69 of 89 buildings — no bundled render yet, so their picture
    // is whatever got uploaded in Dev Mode (BuildingDef.imageUrl). Bundled
    // wins over imageUrl (see data/building_art.dart), so skip a building
    // already covered by [_bootstrap] rather than fetch a picture nothing
    // ever draws.
    for (final def in kBuildingDefs.values) {
      final url = def.imageUrl;
      if (url != null && url.isNotEmpty && buildingAsset(def.id) == null) {
        precacheImage(CachedNetworkImageProvider(url), context)
            .catchError((_) {});
      }
    }
    final speciesUrls = <String>{};
    for (final species in kSpeciesDefs.values) {
      for (final stage in species.stages) {
        final front = stage.imageUrl;
        final back = stage.backImageUrl;
        if (front != null && front.isNotEmpty) speciesUrls.add(front);
        if (back != null && back.isNotEmpty) speciesUrls.add(back);
      }
    }
    for (final url in speciesUrls) {
      final ImageProvider provider = kIsWeb
          ? NetworkImage(url)
          : CachedNetworkImageProvider(url);
      precacheImage(provider, context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_rebuild);
    NewItems().removeListener(_rebuild);
    _ctrl.stopTicker();
    _erasCtrl.dispose();
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

  void _showSocial() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SocialScreen()),
  );

  // Overworld — the front door to expeditions (gather/capture/battle). Battle
  // routes into the existing dungeon run per area; the quick-menu button is
  // the interim entrance until a placeable map/portal building exists.
  void _showOverworld() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const OverworldScreen()),
  );

  Future<void> _showDevMode() async {
    await dev_mode.loadLibrary();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => dev_mode.DevModeScreen()),
    );
  }

  void _showProfile() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProfileScreen(
        onOpenDevMode: _ctrl.isDev ? _showDevMode : null,
      ),
    ),
  );

  /// Same tap-target/icon-button shape as [FeelButton]/[NotificationButton]
  /// right beside it — the account settings a player was otherwise never
  /// shown at all (user 2026-09-15).
  Widget _profileButton() => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: _showProfile,
      borderRadius: BorderRadius.circular(FoE.radiusSmall),
      child: SizedBox(
        width: FoE.tapTarget,
        height: FoE.tapTarget,
        child: Icon(Icons.person_outline, size: 20, color: FoE.textDim),
      ),
    ),
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

  // Its OWN screen now (user 2026-08-31: "die Ressourcendetail screens einen
  // eigenen Screen werden") — [ResourceDetailScreen] reads everything it
  // shows live off [SettlementController] itself, so this only has to name
  // WHICH resource; total/sources/stored/capacity are no longer snapshotted
  // at tap time the way the sheet needed them handed in.
  void _showResourceBreakdown({
    required String resourceId,
    required String emoji,
    required String title,
  }) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ResourceDetailScreen(
        resourceId: resourceId,
        emoji: emoji,
        title: title,
      ),
    ),
  );

  /// Whether the bar is unfolded to show every era's resources.
  bool _erasOpen = false;

  void _openEras() {
    setState(() => _erasOpen = true);
    _erasCtrl.forward();
  }

  void _closeEras() {
    setState(() => _erasOpen = false);
    _erasCtrl.reverse();
  }

  void _toggleEras() => _erasOpen ? _closeEras() : _openEras();

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // A step past pickStarter (adopted, skipped, or the intro replayed from
    // scratch) — drop the stale flag so a later pass through this step shows
    // its card fresh instead of jumping straight to the spotlighted tile.
    if (_ctrl.introStep != IntroStep.pickStarter && _pickStarterPrompted) {
      _pickStarterPrompted = false;
    }
    // Welcome-back digest: queued by load() when the player was away a while;
    // shown exactly once, after this frame so the sheet has a laid-out screen
    // under it.
    final ready = !_ctrl.isLoading && _assetsReady;
    final digest = _ctrl.pendingDigest;
    if (digest != null && ready) {
      _ctrl.pendingDigest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDigest(digest);
      });
    }
    return Scaffold(
      // The map fills this itself; the colour only shows while it loads and
      // behind the edges, so it is the page tone like everywhere else.
      backgroundColor: kParchmentMid,
      body: !ready
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

    // Nothing to report (user 2026-08-27: "wenn bei meiner Abwesenheit
    // nichts nennenswertes passiert ist, dann soll der 'while you were away'
    // screen nicht auftauchen") — an empty gathered list AND an empty event
    // feed means the away period produced nothing worth a whole dialog over.
    // kDigestMinAwayHours already filters trivially SHORT absences; this
    // filters LONG-but-idle ones (an empty settlement, or one with nothing
    // left to produce) the same way.
    if (d.gained.isEmpty && events.isEmpty) return;

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
                  // Same top-to-bottom sheet-into-shade gradient as every
                  // other page/dialog ground (ParchmentPage.pageGradient,
                  // user 2026-09-05) — this dialog still had the flat
                  // single-tone fill that rule replaced everywhere else.
                  gradient: ParchmentPage.pageGradient,
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
                    // The build menu's own bands, as wallpaper. Flush to
                    // the box's own top/bottom edge (user 2026-09-01), the
                    // same fillHeight fix the era panel got — a hard-edged
                    // card, not a free page margin, so the usual centred-
                    // with-margin run left a visible gap at both ends.
                    Positioned(
                      left: 14,
                      top: 0,
                      bottom: 0,
                      width: 16,
                      child: MeanderStrip(color: ornament, fillHeight: true),
                    ),
                    Positioned(
                      right: 14,
                      top: 0,
                      bottom: 0,
                      width: 16,
                      child: MeanderStrip(
                        color: ornament,
                        flip: true,
                        fillHeight: true,
                      ),
                    ),
                    Padding(
                      // +12/+12 (2026-09-06): same band-width delta as
                      // every other page's kParchmentPagePad.
                      padding: const EdgeInsets.fromLTRB(42, 18, 42, 16),
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
                          Pressable(
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

  /// The REAL loading screen (user 2026-09-11) — up until [_ctrl.load]
  /// finishes AND every picture from [_bootstrap] has actually decoded, not
  /// just a bare spinner over the (still empty) map. Same parchment gradient
  /// and title as the sign-in screen, so app launch reads as one continuous
  /// piece rather than a flash of brand, then a blank wait, then the game.
  Widget _loading() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [kParchmentLight, kParchmentMid],
      ),
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Bøddy Game', style: FoE.title(size: 22)),
          const SizedBox(height: 28),
          CircularProgressIndicator(color: FoE.gold),
          const SizedBox(height: 16),
          Text(
            _ctrl.isLoading ? 'Loading your settlement…' : 'Preparing the map…',
            style: FoE.dim(size: 12),
          ),
        ],
      ),
    ),
  );

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
      // Tapping the map closes the open eras panel (user 2026-09-01: "wenn
      // das era panel geöffnet ist, soll es sich schliessen, wenn ich
      // irgendwo auf die map klicke"). Sits ABOVE the map but BELOW the top
      // bar in this Stack, so it swallows a dismiss tap anywhere on the map
      // without also passing it through to the map underneath, while the
      // header/panel's own taps (chips, the fold tab) still land on the
      // header above this layer untouched. Absent entirely while closed —
      // no invisible barrier stealing taps the map needs the rest of the
      // time.
      if (_erasOpen)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _closeEras,
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
                  _profileButton(),
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
      // The intro card ITSELF is the lit control (every step still holding
      // its own unpressed CTA) — centred on the screen rather than pinned
      // above the quick menu (user 2026-09-02: "diese Textboxen in die
      // Mitte des Screens nehmen"). Drawn BEFORE the scrim below so the
      // spotlight punches its hole out around exactly this position.
      if (_ctrl.introStep.isActive &&
          !_mapModeActive &&
          _pendingTypeId == null &&
          _soloQuickPadAnchor == null)
        Center(
          // The spotlight's hole — the card (CTA + skip) is the only living
          // UI while the tutorial overlay is up.
          child: KeyedSubtree(
            key: IntroSpotlightAnchors.of('intro-panel'),
            child: _introCard(),
          ),
        ),
      // Guided tutorial: dim and dead-zone everything except the ONE lit
      // control — the intro card above, or (once a step hands off, see
      // [_soloQuickPadAnchor]) the quick-menu tile it points at. Off during
      // placement (the map is the target then) and map modes.
      if (_ctrl.introStep.isActive && !_mapModeActive && _pendingTypeId == null)
        IntroSpotlightOverlay(
          anchorName: _introSpotlightAnchor,
          hint: _introSpotlightHint,
        ),
      // A narration-only card (firstNode's "your monsters can fight too")
      // stays up ON TOP of the scrim instead of being punched out of it —
      // it has nothing of its own to press, so it never needs to BE the
      // hole, only to stay readable while a quick-pad tile is. Centred too,
      // for the same reason as above.
      if (_ctrl.introStep.isActive &&
          !_mapModeActive &&
          _pendingTypeId == null &&
          _introCardIsNarrationOnly &&
          _soloQuickPadAnchor != null)
        Center(child: _introCard()),
    ],
  );

  /// The guided-tutorial card, padded and ready to drop anywhere in the
  /// Stack — pulled out so both the "I'm the spotlight hole" placement and
  /// the "I float above the scrim" placement (see [build]) render the exact
  /// same widget.
  Widget _introCard() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: IntroCardPanel(
      ctrl: _ctrl,
      onNavigate: _goToIntroTarget,
      onPromptQuickMenu: () => setState(() => _pickStarterPrompted = true),
    ),
  );

  /// The current step's card, or null once the tutorial is [IntroStep.done].
  IntroCard? get _activeIntroCard =>
      _ctrl.introStep.isActive ? introCardFor(_ctrl.introStep) : null;

  /// True for a step whose card is pure narration with no CTA of its own
  /// (e.g. firstNode, user 2026-09-02: "kein Button open the map") — it stays
  /// on screen, drawn ABOVE the spotlight scrim rather than dimmed by it,
  /// while a quick-pad tile is the actual interactive target (see
  /// [_soloQuickPadAnchor]).
  bool get _introCardIsNarrationOnly => _activeIntroCard?.ctaLabel == null;

  /// The ONE quick-pad tile that's lit and interactive right now, or null
  /// when the intro card itself is that one lit control instead (the usual
  /// case: most steps' own CTA button IS the hole).
  ///
  /// Two ways a tile ends up here: a narration-only card that points straight
  /// at a tile from the moment its step begins (firstNode → Map), or
  /// pickStarter's card handing off to Monsters once ITS OWN CTA has been
  /// pressed (see [_pickStarterPrompted]) — the card had something to press,
  /// this one never did.
  String? get _soloQuickPadAnchor {
    final card = _activeIntroCard;
    if (card == null) return null;
    if (_introCardIsNarrationOnly) {
      return switch (card.destination) {
        IntroDestination.map => 'quick-map',
        IntroDestination.collection => 'quick-monsters',
        IntroDestination.build => 'quick-build',
        // Not a quick-pad tile — the Healing Hut itself, on the map (user
        // 2026-09-06: "lass mich das Gebäude anklicken") — see
        // SettlementMapState's own anchorKey wiring in _buildingTile.
        IntroDestination.healingHut => 'map-healing-hut',
        _ => null,
      };
    }
    if (_ctrl.introStep == IntroStep.pickStarter && _pickStarterPrompted) {
      return 'quick-monsters';
    }
    return null;
  }

  /// Which anchor the guided tutorial lights up right now — the CURRENT
  /// step's own quick-pad tile when it has one, else the intro card itself.
  /// An earlier hand-off's tile can still be showing in the pad alongside it
  /// (see [_quickPad]), but only THIS one is the hole.
  String get _introSpotlightAnchor => _soloQuickPadAnchor ?? 'intro-panel';

  String? get _introSpotlightHint => switch (_soloQuickPadAnchor) {
    'quick-monsters' => 'Tap Monsters to choose your starter',
    'quick-map' => 'Tap Map to open the overworld',
    'quick-build' => 'Tap Build to open the build menu',
    'map-healing-hut' => 'Tap the Healing Hut to open it',
    _ => null,
  };

  /// A tile earns a permanent spot in the reduced quick pad the moment its
  /// own step hands off to it, and keeps it through every later solo
  /// hand-off too (user 2026-09-02: "der Monsterbutton soll auch bereits
  /// angezeigt werden, da dieser bereits benutzt wurde") — the pad only
  /// ever grows while the tutorial runs, never loses a tile it already
  /// showed.
  bool get _monstersUnlocked =>
      _soloQuickPadAnchor == 'quick-monsters' ||
      _ctrl.introStep.index > IntroStep.pickStarter.index;

  bool get _mapUnlocked =>
      _soloQuickPadAnchor == 'quick-map' ||
      _ctrl.introStep.index > IntroStep.firstNode.index;

  bool get _buildUnlocked =>
      _soloQuickPadAnchor == 'quick-build' ||
      _ctrl.introStep.index > IntroStep.buildHealingHut.index;

  /// True while the map owns the bottom of the screen: aiming, road building
  /// and move/edit mode each show their own banner down there (with the button
  /// that LEAVES the mode), so the quick menu has to get out of the way or
  /// they stack on top of each other.
  ///
  /// Placement counts too now (2026-08-09): the map's own banner explains the
  /// ✓/✗ that are sitting over the building, and a second banner underneath it
  /// saying roughly the same thing is one too many.
  bool get _mapModeActive => _roadMode || _editMode || _pendingTypeId != null;

  Widget _bottomStack() {
    // The Build menu no longer needs a mention here (2026-07-31): it is a page
    // now, so it covers this screen rather than sharing the bottom edge with it.
    if (_mapModeActive) return const SizedBox.shrink();
    // SafeArea now: the bar that used to paint its own background into the
    // gesture inset is gone, so the loose buttons have to keep off the glass
    // themselves.
    return SafeArea(top: false, child: _quickPad());
  }

  void _goToIntroTarget(IntroDestination target) => switch (target) {
    IntroDestination.collection => _showCreatures(),
    IntroDestination.map => _showOverworld(),
    IntroDestination.trips => _showExpeditions(),
    IntroDestination.build => _showBuildMenu(),
    IntroDestination.healingHut => _mapKey.currentState?.openBuildingByType(
      kHealingHutBuildingId,
    ),
  };

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
  /// exactly six cells in EVERY era now — this era's two build resources,
  /// this era's one luxury (down from two, 2026-09-12), gold, energy, housing —
  /// because that is what a decision on this screen is made of. Everything
  /// older is one tap away in the eras menu at the end of the row, which is
  /// the whole reason the strip can afford to be this short.
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
  /// The TAB sits directly below the band as a normal sibling now, not a
  /// Positioned child tucked (via a negative offset) under it (user
  /// 2026-08-31: "dieser Button zum aufklappen ist nicht anwählbar").
  ///
  /// A Stack's own size is set by its NON-positioned children only — a
  /// Positioned child overflowing the Stack (the tab, hanging below the
  /// band) never counts toward it, so ancestor hit-testing (which stops at
  /// the Stack's own bounds before ever asking its children) rejected any
  /// tap landing in that overflow — exactly where the tab's tappable icon
  /// sits. Doubly so once the band's own height started changing under
  /// [_erasPanel]'s AnimatedSize, which no fixed-size workaround could have
  /// tracked. A real Column sibling has no such blind spot, at the cost of
  /// the few pixels the tab used to tuck up under the band's own edge.
  Widget _topBar() => SafeArea(
    bottom: false,
    child: Column(
      children: [
        ParchmentHeader.band(
          // The exact background the building detail dialog uses (user
          // 2026-09-06: "nimm ... den genau gleichen Hintergrund wie für den
          // Gebäudedetailscreen") rather than [ParchmentHeader.bandFill]'s
          // flat approximation of it — this screen has no ambient
          // [ParchmentPage] gradient behind it to show through, so the band
          // draws the real one itself.
          gradient: ParchmentPage.pageGradient,
          // Lifts it off the map behind it (user 2026-09-06: "damit sich
          // dieser besser von der Map abhebt") — every other [band] caller
          // sits on the flat parchment page and stays shadowless, but this
          // one floats directly over the isometric settlement with nothing
          // but colour to tell the two apart. [_mapShadow], not [FoE.drop],
          // so the shadow reaches the LEFT edge too (user 2026-09-06).
          shadow: _mapShadow,
          // The same Greek-key bordure every ParchmentPage carries down its
          // sides (user 2026-08-31: "bei der Ressourcenübersicht bitte auch
          // das Mäanderband an den Seiten einfügen") — [ParchmentPage
          // .ornament] is the ink for both, since the app went
          // dark-mode-first and that ink already reads on graphite.
          child: Stack(
            children: [
              // Bands BEHIND the content, same paint order ParchmentPage
              // uses — drawn first so the resource cells sit on top of them
              // rather than the other way round.
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                width: 16,
                // Flush to the box's own top/bottom edge (user 2026-08-31:
                // "das Band soll oben und unten bis wirklich zur Kante der
                // Box gehen") — this panel IS a hard-edged box, not a free
                // page margin, so the usual centred-with-margin run left a
                // visible gap at both ends. Left/right inset 14/width 16
                // (2026-09-06), matching building_detail_dialog.dart.
                child: MeanderStrip(
                  color: ParchmentPage.ornament,
                  fillHeight: true,
                ),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                width: 16,
                child: MeanderStrip(
                  color: ParchmentPage.ornament,
                  flip: true,
                  fillHeight: true,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [_resourceRow(), _erasPanel()],
              ),
            ],
          ),
        ),
        _erasWave(),
      ],
    ),
  );

  /// The main screen's own drop shadow — straight down, not [FoE.drop]'s
  /// usual down-RIGHT diagonal (user 2026-09-06: "der Schatten... soll auch
  /// links bis zum Rand gehen") — the diagonal is why every other [FoE.drop]
  /// user only ever shows a sliver on the right/bottom: shifting the shadow
  /// rect sideways tucks its left edge behind the box itself. Shared between
  /// the header band and the eras tab hanging off it, so the two read as one
  /// continuous shape lifted off the map, not two mismatched edges.
  static final List<BoxShadow> _mapShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.45),
      offset: const Offset(0, 3),
    ),
  ];

  /// How deep the wave hangs at its LOWEST point, and how shallow at its
  /// highest — a full-width wave spanning the header's own width, reading as
  /// the header's edge itself flowing down into a pull, rather than a
  /// separate control bolted under it.
  static const double _kWaveMin = 8;
  static const double _kWaveMax = 26;

  /// How far in from EACH edge the curve takes to reach full depth, as a
  /// fraction of the width — centred and symmetric (user 2026-09-07: "der
  /// Headerbutton soll mittig sein und auf beide Seiten auslaufen", then
  /// "wieder deutlich schmaler und weniger hoch"). The middle stretch (the
  /// remaining `1 - 2*_kWaveTaper`) stays flat at full depth; both sides
  /// mirror the same ogee back up to the shallow lip.
  static const double _kWaveTaper = 0.38;

  /// The pull that unfolds the bar — belongs TO the header, not beside it
  /// (user 2026-09-06: "dieser gehört zum Header. Daher gibt es keinen
  /// Übergang"), so it must never restart its own gradient. A LinearGradient
  /// always fits itself to its OWN box, which is why this paints a flat
  /// [FoE.bg] fill (the gradient's own end stop) instead of a fresh
  /// gradient — see the CROSS-FADE note this comment used to carry on the
  /// old fixed-height tab; a wave of varying height has the identical
  /// problem for the same reason.
  Widget _erasWave() => FractionallySizedBox(
    // Centred and narrow (user 2026-09-08: "so dass er links und rechts
    // nicht bis an die Handykante kommt, sondern nur etwa 20% der Breite in
    // der Mitte einnimmt") — no longer spans the header's full width.
    widthFactor: 0.2,
    child: Pressable(
      onTap: _toggleEras,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: _kWaveMax,
        child: CustomPaint(
          painter: _EraWavePainter(
            waveMin: _kWaveMin,
            waveMax: _kWaveMax,
            taper: _kWaveTaper,
            shadow: _mapShadow.first,
          ),
          child: Align(
            // The arrow sits where the wave actually IS deep enough to hold
            // it — dead centre, now that the plateau itself is centred.
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: AnimatedRotation(
                // The arrow turns to point back at the bar it just pulled open
                // — the one thing that says "this closes again" without a
                // second glyph. Same duration as [_erasPanel]'s own
                // AnimatedSize (user 2026-09-06, then "noch langsamere
                // Animation, so dass man es gut sieht") so the arrow finishes
                // turning exactly as the panel finishes moving, instead of
                // visibly settling first.
                turns: _erasOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubic,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 26,
                  color: ParchmentHeader.engravedInk,
                  shadows: ParchmentHeader.engraved(depth: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Everything the settlement holds, region by region — the bar's second
  /// half, shown only when it is unfolded.
  ///
  /// Every region the GOODS ladder reaches ([kMaxRegionOrder]), not just the
  /// ones with a map ([kAreaDefs]) yet (user 2026-09-05: "alle Ressourcen
  /// angezeigt bekommen, welche im Spiel vorhanden sind oder sein werden" —
  /// e.g. Crystal Vault, region VIII's element, used to be invisible here
  /// because no area past III has been built yet). A region without a map
  /// still has a resource ladder authored for it, so it still gets a row —
  /// just with a placeholder name until [areaForRegion] finds one.
  ///
  /// [SizeTransition] driven by [_erasCtrl], not [AnimatedSize] — the list
  /// is as long as [kMaxRegionOrder] says, so a hardcoded height would clip
  /// a late region or leave a gap with only a few, but AnimatedSize here
  /// looked instant regardless of its own duration (user 2026-09-06: "es
  /// sieht noch immer aus, als würde es direkt aufgeklappt sein"). Sitting
  /// as the size-determining child of a Stack that also carries two
  /// full-height Positioned MeanderStrips, something about that combination
  /// skipped straight to the end size instead of interpolating through it.
  /// A driven transition sidesteps the question entirely: [_erasCtrl]'s own
  /// value scales and clips a CHILD THAT'S ALWAYS FULLY BUILT, frame by
  /// frame, rather than asking a parent to notice and animate an implicitly
  /// changing child size.
  Widget _erasPanel() {
    final currentRegion = _ctrl.dungeonMaxStage;
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _erasCtrl,
        curve: Curves.easeInOutCubic,
      ),
      // Reveals downward from the header (user 2026-09-06: "ich möchte
      // aber, dass es nach unten ausfährt und wieder zurückfährt") rather
      // than growing from the centre.
      axisAlignment: -1,
      child: Padding(
        // Clear of the tab, which hangs over the band's bottom edge.
        padding: const EdgeInsets.only(bottom: 10),
        // Own bands, not just a taller reach of _topBar's (user 2026-09-05:
        // "bei todays goals links und rechts noch das Mäanderband
        // hinzufügen") — self-contained so the panel always carries them
        // regardless of how the transition interacts with the outer
        // Stack's sizing. Same 14/16 geometry _topBar's own pair uses (user
        // 2026-09-06: widened from 4/14 to match building_detail_dialog.dart),
        // so the two line up as one continuous band down the whole card.
        child: Stack(
          children: [
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              width: 16,
              child: MeanderStrip(
                color: ParchmentPage.ornament,
                fillHeight: true,
              ),
            ),
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              width: 16,
              child: MeanderStrip(
                color: ParchmentPage.ornament,
                flip: true,
                fillHeight: true,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var region = 1; region <= kMaxRegionOrder; region++) ...[
                  if (region > 1) _eraDivider(),
                  _eraMenuRow(
                    region,
                    areaForRegion(region)?.name ?? 'Unentdeckt',
                    region == currentRegion,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The rule between two era rows — inset and thicker, not edge to edge
  /// (user 2026-09-01: "die Trennstriche im era panel so machen wie bei
  /// Management"), same shape as [ParchmentDivider] but at THIS panel's own
  /// inset (18/16, clearing the band) rather than [ParchmentPage
  /// .kParchmentPagePad] — a page's own margin, which this narrower dropdown
  /// does not share — and in the ink every other line on this dark band
  /// already uses, rather than [ParchmentDivider]'s parchment-page [FoE
  /// .border].
  Widget _eraDivider() => Padding(
    // 38/36, not 26/24 (user 2026-09-06: the band widened from a 4px
    // inset/14px width to building_detail_dialog.dart's 14px inset/16px
    // width) — same +8/+8 breathing room past the band's new edge that
    // 26/24 gave it past the old one (user 2026-09-01: "die Trennstriche
    // sollen nicht ganz bis zum Mäanderband gehen").
    padding: const EdgeInsets.fromLTRB(38, 0, 36, 0),
    child: Container(height: 2, color: kParchmentInk.withValues(alpha: 0.13)),
  );

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
    message:
        'Not saved — it will retry automatically.\n'
        'Your progress is kept locally.',
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 4),
    child: Container(
      constraints: const BoxConstraints(minHeight: FoE.tapTarget),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: const Icon(
        Icons.cloud_off_rounded,
        color: Colors.orangeAccent,
        size: 20,
      ),
    ),
  );

  /// THE SAME SHEET as Notifications, the Bag, the Build menu — a centred
  /// [ParchmentDialog] (user 2026-09-05: "dieses Menü soll genau gleich
  /// aufgemaut sein wie der Gebäude detailscreen. Notifications ebenfalls",
  /// then 2026-09-06: "todays goals soll auch so aufgebaut sein" and "what
  /// happend [the bell] soll genau so gestaltet sein ... wie todays goals").
  void _showDailyTasks() => showDialog<void>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final tasks = _ctrl.dailyTasks.tasks;
        return ParchmentDialog(
          title: 'Today\'s goals',
          child: SingleChildScrollView(
            // +12/+12 (2026-09-06): ParchmentDialog's own bands widened by
            // that on each side.
            padding: const EdgeInsets.fromLTRB(38, 12, 38, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Three fresh goals every day — small rewards for playing '
                  'a round of everything.',
                  style: FoE.dim(
                    size: 11,
                  ).copyWith(color: ParchmentSheet.inkSoft),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < tasks.length; i++)
                  _dailyTaskRow(i, tasks[i], setLocal),
              ],
            ),
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
      // Same recess Notifications' own rows sit in (ParchmentSheet.card),
      // not a second, differently-tinted panel (user 2026-09-05: "genau
      // gleich aufgemaut wie der Gebäude detailscreen. Notifications
      // ebenfalls").
      decoration: ParchmentSheet.card,
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
                style: FoE.label(
                  size: 12,
                ).copyWith(color: t.claimable ? FoE.gold : FoE.textMuted),
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
    final era = _ctrl.dungeonMaxStage;
    // Eight cells while a refinery is unlocked but its era has not arrived —
    // see [_eraResources]. Every cell is an Expanded, so the row still fits.

    return Padding(
      // 30/28, not 18/16 (user 2026-09-06: the band widened from a 4px
      // inset/14px width to building_detail_dialog.dart's 14px inset/16px
      // width) — clears the strip's own 14 + 16 px reach so the first and
      // last cell's icons don't sit half under it.
      padding: const EdgeInsets.fromLTRB(30, 0, 28, 5),
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
      for (final g in buildGoodsOfRegion(era))
        (id: g.id, emoji: g.emoji, name: g.name),
    // Right after the build pair, because that is what it IS — a build
    // material, one region early.
    for (final g in _previewedGoods(era, cleared))
      (id: g.id, emoji: g.emoji, name: g.name),
    for (final g in luxuriesOfRegion(era))
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
      if (!g.isElement || g.regionOrder <= era) continue;
      // Null = no node gates a producer, so the material arrives with its
      // region — the rule the strip already follows, not a preview.
      final at = producerUnlockBattle(g.id);
      if (at == null || cleared < at) continue;
      out.add(g);
    }
    out.sort((a, b) => a.regionOrder.compareTo(b.regionOrder));
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
      resourceId: resourceId,
      emoji: emoji,
      title: title,
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
          // UI colour, not the resource's own tint (user 2026-09-12, undoing
          // 2026-08-31's "die Icons passend einfärben" — now reads as noise
          // rather than variety once every header cell's badge fights for
          // attention in its own hue). Matches the target cards' own cream/tan
          // treatment (see expeditions_screen.dart's _targetCard).
          iconColor: FoE.gold,
          value: _short(amount),
          sub: over
              ? 'over ${_short(cap)}'
              : full
              ? 'full'
              : '${losing ? '' : '+'}${rate.toStringAsFixed(digits)}/h',
          // Coral for AT or OVER the cap (user 2026-09-06: "wenn ein Maximum
          // erreicht wurde, dies bitte in der Farbe Koralle darstellen") —
          // one colour for both, since [over] used to fall through this
          // chain with no colour of its own at all.
          subColor: losing
              ? FoE.danger
              : (full || over)
              ? FoE.coral
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
    Color? iconColor,
    Color? valueColor,
    Color? subColor,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Fixed box, not a bare Text: color emoji render through a fallback
      // system font whose glyph bitmap sits taller than the line height
      // Flutter computes from Outfit's own metrics at this size, so an
      // unconstrained emoji bled down and overwrote the value below it
      // (user 2026-08-31: "Die Icons werden überschrieben").
      //
      // The badge behind it is the resource's own colour at low strength
      // (user 2026-08-31: "die Icons passend einfärben") — the glyph itself
      // is a baked-colour emoji font, immune to TextStyle.color, so the tint
      // has to live on something behind it instead.
      SizedBox(
        height: _kHeaderIconSize + 4,
        child: Center(
          child: Container(
            width: _kHeaderIconSize + 8,
            height: _kHeaderIconSize + 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (iconColor ?? const Color(0xFF8B95A5)).withValues(
                alpha: 0.16,
              ),
            ),
            child: Center(
              child: Text(
                emoji,
                style: const TextStyle(fontSize: _kHeaderIconSize),
              ),
            ),
          ),
        ),
      ),
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
      // Its own screen now (2026-09-11) — Housing left Management for the
      // same door every sheltering building opens it through.
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HousingScreen()),
      ),
      child: _cellBody(
        emoji: '🛏',
        iconColor: FoE.gold,
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
  Widget _eraMenuRow(int region, String name, bool current) {
    final items = <({String id, String emoji, String name})>[
      ..._eraResources(region),
    ];
    return Container(
      width: double.infinity,
      // 30 on the right too, matching the left column's own SizedBox(30)
      // clearance below — the panel's own meander strips now reach the same
      // 14-30 span on both sides (widened from 4-18, user 2026-09-06), so a
      // bare 16 let a wide chip row's right edge sit half under the band
      // (user 2026-09-05: "schauen, dass es keine Kollisionen gibt ... in
      // die Mitte schieben").
      padding: const EdgeInsets.fromLTRB(0, 8, 30, 8),
      // NO fill, and no border of its own any more (user 2026-08-31: "lass
      // den grünen halbtransparenten Schatten/Box [weg]"; 2026-09-01: "die
      // Trennstriche im era panel so machen wie bei Management") — the
      // left accent bar alone says which era this is, and the rule
      // between rows is [_eraDivider], drawn once by [_erasPanel] between
      // rows rather than as each row's own full-bleed top border.
      // The accent bar moved OFF the container's own edge (user 2026-08-31:
      // "damit der vertikale grüne Strich rechts von dem Band Platz hat")
      // — it used to sit at x 0-3, AHEAD of where the band itself starts
      // (x 4-18); now it sits just past the band, with the text pushed
      // further right again to clear it in turn. IntrinsicHeight so the
      // accent bar (a fixed-width, unconstrained-height Container) can
      // stretch to match the text/chip column's own height.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 30), // clears the band
            Container(
              width: 3,
              color: current ? FoE.positive : Colors.transparent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // No icon, no dot (user 2026-08-31: "überall die
                      // Icons streichen und den Punkt zwischen Zahl und
                      // Text") — the roman numeral and the region's name,
                      // plainly.
                      Expanded(
                        child: Text(
                          '${_roman(region)}  $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.label(size: 11).copyWith(
                            color: current ? FoE.positive : FoE.parchment,
                            fontWeight: current
                                ? FontWeight.w700
                                : FontWeight.w400,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _eraChip(String id, String emoji, String name) {
    final amount = _amountOf(id);
    final has = amount > 0;
    return InkWell(
      onTap: () {
        // Close the DROPDOWN, not the route (2026-09-01 fix: "wenn ich eine
        // Ressource beim era panel anklicke und ... auf den zurückbutton
        // drücke, kommt ein blackscreen"). The eras panel is inline now
        // (_erasCtrl + _erasOpen), not the popup its own history once was —
        // this Navigator.pop() was a leftover from back when it WAS one, and
        // since SettlementScreen is the app's root route, popping it here
        // quietly emptied the Navigator's history. Pushing
        // ResourceDetailScreen straight after papered over it (there was
        // still a route to push onto), until backing OUT of that screen had
        // nothing valid left underneath it.
        _closeEras();
        _showResourceBreakdown(resourceId: id, emoji: emoji, title: name);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: ShapeDecoration(
          // An era you have not reached holds nothing, and its chips say so by
          // fading rather than by disappearing — the ladder stays readable.
          color: kParchmentInk.withValues(alpha: has ? 0.07 : 0.03),
          shape: FoE.facet(
            radius: 8,
            side: BorderSide(
              color: kParchmentInk.withValues(alpha: has ? 0.20 : 0.10),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text(
              _short(amount),
              style: FoE.value(
                size: 10,
              ).copyWith(color: has ? FoE.parchment : FoE.textMuted),
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
        child: _cellBody(
          emoji: '⚡',
          iconColor: FoE.gold,
          value: '—',
          sub: '',
        ),
      );
    }
    // Energy is a daily-steps RATE now (user 2026-09-14), not a draining
    // pool with an hours-until-empty countdown — [energy.percent] is already
    // exactly current, no live extrapolation needed. Red only at the floor
    // (0 steps today yet): everything above that is a real, working rate,
    // just not a boosted one.
    final atFloor = energy.stepsToday <= 0;
    return _headerCell(
      onTap: _showEnergyOverview,
      // Ink, not white: the strip is a LIT PARCHMENT band now, and white on
      // cream is a number you cannot read.
      child: _cellBody(
        emoji: '⚡',
        iconColor: FoE.gold,
        value: '${energy.percent.round()}%',
        sub: '${energy.stepsToday} steps',
        valueColor: atFloor ? FoE.danger : null,
        subColor: atFloor ? FoE.danger : null,
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
  ///
  /// ICON-ONLY, and deliberately unshowy (user 2026-08-31: "nur als icon
  /// jeweils, dafür deutlich kleiner, dass alle nebeneinander Platz haben.
  /// Diese sollen nicht auffallen, da sie später so oder so gelöscht
  /// werden") — three small glyphs side by side rather than a labelled,
  /// gold-on-dark row that reads as a real feature of the screen.
  Widget _debugRow() {
    if (!_ctrl.isDev) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Gold gates nothing (it only ever removes waiting) and wood/stone
        // are what every build costs, so a thousand of each costs no
        // balance — it just means a building under test doesn't wait on a
        // gather trip.
        _debugBtn(
          '🪙',
          () => _ctrl.grantResources({
            'gold': kDevResetFloat,
            'wood': kDevResetFloat,
            'stone': kDevResetFloat,
          }),
        ),
        const SizedBox(width: 4),
        _debugBtn('🔄', _confirmReset),
        const SizedBox(width: 4),
        _debugBtn('🛠', _showDevMode),
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
                  Pressable(
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
                  Pressable(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: ShapeDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.4),
                        shape: FoE.facet(
                          radius: 6,
                          side: BorderSide(color: Colors.red.shade700),
                        ),
                      ),
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

  Widget _debugBtn(String emoji, VoidCallback onTap) => Pressable(
    onTap: onTap,
    child: Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: const Color(0xFF1A1206).withValues(alpha: 0.6),
        shape: FoE.facet(
          radius: 4,
          side: BorderSide(color: FoE.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 10)),
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
  Widget _quickPad() {
    final solo = _soloQuickPadAnchor;
    // Only the CURRENT step's own tile carries the anchor (user 2026-09-02:
    // "Nur der jeweilige Button soll aktiv und markiert sein") — an earlier
    // hand-off's tile still SHOWS (see below), it just isn't the hole any
    // more, so the spotlight scrim dims and dead-zones it like everything
    // else that isn't the one lit control right now.
    final monsters = QuickPadItem(
      Icons.pets,
      'Monsters',
      _showCreatures,
      anchorKey: solo == 'quick-monsters'
          ? IntroSpotlightAnchors.of('quick-monsters')
          : null,
    );
    final map = QuickPadItem(
      Icons.map,
      'Map',
      _showOverworld,
      anchorKey: solo == 'quick-map'
          ? IntroSpotlightAnchors.of('quick-map')
          : null,
    );
    final build = QuickPadItem(
      Icons.construction,
      'Build',
      _showBuildMenu,
      anchorKey: solo == 'quick-build'
          ? IntroSpotlightAnchors.of('quick-build')
          : null,
    );
    // Reduced to whichever tiles are unlocked so far — the CURRENT step's
    // own target plus any earlier solo hand-off's tile, which stays around
    // rather than disappearing again (user 2026-09-02: "der Monsterbutton
    // soll auch bereits angezeigt werden, da dieser bereits benutzt
    // wurde").
    if (solo != null) {
      return QuickPad(
        items: [
          if (_monstersUnlocked) monsters,
          if (_mapUnlocked) map,
          if (_buildUnlocked) build,
        ],
      );
    }
    // No button at all until it is the one actually being used (user
    // 2026-09-02: "Zum Start soll noch gar kein Button ersichtlich sein ...
    // Die Buttons erscheinen erst dann, wenn sie benutzt werden"). While the
    // intro card itself is the spotlighted control (every step except the
    // solo hand-offs above), its own CTA is the only way forward — the
    // quick menu isn't the mechanism yet, so it stays off rather than
    // sitting there dimmed and dead behind the scrim.
    if (_ctrl.introStep.isActive) return const SizedBox.shrink();
    return QuickPad(
      items: [
        QuickPadItem(Icons.construction, 'Build', _showBuildMenu),
        map,
        monsters,
        // The Management hub: what is out on the road, who works where, and
        // the housing budget. Research used to be a key here — the overworld
        // IS research now (techs are places on it), so it would have been
        // two doors into one room.
        QuickPadItem(Icons.assignment, 'Manage', _showManagement),
        QuickPadItem(Icons.group, 'Social', _showSocial),
        QuickPadItem(
          Icons.backpack,
          'Bag',
          () => openBag(context),
          // NEW items, not the total held (user 2026-08-29) — a badge that
          // always shows "how many things you own" never goes away, which is
          // not what a badge is for. Clears the moment the Bag opens; see
          // NewItems and BagScreen.
          badge: NewItems().total,
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
}

/// The wave's silhouette (user 2026-09-07: "der Headerbutton soll mittig
/// sein und auf beide Seiten auslaufen", then "einmal konvex und einmal
/// konkav vom Rand bis zur Mitte... Aktuell hat es noch eine Ecke, diese
/// muss auch geschwungen werden"): flush with the header along the top and
/// the two vertical ends, THIN at both edges ([waveMin] deep), flowing up
/// through one true ogee on each side — a convex arc straight off the
/// vertical edge, then a concave arc into a centred plateau at [waveMax]
/// deep — the two sides are exact mirrors of each other.
Path _eraWavePath(Size size, double waveMin, double waveMax, double taper) {
  final w = size.width;
  final tw = w * taper;
  final leftDeepX = tw;
  final rightDeepX = w - tw;
  // How deep the curve's single inflection point sits — not used as a
  // literal path vertex, only to place the control points that give it a
  // vertical tangent at the edge and a horizontal one at the plateau.
  final midDepth = waveMin + (waveMax - waveMin) * 0.7;
  return Path()
    ..moveTo(0, 0)
    ..lineTo(0, waveMin)
    // Control point 1 shares the START's x (0) — the curve leaves the
    // straight edge travelling STRAIGHT DOWN, so the two meet with no kink,
    // the corner the earlier "ease" version still had. Control point 2
    // shares the END's y (waveMax) — the curve arrives at the plateau
    // travelling level, same as before. One cubic, one inflection: convex
    // first, concave second.
    ..cubicTo(0, midDepth, tw * 0.5, waveMax, leftDeepX, waveMax)
    ..lineTo(rightDeepX, waveMax)
    ..cubicTo(w - tw * 0.5, waveMax, w, midDepth, w, waveMin)
    ..lineTo(w, 0)
    ..close();
}

class _EraWavePainter extends CustomPainter {
  final double waveMin;
  final double waveMax;
  final double taper;
  final BoxShadow shadow;
  const _EraWavePainter({
    required this.waveMin,
    required this.waveMax,
    required this.taper,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = _eraWavePath(size, waveMin, waveMax, taper);
    canvas.drawPath(path.shift(shadow.offset), Paint()..color = shadow.color);
    canvas.drawPath(path, Paint()..color = FoE.bg);
  }

  @override
  bool shouldRepaint(covariant _EraWavePainter old) =>
      old.waveMin != waveMin ||
      old.waveMax != waveMax ||
      old.taper != taper ||
      old.shadow != shadow;
}
