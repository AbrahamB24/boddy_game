import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../onboarding/intro_flow.dart';
import '../data/building_definitions.dart';
import '../models/energy_model.dart';
import '../models/placed_building.dart';
import '../models/resource_model.dart';
import '../models/settlement.dart';

class SettlementService {
  // ── Bootstrap: create all rows for a new user ─────────────
  Future<SettlementModel> getOrCreate(String userId) async {
    final existing = await supabase
        .from('settlements')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) return SettlementModel.fromMap(existing);

    final settlement = await supabase
        .from('settlements')
        .insert({'user_id': userId})
        .select()
        .single();
    final model = SettlementModel.fromMap(settlement);

    await Future.wait([
      supabase.from('resources').insert({
        'settlement_id': model.id,
        // Covers the guided tutorial's full build bill (healing hut +
        // woodland camp + quarry + hut + fishing hut ≈ 620 wood / 170
        // stone) with slack — the script must never stall on "can't afford".
        'wood': 750.0,
        'stone': 300.0,
        // Jumpstart float, not income: fish/fur are the region-dungeon entry
        // cost and buildings make them deliberately slowly (workshop mult
        // 0.12), so a new player would otherwise stall at the first gate.
        'fish': kJumpstartGiftFish,
        'fur': kJumpstartGiftFur,
      }),
      supabase.from('energy_state').insert({
        'settlement_id': model.id,
        'current_energy': 80.0,
      }),
      supabase.from('placed_buildings').insert({
        'settlement_id': model.id,
        'building_type_id': 'castle',
        // Centred in the starting plot, derived from the hall's own footprint
        // — see kMainHallStartX/Y. This used to be a hardcoded `- 3` and the
        // hall silently sat off-centre once the def wasn't 3x3.
        'grid_x': kMainHallStartX,
        'grid_y': kMainHallStartY,
        'construction_seconds_required': 0,
        'construction_seconds_built': 0,
        'is_complete': true,
      }),
      supabase.from('profiles').upsert({'id': userId}),
    ]);

