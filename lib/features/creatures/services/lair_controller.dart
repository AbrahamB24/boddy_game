import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../settlement/data/goods_definitions.dart';
import '../../settlement/settlement_controller.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';
import '../models/legendary_lair.dart';
import '../models/legendary_math.dart';
import '../models/species_def.dart';
import 'creatures_controller.dart';
import 'lair_service.dart';

/// The legendary lairs of this player (user 2026-11-07).
///
/// Each legendary lives in a lair whose level IS its level. Raising it costs
/// the species' region luxury plus gold, then runs on a clock that up to five
/// legendaries of OTHER players can speed up and are paid for.
///
/// Everything here degrades quietly when migration 0068 is not applied yet:
/// [available] stays false and the screens say so, nothing else breaks.
class LairController extends ChangeNotifier {
  static final LairController _instance = LairController._();
  factory LairController() => _instance;
  LairController._();

  final LairService _svc = LairService();

  List<LegendaryLair> lairs = const [];

  /// My creatures that are somebody's trainer right now.
  Set<String> busyTrainers = const {};

  bool loading = false;
  bool available = true;
  String? lastError;

  String? get _userId => supabase.auth.currentUser?.id;

  LegendaryLair? lairOf(String creatureId) {
    for (final l in lairs) {
      if (l.creatureId == creatureId) return l;
    }
    return null;
  }

  /// The luxury an upgrade of [species] is paid in: its region's own.
  String luxuryOf(SpeciesDef species) {
    final list = luxuriesOfRegion(species.tier);
    return list.isEmpty ? 'fish' : list.first.id;
  }

  List<CreatureInstance> get myLegendaries => [
    for (final c in CreaturesController().creatures)
      if (c.species?.rarity == CreatureRarity.legendary) c,
  ];

  /// Legendaries of mine that could train somebody now.
  List<CreatureInstance> get freeTrainers => [
    for (final c in myLegendaries)
      if (!busyTrainers.contains(c.id)) c,
  ];

  double trainerEffectOf(CreatureInstance c) => LegendaryMath.trainerEffect(
    c.species?.trainerPower ?? 0,
    c.level,
  );

  /// Loads the lairs, makes one for any legendary that has none yet (a boss
  /// just fell), settles finished upgrades, syncs the monsters' levels and
  /// collects what trainers earned.
  Future<void> load() async {
    final uid = _userId;
    if (uid == null || loading) return;
    loading = true;
    notifyListeners();
    try {
      var loaded = await _svc.loadOwn(uid);
      var missing = [
        for (final c in myLegendaries)
          if (!loaded.any((l) => l.creatureId == c.id)) c,
      ];
      for (final c in missing) {
        await _svc.ensure(c.id, c.speciesId, c.level);
      }
      var changed = missing.isNotEmpty;
      for (final l in loaded) {
        if (l.isDone) {
          await _svc.refresh(l.id);
          changed = true;
        }
      }
      if (changed) loaded = await _svc.loadOwn(uid);
      lairs = loaded;
      busyTrainers = await _svc.myTrainerCreatureIds(uid);
      _syncLevels();
      await _collectRewards();
      available = true;
      lastError = null;
    } catch (e) {
      // Most likely migration 0068 is not applied yet.
      available = false;
      lastError = '$e';
      debugPrint('[LairController] load failed: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// The monster's level is its lair's level. The server already wrote it to
  /// the creature row; this only brings the in-memory copy in line.
  void _syncLevels() {
    for (final l in lairs) {
      final c = CreaturesController().creatures
          .where((x) => x.id == l.creatureId)
          .firstOrNull;
      if (c != null && c.level != l.level) {
        c.level = l.level;
        c.xp = 0;
      }
    }
  }

  Future<void> _collectRewards() async {
    final owed = await _svc.claimRewards();
    if (owed.isEmpty) return;
    final grant = <String, double>{};
    for (final r in owed) {
      if (r.good != null && r.amount > 0) {
        grant[r.good!] = (grant[r.good!] ?? 0) + r.amount;
      }
      if (r.gold > 0) grant['gold'] = (grant['gold'] ?? 0) + r.gold;
    }
    if (grant.isNotEmpty) {
      await SettlementController().grantResources(grant, refund: true);
    }
  }

  /// What the next upgrade of [lair] costs, in the units the settlement holds.
  Map<String, double> costOf(LegendaryLair lair, SpeciesDef species) => {
    luxuryOf(species): LegendaryMath.luxuryCost(lair.level),
    'gold': LegendaryMath.goldCost(lair.level),
  };

  /// Pays and starts the next upgrade. Returns an error text, or null on
  /// success.
  Future<String?> startUpgrade(LegendaryLair lair) async {
    final species = kSpeciesDefs[lair.speciesId];
    if (species == null) return 'Unknown species';
    if (lair.upgrading) return 'Already upgrading';
    final cost = costOf(lair, species);
    final settlement = SettlementController();
    if (!await settlement.spendResources(cost)) {
      return 'Not enough resources';
    }
    try {
      await _svc.startUpgrade(
        lairId: lair.id,
        workSeconds: LegendaryMath.workSeconds(lair.level),
        good: luxuryOf(species),
        amount: cost[luxuryOf(species)]!,
        gold: cost['gold']!,
        shares: LegendaryMath.shares,
      );
    } catch (e) {
      // The server refused: give the payment back.
      await settlement.grantResources(cost, refund: true);
      return '$e';
    }
    await load();
    return null;
  }

  /// [c] (mine) trains somebody else's lair. It cannot be taken out again, but
  /// stays usable for everything else.
  Future<String?> joinAsTrainer(OpenLairSlot slot, CreatureInstance c) async {
    try {
      await _svc.join(slot.lairId, c.id, trainerEffectOf(c));
    } catch (e) {
      return '$e';
    }
    await load();
    return null;
  }

  Future<List<OpenLairSlot>> openSlots() => _svc.openSlots();
}
