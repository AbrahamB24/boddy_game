import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/notifications/game_notifications.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../common/events/game_events.dart';
import '../../onboarding/intro_flow.dart';
import '../../settlement/data/building_definitions.dart';
import '../../settlement/data/goods_definitions.dart';
import '../../settlement/data/item_definitions.dart';
import '../../settlement/services/crafting.dart';
import '../../settlement/services/daily_tasks.dart' show DailyTaskKind;
import '../../settlement/services/gold_economy.dart';
import '../../settlement/settlement_controller.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/saved_team.dart';
import '../models/species_def.dart';
import 'creature_defs_controller.dart';
import 'creature_service.dart';
import 'expedition_risk.dart';
import 'healing_cost.dart';
import 'saved_team_service.dart';

// Singleton holding the player's creature collection, same ChangeNotifier
// pattern as SettlementController.
class CreaturesController extends ChangeNotifier {
  static final CreaturesController _instance = CreaturesController._();
  factory CreaturesController() => _instance;
  CreaturesController._() {
    // Species/ability def edits (dev mode, realtime) change displayed stats —
    // re-notify collection listeners the same way SettlementController chains
    // GameDefsController.
    CreatureDefsController().addListener(notifyListeners);
  }

  final _svc = CreatureService();
  final _rng = math.Random();

  List<CreatureInstance> creatures = [];
  bool isLoading = false;
  bool _loadedOnce = false;

  /// Ids of creatures currently blocked by a running breeding job — kept in
  /// sync by BreedingController (which owns the jobs). Living here so team
  /// selection and release checks don't need a breeding import.
  final Set<String> breedingIds = {};

  bool isBreeding(String creatureId) => breedingIds.contains(creatureId);

  /// Ids of creatures currently out on an expedition — kept in sync by
  /// ExpeditionController (which owns the expeditions), same pattern as
  /// [breedingIds]. Living here so team-selection/availability checks don't
  /// need an expedition import.
  final Set<String> expeditionIds = {};

  bool isOnExpedition(String creatureId) => expeditionIds.contains(creatureId);

  /// Creatures free to be sent on a new expedition: not K.O., not healing, not
  /// breeding and not already away.
  ///
  /// Creatures STATIONED in a building are deliberately included. A worker is
  /// the same creature as an explorer, and forcing an un-station/re-station
  /// round trip to use one only taxed the player's patience. The building pays
  /// the real price instead: it produces nothing from that post until the
  /// creature walks back in (see [isWorkingNow]). The post itself is held —
  /// assignedBuildingId stays set — so nobody can take the slot meanwhile and
  /// the creature resumes its old job on return, with nothing to re-do.
  List<CreatureInstance> availableForExpedition() => creatures
      .where(
        (c) =>
            !c.isKo &&
            !c.isHealing &&
            !isBreeding(c.id) &&
            !isOnExpedition(c.id),
      )
      .toList();

  /// True when [c] is stationed AND actually able to man the post right now.
  ///
  /// The distinction that matters: `isAssigned` means "holds a post",
  /// `isWorkingNow` means "is producing at it" — a monster keeps its job while it
  /// is away, knocked out, mating or under treatment, and produces nothing until
  /// it walks back in.
  ///
  /// THE ONE PREDICATE, since 2026-07-30 (user: "wie kann ein Monster als idle
  /// angestellt sein? Entweder arbeitet es hier, oder ist nicht in diesem
  /// Gebäude"). There were three versions of this rule and they disagreed:
  /// this one excluded only expeditions, SettlementController's excluded K.O./
  /// mating/expedition but not treatment, and the building dialog spelled out a
  /// third union of its own. So a K.O. monster earned work XP for a job it could
  /// not do, and a monster in the Healing Hut produced fish from its bed.
  /// A PAUSED building is a shift nobody is working (user 2026-08-01): the post
  /// is still yours, the building simply is not running — so no output, and no
  /// work XP for standing in it.
  bool isWorkingNow(CreatureInstance c) =>
      c.isAssigned &&
      !isOnExpedition(c.id) &&
      !isBreeding(c.id) &&
      !c.isKo &&
      !c.isHealing &&
      !_isInPausedBuilding(c);

  bool _isInPausedBuilding(CreatureInstance c) {
    final bId = c.assignedBuildingId;
    if (bId == null) return false;
    for (final b in SettlementController().buildings) {
      if (b.id == bId) return b.isPaused;
    }
    return false;
  }

