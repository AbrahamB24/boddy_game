import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/breeding_job.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/species_def.dart';
import 'breeding_service.dart';
import 'creature_service.dart';
import 'creatures_controller.dart';

// Singleton owning the running breeding jobs (ARK-style time-based mating,
// decided design). Starting a job locks both parents out of battles (via
// CreaturesController.breedingIds); once ready_at passes the job shows as an
// egg, and hatching rolls the child — level 1, base form, each stat's IV
// inherited 70% from the better / 30% from the worse parent — then deletes
// the job and frees the parents.
class BreedingController extends ChangeNotifier {
  static final BreedingController _instance = BreedingController._();
  factory BreedingController() => _instance;
  BreedingController._();

  final _svc = BreedingService();
  final _creatureSvc = CreatureService();
  final _rng = math.Random();

  List<BreedingJob> jobs = [];
  bool isLoading = false;
  bool _loadedOnce = false;

  String? get _userId => supabase.auth.currentUser?.id;

  Future<void> load({bool force = false}) async {
    if (isLoading || (_loadedOnce && !force)) return;
    final userId = _userId;
    if (userId == null) return;
    isLoading = true;
    try {
      jobs = await _svc.loadOwn(userId);
      _loadedOnce = true;
      _syncBlockedIds();
    } catch (e) {
      debugPrint('[BreedingController] load failed: $e');
    }
    isLoading = false;
    notifyListeners();
  }

  void _syncBlockedIds() {
    CreaturesController().breedingIds
      ..clear()
      ..addAll(jobs.expand((j) => [j.parentAId, j.parentBId]));
  }

  /// Pure pair check, shared by UI and [start] (and unit-tested): same
  /// species, opposite genders, both battle-ready, neither already breeding.
  /// Returns a user-facing error or null when the pair is valid.
  static String? validatePair(
    CreatureInstance a,
    CreatureInstance b, {
    required Set<String> breedingIds,
  }) {
    if (a.id == b.id) return 'A creature cannot breed with itself.';
    if (a.speciesId != b.speciesId) {
      return 'Only creatures of the same species can breed.';
    }
    if (a.gender == b.gender) {
      return 'It takes one male (♂) and one female (♀).';
    }
    if (a.isKo || b.isKo) return 'K.O. creatures cannot breed.';
    if (breedingIds.contains(a.id) || breedingIds.contains(b.id)) {
      return 'One of these creatures is already breeding.';
    }
    return null;
  }

  /// Starts a mating job. Duration = the species' rarity breedHours.
  /// Returns null on success or a user-facing error.
  Future<String?> start(CreatureInstance a, CreatureInstance b) async {
    final userId = _userId;
    if (userId == null) return 'Not logged in.';
    final error = validatePair(
      a,
      b,
      breedingIds: CreaturesController().breedingIds,
    );
    if (error != null) return error;
    final species = kSpeciesDefs[a.speciesId];
    if (species == null) return 'Unknown species.';

    // The pair's breeding stat shortens incubation (see breedingHours):
    // better breeders hatch their egg faster, down to half the rarity base.
    final avgBreeding =
        (a.statValue(CreatureStat.breeding) + b.statValue(CreatureStat.breeding)) /
        2.0;
    final hours = breedingHours(species.rarity.breedHours, avgBreeding);

    try {
      final job = await _svc.insert(
        userId: userId,
        parentAId: a.id,
        parentBId: b.id,
        speciesId: species.id,
        readyAt: DateTime.now().add(
          Duration(milliseconds: (hours * 3600000).round()),
        ),
      );
      jobs.add(job);
      _syncBlockedIds();
      notifyListeners();
      CreaturesController().notifyListeners();
      return null;
    } catch (e) {
      return 'Breeding failed: $e';
    }
  }

  /// Aborts a job — no egg, parents freed immediately.
  Future<void> cancel(BreedingJob job) async {
    jobs.removeWhere((j) => j.id == job.id);
    _syncBlockedIds();
    notifyListeners();
    CreaturesController().notifyListeners();
    try {
      await _svc.delete(job.id);
    } catch (e) {
      debugPrint('[BreedingController] cancel failed: $e');
    }
  }

  /// Hatches a ready egg: rolls the child (level 1, base form, each of the
  /// 12 genes independently inherited 70% better/30% worse parent, random
  /// gender), inserts it into the collection and removes the job. Returns
  /// the hatchling, or null on error.
  Future<CreatureInstance?> hatch(BreedingJob job) async {
    final userId = _userId;
    if (userId == null || !job.isReady) return null;
    final creatures = CreaturesController();
    final species = kSpeciesDefs[job.speciesId];
    if (species == null) return null;

    CreatureInstance? find(String id) {
      for (final c in creatures.creatures) {
        if (c.id == id) return c;
      }
      return null;
    }

    final parentA = find(job.parentAId);
    final parentB = find(job.parentBId);
    // Both parents should exist (release is blocked while breeding); fresh
    // rolls are the graceful fallback if one is somehow gone. Inheritance
    // reads the parents' CURRENT genes (including any evolution bonus
    // they've earned) — evolving breeding stock first is an intentional
    // strategy, not a loophole. The pair's breeding stat raises the chance the
    // BETTER gene wins (50/50 at breeding 0, up toward certainty).
    final favoredChance = (parentA != null && parentB != null)
        ? breedingFavoredChance(
            (parentA.statValue(CreatureStat.breeding) +
                    parentB.statValue(CreatureStat.breeding)) /
                2.0,
          )
        : 0.70;
    final statBase = (parentA != null && parentB != null)
        ? CreatureInstance.inheritGenes(
            parentA.statBase,
            parentB.statBase,
            _rng,
            favoredChance: favoredChance,
          )
        : CreatureInstance.rollBaseGenes(species, _rng);
    final statSlope = (parentA != null && parentB != null)
        ? CreatureInstance.inheritGenes(
            parentA.statSlope,
            parentB.statSlope,
            _rng,
            favoredChance: favoredChance,
          )
        : CreatureInstance.rollSlopeGenes(species, _rng);

    final baby = CreatureInstance(
      id: '',
      userId: userId,
      speciesId: job.speciesId,
      gender: _rng.nextBool() ? CreatureGender.male : CreatureGender.female,
      level: 1,
      stage: 0,
      statBase: statBase,
      statSlope: statSlope,
      parentAId: job.parentAId,
      parentBId: job.parentBId,
    );

    try {
      final created = await _creatureSvc.insert(baby);
      creatures.creatures.add(created);
      jobs.removeWhere((j) => j.id == job.id);
      _syncBlockedIds();
      await _svc.delete(job.id);
      notifyListeners();
      creatures.notifyListeners();
      return created;
    } catch (e) {
      debugPrint('[BreedingController] hatch failed: $e');
      return null;
    }
  }

  /// Dev-mode shortcut: skip the timer.
  Future<void> devFinishNow(BreedingJob job) async {
    try {
      await _svc.finishNow(job.id);
      await load(force: true);
    } catch (e) {
      debugPrint('[BreedingController] devFinishNow failed: $e');
    }
  }
}