    return model;
  }

  // ── Loaders ───────────────────────────────────────────────
  Future<ResourceModel> loadResources(String settlementId) async {
    final row = await supabase
        .from('resources')
        .select()
        .eq('settlement_id', settlementId)
        .single();
    return ResourceModel.fromMap(row);
  }

  Future<EnergyModel> loadEnergy(String settlementId) async {
    final row = await supabase
        .from('energy_state')
        .select()
        .eq('settlement_id', settlementId)
        .single();
    return EnergyModel.fromMap(row);
  }

  Future<List<PlacedBuilding>> loadBuildings(String settlementId) async {
    final rows = await supabase
        .from('placed_buildings')
        .select()
        .eq('settlement_id', settlementId);
    return (rows as List).map((r) => PlacedBuilding.fromMap(r)).toList();
  }

  /// Daily-tasks blob, or null pre-migration / when never saved — the caller
  /// rolls a fresh set either way, so a missing column degrades to "tasks
  /// simply don't persist yet" (same tolerance style as loadTechGates).
  Future<Map<String, dynamic>?> loadDailyTasks(String settlementId) async {
    try {
      final row = await supabase
          .from('settlements')
          .select('daily_tasks')
          .eq('id', settlementId)
          .single();
      return (row['daily_tasks'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDailyTasks(
    String settlementId,
    Map<String, dynamic> json,
  ) async {
    try {
      await supabase
          .from('settlements')
          .update({'daily_tasks': json})
          .eq('id', settlementId);
    } catch (_) {
      // Pre-migration: progress just isn't persisted yet.
    }
  }

  // ── Savers ────────────────────────────────────────────────
  Future<void> saveResources(ResourceModel r) async {
    try {
      await supabase.from('resources').upsert(r.toMap());
    } catch (_) {
      try {
        // Fallback: omit the gold column if it doesn't exist yet (pre-migration).
        await supabase.from('resources').upsert({
          'settlement_id': r.settlementId,
          'wood': r.wood,
          'stone': r.stone,
          'fish': r.goods['fish'] ?? 0.0,
          'fur': r.goods['fur'] ?? 0.0,
          'last_updated_at': r.lastUpdatedAt.toIso8601String(),
        });
      } catch (_) {
        // Fallback: omit goods columns too if they don't exist yet either.
        // Core resource amounts and lastUpdatedAt are always saved so offline
        // production works even without running the SQL column migrations.
        await supabase.from('resources').upsert({
          'settlement_id': r.settlementId,
          'wood': r.wood,
          'stone': r.stone,
          'last_updated_at': r.lastUpdatedAt.toIso8601String(),
        });
      }
    }
  }

  Future<void> saveEnergy(EnergyModel e) async {
    await supabase.from('energy_state').upsert(e.toMap());
  }

  /// Upserts [buildings] in ONE request.
  ///
  /// This was a sequential `await` per building — and a road is one row PER
  /// GRID CELL (`road` is 1x1, maxCount 0), so a settlement with its buildings
  /// wired up holds 200+ rows, not the ~16 you'd guess from the build menu.
  /// At 5s ticks and a phone's ~80ms round trip, that loop took LONGER than
  /// the tick interval: cycles overlapped forever and the radio never idled.
  /// Batching turns 200 requests into one.
  ///
  /// See SettlementController._persist for the other half of the fix — not
  /// sending unchanged rows in the first place.
  Future<void> saveBuildings(List<PlacedBuilding> buildings) async {
    if (buildings.isEmpty) return;
    final rows = buildings.map((b) => b.toMap()).toList();
    await supabase.from('placed_buildings').upsert(rows);
  }

  Future<void> saveSettlement(SettlementModel s) async {
    try {
      await supabase.from('settlements').upsert(s.toMap());
    } catch (_) {
      // Fallback: omit the crafting columns if migration 0011 hasn't run yet.
      // Postgrest rejects the WHOLE row over one unknown column, so without
      // this a pre-0011 profile couldn't save its era or hall level either —
      // the same failure mode that `healing_until` caused for creatures.
      // Losing the craft job costs a Workshop its progress; losing this write
      // would stall the settlement itself.
      await supabase.from('settlements').upsert({
        'id': s.id,
        'user_id': s.userId,
        'name': s.name,
        'era_index': s.eraIndex,
        'main_building_level': s.mainBuildingLevel,
      });
    }
  }

  Future<void> moveBuilding(String buildingId, int newX, int newY) async {
    await supabase
        .from('placed_buildings')
        .update({'grid_x': newX, 'grid_y': newY})
        .eq('id', buildingId);
  }

  Future<void> setBuildingPaused(String buildingId, bool paused) async {
    await supabase
        .from('placed_buildings')
        .update({'is_paused': paused})
        .eq('id', buildingId);
  }

  Future<void> deleteBuilding(String buildingId) async {
    await supabase.from('placed_buildings').delete().eq('id', buildingId);
  }

  // ── Place a new building ──────────────────────────────────
  Future<PlacedBuilding> placeBuilding({
    required String settlementId,
    required String typeId,
    required int x,
    required int y,
    bool isQueued = false,
  }) async {
    final def = kBuildingDefs[typeId]!;
    final row = await supabase
        .from('placed_buildings')
        .insert({
          'settlement_id': settlementId,
          'building_type_id': typeId,
          'grid_x': x,
          'grid_y': y,
          'construction_seconds_required': def.constructionSeconds,
          'construction_seconds_built': 0,
          'is_complete': def.constructionSeconds == 0,
          'is_queued': isQueued,
        })
        .select()
        .single();
    return PlacedBuilding.fromMap(row);
  }

  // ── Reset ─────────────────────────────────────────────────
  /// Wipes EVERYTHING this account has played back to a first-launch state:
  /// buildings, resources, energy, research, the whole creature collection,
  /// saved teams, breeding jobs, expeditions, spot depletion, and the
  /// profile's region progress/intro step. Afterwards the account is
  /// indistinguishable from one that has just signed up — including the intro
  /// chain and its jumpstart.
  ///
  /// Deliberately NOT touched: the `*_defs` content tables (buildings, techs,
  /// eras, areas, species, abilities). Those are authored game content shared
  /// by every player, not this account's progress — wiping them on a personal
  /// reset would delete the game itself.
  ///
  /// Kept in sync with [getOrCreate] by hand: any change to what a new account
  /// starts with must be mirrored in both.
  ///
  /// [devFloat] keeps a DEV account stocked across a reset (user 2026-07-26:
  /// "wenn ich auf plus Gold/holz/stein drücke, will ich, dass dies bleibt").
  /// Resetting is something a dev does constantly while testing, and having to
  /// re-press the grant button every single time is friction with no upside.
  /// It only ever RAISES the starting bill to [kDevResetFloat], so a normal
  /// account (devFloat false) is byte-for-byte the first-launch state.
  Future<void> resetSettlement(
    String settlementId,
    String userId, {
    bool devFloat = false,
  }) async {
    final now = DateTime.now().toUtc();
    double floor(double startingBill) =>
        devFloat ? math.max(startingBill, kDevResetFloat) : startingBill;

    await Future.wait([
      supabase
          .from('placed_buildings')
          .delete()
          .eq('settlement_id', settlementId),
      supabase
          .from('research_unlocks')
          .delete()
          .eq('settlement_id', settlementId),
      // Everything below is keyed by user, not settlement.
      supabase.from('creatures').delete().eq('user_id', userId),
      _deleteTolerant('breeding_jobs', 'user_id', userId),
      _deleteTolerant('expeditions', 'user_id', userId),
      _deleteTolerant('resource_spot_states', 'user_id', userId),
      // Teams reference creature ids that are being wiped above — a surviving
      // team would name monsters this profile no longer has.
      _deleteTolerant('saved_teams', 'user_id', userId),
    ]);

    await Future.wait([
      saveResources(
        ResourceModel(
          settlementId: settlementId,
          // Keep in sync with getOrCreate's starting bill above.
          wood: floor(750),
          stone: floor(300),
          gold: floor(0),
          goods: const {
            'fish': kJumpstartGiftFish,
            'fur': kJumpstartGiftFur,
          },
          lastUpdatedAt: now,
        ),
      ),
      saveEnergy(
        EnergyModel(
          settlementId: settlementId,
          currentEnergy: 80,
          lastUpdatedAt: now,
        ),
      ),
      _resetSettlementRow(settlementId),
      _resetProfileRow(userId),
    ]);

    await supabase.from('placed_buildings').insert({
      'settlement_id': settlementId,
      'building_type_id': 'castle',
      'grid_x': kMainHallStartX,
      'grid_y': kMainHallStartY,
      'construction_seconds_required': 0,
      'construction_seconds_built': 0,
      'is_complete': true,
    });
  }

  /// Delete that tolerates the table not existing yet — the expedition/gate
  /// tables arrive with migrations 0001/0004, and a reset must still work on a
  /// deployment where those haven't been applied.
  Future<void> _deleteTolerant(String table, String column, String value) async {
    try {
      await supabase.from(table).delete().eq(column, value);
    } catch (e) {
      debugPrint('[SettlementService] reset: skipped $table ($e)');
    }
  }

  /// Back to a freshly-created profile: the intro chain restarts from step 0
  /// (so the jumpstart is on again) and BP is the same gift [getOrCreate]
  /// hands a brand-new account — not 0, or the first research would be
  /// unreachable exactly as it is for a new player without the gift.
  Future<void> _resetProfileRow(String userId) async {
    Future<void> write(Map<String, dynamic> patch) =>
        supabase.from('profiles').upsert({'id': userId, ...patch});
    try {
      await write({
        'dungeon_max_stage': 1,
        'expansions_unlocked': 0,
        'battles_cleared': 0,
        'intro_step': IntroStep.pickStarter.index,
      });
    } catch (_) {
      // Pre-migration deployment: drop the columns that may not exist yet
      // rather than losing the whole profile reset.
      await write({'dungeon_max_stage': 1});
    }
  }

  Future<void> _resetSettlementRow(String settlementId) async {
    try {
      await supabase
          .from('settlements')
          .update({
            'era_index': 1,
            'main_building_level': 1,
            // The Workshop and the bag, cleared: a "first launch" profile that
            // still held potions from the last run wouldn't be one.
            'active_craft_id': null,
            'craft_seconds_built': 0,
            'items': <String, int>{},
          })
          .eq('id', settlementId);
    } catch (_) {
      // Fallback: omit the crafting columns if migration 0011 hasn't run.
      await supabase
          .from('settlements')
          .update({'era_index': 1, 'main_building_level': 1})
          .eq('id', settlementId);
    }
  }

  // loadResearch() is gone (user 2026-07-26) with the feature-unlock system it
  // fed. `research_unlocks` is still WIPED on reset — the rows exist in old
  // databases and a reset that left them behind would be lying about being a
  // first-launch state — but nothing reads them any more.

  /// Tech-gate clears (mini-dungeons beaten). Tolerates the table not existing
  /// yet (pre-migration) — returns empty so the rest of load() still works.
  Future<Map<String, int>> loadProfile(String userId) async {
    final row = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) {
      return {
        'dungeon_max_stage': 1,
        'expansions_unlocked': 0,
        'battles_cleared': 0,
      };
    }
    return {
      // Highest dungeon stage unlocked so far (permanent progression — see
      // kMaxDungeonStage). Tolerates the column not existing yet.
      //
      // `bp` and `level` used to be read here too. The columns may well still
      // exist on the profile row (migration 0010 drops them); nothing reads
      // them any more — the player level was itself only ever derived from BP
      // and was never displayed or gated on anywhere.
      'dungeon_max_stage': (row['dungeon_max_stage'] as num?)?.toInt() ?? 1,
      // Expansion unlocks earned from map "expansion points" — the Building
      // Plot reward count (see SettlementController.buildPlotLimit).
      'expansions_unlocked':
          (row['expansions_unlocked'] as num?)?.toInt() ?? 0,
      // Linear-path progress: campaign battles won so far. Drives party size
      // (partySizeForBattle) and, later, map-milestone unlocks. Tolerates the
      // column not existing yet (migration 0019).
      'battles_cleared': (row['battles_cleared'] as num?)?.toInt() ?? 0,
    };
  }

  /// A write failed only because the column/table isn't migrated yet — safe to
  /// ignore (the in-memory value still holds this session). A REAL or transient
  /// error (network, RLS, timeout) must NOT match, so callers rethrow it and the
  /// UI can flag the save as failed instead of losing progress silently.
  static bool isMissingSchema(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('does not exist') ||
        s.contains('could not find') ||
        s.contains('pgrst204') || // schema cache miss (unknown column)
        s.contains('42703') || // undefined_column
        s.contains('42p01'); // undefined_table
  }

  /// Persists a newly-unlocked dungeon stage (clearing stage N's boss
  /// unlocks N+1). Rethrows anything that isn't a pre-migration schema gap so a
  /// dropped write surfaces instead of vanishing.
  Future<void> saveDungeonMaxStage(String userId, int stage) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'dungeon_max_stage': stage,
      });
    } catch (e) {
      if (!isMissingSchema(e)) rethrow;
    }
  }

  /// Persists the earned expansion-unlock count (each map expansion point grants
  /// one — see SettlementController.unlockExpansion).
  Future<void> saveExpansionsUnlocked(String userId, int count) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'expansions_unlocked': count,
      });
    } catch (e) {
      if (!isMissingSchema(e)) rethrow;
    }
  }

  /// Persists the linear-path progress (campaign battles won — see
  /// SettlementController.advanceBattlesCleared).
  Future<void> saveBattlesCleared(String userId, int count) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'battles_cleared': count,
      });
    } catch (e) {
      if (!isMissingSchema(e)) rethrow;
    }
  }

  // Dev Mode gate. Own method rather than folding into loadProfile (which
  // returns Map<String,int>) since is_dev is a bool on a column that may not
  // exist yet on older deployments — tolerate that the same way saveResources
  // etc. tolerate pre-migration columns, just via a read-side default here.
  Future<bool> loadIsDev(String userId) async {
    try {
      final row = await supabase
          .from('profiles')
          .select('is_dev')
          .eq('id', userId)
          .maybeSingle();
      return row?['is_dev'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Intro / jumpstart progress ───────────────────────────
  // Own methods rather than folding into loadProfile for the same reason
  // loadIsDev is separate: the column may not exist yet (migration
  // 0005_intro_step.sql). A pre-migration client reads `done` — better a
  // veteran-style silent start than trapping someone in a step whose progress
  // can never be written back.

  Future<int> loadIntroStep(String userId) async {
    try {
      final row = await supabase
          .from('profiles')
          .select('intro_step')
          .eq('id', userId)
          .maybeSingle();
      return (row?['intro_step'] as num?)?.toInt() ?? IntroStep.done.index;
    } catch (_) {
      return IntroStep.done.index;
    }
  }

  Future<void> saveIntroStep(String userId, int step) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'intro_step': step,
      });
    } catch (_) {
      // Column not migrated yet — in-memory value still holds this session.
    }
  }

}
