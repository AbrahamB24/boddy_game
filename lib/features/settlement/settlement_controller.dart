import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/supabase/supabase_client.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/services/creature_defs_controller.dart';
import '../creatures/services/creatures_controller.dart';
import 'data/building_definitions.dart';
import 'data/era_definitions.dart';
import 'data/goods_definitions.dart';
import 'data/tech_definitions.dart';
import 'models/energy_model.dart';
import 'models/placed_building.dart';
import 'models/resource_model.dart';
import 'models/settlement.dart';
import 'services/game_defs_controller.dart';
import 'services/game_engine.dart';
import 'services/settlement_service.dart';

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
  Set<String> unlockedTechs = {};
  int bp = 0;
  int level = 1;
  bool isDev = false;

  /// Highest dungeon stage unlocked so far (permanent progression — see
  /// kMaxDungeonStage in dungeon.dart). Clearing stage N's boss unlocks N+1.
  int dungeonMaxStage = 1;

  bool isLoading = true;
  String? error;

  Timer? _tickTimer;
  // Set when a research completes locally (via _applyTick) but hasn't been
  // written to `research_unlocks` yet — retried on the next _persist() cycle.
  String? _pendingUnlockedTechId;

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

      final results = await Future.wait([
        _svc.loadResources(sid),
        _svc.loadEnergy(sid),
        _svc.loadBuildings(sid),
        _svc.loadProfile(userId),
        _svc.loadResearch(sid).catchError((_) => <String>{}),
        // Dev-mode building/tech defs — RLS requires an authenticated user,
        // so this is loaded here (post-login) rather than in main.dart.
        // Bundled fallback defs are already usable before this resolves.
        GameDefsController().load(),
        _svc.loadIsDev(userId),
        _svc.loadWorkoutStats(userId),
        // Creature/ability defs (dev-mode content for the creature system).
        // Appended last — nothing reads its result slot, the maps are global.
        CreatureDefsController().load(),
        // The creature collection IS the workforce: workshopPower() (and the
        // offline _applyTick below) read CreaturesController().creatures, so it
        // must be loaded here rather than lazily on the creatures screen —
        // otherwise the economy produces nothing until that screen is opened.
        CreaturesController().load(),
      ]);

      resources = results[0] as ResourceModel;
      energy = results[1] as EnergyModel;
      buildings = results[2] as List<PlacedBuilding>;
      final profile = results[3] as Map<String, int>;
      unlockedTechs = results[4] as Set<String>;
      isDev = results[6] as bool;
      bp = profile['bp']!;
      level = profile['level']!;
      dungeonMaxStage = profile['dungeon_max_stage'] ?? 1;

      // Restore persisted workout stats. The daily-BP counter's getters call
      // _resetDailyIfNeeded, which zeroes it lazily if the stored day passed.
      final ws =
          results[7]
              as ({
                int bpToday,
                String? bpDate,
                int completed,
                int streak,
                String? lastDate,
              });
      _workoutBpToday = ws.bpToday;
      _workoutBpDate = ws.bpDate ?? '';
      workoutsCompleted = ws.completed;
      workoutStreak = ws.streak;
      _lastWorkoutDate = ws.lastDate ?? '';

      debugPrint(
        '[LOAD] From DB — '
        'lastUpdatedAt=${energy!.lastUpdatedAt.toIso8601String()} '
        'energy=${energy!.currentEnergy.toStringAsFixed(1)} '
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
          buildings = [
            for (final b in buildings)
              if (toQueue.contains(b.id)) b.copyWith(isQueued: true) else b,
          ];
        }
      }

      // Apply offline production FIRST using the original lastUpdatedAt from Supabase.
      final beforeStone = resources!.stone;
      final now = DateTime.now().toUtc();
      final hoursDelta =
          now.difference(energy!.lastUpdatedAt).inMicroseconds / 3.6e9;
      _applyTick(now);
      debugPrint(
        '[LOAD] After tick — '
        'hoursDelta=${hoursDelta.toStringAsFixed(4)}h '
        'stone: ${beforeStone.toStringAsFixed(0)} → ${resources!.stone.toStringAsFixed(0)} '
        'energy=${energy!.currentEnergy.toStringAsFixed(1)}',
      );

      await _persist();

      _tickTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _applyTick(DateTime.now().toUtc());
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

  // Wipes buildings/resources/energy/research back to a fresh start (BP/level
  // untouched — those live on `profiles`, not the settlement) and reloads.
  Future<void> resetSettlement() async {
    if (settlement == null) return;
    await _svc.resetSettlement(settlement!.id);
    await load();
  }

  // ── Housing (creatures ARE the population) ─────────────────
  // How many creatures the settlement can shelter (sum of functional housing
  // buildings' capacity). Every creature the player owns occupies one slot; a
  // full settlement blocks catching/hatching/adopting (enforced in
  // CreaturesController via [housingFull]).
  int get housingCapacity => resources == null
      ? 0
      : GameEngine.housingCapacity(buildings, resources!.goods);

  int get housingUsed => CreaturesController().creatures.length;

  int get housingFree => (housingCapacity - housingUsed).clamp(0, housingCapacity);

  bool get housingFull => housingUsed >= housingCapacity;

  // ── Workshop power (creature-driven production) ────────────
  // Sums, per output, the relevant civilian stat of every creature currently
  // stationed in a functional workshop and actually able to work (not K.O.,
  // has energy, not breeding). Keys are settlement resource ids ('wood',
  // 'stone', 'gold', 'fish', 'fur') plus the pseudo-outputs
  // WorkshopRole.kConstruction / kResearch. This is THE bridge between the
  // creature collection and the settlement economy — tick(), hourlyRates and
  // the countdown estimates all read it.
  Map<String, double> workshopPower() {
    final connected = connectedBuildingIds;
    // Functional workshop buildings, by id → their def.
    final workshopDefs = <String, BuildingDef>{};
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      if (def != null && def.workshops.isNotEmpty) workshopDefs[b.id] = def;
    }
    final creatures = CreaturesController();
    final power = <String, double>{};
    for (final c in creatures.creatures) {
      final bId = c.assignedBuildingId;
      final stat = c.assignedStat;
      if (bId == null || stat == null) continue;
      final def = workshopDefs[bId];
      if (def == null) continue; // building missing / not functional
      if (c.isKo || c.energy <= 0 || creatures.isBreeding(c.id)) continue;
      for (final role in def.workshops) {
        if (role.stat != stat) continue;
        power[role.resource] =
            (power[role.resource] ?? 0) + c.statValue(stat) * role.mult;
        break;
      }
    }
    return power;
  }

  // The settlement's current era, looked up by order (== settlement.eraIndex,
  // 1-based, no translation needed). Null only if defs haven't loaded yet or
  // the current order has no matching EraDef (shouldn't happen once seeded).
  EraDef? get currentEra {
    final order = settlement?.eraIndex;
    if (order == null) return null;
    for (final era in kEraDefs.values) {
      if (era.order == order) return era;
    }
    return null;
  }

  // Buildings currently reachable from the Main Hall via an unbroken road
  // network (edge-adjacent only) — only these actually produce/count.
  Set<String> get connectedBuildingIds =>
      GameEngine.connectedBuildingIds(buildings);

  // Cells the player can currently build on — the starting zone plus every
  // completed Building Plot's footprint.
  Set<int> get buildableRegion => GameEngine.buildableRegionCells(buildings);

  // Combines occupancy + territory rules for one building type at one spot —
  // used by the map's ghost preview as well as placeBuilding/moveBuilding.
  bool isPlacementValid(String typeId, int x, int y, {String? excludeId}) {
    final def = kBuildingDefs[typeId];
    if (def == null) return false;
    if (!_isAreaFreeImpl(x, y, def.gridW, def.gridH, excludeId: excludeId)) {
      return false;
    }
    return def.isBuildPlot
        ? GameEngine.touchesBuildableRegion(
            x,
            y,
            def.gridW,
            def.gridH,
            buildings,
          )
        : GameEngine.isAreaBuildable(x, y, def.gridW, def.gridH, buildings);
  }

  // ── Build slot helpers ────────────────────────────────────
  int get maxBuildSlots {
    final tb = techBonusTotals(unlockedTechs);
    return kBaseBuildSlots + tb.buildSlots;
  }

  int get maxQueueSlots {
    final tb = techBonusTotals(unlockedTechs);
    return kBaseQueueSlots +
        tb.queueSlots +
        GameEngine.buildingsQueueSlotsBonusTotal(buildings);
  }

  // Settlement-wide construction-speed % on top of the creature-driven
  // construction power (tech + era + build-speed buildings) — the same
  // multiplier tick() applies. 1.0 = no bonus.
  double get buildSpeedMultiplier {
    final tb = techBonusTotals(unlockedTechs);
    final eb = eraBonusTotals(settlement?.eraIndex ?? 1);
    return 1.0 +
        tb.buildSpeed +
        eb.buildSpeed +
        GameEngine.buildingsBuildSpeedBonusTotal(buildings);
  }

  // Research now advances at a real rate (creatures stationed in research
  // roles), so a tech simply needs its own researchSeconds accrued at
  // [researchRatePerHour] — no more flat % reduction.
  double effectiveResearchSeconds(TechDef def) => def.researchSeconds;

  // Research-seconds credited per hour — the sum of research workers' output,
  // energy-gated. Zero researchers = research never finishes.
  double get researchRatePerHour => workshopPower()[WorkshopRole.kResearch] ?? 0;

  // Build-seconds of construction progress credited per hour, before the
  // buildSpeedMultiplier % and /activeCount divisor — the creature-driven
  // construction power, exposed so UI countdowns match tick() exactly.
  double get buildRatePerHour =>
      (workshopPower()[WorkshopRole.kConstruction] ?? 0) * buildSpeedMultiplier;

  int get activeConstructionCount =>
      buildings.where((b) => !b.isComplete && !b.isQueued).length;

  int get queuedConstructionCount =>
      buildings.where((b) => !b.isComplete && b.isQueued).length;

  // ── Game tick ─────────────────────────────────────────────
  void _applyTick(DateTime now) {
    if (energy == null || resources == null || settlement == null) return;
    final tb = techBonusTotals(unlockedTechs);
    final eb = eraBonusTotals(settlement!.eraIndex);
    final result = GameEngine.tick(
      energy!,
      resources!,
      buildings,
      now,
      workshopPower: workshopPower(),
      creatureCount: CreaturesController().creatures.length,
      techWood: tb.wood + eb.wood,
      techStone: tb.stone + eb.stone,
      techGoods:
          tb.food + eb.food, // food tech bonus now applies to goods production
      techAll: tb.all + eb.all,
      techBuildSpeed: tb.buildSpeed + eb.buildSpeed,
      activeResearchId: settlement!.activeResearchId,
      researchSecondsBuilt: settlement!.researchSecondsBuilt,
    );
    energy = result.energy;
    resources = result.resources;
    buildings = result.buildings;

    if (settlement!.activeResearchId != null) {
      if (result.researchComplete) {
        final completedId = settlement!.activeResearchId!;
        unlockedTechs = {...unlockedTechs, completedId};
        _pendingUnlockedTechId = completedId;
        settlement = settlement!.clearActiveResearch();
      } else {
        settlement = settlement!.copyWith(
          researchSecondsBuilt: result.researchSecondsBuilt,
        );
      }
    }

    _promoteQueuedBuildings();
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
    buildings = [
      for (final b in buildings)
        if (promoteIds.contains(b.id)) b.copyWith(isQueued: false) else b,
    ];
  }

  // ── Persist to Supabase ───────────────────────────────────
  Future<void> _persist() async {
    if (resources == null || energy == null || settlement == null) return;
    try {
      await Future.wait([
        _svc.saveResources(resources!),
        _svc.saveEnergy(energy!),
        _svc.saveBuildings(buildings),
        _svc.saveSettlement(settlement!),
      ]);
      // Retried every cycle until it succeeds — safe even if unlockTech was
      // already written once (loadResearch dedupes via a Set on load).
      if (_pendingUnlockedTechId != null) {
        await _svc.unlockTech(settlement!.id, _pendingUnlockedTechId!);
        _pendingUnlockedTechId = null;
      }
    } catch (e, st) {
      // Log only — don't overwrite the main error field, which would replace the UI.
      debugPrint('[SettlementController] _persist FAILED: $e\n$st');
    }
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> addSteps(int steps) async {
    if (energy == null) return;
    _applyTick(DateTime.now().toUtc());
    energy = GameEngine.addSteps(energy!, steps);
    // NB: step logging removed — the `step_logs` table was append-only and
    // never read anywhere, so it only ever grew and ate Supabase storage.
    await _svc.saveEnergy(energy!);
    notifyListeners();
  }

  Future<void> addBp(int amount) async {
    final userId = supabase.auth.currentUser!.id;
    bp = await _svc.addBp(userId, amount);
    level = SettlementService.bpToLevel(bp);
    notifyListeners();
  }

  // How many creatures currently fill a given work role of a building — used
  // by the assignment UI to show "N/slots" and to gate new assignments.
  int workshopOccupancy(String buildingId, CreatureStat stat) {
    return CreaturesController().creatures.where((c) =>
        c.assignedBuildingId == buildingId && c.assignedStat == stat).length;
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
    final def = kBuildingDefs[placed.buildingTypeId];
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
        .where((c) =>
            c.id != creatureId &&
            c.assignedBuildingId == buildingId &&
            c.assignedStat == stat)
        .length;
    if (occupied >= role.slots) return 'All slots for this role are full';

    _applyTick(DateTime.now().toUtc());
    await creatures.setAssignment(creature, buildingId, stat);
    notifyListeners();
    return null;
  }

  // Starts a research — no queue, so only one can ever be active. BP is
  // deducted immediately (same moment resources are deducted for a building),
  // and the tech unlocks once enough researchSpeed-driven progress accrues
  // (see GameEngine.tick). Cannot be cancelled once started.
  Future<String?> startResearch(String techId) async {
    if (settlement == null) return 'Not loaded';
    final def = kTechDefs[techId];
    if (def == null) return 'Unknown technology';
    if (unlockedTechs.contains(techId)) return 'Already researched';
    if (def.eraId != null && def.eraId != currentEra?.id) {
      return 'Not available in the current era';
    }
    if (def.prerequisites.any((p) => !unlockedTechs.contains(p))) {
      return 'Prerequisites not yet researched';
    }
    if (settlement!.activeResearchId != null) {
      final activeName =
          kTechDefs[settlement!.activeResearchId]?.name ??
          settlement!.activeResearchId;
      return 'Research slot busy — finish $activeName first';
    }
    if (bp < def.bpCost) {
      return 'Not enough BP (need ${def.bpCost}, have $bp)';
    }

    final userId = supabase.auth.currentUser!.id;
    bp = await _svc.addBp(userId, -def.bpCost);
    level = SettlementService.bpToLevel(bp);
    _applyTick(DateTime.now().toUtc());
    settlement = settlement!.copyWith(
      activeResearchId: techId,
      researchSecondsBuilt: 0,
    );
    await _svc.saveSettlement(settlement!);
    notifyListeners();
    return null;
  }

  Future<String?> placeBuilding(String typeId, int x, int y) async {
    if (settlement == null || resources == null) return 'Not loaded';
    final def = kBuildingDefs[typeId];
    if (def == null) return 'Unknown building';

    if (def.eraIds.isNotEmpty && !def.eraIds.contains(currentEra?.id)) {
      return 'Not available in the current era';
    }
    if (def.requiredTechId != null &&
        !unlockedTechs.contains(def.requiredTechId)) {
      return 'Requires technology: ${kTechDefs[def.requiredTechId!]?.name ?? def.requiredTechId}';
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
    if (!def.canAfford(resources!.asMap)) {
      return 'Not enough resources';
    }
    if (!_isAreaFree(x, y, def.gridW, def.gridH)) {
      return 'Space is occupied';
    }
    if (def.isBuildPlot) {
      if (!GameEngine.touchesBuildableRegion(
        x,
        y,
        def.gridW,
        def.gridH,
        buildings,
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
    );
    buildings = [...buildings, placed];

    await _svc.saveResources(resources!);
    notifyListeners();
    return null;
  }

  // Advances to the next EraDef by `order`. Gated on every tech of the
  // CURRENT era being researched (only then is "the current era's tree is
  // done" well-defined — see TechDef.eraId), then the next era's
  // advancementCost. Applies the next era's one-time grantResources
  // ('bp' is special-cased — it lives on the profile via addBp, not
  // ResourceModel) — its permanent bonus effects take effect automatically
  // once eraIndex advances, via eraBonusTotals (era_definitions.dart).
  Future<String?> advanceEra() async {
    if (settlement == null || resources == null) return 'Not loaded';
    final currentOrder = settlement!.eraIndex;
    EraDef? nextEra;
    for (final era in kEraDefs.values) {
      if (era.order == currentOrder + 1) nextEra = era;
    }
    if (nextEra == null) return 'No further era defined yet';

    final current = currentEra;
    if (current != null) {
      final required = kTechDefs.values.where((t) => t.eraId == current.id);
      if (!required.every((t) => unlockedTechs.contains(t.id))) {
        return 'Research all ${current.name} technologies first';
      }
    }
    for (final e in nextEra.advancementCost.entries) {
      if ((resources!.asMap[e.key] ?? 0) < e.value) {
        return 'Not enough ${e.key}';
      }
    }

    _applyTick(DateTime.now().toUtc());
    resources = resources!.deduct(nextEra.advancementCost);
    final grants = Map<String, double>.of(nextEra.grantResources)..remove('bp');
    if (grants.isNotEmpty) resources = resources!.grant(grants);
    // Kept in lockstep for backward-compat display only — eraIds/gating no
    // longer read mainBuildingLevel (see availableBuildings/placeBuilding).
    settlement = settlement!.copyWith(
      eraIndex: nextEra.order,
      mainBuildingLevel: settlement!.mainBuildingLevel + 1,
    );

    await Future.wait([
      _svc.saveResources(resources!),
      _svc.saveSettlement(settlement!),
    ]);
    final bpGrant = nextEra.grantResources['bp'];
    if (bpGrant != null && bpGrant > 0) await addBp(bpGrant.round());
    notifyListeners();
    return null;
  }

  Future<String?> deleteBuilding(String buildingId) async {
    final idx = buildings.indexWhere((b) => b.id == buildingId);
    if (idx < 0) return 'Building not found';

    // Block demolition if it would leave the settlement unable to shelter the
    // creatures it already owns (demolishing housing shrinks capacity; every
    // owned creature needs a slot). Non-housing buildings never trip this.
    final remaining = [...buildings]..removeAt(idx);
    final remainingCapacity = resources == null
        ? 0
        : GameEngine.housingCapacity(remaining, resources!.goods);
    if (remainingCapacity < housingUsed) {
      return 'Not enough housing left for your creatures — release or rehouse '
          'some first';
    }

    buildings = remaining;
    _promoteQueuedBuildings();
    // Pull any workers off the demolished building so they don't stay stuck
    // pointing at a building that no longer exists.
    await CreaturesController().unassignAllFrom(buildingId);
    notifyListeners();
    await _svc.deleteBuilding(buildingId);
    return null;
  }

  Future<String?> moveBuilding(String buildingId, int newX, int newY) async {
    final idx = buildings.indexWhere((b) => b.id == buildingId);
    if (idx < 0) return 'Building not found';
    final b = buildings[idx];
    final def = kBuildingDefs[b.buildingTypeId];
    if (def == null) return 'Unknown building type';

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

    buildings = [
      for (final existing in buildings)
        if (existing.id == buildingId)
          existing.copyWith(gridX: newX, gridY: newY)
        else
          existing,
    ];

    notifyListeners();
    await _svc.moveBuilding(buildingId, newX, newY);
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────

  bool _isAreaFreeImpl(int x, int y, int w, int h, {String? excludeId}) {
    if (x < 0 || y < 0 || x + w > kGridCols || y + h > kGridRows) return false;
    for (final b in buildings) {
      if (b.id == excludeId) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      // Building Plots mark territory, not structures — they never block
      // other buildings from later occupying the same ground.
      if (def == null || def.isBuildPlot) continue;
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
    final tb = techBonusTotals(unlockedTechs);
    final eb = eraBonusTotals(settlement?.eraIndex ?? 1);
    return GameEngine.hourlyRates(
      energy!,
      buildings,
      workshopPower(),
      resources?.goods ?? {},
      techWood: tb.wood + eb.wood,
      techStone: tb.stone + eb.stone,
      techGoods: tb.food + eb.food,
      techAll: tb.all + eb.all,
    );
  }

  // ── Resource-tap breakdown ("where does this come from") ──
  // Groups the creature-driven output for [resourceId] by workshop building
  // type, applying the same need/tech bonuses as hourlyRates so the rows add
  // up to the header rate. For goods (fish/fur) it appends a consumption row.
  List<ProductionSource> productionSources(String resourceId) {
    final connected = connectedBuildingIds;
    final goods = resources?.goods ?? {};
    final tb = techBonusTotals(unlockedTechs);
    final eb = eraBonusTotals(settlement?.eraIndex ?? 1);

    // Bonus multiplier matching hourlyRates for this resource.
    double bonusMult = 1.0;
    if (resourceId == 'wood' || resourceId == 'stone' || resourceId == 'gold') {
      double pct = resourceId == 'wood'
          ? tb.wood + eb.wood + tb.all + eb.all
          : resourceId == 'stone'
          ? tb.stone + eb.stone + tb.all + eb.all
          : 0.0; // gold: only need bonus, additive below
      for (final b in buildings.where((b) => b.isComplete && connected.contains(b.id))) {
        final def = kBuildingDefs[b.buildingTypeId];
        if (def == null || def.needGoodId == null) continue;
        if ((goods[def.needGoodId] ?? 0) <= 0) continue;
        if (resourceId == 'wood') pct += def.needWoodBonus;
        if (resourceId == 'stone') pct += def.needStoneBonus;
        if (resourceId == 'gold') pct += def.needGoldBonus;
      }
      bonusMult = 1 + pct;
    } else {
      bonusMult = 1 + tb.food + eb.food; // goods
    }

    // Per-building-type creature output for this resource.
    final creatures = CreaturesController();
    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final b in buildings) {
      if (!b.isComplete || !connected.contains(b.id)) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      double out = 0;
      for (final role in def.workshops) {
        if (role.resource != resourceId) continue;
        for (final c in creatures.creatures) {
          if (c.assignedBuildingId != b.id || c.assignedStat != role.stat) {
            continue;
          }
          if (c.isKo || c.energy <= 0 || creatures.isBreeding(c.id)) continue;
          out += c.statValue(role.stat) * role.mult;
        }
      }
      if (out == 0) continue;
      totals[def.id] = (totals[def.id] ?? 0) + out * bonusMult;
      counts[def.id] = (counts[def.id] ?? 0) + 1;
    }

    final sources = totals.entries.map((e) {
      final def = kBuildingDefs[e.key]!;
      return ProductionSource(
        imageUrl: def.imageUrl,
        label: def.name,
        count: counts[e.key]!,
        amount: e.value,
      );
    }).toList()..sort((a, b) => b.amount.compareTo(a.amount));

    // Goods consumption row (creatures eating).
    final gDef = kGoodsDefs[resourceId];
    if (gDef != null && gDef.consumptionPerCapitaPerHour > 0 && housingUsed > 0) {
      sources.add(ProductionSource(
        emoji: '🐾',
        label: 'Creature upkeep',
        count: housingUsed,
        amount: -housingUsed * gDef.consumptionPerCapitaPerHour,
      ));
    }
    return sources;
  }

  List<ProductionSource> get housingSources =>
      GameEngine.housingSources(buildings, resources?.goods ?? {});

  // ── Workout BP ────────────────────────────────────────────
  static const kBaseWorkoutBpPerDay = 200;

  int _workoutBpToday = 0;
  String _workoutBpDate = ''; // 'YYYY-MM-DD' (local); '' until first load/save

  // Lifetime workout count and the consecutive-day streak (with the last
  // workout's local date, to know whether the streak is still alive). Both
  // persisted on the profile and updated in completeWorkout.
  int workoutsCompleted = 0;
  int workoutStreak = 0;
  String _lastWorkoutDate = '';

  // The streak only counts as "current" if the last workout was today or
  // yesterday; a longer gap has already broken it (the stored number is stale
  // until the next workout resets it).
  int get currentStreak {
    if (_lastWorkoutDate.isEmpty) return 0;
    final now = DateTime.now();
    final today = _dateKey(now);
    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));
    return (_lastWorkoutDate == today || _lastWorkoutDate == yesterday)
        ? workoutStreak
        : 0;
  }

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  int get maxWorkoutBpPerDay {
    final bonus =
        techBonusTotals(unlockedTechs).workoutBp +
        eraBonusTotals(settlement?.eraIndex ?? 1).workoutBp;
    return (kBaseWorkoutBpPerDay * (1 + bonus)).round();
  }

  int get workoutBpToday {
    _resetDailyIfNeeded();
    return _workoutBpToday;
  }

  int get workoutBpRemaining =>
      (maxWorkoutBpPerDay - workoutBpToday).clamp(0, maxWorkoutBpPerDay);

  void _resetDailyIfNeeded() {
    final today = _dateKey(DateTime.now());
    if (_workoutBpDate != today) {
      _workoutBpToday = 0;
      _workoutBpDate = today;
    }
  }

  // ── Dungeon economy (creature system) ─────────────────────
  /// Pays a cost map (dungeon entry — gold's decided spending sink).
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
    }
    return true;
  }

  /// Credits dungeon-space loot. Rewards are granted immediately per cleared
  /// space, so a failed run keeps everything earned (decided design).
  Future<void> grantResources(Map<String, double> amounts) async {
    final res = resources;
    if (res == null) return;
    resources = res.grant(amounts);
    notifyListeners();
    try {
      await _svc.saveResources(resources!);
    } catch (e) {
      debugPrint('[SettlementController] grantResources save failed: $e');
    }
  }

  Future<int> completeWorkout(int durationMinutes) async {
    _resetDailyIfNeeded();
    final now = DateTime.now();
    final today = _dateKey(now);
    final yesterday = _dateKey(now.subtract(const Duration(days: 1)));

    // Every finished workout counts (completeWorkout is only called on a real
    // finish, never on abandon), regardless of whether the daily BP cap is
    // already full. Streak: +1 if the last one was yesterday, unchanged if
    // already worked out today, otherwise it restarts at 1.
    if (_lastWorkoutDate == yesterday) {
      workoutStreak += 1;
    } else if (_lastWorkoutDate != today) {
      workoutStreak = 1;
    }
    _lastWorkoutDate = today;
    workoutsCompleted += 1;

    final remaining = workoutBpRemaining;
    final earned = remaining <= 0 ? 0 : (durationMinutes * 10).clamp(0, remaining);
    final userId = supabase.auth.currentUser!.id;
    if (earned > 0) {
      _workoutBpToday += earned;
      bp = await _svc.addBp(userId, earned);
      level = SettlementService.bpToLevel(bp);
    }
    // Persist all workout stats together (daily cap survives restarts and
    // resets only at local midnight; count/streak are lifetime).
    await _svc.saveWorkoutStats(
      userId,
      bpToday: _workoutBpToday,
      bpDate: _workoutBpDate,
      completed: workoutsCompleted,
      streak: workoutStreak,
      lastDate: _lastWorkoutDate,
    );
    notifyListeners();
    return earned;
  }

  // ── Dungeon stage progression (creature system) ───────────
  /// Called when a dungeon run clears [stage]'s boss — permanently unlocks
  /// stage+1 if it isn't already. No-op (and no write) if already unlocked.
  Future<void> unlockDungeonStage(int stage) async {
    final next = stage + 1;
    if (next <= dungeonMaxStage) return;
    dungeonMaxStage = next;
    notifyListeners();
    final userId = supabase.auth.currentUser?.id;
    if (userId != null) {
      await _svc.saveDungeonMaxStage(userId, dungeonMaxStage);
    }
  }
}