  /// True when [c]'s current post is a training role (WorkshopRole.kTraining
  /// — the Training Grounds). Resolves the placed building to its def; false
  /// whenever the chain breaks (unassigned, building gone, unknown def).
  bool isInTrainingRole(CreatureInstance c) {
    final bId = c.assignedBuildingId;
    final stat = c.assignedStat;
    if (bId == null || stat == null) return false;
    for (final b in SettlementController().buildings) {
      if (b.id != bId) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) return false;
      for (final role in def.workshops) {
        if (role.stat == stat) return role.resource == WorkshopRole.kTraining;
      }
      return false;
    }
    return false;
  }

  /// XP/h [c] earns at its current post: the training rate in a training role,
  /// else the settlement-wide WORK rate at that building's level — the same for
  /// every building that stations monsters (user 2026-07-30: "Jedes Gebäude,
  /// welches Monster «anstellt» soll EP geben. Jedes Gebäude gibt genau gleich
  /// viel EP"). 0 for a monster holding no post.
  ///
  /// THE one place the rule lives. It used to read a per-building `xp` effect,
  /// so ~40 of the ~50 buildings with work posts paid nothing at all — the
  /// effect existed on eleven era-I buildings and nowhere else. There is no
  /// per-building XP number any more; both rates come from Species-Budget → XP.
  /// The UI (building XP note, creature card) shows this same number.
  double xpRatePerHour(CreatureInstance c) {
    final bId = c.assignedBuildingId;
    if (bId == null) return 0;
    // Training FIRST: the Training Grounds produces nothing, so its wage must
    // not be undercut by the trickle every other post pays.
    if (isInTrainingRole(c)) return kTrainingXpPerHour;
    for (final b in SettlementController().buildings) {
      if (b.id != bId) continue;
      final def = kBuildingDefs[b.buildingTypeId];
      // "Stations monsters" IS having a work post — a creature can only hold a
      // post in a building that has one, and a def we cannot resolve pays
      // nothing rather than guessing.
      if (def == null || def.workshops.isEmpty) return 0;
      return workXpPerHourAt(b.level);
    }
    return 0;
  }

  CreatureInstance? byId(String id) {
    for (final c in creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// How many creatures a battle/expedition team may hold — starts at ONE and
  /// grows with LINEAR-PATH progress, not research (user 2026-07-24): the party
  /// size is a rule of how far up the numbered line of battles you are. See
  /// SettlementController.partyCap / partySizeForBattle. The old team-size techs
  /// are gone.
  int get teamSizeCap => SettlementController().partyCap;

  // ── Saved teams ─────────────────────────────────────────────
  // Named rosters the player builds once and reuses ("Steinteam"). See
  // saved_team.dart for the rationale.
  final List<SavedTeam> savedTeams = [];
  final _teamSvc = SavedTeamService();

  /// The FIGHTING rosters — what the Teams screen lists and battleTeam() reads.
  /// [savedTeams] also holds the Market's caravans since migration 0028, and a
  /// caravan has no business in the battle-team picker.
  List<SavedTeam> get battleTeams =>
      [for (final t in savedTeams) if (t.kind == TeamKind.battle) t];

  /// The Market's saved hauling parties, oldest first (the insert order).
  List<SavedTeam> get caravans =>
      [for (final t in savedTeams) if (t.kind == TeamKind.caravan) t];

  SavedTeam? get activeTeam {
    for (final t in savedTeams) {
      if (t.isActive && t.kind == TeamKind.battle) return t;
    }
    return null;
  }

  /// Creates a team and makes it active. Returns null on success, else why not.
  Future<String?> createTeam(String name, List<String> memberIds) async {
    final clean = name.trim();
    if (clean.isEmpty) return 'Give the team a name';
    if (memberIds.isEmpty) return 'Pick at least one monster';
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 'Not signed in';
    await _teamSvc.clearActive(userId);
    for (var i = 0; i < savedTeams.length; i++) {
      savedTeams[i] = savedTeams[i].copyWith(isActive: false);
    }
    savedTeams.add(
      await _teamSvc.insert(
        SavedTeam(
          id: '',
          userId: userId,
          name: clean,
          memberIds: memberIds,
          isActive: true,
        ),
      ),
    );
    notifyListeners();
    return null;
  }

  /// Saves the Market's current caravan under [name] (user 2026-07-27).
  ///
  /// NEVER active, unlike [createTeam]: "active" means "the roster battleTeam()
  /// picks", which a caravan has no equivalent of — and the DB's partial unique
  /// index is over the whole user, so an active caravan would evict the battle
  /// team from its own slot.
  Future<String?> saveCaravan(String name, List<String> memberIds) async {
    final clean = name.trim();
    if (clean.isEmpty) return 'Give the caravan a name';
    if (memberIds.isEmpty) return 'Pick at least one monster';
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 'Not signed in';
    savedTeams.add(
      await _teamSvc.insert(
        SavedTeam(
          id: '',
          userId: userId,
          name: clean,
          kind: TeamKind.caravan,
          memberIds: memberIds,
        ),
      ),
    );
    notifyListeners();
    return null;
  }

  Future<String?> renameTeam(SavedTeam team, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return 'Give the team a name';
    return _updateTeam(team.copyWith(name: clean));
  }

  Future<String?> setTeamMembers(SavedTeam team, List<String> memberIds) async {
    if (memberIds.isEmpty) return 'Pick at least one monster';
    return _updateTeam(team.copyWith(memberIds: memberIds));
  }

  Future<String?> _updateTeam(SavedTeam updated) async {
    final i = savedTeams.indexWhere((t) => t.id == updated.id);
    if (i < 0) return 'That team is gone';
    await _teamSvc.update(updated);
    savedTeams[i] = updated;
    notifyListeners();
    return null;
  }

  /// Makes [team] the one battleTeam() reads, or — with null — deactivates all
  /// of them (back to the first-N fallback).
  ///
  /// Clears every other team FIRST: `saved_teams_one_active_per_user` is a
  /// partial unique index, so two active rows is a constraint violation.
  Future<void> activateTeam(SavedTeam? team) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    await _teamSvc.clearActive(userId);
    for (var i = 0; i < savedTeams.length; i++) {
      savedTeams[i] = savedTeams[i].copyWith(isActive: false);
    }
    if (team != null) {
      final i = savedTeams.indexWhere((t) => t.id == team.id);
      if (i >= 0) {
        savedTeams[i] = savedTeams[i].copyWith(isActive: true);
        await _teamSvc.update(savedTeams[i]);
      }
    }
    notifyListeners();
  }

  Future<void> deleteTeam(SavedTeam team) async {
    await _teamSvc.delete(team.id);
    savedTeams.removeWhere((t) => t.id == team.id);
    notifyListeners();
  }

  /// Creatures that can fight right now.
  ///
  /// A creature under treatment is OUT — that wait is the whole point of
  /// healing taking time (healing_cost.dart). Without this you could heal and
  /// fight with the same monster in the same breath.
  bool _isBattleReady(CreatureInstance c) =>
      !c.isKo &&
      !c.isHealing &&
      !isBreeding(c.id) &&
      !isOnExpedition(c.id);

  /// The battle roster, capped at [size] (default: the researched team-size
  /// cap). THE single team-selection rule — collection training, dungeon entry
  /// and the tech trials all read this, so the active team propagates
  /// everywhere for free.
  ///
  /// With a team active, it picks that team's members IN THE PLAYER'S ORDER,
  /// skipping any that are hurt, busy or since released. With none active it
  /// falls back to "the first N that can fight" — which, since the collection
  /// loads ordered by caught_at, means your OLDEST monsters. That fallback is
  /// only defensible because a fresh profile has no teams yet; the moment the
  /// player saves one, intent beats catch order.
  ///
  /// A team whose members are ALL unavailable yields an empty roster rather
  /// than quietly substituting whoever is free — silently fighting a boss with
  /// the wrong monsters is worse than being told nobody can go.
  /// Every creature that could walk into a fight right now (not K.O., healing,
  /// breeding or on an expedition) — the pool the pre-battle team picker offers.
  List<CreatureInstance> get battleReadyCreatures =>
      creatures.where(_isBattleReady).toList();

  List<CreatureInstance> battleTeam({int? size}) {
    final cap = size ?? teamSizeCap;
    final team = activeTeam;
    if (team == null) {
      return creatures.where(_isBattleReady).take(cap).toList();
    }
    return team.memberIds
        .map(byId)
        .whereType<CreatureInstance>()
        .where(_isBattleReady)
        .take(cap)
        .toList();
  }

  /// Whether the settlement can shelter another creature. Captured monsters
  /// ARE the population, so a full settlement blocks catching/hatching. The
  /// very first creature (empty collection) always fits — a fresh Tribal
  /// Center provides starting capacity.
  bool get housingFull =>
      creatures.isNotEmpty && SettlementController().housingFull;

  String? get _userId => supabase.auth.currentUser?.id;

  Future<void> load({bool force = false}) async {
    if (isLoading || (_loadedOnce && !force)) return;
    final userId = _userId;
    if (userId == null) return;
    isLoading = true;
    notifyListeners();
    try {
      creatures = await _svc.loadOwn(userId);
      _loadedOnce = true;
      await _backfillGenes();
    } catch (e) {
      debugPrint('[CreaturesController] load failed: $e');
    }
    // Separate try: saved_teams is behind migration 0009, and a profile whose
    // migration hasn't run yet must still get its COLLECTION. Losing the teams
    // costs you a convenience (battleTeam falls back to first-N); losing the
    // collection would look like the game ate your monsters.
    try {
      savedTeams
        ..clear()
        ..addAll(await _teamSvc.loadOwn(userId));
    } catch (e) {
      debugPrint('[CreaturesController] saved teams unavailable: $e');
    }
    isLoading = false;
    notifyListeners();
  }

  /// One-time legacy migration: creatures saved before the 8 civilian stats
  /// existed have partial gene maps. Fill the gaps from each species curve and
  /// persist the completed rows. No-op once every creature is up to date.
  Future<void> _backfillGenes() async {
    for (final c in creatures) {
      if (!c.needsGeneBackfill) continue;
      if (c.backfillGenes(_rng)) {
        try {
          await _svc.update(c);
        } catch (e) {
          debugPrint('[CreaturesController] gene backfill persist failed: $e');
        }
      }
    }
  }

  // ── Work assignment (settlement economy) ──────────────────
  /// Sets (or clears) a creature's workshop posting and persists it. Slot/
  /// functional validation lives in SettlementController.assignCreatureToWorkshop
  /// — this just records the decision.
  Future<void> setAssignment(
    CreatureInstance creature,
    String? buildingId,
    CreatureStat? stat,
  ) async {
    creature.assignedBuildingId = buildingId;
    creature.assignedStat = stat;
    notifyListeners();
    if (buildingId != null) {
      await SettlementController().advanceIntro(IntroStep.assignWorker);
    }
    try {
      await _svc.update(creature);
    } catch (e) {
      debugPrint('[CreaturesController] setAssignment persist failed: $e');
    }
  }

  /// Clears the posting of every creature stationed in [buildingId] (called
  /// when that building is demolished so nobody stays stuck pointing at it).
  Future<void> unassignAllFrom(String buildingId) async {
    final affected =
        creatures.where((c) => c.assignedBuildingId == buildingId).toList();
    if (affected.isEmpty) return;
    for (final c in affected) {
      c.assignedBuildingId = null;
      c.assignedStat = null;
    }
    notifyListeners();
    for (final c in affected) {
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] unassign persist failed: $e');
      }
    }
  }

  /// First creature for a fresh account: level 1 (user 2026-07-24 — the early
  /// fights scale down to meet it), random gender, freshly Gaussian-sampled
  /// genes. Only allowed while the collection is empty (the UI gates this too),
  /// and only for a starter species — see [starterChoices].
  Future<CreatureInstance?> adoptStarter(SpeciesDef species) async {
    final userId = _userId;
    if (userId == null || creatures.isNotEmpty) return null;
    // Enforced here and not just in the picker: this is the write path, and the
    // starter must be one of the three fire/water/plant epics.
    if (!isStarterSpecies(species)) return null;
    final starter = CreatureInstance(
      id: '',
      userId: userId,
      speciesId: species.id,
      gender: _rng.nextBool() ? CreatureGender.male : CreatureGender.female,
      level: 1,
      statBase: CreatureInstance.rollBaseGenes(species, _rng),
      statSlope: CreatureInstance.rollSlopeGenes(species, _rng),
    );
    try {
      final created = await _svc.insert(starter);
      creatures.add(created);
      notifyListeners();
      await SettlementController().advanceIntro(IntroStep.pickStarter);
      return created;
    } catch (e) {
      debugPrint('[CreaturesController] adoptStarter failed: $e');
      return null;
    }
  }

  /// Evolves to the next stage. Free — see the note inside.
  /// Per the balance spec, evolution bumps only the individual's stat BASE
  /// (by the species' own mean delta between stages) — the growth slope
  /// never changes, and the bonus is added to whatever this individual
  /// already rolled, never re-rolled. Returns null on success or a
  /// user-facing error message.
  Future<String?> evolve(CreatureInstance creature) async {
    final species = creature.species;
    if (species == null || !creature.hasNextStage) {
      return 'Already at the final stage.';
    }
    // THE LEVEL IS THE WHOLE GATE (user 2026-07-26: "evolution ist immer
    // freigeschalten sobald das level erreicht wurde gibt es die evolution").
    // There was a second gate here — a creature_evolution_1/2 feature earned on
    // the path — so a monster could sit at its evolution level for a whole
    // region with a greyed-out button and no way to tell what it was waiting
    // for. Reaching the level IS the achievement.
    if (!creature.canEvolve) {
      return 'Requires Level ${species.evoLevelFrom(creature.stage)}.';
    }
    try {
      // Free, and deliberately manual: evolution is the REWARD for the levels
      // you already put in, not a purchase (user decision, 2026-07-16). It
      // still has to be claimed by hand — the moment is the point.
      final fromStage = creature.stage;
      for (final stat in CreatureStat.values) {
        final bonus = species.statCurve(stat).evolutionBonus(fromStage);
        creature.statBase[stat] = (creature.statBase[stat] ?? 0) + bonus;
      }
      creature.stage += 1;
      // Evolution is a moment of triumph — refill HP to the (now higher) max
      // instead of leaving the old, smaller value.
      creature.currentHp = -1;
      await _svc.update(creature);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Evolution failed: $e';
    }
  }

  Future<void> rename(CreatureInstance creature, String? nickname) async {
    creature.nickname = (nickname?.trim().isEmpty ?? true)
        ? null
        : nickname!.trim();
    notifyListeners();
    try {
      await _svc.update(creature);
    } catch (e) {
      debugPrint('[CreaturesController] rename failed: $e');
    }
  }

  /// Returns a user-facing error instead of releasing when the creature is
  /// locked in a breeding job (its egg would silently die via FK cascade).
  Future<String?> release(CreatureInstance creature) async {
    if (isBreeding(creature.id)) {
      return 'This creature is currently breeding — cancel breeding first.';
    }
    creatures.removeWhere((c) => c.id == creature.id);
    notifyListeners();
    try {
      await _svc.delete(creature.id);
    } catch (e) {
      debugPrint('[CreaturesController] release failed: $e');
    }
    return null;
  }

  /// The era's level cap (user 2026-07-22) — every XP grant in this controller
  /// goes through it, so era progression has ONE seam.
  ///
  /// The era XP MULTIPLIER that used to sit beside it is gone (user
  /// 2026-07-26): a source now pays exactly what it says, in every era.
  int get eraLevelCap =>
      creatureLevelCap(SettlementController().currentEra?.order ?? 1);

  /// Dev-mode helper: grant XP and persist.
  Future<void> devGainXp(CreatureInstance creature, int amount) async {
    creature.gainXp(amount, levelCap: eraLevelCap);
    notifyListeners();
    try {
      await _svc.update(creature);
    } catch (e) {
      debugPrint('[CreaturesController] devGainXp failed: $e');
    }
  }

  /// DEV: pushes [creature] straight to its next form (user 2026-08-01: "gib
  /// mir bei den monsterdetailscrrens einen devbutton, wobmit ich direkt eine
  /// evolution auslösen kann (d.h level bis dort steigern unabhängig von der
  /// ära)").
  ///
  /// It raises the LEVEL to the evolution threshold and then evolves, rather
  /// than jumping the stage on its own: a monster that is stage 2 at level 4
  /// has stats no real creature could have, and every balance reading taken off
  /// it afterwards would be fiction.
  ///
  /// The era cap is deliberately ignored — that is the whole request. The cap
  /// exists so a player cannot outgrow the chapter they are in; a dev checking
  /// what the third form looks like is not that player. The level stays where
  /// this puts it, so the monster is a legitimate over-levelled one rather than
  /// a broken one.
  Future<String?> devEvolve(CreatureInstance creature) async {
    final species = creature.species;
    if (species == null) return 'Unknown species.';
    if (!creature.hasNextStage) return 'Already at the final stage.';
    final need = species.evoLevelFrom(creature.stage);
    if (creature.level < need) {
      creature.level = need;
      creature.xp = 0;
      // The new form is met at full health, like any evolution.
      creature.currentHp = -1;
    }
    return evolve(creature);
  }

  /// Adds a successfully caught wild to the collection. The catch keeps the
  /// wild's exact identity: species, level, evolution stage, gender and its
  /// exact sampled genes. Joins with full pools (fresh start in your team).
  /// [force] bypasses the housing cap — used for the region-boss legendary,
  /// which is awarded ceremonially and must never be lost to a full house.
  Future<CreatureInstance?> captureWild(Combatant wild, {bool force = false}) async {
    final userId = _userId;
    final speciesId = wild.speciesId;
    if (userId == null ||
        speciesId == null ||
        wild.wildStatBase == null ||
        wild.wildStatSlope == null) {
      return null;
    }
    // Defensive capacity guard (the catch UI checks first, but never exceed
    // housing even if it doesn't) — skipped for a forced ceremonial award.
    if (!force && housingFull) return null;
    final caught = CreatureInstance(
      id: '',
      userId: userId,
      speciesId: speciesId,
      gender: wild.gender,
      level: wild.level,
      stage: wild.stage,
      statBase: Map.of(wild.wildStatBase!),
      statSlope: Map.of(wild.wildStatSlope!),
    );
    try {
      final created = await _svc.insert(caught);
      creatures.add(created);
      // Daily-task hook: a monster joined the roster.
      SettlementController()
          .reportDailyProgress(DailyTaskKind.catchMonsters);
      notifyListeners();
      return created;
    } catch (e) {
      debugPrint('[CreaturesController] captureWild failed: $e');
      return null;
    }
  }

  /// Heal-space effect (dungeon): revives K.O. creatures at 50% HP and heals
  /// the rest by 60% of max — capped at maxHp. Persisted immediately (the HP
  /// pool is persistent by design).
  Future<void> healTeam(List<CreatureInstance> team) async {
    for (final c in team) {
      c.hp = c.isKo
          ? (c.maxHp * 0.5).round()
          : math.min(c.maxHp, c.hp + (c.maxHp * 0.6).round());
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] healTeam persist failed: $e');
      }
    }
    notifyListeners();
  }

  // ── Passive XP (stationed creatures) ──────────────────────
  // Fractional XP per creature id, accrued by the settlement tick and flushed
  // when it reaches a whole point. Same fractional-accrual pattern the
  // settlement tick uses: the game ticks in fractions of an hour, and rounding
  // each tick to an int would floor a slow rate to zero forever.
  final Map<String, double> _xpFraction = {};

  /// Called by the settlement tick with its ENERGY-GATED hours, so a
  /// settlement that ran out of energy trains nobody — same rule as every
  /// other passive rate.
  ///
  /// Returns the level-up messages to report (empty if none). The caller owns
  /// telling the player; this just does the maths.
  Future<List<String>> accruePassiveXp(double effectiveHours) async {
    if (effectiveHours <= 0) return const [];
    final messages = <String>[];

    // isWorkingNow, not isAssigned: passive XP is pay for doing the job, and a
    // creature away on an expedition isn't doing it. It earns on the trip
    // instead.
    for (final c in creatures.where(isWorkingNow)) {
      // The rate is what the building (or the training post) says it is — no
      // era multiplier any more. The era cap still stops the accrual.
      final rate = xpRatePerHour(c);
      if (rate <= 0) continue; // a post with no `xp` effect pays nothing
      final total = (_xpFraction[c.id] ?? 0) + rate * effectiveHours;
      final whole = total.floor();
      _xpFraction[c.id] = total - whole;
      if (whole < 1) continue;

      final levels = c.gainXp(whole, levelCap: eraLevelCap);
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] passive xp persist failed: $e');
      }
      if (levels > 0) {
        messages.add(
          '${c.displayName} reached Lv ${c.level}'
          '${levels > 1 ? ' (+$levels levels)' : ''}',
        );
      }
    }
    if (messages.isNotEmpty) notifyListeners();
    return messages;
  }

  /// The creatures a heal would actually do something for.
  List<CreatureInstance> get hurtCreatures =>
      creatures.where((c) => c.hp < c.maxHp).toList();

  /// "🐟 4 · 🦫 4" — names the goods rather than saying "resources", so a
  /// refusal tells the player what to go and gather.
  static String _costLabel(Map<String, double> cost) => cost.entries
      .map((e) => '${kGoodsDefs[e.key]?.emoji ?? e.key} ${e.value.toInt()}')
      .join(' · ');

  /// What healing every hurt creature costs right now, in the current era's
  /// goods. Empty when nobody needs it. See healing_cost.dart.
  Map<String, double> get healAllCost {
    final settlement = SettlementController();
    // Quotes the creatures healAll will ACTUALLY charge for — anyone already
    // in treatment is not billed again, and the button used to over-quote by
    // including them.
    return healCost(
      hurtCreatures.where((c) => !c.isHealing).toList(),
      settlement.resources?.asMap ?? const {},
    );
  }

  /// Creatures currently under treatment.
  List<CreatureInstance> get healingCreatures =>
      creatures.where((c) => c.isHealing).toList();

  // ── The queue (user 2026-07-27) ───────────────────────────
  // "Treat all sollte nicht funktionieren, da ich aktuell keine Warteschlange
  // habe. Diese soll direkt eingebaut werden."
  //
  // The hut treats [SettlementController.healCapacity] monsters at a time. With
  // the slots full, healAll simply REFUSED — and with one slot free it treated
  // the worst and left the rest hurt with nothing to say they were waiting.
  // Now the overflow stands in line: queued monsters are pulled in, oldest
  // first, as slots free ([_autoStartQueuedHeals]), and each pays its own bill
  // at the moment it actually starts.

  /// Who is in line, in the order they joined it. Ties (a "treat all" queues
  /// everyone in the same instant) break towards the most urgent.
  List<CreatureInstance> get healQueue {
    final list = creatures.where((c) => c.isQueuedForHealing).toList();
    list.sort((a, b) {
      final byTime = a.healQueuedAt!.compareTo(b.healQueuedAt!);
      return byTime != 0 ? byTime : _healPriority(a, b);
    });
    return list;
  }

  /// Room left in the line, or null when the hut has no `healQueue` effect
  /// authored (an unlimited line — see [SettlementController.healQueueCapacity]).
  int? get freeHealQueueSlots {
    final cap = SettlementController().healQueueCapacity;
    return cap == null ? null : cap - healQueue.length;
  }

  /// Sends [c] to the hut: STRAIGHT into treatment when a slot is free, into the
  /// line only when there is none.
  ///
  /// It used to go through the line either way (user 2026-07-30: "healing hut,
  /// wenn treating noch frei ist, direkt dorhin verschieben und nicht über die in
  /// line") — `healQueuedAt` was set, PERSISTED, and the UI notified before the
  /// auto-start pulled it back out again. So a monster with a free slot waiting
  /// for it still appeared under "In line" for the length of a database round
  /// trip, and the row it was about to leave is the one you were looking at.
  /// Two writes for one decision, and a state the game was never in.
  Future<String?> queueForHealing(CreatureInstance c) async {
    if (c.isHealing) return '${c.displayName} is already being treated.';
    if (c.hp >= c.maxHp) return '${c.displayName} is at full health.';
    // A free slot means it is not queueing at all — it is being treated. Any
    // refusal (no energy, cannot pay) surfaces NOW instead of parking it in a
    // line it was never meant to stand in.
    final slots = _freeTreatmentSlots;
    if (c.healQueuedAt == null && (slots == null || slots > 0)) {
      return _startTreatment([c]);
    }
    if (c.healQueuedAt == null) {
      // The waiting room is a building effect too (user 2026-07-27), so the
      // line has an end. Checked only for someone JOINING it: a monster already
      // standing there is never pushed out by a shrinking cap. (The free-slot
      // case never reaches here — it went straight into treatment above.)
      final freeQueue = freeHealQueueSlots;
      if (freeQueue != null && freeQueue <= 0) {
        return 'The waiting room is full — treat somebody first.';
      }
      c.healQueuedAt = DateTime.now();
      await _persistQuietly(c);
      notifyListeners();
    }
    // Still worth a pass: a slot may have freed while this monster was being
    // written, and an already-queued one (a second tap) belongs in it.
    await _autoStartQueuedHeals();
    return null;
  }

  /// Free treatment slots, or null when the hut is uncapped.
  int? get _freeTreatmentSlots {
    final cap = SettlementController().healCapacity;
    return cap == null ? null : cap - healingCreatures.length;
  }

  /// Takes [c] out of the line. No refund: nothing was billed — a queued
  /// monster pays only when its treatment actually starts.
  Future<void> unqueueHealing(CreatureInstance c) async {
    if (c.healQueuedAt == null) return;
    c.healQueuedAt = null;
    await _persistQuietly(c);
    notifyListeners();
  }

  Future<void> _persistQuietly(CreatureInstance c) async {
    try {
      await _svc.update(c);
    } catch (e) {
      debugPrint('[CreaturesController] heal queue persist failed: $e');
    }
  }

  /// Sends every hurt creature to the Healing Hut. Returns null on success or
  /// a user-facing error.
  ///
  /// COSTS GOODS **AND TIME** (user design 2026-07-16). This used to be free
  /// and instant — one tap restored the whole collection, which quietly made
  /// every HP cost in the game meaningless. Goods alone weren't enough either:
  /// they're easy to gather, so a wipe cost a trip rather than a decision.
  /// The WAIT is what makes retreating at 30% different from pushing on and
  /// fainting (see healing_cost.dart's healDuration).
  ///
  /// Treatment runs per creature and in PARALLEL — a scratched monster is back
  /// in minutes while a K.O.'d one is out for the best part of an hour.
  ///
  /// [free] is the dev instant-heal: no cost, no wait.
  /// QUEUES every hurt monster (user 2026-07-27). Whoever fits goes straight
  /// into treatment; the rest wait in line and are pulled in as slots free.
  ///
  /// It used to refuse outright with the slots full — "The Healing Hut is full
  /// — wait for a treatment to finish" — which made the button useless in
  /// exactly the situation it exists for: you just lost a fight and everyone is
  /// hurt. With a line to stand in, it always has somewhere to put them.
  Future<String?> healAll({bool free = false}) async {
    final hurt = hurtCreatures.where((c) => !c.isHealing).toList();
    if (hurt.isEmpty) {
      return healingCreatures.isEmpty
          ? 'Nobody needs healing.'
          : 'They are already being treated.';
    }
    // The dev free-heal and the tutorial are instant and uncapped — no line to
    // join, so they keep going straight through.
    if (free || SettlementController().introStep.isActive) {
      return _startTreatment(hurt, free: free);
    }
    // Worst off first, so a line with room for four takes the four that need it
    // most rather than whoever the roster happens to list first.
    final order = List.of(hurt)..sort(_healPriority);
    // WHOEVER FITS IS TREATED, not queued (user 2026-07-30) — the same rule
    // [queueForHealing] follows for one monster. Billed ONE AT A TIME on purpose:
    // a purse that covers three of five treats three, which a single combined
    // bill would have turned into treating nobody.
    String? treatmentError;
    for (final c in order) {
      if (c.healQueuedAt != null) continue;
      final slots = _freeTreatmentSlots;
      if (slots != null && slots <= 0) break;
      final err = await _startTreatment([c]);
      if (err != null) {
        // No energy, or the goods ran out mid-way. Stop treating and let the
        // rest queue: they pay when their slot comes up anyway.
        treatmentError = err;
        break;
      }
    }
    // The overflow stands in line.
    final now = DateTime.now();
    var queued = 0;
    var refused = 0;
    for (final c in order) {
      if (c.healQueuedAt != null || c.isHealing) continue;
      final freeQueue = freeHealQueueSlots;
      if (freeQueue != null && freeQueue - queued <= 0) {
        refused++;
        continue;
      }
      c.healQueuedAt = now;
      queued++;
      await _persistQuietly(c);
    }
    notifyListeners();
    await _autoStartQueuedHeals();
    // Never silently drop somebody: if the treatment stopped or the waiting room
    // filled up, say so.
    if (treatmentError != null && queued == 0) return treatmentError;
    return refused == 0
        ? null
        : 'The waiting room only took ${hurt.length - refused} of them — '
              '$refused still need treating.';
  }

  /// Sends ONE monster to the hut (user 2026-07-27: "ich will alle verletzten
  /// Monster angezeigt bekommen und einzelne heilen können").
  ///
  /// Every rule [healAll] applies applies here too — it shares its body — so a
  /// single heal cannot slip past the energy check, the concurrent-treatment
  /// cap or the bill. Which one you treat first is now a real decision: goods
  /// are finite and the hut only holds so many at once.
  Future<String?> healOne(CreatureInstance c, {bool free = false}) async {
    if (c.isHealing) return '${c.displayName} is already being treated.';
    if (c.hp >= c.maxHp) return '${c.displayName} is at full health.';
    return _startTreatment([c], free: free);
  }

  /// The one body behind [healAll] and [healOne]: bill [hurt], start their
  /// timers, persist. [hurt] must be non-empty and free of anyone already in
  /// treatment.
  Future<String?> _startTreatment(
    List<CreatureInstance> requested, {
    bool free = false,
  }) async {
    var hurt = requested;
    final settlement = SettlementController();
    final intro = settlement.introStep.isActive;

    // NOTHING RUNS ON AN EMPTY TANK (user 2026-07-27) — treatment included.
    // The dev free-heal and the scripted tutorial heal are exempt: neither is
    // the settlement working, and blocking the intro would dead-end it.
    if (!free && !intro && !settlement.hasEnergy) {
      return SettlementController.kNoEnergyMessage;
    }

    // Concurrent-heal cap from the Healing Hut's per-level `healSlots` effect
    // (user 2026-07-25). null = no building authored one → unlimited (the old
    // behaviour). The dev free-heal and the tutorial are INSTANT, so they
    // occupy no slot and ignore the cap. Any overflow stays hurt and is pulled
    // into treatment automatically as slots free (see _autoStartQueuedHeals).
    if (!free && !intro) {
      final cap = settlement.healCapacity;
      if (cap != null) {
        final freeSlots = cap - healingCreatures.length;
        if (freeSlots <= 0) {
          return 'The Healing Hut is full — wait for a treatment to finish.';
        }
        if (hurt.length > freeSlots) {
          hurt = (List.of(hurt)..sort(_healPriority)).take(freeSlots).toList();
        }
      }
    }

    // Buildings can grant per-era `heal` effects that cut the cost and/or time.
    final costMult = 1 - settlement.healReduction('cost');
    final speedMult = 1 - settlement.healReduction('speed');
    if (!free) {
      final cost = healCost(
        hurt,
        settlement.resources?.asMap ?? const {},
        costMult: costMult,
      );
      if (!await settlement.spendResources(cost)) {
        return 'Not enough ${_costLabel(cost)} to treat them.';
      }
    }

    // Tutorial: costed but INSTANT (user script 2026-07-17) — the K.O.'d
    // starter is a scripted state, and making the very next step "wait out a
    // timer" would teach patience instead of the mechanic. The real
    // treatment time starts applying the moment the tutorial ends. (`intro` is
    // computed above, where it also exempts the tutorial from the heal cap.)
    final now = DateTime.now();
    for (final c in hurt) {
      if (free || intro) {
        _finishHeal(c);
      } else {
        c.healingUntil = now.add(healDuration(c) * speedMult);
        // A REAL deadline (unlike crafting/construction, which accrue seconds and
        // whose finish time moves with staffing), so it can be promised (user
        // 2026-07-30).
        unawaited(GameNotifications.schedule(
          kind: NotifyKind.healing,
          key: c.id,
          at: c.healingUntil!,
          title: '🩺 Patched up',
          body: '${c.displayName} is out of the Healing Hut.',
        ));
      }
      // It is in the hut now, not in the line — the two states are exclusive,
      // and a stale queue entry would put it back in the queue list beside its
      // own treatment card.
      c.healQueuedAt = null;
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] healAll persist failed: $e');
      }
    }
    notifyListeners();
    await settlement.advanceIntro(IntroStep.healStarter);
    return null;
  }

  void _finishHeal(CreatureInstance c) {
    unawaited(GameNotifications.cancel(NotifyKind.healing, c.id));
    c.currentHp = -1;
    c.healingUntil = null;
  }

  /// Treatment order when a heal cap forces a choice: the K.O.'d go first, then
  /// whoever is missing the most HP — the open slots go to the most urgent.
  static int _healPriority(CreatureInstance a, CreatureInstance b) {
    if (a.isKo != b.isKo) return a.isKo ? -1 : 1;
    return (b.maxHp - b.hp).compareTo(a.maxHp - a.hp);
  }

  /// Pulls the QUEUE into treatment up to the Healing Hut's concurrent-heal
  /// capacity (user 2026-07-25) — called after a treatment finishes and after
  /// anything joins the line, so a capped hut works through the injured over
  /// time instead of stranding the overflow.
  ///
  /// It used to take any hurt creature, which meant everybody was implicitly in
  /// line and got billed the moment a slot opened, whether the player had asked
  /// for it or not. Since migration 0029 it reads the ACTUAL queue
  /// ([healQueue]) — you choose who stands in it, in what order.
  ///
  /// Best-effort billing: each is charged its own heal cost as it starts, and
  /// one the settlement can't afford yet KEEPS ITS PLACE and is retried on the
  /// next resolve.
  ///
  /// With no cap authored the hut is unlimited, so anything queued starts at
  /// once — the line simply never has anyone standing in it.

  /// Drops anyone standing beyond the waiting room's capacity back out of the
  /// line (user 2026-07-27: "in line 3/0 sollte nicht möglich sein").
  ///
  /// A queue longer than its cap is not a display bug, it is a real state the
  /// rules let happen: the line was joined while it was still unlimited (before
  /// the `healQueue` effect existed on the hut), and then a cap appeared — an
  /// authored 0, a levelled-down hut, a def edited in Dev Mode. [queueForHealing]
  /// only ever checks the cap for somebody JOINING, so nothing pushed the
  /// leftovers out again.
  ///
  /// Trimmed from the BACK, never the front: the ones who have waited longest
  /// keep their place. Nothing is refunded because nothing was billed — a queued
  /// monster pays only when its treatment actually starts.
  Future<void> _enforceHealQueueCap() async {
    final cap = SettlementController().healQueueCapacity;
    if (cap == null) return; // unlimited line — nothing to enforce
    final line = healQueue;
    if (line.length <= cap) return;
    var changed = false;
    for (final c in line.skip(cap)) {
      c.healQueuedAt = null;
      await _persistQuietly(c);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  Future<void> _autoStartQueuedHeals() async {
    final settlement = SettlementController();
    if (settlement.introStep.isActive) return;
    final waiting = healQueue;
    final cap = settlement.healCapacity;
    var free = cap == null ? waiting.length : cap - healingCreatures.length;
    if (waiting.isEmpty || free <= 0) {
      // Nothing to admit, but the line itself may still be over its capacity.
      await _enforceHealQueueCap();
      return;
    }

    // No settlement era here on purpose: each monster is billed in the goods of
    // ITS OWN era (user 2026-07-26) — see healCost.
    final costMult = 1 - settlement.healReduction('cost');
    final speedMult = 1 - settlement.healReduction('speed');
    final now = DateTime.now();
    var started = false;
    for (final c in waiting) {
      if (free <= 0) break;
      final cost = healCost(
        [c],
        settlement.resources?.asMap ?? const {},
        costMult: costMult,
      );
      if (!await settlement.spendResources(cost)) continue; // can't afford yet
      c.healingUntil = now.add(healDuration(c) * speedMult);
      // Out of the line, into the hut.
      c.healQueuedAt = null;
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] queued heal persist failed: $e');
      }
      free--;
      started = true;
    }
    if (started) notifyListeners();
    // AFTER the admissions, never before (2026-07-27): starting a treatment
    // takes a monster out of the line, so trimming first would evict somebody
    // the free slot was about to take — which is exactly what a waiting room
    // authored as 0 would have done to every single heal.
    await _enforceHealQueueCap();
  }

  /// Completes every treatment whose timer has elapsed.
  ///
  /// Lazy, like expedition/breeding resolution: called on load and on the
  /// settlement tick, so a heal that finished while the app was closed is
  /// simply done — no background timer, no lost time.
  Future<void> resolveFinishedHeals() async {
    final due = creatures
        .where((c) => c.healingUntil != null && !c.isHealing)
        .toList();
    if (due.isEmpty) {
      // Nothing finished — but this is still the "settle the healing world"
      // entry point (load, tick, screen), and the LINE may need settling: a cap
      // that shrank while the app was closed leaves an over-full queue that
      // nothing else would ever trim.
      await _autoStartQueuedHeals();
      return;
    }
    for (final c in due) {
      // The heal actually finished at healingUntil — capture it before
      // _finishHeal clears it, so an offline-resolved treatment is timestamped
      // to when it completed, not to screen-open (user 2026-07-18).
      final finishedAt = c.healingUntil;
      _finishHeal(c);
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] heal resolve persist failed: $e');
      }
      GameEventLog().add(
        GameEventKind.levelUp,
        '${c.displayName} is patched up and ready',
        at: finishedAt,
      );
    }
    notifyListeners();
    // A slot just freed — pull in anyone who was waiting on the heal cap.
    await _autoStartQueuedHeals();
  }

  /// Gold to finish [c]'s treatment now. 0 when it isn't being treated.
  int healSkipCost(CreatureInstance c) => goldToSkip(c.healingRemaining);

  /// Pays gold to end a treatment early. Returns null on success or an error.
  /// Uses a crafted potion on [c]. Returns null on success, else why not.
  ///
  /// The instant alternative to the Healing Hut: no goods bill scaled to the
  /// missing HP and no wait, but you had to make it in advance. That's the
  /// trade — potions are banked between fights, the Hut is what you fall back
  /// on when the bag is empty.
  ///
  /// Refused on a creature at full HP: the item is spent for good, and
  /// silently burning one to heal nothing is a bug from the player's side.
  /// Also refused mid-treatment — otherwise a potion would top up HP the Hut
  /// is already being paid to restore, and the creature would still be locked
  /// out of fights until the timer ran down anyway.
  Future<String?> useItemOn(String itemId, CreatureInstance c) async {
    final def = kItemDefs[itemId];
    if (def == null) return 'Unknown item';
    if (c.isHealing) return '${c.displayName} is already being treated.';

    switch (def.kind) {
      case ItemKind.heal:
        final missing = (c.maxHp - c.hp).toDouble();
        if (!canUseOn(def, missing)) {
          return '${c.displayName} is already at full health.';
        }
        // Spend FIRST: if the item can't leave the bag, nothing was healed.
        final err = await SettlementController().consumeItem(itemId);
        if (err != null) return err;
        final healed = healFromItem(def, missing);
        c.hp = c.hp + healed.round();
        GameEventLog().add(
          GameEventKind.craft,
          '${def.emoji} ${c.displayName} healed ${healed.round()} HP',
        );
      case ItemKind.revive:
        if (!c.isKo) return "${c.displayName} isn't K.O.";
        final err = await SettlementController().consumeItem(itemId);
        if (err != null) return err;
        // Revive to [magnitude] fraction of max HP (min 1, so it's never a
        // no-op revive that leaves it K.O.).
        c.hp = (c.maxHp * def.magnitude).round().clamp(1, c.maxHp);
        GameEventLog().add(
          GameEventKind.craft,
          '${def.emoji} ${c.displayName} revived to ${c.hp} HP',
        );
      default:
        // catchBoost / expeditionYield / breedSpeed are used in their own flows,
        // not on a single creature here.
        return 'Nothing to use it on directly';
    }
    notifyListeners();
    await _svc.update(c);
    return null;
  }

  Future<String?> skipHealWithGold(CreatureInstance c) async {
    if (!c.isHealing) return 'It is not being treated.';
    final cost = healSkipCost(c);
    final settlement = SettlementController();
    if (!await settlement.spendResources({'gold': cost.toDouble()})) {
      return 'Not enough gold (need $cost, have ${settlement.gold.toInt()}).';
    }
    _finishHeal(c);
    try {
      await _svc.update(c);
    } catch (e) {
      debugPrint('[CreaturesController] heal skip persist failed: $e');
    }
    notifyListeners();
    return null;
  }

  /// Applies expedition casualties (see expedition_risk.dart): removes the
  /// rolled HP from each hurt member and persists it. K.O. members drop to 0
  /// HP and must be healed (Healing Hut / dev heal) before working again.
  Future<void> applyExpeditionCasualties(List<Casualty> casualties) async {
    for (final cas in casualties) {
      final c = byId(cas.creatureId);
      if (c == null) continue;
      c.hp = c.hp - cas.hpLost; // setter clamps to [0, maxHp]
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] casualty persist failed: $e');
      }
    }
    if (casualties.isNotEmpty) notifyListeners();
  }

  /// Writes a finished battle back to the collection: the participants'
  /// persistent HP/energy pools (they carry over between fights by design)
  /// plus, on victory, the same XP for every participant — including K.O.
  /// ones, so bringing a low-level creature along is a valid leveling path.
  Future<List<LevelUpResult>> applyBattleOutcome(
    List<Combatant> playerCombatants, {
    int xpEach = 0,
  }) async {
    final levelUps = <LevelUpResult>[];
    for (final combatant in playerCombatants) {
      CreatureInstance? creature;
      for (final c in creatures) {
        if (c.id == combatant.instanceId) {
          creature = c;
          break;
        }
      }
      if (creature == null) continue;
      creature.hp = combatant.hp;
      // Era-CAPPED (user 2026-07-22): nobody levels past the era's ceiling. The
      // reward itself is no longer era-scaled — the defeated monsters' own
      // levels are what make a later fight pay more (user 2026-07-26).
      if (xpEach > 0) {
        // Snapshot before, so a level-up can report exactly which stats grew
        // (user 2026-07-24: show the improvement at the end of the fight).
        final fromLevel = creature.level;
        final before = {
          for (final s in kCombatStats) s: creature.statValue(s),
        };
        final gained = creature.gainXp(xpEach, levelCap: eraLevelCap);
        if (gained > 0) {
          final statGains = <CreatureStat, int>{};
          for (final s in kCombatStats) {
            final delta = creature.statValue(s) - before[s]!;
            if (delta > 0) statGains[s] = delta;
          }
          levelUps.add(LevelUpResult(
            creatureId: creature.id,
            name: creature.displayName,
            imageUrl: creature.imageUrl,
            fromLevel: fromLevel,
            toLevel: creature.level,
            statGains: statGains,
          ));
        }
      }
      try {
        await _svc.update(creature);
      } catch (e) {
        debugPrint('[CreaturesController] battle sync failed: $e');
      }
    }
    notifyListeners();
    return levelUps;
  }
}

/// A creature that levelled up as a battle resolved, and by how much each combat
/// stat grew — fed to the end-of-fight level-up animation (user 2026-07-24).
class LevelUpResult {
  final String creatureId;
  final String name;
  final String? imageUrl;
  final int fromLevel;
  final int toLevel;

  /// Combat stat → points gained across the level(s). Only stats that grew.
  final Map<CreatureStat, int> statGains;

  const LevelUpResult({
    required this.creatureId,
    required this.name,
    required this.imageUrl,
    required this.fromLevel,
    required this.toLevel,
    required this.statGains,
  });
}
