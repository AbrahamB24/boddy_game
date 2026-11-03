import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Warms the picture's BYTES without decoding it — see
// [_warmNetworkArtInBackground] for why a decode-based precache was worse
// than no precache at all.
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/ui/feel.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/monster_sheet.dart' show precacheMonsterSheets;
import 'data/road_tiles.dart' show roadAsset, kRoadDecodeWidth;
import 'data/resource_icons.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/fachwerk.dart';
import '../../core/ui/duration_format.dart';
import '../../core/ui/number_format.dart';
import '../creatures/models/species_def.dart' show kSpeciesDefs;
import 'data/building_art.dart'
    show kBundledBuildingArt, artBoxOf, buildingAsset;
import 'data/iso_grid.dart' show artPlacement, isoLocalBounds;
import 'data/building_model.dart' show animFor;
import 'widgets/animated_building_art.dart' show AnimatedBuildingArt;
import 'widgets/building_icon.dart' show BuildingIcon, BuildingGroundShadow;
import 'data/building_definitions.dart';
import 'data/goods_definitions.dart';
import 'data/item_definitions.dart' show kItemDefs;
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
import 'widgets/building_carousel.dart';
import 'energy_screen.dart';
import 'bag_screen.dart';
import 'profile_screen.dart';
import 'resource_detail_screen.dart';
import 'widgets/quick_pad.dart';
import 'resources_screen.dart';
import 'widgets/settlement_map.dart';
import 'widgets/terrain_layer.dart';
import '../common/events/game_events.dart';
import '../common/widgets/parchment_page.dart';
import '../common/events/notification_button.dart'
    show NotificationBadge, gameEventHasDestination, openGameEvent;
import 'widgets/trips_status_builder.dart';
import '../creatures/collection_screen.dart';
import 'build_menu_request.dart';
import 'work_screen.dart';
import 'management_screen.dart';
import '../creatures/expeditions_screen.dart';
import '../creatures/models/creature_enums.dart' show kHealingHutBuildingId;
import '../creatures/overworld_screen.dart';
import '../onboarding/intro_card_panel.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../../core/ui/pressable.dart';
import '../social/social_screen.dart';
import '../social/services/message_notifier.dart';
import '../social/services/pvp_notifier.dart';
import '../../core/theme/voxel_kit.dart';
import '../../core/theme/voxel_icons.dart';

