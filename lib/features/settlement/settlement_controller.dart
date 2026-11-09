import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../core/tuning/game_tuning.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart' show CreatureInstance;
import '../creatures/services/breeding_controller.dart';
import '../creatures/services/creature_defs_controller.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/services/combat_tuning.dart';
import '../creatures/services/expedition_controller.dart';
import '../creatures/services/battle_stars.dart';
import '../creatures/services/overworld_path.dart';
import '../creatures/services/survival_run.dart' show goldRewardForFloors;
import '../common/events/game_events.dart';
import '../onboarding/intro_flow.dart';
import 'data/building_definitions.dart';
import 'data/building_model.dart' show walkwaysFor;
import 'data/goods_definitions.dart';
import 'data/item_definitions.dart';
import 'data/road_tiles.dart';
import '../creatures/models/path_node.dart';
import 'models/energy_model.dart';
import 'models/placed_building.dart';
import 'models/resource_model.dart';
import 'models/settlement.dart';
import 'services/crafting.dart';
import 'services/daily_tasks.dart';
import 'services/game_defs_controller.dart';
import 'services/game_engine.dart';
import 'services/gold_economy.dart';
import 'services/new_items.dart';
import 'services/settlement_service.dart';
import 'services/trade_center.dart';

/// Minimum time away before the welcome-back digest shows. Shorter absences
/// (app switch, a quick lock) accrue too little to be worth a sheet.
const double kDigestMinAwayHours = 0.5;

/// Stand-in for the deleted `eraBonusTotals` (user 2026-09-05: the paid
/// Castle ascension — and the permanent wood/stone/food/build-speed bonuses
/// it granted per era — is gone entirely, not folded into anything else).
/// Kept as an all-zero constant of the exact same shape so every call site
/// that used to add these in stays structurally unchanged.
const ({double wood, double stone, double food, double all, double buildSpeed})
_noEraBonus = (wood: 0, stone: 0, food: 0, all: 0, buildSpeed: 0);

/// What happened while the player was away — resources the offline tick and
/// offline expedition resolution brought in. Built once during [SettlementController.load],
/// consumed (and cleared) by the settlement screen.
class WelcomeDigest {
  final double awayHours;

  /// Resource key → amount gained (only entries ≥ 1).
  final Map<String, double> gained;

  /// Resources whose store was FULL for part of the time away, with how many hours
  /// it stood full and about how much production that cost (estimated from the
  /// rate the settlement had when it left — production stops at the ceiling).
  final Map<String, double> fullHours;
  final Map<String, double> lost;

  /// The energy pool when the player left and on return (percent), so the digest
  /// can say it ran down. Null when energy was not loaded.
  final double? energyBefore;
  final double? energyAfter;

  const WelcomeDigest({
    required this.awayHours,
    required this.gained,
    this.fullHours = const {},
    this.lost = const {},
    this.energyBefore,
    this.energyAfter,
  });
}

/// Why the aimed spot cannot take a building (see
/// [SettlementController.placementProblem]). [label] is what the ghost's name tag
/// says about it — null for [overlap]: a footprint on top of a building is red
/// already, and words there only made the tag bigger (user 2026-09-19).
enum PlacementProblem {
  unknown('Unknown building'),
  offMap('Outside the map'),
  overlap(null),
  outsideLand('Outside your land'),
  plotMustExtend('A plot has to extend your land');

  final String? label;
  const PlacementProblem(this.label);
}

class SettlementController extends ChangeNotifier {
  // Singleton so both home and settlement share state (BP cap, unlocked techs)
  static final SettlementController _instance = SettlementController._();
  factory SettlementController() => _instance;
  // Chains GameDefsController's dev-mode def changes (DB load + realtime
  // edits) into this controller's own notifyListeners — every screen
  // already listens to SettlementController, so def edits propagate with
  // no new per-screen wiring.
  SettlementController._() {
    GameDefsController().addListener(notifyListeners);
  }

  final _svc = SettlementService();

  SettlementModel? settlement;
  ResourceModel? resources;
  EnergyModel? energy;
  List<PlacedBuilding> buildings = [];

  /// THE rate multiplier every action/production figure reads — the energy
  /// pool's own fraction, never below the floor. The pool is drained forward
  /// by every tick (5 s live, one integrated catch-up after the app was closed),
  /// so [EnergyModel.multiplier] is as current as [energy] itself is.
  double get energyMultiplier => energy?.multiplier ?? kEnergyFloorMultiplier;
  bool isDev = false;

  /// How far the new-player intro chain has got. Defaults to [IntroStep.done]
  /// so that any failure to read it (pre-migration client, offline) leaves a
  /// veteran unbothered rather than replaying the tutorial at them.
  /// See lib/features/onboarding/intro_flow.dart.
  IntroStep introStep = IntroStep.done;

  /// The jumpstart window is exactly the intro chain — progress-based, never
  /// wall-clock, so quitting after ten minutes costs the player nothing.
  bool get jumpstartActive => introStep.isActive;

  /// The Healing Hut, while it is the CURRENT build step, is excluded from
  /// this tick's construction progress entirely (user 2026-09-06: "Es soll
  /// gar kein Timer laufen" — only [skipBuildWithGold] may finish it, and
  /// that already ignores construction progress altogether). Every other
  /// site's rate is untouched by this — see [_applyTick]'s own
  /// `frozenBuildingIds`. A set rather than a bool because [GameEngine.tick]
  /// works over the whole buildings list at once, one rate for everyone;
  /// this is the one place that still needs a single building singled out.
  Set<String> get _frozenBuildingIds {
    if (introStep != IntroStep.buildHealingHut) return const {};
    return {
      for (final b in buildings)
        if (b.buildingTypeId == kHealingHutBuildingId && !b.isComplete) b.id,
    };
  }

  /// [_frozenBuildingIds], queryable by id — the building detail dialog's
  /// own live countdown (see _BuildCountdown in building_detail_dialog.dart)
  /// extrapolates progress from [buildRatePerHour] independently of any real
  /// tick, and needs to know NOT to for a frozen site; otherwise it shows a
  /// countdown visibly moving even though nothing behind it ever will (user
  /// 2026-09-06: "es läuft noch immer ein Timer beim Healing Hut").
  bool isConstructionFrozen(String buildingId) =>
      _frozenBuildingIds.contains(buildingId);

  /// Highest dungeon stage unlocked so far (permanent progression — see
  /// kMaxDungeonStage in dungeon.dart). Clearing stage N's boss unlocks N+1.
  int dungeonMaxStage = 1;

  /// Campaign battles won on the linear overworld path (user 2026-07-24). This
  /// is the FINE progress counter: the player's position on the one numbered
  /// line of battles. It drives party size (see [partyCap]) and, in the linear
  /// rebuild, map-milestone unlocks. Advanced by [advanceBattlesCleared] on a
  /// won battle. Persisted (profiles.battles_cleared, migration 0019).
  int battlesCleared = 0;

  /// Deepest Survival Mode run ever banked (user 2026-09-06) — a high score,
  /// not a gate: unlike [battlesCleared] nothing reads this to unlock
  /// anything, it only ever gets bigger. Persisted
  /// (profiles.survival_best_floor, migration 0042). Set by
  /// [recordSurvivalRun], never by the running screen itself — the same
  /// "only the controller writes state" split [advanceBattlesCleared] uses.
  int survivalBestFloor = 0;

  /// The best stars (1–3) the player has earned in each campaign battle, by
  /// battle number (user 2026-09-28). Only ever raised — a poor rematch never
  /// takes a star away. Persisted (profiles.battle_stars, migration 0058). Set
  /// by [recordBattleStars].
  Map<int, int> battleStars = {};

  /// The best stars in [battle], 0 when it has none yet.
  int starsFor(int battle) => battleStars[battle] ?? 0;

  /// Every star earned so far.
  int get totalStars => battleStars.values.fold(0, (a, b) => a + b);

  /// Banks the result of a won battle. Returns the gold paid as the ONE-TIME
  /// bonus for stars reached for the first time (see [firstTimeStarGold]); 0 for
  /// a rematch that did not beat the best. Nothing here can lower a record.
  Future<int> recordBattleStars(int battle, int stars) async {
    final before = starsFor(battle);
    if (stars <= before) return 0;
    battleStars = {...battleStars, battle: stars};
    final gold = firstTimeStarGold(before, stars);
    if (gold > 0) await grantResources({'gold': gold.toDouble()});
    _progressDirty = true;
    notifyListeners();
    await _persist();
    return gold;
  }

  /// Max party the player may currently field — for standing teams and
  /// expedition groups (things not tied to one specific battle node). It's the
  /// size allowed for the NEXT battle on the line: clear 5 battles and battle 6
  /// permits two, so the allowance becomes two the moment battle 5 falls.
  /// A specific battle NODE instead uses partySizeForBattle(its own number),
  /// so re-fighting an early battle stays 1v1.
  int get partyCap => partySizeForBattle(battlesCleared + 1);

  /// Expansion unlocks EARNED as a reward — one per "expansion point" cleared
  /// on the map (user 2026-07-17). Drives [buildPlotLimit]: 0 = no Building
  /// Plots yet, each unlock allows one more. Persisted (profiles table).
  int expansionsUnlocked = 0;

  bool isLoading = true;
  String? error;

  /// Set by [load] when the player was away ≥ [kDigestMinAwayHours]; the
  /// settlement screen shows it once and clears it.
  WelcomeDigest? pendingDigest;

  /// Today's three rotating goals (user 2026-07-21). Rolled deterministically
  /// per UTC date; progress reported via [reportDailyProgress] from the gather
  /// resolve, captureWild and battle-victory hooks.
  DailyTasksState dailyTasks = rollDailyTasks(DateTime.now().toUtc());

  /// Replaces today's set when the stored one is from an earlier day. Called
  /// on load and from the ticker, so a session crossing midnight rolls over.
  void _rolloverDailyTasks(DateTime now) {
    if (dailyTasks.dateKey != dateKeyFor(now)) {
      // The streak and the date of the last chest carry over; the tasks do not.
      dailyTasks = rollDailyTasks(
        now,
        carry: dailyTasks,
        exclude: _impossibleDailyTasks,
      );
      _saveDailyTasks();
    }
  }

  /// Daily-task kinds this settlement cannot make progress on today — the
  /// building that makes them possible is not standing (complete) yet. Fed to
  /// [rollDailyTasks] so a fresh account is never dealt "Hatch an egg" with
  /// no Hatchery, which forfeited the day's chest and broke the streak.
  Set<DailyTaskKind> get _impossibleDailyTasks {
    bool has(bool Function(BuildingDef def) test) => buildings.any((b) {
      if (!b.isComplete) return false;
      final def = placedDefOf(b);
      return def != null && test(def);
    });
    final era = dungeonMaxStage;
    return {
      if (!has((d) => d.id == kHatcheryBuildingId)) DailyTaskKind.hatchEggs,
      if (!has((d) => d.id == kHealingHutBuildingId))
        DailyTaskKind.healMonsters,
      if (!has((d) => d.hasEffect('craftSlots', era))) DailyTaskKind.craftItems,
    };
  }

  void _saveDailyTasks() {
    final id = settlement?.id;
    if (id != null) {
      // Fire-and-forget: task progress is a nicety, never worth blocking on.
      _svc.saveDailyTasks(id, dailyTasks.toJson());
    }
  }

  /// Advances every unclaimed task of [kind] by [amount]. Safe to call from
  /// anywhere (no-op when nothing matches).
  void reportDailyProgress(DailyTaskKind kind, [int amount = 1]) {
    _rolloverDailyTasks(DateTime.now().toUtc());
    var changed = false;
    for (final t in dailyTasks.tasks) {
      if (t.kind != kind || t.claimed || t.done) continue;
      t.progress = (t.progress + amount).clamp(0, t.target);
      changed = true;
    }
    if (changed) {
      _saveDailyTasks();
      notifyListeners();
    }
  }

  /// Opens today's DAILY CHEST once all three tasks are claimed: gold and items
  /// for the streak day this opens (see [chestForStreakDay]), and the streak goes
  /// up by one — or starts again at 1 if yesterday's chest was missed. Returns
  /// the chest, or null when there is nothing to open.
  Future<DailyChest?> claimDailyChest() async {
    final now = DateTime.now().toUtc();
    _rolloverDailyTasks(now);
    final state = dailyTasks;
    if (!state.chestReady) return null;
    final day = state.nextChestDay(now);
    final chest = chestForStreakDay(day);
    state.streak = day;
    state.lastChestKey = state.dateKey;
    await grantResources({'gold': chest.gold.toDouble()});
    if (chest.items.isNotEmpty) {
      _grantItems(chest.items);
      await _persist();
    }
    _saveDailyTasks();
    notifyListeners();
    return chest;
  }

  /// Claims a finished task's reward. Returns a user-facing error or null.
  Future<String?> claimDailyTask(int index) async {
    if (index < 0 || index >= dailyTasks.tasks.length) return 'No such task';
    final t = dailyTasks.tasks[index];
    if (!t.claimable) return t.claimed ? 'Already claimed' : 'Not done yet';
    t.claimed = true;
    await grantResources(t.reward);
    _saveDailyTasks();
    notifyListeners();
    return null;
  }

  Timer? _tickTimer;

