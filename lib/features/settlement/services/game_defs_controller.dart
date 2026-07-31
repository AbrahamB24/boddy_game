import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/path_node.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/gather_defs.dart';
import '../data/item_definitions.dart';
import 'game_defs_service.dart';

// Singleton, same ChangeNotifier pattern as SettlementController. Loads
// building/tech/era/area defs from Supabase and updates the live k*Defs maps'
// *contents* in place (not the map reference) so every existing bare
// `kBuildingDefs` reference across the app picks up the change
// automatically, and subscribes to realtime changes so every connected
// client sees dev-mode edits live — no restart. SettlementController chains
// this controller's notifications into its own (see settlement_controller.dart),
// so every screen already listening to SettlementController picks up def
// changes with no new wiring.
//
// ── THE DB *OVERRIDES* THE BUNDLED CONTENT, IT DOES NOT REPLACE IT ──
// This used to clear the map and refill it from the DB whenever the table was
// non-empty. That destroyed the game the first time anyone edited a single
// def: uploading a PNG for `main_hall` wrote ONE row, so the roster became
// exactly that one building, and every placed woodland camp / quarry / hut
// silently stopped existing (`kBuildingDefs[b.buildingTypeId]` → null →
// skipped everywhere). The rows in `placed_buildings` were never touched — the
// buildings looked deleted purely because their TYPE had vanished.
//
// So: bundled fallbacks are the base, DB rows override per id. Editing one def
// now affects one def.
//
// ── DELETING A BUNDLED DEF: TOMBSTONES (user 2026-07-31) ──
// "ich kann von dir erstellte gebäude wie z.b primitive wood camp nicht
//  löschen, das möchte ich aber können"
//
// Absence is how the BASE state is expressed here, so deleting a row could only
// ever remove an override — the generated def came back on the next load. A
// bundled def is therefore retired instead of deleted: a row with `retired`
// true, which [_merge] subtracts. Custom ids (not in the fallback) still delete
// outright, because for them absence really does mean gone.
//
// Retired ids are kept in [retiredBuildingIds] so Dev Mode can list them and put
// one back — a destructive action nobody can undo is one nobody dares use.
class GameDefsController extends ChangeNotifier {
  static final GameDefsController _instance = GameDefsController._();
  factory GameDefsController() => _instance;
  GameDefsController._();

  final _svc = GameDefsService();
  RealtimeChannel? _channel;
  bool _loading = false;
  bool _reloadPending = false;

  /// Rebuilds [live] as `fallback` + the DB rows on top, in place.
  ///
  /// PUBLIC so the merge rule can be tested against the real function rather
  /// than a copy of it in a test file — this is the code that once ate the whole
  /// roster, and since 2026-07-31 it also decides what a tombstone removes.
  ///
  /// Note there is no `if (rows.isNotEmpty)` guard: it isn't needed (an empty
  /// table just leaves the fallback), and having one would ALSO mean a table
  /// you deliberately emptied never took effect.
  /// Ids whose DB row is a tombstone, filled by the last [_merge] of the
  /// building table. Dev Mode's roster reads it to offer them back.
  static final Set<String> retiredBuildingIds = <String>{};

