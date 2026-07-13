import '../../../core/supabase/supabase_client.dart';
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
        'wood': 500.0,
        'stone': 300.0,
        'fish': 0.0,
        'fur': 0.0,
      }),
      supabase.from('energy_state').insert({
        'settlement_id': model.id,
        'current_energy': 80.0,
      }),
      supabase.from('placed_buildings').insert({
        'settlement_id': model.id,
        'building_type_id': 'main_hall',
        // Centered in the starting 12x12 buildable zone (main_hall is 3x3).
        'grid_x': kInitialPlotX + (kInitialPlotSize - 3) ~/ 2,
        'grid_y': kInitialPlotY + (kInitialPlotSize - 3) ~/ 2,
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

  Future<void> saveBuildings(List<PlacedBuilding> buildings) async {
    for (final b in buildings) {
      try {
        await supabase.from('placed_buildings').upsert(b.toMap());
      } catch (_) {
        // Fallback: omit laborers_assigned if that column doesn't exist yet
        // (pre-migration).
        final map = b.toMap()..remove('laborers_assigned');
        await supabase.from('placed_buildings').upsert(map);
      }
    }
  }

  Future<void> saveSettlement(SettlementModel s) async {
    try {
      await supabase.from('settlements').upsert(s.toMap());
    } catch (_) {
      // Fallback: omit the research-progress columns if they don't exist yet
      // (pre-migration) — era/hall level always save regardless.
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
  // Wipes buildings, resources, energy allocation and research back to a
  // fresh start. Deliberately leaves `profiles` (BP/level) untouched.
  Future<void> resetSettlement(String settlementId) async {
    final now = DateTime.now().toUtc();
    await Future.wait([
      supabase
          .from('placed_buildings')
          .delete()
          .eq('settlement_id', settlementId),
      supabase
          .from('research_unlocks')
          .delete()
          .eq('settlement_id', settlementId),
    ]);

    await Future.wait([
      saveResources(
        ResourceModel(
          settlementId: settlementId,
          wood: 500,
          stone: 300,
          gold: 0,
          goods: const {'fish': 0, 'fur': 0},
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
    ]);

    await supabase.from('placed_buildings').insert({
      'settlement_id': settlementId,
      'building_type_id': 'main_hall',
      'grid_x': kInitialPlotX + (kInitialPlotSize - 3) ~/ 2,
      'grid_y': kInitialPlotY + (kInitialPlotSize - 3) ~/ 2,
      'construction_seconds_required': 0,
      'construction_seconds_built': 0,
      'is_complete': true,
    });
  }

  Future<void> _resetSettlementRow(String settlementId) async {
    try {
      await supabase
          .from('settlements')
          .update({
            'era_index': 1,
            'main_building_level': 1,
            'active_research_id': null,
            'research_seconds_built': 0,
          })
          .eq('id', settlementId);
    } catch (_) {
      // Fallback: omit the research-progress columns if they don't exist yet.
      await supabase
          .from('settlements')
          .update({'era_index': 1, 'main_building_level': 1})
          .eq('id', settlementId);
    }
  }

  // ── Research ──────────────────────────────────────────────
  Future<Set<String>> loadResearch(String settlementId) async {
    final rows = await supabase
        .from('research_unlocks')
        .select('tech_id')
        .eq('settlement_id', settlementId);
    return (rows as List).map((r) => r['tech_id'] as String).toSet();
  }

  Future<void> unlockTech(String settlementId, String techId) async {
    await supabase.from('research_unlocks').insert({
      'settlement_id': settlementId,
      'tech_id': techId,
    });
  }

  // ── BP ───────────────────────────────────────────────────
  Future<int> addBp(String userId, int amount) async {
    final profile = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    final current = profile != null ? (profile['bp'] as num).toInt() : 0;
    final newBp = current + amount;
    final newLevel = bpToLevel(newBp);
    await supabase.from('profiles').upsert({
      'id': userId,
      'bp': newBp,
      'level': newLevel,
    });
    return newBp;
  }

  Future<Map<String, int>> loadProfile(String userId) async {
    final row = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (row == null) return {'bp': 0, 'level': 1, 'dungeon_max_stage': 1};
    return {
      'bp': (row['bp'] as num).toInt(),
      'level': (row['level'] as num).toInt(),
      // Highest dungeon stage unlocked so far (permanent progression — see
      // kMaxDungeonStage). Tolerates the column not existing yet.
      'dungeon_max_stage': (row['dungeon_max_stage'] as num?)?.toInt() ?? 1,
    };
  }

  /// Persists a newly-unlocked dungeon stage (clearing stage N's boss
  /// unlocks N+1 — see CreaturesController/DungeonMapScreen).
  Future<void> saveDungeonMaxStage(String userId, int stage) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'dungeon_max_stage': stage,
      });
    } catch (_) {
      // Column not migrated yet — in-memory value still holds this session.
    }
  }

  // Workout stats persisted on the profile: the daily-BP counter (survives
  // restarts, resets only at local midnight — see
  // SettlementController._resetDailyIfNeeded) plus the lifetime workout count
  // and the day-streak. Dates are 'YYYY-MM-DD' strings in the device's local
  // time. Tolerates the columns not existing yet on older deployments
  // (read-side default), mirroring loadIsDev.
  Future<
    ({
      int bpToday,
      String? bpDate,
      int completed,
      int streak,
      String? lastDate,
    })
  >
  loadWorkoutStats(String userId) async {
    try {
      final row = await supabase
          .from('profiles')
          .select(
            'workout_bp_today, workout_bp_date, workouts_completed, '
            'workout_streak, last_workout_date',
          )
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        return (
          bpToday: 0,
          bpDate: null,
          completed: 0,
          streak: 0,
          lastDate: null,
        );
      }
      return (
        bpToday: (row['workout_bp_today'] as num?)?.toInt() ?? 0,
        bpDate: row['workout_bp_date'] as String?,
        completed: (row['workouts_completed'] as num?)?.toInt() ?? 0,
        streak: (row['workout_streak'] as num?)?.toInt() ?? 0,
        lastDate: row['last_workout_date'] as String?,
      );
    } catch (_) {
      return (
        bpToday: 0,
        bpDate: null,
        completed: 0,
        streak: 0,
        lastDate: null,
      );
    }
  }

  Future<void> saveWorkoutStats(
    String userId, {
    required int bpToday,
    required String bpDate,
    required int completed,
    required int streak,
    required String lastDate,
  }) async {
    try {
      await supabase.from('profiles').upsert({
        'id': userId,
        'workout_bp_today': bpToday,
        'workout_bp_date': bpDate,
        'workouts_completed': completed,
        'workout_streak': streak,
        'last_workout_date': lastDate,
      });
    } catch (_) {
      // Columns not migrated yet — the in-memory values still hold for this
      // session; nothing else depends on the write succeeding.
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

  static int bpToLevel(int bp) {
    final thresholds = [0, 100, 350, 850, 1850, 3850, 7850, 15850];
    for (int i = thresholds.length - 1; i >= 0; i--) {
      if (bp >= thresholds[i]) return i + 1;
    }
    return 1;
  }
}