/// How many background art downloads run at once — see
/// [_SettlementScreenState._warmNetworkArtInBackground].
const int _kWarmDownloadWorkers = 4;

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with WidgetsBindingObserver {
  final _ctrl = SettlementController();
  // Lets the tutorial's CTAs open a building's dialog directly (heal step,
  // assign step) instead of asking a brand-new player to find it on the map.
  final _mapKey = GlobalKey<SettlementMapState>();
  String? _pendingTypeId;
  bool _editMode = false;

  /// Which of edit mode's two doors is open (user 2026-09-22) — see
  /// [SettlementMap.persistentEditMode]'s own doc comment for what this
  /// changes. False whenever [_editMode] was set true by a long-press
  /// (single-shot: one move, then leaves on its own); true only for
  /// [_enterLayoutMode] (the Build menu's own right-edge button — Umbaumodus proper,
  /// including "Alle Gebäude zurücknehmen").
  bool _editModePersistent = false;

  /// True the instant the map starts aiming something and false the instant
  /// that ghost is gone, confirmed or cancelled (user 2026-09-22, via
  /// [SettlementMap.onAimingChanged]) — the tray carousel (see
  /// [_showTrayCarousel]) has to get out of the way while the player is
  /// actually positioning a ghost, the same way it already hides itself
  /// while a brand-new purchase is being aimed.
  bool _trayAiming = false;

  /// The tray card the player just tapped, handed to [SettlementMap] as
  /// [SettlementMap.selectBuildingId] — its own existing "aim THIS specific
  /// building" door (see that prop's doc comment), reused rather than
  /// reinvented for Umbaumodus's tray (user 2026-09-22). Reset the moment
  /// aiming ends, so tapping the same or another tray card again is always
  /// a fresh value change.
  String? _selectTrayBuildingId;

  bool _roadMode = false;

  // Whether the player has opened the build carousel (user 2026-09-18: "das
  // Baumenü soll nicht immer offen sein, sondern nur wenn ich es öffne").
  // Toggled by the quick pad's Build tile, closed again once a building or the
  // road tool is picked. Ignored while the tutorial runs — see
  // [_showBuildCarousel].
  bool _buildOpen = false;

  // The header's resources dropdown (user 2026-09-30: "wie früher eine Art
  // Hovermenü... öffnet nach unten... nur so weit... wie aktuell Ressourcen
  // freigeschalten sind"). Toggled by the tab under the header; closes on a
  // tap anywhere else — see [_resourcesDropdown].
  bool _resourcesOpen = false;

  // The category a page other than the map asked the strip to open on (Work's
  // "Build a house"); null = wherever the strip was. See [BuildMenuRequest].
  BuildingCategory? _requestedCategory;

  void _onBuildRequest() {
    if (!mounted) return;
    setState(() {
      _requestedCategory = BuildMenuRequest.category;
      _buildOpen = true;
      _editMode = false;
      _editModePersistent = false;
      _roadMode = false;
      _pendingTypeId = null;
    });
  }

  // Where/when the current touch on the map began — lets the map's tap-to-close
  // Listener tell a tap from the start of a pan (see [_layout]).
  Offset? _mapTapDownPos;
  Duration? _mapTapDownAt;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _ctrl.addListener(_rebuild);
    NewItems().addListener(_rebuild);
    PvpNotifier.instance.addListener(_rebuild);
    MessageNotifier.instance.addListener(_rebuild);
    BuildMenuRequest.requests.addListener(_onBuildRequest);
    // Real step counter: watches the hardware sensor and credits steps as
    // energy automatically (user 2026-07-18).
    StepTrackerService().start();
    _bootstrap();
  }

  /// True once every picture the game's first frame (or a moment later) could
  /// need has actually finished decoding — [_loading] stays up until then, see
  /// [build].
  bool _assetsReady = false;

  /// 0.0–1.0 through [_bootstrap] — drives the loading screen's progress bar
  /// (user 2026-10-04: "kannst du das nicht beim Öffnen der App mit einem
  /// Ladebalken machen"). Weighted by wall-clock share, not item count: the
  /// network load (`_ctrl.load()`) is the slow half, the local
  /// precache+terrain pass is the other half, and within that pass each
  /// future bumps the bar by its own even slice as it finishes — so the bar
  /// actually tracks real work instead of just ticking up on a timer.
  double _progress = 0.0;

  /// True once the real map has had a few real frames to actually PAINT
  /// while still hidden behind [_loading] — see [_warmPaintPipeline]. Stays
  /// false the instant data arrives so [build] can mount the real [_layout]
  /// (invisibly) well before this flips, which is the whole point: the GPU
  /// pays its one-time pipeline-compile cost for the map's custom painters
  /// and blend modes HERE, not on the player's first real pan.
  bool _paintWarmed = false;

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
    setState(() => _progress = 0.5);
    final local = <Future<void>>[];
    // AT THE WIDTH THE MAP WILL ASK FOR, not at the asset's own (2026-09-21).
    // `precacheImage(AssetImage(asset))` decoded every bundled render at its
    // full ~960 px and filed it under the bare AssetImage key — but the map
    // draws through [BuildingIcon], which caps the decode with `cacheWidth`
    // and therefore resolves a `ResizeImage(AssetImage(...), width: …)`. Two
    // different ImageCache keys: the loading screen blocked on a decode of
    // every bundled building that nothing would ever read, and then the map
    // decoded all of them AGAIN on its first paint. Worse, the full-size
    // copies sat in the cache evicting the capped ones the map actually
    // draws — the exact eviction-and-redecode-on-every-pan that
    // BuildingIcon's own cap exists to prevent.
    //
    // Every bundled render PLUS every building actually standing on this
    // map, bundled or not (user 2026-11-03: "alle Assets beim Ladescreen
    // vorladen, damit im Anschluss alles flüssig läuft") — a placed building
    // on uploaded art used to pop in a moment after the map appeared, and
    // its ground shadow (measured from the picture) a moment after that.
    // Keyed by the PICTURE (artId): a building that stands turned on this
    // map (user 2026-11-03) is drawn from its turned render, so that is
    // the one to warm.
    final mapDefs = <String, BuildingDef>{};
    for (final id in {
      ...kBundledBuildingArt,
      for (final b in _ctrl.buildings) b.buildingTypeId,
    }) {
      final d = kBuildingDefs[id];
      if (d != null) mapDefs[d.artId] = d;
    }
    for (final b in _ctrl.buildings) {
      final d = placedDefOf(b);
      if (d != null) mapDefs[d.artId] = d;
    }
    for (final def in mapDefs.values) {
      if (def.isRoad) continue;
      final id = def.artId;
      // The same number settlement_map's _BuildingTile passes as `width`.
      final box = artBoxOf(def);
      final artWidth = artPlacement(
        isoLocalBounds(def.gridW, def.gridH),
        baseWidth: box.baseWidth,
        anchorX: box.anchorX,
        lift: box.lift,
      ).width;
      final provider = BuildingIcon.providerFor(
        context,
        id,
        artWidth,
        imageUrl: def.imageUrl,
      );
      if (provider != null) local.add(precacheImage(provider, context));
      // A building that MOVES on the map draws its cut-out base and its
      // atlas there, not the still picture above.
      if (animFor(id, def.gridW, def.gridH) case final spec?) {
        local
          ..add(
            precacheImage(
              AnimatedBuildingArt.baseProvider(context, id, spec, artWidth),
              context,
            ),
          )
          ..add(precacheImage(AnimatedBuildingArt.atlasProvider(id), context));
      }
      if (!def.isBuildPlot) {
        local.add(
          BuildingGroundShadow.preload(defId: id, imageUrl: def.imageUrl),
        );
      }
    }
    // Road junction tiles, at the exact cap the map's road cells and the
    // road ghost decode them with (cacheWidth 256), plus the build menu's
    // uncapped straight piece.
    for (var mask = 0; mask < 16; mask++) {
      local.add(
        precacheImage(
          ResizeImage(AssetImage(roadAsset(mask)), width: kRoadDecodeWidth),
          context,
        ),
      );
    }
    local.add(precacheImage(AssetImage(roadAsset(15)), context));
    // The animated monster sheets every list and
    // battle draws from, the sound effects and music, and the one runtime
    // font (Outfit, used by the creature detail screen) — so the first
    // visit to any of them is as smooth as the tenth.
    local.add(precacheMonsterSheets());
    local.add(Feel.preloadClips());
    local.add(_preloadFonts());
    local.add(_preloadOwnMonsterArt());
    // The map's ground too: its art and its terrain (shore, forest, props)
    // are worked out here, behind the loading screen and off the UI thread,
    // rather than on the map's first paint. Never throws — see preload.
    local.add(TerrainLayer.preload(_ctrl.buildableRegion));
    // One broken asset must not hang the loading screen forever. Each future
    // still bumps the bar on completion even when it errors, via
    // catchError-then-whenComplete — a single stuck image must not freeze
    // the bar just short of full.
    final bump = local.isEmpty ? 0.0 : 0.5 / local.length;
    await Future.wait(
      local.map(
        // Capped too: a placed building's uploaded picture now loads here,
        // and a stalled download must not hold the bar short of full.
        // `then<void>` first: several of these are really a
        // Future<List<void>> (a Future.wait), and `timeout`'s onTimeout must
        // return the future's OWN type — on web a `() {}` against a
        // List-typed future is a runtime type error that froze the bar.
        (f) => f
            .then<void>((_) {})
            .timeout(const Duration(seconds: 15), onTimeout: () {})
            .catchError((_) {})
            .whenComplete(() {
              if (mounted) setState(() => _progress += bump);
            }),
      ),
    );
    if (!mounted) return;
    setState(() => _assetsReady = true);
    // [build] has been mounting the real map, invisibly, since [dataReady]
    // went true above — this just gives the engine a few real frames to
    // actually rasterize it before the bar comes down. See
    // [_warmPaintPipeline].
    await _warmPaintPipeline();
    if (!mounted) return;
    setState(() => _paintWarmed = true);
    _warmNetworkArtInBackground();
  }

  /// Three real frames, forced even if nothing would otherwise invalidate —
  /// see [WidgetsBinding.endOfFrame] (user 2026-10-04: "beim Öffnen... damit
  /// alles super flüssig läuft").
  ///
  /// [precacheImage] only decodes a bitmap into a texture; it never asks the
  /// GPU to actually DRAW with it. The map's first real paint also drives a
  /// handful of CustomPainters (grid, footprints, cast shadows) and
  /// `ColorFilter.mode(..., BlendMode.srcIn)` tinting in [BuildingIcon] —
  /// each a distinct draw-op/shader combination the GPU backend compiles and
  /// links the FIRST time it is actually used, not when its source image is
  /// merely decoded. On a weak Android phone that compile is the stutter the
  /// player sees right as the map appears and for the first second of
  /// panning — precaching pictures never touched it.
  ///
  /// Forcing that paint to happen now, while [_layout] is mounted but still
  /// hidden under [_loading] (see [build]), moves the cost here instead.
  /// Three frames rather than one: the map's own async bits (terrain data
  /// arriving, an image decode finishing) can each trigger their own
  /// follow-up repaint a frame later, and those still need to land before
  /// the bar comes down for this to have been worth doing.
  Future<void> _warmPaintPipeline() async {
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Everything that needs the network, fired AFTER the game is already
  /// showing — see [_bootstrap]. Fire-and-forget: nothing awaits this, it
  /// just warms the cache so the Bestiary/battle/build-menu don't hit a cold
  /// fetch the first time they draw a picture this save hasn't needed yet.
  ///
  /// IT DOWNLOADS, IT DOES NOT DECODE (2026-09-21). This used to call
  /// `precacheImage`, which decodes — roughly 300 pictures at their FULL
  /// native resolution, all at once, in the seconds right after the map
  /// appears. Not one of those decodes was ever read: both widgets that draw
  /// this art cap the decode ([BuildingIcon] with `memCacheWidth`,
  /// [CreatureSprite] with `memCacheWidth`/`cacheWidth`), so both resolve a
  /// `ResizeImage(provider, width: …)` whose ImageCache key is a different
  /// key from the bare provider's. The full-size copies only ever did harm:
  /// they filled the 200 MB budget and evicted the capped entries the map
  /// was actively drawing, which is what turns a pan into a re-decode.
  ///
  /// What the cold-fetch gap is actually made of is the NETWORK, and bytes
  /// on disk are what closes it. [DefaultCacheManager] is the same store
  /// [CachedNetworkImageProvider] reads from, so a file pulled here is a
  /// local read when the widget asks — at zero cost in texture memory.
  ///
  /// Web has no such store (flutter_cache_manager has nowhere durable to
  /// write, which is why [CreatureSprite] skips it there), and the browser
  /// caches the response on the real request anyway. So web warms nothing —
  /// strictly better than spending the CanvasKit heap on decodes that miss.
  void _warmNetworkArtInBackground() {
    if (kIsWeb) return;
    final urls = <String>{};
    // The other ~69 of 89 buildings — no bundled render yet, so their picture
    // is whatever got uploaded in Dev Mode (BuildingDef.imageUrl). Bundled
    // wins over imageUrl (see data/building_art.dart), so skip a building
    // already covered by [_bootstrap] rather than fetch a picture nothing
    // ever draws.
    for (final def in kBuildingDefs.values) {
      final url = def.imageUrl;
      if (url != null && url.isNotEmpty && buildingAsset(def.id) == null) {
        urls.add(url);
      }
    }
    for (final species in kSpeciesDefs.values) {
      for (final stage in species.stages) {
        final front = stage.imageUrl;
        final back = stage.backImageUrl;
        if (front != null && front.isNotEmpty) urls.add(front);
        if (back != null && back.isNotEmpty) urls.add(back);
      }
    }
    // A FEW AT A TIME, not all ~300 at once. Firing every download in the same
    // tick opened hundreds of sockets and held hundreds of response bodies in
    // memory in the very seconds the map is first drawing — on a weak phone
    // that is the wrong moment to be spending either. Four workers drain the
    // queue; the cache ends up in the same state, just without the spike.
    _downloadArt(urls);
  }

  /// Pulls [urls] into the disk cache [CachedNetworkImageProvider] reads from,
  /// [_kWarmDownloadWorkers] at a time. Completes when the queue is drained.
  ///
  /// A FEW AT A TIME, not all at once. Firing every download in the same tick
  /// opened hundreds of sockets and held hundreds of response bodies in memory
  /// in the very seconds the map is first drawing — on a weak phone that is
  /// the wrong moment to be spending either.
  Future<void> _downloadArt(Iterable<String> urls) {
    final cache = DefaultCacheManager();
    final queue = urls.toList();
    Future<void> worker() async {
      while (mounted && queue.isNotEmpty) {
        // A picture that will not download is not an error here — the widget
        // that needs it has its own placeholder and its own retry.
        try {
          await cache.downloadFile(queue.removeLast());
        } catch (_) {}
      }
    }

    return Future.wait([
      for (var i = 0; i < _kWarmDownloadWorkers; i++) worker(),
    ]).then<void>((_) {});
  }

  /// The player's OWN monsters' art, every stage, front and back — what the
  /// Monsters tab, the team picker and every battle draw first. Fetched
  /// behind the loading bar (user 2026-11-03: "alle Assets beim Ladescreen
  /// vorladen") but capped in time: a slow connection must never hold the
  /// front door shut. On disk after the first launch, so later launches pass
  /// straight through. Web has no such store; the browser caches the real
  /// request instead (see [_warmNetworkArtInBackground]).
  Future<void> _preloadOwnMonsterArt() {
    if (kIsWeb) return Future.value();
    final urls = <String>{};
    for (final c in CreaturesController().creatures) {
      final species = c.species;
      if (species == null) continue;
      for (final stage in species.stages) {
        final front = stage.imageUrl;
        final back = stage.backImageUrl;
        if (front != null && front.isNotEmpty) urls.add(front);
        if (back != null && back.isNotEmpty) urls.add(back);
      }
    }
    if (urls.isEmpty) return Future.value();
    return _downloadArt(
      urls,
    ).then<void>((_) {}).timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  /// Outfit, the one face still fetched at runtime (bundled in assets/fonts/,
  /// but google_fonts only loads a weight the first time a style asks for
  /// it — a relayout on the creature detail screen's first open).
  Future<void> _preloadFonts() async {
    try {
      GoogleFonts.outfit();
      GoogleFonts.outfit(fontWeight: FontWeight.w600);
      GoogleFonts.outfit(fontWeight: FontWeight.w700);
      GoogleFonts.outfit(fontWeight: FontWeight.w800);
      await GoogleFonts.pendingFonts();
    } catch (_) {}
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.removeListener(_rebuild);
    NewItems().removeListener(_rebuild);
    PvpNotifier.instance.removeListener(_rebuild);
    MessageNotifier.instance.removeListener(_rebuild);
    BuildMenuRequest.requests.removeListener(_onBuildRequest);
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
  // The menus below are laid OVER the map (see [pushMenu]) rather than
  // replacing it.
  void _showExpeditions() => pushMenu(context, const ExpeditionsScreen());

  void _showCreatures() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CollectionScreen()),
  );

  void _showManagement() => pushMenu(context, const ManagementScreen());

  void _showSocial() => pushMenu(context, const SocialScreen());

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

  void _showProfile() => pushMenu(
    context,
    ProfileScreen(onOpenDevMode: _ctrl.isDev ? _showDevMode : null),
  );

  /// Opens Build and applies whatever the player picked.
  /// Hands the building to the MAP to be aimed (user 2026-08-09: "Wenn ich ein
  /// Gebäude ausgewählt habe, dann erscheint es mittig im Screen … Über dem
  /// Gebäude gibt es ein gutzeichen und ein X"). Called directly by the
  /// bottom [BuildingCarousel]'s card taps now (2026-09-18) — there is no
  /// longer a pushed Build menu route to await a result from.
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
  void _buildAndPlace(String typeId) {
    if (kBuildingDefs[typeId] == null) return;
    setState(() {
      _pendingTypeId = typeId;
      _editMode = false;
      _editModePersistent = false;
      _roadMode = false;
      _buildOpen = false;
    });
  }

  /// Long-pressing a building on the map is a SINGLE-SHOT errand (user
  /// 2026-09-22: "wenn ich lange auf ein Gebäude drücke, [soll] ich nur
  /// dieses [verschieben] … nach dem Platzieren [wird] der Modus verlassen"):
  /// it picks that one building up, and [SettlementMap] itself leaves edit
  /// mode again the moment the move confirms — see
  /// [SettlementMap.persistentEditMode]. Rearranging several buildings (or
  /// the FoE-style "take the whole city back") now lives in
  /// [_enterLayoutMode], its own door into the same mode.
  void _enterEditMode() => setState(() {
    _editMode = true;
    _editModePersistent = false;
    _roadMode = false;
    _pendingTypeId = null;
  });

  /// Umbaumodus proper (user 2026-09-22): opened from the Build menu's own
  /// right-edge button ("ich will über das Baumenü in den Umbaumodus
  /// kommen") rather than by grabbing a specific building, so it has
  /// something to do even before the player has touched anything — namely
  /// "Alle Gebäude zurücknehmen". Ordinary tap-and-move still works exactly
  /// as it always has inside it; this only changes what happens to the
  /// SESSION once a move confirms (see [SettlementMap.persistentEditMode]):
  /// it stays open.
  void _enterLayoutMode() => setState(() {
    _editMode = true;
    _editModePersistent = true;
    _roadMode = false;
    _pendingTypeId = null;
    _buildOpen = false;
  });

  void _enterRoadMode() => setState(() {
    _roadMode = true;
    _editMode = false;
    _editModePersistent = false;
    _pendingTypeId = null;
    _buildOpen = false;
  });

  void _showEnergyOverview() => pushMenu(context, const EnergyScreen());

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

  /// The header band, measured — the map's top edge is wherever it ends.
  final _headerKey = GlobalKey();

  /// The band's FOLDED height (safe area included); 0 until first measured.
  double _headerH = 0;

  /// Where the map starts. Until the band has been measured, a guess close
  /// enough (safe area + one row of cells) that the first frame is not far off.
  double get _mapTop =>
      _headerH > 0 ? _headerH : MediaQuery.paddingOf(context).top + 56;

  /// Reads the band's height after layout — the map starts where it ends.
  void _measureHeader() {
    if (!mounted) return;
    final box = _headerKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final h = box.size.height;
    if ((h - _headerH).abs() > 0.5) setState(() => _headerH = h);
  }

  /// The header's rounded tab opens the Resources page — every era's shelf (user
  /// 2026-09-22, replacing the eras drop-down).
  void _openResources() => pushMenu(context, const ResourcesScreen());

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Welcome-back digest: queued by load() when the player was away a while;
    // shown exactly once, after this frame so the sheet has a laid-out screen
    // under it.
    final dataReady = !_ctrl.isLoading && _ctrl.error == null;
    final ready = dataReady && _assetsReady && _paintWarmed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
    final digest = _ctrl.pendingDigest;
    if (digest != null && ready) {
      _ctrl.pendingDigest = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showDigest(digest);
      });
    }
    return Scaffold(
      // The map fills this itself; the colour only shows while it loads and
      // behind the edges, so it is the wood ground like every menu (was the
      // navy page tone, which showed blue at the map's edges).
      backgroundColor: CreamPalette.groundBottom,
      body: _ctrl.error != null
          ? _error()
          : Stack(
              // Both children below must fill the screen exactly — a loose
              // fit would let [_loading] shrink-wrap its own small centred
              // column (Stack's default for non-positioned children) and
              // stop covering the real map it exists to hide.
              fit: StackFit.expand,
              children: [
                // Mounted the MOMENT data arrives, well before [ready] —
                // real underneath the still-opaque [_loading] (user
                // 2026-10-04's follow-up: a bare spinner wasn't the only
                // thing making the first moments feel slow; the map's own
                // first paint was janky too). Hidden from touch and from
                // screen readers until it is actually the thing on screen —
                // see [_warmPaintPipeline] for why this is mounted this
                // early at all.
                if (dataReady)
                  IgnorePointer(
                    ignoring: !ready,
                    child: ExcludeSemantics(
                      excluding: !ready,
                      child: _layout(),
                    ),
                  ),
                if (!ready) _loading(),
              ],
            ),
    );
  }

  /// "While you were away" — the passive economy, experienced instead of
  /// silently accrued (user 2026-07-21).
  ///
  /// "Zwei Spalten" (user 2026-09-22): ONE wide cream card in the kit's dialog
  /// shell, the same as every other popup — LEFT what was gathered, RIGHT what
  /// happened. It used to be a narrow portrait box; a landscape screen has the
  /// width for both at once.
  ///
  /// It also reports WHAT HAPPENED, not just what was gathered (user
  /// 2026-07-27): expeditions resolving, eggs hatching, monsters levelling up
  /// and casualties all landed silently in the bell, and the digest just said
  /// "N new events" and left you to go looking.
  ///
  /// It has to carry MANY resources (user 2026-09-22: "wie machen wir es, wenn
  /// ich später etwa 20 Ressourcen bekomme?"): the current era's resources and
  /// gold stand as big tiles; everything else — older eras, whatever else came
  /// in — is a compact run of chips underneath, newest era first. The column
  /// scrolls, so twenty of them are a scroll and not a redirect.
  void _showDigest(WelcomeDigest d) {
    final hours = d.awayHours;
    final awayLabel = hours >= 48
        ? '${(hours / 24).toStringAsFixed(1)} days'
        : hours >= 1.5
        ? '${hours.toStringAsFixed(1)} hours'
        : '${(hours * 60).round()} minutes';
    // EVERYTHING THE BELL WOULD SHOW YOU (user 2026-07-27: "alles was bei den
    // notifications angezeigt wird, soll auch beim while you were away screen
    // sein") — the unread feed, whole and uncut. Reading the same
    // [GameEventLog.unreadEvents] the badge counts makes the two incapable of
    // disagreeing.
    final log = GameEventLog();
    final events = log.unreadEvents;

    // Nothing to report (user 2026-08-27: "wenn bei meiner Abwesenheit
    // nichts nennenswertes passiert ist, dann soll der 'while you were away'
    // screen nicht auftauchen") — an empty gathered list AND an empty event
    // feed means the away period produced nothing worth a whole dialog over.
    // kDigestMinAwayHours already filters trivially SHORT absences; this
    // filters LONG-but-idle ones the same way.
    if (d.gained.isEmpty && events.isEmpty && d.lost.isEmpty) return;

    // Big tiles: this era's own resources and gold. The rest: chips.
    final eraIds = {
      for (final r in _eraResources(
        _ctrl.dungeonMaxStage,
        cleared: _ctrl.battlesCleared,
      ))
        r.id,
      'gold',
    };
    final main = [
      for (final e in d.gained.entries)
        if (eraIds.contains(e.key)) e,
    ];
    final others =
        [
          for (final e in d.gained.entries)
            if (!eraIds.contains(e.key)) e,
        ]..sort(
          (a, b) => (kGoodsDefs[b.key]?.regionOrder ?? 1).compareTo(
            kGoodsDefs[a.key]?.regionOrder ?? 1,
          ),
        );

    Widget tile(MapEntry<String, double> e) => Container(
      width: 138,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      decoration: raisedTile(radius: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(resourceEmoji(e.key), style: const TextStyle(fontSize: 22)),
          Text(
            '+${e.value.toStringAsFixed(0)}',
            style: FoE.value(size: 18).copyWith(color: kBoxInk),
          ),
          Text(
            resourceName(e.key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
          ),
        ],
      ),
    );

    Widget chip(MapEntry<String, double> e) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: raisedTile(radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(resourceEmoji(e.key), style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '+${e.value.toStringAsFixed(0)}',
            style: FoE.value(size: 12).copyWith(color: kBoxInk),
          ),
        ],
      ),
    );

    // What went WRONG while away: stores that stood full (production stops at the
    // ceiling, so that time earned nothing) and an energy pool that ran down.
    final lostEntries = d.lost.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final energyDrop = (d.energyBefore != null && d.energyAfter != null)
        ? d.energyBefore! - d.energyAfter!
        : 0.0;
    Widget notice(String text) => Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: CreamPalette.warn.withValues(alpha: 0.13),
        borderRadius: vr(10),
      ),
      child: Text(
        text,
        style: FoE.label(
          size: 11.5,
        ).copyWith(color: CreamPalette.warn, fontWeight: FontWeight.w700),
      ),
    );
    final notices = <Widget>[
      for (final e in lostEntries.take(4))
        notice(
          '${resourceEmoji(e.key)} ${resourceName(e.key)} was full for '
          '${(d.fullHours[e.key] ?? 0).round()} h · about '
          '${e.value.round()} lost',
        ),
      if (energyDrop >= 10)
        notice(
          (d.energyAfter ?? 0) < 1
              ? '⚡ Energy ran out — production slowed to a crawl'
              : '⚡ Energy fell from ${d.energyBefore!.round()} % to '
                    '${d.energyAfter!.round()} % — production slowed',
        ),
    ];

    final gathered = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _digestHeading('Gathered', kBoxInk),
          const SizedBox(height: 8),
          if (d.gained.isEmpty)
            Text(
              'Nothing came in — station monsters in your buildings so the '
              'settlement works while you are gone.',
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final e in main) tile(e)],
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 12),
              _digestHeading('Other resources', kBoxInk),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final e in others) chip(e)],
              ),
            ],
          ],
          if (notices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _digestHeading('Lost', kBoxInk),
            const SizedBox(height: 8),
            ...notices,
          ],
        ],
      ),
    );

    final happened = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _digestHeading('What happened', kBoxInk),
        const SizedBox(height: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: vr(12),
            ),
            child: events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Nothing else to report.',
                      style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                    ),
                  )
                // ALL of them. The list scrolls, so a long night away is a
                // scroll, not a truncation and a redirect.
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: events.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: kBoxInk.withValues(alpha: 0.13),
                    ),
                    itemBuilder: (ctx, i) {
                      final e = events[i];
                      final goes = gameEventHasDestination(e);
                      final row = Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.kind.emoji,
                              style: const TextStyle(fontSize: 15),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                e.message,
                                style: FoE.label(
                                  size: 12,
                                ).copyWith(color: kBoxInk),
                              ),
                            ),
                            // WHEN, as the bell prints it — the only way to
                            // tell an expedition that landed an hour ago from
                            // one that landed as you opened the game.
                            const SizedBox(width: 8),
                            Text(
                              _digestAgo(e.at),
                              style: FoE.dim(
                                size: 10,
                              ).copyWith(color: kBoxInkFaint),
                            ),
                            // The chevron is the whole affordance — the same
                            // door the bell's rows are.
                            if (goes)
                              PixelIcon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: kBoxInkFaint,
                              ),
                          ],
                        ),
                      );
                      if (!goes) return row;
                      return Pressable(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Opening one is reading them: the digest has shown
                          // the whole set, exactly as its own Continue means.
                          log.markAllRead();
                          openGameEvent(ctx, e);
                        },
                        child: row,
                      );
                    },
                  ),
          ),
        ),
      ],
    );

    showDialog<void>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (ctx) => ParchmentDialog(
        title: 'Welcome back',
        maxWidth: 800,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: raisedTile(radius: 10),
          child: Text(
            '🕒 $awayLabel',
            style: FoE.label(size: 11).copyWith(color: kBoxInk),
          ),
        ),
        closeLabel: 'Continue',
        // Dismissing with Continue MARKS THEM READ. This screen has just shown
        // the same set the bell would, so leaving the badge nagging about it
        // would send the player to read a second time what they have already
        // read once (user 2026-07-27).
        onClose: log.markAllRead,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: gathered),
              const SizedBox(width: 20),
              Expanded(child: happened),
            ],
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
  ///
  /// A determinate bar, not a spinner (user 2026-10-04) — it tracks
  /// [_progress], which [_bootstrap] actually advances as each real step
  /// finishes, so a slow phone shows a bar that is genuinely crawling rather
  /// than a spinner that gives no sense of how much longer.
  Widget _loading() => DecoratedBox(
    decoration: const BoxDecoration(gradient: kMenuGround),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Bøddy Game', style: FoE.title(size: 22)),
          const SizedBox(height: 28),
          SizedBox(
            width: 180,
            child: ClipRRect(
              borderRadius: vr(4),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: FoE.gold.withValues(alpha: 0.2),
                color: FoE.gold,
              ),
            ),
          ),
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
      // The map begins UNDER the header, not behind it (user 2026-09-18: "der
      // Header verdeckt einiges von der Baufläche. Ich sollte auch wenn ich
      // ganz herausgezoomt bin, die ganze Baufläche sehen können"). The
      // starting plot sits near the top of the map, and the map may never be
      // scrolled past its own edge — so with the header laid over it, the
      // top of the plot was hidden AND out of reach. Sized this way the map's
      // viewport is exactly the visible part, so its zoom-out limit, its pan
      // limits and the "middle of the view" the placement ghost drops into all
      // mean what the player sees.
      //
      // The bottom stays full-bleed: the build carousel has no backdrop, and
      // closes the moment a building is picked, so the placement ghost is
      // never aimed from underneath it.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        top: _mapTop,
        child: SettlementMap(
          key: _mapKey,
          ctrl: _ctrl,
          pendingTypeId: _pendingTypeId,
          editMode: _editMode,
          roadMode: _roadMode,
          persistentEditMode: _editModePersistent,
          selectBuildingId: _selectTrayBuildingId,
          onAimingChanged: (aiming) => setState(() {
            _trayAiming = aiming;
            if (!aiming) _selectTrayBuildingId = null;
          }),
          onPlacementDone: () => setState(() => _pendingTypeId = null),
          onEnterEditMode: _enterEditMode,
          onExitEditMode: () => setState(() {
            _editMode = false;
            _editModePersistent = false;
          }),
          onExitRoadMode: () => setState(() => _roadMode = false),
        ),
      ),
      // Tapping the map closes the build menu (user 2026-09-18). A Listener,
      // not a GestureDetector: it sees the tap WITHOUT absorbing it, so the
      // map underneath keeps panning, zooming and opening buildings while the
      // menu is up. Only when the player opened the menu — the tutorial's
      // forced-open carousel has no other way to be reached again.
      if (_buildOpen && _showBuildCarousel)
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) {
              _mapTapDownPos = e.position;
              _mapTapDownAt = e.timeStamp;
            },
            onPointerUp: (e) {
              final downPos = _mapTapDownPos;
              final downAt = _mapTapDownAt;
              _mapTapDownPos = null;
              if (downPos == null || downAt == null) return;
              final isTap =
                  (e.position - downPos).distance < 18 &&
                  e.timeStamp - downAt < const Duration(milliseconds: 400);
              if (isTap) {
                setState(() => _buildOpen = false);
              }
            },
            onPointerCancel: (_) => _mapTapDownPos = null,
            child: const SizedBox.expand(),
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
              // Raised again (user 2026-09-29: first to match the 4 px right
              // margin, then "etwas höher nehmen" once more) — was 6, then 4.
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  if (_ctrl.saveFailed) _syncWarning(),
                  // Sound/music left the header for the Profile (user
                  // 2026-09-20: "Musik/Sound aus gehört ins Profil").
                  _newsButton(),
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
      //
      // Beside the build strip while the PLAYER has it open (2026-09-19: the Build
      // tile stands in the strip's left margin, on one line with its cards); lifted
      // above it by [buildingCarouselHeight] only when the tutorial forces the
      // strip open and the rail carries other tiles.
      AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        left: 0,
        right: 0,
        bottom: _showBuildCarousel && !_buildOpen
            ? buildingCarouselHeight(context)
            : 0,
        child: _bottomStack(),
      ),
      // THE BUILD MENU, FOLDED INTO THE MAP (2026-09-18 — user: "das
      // Baumenü kein eigener Screen ist, sondern unten die Gebäude
      // gescrollt werden können wie dies bei rok der Fall ist"). Replaces
      // the old pushed BuildMenuScreen entirely — see BuildingCarousel's
      // own doc comment.
      if (_showBuildCarousel)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: BuildingCarousel(
              ctrl: _ctrl,
              onPlace: _buildAndPlace,
              onRoads: _enterRoadMode,
              onLayout: _enterLayoutMode,
              initialCategory: _requestedCategory,
              trayBuildings: _showTrayCarousel ? _ctrl.storedBuildings : null,
              onPlaceStored: (id) => setState(() => _selectTrayBuildingId = id),
              onCancelTray: _cancelUmbaumodus,
            ),
          ),
        ),
      if (_resourcesOpen) _resourcesDropdown(),
      // The intro card ITSELF is the lit control (every step still holding
      // its own unpressed CTA) — centred on the screen rather than pinned
      // above the quick menu (user 2026-09-02: "diese Textboxen in die
      // Mitte des Screens nehmen"). Drawn BEFORE the scrim below so the
      // spotlight punches its hole out around exactly this position.
      if (_ctrl.introStep.isActive &&
          !_mapModeActive &&
          _pendingTypeId == null &&
          _soloQuickPadAnchor == null &&
          !_introHandledByBuildCarousel)
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
      // placement (the map is the target then), map modes, and the two
      // build-carousel steps (see [_introHandledByBuildCarousel]) — that
      // strip punches its own hole, and a second one here just fights it.
      if (_ctrl.introStep.isActive &&
          !_mapModeActive &&
          _pendingTypeId == null &&
          !_introHandledByBuildCarousel)
        IntroSpotlightOverlay(
          anchorName: _introSpotlightAnchor,
          hint: _introSpotlightHint,
        ),
      // A narration-only card (firstNode's "your monsters can fight too", or
      // buildHealingHut/buildRoad handing off to BuildingCarousel) stays up
      // ON TOP of the scrim instead of being punched out of it — it has
      // nothing of its own to press, so it never needs to BE the hole, only
      // to stay readable while its real target (a quick-pad tile, or the
      // build strip's own spotlight) is. Centred, EXCEPT when the real
      // target is a building ON THE MAP itself (assignHealer's Healing Hut)
      // — a screen-centred card there used to sit right on top of it (user
      // 2026-09-30 screenshot: "die Kamera so gesetzt wird, dass das
      // Healing Hut ... anwählbar [ist], oder der Text so geschoben wird").
      // Pinned to the top instead, out of the map's own centre.
      if (_ctrl.introStep.isActive &&
          !_mapModeActive &&
          _pendingTypeId == null &&
          _introCardIsNarrationOnly &&
          (_soloQuickPadAnchor != null || _introHandledByBuildCarousel))
        _activeIntroCard?.destination == IntroDestination.healingHut
            ? Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 76),
                  // Keyed so SettlementMap can measure how far down this
                  // reaches and keep the Healing Hut it's pointing at out
                  // from under it while focusing the camera (user 2026-10-01:
                  // "bitte die kamera so schieben, dass ich mehr von dem
                  // Healing hut sehe") — see
                  // SettlementMapState._introTopCardInset.
                  child: KeyedSubtree(
                    key: IntroSpotlightAnchors.of('intro-top-card'),
                    child: _introCard(),
                  ),
                ),
              )
            : Center(child: _introCard()),
    ],
  );

  /// The guided-tutorial card, padded and ready to drop anywhere in the
  /// Stack — pulled out so both the "I'm the spotlight hole" placement and
  /// the "I float above the scrim" placement (see [build]) render the exact
  /// same widget.
  Widget _introCard() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    // Width-capped (2026-09-18, landscape): a full-width card on a 900px
    // screen is a banner nobody reads end to end.
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: IntroCardPanel(ctrl: _ctrl, onNavigate: _goToIntroTarget),
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

  /// True for buildHealingHut/buildRoad: a narration-only card whose real
  /// target is BuildingCarousel's OWN internal row/category spotlight, not a
  /// quick-pad tile ([_soloQuickPadAnchor] returns null for
  /// [IntroDestination.build] on purpose — see its own doc comment). Without
  /// this, [_introSpotlightAnchor] fell back to 'intro-panel' and put the
  /// TOP-LEVEL overlay's hole around the card itself — a card with no CTA,
  /// so nothing in it was tappable either, while that same overlay's scrim
  /// sat OVER BuildingCarousel and blocked its own, separately-punched hole
  /// around the real target building. Net effect (user report 2026-09-30,
  /// screenshot of "Patch it up"): "kann ich nichts anwählen" — literally
  /// nothing on screen was reachable. This flag turns the top-level overlay
  /// off entirely for these two steps, leaving BuildingCarousel's own
  /// spotlight as the only one, and keeps the card floating above it
  /// (the "narration stays visible, un-dimmed" treatment every other
  /// narration-only step already gets once it hands off to a real target).
  bool get _introHandledByBuildCarousel =>
      _introCardIsNarrationOnly &&
      _activeIntroCard?.destination == IntroDestination.build;

  /// The ONE quick-pad tile that's lit and interactive right now, or null
  /// when the intro card itself is that one lit control instead (the usual
  /// case: most steps' own CTA button IS the hole).
  ///
  /// A narration-only card points straight at a tile from the moment its
  /// step begins (firstNode → Map, pickStarter → Monsters) — every step
  /// that hands off to a quick-pad tile does it this way now (2026-09-30:
  /// pickStarter dropped the extra "Choose starter" tap its own CTA used to
  /// need first).
  String? get _soloQuickPadAnchor {
    final card = _activeIntroCard;
    if (card == null || !_introCardIsNarrationOnly) return null;
    return switch (card.destination) {
      IntroDestination.map => 'quick-map',
      IntroDestination.collection => 'quick-monsters',
      // Build has no solo hand-off any more (2026-09-18): the carousel
      // isn't a tile you tap to OPEN something — it appears the moment
      // [_buildUnlocked] flips true, already showing its own row/category
      // spotlight (see BuildingCarousel) for exactly what to tap next.
      IntroDestination.build => null,
      // Not a quick-pad tile — the Healing Hut itself, on the map (user
      // 2026-09-06: "lass mich das Gebäude anklicken") — see
      // SettlementMapState's own anchorKey wiring in _buildingTile.
      IntroDestination.healingHut => 'map-healing-hut',
      // The bottom-right Expedition button (user 2026-10-01: "ich will,
      // dass ich über den expeditionsbutton unten rechts ins menü gehe" —
      // this used to point at the header's small Trips readout cell, which
      // reads as a stat, not a button, next to the quick pad's other real
      // destinations). See [_railItems]'s own anchorKey wiring on its
      // Expedition tile.
      IntroDestination.trips => 'quick-trips',
      _ => null,
    };
  }

  /// Which anchor the guided tutorial lights up right now — the CURRENT
  /// step's own quick-pad tile when it has one, else the intro card itself.
  /// An earlier hand-off's tile can still be showing in the pad alongside it
  /// (see [_quickPad]), but only THIS one is the hole.
  String get _introSpotlightAnchor => _soloQuickPadAnchor ?? 'intro-panel';

  String? get _introSpotlightHint => switch (_soloQuickPadAnchor) {
    'quick-monsters' => 'Tap Monsters to choose your starter',
    'quick-map' => 'Tap Map to open the overworld',
    'map-healing-hut' => 'Tap the Healing Hut to open it',
    'quick-trips' => 'Tap Expedition to send a hunt.',
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

  bool get _tripsUnlocked =>
      _soloQuickPadAnchor == 'quick-trips' ||
      _ctrl.introStep.index > IntroStep.firstCapture.index;

  /// Whether the build carousel is allowed to exist at all — the same
  /// progressive-reveal rule the quick pad's own tiles follow, just no
  /// longer keyed to a solo hand-off (there's no separate "open" tile any
  /// more — see [_soloQuickPadAnchor]'s own doc comment on Build). True
  /// from the moment the tutorial hands off to buildHealingHut onward
  /// (buildRoad is the very next step, so `>=` already covers it).
  bool get _buildUnlocked =>
      _ctrl.introStep.index >= IntroStep.buildHealingHut.index;

  /// True while the map owns the bottom of the screen: aiming, road building
  /// and move/edit mode each show their own banner down there (with the button
  /// that LEAVES the mode), so the quick menu has to get out of the way or
  /// they stack on top of each other.
  ///
  /// Placement counts too now (2026-08-09): the map's own banner explains the
  /// ✓/✗ that are sitting over the building, and a second banner underneath it
  /// saying roughly the same thing is one too many.
  bool get _mapModeActive => _roadMode || _editMode || _pendingTypeId != null;

  /// Whether the bottom [BuildingCarousel] is showing right now — unlocked,
  /// not fighting the map's own mode banner for the same strip of screen
  /// (2026-09-18), and OPENED by the player via the quick pad's Build tile.
  /// The tutorial is the exception: the quick pad is hidden while it runs, so
  /// its build steps get the carousel without asking for it.
  ///
  /// OR — [_showTrayCarousel] (user 2026-09-22): Umbaumodus's own tray. This
  /// is the one case the carousel appears WHILE `_mapModeActive` is true
  /// (edit mode never turns that off) — [BuildingCarousel] itself switches
  /// into tray mode; see [_bottomStack]'s own build call.
  ///
  /// Scoped to [_introHandledByBuildCarousel] (the two BUILD steps), not the
  /// whole tutorial (user 2026-10-01, a firstCapture screenshot: "das
  /// Baumenü noch geöffnet" pushing the quick pad up off the true bottom
  /// edge) — `introStep.isActive` used to hold it open through every later
  /// step too (assignHealer, healStarter, firstCapture, secondNode), which
  /// contradicts this getter's own "its BUILD steps" doc line above and had
  /// nothing to do with any of those steps' own targets.
  bool get _showBuildCarousel =>
      (_buildUnlocked &&
          !_mapModeActive &&
          (_buildOpen || _introHandledByBuildCarousel)) ||
      _showTrayCarousel;

  /// Umbaumodus's tray, standing in for the map's own small banner (user
  /// 2026-09-22: "wenn ich recall all mache, sollen das Baumenü geöffnet
  /// werden … genau gleiche Oberfläche, aber nur mit den gespeicherten
  /// Gebäuden") — the instant "Alle Gebäude/Straßen zurücknehmen" leaves
  /// anything in [SettlementController.storedBuildings], the Build menu
  /// itself takes over the bottom of the screen, filtered to just those.
  /// [_trayAiming] hides it again for as long as one of its cards is
  /// actually being positioned, so it never covers the spot the player is
  /// dragging a ghost toward.
  bool get _showTrayCarousel =>
      _editMode &&
      _editModePersistent &&
      _ctrl.hasStoredBuildings &&
      !_trayAiming;

  /// The tray carousel's own Cancel button (user 2026-09-22): undoes the
  /// whole rearrange — see [SettlementController.cancelRecall] — and only
  /// then leaves Umbaumodus. A no-op revert (nothing was ever recalled this
  /// visit) still safely falls through to just leaving.
  Future<void> _cancelUmbaumodus() async {
    await _ctrl.cancelRecall();
    if (!mounted) return;
    setState(() {
      _editMode = false;
      _editModePersistent = false;
    });
  }

  Widget _bottomStack() {
    // The Build menu no longer needs a mention here (2026-07-31): it is a page
    // now, so it covers this screen rather than sharing the bottom edge with it.
    if (_mapModeActive) return const SizedBox.shrink();
    // SafeArea now: the bar that used to paint its own background into the
    // gesture inset is gone, so the loose buttons have to keep off the glass
    // themselves. The two rails stand at the screen's own edges and leave the
    // middle to the map.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: _quickRails(),
      ),
    );
  }

  void _goToIntroTarget(IntroDestination target) => switch (target) {
    IntroDestination.collection => _showCreatures(),
    IntroDestination.map => _showOverworld(),
    IntroDestination.trips => _showExpeditions(),
    // No screen to open any more (2026-09-18) — the carousel is already on
    // screen the moment [_buildUnlocked] flips true, and no build step's
    // own card carries a CTA that reaches this case in practice (both are
    // narration-only; see [_soloQuickPadAnchor]'s doc comment). Kept for
    // the switch's own exhaustiveness rather than removed.
    IntroDestination.build => null,
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
  /// sits. A real Column sibling has no such blind spot, at the cost of
  /// the few pixels the tab used to tuck up under the band's own edge.
  Widget _topBar() => Column(
    children: [
      // STRATEGY-HUD RESOURCE BAR (2026-09-18): one flat navy plate
      // (the same [FoE.bg] the pull tab below fills itself with, so the
      // two still read as one shape) lifted off the map by the shadow,
      // with the resource cells sitting on it as gem badges. The meander
      // bordure it used to carry is gone with the rest of it.
      // Measured (see [_measureHeader]): the map starts where this ends.
      KeyedSubtree(
        key: _headerKey,
        child: ParchmentHeader.band(
          // A flat gradient (both stops [FoE.bg]) rather than ill: — a band
          // given a plain fill also draws its lit/shaded facet edges, a seam the
          // pull tab hanging off the bottom of it has no counterpart for.
          //
          // It LIGHTENS towards the top now (user 2026-09-18: "der Header ...
          // wirkt sehr schlicht") but still ends on exactly [FoE.bg], the flat
          // colour the wave fills itself with, so the two read as one shape.
          // A TIMBER BEAM now (Fachwerk, 2026-11-02): lit wood on top,
          // shaded wood at the foot, where the roof course hangs from it.
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Fachwerk.timberLight,
              Fachwerk.timber,
              Fachwerk.timberDark,
            ],
          ),
          shadow: _mapShadow,
          // The safe area is the band's own top padding rather than a
          // SafeArea around it: the plate paints up through a notch instead of
          // leaving a strip of map showing above it, and the measured height
          // then includes it — which is what the map's top edge needs.
          child: Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_resourceRow(), _headerTrim()],
            ),
          ),
        ),
      ),
      // Up by the trim's own height, so the tab's fill covers the trim where
      // the two meet and the gold line carries on around the tab's edge
      // instead of cutting across its top.
      Transform.translate(offset: const Offset(0, -_kTrimH), child: _erasTab()),
    ],
  );

  static const double _kTrimH = 13;

  /// A thin gold rule along the header's foot, brightest in the middle where the
  /// wave hangs from it and fading out towards the phone's edges — the piece of
  /// jewellery that stops a flat navy plate reading as a bare bar.
  ///
  /// Fachwerk (2026-11-02): a course of ROOF TILES instead of the gold rule —
  /// the header is the eaves the map sits under.
  Widget _headerTrim() => const RoofTileStrip(height: _kTrimH, tileWidth: 18);

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

  /// The one-line strip's height. The band is nothing but this row (and the eras
  /// panel when it is unfolded) — the map starts right under it.
  static const double _kResourceRowHeight = 34;

  /// How tall the rounded tab under the header is.
  static const double _kPullH = 22;

  /// The tab under the header — belongs TO the header, not beside it (user
  /// 2026-09-06: "dieser gehört zum Header. Daher gibt es keinen Übergang"), so it
  /// is the header's own colour, hung from its foot with the same gold rim. ROUND
  /// like the rest of the UI (user 2026-09-22). Opens/closes the resources
  /// dropdown (user 2026-09-30: back to "wie früher eine Art Hovermenü",
  /// replacing the full Resources page this used to push — see
  /// [_resourcesDropdown]; that page is still reachable from its own "See
  /// all" link). (It wore a coral dot while any store was full; removed on
  /// request, 2026-09-22 — the Resources page marks full stores itself.)
  Widget _erasTab() => Center(
    child: Semantics(
      label: 'All resources',
      button: true,
      child: Pressable(
        onTap: () => setState(() => _resourcesOpen = !_resourcesOpen),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 78,
          height: _kPullH,
          decoration: BoxDecoration(
            // Hangs from the roof course: a terracotta tile of its own.
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Fachwerk.timberLight, Fachwerk.timber],
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            border: Border.all(color: Voxel.outline, width: 2),
            boxShadow: [_mapShadow.first],
          ),
          alignment: Alignment.center,
          child: PixelIcon(
            _resourcesOpen ? Icons.expand_less_rounded : Icons.apps_rounded,
            size: 16,
            color: CreamPalette.gold,
          ),
        ),
      ),
    ),
  );

  /// The resources dropdown itself (user 2026-09-30) — a cream panel hanging
  /// under the tab, GOLD ALONE AND CENTRED AT THE TOP ("Gold ist immer oben
  /// mittig", it belongs to no era — same rule [ResourcesScreen] itself
  /// follows), then one row of chips per era actually unlocked so far, via
  /// the exact same [unlockedResourceShelves]/[ResourceTile] the full page
  /// uses — so the two can never show different numbers. Sized to its own
  /// content, not a fixed height: an early game with one era shows a short
  /// panel, not a mostly-empty one. A tap anywhere outside it closes it.
  Widget _resourcesDropdown() {
    final rates = _ctrl.hourlyRates;
    final eraShelves = unlockedResourceShelves(
      _ctrl,
    ).where((s) => s.era != null);
    return Positioned.fill(
      child: Stack(
        children: [
          // The scrim — transparent (a hover menu, not a modal that dims the
          // world) but still opaque to hit-testing, so a tap anywhere else
          // (the map, the quick rails underneath) closes this instead of
          // reaching them.
          Positioned.fill(
            child: Pressable(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _resourcesOpen = false),
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Positioned(
            top: _mapTop + 6,
            left: 0,
            right: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  // Absorbs its own taps so pressing a tile (or the padding
                  // around them) never falls through to the scrim behind it.
                  child: Pressable(
                    onTap: () {},
                    child: creamCard(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 124,
                            child: ResourceTile(
                              id: 'gold',
                              rate: rates['gold'] ?? 0,
                            ),
                          ),
                          for (final s in eraShelves) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                romanNumeral(s.era!),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: kBoxAccent,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final id in s.ids)
                                  SizedBox(
                                    width: 124,
                                    child: ResourceTile(
                                      id: id,
                                      rate: rates[id] ?? 0,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Pressable(
                            onTap: () {
                              setState(() => _resourcesOpen = false);
                              _openResources();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'See all →',
                                style: FoE.dim(size: 11.5).copyWith(
                                  color: kBoxAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
      child: const PixelIcon(
        Icons.cloud_off_rounded,
        color: Colors.orangeAccent,
        size: 20,
      ),
    ),
  );

  /// TODAY'S GOALS (v2, user 2026-09-22: "Serie, mehr Aufgabenarten, Tages-Truhe"):
  /// a wide cream dialog — LEFT the three goals of the day, RIGHT the streak (a
  /// week of days in a row, with a chest to look forward to on days 3, 5 and 7) and
  /// today's chest, which opens once all three are claimed.
  void _showDailyTasks() {
    DailyChest? got;
    showDialog<void>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final state = _ctrl.dailyTasks;
          final tasks = state.tasks;
          return ParchmentDialog(
            title: "Today's goals",
            maxWidth: 780,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Three fresh goals every day. Finish all three for '
                            "today's chest.",
                            style: FoE.dim(
                              size: 11,
                            ).copyWith(color: kBoxInkSoft),
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < tasks.length; i++)
                            _dailyTaskRow(i, tasks[i], setLocal),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 270,
                    child: SingleChildScrollView(
                      child: _streakAndChest(state, got, (chest) {
                        got = chest;
                        setLocal(() {});
                      }, setLocal),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The right-hand side: the streak strip and the chest.
  Widget _streakAndChest(
    DailyTasksState state,
    DailyChest? got,
    ValueChanged<DailyChest> onOpened,
    StateSetter setLocal,
  ) {
    final now = DateTime.now().toUtc();
    final streak = state.streakOn(now);
    // The day of the week-long cycle the chest just opened (or the next one) sits
    // on: pips up to it are lit.
    final lit = streak == 0 ? 0 : ((streak - 1) % kStreakCycle) + 1;
    final nextDay = state.nextChestDay(now);
    final next = chestForStreakDay(nextDay);
    final doneCount = state.tasks.where((t) => t.claimed).length;

    Widget pip(int day) {
      final on = day <= lit;
      final special = day == 3 || day == 5 || day == kStreakCycle;
      return Expanded(
        child: Column(
          children: [
            Container(
              height: 26,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: vr(8),
                color: on ? CreamPalette.gold : kBoxInk.withValues(alpha: 0.12),
              ),
              child: special
                  ? Text(day == kStreakCycle ? '🏆' : '🎁')
                  : Text(
                      '$day',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: on ? CreamPalette.ink : kBoxInkSoft,
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    final chestBody = got != null
        ? _chestLine('You got', got)
        : _chestLine(state.chestOpened ? "Tomorrow's chest" : next.name, next);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: raisedTile(radius: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    streak == 0
                        ? 'No streak yet'
                        : streak == 1
                        ? 'Streak: 1 day'
                        : 'Streak: $streak days',
                    style: FoE.label(
                      size: 13,
                    ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [for (var d = 1; d <= kStreakCycle; d++) pip(d)]),
              const SizedBox(height: 6),
              Text(
                'Open the chest every day. Miss a day and it starts over. '
                'Days 3, 5 and 7 give more.',
                style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: raisedTile(radius: 12, lit: state.chestReady),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              chestBody,
              const SizedBox(height: 10),
              if (state.chestReady)
                Pressable(
                  onTap: () async {
                    final chest = await _ctrl.claimDailyChest();
                    if (chest != null) onOpened(chest);
                  },
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: goldButton(),
                    child: Text(
                      'Open chest',
                      style: FoE.label(
                        size: 14,
                      ).copyWith(color: goldButtonInk()),
                    ),
                  ),
                )
              else
                Text(
                  state.chestOpened
                      ? 'Opened — come back tomorrow.'
                      : '$doneCount of ${state.tasks.length} goals claimed',
                  textAlign: TextAlign.center,
                  style: FoE.dim(size: 11.5).copyWith(
                    color: state.chestOpened
                        ? CreamPalette.better
                        : kBoxInkSoft,
                    fontWeight: state.chestOpened ? FontWeight.w800 : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// A chest's name and what is in it: gold, and the items.
  Widget _chestLine(String label, DailyChest chest) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text('🎁', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 6),
          Text(
            label,
            style: FoE.label(
              size: 13,
            ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          Text(
            '🪙 ${chest.gold}',
            style: FoE.value(size: 13).copyWith(color: kBoxInk),
          ),
          for (final e in chest.items.entries)
            Text(
              '${kItemDefs[e.key]?.emoji ?? '🎁'} ×${e.value}',
              style: FoE.value(size: 13).copyWith(color: kBoxInk),
            ),
        ],
      ),
    ],
  );

  Widget _dailyTaskRow(int index, DailyTask t, StateSetter setLocal) {
    final rewardText = t.reward.entries
        .map(
          (e) =>
              '${resourceEmoji(e.key)} '
              '${e.value.toStringAsFixed(0)}',
        )
        .join('  ');
    final frac = t.target == 0 ? 1.0 : (t.progress / t.target).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: raisedTile(radius: 12, lit: t.claimable),
      child: Row(
        children: [
          Text(t.kind.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.kind.label,
                  style: FoE.label(
                    size: 13,
                  ).copyWith(color: kBoxInk, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: vr(4),
                  child: SizedBox(
                    height: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: kBoxInk.withValues(alpha: 0.16)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: frac,
                            child: ColoredBox(
                              color: t.done
                                  ? CreamPalette.better
                                  : CreamPalette.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${t.progress}/${t.target} · reward: $rewardText',
                  style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (t.claimed)
            Text(
              '✓',
              style: FoE.label(size: 18).copyWith(color: CreamPalette.better),
            )
          else
            Pressable(
              onTap: t.claimable
                  ? () async {
                      await _ctrl.claimDailyTask(index);
                      setLocal(() {});
                    }
                  : null,
              child: Opacity(
                opacity: t.claimable ? 1 : 0.4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: t.claimable
                      ? goldButton()
                      : raisedTile(radius: 10),
                  child: Text(
                    'Claim',
                    style: FoE.label(size: 12).copyWith(
                      color: t.claimable ? goldButtonInk() : kBoxInkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ONE LINE, EVERY ERA. Not scrollable and no longer wrapping: the era's
  /// resources share the left half equally, gold, housing and trips the right, so
  /// the strip is the same height in era VIII as in era I and nothing is ever
  /// hidden behind a scroll. The energy bar stands between them.
  Widget _resourceRow() {
    final rates = _ctrl.hourlyRates;
    final era = _ctrl.dungeonMaxStage;
    // ONE LINE, 34 px (user 2026-09-22, "Variante 4"). LEFT: the era's own
    // resources (its build pair and its luxury — three in era I). CENTRE: ENERGY,
    // the one bar, because it scales every rate on the strip. RIGHT: gold,
    // housing and trips. The two groups get the same width either side of the
    // bar, so the bar stays on the screen's own centre line. The bell is not in
    // the strip: it hangs under the header at the right.
    return SizedBox(
      height: _kResourceRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  for (final r in _eraResources(
                    era,
                    cleared: _ctrl.battlesCleared,
                  ))
                    Expanded(
                      child: _resCell(
                        r.emoji,
                        r.name,
                        r.id,
                        _amountOf(r.id),
                        rates[r.id] ?? 0,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _energyBar(),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _resCell(
                      '🪙',
                      'Gold',
                      'gold',
                      _amountOf('gold'),
                      rates['gold'] ?? 0,
                    ),
                  ),
                  Expanded(child: _housingCell()),
                  Expanded(child: _tripsCell()),
                ],
              ),
            ),
          ],
        ),
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

  // Shared sizing for every header cell so glyphs and text lines all match up.
  static const _kHeaderIconSize = 15.0;
  static const _kHeaderSubSize = 10.0;

  /// Header numbers are SHORT (`1.2k`, `12k`, `1.4M`). At a seventh of a phone
  /// each, a cell has room for about four glyphs — and a five-digit pile of wood
  /// is a magnitude, not a figure you read digit by digit.
  ///
  /// Shared with every other surface since 2026-07-30 (core/ui/number_format) —
  /// this used to be the only place in the app that shortened anything.
  static String _short(double v) => shortNumber(v);

  /// Every header cell is tappable (it opens the resource breakdown), so each one
  /// gets a real hit area instead of being a bare Padding you have to aim at. No
  /// slot around it any more (user 2026-09-22, "Variante 4"): the figures stand
  /// straight on the bar, and the cell is scaled down as a whole when a long
  /// figure would not fit its share of the width.
  Widget _headerCell({required VoidCallback onTap, required Widget child}) =>
      InkWell(
        onTap: onTap,
        borderRadius: vr(10),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
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

  /// The shape every cell in the strip shares: ONE LINE — the glyph, the figure,
  /// the rate (user 2026-09-22, "Variante 4"). The strip is 34 px high, so a cell
  /// can no longer stack them; side by side, the figure reads first and the rate
  /// is a quiet tail behind it.
  Widget _cellBody({
    required String emoji,
    required String value,
    required String sub,
    Color? valueColor,
    Color? subColor,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Fixed box, not a bare Text: color emoji render through a fallback
      // system font whose glyph bitmap sits taller than the line height
      // Flutter computes from Outfit's own metrics at this size, so an
      // unconstrained emoji bled down and overwrote the value beside it (user
      // 2026-08-31: "Die Icons werden überschrieben").
      SizedBox(
        width: _kHeaderIconSize + 5,
        height: _kHeaderIconSize + 5,
        child: Center(
          child: Text(
            emoji,
            style: const TextStyle(fontSize: _kHeaderIconSize),
          ),
        ),
      ),
      const SizedBox(width: 3),
      Text(
        value,
        maxLines: 1,
        style: FoE.value(size: 13).copyWith(
          color: valueColor,
          shadows: ParchmentHeader.engraved(depth: 0.8),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        sub,
        maxLines: 1,
        style: FoE.dim(size: _kHeaderSubSize).copyWith(
          color: subColor,
          shadows: ParchmentHeader.engraved(depth: 0.6),
        ),
      ),
    ],
  );

  /// TRIPS: how many expeditions and caravans are away, and when the first is
  /// back. Gold once one is home and waiting to be played. Opens the
  /// expeditions hub.
  ///
  /// NOT the tutorial's firstCapture target any more (user 2026-10-01: "ich
  /// will, dass ich über den expeditionsbutton unten rechts ins menü gehe")
  /// — this header cell reads as a stat readout, not a button, and the
  /// bottom quick pad already has a real "Expedition" destination of its
  /// own; see [_railItems]'s own anchorKey wiring on that tile instead.
  Widget _tripsCell() => TripsStatusBuilder(
    builder: (context, s) {
      final ready = s.ready > 0;
      return _headerCell(
        onTap: _showExpeditions,
        child: _cellBody(
          emoji: '🧭',
          value: s.noSlots ? '–' : '${ready ? s.ready : s.out}',
          sub: ready
              ? 'ready'
              : s.soonest != null
              ? fmtDuration(s.soonest!.inSeconds.toDouble())
              : s.noSlots
              ? 'no post'
              : 'idle',
          valueColor: ready ? CreamPalette.gold : null,
          subColor: ready ? CreamPalette.gold : null,
        ),
      );
    },
  );

  /// NEWS: the bell, out of the strip again (user 2026-09-19) — a small round kit
  /// button under the header at the right, with the unread count on its corner.
  /// The same sheet on tap, and the same "mark read on open" rule
  /// ([NotificationBadge]).
  Widget _newsButton() => NotificationBadge(
    builder: (context, unread, open) => Semantics(
      label: 'News',
      button: true,
      child: Pressable(
        onTap: open,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                // The full gem chrome, the same as Build/Manage — gradient,
                // white/cream rim, drop shadow — not just the fill colour
                // (user 2026-09-29: "es fehlt noch der weisse Rahmen und der
                // Farbverlauf, damit sie gleich sind wie die Buttons Build
                // und Management").
                decoration: gemDecoration(CreamPalette.gold),
                child: PixelIcon(
                  unread > 0
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 20,
                  color: CreamPalette.ink.withValues(
                    alpha: unread > 0 ? 1 : 0.6,
                  ),
                ),
              ),
              if (unread > 0)
                Positioned(
                  top: 0,
                  right: -2,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FoE.coral,
                      borderRadius: vr(9),
                      border: Border.all(
                        color: CreamPalette.paperTop,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      // Caps the badge: "99+" keeps it stable no matter how
                      // long you were away.
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                        color: CreamPalette.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
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
      // Opens Work, not Housing (user 2026-09-20: "wenn ich beim Header auf
      // Housing drücke, soll Work aufgehen, da dies der wichtigere Screen
      // ist") — Housing is the page's second tab, one tap over.
      onTap: () => pushMenu(context, const WorkScreen()),
      child: _cellBody(
        emoji: '🛏',
        value: '$used/$cap',
        sub: full ? 'full' : '${cap - used} free',
        valueColor: full ? FoE.danger : null,
        subColor: full ? FoE.danger : null,
      ),
    );
  }

  /// ENERGY, AS THE STRIP'S CENTRE (user 2026-09-19, "Variante 4" 2026-09-22). A
  /// wide bar on a 0–125 % scale, the figure and how many hours it will still last
  /// written across it. Energy is a POOL that steps fill and time empties (user
  /// 2026-09-20), and it scales every rate beside it. Amber up to 100 %; the
  /// stretch from 100 to 125 % is cyan, with a tick at the 100 % mark. Coral only
  /// when it is empty: everything above that is a real, working rate.
  ///
  /// Energy is loaded separately from the settlement, so it can genuinely be
  /// absent for the first frames: the bar keeps its SLOT either way, so the row
  /// must not reflow the moment it arrives.
  Widget _energyBar() {
    final energy = _ctrl.energy;
    final percent = (energy?.percent ?? 0).toDouble();
    final atFloor = energy != null && energy.isEmpty;
    // How long it lasts — the countdown is the point of a pool that drains.
    final left = energy == null || energy.isEmpty
        ? ''
        : energy.hoursLeft >= 1
        ? ' · ${energy.hoursLeft.floor()}h'
        : ' · ${(energy.hoursLeft * 60).ceil()}m';
    return Semantics(
      label: 'Energy',
      button: true,
      child: Pressable(
        onTap: _showEnergyOverview,
        behavior: HitTestBehavior.opaque,
        // The same battery the energy page itself shows (user 2026-09-30:
        // "verwende beim Header für die Energieanzeige die Batterie, welche
        // bereits beim Detailscreen vorhanden ist"), compact and with no
        // "100 %"/"125 %" marks. Its rim is [_QuickTile]'s own unlit one, not
        // a plain black or white (user, same message: "der Rand soll aber
        // nicht Schwarz sein, sondern so wie der Rand des Management oder
        // Build Buttons" — those sit at `CreamPalette.paperTop` @ 95 %, not
        // `Colors.white`, unless active). Red when the pool is empty, same
        // warning the gauge's own retired stroke used to give.
        child: SizedBox(
          width: _kEnergyBarWidth,
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              EnergyBattery(
                percent: percent,
                height: 22,
                radius: 10,
                borderColor: atFloor
                    ? FoE.danger
                    : CreamPalette.paperTop.withValues(alpha: 0.95),
                borderWidth: 2,
                showLabels: false,
                continuous: true,
                showContact: false,
              ),
              Text(
                energy == null ? '⚡ —' : '⚡ ${percent.round()}%$left',
                maxLines: 1,
                style: FoE.value(size: 11.5).copyWith(
                  color: atFloor ? FoE.danger : Colors.white,
                  fontWeight: FontWeight.w800,
                  shadows: const [
                    Shadow(color: Color(0xCC000000), blurRadius: 2),
                    Shadow(color: Color(0x99000000), offset: Offset(0, 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The energy bar's width — wide enough for "⚡ 125% · 30h" at a glance.
  static const double _kEnergyBarWidth = 172;

  // ── Quick buttons (bottom-left dock, bottom-right row) ──
  /// THE SETTLEMENT'S CONTROLS THE FORGE-OF-EMPIRES WAY (user 2026-09-19): at
  /// the bottom RIGHT one horizontal row — Build, Monsters, Map, the three
  /// places you go to all the time; at the bottom LEFT Social, with a fold
  /// button that opens a row to its right holding every other button (Manage,
  /// Profile, Bag, Daily tasks). Build toggles the bottom carousel, which is
  /// only on screen while the player has it open. Manage is the hub for what is
  /// out on the road, who works where and the housing budget; Research is not a
  /// button (the overworld IS research now).
  ///
  /// Dev Mode deliberately NOT here: it lives in the debug row with the other
  /// dev tools. These buttons are the player's.
  Widget _quickRails() {
    final r = _railItems();
    if (r.main == null && r.right.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (r.main != null) QuickDock(main: r.main!, more: r.more),
        const Spacer(),
        if (r.right.isNotEmpty) QuickRail(items: r.right),
      ],
    );
  }

  // "main" used to always be Social, with Manage folded — swapped (user
  // 2026-09-22: "manage und social sollen noch den Platz wechseln"): Manage
  // is the tile that's always visible now, Social moved into the fold. Its
  // badge (challenges/unread messages) travels with it — summed onto the
  // fold button while closed, the same as Bag's and Daily tasks' already are.
  ({QuickPadItem? main, List<QuickPadItem> more, List<QuickPadItem> right})
  _railItems() {
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
    // firstCapture's own hand-off target (user 2026-10-01) — the same real
    // "Expedition" button normal play already uses (see the non-tutorial
    // `main` below), not a tutorial-only header cell.
    final expedition = QuickPadItem(
      Icons.travel_explore,
      'Expedition',
      _showManagement,
      anchorKey: solo == 'quick-trips'
          ? IntroSpotlightAnchors.of('quick-trips')
          : null,
    );
    // The solo hand-off has no Build tile — the tutorial's carousel is forced
    // open instead; see [_buildUnlocked]/[_showBuildCarousel].
    //
    // Reduced to whichever tiles are unlocked so far — the CURRENT step's own
    // target plus any earlier solo hand-off's tile, which stays around rather
    // than disappearing again (user 2026-09-02: "der Monsterbutton soll auch
    // bereits angezeigt werden, da dieser bereits benutzt wurde").
    if (solo != null) {
      final soloItems = [
        if (_monstersUnlocked) monsters,
        if (_mapUnlocked) map,
      ];
      // Monsters and Map live in the right-hand row now, tutorial or not;
      // Expedition is the dock's own "main" button, same as normal play.
      return (
        main: _tripsUnlocked ? expedition : null,
        more: const <QuickPadItem>[],
        right: soloItems,
      );
    }
    // No button at all until it is the one actually being used (user
    // 2026-09-02): while the intro card itself is the spotlighted control, its
    // own CTA is the only way forward.
    if (_ctrl.introStep.isActive) {
      return (
        main: null,
        more: const <QuickPadItem>[],
        right: const <QuickPadItem>[],
      );
    }
    // Opens/closes the build carousel (amber while it is open).
    final build = QuickPadItem(Icons.construction, 'Build', () {
      setState(() {
        _buildOpen = !_buildOpen;
        _requestedCategory = null;
      });
    }, active: _buildOpen);
    // While the menu is open the rails are EMPTY (user 2026-09-19: "der
    // Buildbutton soll verschwinden, wenn das Menü offen ist") — the category
    // column takes the left edge, and a tap on the map closes the menu again.
    if (_buildOpen) {
      return (
        main: null,
        more: const <QuickPadItem>[],
        right: const <QuickPadItem>[],
      );
    }
    return (
      // Build, Monsters, Map: the three you go to all the time (user
      // 2026-09-19, Forge-of-Empires layout).
      right: [build, monsters, map],
      // Verwalten (Manage), always visible — swapped with Social (user
      // 2026-09-22).
      main: QuickPadItem(Icons.travel_explore, 'Expedition', _showManagement),
      // Everything else, behind the fold button next to Manage.
      more: [
        // Waiting on you: a challenge to answer, an opponent already in
        // their lobby, your move in a fight, unread messages — the badge
        // rides along into the fold and sums onto its button while closed,
        // same as Bag's and Daily tasks' already do.
        QuickPadItem(
          Icons.group,
          'Social',
          _showSocial,
          badge:
              PvpNotifier.instance.attention + MessageNotifier.instance.unread,
        ),
        // Umbaumodus's entry point lives in the Build menu itself now (user
        // 2026-09-22: "ich will über das Baumenü in den Umbaumodus kommen") —
        // see BuildingCarousel's own right-edge button, which calls
        // _enterLayoutMode directly. A long-press on a building is still the
        // quick way to move just that one.
        // The account settings — a tile like Manage (user 2026-09-18).
        QuickPadItem(Icons.person, 'Profile', _showProfile),
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