  static void mergeDefRows<T>(
    Map<String, T> live,
    Map<String, T> fallback,
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) fromRow, {
    /// Collects the ids this merge subtracted. Only the building table has a
    /// `retired` column today; for every other table the flag is simply absent,
    /// so the check costs nothing and the day a second table needs it, it works.
    Set<String>? retired,
  }) {
    retired?.clear();
    live
      ..clear()
      ..addAll(fallback);
    for (final row in rows) {
      final id = row['id'] as String;
      // A TOMBSTONE subtracts — including a bundled fallback, which is the whole
      // point of it. Nothing is parsed from the row: a retired def may well be a
      // shape the current code no longer understands.
      if (row['retired'] == true) {
        live.remove(id);
        retired?.add(id);
        continue;
      }
      live[id] = fromRow(row);
    }
  }

  /// Writes a def and refreshes the live maps from the DB.
  ///
  /// Go through these rather than GameDefsService directly. An upsert alone
  /// only changes the DB — the in-memory k*Defs maps refresh on realtime, so a
  /// bare write left the editor showing the OLD value until realtime happened
  /// to fire. If the table isn't in the `supabase_realtime` publication it
  /// never fires at all, and every edit looks like it silently reverted.
  /// Reloading here makes a save mean the same thing whatever realtime does.
  Future<void> saveBuildingDef(BuildingDef def) =>
      _saveThenReload(() => _svc.upsertBuildingDef(def));
  Future<void> saveEraDef(EraDef def) =>
      _saveThenReload(() => _svc.upsertEraDef(def));
  Future<void> savePathNode(PathNode node) =>
      _saveThenReload(() => _svc.upsertPathNode(node));

  /// Writes SEVERAL path nodes and reloads ONCE (user 2026-07-30, with the
  /// per-era re-roll).
  ///
  /// [savePathNode] reloads every def table after each write, which is right for
  /// one edit and absurd for nineteen: a region's re-roll would have pulled the
  /// whole content set down nineteen times over.
  Future<void> savePathNodes(Iterable<PathNode> nodes) =>
      _saveThenReload(() async {
        for (final n in nodes) {
          await _svc.upsertPathNode(n);
        }
      });
  Future<void> saveItemDef(ItemDef def) =>
      _saveThenReload(() => _svc.upsertItemDef(def));
  Future<void> saveGatherDef(ResourceGatherDef def) =>
      _saveThenReload(() => _svc.upsertGatherDef(def));

  /// Removes a building from the game for good.
  ///
  /// A BUNDLED def is retired (tombstoned) rather than deleted — see the note on
  /// this class. A custom id is deleted outright: there is no fallback waiting
  /// to take its place, so the row IS the def.
  Future<void> deleteBuildingDef(String id) => _saveThenReload(() {
    final def = kBuildingDefs[id] ?? kFallbackBuildingDefs[id];
    if (kFallbackBuildingDefs.containsKey(id) && def != null) {
      return _svc.retireBuildingDef(def);
    }
    return _svc.deleteBuildingDef(id);
  });

  /// Puts a retired building back. The tombstone row is simply deleted, which
  /// leaves the bundled fallback to come through the merge again — exactly what
  /// used to happen by accident, now on purpose.
  Future<void> restoreBuildingDef(String id) =>
      _saveThenReload(() => _svc.deleteBuildingDef(id));
  Future<void> deleteEraDef(String id) =>
      _saveThenReload(() => _svc.deleteEraDef(id));
  Future<void> deletePathNode(String id) =>
      _saveThenReload(() => _svc.deletePathNode(id));
  Future<void> deleteItemDef(String id) =>
      _saveThenReload(() => _svc.deleteItemDef(id));

  Future<void> _saveThenReload(Future<void> Function() write) async {
    await write(); // throws on failure — the forms surface it
    await load();
  }

  Future<void> load() async {
    // A reload asked for mid-load isn't dropped, it's deferred: the write that
    // triggered it may well have landed after this load's SELECT, and silently
    // skipping it is how a saved edit disappears until the next restart.
    if (_loading) {
      _reloadPending = true;
      return;
    }
    _loading = true;
    try {
      mergeDefRows(
        kBuildingDefs,
        kFallbackBuildingDefs,
        await _svc.loadBuildingDefRows(),
        BuildingDef.fromDefRow,
        retired: retiredBuildingIds,
      );
      mergeDefRows(
        kEraDefs,
        kFallbackEraDefs,
        await _svc.loadEraDefRows(),
        EraDef.fromDefRow,
      );
      mergeDefRows(
        kAreaDefs,
        {for (final a in kFallbackAreaDefs) a.id: a},
        await _svc.loadAreaDefRows(),
        AreaDef.fromDefRow,
      );
      mergeDefRows(
        kPathNodes,
        kFallbackPathNodes,
        await _svc.loadPathNodeRows(),
        PathNode.fromDefRow,
      );
      mergeDefRows(
        kItemDefs,
        kFallbackItemDefs,
        await _svc.loadItemDefRows(),
        ItemDef.fromDefRow,
      );
      mergeDefRows(
        kGatherDefs,
        kFallbackGatherDefs,
        await _svc.loadGatherDefRows(),
        ResourceGatherDef.fromDefRow,
      );
    } catch (e) {
      debugPrint(
        '[GameDefsController] load failed, keeping bundled fallback defs: $e',
      );
    }
    _loading = false;
    notifyListeners();
    _subscribeRealtime();
    if (_reloadPending) {
      _reloadPending = false;
      await load();
    }
  }

  void _subscribeRealtime() {
    if (_channel != null) return; // already subscribed
    _channel = supabase.channel('game_defs_changes')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'building_defs',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'era_defs',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'area_defs',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'path_nodes',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'item_defs',
        callback: (_) => load(),
      )
      ..subscribe();
  }

}
