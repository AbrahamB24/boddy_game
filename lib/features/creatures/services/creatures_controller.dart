import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../settlement/data/tech_definitions.dart';
import '../../settlement/settlement_controller.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/species_def.dart';
import 'creature_defs_controller.dart';
import 'creature_service.dart';

// Singleton holding the player's creature collection, same ChangeNotifier
// pattern as SettlementController. Evolution spends BP through the
// SettlementController singleton so the top-bar BP chip and research screen
// stay in sync automatically.
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

  CreatureInstance? byId(String id) {
    for (final c in creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The battle roster: first [size] creatures that are neither K.O. nor
  /// locked in a breeding job. THE single team-selection rule — collection
  /// training, dungeon entry and dungeon fights all use this.
  List<CreatureInstance> battleTeam({int size = 3}) => creatures
      .where((c) => !c.isKo && !isBreeding(c.id))
      .take(size)
      .toList();

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

  /// First creature for a fresh account: level 5, random gender, freshly
  /// Gaussian-sampled genes. Only allowed while the collection is empty (the
  /// UI gates this too).
  Future<CreatureInstance?> adoptStarter(SpeciesDef species) async {
    final userId = _userId;
    if (userId == null || creatures.isNotEmpty) return null;
    final starter = CreatureInstance(
      id: '',
      userId: userId,
      speciesId: species.id,
      gender: _rng.nextBool() ? CreatureGender.male : CreatureGender.female,
      level: 5,
      statBase: CreatureInstance.rollBaseGenes(species, _rng),
      statSlope: CreatureInstance.rollSlopeGenes(species, _rng),
    );
    try {
      final created = await _svc.insert(starter);
      creatures.add(created);
      notifyListeners();
      return created;
    } catch (e) {
      debugPrint('[CreaturesController] adoptStarter failed: $e');
      return null;
    }
  }

  /// Evolves to the next stage, spending BP via the settlement singleton.
  /// Per the balance spec, evolution bumps only the individual's stat BASE
  /// (by the species' own mean delta between stages) — the growth slope
  /// never changes, and the bonus is added to whatever this individual
  /// already rolled, never re-rolled. Returns null on success or a
  /// user-facing error message.
  Future<String?> evolve(CreatureInstance creature) async {
    final species = creature.species;
    final cost = creature.nextEvolutionCostBp;
    if (species == null || cost == null) {
      return 'Already at the final stage.';
    }
    if (!creature.canEvolve) {
      return 'Requires Level ${species.evoLevelFrom(creature.stage)}.';
    }
    final settlement = SettlementController();
    // Research-tree gate: only enforced once the tech def exists as content
    // — see kEvolutionTechIds.
    final techId = kEvolutionTechIds[creature.stage.clamp(0, 1)];
    final techDef = kTechDefs[techId];
    if (techDef != null && !settlement.unlockedTechs.contains(techId)) {
      return 'Requires research "${techDef.name}".';
    }
    if (settlement.bp < cost) {
      return 'Not enough BP ($cost needed) — workouts earn BP!';
    }
    try {
      await settlement.addBp(-cost);
      final fromStage = creature.stage;
      for (final stat in CreatureStat.values) {
        final bonus = species.statCurve(stat).evolutionBonus(fromStage);
        creature.statBase[stat] = (creature.statBase[stat] ?? 0) + bonus;
      }
      creature.stage += 1;
      // Evolution is a moment of triumph — refill both pools to the (now
      // higher) maxima instead of leaving the old, smaller values.
      creature.currentHp = -1;
      creature.currentEnergy = -1;
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

  /// Dev-mode helper: grant XP and persist.
  Future<void> devGainXp(CreatureInstance creature, int amount) async {
    creature.gainXp(amount);
    notifyListeners();
    try {
      await _svc.update(creature);
    } catch (e) {
      debugPrint('[CreaturesController] devGainXp failed: $e');
    }
  }

  /// Adds a successfully caught wild to the collection. The catch keeps the
  /// wild's exact identity: species, level, evolution stage, gender and its
  /// exact sampled genes. Joins with full pools (fresh start in your team).
  Future<CreatureInstance?> captureWild(Combatant wild) async {
    final userId = _userId;
    final speciesId = wild.speciesId;
    if (userId == null ||
        speciesId == null ||
        wild.wildStatBase == null ||
        wild.wildStatSlope == null) {
      return null;
    }
    // Defensive capacity guard (the catch UI checks first, but never exceed
    // housing even if it doesn't).
    if (housingFull) return null;
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
      notifyListeners();
      return created;
    } catch (e) {
      debugPrint('[CreaturesController] captureWild failed: $e');
      return null;
    }
  }

  /// Heal-space effect (dungeon): revives K.O. creatures at 50% HP, heals
  /// the rest by 60% of max, and restores 50% max energy — capped at the
  /// maxima. Persisted immediately (pools are persistent by design).
  Future<void> healTeam(List<CreatureInstance> team) async {
    for (final c in team) {
      c.hp = c.isKo
          ? (c.maxHp * 0.5).round()
          : math.min(c.maxHp, c.hp + (c.maxHp * 0.6).round());
      c.energy = math.min(c.maxEnergy, c.energy + (c.maxEnergy * 0.5).round());
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] healTeam persist failed: $e');
      }
    }
    notifyListeners();
  }

  /// Full-heal effect (Healing Hut building + Dev instant-heal button):
  /// revives every K.O. creature and refills HP + energy to their maxima.
  /// Unlike [healTeam] (dungeon heal-space, partial, active team only) this
  /// touches the WHOLE collection and is a full restore — persisted
  /// immediately.
  Future<void> healAll() async {
    for (final c in creatures) {
      c.currentHp = -1;
      c.currentEnergy = -1;
      try {
        await _svc.update(c);
      } catch (e) {
        debugPrint('[CreaturesController] healAll persist failed: $e');
      }
    }
    notifyListeners();
  }

  /// Writes a finished battle back to the collection: the participants'
  /// persistent HP/energy pools (they carry over between fights by design)
  /// plus, on victory, the same XP for every participant — including K.O.
  /// ones, so bringing a low-level creature along is a valid leveling path.
  Future<void> applyBattleOutcome(
    List<Combatant> playerCombatants, {
    int xpEach = 0,
  }) async {
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
      creature.energy = combatant.energy;
      if (xpEach > 0) creature.gainXp(xpEach);
      try {
        await _svc.update(creature);
      } catch (e) {
        debugPrint('[CreaturesController] battle sync failed: $e');
      }
    }
    notifyListeners();
  }
}
