import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/notifications/game_notifications.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../common/events/game_events.dart';
import '../../settlement/data/item_definitions.dart';
import '../../settlement/settlement_controller.dart';
import '../models/breeding_job.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';
import 'breeding_cost.dart';
import 'breeding_service.dart';
import 'creature_service.dart';
import 'creatures_controller.dart';

// Singleton owning the running breeding jobs (ARK-style time-based mating,
// decided design). Starting a job locks both parents out of battles (via
// CreaturesController.breedingIds); once ready_at passes the job becomes an
// EGG and the parents are freed.
//
// The child is rolled AT LAY TIME, not at hatch (user 2026-07-26, migration
// 0027): each gene inherited from the better parent with a chance set by the
// pair's breeding stat, then frozen onto the row. That is what makes an egg an
// item you hold rather than a promise about two other creatures — and it fixes
// a real bug, since releasing a parent used to turn the unhatched child into a
// random roll off the species curve.
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
      await _promoteLaidEggs();
      _syncBlockedIds();
    } catch (e) {
      debugPrint('[BreedingController] load failed: $e');
    }
    isLoading = false;
    notifyListeners();
  }

  /// A `breeding` job whose timer has elapsed has laid its egg: flip it to
  /// `egg` (frees the parents) and persist. Called on load and whenever the UI
  /// ticks, so an egg that finished while the app was closed collects itself.
  ///
  /// THE CHILD IS ROLLED HERE, not at hatch (user 2026-07-26, making the egg a
  /// bag item). Laying is the last moment both parents are guaranteed present
  /// and unchanged, so it is the only honest place to read their genes. From
  /// here the egg is an object: releasing, evolving or levelling a parent
  /// cannot alter what is inside it.
  Future<void> _promoteLaidEggs() async {
    for (var i = 0; i < jobs.length; i++) {
      final j = jobs[i];
      if (j.status == BreedingStatus.breeding && j.isReady) {
        final child = _rollChild(j);
        jobs[i] = j.copyWith(
          status: BreedingStatus.egg,
          childBase: child?.$1,
          childSlope: child?.$2,
        );
        try {
          await _svc.updateStatus(
            j.id,
            BreedingStatus.egg,
            childBase:
                child == null ? null : BreedingJob.genesToJson(child.$1),
            childSlope:
                child == null ? null : BreedingJob.genesToJson(child.$2),
          );
        } catch (e) {
          debugPrint('[BreedingController] promote egg failed: $e');
        }
        // BREEDING FINISHED → THE BELL RINGS (user 2026-07-27). A mating that
        // completed while the app was closed used to leave no trace at all: the
        // egg simply appeared in the bag, and nothing said when or from what.
        //
        // Fired here, on the PERSISTED transition, so it happens exactly once —
        // the row is `egg` from now on and can never promote again. [at] is the
        // moment it was laid, not when the resolver ran, so the feed and the
        // welcome-back box both read true after a night away.
        GameEventLog().add(
          GameEventKind.breeding,
          '${kSpeciesDefs[j.speciesId]?.name ?? j.speciesId} laid an egg — '
          'it is in your bag.',
          at: j.readyAt,
        );
      }
    }
  }

  /// Rolls the child of [job] from its parents' CURRENT genes — each gene
  /// independently, the better parent's value winning with a chance set by the
  /// pair's breeding stat. Null when a parent is missing, which is the caller's
  /// signal to leave the egg un-frozen (it then hatches the legacy way).
  ///
  /// Reading the parents' current genes means evolving breeding stock BEFORE
  /// the egg is laid is an intentional strategy, not a loophole.
  (Map<CreatureStat, double>, Map<CreatureStat, double>)? _rollChild(
    BreedingJob job,
  ) {
    final creatures = CreaturesController();
    final a = creatures.byId(job.parentAId);
    final b = creatures.byId(job.parentBId);
    if (a == null || b == null) return null;
    // Flat odds since 2026-07-27 — the parents' breeding stat plays no part.
    final favored = breedingFavoredChance();
    return (
      CreatureInstance.inheritGenes(a.statBase, b.statBase, _rng,
          favoredChance: favored),
      CreatureInstance.inheritGenes(a.statSlope, b.statSlope, _rng,
          favoredChance: favored),
    );
  }

  /// Public tick hook for the UI: promote any finished matings to eggs, then
  /// notify. Cheap when nothing changed.
  Future<void> refreshEggs() async {
    final before = jobs.map((j) => j.status).toList();
    await _promoteLaidEggs();
    _syncBlockedIds();
    if (!_sameStatuses(before)) {
      notifyListeners();
      CreaturesController().notifyListeners();
    }
  }

  bool _sameStatuses(List<BreedingStatus> before) {
    if (before.length != jobs.length) return false;
    for (var i = 0; i < jobs.length; i++) {
      if (before[i] != jobs[i].status) return false;
    }
    return true;
  }

  // Parents are only locked while actively MATING (status breeding). Once the
  // egg is laid they are free again — the egg and the later hatching no longer
  // involve them (they only ever provided genes).
  void _syncBlockedIds() {
    CreaturesController().breedingIds
      ..clear()
      ..addAll(jobs
          .where((j) => j.status == BreedingStatus.breeding)
          .expand((j) => [j.parentAId, j.parentBId]));
  }

  // ── Slot accounting (user 2026-07-24) ─────────────────────────
  List<BreedingJob> get matingJobs =>
      jobs.where((j) => j.status == BreedingStatus.breeding).toList();
  List<BreedingJob> get eggs =>
      jobs.where((j) => j.status == BreedingStatus.egg).toList();
  List<BreedingJob> get hatchingJobs =>
      jobs.where((j) => j.status == BreedingStatus.hatching).toList();

  int get breedingSlots =>
      SettlementController().breedingCapacity(kBreedingHutBuildingId);
  int get freeBreedingSlots => breedingSlots - matingJobs.length;
  int get hatcherySlots =>
      SettlementController().hatchingCapacity(kHatcheryBuildingId);
  int get freeHatcherySlots => hatcherySlots - hatchingJobs.length;

  /// Pure pair check, shared by UI and [start] (and unit-tested): same
  /// species, opposite genders, both battle-ready, neither already breeding —
  /// and never legendaries. Returns a user-facing error or null when valid.
  static String? validatePair(
    CreatureInstance a,
    CreatureInstance b, {
    required Set<String> breedingIds,
  }) {
    if (a.id == b.id) return 'A creature cannot breed with itself.';
    if (a.speciesId != b.speciesId) {
      return 'Only creatures of the same species can breed.';
    }
    // Legendaries do not breed (user 2026-07-22): each region's legendary is
    // a one-of-a-kind boss trophy — a breeding pen full of copies would
    // unmake exactly that.
    if (kSpeciesDefs[a.speciesId]?.rarity == CreatureRarity.legendary) {
      return 'Legendary creatures cannot breed.';
    }
    if (a.gender == b.gender) {
      return 'It takes one male (♂) and one female (♀).';
    }
    if (a.isKo || b.isKo) return 'K.O. creatures cannot breed.';
    if (a.isHealing || b.isHealing) {
      return 'One of these creatures is still being treated.';
    }
    if (breedingIds.contains(a.id) || breedingIds.contains(b.id)) {
      return 'One of these creatures is already breeding.';
    }
    return null;
  }

  /// Starts a mating job in the Breeding Hut. Duration = the rarity base hours
  /// cut down by the breeders stationed in the hut; capped by its slots.
  /// Returns null on success or a user-facing error.
  Future<String?> start(CreatureInstance a, CreatureInstance b) async {
    final userId = _userId;
    if (userId == null) return 'Not logged in.';
    // THE HUT IS THE GATE (user 2026-07-26: "zucht ist bereits an breeding
    // geknüpft"). A second, map-progress feature check sat here and was pure
    // duplication: `breedingSlots <= 0` below already refuses without a hut,
    // and it says something the player can act on.
    final error = validatePair(
      a,
      b,
      breedingIds: CreaturesController().breedingIds,
    );
    if (error != null) return error;
    final species = kSpeciesDefs[a.speciesId];
    if (species == null) return 'Unknown species.';

    // NOTHING RUNS ON AN EMPTY TANK (user 2026-07-27) — mating included.
    if (!SettlementController().hasEnergy) {
      return SettlementController.kNoEnergyMessage;
    }

    // The Breeding Hut's concurrent-mating cap (its `breeding` effect, summed
    // over levels). No hut / no free slot → nothing to start.
    if (breedingSlots <= 0) return 'Build a Breeding Hut first.';
    if (freeBreedingSlots <= 0) {
      return 'All breeding slots are busy ($breedingSlots).';
    }

    // Speed now comes from the breeders STATIONED in the hut, not the parents
    // (user 2026-07-24): the parents only pass on genes. More/stronger breeders
    // on post cut the rarity base incubation, down to half.
    final settlement = SettlementController();
    final workerPower = settlement.breedingPower(kBreedingHutBuildingId);
    final hours = breedingHours(
      kSpeciesBalance.of(species.rarity).breedHours,
      workerPower,
    );

    // A mating COSTS SUPPLIES (user 2026-07-27) — the goods of the era the
    // PARENTS come from, not the settlement's. See breeding_cost.dart. Charged
    // before the insert and refunded below if that fails, so a dropped
    // connection never eats the bill.
    final cost = breedCost(a, b, settlement.resources?.asMap ?? const {});
    if (cost.isNotEmpty && !await settlement.spendResources(cost)) {
      return 'Not enough ${breedCostLabel(cost)} to breed them.';
    }

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
      // Both breeding clocks get a reminder (user 2026-07-30): a mating runs for
      // hours and the egg it lays is the thing the player came for.
      unawaited(GameNotifications.schedule(
        kind: NotifyKind.breeding,
        key: job.id,
        at: job.readyAt,
        title: '🥚 An egg was laid',
        body: 'Your pair is done — the egg is ready for the Hatchery.',
      ));
      _syncBlockedIds();
      notifyListeners();
      CreaturesController().notifyListeners();
      return null;
    } catch (e) {
      // The supplies were already spent — give them back, or a failed insert
      // costs the pair's bill for nothing.
      if (cost.isNotEmpty) await settlement.grantResources(cost);
      return 'Breeding failed: $e';
    }
  }

  /// Drops a laid [egg] into the Hatchery: starts a second timed incubation
  /// driven by the breeders stationed THERE, capped by the Hatchery's slots.
  /// Returns null on success or a user-facing error.
  Future<String?> placeInHatchery(BreedingJob job) async {
    if (job.status != BreedingStatus.egg) return 'That egg is not ready.';
    if (!SettlementController().hasEnergy) {
      return SettlementController.kNoEnergyMessage;
    }
    if (hatcherySlots <= 0) return 'Build a Hatchery first.';
    if (freeHatcherySlots <= 0) {
      return 'All hatchery slots are busy ($hatcherySlots).';
    }
    final species = kSpeciesDefs[job.speciesId];
    if (species == null) return 'Unknown species.';

    // The egg's OWN clock and the Hatchery's OWN staff (user 2026-07-26):
    // hatchHours driven by the hatchers here, not by the hut's breeders.
    final workerPower =
        SettlementController().hatchingPower(kHatcheryBuildingId);
    final hours = breedingHours(
      kSpeciesBalance.of(species.rarity).hatchHours,
      workerPower,
    );
    final readyAt = DateTime.now().add(
      Duration(milliseconds: (hours * 3600000).round()),
    );

    final i = jobs.indexWhere((j) => j.id == job.id);
    if (i < 0) return 'Egg is gone.';
    jobs[i] = job.copyWith(status: BreedingStatus.hatching, readyAt: readyAt);
    try {
      await _svc.updateStatus(job.id, BreedingStatus.hatching, readyAt: readyAt);
      unawaited(GameNotifications.schedule(
        kind: NotifyKind.breeding,
        key: job.id,
        at: readyAt,
        title: '🐣 Ready to hatch',
        body: 'The egg in the Hatchery has finished incubating.',
      ));
      notifyListeners();
      return null;
    } catch (e) {
      jobs[i] = job; // roll back the optimistic update
      return 'Could not start hatching: $e';
    }
  }

  /// Uses a `breedSpeed` item to cut a timed job's REMAINING time by the item's
  /// magnitude fraction (user 2026-07-25). Only for a running timer (breeding or
  /// hatching); an egg has no clock. Returns null on success or an error.
  Future<String?> useSpeedItem(BreedingJob job, String itemId) async {
    final def = kItemDefs[itemId];
    if (def == null || def.kind != ItemKind.breedSpeed) {
      return 'Not an accelerator.';
    }
    if (job.status == BreedingStatus.egg) return 'The egg has no running timer.';
    if (job.isReady) return 'It is already done.';
    final err = await SettlementController().consumeItem(itemId);
    if (err != null) return err;
    final remainingMs = job.readyAt.difference(DateTime.now()).inMilliseconds;
    final cutMs =
        (remainingMs * (1 - def.magnitude)).round().clamp(0, remainingMs);
    final newReadyAt = DateTime.now().add(Duration(milliseconds: cutMs));
    final i = jobs.indexWhere((j) => j.id == job.id);
    if (i < 0) return 'Job is gone.';
    jobs[i] = job.copyWith(readyAt: newReadyAt);
    // Same key, so this REPLACES the old promise rather than adding a second one
    // at the time the accelerator just cancelled.
    unawaited(GameNotifications.schedule(
      kind: NotifyKind.breeding,
      key: job.id,
      at: newReadyAt,
      title: job.status == BreedingStatus.hatching
          ? '🐣 Ready to hatch'
          : '🥚 An egg was laid',
      body: 'Hurried along — it is done sooner than planned.',
    ));
    try {
      await _svc.updateStatus(job.id, job.status, readyAt: newReadyAt);
    } catch (e) {
      debugPrint('[BreedingController] speed item persist failed: $e');
    }
    notifyListeners();
    return null;
  }

  /// Takes an incubating egg back OUT of the Hatchery (user 2026-07-27: "wenn
  /// ich ein hatchendes ei cancle, soll es zurück ins inventar gehen").
  ///
  /// Cancelling used to DELETE the row — the same call the breeding page uses
  /// to abort a mating, which is right there (nothing exists yet) and wrong
  /// here (an egg does, with a child frozen inside it). Freeing a Hatchery slot
  /// should not destroy what is in it.
  ///
  /// The incubation's PROGRESS is lost: the egg goes back to the bag as an egg,
  /// and re-placing it starts a fresh clock. [readyAt] is reset to now because
  /// the row has one timestamp column — the incubation deadline overwrote the
  /// lay time when it went in — and leaving a future value there would have the
  /// bag reporting an egg laid in the future.
  Future<String?> returnToBag(BreedingJob job) async {
    if (job.status != BreedingStatus.hatching) {
      return 'That egg is not incubating.';
    }
    final i = jobs.indexWhere((j) => j.id == job.id);
    if (i < 0) return 'Egg is gone.';
    final now = DateTime.now();
    jobs[i] = job.copyWith(status: BreedingStatus.egg, readyAt: now);
    notifyListeners();
    try {
      await _svc.updateStatus(job.id, BreedingStatus.egg, readyAt: now);
    } catch (e) {
      jobs[i] = job; // roll back the optimistic update
      notifyListeners();
      return 'Could not take it out: $e';
    }
    return null;
  }

  /// Aborts a job — no egg, parents freed immediately.
  Future<void> cancel(BreedingJob job) async {
    // A discarded egg's reminder goes with it — nothing is coming.
    unawaited(GameNotifications.cancel(NotifyKind.breeding, job.id));
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

  /// Hatches a ready egg: reads the child frozen into it when it was laid
  /// (level 1, base form, random gender), inserts it into the collection and
  /// removes the job. Returns the hatchling, or null on error.
  Future<CreatureInstance?> hatch(BreedingJob job) async {
    // Whatever happens below, this job's clock is finished with — the promise
    // about it must not outlive the egg.
    unawaited(GameNotifications.cancel(NotifyKind.breeding, job.id));
    final userId = _userId;
    // Only a finished HATCHERY incubation yields a child — a laid egg still
    // has to be placed in the Hatchery first.
    if (userId == null || !job.isHatchable) return null;
    final creatures = CreaturesController();
    final species = kSpeciesDefs[job.speciesId];
    if (species == null) return null;

    // THE EGG CARRIES ITS CHILD (migration 0027). Hatching is now a pure
    // read: no parent is consulted, so releasing or evolving one after the egg
    // was laid changes nothing about what comes out.
    //
    // The fallbacks below are for eggs laid BEFORE that: roll from the parents
    // if they are still around, else off the species curve. Without the first
    // fallback a pre-0027 egg in flight would hatch a random creature.
    var statBase = job.childBase;
    var statSlope = job.childSlope;
    if (statBase.isEmpty || statSlope.isEmpty) {
      final legacy = _rollChild(job);
      if (statBase.isEmpty) {
        statBase = legacy?.$1 ?? CreatureInstance.rollBaseGenes(species, _rng);
      }
      // GROWTH IS A GENE OF ITS OWN (user 2026-07-27) and is checked on its
      // own: an egg whose child_slope failed to write would otherwise hatch a
      // creature that gains nothing per level, which reads as a broken child
      // rather than as a missing column.
      if (statSlope.isEmpty) {
        statSlope = legacy?.$2 ?? CreatureInstance.rollSlopeGenes(species, _rng);
      }
    }

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
      GameEventLog().add(
        GameEventKind.breeding,
        '${created.displayName} hatched!',
        // The egg was ready at readyAt; an offline hatch resolved on load
        // should read from then, not from screen-open.
        at: job.readyAt,
      );
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