  // ── Bootstrap ─────────────────────────────────────────────
  Future<void> load() async {
    // Cancel any leftover ticker so we never run two simultaneous timers.
    _tickTimer?.cancel();
    _tickTimer = null;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final userId = supabase.auth.currentUser!.id;
      settlement = await _svc.getOrCreate(userId);
      final sid = settlement!.id;

      // Named futures rather than a positional list read back by index.
      // The list version cost a real bug: dropping the tech-gates load (BP
      // removal) shifted every slot after it, so `isDev` silently started
      // reading a def-loader's void and the intro step read off the end. With
      // names, adding or removing a load can't quietly re-point another one.
      final resourcesF = _svc.loadResources(sid);
      final energyF = _svc.loadEnergy(sid);
      final buildingsF = _svc.loadBuildings(sid);
      final profileF = _svc.loadProfile(userId);
      final isDevF = _svc.loadIsDev(userId);
      final starsF = _svc.loadBattleStars(userId);
      final introF = _svc.loadIntroStep(userId);
      // Dev-mode building/tech defs — RLS requires an authenticated user, so
      // these load here (post-login) rather than in main.dart. Bundled
      // fallback defs are already usable before they resolve. Nothing reads
      // their results; the def maps are global.
      final defsF = GameDefsController().load();
      final creatureDefsF = CreatureDefsController().load();
      // The tuning dials (user 2026-07-29). AWAITED with the defs, unlike the
      // combat dials below: these decide the level curve, the energy budget and
      // the slot counts, and the very first tick reads them — resolving them a
      // frame late would run one tick of the settlement on the code defaults.
      final tuningF = GameTuning.i.load();
      // The creature collection IS the workforce: workshopPower() (and the
      // offline _applyTick below) read CreaturesController().creatures, so it
      // must load here rather than lazily on the creatures screen — otherwise
      // the economy produces nothing until that screen is opened.
      final creaturesF = CreaturesController().load();
      // Dev-tunable combat dials — read once here, graceful if the table
      // isn't there yet (see CombatTuning.load). Fire-and-forget: combat
      // reads the statics live, so nothing awaits it.
      unawaited(CombatTuning().load());
      await Future.wait([
        resourcesF,
        energyF,
        buildingsF,
        profileF,
        isDevF,
        introF,
        defsF,
        creatureDefsF,
        creaturesF,
        tuningF,
      ]);

      resources = await resourcesF;
      energy = await energyF;
      buildings = await buildingsF;
      // NO TRIM ON LOAD any more (user 2026-07-30). Being over the ceiling is a
      // legal state since resource packs exist — you redeemed one — and the
      // price is paid by the production halt, not by deleting the stock. A save
      // made before ceilings existed simply drains back under instead of losing
      // the difference in one silent step.
      final profile = await profileF;
      isDev = await isDevF;
      dungeonMaxStage = profile['dungeon_max_stage'] ?? 1;
      expansionsUnlocked = profile['expansions_unlocked'] ?? 0;
      battlesCleared = profile['battles_cleared'] ?? 0;
      survivalBestFloor = profile['survival_best_floor'] ?? 0;
      battleStars = await starsF;
      introStep = IntroStep.fromIndex(await introF);
      // Tutorial master switch: coerce to done in memory WITHOUT persisting,
      // so re-enabling kIntroEnabled resumes the account where the DB says.
      // Everything tutorial-related (overlay, card, jumpstart, bent rules)
      // keys off introStep.isActive, so this one line silences all of it.
      if (!kIntroEnabled) introStep = IntroStep.done;
      // Self-heal: the intro step is advanced by milestone callbacks, which a
      // crash or a failed write can miss.
      if (introStep.isActive) {
        // Beating a region boss ends the intro outright, whatever step it
        // claims. Without this the jumpstart's 5x build/research speed would
        // ride along indefinitely for anyone who simply never researches a
        // gated tech — and that IS a rate change, which is exactly what
        // docs/balancing.md §6 says must not happen.
        if (dungeonMaxStage > 1) {
          introStep = IntroStep.done;
          unawaited(_svc.saveIntroStep(userId, introStep.index));
        } else if (introStep == IntroStep.pickStarter &&
            CreaturesController().creatures.isNotEmpty) {
          // Owning a creature demonstrably means step 1 is done.
          introStep = IntroStep.pickStarter.next;
          unawaited(_svc.saveIntroStep(userId, introStep.index));
        }
      }
      // introStep decides which answer connectedBuildingIds caches, and it
      // has just been read from the DB and possibly corrected twice above.
      _connectedCache = null;

      debugPrint(
        '[LOAD] From DB — '
        'lastUpdatedAt=${energy!.lastUpdatedAt.toIso8601String()} '
        'energy=${energy!.energyPct.toStringAsFixed(1)}% steps=${energy!.stepsToday} '
        'wood=${resources!.wood.toStringAsFixed(0)} '
        'stone=${resources!.stone.toStringAsFixed(0)} '
        'buildings=${buildings.length}',
      );

      // Load-time migration: if more active builds than slots, queue the excess.
      {
        final maxSlots = maxBuildSlots;
        final active =
            buildings.where((b) => !b.isComplete && !b.isQueued).toList()
              ..sort((a, b) => a.placedAt.compareTo(b.placedAt));
        if (active.length > maxSlots) {
          final toQueue = active.skip(maxSlots).map((b) => b.id).toSet();
          _buildingsDirty = true;
          buildings = [
            for (final b in buildings)
              if (toQueue.contains(b.id)) b.copyWith(isQueued: true) else b,
          ];
        }
      }

      // Apply offline production FIRST using the original lastUpdatedAt from Supabase.
      final beforeStone = resources!.stone;
      // Snapshot for the welcome-back digest: everything the offline tick AND
      // the offline expedition resolve (below) add lands in this diff.
      final beforeAll = resources!.asMap;
      // What the offline tick could NOT add because a store was full: worked out
      // from the rates and ceilings the settlement had on leaving.
      final ratesBefore = hourlyRates;
      final capsBefore = storageCaps;
      final energyBefore = energy!.energyPct;
      final now = DateTime.now().toUtc();
      final hoursDelta =
          now.difference(energy!.lastUpdatedAt).inMicroseconds / 3.6e9;
      _applyTick(now);
      debugPrint(
        '[LOAD] After tick — '
        'hoursDelta=${hoursDelta.toStringAsFixed(4)}h '
        'stone: ${beforeStone.toStringAsFixed(0)} → ${resources!.stone.toStringAsFixed(0)} '
        'energy=${energy!.energyPct.toStringAsFixed(1)}% steps=${energy!.stepsToday}',
      );

      await _persist();

      // Resolve any expeditions that finished while the app was closed and
      // sync creature locks. Offline-safe and internally tolerant of the
      // expeditions migration not being applied yet (degrades to no-op).
      await ExpeditionController().load(force: true);

      // Breeding jobs load HERE too (user 2026-07-27: "eggs werden aktuell
      // nicht gespeichert … erst wenn ich die hatchery geöffnet habe, wurde das
      // ei erneut in den bag geschoben").
      //
      // The rows were always persisted — nothing was ever lost. But the only
      // callers of load() were the collection and hatchery screens, so on a
      // fresh start the singleton held an EMPTY list, and the Bag's Eggs drawer
      // reads straight off it: an egg you owned looked gone until you happened
      // to walk into the Hatchery.
      //
      // After the creature load above, because promoting a finished mating
      // rolls the child from its parents' live genes — with an empty collection
      // it would freeze nothing and the egg would hatch off the species curve.
      // The same reason expeditions resolve here: what finished while the app
      // was closed must land before the player sees any of it.
      await BreedingController().load(force: true);

      // Welcome-back digest (user 2026-07-21): the passive economy used to
      // accrue in silence — the player never EXPERIENCED their income. Away
      // long enough, the screen greets them with what happened instead.
      if (hoursDelta >= kDigestMinAwayHours) {
        final gained = <String, double>{};
        resources!.asMap.forEach((key, v) {
          final delta = v - (beforeAll[key] ?? 0);
          if (delta >= 1) gained[key] = delta;
        });
        // A store that reached its ceiling while away stopped producing: how long
        // it stood full, and what that cost.
        final fullHours = <String, double>{};
        final lost = <String, double>{};
        ratesBefore.forEach((key, rate) {
          final cap = capsBefore[key] ?? 0;
          if (rate <= 0 || cap <= 0) return;
          final toFull = math.max(0.0, (cap - (beforeAll[key] ?? 0)) / rate);
          if (toFull >= hoursDelta) return;
          final hours = hoursDelta - toFull;
          if (hours >= 1 && rate * hours >= 1) {
            fullHours[key] = hours;
            lost[key] = rate * hours;
          }
        });
        pendingDigest = WelcomeDigest(
          awayHours: hoursDelta,
          gained: gained,
          fullHours: fullHours,
          lost: lost,
          energyBefore: energyBefore,
          energyAfter: energy?.energyPct,
        );
      }

      // Self-heal: unassign creatures whose POST no longer exists — the
      // building is gone, or its def lost the workshop role (the main hall
      // dropped all worker slots, user 2026-07-22). Without this they'd sit
      // "assigned" forever, showing as workers while contributing nothing.
      {
        final creaturesCtrl = CreaturesController();
        for (final c in List.of(creaturesCtrl.creatures)) {
          final bId = c.assignedBuildingId;
          final stat = c.assignedStat;
          if (bId == null || stat == null) continue;
          PlacedBuilding? placed;
          for (final b in buildings) {
            if (b.id == bId) {
              placed = b;
              break;
            }
          }
          final def = placed == null
              ? null
              : placedDefOf(placed);
          final valid = def != null && def.workshops.any((w) => w.stat == stat);
          if (!valid) {
            await assignCreatureToWorkshop(c.id, null, null);
          }
        }
      }

      // Daily tasks: restore today's saved progress, else keep the fresh roll.
      // (A stored set from an earlier date is simply superseded.)
      final storedTasks = await _svc.loadDailyTasks(settlement!.id);
      if (storedTasks != null) {
        final restored = DailyTasksState.fromJson(storedTasks);
        // Today's saved progress if it is from today, else a fresh roll — but
        // the streak lives on either way.
        dailyTasks = restored.dateKey == dateKeyFor(now)
            ? restored
            : rollDailyTasks(
                now,
                carry: restored,
                exclude: _impossibleDailyTasks,
              );
      } else {
        // First load ever: the field's own initial roll happened before any
        // building was known, so it could not filter. Roll again now.
        dailyTasks = rollDailyTasks(now, exclude: _impossibleDailyTasks);
      }

      // 10s, not 5 (2026-09-12, chasing Chrome-debug responsiveness) — every
      // firing does real work three times over: GameEngine.tick sums
      // production across every building, notifyListeners rebuilds the
      // whole settlement screen (the map included), and _persist writes
      // resources/energy/settlement to Supabase. Halving how often that
      // fires halves all three costs at once. Still comfortably granular —
      // The Energy page's countdown only shows minute resolution at this
      // drain rate, and every number here reads as "a few seconds behind",
      // never as stalled.
      _tickTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _applyTick(DateTime.now().toUtc());
        _rolloverDailyTasks(DateTime.now().toUtc());
        notifyListeners();
        _persist();
      });
    } catch (e) {
      error = e.toString();
    }

    isLoading = false;
    notifyListeners();
  }

  // Call when leaving the settlement screen — stops tick without disposing singleton.
  void stopTicker() {
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// Full account wipe: buildings, resources, energy, research, tech gates,
  /// the creature collection, breeding, expeditions and the profile
  /// (BP/level/region progress/intro) — back to a first-launch state, intro
  /// chain and jumpstart included. Authored `*_defs` content is never touched.
  Future<void> resetSettlement() async {
    final userId = _userId;
    if (settlement == null || userId == null) return;
    // A dev account keeps its grant float across the reset — see kDevResetFloat.
    await _svc.resetSettlement(settlement!.id, userId, devFloat: isDev);

    // These singletons cache their rows behind a _loadedOnce guard, and the
    // load() below calls them WITHOUT force — so without this the app would
    // keep listing creatures that no longer exist, and worse, load()'s intro
    // self-heal would see a non-empty collection and skip "pick your starter".
    await Future.wait([
      CreaturesController().load(force: true),
      BreedingController().load(force: true),
    ]);
    await load();
  }

  // ── Housing (creatures ARE the population) ─────────────────
  // How many creatures the settlement can shelter (sum of functional housing
  // buildings' capacity). Every creature the player owns occupies one slot; a
  // full settlement blocks catching/hatching/adopting (enforced in
  // CreaturesController via [housingFull]).
  int get housingCapacity => resources == null
      ? 0
      : GameEngine.housingCapacity(buildings, eraOrder: dungeonMaxStage);

  /// A legendary lives in its own lair and takes no housing (user
  /// 2026-11-07: "kein Housing sonst").
  int get housingUsed => CreaturesController().creatures
      .where((c) => c.species?.rarity != CreatureRarity.legendary)
      .length;

  int get housingFree =>
      (housingCapacity - housingUsed).clamp(0, housingCapacity);

  bool get housingFull => housingUsed >= housingCapacity;

  // ── Workshop power (creature-driven production) ────────────
  // Sums, per output, the relevant civilian stat of every creature currently
  // stationed in a functional workshop and actually able to work (not K.O.,
  // has energy, not breeding). Keys are settlement resource ids ('wood',
  // 'stone', 'gold', 'fish', 'meat') plus the pseudo-outputs
  // WorkshopRole.kConstruction / kResearch. This is THE bridge between the
  // creature collection and the settlement economy — tick(), hourlyRates and
  // the countdown estimates all read it.
  /// The settlement's expedition amplifiers: summed over functional,
  /// road-connected buildings' authored `expedition` effects. Travel is floored
  /// at 40% so stacked scout posts can never zero a trip.
  ///
  /// The code-side warehouse/scout/smokehouse table is GONE (user 2026-07-25:
  /// "alle hardcoded boni bitte löschen … es zählt nur das, was bei den
  /// Effekten steht") — a building amplifies trips only if its effects say so.
  ({double carryMult, double travelMult, double goodsMult})
  get expeditionBonuses {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    double carry = 0, travel = 0, goods = 0;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      carry += def.effectAt('expedition', 'carry', era, level: b.level);
      travel += def.effectAt('expedition', 'travel', era, level: b.level);
      goods += def.effectAt('expedition', 'goods', era, level: b.level);
    }
    // …plus the STAFF of the logistics posts (user 2026-07-25): a warehouse
    // raises the load only while somebody works in it. workshopPower already
    // sums stat × mult × level for these role outputs.
    final power = workshopPower();
    carry += power[WorkshopRole.kExpCarry] ?? 0;
    travel += power[WorkshopRole.kExpTravel] ?? 0;
    goods += power[WorkshopRole.kExpGoods] ?? 0;
    return (
      carryMult: 1 + carry,
      travelMult: _travelMult(travel),
      goodsMult: 1 + goods,
    );
  }

  /// Whole-number total of a keyless COUNT effect (`expeditionSlots`,
  /// `huntOptions`) over every functional building.
  ///
  /// Flat by default — an authored per-effect factor scales it, an unset one
  /// leaves it alone (levelScaleExplicit). Counts are not yields: a scout post
  /// that silently opened +50% of a hunt variant per level would be nonsense.
  int _countEffectTotal(String type) {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    int total = 0;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      final e = def.effectEntry(type, '', era);
      if (e == null) continue;
      // An explicit levelSteps ladder is the natural shape for a count ("one
      // more hunt variant at level 3"), so it wins where it is authored.
      total +=
          (e.levelSteps.isNotEmpty
                  ? e.valueAtLevel(b.level)
                  : e.value * e.levelScaleExplicit(b.level))
              .floor();
    }
    return total;
  }

  /// [travel] points of shortening, as the factor a trip's duration is
  /// multiplied by.
  ///
  /// NO CEILING (user 2026-07-29: "expeditions soll kein cap bei 60% haben").
  /// It was `(1 - travel).clamp(0.4, 1.0)`: a hard wall at −60 %, past which
  /// another scout, another level and another post all bought exactly nothing,
  /// with nothing on screen to say so.
  ///
  /// A hyperbola instead — the SAME shape build time, breeding and the trade
  /// road already use (`cut = S/(S+100)`). Every point still helps, the help
  /// gets smaller, and the curve approaches an instant trip without ever
  /// reaching it. At the small values buildings actually author it is nearly
  /// the old straight line (0.10 → −9 % against −10 %); where the wall used to
  /// stand it is −60 % at 1.5 points and keeps going.
  ///
  /// The floor is arithmetic, not policy: a trip of zero seconds resolves in
  /// the same tick it is sent, which is not a fast expedition, it is a broken
  /// one.
  static double _travelMult(double travel) =>
      travel <= 0 ? 1.0 : 1 / (1 + travel);

  // ── What the settlement can HOLD (user 2026-07-30) ──────────────────────
  // "Ein Lager für die Ära 1 … welches alle Produktion und Luxusressourcen
  // lagern kann. Zusätzlich ein Goldlager." — and, on how it behaves:
  // production STOPS at the ceiling, capacity is per resource, and a save made
  // before the ceilings existed is trimmed to them.
  //
  // Ceilings are ordinary authored effects (`storage`, keyed by resource), so a
  // store is a building like any other: it is worth levelling, it has to be
  // road-connected to count, and every number in it is dev-tunable. What the
  // settlement holds WITHOUT one is a dial, not a hidden grant.

  /// The ceiling on [resource] — every functional building's authored
  /// `storage` effect for it, plus the room its posted logisticians make
  /// (user 2026-07-30).
  ///
  /// The staff's room only counts for a resource the building actually stores:
  /// a store's post amplifies what that store holds, the way every post reads
  /// what it amplifies. So a logistician in the Gold Vault raises the gold
  /// ceiling and nothing else, and one in the Storehouse raises all four of its
  /// goods by the same amount.
  ///
  /// ── The flat dial is a FALLBACK now, not a given (user 2026-08-31: "alle
  /// Anfangslagerplätze sollen vom Castle kommen") ──
  /// Wood/stone/gold used to start from [Dials.baseStorage]/
  /// [Dials.baseGoldStorage] unconditionally, on top of whatever a building
  /// added — an invisible number no building's own card could explain, and
  /// one that never grew no matter how the settlement did. The Castle now
  /// authors that same starting room as its own `storage` effects (see
  /// building_effects.dart), so it reads on the Castle's own card and grows
  /// with its level like everything else it does. The dial still applies,
  /// but only to a resource NO building — Castle included — has anything to
  /// say about yet: a later era's good with no store built for it still
  /// gets somewhere to sit, exactly as it always has.
  double storageCapacity(String resource) {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    var total = 0.0;
    var anyBuildingStoresIt = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      // No `storage` effect for this resource → this building does not hold it,
      // so neither its ceiling nor its staff has anything to say about it.
      if (def.effectEntry('storage', resource, era) == null) continue;
      anyBuildingStoresIt = true;
      total += def.effectAt('storage', resource, era, level: b.level);
      total += storageRoomPosted(b, resource);
    }
    if (!anyBuildingStoresIt) {
      total += resource == 'gold'
          ? GameTuning.i.raw(Dials.baseGoldStorage)
          : GameTuning.i.raw(Dials.baseStorage);
    }
    return total;
  }

  /// Every ceiling that currently applies, by resource — what ResourceModel
  /// .capped clamps against. Built from the resources the settlement actually
  /// holds PLUS every resource some building stores, so a ceiling is visible
  /// before the first unit of that good ever arrives.
  Map<String, double> get storageCaps {
    final keys = <String>{
      'wood',
      'stone',
      'gold',
      ...?resources?.goods.keys,
      ...kGoodsDefs.keys,
    };
    return {for (final k in keys) k: storageCapacity(k)};
  }

  /// Resource ids sitting at their ceiling right now — production on those has
  /// stopped, which is the one thing a full store must not do quietly.
  List<String> get fullStores =>
      resources?.atCapacity(storageCaps).toList() ?? const [];

  /// WHERE the room for [resource] comes from, PER BUILDING (user
  /// 2026-08-31) — the new Storage screen's own list, one row per instance
  /// rather than [storageSources]' by-type grouping, same reasoning as
  /// [productionSourcesByBuilding]. A building's own posted logisticians are
  /// folded into ITS row rather than a separate settlement-wide "on duty"
  /// line — per instance, the staff belongs to the building they are posted
  /// in, the same building the row's own tap opens.
  List<(PlacedBuilding, BuildingDef, double)> storageSourcesByBuilding(
    String resource,
  ) {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    final out = <(PlacedBuilding, BuildingDef, double)>[];
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      if (def.effectEntry('storage', resource, era) == null) continue;
      final room =
          def.effectAt('storage', resource, era, level: b.level) +
          storageRoomPosted(b, resource);
      if (room <= 0) continue;
      out.add((b, def, room));
    }
    return out;
  }

  /// Extra concurrent expedition slots from functional buildings' per-era
  /// `expeditionSlots` effects — on top of [kBaseExpeditionSlots].
  int get buildingExpeditionSlots => _countEffectTotal('expeditionSlots');

  /// Extra concurrent CARAVAN slots — the Caravanserai's `caravanSlots`
  /// effect, on top of [kBaseCaravanSlots]. Its own count, so a Scout Post
  /// cannot put more traders on the road (user 2026-07-29).
  int get buildingCaravanSlots => _countEffectTotal('caravanSlots');

  /// What the settlement's buildings do for a TRADE CARAVAN: how much it hauls
  /// and how long the run takes.
  ///
  /// The twin of [expeditionBonuses] and deliberately NOT the same numbers.
  /// A caravan and a hunting party are both groups of monsters away on a
  /// timer, but nothing that helps one has any business helping the other: a
  /// warehouse full of gathered ore does not make a trade run faster, and a
  /// scout who knows the forest paths does not know the market road. The
  /// Caravanserai is the building that knows the market road — see
  /// [WorkshopRole.kCarCarry] / [WorkshopRole.kCarTravel].
  ///
  /// There is no `goods` counterpart: a caravan's return is PRICED at send (see
  /// ExpeditionController.startTrade), so a yield multiplier would either be
  /// ignored or let the settlement renegotiate mid-road.
  ({double carryMult, double travelMult}) get caravanBonuses {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    double carry = 0, travel = 0;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      carry += def.effectAt('caravan', 'carry', era, level: b.level);
      travel += def.effectAt('caravan', 'travel', era, level: b.level);
    }
    final power = workshopPower();
    carry += power[WorkshopRole.kCarCarry] ?? 0;
    travel += power[WorkshopRole.kCarTravel] ?? 0;
    return (
      carryMult: 1 + carry,
      // The same curve the expeditions use — the caravan version only ever
      // existed as its mirror.
      travelMult: _travelMult(travel),
    );
  }

  /// How many of the LONGER hunt variants the settlement's buildings have
  /// opened (user 2026-07-26: "jagdt an scout"). The shortest hunt always
  /// exists; each point here adds the next entry of kCaptureHuntOptions.
  int get buildingHuntOptions => _countEffectTotal('huntOptions');

  /// The same, from the authored path instead of a building (user
  /// 2026-09-14: "ich muss beim Pfad die längeren Hunts als Belohnung
  /// einstellen können") — a node's PathRewards.huntOptions, summed. Adds
  /// to [buildingHuntOptions] at every call site rather than replacing it,
  /// so a Scout Post upgrade and a path reward both count.
  int get pathHuntOptions => pathHuntOptionsGranted(battlesCleared);

  /// Fractional reduction to heal [target] ('speed' | 'cost') from functional
  /// buildings' per-era `heal` effects, summed and capped at 90%.
  double healReduction(String target) {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    double total = 0;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      final e = def.effectEntry('heal', target, era);
      if (e != null) total += e.value * e.levelScaleExplicit(b.level);
    }
    // Posted HEALERS speed treatment up (user 2026-07-25) — the `medicine`
    // stat's job. Only speed: what healing COSTS is the building's business.
    if (target == 'speed') {
      total += workshopPower()[WorkshopRole.kHealSpeed] ?? 0;
    }
    // The ceiling is a DIAL since 2026-07-29 (Settlement → Heilen).
    return total.clamp(0.0, GameTuning.i.raw(Dials.healMaxCut));
  }

  /// How many creatures can be under treatment AT ONCE across all functional
  /// buildings (user 2026-07-25) — summed from their per-level `healSlots`
  /// effects (Healing Hut). Returns null when NO building authored the effect:
  /// that means "unlimited", the game's original behaviour, so a save with no
  /// healSlots set keeps healing everyone in parallel. A real cap (even 0) is
  /// returned the moment any building defines the effect.
  int? get healCapacity {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    int total = 0;
    var authored = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null || !def.hasEffect('healSlots', era)) continue;
      authored = true;
      // A hut with nobody stationed contributes NOTHING (user 2026-08-24):
      // still `authored`, so the building keeps reading as "a real healing
      // building at 0 capacity" rather than vanishing from the null-means-
      // unlimited case above — it just heals no one until someone works it.
      if (workshopOccupancy(b.id, CreatureStat.medicine) <= 0) continue;
      total += def.healSlotsAt(b.level, eraOrder: era);
    }
    return authored ? total : null;
  }

  // ── The Workshop's benches and its queue (user 2026-07-30) ──────────────
  // "wieviele items gleichzeitig produziert werden können und eine
  // warteschlange … beides will ich pro Level einstellen können." Same pair,
  // same shape and same summing rule as the Healing Hut's slots and line.

  /// How many items are made AT ONCE — summed from the functional buildings'
  /// per-level `craftSlots` effects.
  ///
  /// ONE when no building authors any, which is exactly what the Workshop did
  /// before benches existed: a settlement mid-craft keeps working rather than
  /// stopping because a new effect has not been authored onto its building yet.
  int get craftCapacity {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    var total = 0;
    var authored = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null || !def.hasEffect('craftSlots', era)) continue;
      authored = true;
      total += def.effectAt('craftSlots', '', era, level: b.level).round();
    }
    return authored ? total : 1;
  }

  /// How many items may WAIT for a free bench. Null = no building authored one,
  /// i.e. an endless line — the same "unauthored means unlimited" rule the
  /// healing queue follows.
  int? get craftQueueCapacity {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    var total = 0;
    var authored = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null || !def.hasEffect('craftQueue', era)) continue;
      authored = true;
      total += def.effectAt('craftQueue', '', era, level: b.level).round();
    }
    return authored ? total : null;
  }

  /// Everything on a bench or in line, in order.
  List<CraftJob> get craftJobs => settlement?.craftJobs ?? const [];

  /// The ones actually being made — the first [craftCapacity] of them.
  List<CraftJob> get activeCraftJobs => craftJobs.take(craftCapacity).toList();

  /// The ones waiting for a bench.
  List<CraftJob> get queuedCraftJobs => craftJobs.skip(craftCapacity).toList();

  /// Whether another item can be put in at all — benches plus line.
  bool get canQueueCraft {
    final queueCap = craftQueueCapacity;
    if (queueCap == null) return true; // unauthored line = endless
    return craftJobs.length < craftCapacity + queueCap;
  }

  /// How many creatures may WAIT for a treatment (user 2026-07-27) — summed
  /// from the functional buildings' per-level `healQueue` effects, exactly as
  /// [healCapacity] sums their `healSlots`. Null = no building authored one,
  /// which means an unlimited line.
  ///
  /// A cap the queue can hit is what keeps it a decision: with room for four,
  /// putting the tank in line is choosing it over somebody else.
  int? get healQueueCapacity {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    int total = 0;
    var authored = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null || !def.hasEffect('healQueue', era)) continue;
      authored = true;
      total += def.healQueueAt(b.level, eraOrder: era);
    }
    return authored ? total : null;
  }

  /// How many creatures the Combat School can teach AT ONCE (user 2026-09-05)
  /// — summed from the functional buildings' per-level `trainSlots` effects.
  /// Null = no building authored one, meaning unlimited (same "unauthored
  /// means unlimited" rule [healCapacity] follows). Unlike the Healing Hut
  /// there is no workshop role staffing this — see building_effects.dart's
  /// `combat_school` entry for why — so an authored building always
  /// contributes, whether or not anyone works there.
  int? get trainCapacity {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    var total = 0;
    var authored = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null || !def.hasEffect('trainSlots', era)) continue;
      authored = true;
      total += def.trainSlotsAt(b.level, eraOrder: era);
    }
    return authored ? total : null;
  }

  /// How many creatures may WAIT for a lesson — from `trainQueue` effects,
  /// exactly as [trainCapacity] sums `trainSlots`. Null = unlimited line.
  int? get trainQueueCapacity {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    var total = 0;
    var authored = false;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null || !def.hasEffect('trainQueue', era)) continue;
      authored = true;
      total += def.trainQueueAt(b.level, eraOrder: era);
    }
    return authored ? total : null;
  }

  /// How much better this settlement's trade rates are than the base spread
  /// (user 2026-07-25) — the summed `trade` effect of every functional building
  /// (the Trade Center), as a 0..[kMaxTradeDiscount] fraction.
  ///
  /// 0 without a working Trade Center, which is the point: the sheet is only
  /// reachable through the building, and levelling it is what narrows the spread.
  double get tradeDiscount {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    var percent = 0.0;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      percent += def.tradePercentAt(b.level, eraOrder: era);
    }
    // Posted TRADERS haggle on top of what the building itself is worth (user
    // 2026-07-25) — the `trade` stat's job. Same cap for both together.
    final staffed = workshopPower()[WorkshopRole.kTradeRate] ?? 0;
    return (percent / 100 + staffed).clamp(0.0, kMaxTradeDiscount);
  }

  /// Combined `breeding`-stat power of the creatures stationed in the MATING
  /// posts of the (complete, road-connected) building(s) of [buildingTypeId] —
  /// the Breeding Hut (user 2026-07-24). This is the magnitude that shortens a
  /// mating (fed to breedingHours): each stationed breeder contributes its
  /// breeding stat, scaled by the role's mult and the building's level. 0 when
  /// the building is missing or empty, so a job runs at the rarity base.
  double breedingPower(String buildingTypeId) =>
      _postPower(buildingTypeId, WorkshopRole.kBreeding);

  /// The same for the Hatchery's INCUBATION posts (user 2026-07-26). Separate
  /// buildings, separate posts — staffing the hut no longer speeds up eggs.
  ///
  /// Falls back to the [WorkshopRole.kBreeding] role when a def authors no
  /// hatching one: every Hatchery saved before the split staffs that role, and
  /// silently reading 0 would have stopped those eggs from ever speeding up.
  double hatchingPower(String buildingTypeId) => _postPower(
    buildingTypeId,
    WorkshopRole.kHatching,
    fallbackResource: WorkshopRole.kBreeding,
  );

  double _postPower(
    String buildingTypeId,
    String roleResource, {
    String? fallbackResource,
  }) {
    final connected = connectedBuildingIds;
    // The placed buildings of this type that are actually functional.
    final active = <String, PlacedBuilding>{};
    for (final b in buildings) {
      if (b.buildingTypeId != buildingTypeId) continue;
      if (!b.isComplete || !connected.contains(b.id)) continue;
      active[b.id] = b;
    }
    if (active.isEmpty) return 0;
    final def = kBuildingDefs[buildingTypeId];
    if (def == null) return 0;
    WorkshopRole? role;
    for (final r in def.workshops) {
      if (r.resource == roleResource) {
        role = r;
        break;
      }
    }
    if (role == null && fallbackResource != null) {
      for (final r in def.workshops) {
        if (r.resource == fallbackResource) {
          role = r;
          break;
        }
      }
    }
    if (role == null) return 0;
    final creatures = CreaturesController();
    var power = 0.0;
    for (final c in creatures.creatures) {
      final b = active[c.assignedBuildingId];
      if (b == null || c.assignedStat != role.stat) continue;
      if (c.isKo ||
          creatures.isBreeding(c.id) ||
          creatures.isOnExpedition(c.id)) {
        continue;
      }
      power += c.statValue(role.stat) * role.mult * role.levelScale(b.level);
    }
    return power;
  }

  /// Total concurrent MATINGS the (complete, connected) building(s) of
  /// [buildingTypeId] allow, summed across every copy at its own level
  /// (BuildingDef.concurrentJobsAt — the `breeding` effect). 0 when none is
  /// built, which is exactly what gates the feature off.
  int breedingCapacity(String buildingTypeId) =>
      _jobCapacity(buildingTypeId, 'breeding');

  /// The same for concurrent INCUBATIONS (the `hatching` effect, user
  /// 2026-07-26), falling back to `breeding` for a Hatchery def saved before
  /// the two had separate effects — see [hatchingPower].
  int hatchingCapacity(String buildingTypeId) {
    final def = kBuildingDefs[buildingTypeId];
    if (def == null) return 0;
    final era = dungeonMaxStage;
    final type = def.hasEffect('hatching', era) ? 'hatching' : 'breeding';
    return _jobCapacity(buildingTypeId, type);
  }

  int _jobCapacity(String buildingTypeId, String effectType) {
    final def = kBuildingDefs[buildingTypeId];
    if (def == null) return 0;
    final era = dungeonMaxStage;
    final connected = connectedBuildingIds;
    var cap = 0;
    for (final b in buildings) {
      if (b.buildingTypeId != buildingTypeId) continue;
      if (!b.isComplete || !connected.contains(b.id)) continue;
      cap += def.concurrentJobsAt(b.level, eraOrder: era, type: effectType);
    }
    return cap;
  }

  /// The post [c] is actually WORKING in [b] right now, or null when it is not
  /// working (K.O., breeding, away on an expedition), holds no post this
  /// building offers, or sits in a legendary-boost slot — that one multiplies
  /// the building's own production instead of producing anything itself.
  ///
  /// THE presence rule, in ONE place: [workshopPower] asks it settlement-wide,
  /// [storageRoomPosted] asks it for a single store (user 2026-07-30), so a
  /// store's staff can never count under conditions a lumber camp's would not.
  static WorkshopRole? _postedRole(
    CreatureInstance c,
    BuildingDef def,
    CreaturesController creatures,
  ) {
    final stat = c.assignedStat;
    if (stat == null) return null;
    // The post is still theirs, but they are not IN it — away on a trip, knocked
    // out, mating or under treatment — so it yields nothing until they walk back
    // in. One predicate for all of it (user 2026-07-30): this used to list its own
    // three conditions and disagreed with the XP rule and with the dialog.
    if (!creatures.isWorkingNow(c)) return null;
    // Which post this monster holds. Normally the one whose stat it was
    // assigned to — but a stat can be RETIRED under a saved assignment, and
    // then `assigned_stat` reads back as something no role offers and the
    // worker silently stops producing while still looking posted.
    //
    // A building with exactly ONE post has no ambiguity to resolve, so it
    // heals itself instead: that is the post, whatever the stale row says.
    // This is what carried the warehouse/scout-post/smokehouse staff across
    // the deletion of `logistics` (user 2026-07-26); it is deliberately NOT
    // applied to multi-post buildings, where guessing would be wrong.
    final roles = def.workshops;
    final matched = roles.any((r) => r.stat == stat);
    for (final role in roles) {
      if (matched ? role.stat != stat : roles.length != 1) continue;
      return role;
    }
    return null;
  }

  /// Extra room every LOGISTICIAN posted in [b] makes for [resource] (user
  /// 2026-07-30). 0 for a building with no store post, nobody in it, or a
  /// resource this store does not hold.
  ///
  /// PER RESOURCE, not one figure for the building (user 2026-07-30: "Ich muss
  /// den output pro worker für jede Ressource einzeln einstellen können") — the
  /// post carries a dial per resource and falls back to its flat one, see
  /// [WorkshopRole.storageMultFor].
  ///
  /// And per BUILDING, not settlement-wide: room made in the Gold Vault is room
  /// for coin, and the Storehouse's staff must not widen it. That is why this
  /// reads one building's staff instead of [workshopPower]'s summed map — see
  /// [storageCapacity], which only asks for resources this building authors a
  /// `storage` effect for.
  double storageRoomPosted(PlacedBuilding b, String resource) {
    final def = placedDefOf(b);
    if (def == null || def.workshops.isEmpty) return 0;
    // A store's post amplifies what that store HOLDS. Without this the fallback
    // dial would happily make room for a good the building has no shelf for —
    // and every caller would have to remember to ask first.
    if (def.effectEntry('storage', resource, dungeonMaxStage) == null) {
      return 0;
    }
    final creatures = CreaturesController();
    var room = 0.0;
    for (final c in creatures.creatures) {
      if (c.assignedBuildingId != b.id) continue;
      final role = _postedRole(c, def, creatures);
      if (role == null || role.resource != WorkshopRole.kStorageRoom) continue;
      room += role.storageRoomFor(
        resource,
        c.statValue(role.stat).toDouble(),
        b.level,
      );
    }
    return room;
  }

  Map<String, double> workshopPower() {
    final connected = connectedBuildingIds;
    // Functional workshop buildings, by id → the placed building (carries the
    // LEVEL that scales its output) and its def.
    final workshops = <String, ({PlacedBuilding b, BuildingDef def})>{};
    for (final b in buildings) {
      // PAUSED = not running (user 2026-08-01). Skipping it here is what makes
      // the pause real everywhere at once: hourlyRates, the tick, the refinery
      // burn and the breakdown all read this one map.
      if (!b.isComplete || b.isPaused || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def != null && def.workshops.isNotEmpty) {
        workshops[b.id] = (b: b, def: def);
      }
    }
    final creatures = CreaturesController();
    final power = <String, double>{};
    for (final c in creatures.creatures) {
      final bId = c.assignedBuildingId;
      if (bId == null) continue;
      final entry = workshops[bId];
      if (entry == null) continue; // building missing / not functional
      // Every post reads the same way (user 2026-07-26: the construction mult
      // "soll eine Wirkung haben, da ich dies beim Hauptgebäude einfügen will").
      // Construction used to ignore BOTH the role mult and the building level —
      // a special case that made two authored fields inert on exactly the role
      // someone would tune first. It is no longer special in ANY way ("jeder
      // Construction Punkt zählt als 1 Construction Point"): the map carries raw
      // build points and buildTimeCut turns the total into a % off the time.
      //
      // A higher-level building multiplies output: by the role's own per-level
      // factor when set, else the global +50%/level curve.
      final role = _postedRole(c, entry.def, creatures);
      if (role == null) continue;
      // A store's room is LOCAL to its building AND per resource (user
      // 2026-07-30), so it never lands in the settlement-wide map —
      // storageCapacity reads it per building via storageRoomPosted. Summing it
      // here would make one number out of ceilings belonging to different stores
      // and different goods, and `contribution` cannot even express it: the
      // per-resource dials have no single output key.
      if (role.resource == WorkshopRole.kStorageRoom) continue;
      // One post can feed SEVERAL outputs (user 2026-07-29): the Scout Post's
      // combined post banks carry, goods and travel at once, each from the stat
      // it amplifies and with its own dial. Every other post returns a single
      // entry — see WorkshopRole.contribution.
      final contribution = role.contribution(
        (s) => c.statValue(s).toDouble(),
        entry.b.level,
      );
      for (final out in contribution.entries) {
        power[out.key] = (power[out.key] ?? 0) + out.value;
      }
    }
    // Worker-INDEPENDENT production: ONLY what a building's own `production`
    // effects declare (user 2026-07-25: "alle hardcoded boni bitte löschen …
    // es zählt nur das, was bei den Effekten steht").
    //
    // What stood here — a code-side base table (kBaseProductionByType), a
    // passive house-gold curve (HouseEconomy) and the hall's automatic build
    // points — was invisible in Dev Mode: the effects editor showed one set of
    // numbers and the economy ran on another. A building now produces exactly
    // what its effect list says, and nothing at all when that list is empty.
    final era = dungeonMaxStage;
    for (final b in buildings) {
      if (!b.isComplete || b.isPaused || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      // Dev-authored per-era `production` effects add on top (level scaling is
      // baked into the effect now — per-effect factor or the global curve).
      for (final res in def.effectKeys('production')) {
        final v = def.effectAt('production', res, era, level: b.level);
        if (v == 0) continue;
        // PASSIVE CONSTRUCTION lands here in exactly the unit it is authored
        // in — build points, one for one, the same as a stationed builder's
        // (user 2026-07-26: "das soll die passive Construction sein … wie wenn
        // ein Monster mit dieser Stufe dort arbeiten würde"). No conversion:
        // both sides of the sum have been plain points since the build time
        // became a percentage cut rather than a seconds budget.
        power[res] = (power[res] ?? 0) + v;
      }
    }
    // NOTE: the hall's automatic build points are gone with the rest of the
    // hardcoded bonuses (user 2026-07-25). Construction now comes from stationed
    // builders and from any authored `production` effect with the key
    // `construction` — the Castle included, if its effects say so.
    //
    // The tutorial's free build power is gone too (user 2026-07-26): it only
    // ever existed because zero builders meant zero progress. Points are a cut
    // off the authored time now, so an unstaffed site still finishes — see
    // buildTimeCut and the note where kIntroBaseBuildPower used to live.
    return power;
  }

  // Buildings currently reachable from the Main Hall via an unbroken road
  // network (edge-adjacent only) — only these actually produce/count.
  // ── Derived-from-buildings caches ─────────────────────────
  // Both of these are flood fills / set builds over `buildings`, and both were
  // plain getters — so they looked free and were called from inside build
  // loops. `connectedBuildingIds` ran once PER BUILDING TILE per frame, and
  // `buildableRegion` was rebuilt twice more per pointer-move while dragging.
  // With a road being one building row per grid cell (200+ rows is normal),
  // that was the drag path's frame budget.
  //
  // Invalidated by the identity of the `buildings` list rather than a manual
  // flag: every mutation replaces the list (`buildings = [...]`), so an
  // identity check can't go stale the way a flag someone forgets to set can.
  List<PlacedBuilding>? _derivedFor;
  Set<String>? _connectedCache;
  Set<int>? _regionCache;
  Set<int>? _roadCache;
  Set<int>? _walkCache;

  /// The signed-in user, or null — including when Supabase has not been
  /// initialised at all (2026-09-21). `supabase.auth` ASSERTS on an
  /// uninitialised instance rather than returning null, so a bare
  /// `currentUser?.id` throws instead of degrading, and the `?.` reads as if
  /// it were handling that. Every read here is on a path whose answer to "no
  /// user" is already "skip the write", so a throw only ever turns a skipped
  /// save into a crash. Matches CreaturesController's own `_userId`.
  String? get _userId {
    try {
      return supabase.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  void _refreshDerived() {
    if (identical(_derivedFor, buildings)) return;
    final previous = _derivedFor;
    _derivedFor = buildings;
    // A new list is not necessarily a new LAYOUT: construction progress, a
    // level-up or a pause all replace the list without moving, adding or
    // finishing anything. The caches below read only these five fields, so
    // when they all match the old answers still stand — and, because the sets
    // keep their identity, the map's terrain (which repaints when the region
    // changes) is not thrown away and rebuilt for nothing.
    if (previous != null && _sameLayout(previous, buildings)) return;
    _connectedCache = null;
    _regionCache = null;
    _roadCache = null;
    _walkCache = null;
  }

  static bool _sameLayout(List<PlacedBuilding> a, List<PlacedBuilding> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.id != y.id ||
          x.buildingTypeId != y.buildingTypeId ||
          x.gridX != y.gridX ||
          x.gridY != y.gridY ||
          // A quarter turn moves the ENTRANCE (and swaps the footprint), so a
          // building turned in place is a new layout: without this the
          // connection cache kept answering for the old facing and a turned
          // building never went red (user 2026-11-05).
          x.rotation != y.rotation ||
          x.isComplete != y.isComplete ||
          // A recall/place doesn't necessarily move gridX/gridY (a building
          // placed back at the same spot it started from wouldn't), but it
          // always changes which buildings occupy/connect the map.
          x.isStored != y.isStored) {
        return false;
      }
    }
    return true;
  }

  /// Every cell a road stands on, keyed by [roadCellKey].
  ///
  /// Cached for the same reason the region is: the map asks each road tile
  /// which of its neighbours are roads, and answering that by scanning the
  /// buildings list would be O(roads²) per frame — with one row per cell, a
  /// couple of hundred roads is normal.
  Set<int> get roadCells {
    _refreshDerived();
    return _roadCache ??= {
      for (final b in buildings)
        if (placedDefOf(b)?.isRoad ?? false)
          roadCellKey(b.gridX, b.gridY),
    };
  }

  /// Every cell a monster on the roads may walk: the roads, plus the lanes
  /// INSIDE a building that has them — the Castle's, from each gate to the
  /// square (user 2026-11-03: "die Monster können durch die Tore in die Burg
  /// laufen"). A road tile in front of a gate counts its lane as a
  /// neighbour too, so the road runs on into the gate instead of ending at
  /// the moat.
  Set<int> get walkCells {
    _refreshDerived();
    return _walkCache ??= {
      ...roadCells,
      for (final b in buildings)
        if (b.isComplete && !b.isStored)
          if (placedDefOf(b) case final d?)
            if (walkwaysFor(d.artId, d.gridW, d.gridH) case final cells?)
              for (final (cx, cy) in cells) roadCellKey(b.gridX + cx, b.gridY + cy),
    };
  }

  Set<String> get connectedBuildingIds {
    // Tutorial: every building counts as connected while it runs, road or
    // not — otherwise the Healing Hut the script just had the player place
    // would refuse to heal before the buildRoad step even gets to it. That
    // step (user script 2026-08-24) still has the player lay a real road,
    // so the mechanic is taught, but enforcement only starts once the
    // tutorial ends (the completion message says so).
    _refreshDerived();
    // Through the same cache as the real answer (2026-09-21), not a fresh
    // set on every read: the map asks this ONCE PER BUILDING while it lays
    // out its tiles, so building a new set of every id per call made the
    // tutorial's map quadratic in the number of buildings — for an answer
    // that cannot change until the layout does.
    return _connectedCache ??= introStep.isActive
        ? {for (final b in buildings) b.id}
        : GameEngine.connectedBuildingIds(buildings);
  }

  // Cells the player can currently build on — the starting zone plus every
  // completed Building Plot's footprint.
  Set<int> get buildableRegion {
    _refreshDerived();
    return _regionCache ??= GameEngine.buildableRegionCells(buildings);
  }

  // Combines occupancy + territory rules for one building type at one spot —
  // used by the map's ghost preview as well as placeBuilding/moveBuilding.
  /// Build plots snap to a clean 5×5 grid (user decision 2026-07-17): their
  /// top-left is forced to a multiple of 5, so they tile the map evenly
  /// instead of landing at arbitrary offsets. Non-plots pass through
  /// unchanged. The map uses this for the ghost preview; placeBuilding and
  /// isPlacementValid apply it too, so the snap can't be bypassed.
  (int, int) snapPlacement(String typeId, int x, int y) {
    final def = kBuildingDefs[typeId];
    if (def == null || !def.isBuildPlot) return (x, y);
    int snap(int c, int span, int maxCells) =>
        ((c / 5).round() * 5).clamp(0, maxCells - span);
    return (snap(x, def.gridW, kGridCols), snap(y, def.gridH, kGridRows));
  }

  bool isPlacementValid(
    String typeId,
    int x,
    int y, {
    String? excludeId,
    int rotation = 0,
  }) {
    // Turned: its footprint's sides swap on an odd turn (user 2026-11-03).
    final def = defRotated(typeId, rotation);
    if (def == null) return false;
    (x, y) = snapPlacement(typeId, x, y);
    if (!_isAreaFreeImpl(x, y, def.gridW, def.gridH, excludeId: excludeId)) {
      return false;
    }
    // Cached region: this runs on every pointer move behind the ghost.
    final region = buildableRegion;
    if (def.isBuildPlot) {
      // Must extend the territory: adjacent to it, but NOT entirely on ground
      // you can already build on (user 2026-07-17).
      return GameEngine.touchesBuildableRegion(
            x,
            y,
            def.gridW,
            def.gridH,
            buildings,
            region: region,
          ) &&
          !GameEngine.isAreaBuildable(
            x,
            y,
            def.gridW,
            def.gridH,
            buildings,
            region: region,
          );
    }
    return GameEngine.isAreaBuildable(
      x,
      y,
      def.gridW,
      def.gridH,
      buildings,
      region: region,
    );
  }

  /// WHY a footprint cannot go here — null when [isPlacementValid] says it can.
  /// The rules themselves stay in [isPlacementValid]; this only names the first
  /// one that fails, for the ghost's name tag.
  PlacementProblem? placementProblem(
    String typeId,
    int x,
    int y, {
    String? excludeId,
    int rotation = 0,
  }) {
    final def = defRotated(typeId, rotation);
    if (def == null) return PlacementProblem.unknown;
    (x, y) = snapPlacement(typeId, x, y);
    if (isPlacementValid(typeId, x, y, excludeId: excludeId, rotation: rotation)) {
      return null;
    }
    if (x < 0 ||
        y < 0 ||
        x + def.gridW > kGridCols ||
        y + def.gridH > kGridRows) {
      return PlacementProblem.offMap;
    }
    for (final b in buildings) {
      if (b.id == excludeId) continue;
      final other = placedDefOf(b);
      // Building Plots mark territory, not structures — see [_isAreaFreeImpl].
      if (other == null || other.isBuildPlot) continue;
      if (x < b.gridX + other.gridW &&
          x + def.gridW > b.gridX &&
          y < b.gridY + other.gridH &&
          y + def.gridH > b.gridY) {
        return PlacementProblem.overlap;
      }
    }
    if (def.isBuildPlot) return PlacementProblem.plotMustExtend;
    return PlacementProblem.outsideLand;
  }

  // ── Build slot helpers ────────────────────────────────────
  int get maxBuildSlots {
    return kBaseBuildSlots +
        GameEngine.buildingsBuildSlotsBonusTotal(
          buildings,
          eraOrder: dungeonMaxStage,
        );
  }

  int get maxQueueSlots {
    return kBaseQueueSlots +
        GameEngine.buildingsQueueSlotsBonusTotal(
          buildings,
          eraOrder: dungeonMaxStage,
        );
  }

  // Settlement-wide construction-speed % on top of the creature-driven
  // construction power (era + build-speed buildings) — the same multiplier
  // tick() applies. 1.0 = no bonus.
  double get buildSpeedMultiplier {
    final eb = _noEraBonus;
    final base =
        1.0 +
        eb.buildSpeed +
        GameEngine.buildingsBuildSpeedBonusTotal(buildings);
    // Jumpstart: a time scale of 0.2 means 5x the build speed. Applied here
    // rather than to constructionSeconds so it rides on the multiplier tick()
    // already uses — and so it simply stops applying when the intro ends,
    // with no half-built building stuck on a stale requirement. This is the
    // settlement-wide RATE, used for every site's ETA/skip-cost math — the
    // Healing Hut's own freeze during its build step (see
    // [_frozenBuildingIds]) works by excluding it from progress entirely,
    // not by changing the rate everyone else's estimate is still priced on.
    return base / jumpstartTimeScale(jumpstartActive);
  }

  /// Total CONSTRUCTION POINTS the settlement has on hand — stationed builders
  /// plus every authored passive `construction` effect, all counted 1:1.
  double get buildPoints => workshopPower()[WorkshopRole.kConstruction] ?? 0;

  /// Fraction the settlement takes off any building's authored construction
  /// time right now, e.g. 0.6 for "−60 %". This is what the points BUY.
  double get buildTimeCutNow => buildTimeCut(buildPoints);

  // Build-seconds of construction progress credited per real hour, including
  // the buildSpeedMultiplier % — exposed so UI countdowns match tick() exactly.
  //
  // 3600 is the floor, not a target: with nobody building a site advances one
  // build-second per real second, i.e. it takes exactly its authored time. The
  // points scale that up (user 2026-07-26).
  double get buildRatePerHour =>
      3600 * buildSpeedFromPoints(buildPoints) * buildSpeedMultiplier;

  /// Crafting-seconds the Workshop credits per hour — the sum of its crafting
  /// workers' output, energy-gated. Zero crafters = nothing is ever made.
  ///
  /// This is what the crafting stat finally does. It was `research` and drove
  /// a countdown that no longer exists.
  double get craftRatePerHour => workshopPower()[WorkshopRole.kCrafting] ?? 0;

  /// The recipe on the FIRST bench — what the map's Workshop badge shows.
  ItemDef? get activeCraft {
    final job = craftJobs.firstOrNull;
    return job == null ? null : kItemDefs[job.itemId];
  }

  /// The bag: itemId → count. Never holds a zero.
  Map<String, int> get items => settlement?.items ?? const {};

  /// Real seconds until the NEXT item lands — the first bench's remaining
  /// work. Null when nothing is being made or nobody is making it.
  double? get craftEtaSeconds {
    final job = activeCraftJobs.firstOrNull;
    final def = job == null ? null : kItemDefs[job.itemId];
    if (def == null) return null;
    final total = craftSecondsAt(
      def,
      craftRatePerHour,
      timeScale: jumpstartTimeScale(jumpstartActive),
    );
    if (total == null) return null;
    final done = craftProgress(
      def,
      job!.secondsBuilt,
      timeScale: jumpstartTimeScale(jumpstartActive),
    );
    return total * (1 - done);
  }

  /// How far along one job is, 0..1 — what a bench's bar reads.
  double craftJobProgress(CraftJob job) {
    final def = kItemDefs[job.itemId];
    if (def == null) return 0;
    return craftProgress(
      def,
      job.secondsBuilt,
      timeScale: jumpstartTimeScale(jumpstartActive),
    );
  }

  int get activeConstructionCount =>
      buildings.where((b) => !b.isComplete && !b.isQueued).length;

  int get queuedConstructionCount =>
      buildings.where((b) => !b.isComplete && b.isQueued).length;

  /// Sum of the per-era `resource` bonus effects (+% production) over functional
  /// buildings, for [target] ∈ {wood, stone, food, all}. Flat like the tech/era
  /// bonuses it is added to. ('all' covers wood+stone+goods; gold has no % hook
  /// in the tick, so a gold `resource` effect is currently inert.)
  double _buildingResourceBonus(String target) {
    final connected = connectedBuildingIds;
    final era = dungeonMaxStage;
    double total = 0;
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      // Flat historically; an authored per-effect factor scales it per level.
      final e = def.effectEntry('resource', target, era);
      if (e != null) total += e.value * e.levelScaleExplicit(b.level);
    }
    return total;
  }

  // ── Game tick ─────────────────────────────────────────────
  // Applies elapsed production, energy drain and passive accrual since the last
  // tick (see GameEngine.tick and _persist).
  void _applyTick(DateTime now) {
    if (energy == null || resources == null || settlement == null) return;
    final eb = _noEraBonus;
    final power = workshopPower();
    // Snapshot to spot what FINISHED during this tick. Diffed here rather than
    // reported by GameEngine so the engine stays a pure function with no idea
    // an event log exists.
    final wasComplete = {
      for (final b in buildings)
        if (b.isComplete) b.id,
    };
    // The stock BEFORE this tick — what the production cap is measured against,
    // so an overflow is judged by where the store stood, not by where the engine
    // would have pushed it.
    final before = resources!;
    final result = GameEngine.tick(
      energy!,
      resources!,
      buildings,
      now,
      workshopPower: power,
      creatureCount: CreaturesController().creatures.length,
      techWood: eb.wood + _buildingResourceBonus('wood'),
      techStone: eb.stone + _buildingResourceBonus('stone'),
      // era food bonus applies to goods production
      techGoods: eb.food + _buildingResourceBonus('food'),
      techAll: eb.all + _buildingResourceBonus('all'),
      techBuildSpeed: eb.buildSpeed,
      buildSpeedScale: 1.0 / jumpstartTimeScale(jumpstartActive),
      frozenBuildingIds: _frozenBuildingIds,
    );
    energy = result.energy;
    // Production stops AT the ceiling, but what is already above it stays there
    // (user 2026-07-30, with the resource packs). Trimming the engine's result
    // used to be the same thing — and stopped being it the moment a redeemed
    // pack could legitimately overfill a store: the next tick, five seconds
    // later, would have deleted the reward.
    resources = before.withProductionCapped(result.resources, storageCaps);
    buildings = result.buildings;

    // The tick only CHANGES a building row while one is actually being built
    // (its constructionSecondsBuilt ticks up, then isComplete flips). With
    // nothing on site the rows come back identical, so there is nothing to
    // write — which is the normal case, and the reason this flag exists.
    if (buildings.any((b) => !b.isComplete && !b.isQueued)) {
      _buildingsDirty = true;
    }

    for (final b in buildings) {
      if (b.isComplete && !wasComplete.contains(b.id)) {
        _buildingsDirty = true;
        reportDailyProgress(DailyTaskKind.finishBuildings);
        GameEventLog().add(
          GameEventKind.building,
          '${placedDefOf(b)?.name ?? b.buildingTypeId} '
          'is finished',
          // Timestamp to the real finish, not to screen-open — a load-time
          // catch-up folds offline hours into one tick.
          at: result.completedAt[b.id],
          ref: b.id,
        );
        // Tutorial build steps advance on COMPLETION, not on placement — the
        // guard inside advanceIntro ignores buildings that aren't the
        // current step's target.
        final introBuildStep = kIntroBuildSteps[b.buildingTypeId];
        if (introBuildStep != null) unawaited(advanceIntro(introBuildStep));
      }
    }

    // Passive XP for stationed creatures — same energy-gated hours as
    // production, so a settlement that ran dry trains nobody. Fire-and-forget:
    // _applyTick is sync (it runs on the 5s ticker and on the load path), and
    // a level-up is reported through the event log rather than a return value.
    unawaited(
      CreaturesController().accruePassiveXp(result.effectiveHours).then((
        levelUps,
      ) {
        for (final l in levelUps) {
          GameEventLog().add(
            GameEventKind.levelUp,
            l.message,
            ref: l.creatureId,
          );
        }
      }),
    );

    // Finished treatments. Resolved here rather than on a timer of their own:
    // this tick already runs on load (catching up offline time) and every few
    // seconds while playing, which is exactly when a heal needs noticing.
    // NOT energy-gated — a monster mends whether or not you walked today.
    unawaited(CreaturesController().resolveFinishedHeals());

    _accrueCrafting(result.realHours);
    _promoteQueuedBuildings();
  }

  /// Advances the Workshop and banks a finished item.
  ///
  /// Energy-gated through [effectiveHours] like every other producer, so a
  /// settlement that ran dry makes nothing.
  ///
  /// The cost is paid ON COMPLETION, not when the recipe is picked. Charging up
  /// front would mean a player who switches recipes — or whose crafters get
  /// sent on an expedition — silently loses what they paid. Here, work that
  /// can't be paid for simply waits: the bar sits full until the goods exist.
  void _accrueCrafting(double effectiveHours) {
    final s = settlement;
    final res = resources;
    if (s == null || res == null || effectiveHours <= 0) return;
    if (s.craftJobs.isEmpty) return;

    final scale = jumpstartTimeScale(jumpstartActive);
    final rate = craftRatePerHour;
    // EACH BENCH RUNS AT THE FULL RATE (user 2026-07-30), exactly as each
    // healing slot treats its own monster at the full rate. A second bench is
    // therefore a real doubling, not a way to split one crew's work in two —
    // which is what "wieviele items gleichzeitig produziert werden können"
    // asks for, and what makes the effect worth levelling. How steep that gets
    // is the author's to set: craftSlots is a per-level dial.
    final benches = craftCapacity;
    var jobs = [...s.craftJobs];
    var stock = res;
    final finished = <ItemDef>[];

    for (var i = 0; i < jobs.length && i < benches; i++) {
      final def = kItemDefs[jobs[i].itemId];
      // A recipe deleted in Dev Mode leaves a job nothing can finish; drop it
      // rather than jamming the bench behind it forever.
      if (def == null) {
        jobs[i] = jobs[i].withSeconds(-1);
        continue;
      }
      final built = jobs[i].secondsBuilt + rate * effectiveHours;
      if (!craftComplete(def, built, timeScale: scale)) {
        jobs[i] = jobs[i].withSeconds(built);
        continue;
      }
      // The cost is paid ON COMPLETION, not when the recipe is queued.
      // Charging up front would mean a player who cancels — or whose crafters
      // get sent on an expedition — silently loses what they paid.
      final cost = craftCost(def, dungeonMaxStage, stock.asMap);
      final canPay = cost.entries.every(
        (e) => (stock.asMap[e.key] ?? 0) >= e.value,
      );
      if (!canPay) {
        // Hold at exactly full rather than letting seconds pile up: banking
        // overflow would hand the player a burst of free items the moment
        // goods arrived, from work the Workshop never actually did.
        jobs[i] = jobs[i].withSeconds(def.craftSeconds * scale);
        continue;
      }
      stock = stock.deduct(cost);
      jobs[i] = jobs[i].withSeconds(-1); // done — swept below
      finished.add(def);
    }

    if (finished.isEmpty && !jobs.any((j) => j.secondsBuilt < 0)) {
      settlement = s.copyWith(craftJobs: jobs);
      return;
    }
    // Sweeping the finished jobs is what PULLS THE QUEUE FORWARD: the next
    // waiting item simply becomes one of the first `benches` entries.
    jobs = [
      for (final j in jobs)
        if (j.secondsBuilt >= 0) j,
    ];
    resources = stock;
    var items = s.items;
    for (final def in finished) {
      items = addItem(items, def.id);
      reportDailyProgress(DailyTaskKind.craftItems);
      NewItems().add(def.id, 1);
      GameEventLog().add(
        GameEventKind.craft,
        '${def.emoji} ${def.name} crafted',
      );
    }
    settlement = s.copyWith(craftJobs: jobs, items: items);
  }

  /// Puts one more of [itemId] in — onto a free bench, or into the line.
  ///
  /// The Workshop used to hold ONE recipe and repeat it forever, so "make three
  /// torches and then a rope" was not expressible. Now every item is its own
  /// job: benches decide how many progress at once, the queue how many may
  /// wait, and both are authored per level.
  Future<String?> queueCraft(String itemId) async {
    final s = settlement;
    if (s == null) return 'Not loaded';
    if (kItemDefs[itemId] == null) return 'Unknown recipe';
    if (!canQueueCraft) {
      final queueCap = craftQueueCapacity ?? 0;
      return queueCap == 0
          ? 'Every bench is busy — level the Workshop for room to queue.'
          : 'The Workshop holds $craftCapacity on the bench and $queueCap in '
                'line, and both are full.';
    }
    settlement = s.copyWith(craftJobs: [...s.craftJobs, CraftJob(itemId)]);
    notifyListeners();
    await _persist();
    return null;
  }

  /// Drops the job at [index]. Banked seconds go with it — they belonged to
  /// that item, and carrying them to the next would let a player bank work on
  /// a cheap recipe and cash it in on an expensive one.
  Future<String?> cancelCraft(int index) async {
    final s = settlement;
    if (s == null) return 'Not loaded';
    if (index < 0 || index >= s.craftJobs.length) return null;
    settlement = s.copyWith(craftJobs: [...s.craftJobs]..removeAt(index));
    notifyListeners();
    await _persist();
    return null;
  }

  /// Opens ONE resource package from the bag (user 2026-07-30).
  ///
  /// The one grant in the game that is NOT capped: the whole point of a package
  /// is that a campaign reward keeps its value until you decide to take it, so a
  /// small store may not quietly eat the difference. What it costs is stated on
  /// the item and enforced by the tick — while a resource sits above its
  /// ceiling, none of it is produced (ResourceModel.withProductionCapped).
  ///
  /// Returns null on success, else a user-facing reason.
  Future<String?> redeemPack(String itemId) async {
    final s = settlement;
    final res = resources;
    if (s == null || res == null) return 'Not loaded';
    final def = kItemDefs[itemId];
    if (def == null) return 'Unknown item';
    if (def.kind != ItemKind.resourcePack) {
      return '${def.name} is not a package.';
    }
    final resourceId = def.resourceId;
    if (resourceId == null || def.magnitude <= 0) {
      return '${def.name} is empty — check its Dev-Mode definition.';
    }
    final next = removeItem(s.items, itemId);
    if (next == null) return 'You have none left';
    settlement = s.copyWith(items: next);
    // grant WITHOUT capped(): see above.
    resources = res.grant({resourceId: def.magnitude});
    notifyListeners();
    await _persist();
    return null;
  }

  /// Resource ids currently ABOVE their ceiling — production of these is paused
  /// until they drain back under. Drives the "over the ceiling" note wherever a
  /// rate is shown.
  List<String> get overflowingResources =>
      resources?.overCapacity(storageCaps) ?? const [];

  /// Spends one item. Returns null on success, else why not.
  ///
  /// Heals are applied by the caller (CreaturesController owns creature HP);
  /// this only moves the item out of the bag.
  Future<String?> consumeItem(String itemId) async {
    final s = settlement;
    if (s == null) return 'Not loaded';
    final next = removeItem(s.items, itemId);
    if (next == null) return 'You have none left';
    settlement = s.copyWith(items: next);
    notifyListeners();
    await _persist();
    return null;
  }

  void _promoteQueuedBuildings() {
    final maxSlots = maxBuildSlots;
    int active = buildings.where((b) => !b.isComplete && !b.isQueued).length;
    if (active >= maxSlots) return;

    final toPromote =
        buildings.where((b) => !b.isComplete && b.isQueued).toList()
          ..sort((a, b) => a.placedAt.compareTo(b.placedAt));

    final promoteIds = <String>{};
    for (final b in toPromote) {
      if (active >= maxSlots) break;
      promoteIds.add(b.id);
      active++;
    }

    if (promoteIds.isEmpty) return;
    _buildingsDirty = true;
    buildings = [
      for (final b in buildings)
        if (promoteIds.contains(b.id)) b.copyWith(isQueued: false) else b,
    ];
  }

  // ── Persist to Supabase ───────────────────────────────────
  /// True while a `_persist()` is in flight.
  ///
  /// The ticker fires `_persist()` unawaited every 5s. When a cycle takes
  /// longer than that (it did — see saveBuildings), cycles overlapped and
  /// stacked without bound, so the radio never got to idle. Skipping while one
  /// is running loses nothing: the next tick writes the same state.
  bool _persisting = false;

  /// Buildings only change when something is placed, moved, demolished or
  /// finishes construction — NOT on a normal tick. Set by the paths that do
  /// change them; cleared once written.
  bool _buildingsDirty = false;

  /// Profile-column progress (battles cleared, dungeon stage, expansions) that
  /// changed and hasn't been written yet. Folded into [_persist] so a dropped
  /// write RETRIES on the next tick instead of being lost — these used to save
  /// once, swallow all errors, and never retry (a boss clear could vanish).
  bool _progressDirty = false;

  /// True when the last persist attempt FAILED for a real reason (network/RLS,
  /// not a pre-migration column). The UI shows an "unsaved" indicator; cleared
  /// automatically the next time a persist succeeds. Local state is kept and
  /// retried, so nothing is lost while offline.
  bool _saveFailed = false;
  bool get saveFailed => _saveFailed;

  /// Flags the last write as failed so the UI shows the "unsaved" indicator. The
  /// periodic [_persist] always re-saves resources and clears this on success,
  /// so direct-save callers that fail only need to raise the flag.
  void _flagSaveFailed() {
    if (!_saveFailed) {
      _saveFailed = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    if (resources == null || energy == null || settlement == null) return;
    if (_persisting) return;
    _persisting = true;
    final userId = _userId;
    try {
      await Future.wait([
        _svc.saveResources(resources!),
        _svc.saveEnergy(energy!),
        // Dirty-tracked: re-uploading 200 unchanged road rows every 5 seconds
        // forever was the single most expensive thing this app did.
        if (_buildingsDirty) _svc.saveBuildings(buildings),
        _svc.saveSettlement(settlement!),
        // Progress columns retry through here — dirty stays set until a write
        // actually lands, so a transient failure after a boss kill isn't lost.
        if (_progressDirty && userId != null) ...[
          _svc.saveBattlesCleared(userId, battlesCleared),
          _svc.saveDungeonMaxStage(userId, dungeonMaxStage),
          _svc.saveExpansionsUnlocked(userId, expansionsUnlocked),
          _svc.saveSurvivalBestFloor(userId, survivalBestFloor),
          _svc.saveBattleStars(userId, battleStars),
        ],
      ]);
      _buildingsDirty = false;
      if (userId != null) _progressDirty = false;
      if (_saveFailed) {
        _saveFailed = false;
        notifyListeners();
      }
    } catch (e, st) {
      // Log only — don't overwrite the main error field, which would replace the
      // UI. The dirty flags deliberately stay set on failure, so a dropped write
      // retries next cycle instead of being lost; the indicator tells the player.
      debugPrint('[SettlementController] _persist FAILED: $e\n$st');
      if (!_saveFailed) {
        _saveFailed = true;
        notifyListeners();
      }
    } finally {
      _persisting = false;
    }
  }

  // ── Actions ───────────────────────────────────────────────
  /// Dev cheat: the pool straight to its ceiling, same "auffüllen" pattern
  /// as the gold/wood/stone action beside it.
  Future<void> devFillEnergy() async {
    if (energy == null) return;
    _applyTick(DateTime.now().toUtc());
    energy = energy!.copyWith(energyPct: kEnergyMaxPercent);
    notifyListeners();
    await _persist();
  }

  Future<void> addSteps(int steps) async {
    if (energy == null) return;
    _applyTick(DateTime.now().toUtc());
    energy = GameEngine.addSteps(energy!, steps, DateTime.now());
    // Daily goal: the steps walked count, whether or not the pool had room.
    if (steps > 0) reportDailyProgress(DailyTaskKind.walkSteps, steps);
    // NB: step logging removed — the `step_logs` table was append-only and
    // never read anywhere, so it only ever grew and ate Supabase storage.
    // Hunts run on real steps too (user 2026-10-02) — crediting them HERE,
    // the one place both StepTrackerService and the Dev Mode "Add steps"
    // shortcut funnel through, means every caller of addSteps advances a
    // hunt the same way, instead of only the hardware pedometer path doing
    // it (see ExpeditionController.creditSteps's own doc).
    if (steps > 0) unawaited(ExpeditionController().creditSteps(steps));
    notifyListeners();
    // Persist BOTH energy and the resources _applyTick just credited — saving
    // energy alone advanced the clock while dropping that tick's production.
    await _persist();
  }

  // How many creatures currently fill a given work role of a building — used
  // by the assignment UI to show "N/slots" and to gate new assignments.
  int workshopOccupancy(String buildingId, CreatureStat stat) {
    return CreaturesController().creatures
        .where(
          (c) => c.assignedBuildingId == buildingId && c.assignedStat == stat,
        )
        .length;
  }

  // Stations [creatureId] in [buildingId]'s [stat] work role (moving it from
  // any previous post), or — with a null buildingId/stat — pulls it off work.
  // Settles production up to now with the OLD assignment first, then validates
  // the target building is a functional workshop offering that role with a
  // free slot. Returns null on success or a user-facing error.
  Future<String?> assignCreatureToWorkshop(
    String creatureId,
    String? buildingId,
    CreatureStat? stat,
  ) async {
    final creatures = CreaturesController();
    final creature = creatures.byId(creatureId);
    if (creature == null) return 'Creature not found';

    if (buildingId == null || stat == null) {
      _applyTick(DateTime.now().toUtc());
      await creatures.setAssignment(creature, null, null);
      notifyListeners();
      return null;
    }

    PlacedBuilding? placed;
    for (final b in buildings) {
      if (b.id == buildingId) {
        placed = b;
        break;
      }
    }
    if (placed == null) return 'Building not found';
    final def = placedDefOf(placed);
    if (def == null) return 'Unknown building type';
    if (!placed.isComplete || !connectedBuildingIds.contains(buildingId)) {
      return 'Building must be complete and connected to a road';
    }
    WorkshopRole? role;
    for (final r in def.workshops) {
      if (r.stat == stat) {
        role = r;
        break;
      }
    }
    if (role == null) return 'This building has no such work role';
    final occupied = creatures.creatures
        .where(
          (c) =>
              c.id != creatureId &&
              c.assignedBuildingId == buildingId &&
              c.assignedStat == stat,
        )
        .length;
    // Slots grow with the building's level (user 2026-07-22) — the guard has
    // to agree with what the dialog shows.
    PlacedBuilding? placedFor;
    for (final b in buildings) {
      if (b.id == buildingId) {
        placedFor = b;
        break;
      }
    }
    final cap = effectiveSlots(role, placedFor?.level ?? 1);
    if (occupied >= cap) return 'All slots for this role are full';

    _applyTick(DateTime.now().toUtc());
    await creatures.setAssignment(creature, buildingId, stat);
    // Tutorial milestone: specifically the Healing Hut, not any workshop —
    // it is the only one standing this early anyway (see intro_flow.dart).
    if (def.id == kHealingHutBuildingId) {
      await advanceIntro(IntroStep.assignHealer);
    }
    notifyListeners();
    return null;
  }

  // Research as a player activity is GONE (user 2026-07-24), and the
  // feature-unlock flags that outlived it are gone too (user 2026-07-26).
  // Nothing is "unlocked" by an invisible id any more: evolution needs a level,
  // breeding a Breeding Hut, hunts and expedition slots a Scout Post, and party
  // size is a position on the path. The `research_unlocks` table is dead.

  /// A free, legal cell for [typeId] — where the game puts a building you just
  /// bought (user 2026-07-30: "wenn ich beim app ein gebäude baue, soll dies
  /// einfach auf die map kommen, damit ich es dann verschieben kann").
  ///
  /// Buying used to hand you a ghost and a job: find a spot, aim it, tap. But
  /// the spot is not a decision you can make well before the thing exists — you
  /// want to see it standing there and then push it around, which the map has
  /// always been able to do. So the purchase lands it and the DRAG is the
  /// placement.
  ///
  /// Nearest-to-the-hall first, so it appears where you are already looking
  /// rather than in whatever corner scans first — and, being near the middle, it
  /// is usually already road-connected.
  ///
  /// Returns null when nothing fits, which is a real answer: the settlement is
  /// full and needs a Building Plot.
  (int, int)? firstFreeSpotFor(String typeId) {
    final def = kBuildingDefs[typeId];
    if (def == null) return null;
    // A BUILD PLOT is never auto-placed. It must go on NEW ground, it can never
    // be moved afterwards, and WHICH ground it claims is the only thing it is
    // for — so the player picks. Refused here rather than only in the screen, so
    // a second caller cannot quietly place one in the corner and freeze it there.
    if (def.isBuildPlot) return null;
    PlacedBuilding? hall;
    for (final b in buildings) {
      if (placedDefOf(b)?.isMainBuilding ?? false) hall = b;
    }
    final cx = hall == null
        ? kGridCols / 2
        : hall.gridX + (placedDefOf(hall)?.gridW ?? 1) / 2;
    final cy = hall == null
        ? kGridRows / 2
        : hall.gridY + (placedDefOf(hall)?.gridH ?? 1) / 2;
    final region = buildableRegion;
    final cells = <(int, int, double)>[];
    for (final cell in region) {
      final x = cell % kGridCols;
      final y = cell ~/ kGridCols;
      final dx = x + def.gridW / 2 - cx;
      final dy = y + def.gridH / 2 - cy;
      cells.add((x, y, dx * dx + dy * dy));
    }
    cells.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (x, y, _) in cells) {
      if (isPlacementValid(typeId, x, y)) return (x, y);
    }
    return null;
  }

  Future<String?> placeBuilding(
    String typeId,
    int x,
    int y, {
    int rotation = 0,
  }) async {
    if (settlement == null || resources == null) return 'Not loaded';
    final def = defRotated(typeId, rotation);
    if (def == null) return 'Unknown building';
    // Authoritative 5×5 snap for plots — the map ghost snaps too, this makes
    // sure a non-snapped (x,y) can never slip in.
    (x, y) = snapPlacement(typeId, x, y);

    if (def.eraIds.isNotEmpty && !def.eraIds.contains('era_$dungeonMaxStage')) {
      return 'Not available in this region';
    }
    // Map-progress gate (user 2026-07-24): buildings unlock as battles are won
    // on the linear path, not by research. The menu already hides locked ones;
    // this guards the write path too.
    //
    // A Building Plot is exempt (governed by expansionsUnlocked/
    // buildPlotLimit instead — see the check below), and so is a road — like
    // availableBuildings' own `!b.isRoad` (see there), a road is never handed
    // out as a node reward, so this gate could never pass one through
    // otherwise. Every other building additionally needs a REAL node reward
    // now, not just an era it happens to belong to (user 2026-08-31:
    // "diejenigen, welche ich noch gar keinem Knoten zugeordnet habe, sollen
    // noch nicht baubar sein").
    if (!def.isBuildPlot && !def.isRoad && !buildingHasPathReward(typeId)) {
      return 'Not yet unlocked by the campaign';
    }
    final unlockBattle = buildingUnlockBattle(typeId);
    if (battlesCleared < unlockBattle) {
      return 'Unlocks after battle $unlockBattle on the map';
    }
    final existingCount = buildings
        .where((b) => b.buildingTypeId == typeId)
        .length;
    if (def.isUnique && existingCount >= 1) {
      return '${def.name} is already built';
    }
    if (def.maxCount > 0 && existingCount >= def.maxCount) {
      return '${def.name}: limit of ${def.maxCount} reached';
    }
    // Build Plots unlock ONE at a time, per cleared map point (user 2026-07-17).
    if (def.isBuildPlot && existingCount >= buildPlotLimit) {
      return buildPlotLimit == 0
          ? 'Building Plots unlock by clearing points on the map — none cleared yet'
          : 'All $buildPlotLimit Building Plots used — clear another map point for one more';
    }
    if (!def.canAfford(resources!.asMap)) {
      return 'Not enough resources';
    }
    if (!_isAreaFree(x, y, def.gridW, def.gridH)) {
      return 'Space is occupied';
    }
    if (def.isBuildPlot) {
      final region = GameEngine.buildableRegionCells(buildings);
      // A plot only makes sense on NEW ground: reject one placed entirely
      // inside land you can already build on (user 2026-07-17).
      if (GameEngine.isAreaBuildable(
        x,
        y,
        def.gridW,
        def.gridH,
        buildings,
        region: region,
      )) {
        return 'You can already build here — place the plot on new ground';
      }
      if (!GameEngine.touchesBuildableRegion(
        x,
        y,
        def.gridW,
        def.gridH,
        buildings,
        region: region,
      )) {
        return 'Must be adjacent to your existing territory';
      }
    } else if (!GameEngine.isAreaBuildable(
      x,
      y,
      def.gridW,
      def.gridH,
      buildings,
    )) {
      return 'Outside buildable area — expand your territory first';
    }

    // Slot enforcement — only for buildings that take time to build
    bool shouldQueue = false;
    if (def.constructionSeconds > 0) {
      final active = activeConstructionCount;
      final queued = queuedConstructionCount;
      if (active < maxBuildSlots) {
        shouldQueue = false;
      } else if (queued < maxQueueSlots) {
        shouldQueue = true;
      } else {
        return 'Build queue is full ($maxBuildSlots active + $maxQueueSlots queued)';
      }
    }

    _applyTick(DateTime.now().toUtc());
    resources = resources!.deduct(def.resourceCost);

    final placed = await _svc.placeBuilding(
      settlementId: settlement!.id,
      typeId: typeId,
      x: x,
      y: y,
      isQueued: shouldQueue,
      rotation: def.rotation,
    );
    buildings = [...buildings, placed];
    _buildingsDirty = true;
    // The id of what was just built — the map selects it so it can be dragged
    // straight away (user 2026-07-30). Kept here rather than returned because
    // this method's return value is the ERROR channel, and every caller reads
    // it that way.
    lastPlacedId = placed.id;

    // notifyListeners BEFORE the resources save, not after (2026-09-12) — a
    // road drawn tile-by-tile calls this once per tap (see settlement_map
    // .dart's _chainStep), and this second, sequential network write used to
    // sit between "the insert above resolved" and "the tile actually
    // appears", doubling the round trip every single tap. The 5s ticker
    // re-saves resources regardless, so nothing here needs the caller to
    // wait on it.
    notifyListeners();
    unawaited(
      _svc.saveResources(resources!).catchError((e) {
        debugPrint(
          '[SettlementController] placeBuilding resources save failed: $e',
        );
        _flagSaveFailed();
      }),
    );
    return null;
  }

  /// The building placed most recently, or null before the first one. See
  /// [placeBuilding]; the map uses it to select a fresh building for dragging.
  String? lastPlacedId;

  /// Buildings that carry a level worth upgrading — excludes roads, plots and
  /// the main hall (which has its own era-driven level).
  bool isUpgradable(BuildingDef def) =>
      !def.isRoad && !def.isBuildPlot && !def.isMainBuilding;

  /// Upgrades a building one level: charges the level-scaled cost and puts it
  /// back into construction (level-scaled time) — it stops producing until the
  /// upgrade finishes, then yields more (user design 2026-07-17). Returns null
  /// on success or a user-facing error.
  Future<String?> upgradeBuilding(String buildingId) async {
    if (settlement == null || resources == null) return 'Not loaded';
    final idx = buildings.indexWhere((b) => b.id == buildingId);
    if (idx < 0) return 'Building not found';
    final b = buildings[idx];
    final def = placedDefOf(b);
    if (def == null) return 'Unknown building type';
    if (!isUpgradable(def)) return 'This building cannot be upgraded';
    if (!b.isComplete) return 'Finish building it first';
    final maxLevel = maxBuildingLevelFor(def, dungeonMaxStage);
    if (b.level >= maxLevel) {
      return 'Already at the maximum level ($maxLevel) for this region';
    }

    final target = b.level + 1;
    if (!def.canAffordAt(target, resources!.asMap)) {
      return 'Not enough resources for level $target';
    }

    // A build slot is needed, same as a fresh construction.
    bool shouldQueue = false;
    final activeCount = activeConstructionCount;
    final queued = queuedConstructionCount;
    if (activeCount < maxBuildSlots) {
      shouldQueue = false;
    } else if (queued < maxQueueSlots) {
      shouldQueue = true;
    } else {
      return 'Build queue is full ($maxBuildSlots active + $maxQueueSlots queued)';
    }

    _applyTick(DateTime.now().toUtc());
    resources = resources!.deduct(def.resourceCostAt(target));

    // Level bumps NOW but the building goes back under construction — the tick
    // builds it, and only a complete building produces (workshopPower gates on
    // isComplete), so the higher yield lands when the upgrade finishes.
    final upgraded = b.copyWith(
      level: target,
      constructionSecondsRequired: def.constructionSecondsAt(target),
      constructionSecondsBuilt: 0,
      isComplete: false,
      isQueued: shouldQueue,
    );
    buildings = [...buildings]..[idx] = upgraded;
    _buildingsDirty = true;

    // LOCAL first, network in the BACKGROUND (2026-09-12, same reasoning as
    // [setPaused]) — this used to await two SEQUENTIAL network writes before
    // notifyListeners, so every upgrade tap sat there for two round trips
    // before the building even looked upgraded, AND [building_detail_dialog
    // .dart]'s own caller keeps the sheet open until this returns — so the
    // whole dialog hung there too. Nothing past this point can still fail
    // this call (every validation already returned above), so there is
    // nothing left for the caller to usefully wait on: the periodic 5s
    // ticker re-saves resources regardless, and saveBuildings retries next
    // cycle too since _buildingsDirty stays true on a failed write.
    notifyListeners();
    unawaited(_persistUpgrade(upgraded));
    return null;
  }

  Future<void> _persistUpgrade(PlacedBuilding upgraded) async {
    try {
      await Future.wait([
        _svc.saveBuildings([upgraded]),
        _svc.saveResources(resources!),
      ]);
    } catch (e) {
      debugPrint('[SettlementController] upgradeBuilding save failed: $e');
      _flagSaveFailed();
    }
  }

  Future<String?> deleteBuilding(String buildingId) async {
    final idx = buildings.indexWhere((b) => b.id == buildingId);
    if (idx < 0) return 'Building not found';

    // Build plots are permanent (user decision 2026-07-17): claiming
    // territory is a one-way move — you can't un-expand. The map hides the
    // delete button for plots too, this is the authoritative backstop.
    if (placedDefOf(buildings[idx])?.isBuildPlot ?? false) {
      return 'Building Plots are permanent and cannot be removed.';
    }
    // The Castle is the settlement (user 2026-07-22). The map already
    // hides its delete button, but that was the ONLY thing preventing it —
    // this is the authoritative backstop, same pattern as the plots above.
    if (placedDefOf(buildings[idx])?.isMainBuilding ?? false) {
      return 'The Castle is the heart of the settlement — it cannot '
          'be demolished.';
    }

    final remaining = [...buildings]..removeAt(idx);

    // Block demolition if it would leave the settlement unable to shelter the
    // creatures it already owns.
    //
    // ROADS ARE EXEMPT, and that exemption is load-bearing: housingCapacity
    // counts only road-CONNECTED buildings, so removing almost any road
    // disconnects a hut somewhere and collapses capacity — which made roads
    // undeletable in practice (reported from a real run). The guard exists to
    // stop you DESTROYING housing you need; a road destroys nothing, it only
    // disconnects, and you're mid-edit and about to reconnect it.
    final isRoad =
        placedDefOf(buildings[idx])?.isRoad ?? false;
    if (!isRoad) {
      final remainingCapacity = resources == null
          ? 0
          : GameEngine.housingCapacity(remaining, eraOrder: dungeonMaxStage);
      if (remainingCapacity < housingUsed) {
        return 'Not enough housing left for your creatures — release or '
            'rehouse some first';
      }
    }

    buildings = remaining;
    _buildingsDirty = true;
    _promoteQueuedBuildings();
    // Pull any workers off the demolished building so they don't stay stuck
    // pointing at a building that no longer exists.
    await CreaturesController().unassignAllFrom(buildingId);
    notifyListeners();
    await _svc.deleteBuilding(buildingId);
    return null;
  }

  /// Stops or restarts a building (user 2026-08-01: "ich will gebäude
  /// pausieren können").
  ///
  /// The state is applied LOCALLY first and saved after, like every other
  /// building edit: pausing is what you reach for when something is draining
  /// away, and a switch that waits for the network is a switch you press twice.
  Future<void> setPaused(String buildingId, bool paused) async {
    final idx = buildings.indexWhere((b) => b.id == buildingId);
    if (idx < 0) return;
    _buildingsDirty = true;
    buildings = [
      for (final b in buildings)
        if (b.id == buildingId) b.copyWith(isPaused: paused) else b,
    ];
    notifyListeners();
    try {
      await _svc.setBuildingPaused(buildingId, paused);
    } catch (e) {
      debugPrint('[SettlementController] setPaused save failed: $e');
      _flagSaveFailed();
    }
  }

  Future<String?> moveBuilding(
    String buildingId,
    int newX,
    int newY, {
    int? rotation,
  }) async {
    final idx = buildings.indexWhere((b) => b.id == buildingId);
    if (idx < 0) return 'Building not found';
    final b = buildings[idx];
    // Optionally turned on the way (user 2026-11-03): the new footprint is
    // the one that has to fit.
    final def = rotation == null
        ? placedDefOf(b)
        : defRotated(b.buildingTypeId, rotation);
    if (def == null) return 'Unknown building type';
    // Permanent — same reasoning as deleteBuilding.
    if (def.isBuildPlot) return 'Building Plots cannot be moved.';

    if (!isAreaFree(newX, newY, def.gridW, def.gridH, excludeId: buildingId)) {
      return 'Space is occupied';
    }
    if (def.isBuildPlot) {
      if (!GameEngine.touchesBuildableRegion(
        newX,
        newY,
        def.gridW,
        def.gridH,
        buildings,
      )) {
        return 'Must be adjacent to your existing territory';
      }
    } else if (!GameEngine.isAreaBuildable(
      newX,
      newY,
      def.gridW,
      def.gridH,
      buildings,
    )) {
      return 'Outside buildable area';
    }

    _buildingsDirty = true;
    buildings = [
      for (final existing in buildings)
        if (existing.id == buildingId)
          // isStored: false unconditionally — this is also how a building
          // LEAVES the Umbaumodus tray (user 2026-09-22): placing it from
          // storage is the same call as moving one already on the map, it
          // just also clears the flag that made it invisible and non-
          // blocking. A no-op for a building that was never stored.
          existing.copyWith(
            gridX: newX,
            gridY: newY,
            isStored: false,
            rotation: def.rotation,
          )
        else
          existing,
    ];
    // The rearrange is DONE, not just this one placement, the moment the
    // tray runs out — nothing is left for cancelRecall to put back, so its
    // memory of where everything came from can go too (user 2026-09-22:
    // closing early undoes the whole visit, but finishing it for real must
    // not leave a stale revert sitting around for next time).
    if (_recallOrigin.isNotEmpty && !hasStoredBuildings) {
      _recallOrigin.clear();
    }

    notifyListeners();
    await _svc.moveBuilding(buildingId, newX, newY, rotation: def.rotation);
    return null;
  }

  // ── Umbaumodus: recall the whole city (user 2026-09-22) ────
  // "der Umbaumodus soll so sein wie bei FoE. D.h ich kann alle Gebäude
  // 'zurücknehmen' und dann einzeln frei platzieren. Ich kann aber auch
  // Gebäude verschieben wie bis anhin." — TWO tools now share Umbaumodus:
  // tapping a building on the map still moves just that one exactly as
  // before (moveBuilding above, unchanged); this is the OTHER one, for a
  // full redesign, where whatever is already standing in the way is never
  // the obstacle it used to be.

  /// Every recalled building's spot from BEFORE this Umbaumodus visit
  /// touched it, so [cancelRecall] has something to put back. Grows across
  /// however many "Alle Gebäude zurücknehmen" presses happen in one session
  /// (a building already in here keeps its FIRST-recorded spot, never a
  /// later, already-replaced one) and is cleared the moment there is
  /// nothing left to revert — either every recalled building has a new home
  /// ([moveBuilding] clears its entry the instant that makes the tray
  /// empty) or [cancelRecall] just put everything back.
  /// (x, y, quarter turns) — a turn made during the visit undoes too.
  final Map<String, (int, int, int)> _recallOrigin = {};

  /// True once there is something [cancelRecall] would actually undo —
  /// closing Umbaumodus while this is true is what triggers it (user
  /// 2026-09-22: "wenn ich es schliesse, bevor ich fertig bin, dann soll
  /// einfach alles rückgängig gemacht werden").
  bool get hasRecallInProgress => _recallOrigin.isNotEmpty;

  /// Everything currently in the tray, recalled but not yet given a new
  /// spot — see [recallAllBuildings]. The map draws none of these (they are
  /// not standing anywhere) and offers them back up as a row of tiles to tap
  /// and place.
  List<PlacedBuilding> get storedBuildings => [
    for (final b in buildings)
      if (b.isStored) b,
  ];

  /// True while the tray holds anything.
  bool get hasStoredBuildings => buildings.any((b) => b.isStored);

  /// What [recallAllBuildings] is allowed to touch: everything actually
  /// placed right now except the Castle (the settlement itself — see
  /// deleteBuilding's own reasoning), Building Plots (permanent territory,
  /// never move) and roads — roads have their OWN bulk tool now
  /// ([recallableRoads]/[recallAllRoads], user 2026-09-22: "es braucht auch
  /// noch einen Button, um alle Strassen aufzuheben"), kept separate so a
  /// tray of thirty individual road tiles never drowns out the real
  /// buildings sitting in it.
  List<PlacedBuilding> get recallableBuildings {
    final out = <PlacedBuilding>[];
    for (final b in buildings) {
      if (b.isStored) continue;
      final def = placedDefOf(b);
      if (def == null || def.isMainBuilding || def.isBuildPlot || def.isRoad) {
        continue;
      }
      out.add(b);
    }
    return out;
  }

  /// Every placed road, none recalled yet — the source [recallAllRoads]
  /// works through.
  List<PlacedBuilding> get recallableRoads {
    final out = <PlacedBuilding>[];
    for (final b in buildings) {
      if (b.isStored) continue;
      if (placedDefOf(b)?.isRoad ?? false) out.add(b);
    }
    return out;
  }

  /// "Alle Gebäude zurücknehmen": every [recallableBuildings] entry leaves
  /// the map at once and waits in [storedBuildings] — a full replan never has
  /// to shuffle around whatever is still standing in the way first.
  ///
  /// Nothing is deleted and nothing here costs anything: a stored building
  /// keeps its level, its workers and its construction progress exactly as
  /// a PAUSED one does (see [PlacedBuilding.isPaused]'s own doc comment) —
  /// it simply isn't standing anywhere until [moveBuilding] places it again,
  /// which is also what clears the flag. Its housing/production pause the
  /// same way an unconnected building's already do
  /// ([GameEngine.connectedBuildingIds] skips a stored building the same way
  /// it skips an incomplete one), so no separate effect bookkeeping is
  /// needed here.
  Future<void> recallAllBuildings() => _recallAll(recallableBuildings);

  /// "Alle Straßen zurücknehmen" (user 2026-09-22) — same tool, same tray,
  /// same [_recallOrigin] snapshot (so [cancelRecall] undoes buildings and
  /// roads together regardless of which button recalled which), just
  /// sourced from [recallableRoads] instead.
  Future<void> recallAllRoads() => _recallAll(recallableRoads);

  Future<void> _recallAll(List<PlacedBuilding> targets) async {
    if (targets.isEmpty) return;
    final ids = [for (final b in targets) b.id];
    final idSet = ids.toSet();
    // Only a building's FIRST recall this session records where it came
    // from — a second "Alle zurücknehmen" press must not overwrite that
    // with a spot it only reached because this same rearrange put it there.
    for (final b in targets) {
      _recallOrigin.putIfAbsent(b.id, () => (b.gridX, b.gridY, b.rotation));
    }
    _buildingsDirty = true;
    buildings = [
      for (final b in buildings)
        if (idSet.contains(b.id)) b.copyWith(isStored: true) else b,
    ];
    notifyListeners();
    await _svc.setBuildingsStored(ids, true);
  }

  /// Umbaumodus closed with the tray still non-empty (user 2026-09-22): the
  /// WHOLE rearrange undoes at once, not just what is still sitting in the
  /// tray — a building already placed somewhere else during this same
  /// unfinished visit goes back too, because "fertig" never happened.
  /// [_recallOrigin] is what makes that possible: it remembers where every
  /// touched building stood before this visit picked it up at all.
  Future<void> cancelRecall() async {
    if (_recallOrigin.isEmpty) return;
    final origin = Map<String, (int, int, int)>.from(_recallOrigin);
    _recallOrigin.clear();
    final reverted = <PlacedBuilding>[];
    final next = <PlacedBuilding>[];
    for (final b in buildings) {
      final spot = origin[b.id];
      if (spot == null) {
        next.add(b);
        continue;
      }
      final back = b.copyWith(
        gridX: spot.$1,
        gridY: spot.$2,
        isStored: false,
        rotation: spot.$3,
      );
      reverted.add(back);
      next.add(back);
    }
    _buildingsDirty = true;
    buildings = next;
    notifyListeners();
    await _svc.saveBuildings(reverted);
    for (final b in reverted) {
      await _svc.setBuildingRotation(b.id, b.rotation);
    }
  }

  // ── Helpers ───────────────────────────────────────────────

  bool _isAreaFreeImpl(int x, int y, int w, int h, {String? excludeId}) {
    if (x < 0 || y < 0 || x + w > kGridCols || y + h > kGridRows) return false;
    for (final b in buildings) {
      if (b.id == excludeId) continue;
      final def = placedDefOf(b);
      // Building Plots mark territory, not structures — they never block
      // other buildings from later occupying the same ground. A STORED
      // building (Umbaumodus tray, user 2026-09-22) isn't standing anywhere
      // either — its gridX/gridY are stale, so it must never block a spot.
      if (def == null || def.isBuildPlot || b.isStored) continue;
      final bRight = b.gridX + def.gridW;
      final bBottom = b.gridY + def.gridH;
      final nRight = x + w;
      final nBottom = y + h;
      if (x < bRight && nRight > b.gridX && y < bBottom && nBottom > b.gridY) {
        return false;
      }
    }
    return true;
  }

  bool _isAreaFree(int x, int y, int w, int h) => _isAreaFreeImpl(x, y, w, h);
  bool isAreaFree(int x, int y, int w, int h, {String? excludeId}) =>
      _isAreaFreeImpl(x, y, w, h, excludeId: excludeId);

  // ── Hourly display rates ──────────────────────────────────
  Map<String, double> get hourlyRates {
    if (energy == null) return {};
    final eb = _noEraBonus;
    return GameEngine.hourlyRates(
      energy!,
      workshopPower(),
      techWood: eb.wood,
      techStone: eb.stone,
      techGoods: eb.food,
      techAll: eb.all,
    );
  }

  /// What building [b] makes of [resourceId] per hour at 100 % energy and before
  /// the tech bonus — read EXACTLY the way [workshopPower] reads it (the same
  /// presence rule, and each post's own level factor via
  /// [WorkshopRole.contribution]), so the breakdown's rows add up to the rate
  /// the header shows. (They used to apply the global level curve to every post
  /// and drifted from the header wherever a role authors its own factor.)
  double _buildingOutput(
    PlacedBuilding b,
    BuildingDef def,
    String resourceId,
    CreaturesController creatures,
    int era,
  ) {
    var amount = 0.0;
    for (final c in creatures.creatures) {
      if (c.assignedBuildingId != b.id) continue;
      final role = _postedRole(c, def, creatures);
      if (role == null || role.resource == WorkshopRole.kStorageRoom) continue;
      amount +=
          role.contribution(
            (s) => c.statValue(s).toDouble(),
            b.level,
          )[resourceId] ??
          0;
    }
    final effVal = def.effectAt('production', resourceId, era, level: b.level);
    if (effVal != 0) {
      amount += effVal;
    }
    return amount;
  }

  /// Whether [def] has a post or a `production` effect that makes [resourceId] —
  /// what a paused building of it would be making.
  bool _canMake(BuildingDef def, String resourceId) =>
      def.workshops.any(
        (r) =>
            r.resource == resourceId ||
            (r.isCombined && r.parts.values.contains(resourceId)),
      ) ||
      def.effectKeys('production').contains(resourceId);

  // ── Resource-tap breakdown, PER BUILDING (user 2026-08-31) ──
  // [productionSources] groups by building TYPE; the Resource screen's own
  // "Produced by" list wants one row per INSTANCE instead, the same reason
  // Housing/Work list buildings individually rather than by type — two
  // Lumber Camps with different crews or levels do not make the same wood.
  // Same math as [productionSources]' own per-building loop, just kept apart
  // rather than summed into `totals`.
  List<(PlacedBuilding, BuildingDef, double)> productionSourcesByBuilding(
    String resourceId,
  ) {
    final connected = connectedBuildingIds;
    final eb = _noEraBonus;
    double bonusMult;
    if (resourceId == 'wood' || resourceId == 'stone' || resourceId == 'gold') {
      final pct = resourceId == 'wood'
          ? eb.wood + eb.all
          : resourceId == 'stone'
          ? eb.stone + eb.all
          : 0.0;
      bonusMult = 1 + pct;
    } else {
      bonusMult = 1 + eb.food;
    }
    final creatures = CreaturesController();
    final era = dungeonMaxStage;
    final out = <(PlacedBuilding, BuildingDef, double)>[];
    for (final b in buildings) {
      final def = placedDefOf(b);
      if (def == null) continue;
      // A building mid-UPGRADE makes nothing until it finishes — shown at
      // 0/h rather than silently vanishing from the list (user 2026-09-22:
      // "Gebäude, welche gerade upgegraded werden, sollen ... mit 0/h
      // angezeigt werden ... im Bau genau wie pausiert"). `level > 1` is
      // what marks an upgrade in progress rather than a first-time build,
      // which never had output to miss in the first place.
      if (!b.isComplete && b.level > 1) {
        if (_canMake(def, resourceId)) out.add((b, def, 0.0));
        continue;
      }
      if (!b.isComplete) continue;
      // A PAUSED building stays on the list, making nothing (user 2026-09-22:
      // "auch die Gebäude anzeigen, welche pausiert sind und mit 0/h"): it is the
      // first thing to look at when a rate is lower than expected. Only ones that
      // could make this resource are listed.
      if (b.isPaused) {
        if (_canMake(def, resourceId)) out.add((b, def, 0.0));
        continue;
      }
      if (!connected.contains(b.id)) continue;
      final amount = _buildingOutput(b, def, resourceId, creatures, era);
      if (amount == 0) continue;
      out.add((b, def, amount * bonusMult));
    }
    return out;
  }

  // ── Resource-tap breakdown ("where does this come from") ──
  // Groups the creature-driven output for [resourceId] by workshop building
  // type, applying the same tech bonuses as hourlyRates so the rows add
  // up to the header rate. For goods (fish/meat) it appends a consumption row.
  List<ProductionSource> productionSources(String resourceId) {
    final connected = connectedBuildingIds;
    final eb = _noEraBonus;

    // Bonus multiplier matching hourlyRates for this resource.
    double bonusMult = 1.0;
    if (resourceId == 'wood' || resourceId == 'stone' || resourceId == 'gold') {
      final pct = resourceId == 'wood'
          ? eb.wood + eb.all
          : resourceId == 'stone'
          ? eb.stone + eb.all
          : 0.0; // gold: no percentage bonus
      bonusMult = 1 + pct;
    } else {
      bonusMult = 1 + eb.food; // goods
    }

    // Per-building-type creature output for this resource.
    final creatures = CreaturesController();
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final b in buildings) {
      if (!b.isComplete || b.isPaused || !connected.contains(b.id)) continue;
      final def = placedDefOf(b);
      if (def == null) continue;
      final out = _buildingOutput(
        b,
        def,
        resourceId,
        creatures,
        dungeonMaxStage,
      );
      if (out == 0) continue;
      totals[def.id] = (totals[def.id] ?? 0) + out * bonusMult;
      counts[def.id] = (counts[def.id] ?? 0) + 1;
    }

    final sources = totals.entries.map((e) {
      final def = kBuildingDefs[e.key]!;
      return ProductionSource(
        imageUrl: def.imageUrl,
        defId: def.id,
        label: def.name,
        count: counts[e.key]!,
        amount: e.value,
      );
    }).toList()..sort((a, b) => b.amount.compareTo(a.amount));

    // ── WHAT EATS IT (user 2026-08-01: "sollen mir auch die negativen Werte/
    // Verbrauch angezeigt werden und am Ende das Total, welches wirklich
    // produziert wird") ──
    //
    // Creatures eating was the only drain this list knew about. The other one is
    // REFINING: a Clay Refinery making 5 Timber Frame an hour is quietly eating
    // 10 wood and 10 stone, and [GameEngine.hourlyRates] has always subtracted
    // that — so the header showed a net rate while this sheet listed only the
    // gross, and the rows did not add up to the number above them.
    //
    // Grouped per REFINED GOOD rather than per building, because that is how the
    // rate is computed (workshopPower is per good): one line per thing being
    // made from this, which is also the line you would act on.
    final rates = hourlyRates;
    for (final g in kGoodsDefs.values.where((g) => g.isElement)) {
      final per = g.refinedFrom[resourceId];
      if (per == null || per <= 0) continue;
      final made = rates[g.id] ?? 0;
      if (made <= 0) continue;
      sources.add(
        ProductionSource(
          emoji: g.emoji,
          label: 'Refined into ${g.name}',
          count: 1,
          amount: -made * per,
        ),
      );
    }

    // Goods consumption row (creatures eating).
    final gDef = kGoodsDefs[resourceId];
    if (gDef != null &&
        gDef.consumptionPerCapitaPerHour > 0 &&
        housingUsed > 0) {
      sources.add(
        ProductionSource(
          emoji: '🐾',
          label: 'Creature upkeep',
          count: housingUsed,
          amount: -housingUsed * gDef.consumptionPerCapitaPerHour,
        ),
      );
    }
    return sources;
  }

  List<ProductionSource> get housingSources =>
      GameEngine.housingSources(buildings, eraOrder: dungeonMaxStage);

  // ── Spending ──────────────────────────────────────────────
  /// Pays a cost map (dungeon entry, healing, gold speed-ups).
  /// Returns false without any changes when unaffordable.
  Future<bool> spendResources(Map<String, double> cost) async {
    final res = resources;
    if (res == null) return false;
    for (final e in cost.entries) {
      if ((res.asMap[e.key] ?? 0) < e.value) return false;
    }
    resources = res.deduct(cost);
    notifyListeners();
    try {
      await _svc.saveResources(resources!);
    } catch (e) {
      debugPrint('[SettlementController] spendResources save failed: $e');
      _flagSaveFailed();
    }
    return true;
  }

  /// Credits dungeon-space loot. Rewards are granted immediately per cleared
  /// space, so a failed run keeps everything earned (decided design).
  ///
  /// The ceiling only limits what THIS grant adds ([withProductionCapped]).
  /// It used to `capped()` the whole store, which also deleted any legal
  /// overflow a redeemed resource pack had left above the ceiling — any daily
  /// reward or homecoming trip, in any resource, silently trimmed a pack the
  /// player had paid for.
  ///
  /// [refund] returns something the player paid a moment ago (a failed
  /// send, a recalled caravan, a gold skip that could not reach the server):
  /// it goes back in full, ceiling or not — a store that filled up in the
  /// meantime must not swallow the player's own goods.
  Future<void> grantResources(
    Map<String, double> amounts, {
    bool refund = false,
  }) async {
    final res = resources;
    if (res == null) return;
    final granted = res.grant(amounts);
    resources = refund
        ? granted
        : res.withProductionCapped(granted, storageCaps);
    notifyListeners();
    try {
      await _svc.saveResources(resources!);
    } catch (e) {
      debugPrint('[SettlementController] grantResources save failed: $e');
      _flagSaveFailed();
    }
  }

  // ── Dungeon stage progression (creature system) ───────────
  /// How many Building Plots the player may have placed — one per earned
  /// expansion unlock (user 2026-07-17: Building Plots are a REWARD, not a tech;
  /// each "expansion point" cleared on the map grants one via [unlockExpansion]).
  int get buildPlotLimit => expansionsUnlocked;

  /// Grants one expansion-unlock reward (a map "expansion point" was cleared) —
  /// raises [buildPlotLimit] by one and persists. Call this from the map's
  /// expansion points.
  Future<void> unlockExpansion() async {
    expansionsUnlocked++;
    _progressDirty = true;
    notifyListeners();
    await _persist();
  }

  /// Called when a dungeon run clears [stage]'s boss — permanently unlocks
  /// stage+1 if it isn't already. No-op (and no write) if already unlocked.
  ///
  /// FULLY AUTOMATIC (user 2026-09-05: eras removed, no paid Castle
  /// ascension) — everything that used to happen at the manual ascension
  /// step (the main hall auto-leveling to match, the new level cap
  /// announcement) now happens right here, the instant the boss falls. No
  /// resource cost and no permanent bonus grant survive from that mechanic;
  /// only the path's own reward system (items/buildings/expansions) pays
  /// out any more.
  Future<void> unlockDungeonStage(int stage) async {
    final next = stage + 1;
    if (next <= dungeonMaxStage) return;
    dungeonMaxStage = next;
    // The hall's level IS the region reached — unique + permanent, so it's
    // exempt from the normal upgrade flow and the successor model alike.
    final hallIdx = buildings.indexWhere(
      (b) => placedDefOf(b)?.isMainBuilding ?? false,
    );
    if (hallIdx >= 0 && buildings[hallIdx].level < next) {
      buildings = [
        for (final b in buildings)
          if (b.id == buildings[hallIdx].id) b.copyWith(level: next) else b,
      ];
      _buildingsDirty = true;
    }
    _progressDirty = true;
    notifyListeners();
    await _persist();
    GameEventLog().add(
      GameEventKind.research,
      'Region $next reached! Monsters can now reach '
      'Lv ${creatureLevelCap(next)}.',
    );
  }

  /// Advances the linear-path progress by one won battle (user 2026-07-24), up
  /// to [toBattle] if given (never backwards). Persisted. This is what grows the
  /// party ([partyCap]) as the player works up the line — and, in the linear
  /// rebuild, what will fire map-milestone unlocks (buildings, legendaries).
  ///
  /// BRIDGE NOTE: for now this is called from the shared battle-victory path
  /// (battle_screen), so any won fight counts. Once battles are individual path
  /// NODES it will only count clearing a NEW node (no re-fight double-count).
  Future<void> advanceBattlesCleared({int? toBattle}) async {
    final next = toBattle ?? battlesCleared + 1;
    if (next <= battlesCleared) return;
    final grew = partySizeForBattle(next) > partySizeForBattle(battlesCleared);
    // Expansion rewards come from the authored path nodes.
    final newExpansions =
        pathExpansionsGranted(next) - pathExpansionsGranted(battlesCleared);
    // LOOT: the items a node hands out — potions, lures, and since 2026-07-30
    // the RESOURCE PACKAGES that replaced raw resource rewards entirely (user:
    // "«normale» Ressourcen gibt es nicht mehr als Belohnungen"). A delta over
    // the nodes just cleared, so a jump straight to battle N pays every node in
    // between exactly once.
    final itemLoot = pathItemLoot(battlesCleared, next);
    battlesCleared = next;
    // Territory-expansion points a node just granted (folded into one persist
    // below rather than a save per point).
    if (newExpansions > 0) expansionsUnlocked += newExpansions;
    _grantItems(itemLoot);
    if (grew) {
      GameEventLog().add(
        GameEventKind.levelUp,
        'Your battle party can now hold $partyCap monster'
        '${partyCap > 1 ? 's' : ''}!',
      );
    }
    _progressDirty = true;
    notifyListeners();
    await _persist();
  }

  /// Banks a finished Survival Mode run (user 2026-09-06): grants gold via
  /// the same [grantResources] every other instant reward uses (daily-task
  /// claims included), and bumps [survivalBestFloor] if this run beat it.
  /// Called once, when the run ends (defeat or a voluntary retreat) — never
  /// per floor, since the reward is "only at the end, scaled by how far you
  /// got" by design.
  Future<void> recordSurvivalRun(int floorsCleared) async {
    // Priced against the record BEFORE this run raises it — only new floors
    // pay the full rate (see goldRewardForFloors).
    final gold = goldRewardForFloors(
      floorsCleared,
      previousBest: survivalBestFloor,
    );
    if (floorsCleared > survivalBestFloor) survivalBestFloor = floorsCleared;
    if (gold > 0) await grantResources({'gold': gold});
    _progressDirty = true;
    notifyListeners();
    await _persist();
  }

  // ── Gold: surplus → time ──────────────────────────────────
  // See services/gold_economy.dart for the rates and the reasoning. Gold gates
  // NOTHING — it only ever removes waiting — so everything here is optional.

  // Selling, buying goods and bartering all used to settle HERE, instantly.
  // They are caravan trips now (user 2026-07-26: "sobald ich einen trade
  // auswähle, sende ich eine Expedition"), so the three over-the-counter
  // methods are gone rather than left lying around: a second, instant path to
  // the same payout is how a trade ends up costing nothing and paying twice.
  //
  // The rates themselves did not move — the caravan prices through the very
  // same services/trade_center.dart functions with [tradeDiscount] applied.
  // See ExpeditionController.startTrade for where cargo leaves and arrives.

  double get gold => resources?.gold ?? 0;

  // ── Trade Center: gold → items, gold → goods, goods ↔ goods ──
  // The other three directions of the market (user 2026-07-25, item Phase 3).
  // All of them price through services/trade_center.dart with [tradeDiscount],
  // so the sheet never computes a rate of its own. Each returns null on success
  // or a user-facing reason, exactly like [sellForGold].

  /// Buys one [itemId] from the Trade Center for gold.
  Future<String?> buyItem(String itemId) async {
    final s = settlement;
    final res = resources;
    if (s == null || res == null) return 'Not loaded';
    final def = kItemDefs[itemId];
    if (def == null) return 'Unknown item';
    if (!itemIsSold(def)) return '${def.name} is not for sale.';
    final cost = itemBuyCost(def, discount: tradeDiscount);
    if (res.gold < cost) {
      return 'Not enough gold (need $cost, have ${res.gold.toInt()}).';
    }
    resources = res.deduct({'gold': cost.toDouble()});
    settlement = s.copyWith(items: addItem(s.items, itemId));
    GameEventLog().add(
      GameEventKind.craft,
      '${def.emoji} ${def.name} bought for 🪙 $cost',
    );
    notifyListeners();
    await _persist();
    return null;
  }

  /// Sells one [itemId] back to the Trade Center. Always worth less than buying
  /// it (see [itemSellValue]) — this is a way out of a bad bag, not an income.
  Future<String?> sellItem(String itemId) async {
    final s = settlement;
    final res = resources;
    if (s == null || res == null) return 'Not loaded';
    final def = kItemDefs[itemId];
    if (def == null) return 'Unknown item';
    final earned = itemSellValue(def, discount: tradeDiscount);
    if (earned <= 0) return '${def.name} can\'t be sold.';
    final next = removeItem(s.items, itemId);
    if (next == null) return 'You have none left';
    // Same ceiling rule as grantResources: only what is ADDED is limited,
    // a redeemed pack's overflow elsewhere is never trimmed.
    resources = res.withProductionCapped(
      res.grant({'gold': earned.toDouble()}),
      storageCaps,
    );
    settlement = s.copyWith(items: next);
    notifyListeners();
    await _persist();
    return null;
  }

  /// Drops [loot] (itemId → count) into the bag — path-node rewards and any
  /// other system that hands out items. Persisting is left to the caller so a
  /// grant can ride along with other progress in ONE write.
  void _grantItems(Map<String, int> loot) {
    final s = settlement;
    if (s == null || loot.isEmpty) return;
    var bag = s.items;
    for (final e in loot.entries) {
      if (e.value <= 0) continue;
      bag = addItem(bag, e.key, e.value);
      NewItems().add(e.key, e.value);
      final def = kItemDefs[e.key];
      GameEventLog().add(
        GameEventKind.craft,
        '${def?.emoji ?? '🎁'} ${def?.name ?? e.key} ×${e.value} received',
      );
    }
    settlement = s.copyWith(items: bag);
  }

  /// One-time gift for the tutorial's scripted first fight (user 2026-09-03:
  /// "ich bekomme Schaden, welchen ich mit einem Heilitem während dem Kampf
  /// heile") — a fresh account has no heal item at all yet, since potions
  /// are crafted and crafting needs a Workshop the player hasn't built this
  /// early. Idempotent (checks for an existing one first), so re-entering
  /// the fight never stacks a second free potion.
  Future<void> grantTutorialPotion() async {
    final s = settlement;
    if (s == null || (s.items['minor_potion'] ?? 0) > 0) return;
    _grantItems({'minor_potion': 1});
    await _persist();
  }

  /// Gold to finish [b]'s construction now. 0 when it's already done.
  int buildSkipCost(PlacedBuilding b) {
    if (b.isComplete) return 0;
    final remainingSeconds =
        b.constructionSecondsRequired - b.constructionSecondsBuilt;
    if (remainingSeconds <= 0) return 0;
    // Priced on the REAL wait: every site builds at the full rate now, and
    // there is always a wait to price — the rate starts at 3600 s/h with zero
    // builders, so the old "standstill" branch is gone (user 2026-07-26).
    final hours = remainingSeconds / buildRatePerHour;
    return goldToSkip(Duration(seconds: (hours * 3600).ceil()));
  }

  /// Pays gold to finish [b] immediately.
  Future<String?> skipBuildWithGold(PlacedBuilding b) async {
    if (b.isComplete) return 'Already built.';
    final cost = buildSkipCost(b);
    if (!await spendResources({'gold': cost.toDouble()})) {
      return 'Not enough gold (need $cost, have ${gold.toInt()}).';
    }
    _buildingsDirty = true;
    buildings = [
      for (final x in buildings)
        if (x.id == b.id)
          x.copyWith(
            constructionSecondsBuilt: x.constructionSecondsRequired,
            isComplete: true,
          )
        else
          x,
    ];
    _promoteQueuedBuildings();
    // The tutorial's build steps normally advance from _applyTick's own
    // completion sweep (see there) — which this skips entirely, since it
    // flips isComplete directly rather than through a tick. Without this a
    // gold-skipped building left the step exactly where it was, still
    // asking to build the thing that was just finished (user 2026-09-06).
    final introBuildStep = kIntroBuildSteps[b.buildingTypeId];
    if (introBuildStep != null) unawaited(advanceIntro(introBuildStep));
    // The same two side effects the tick's completion sweep has — a
    // gold-finished building used to count for nothing towards the daily
    // "Finish buildings" goal and never appeared in the event feed.
    reportDailyProgress(DailyTaskKind.finishBuildings);
    GameEventLog().add(
      GameEventKind.building,
      '${placedDefOf(b)?.name ?? b.buildingTypeId} '
      'is finished',
      ref: b.id,
    );
    notifyListeners();
    await _persist();
    return null;
  }

  // ── Intro chain / jumpstart ───────────────────────────────
  // See lib/features/onboarding/intro_flow.dart for the design (and for why
  // the jumpstart is a temporary multiplier rather than new base values).

  /// Completes [from] and moves to the next step — but ONLY if [from] is
  /// actually the current step. Milestone callbacks fire from several places
  /// (and can fire again later: the region boss also grants a catch), so this
  /// guard is what keeps them idempotent and stops a late call from dragging
  /// a player backwards or skipping a step they never saw.
  Future<void> advanceIntro(IntroStep from) async {
    if (introStep != from) return;
    var next = from.next;
    // healStarter has nothing to do when nobody is hurt (a player who
    // somehow WON the practice fight) — skip rather than dead-end a script
    // whose only lit button would be "treat nobody".
    if (next == IntroStep.healStarter &&
        CreaturesController().hurtCreatures.isEmpty) {
      next = next.next;
    }
    await _setIntroStep(next);
    if (introStep == IntroStep.done) {
      GameEventLog().add(
        GameEventKind.building,
        // "Castle", the building's own name in kBuildingDefs and on every
        // other screen — the intro cards were corrected to it on 2026-09-06
        // (see intro_flow.dart's buildRoad card) and this one, the very last
        // thing the tutorial says, was left behind calling it something the
        // player has never seen (fixed 2026-09-21).
        '🎓 Tutorial complete! Road connectivity is enforced for real now '
        '— keep every new building linked back to the Castle via '
        'Build ▸ Roads.',
      );
    }
  }

  /// Player-initiated "✕ Skip" — ends the chain and the jumpstart at once.
  Future<void> skipIntro() => _setIntroStep(IntroStep.done);

  /// Dev-mode only: replays the intro from the top. Existing accounts are
  /// backfilled to `done` by migration 0005, so without this there is no way
  /// to see the flow again on an account that already has progress.
  Future<void> restartIntro() => _setIntroStep(IntroStep.welcome);

  Future<void> _setIntroStep(IntroStep step) async {
    if (introStep == step) return;
    final wasActive = introStep.isActive;
    introStep = step;
    // The tutorial answers "is it connected?" with "everything is", and that
    // answer is cached alongside the real one — so crossing into or out of
    // the tutorial invalidates it even though the LAYOUT has not moved.
    if (wasActive != step.isActive) _connectedCache = null;
    notifyListeners();
    final userId = _userId;
    if (userId != null) await _svc.saveIntroStep(userId, step.index);
  }
}
