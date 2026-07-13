import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/tech_definitions.dart';
import 'game_defs_service.dart';

// Singleton, same ChangeNotifier pattern as SettlementController. Loads
// building/tech defs from Supabase, overwrites kBuildingDefs/kTechDefs'
// *contents* in place (not the map reference) so every existing bare
// `kBuildingDefs`/`kTechDefs` reference across the app picks up the change
// automatically, and subscribes to realtime changes so every connected
// client sees dev-mode edits live — no restart. SettlementController chains
// this controller's notifications into its own (see settlement_controller.dart),
// so every screen already listening to SettlementController picks up def
// changes with no new wiring.
class GameDefsController extends ChangeNotifier {
  static final GameDefsController _instance = GameDefsController._();
  factory GameDefsController() => _instance;
  GameDefsController._();

  final _svc = GameDefsService();
  RealtimeChannel? _channel;
  bool _loading = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      final buildingRows = await _svc.loadBuildingDefRows();
      if (buildingRows.isNotEmpty) {
        kBuildingDefs
          ..clear()
          ..addAll({
            for (final row in buildingRows)
              row['id'] as String: BuildingDef.fromDefRow(row),
          });
      }

      final techRows = await _svc.loadTechDefRows();
      if (techRows.isNotEmpty) {
        final layout = _computeLayout(techRows);
        kTechDefs
          ..clear()
          ..addAll({
            for (final row in techRows)
              row['id'] as String: TechDef.fromDefRow(
                row,
                col: layout[row['id']]!.$1,
                row: layout[row['id']]!.$2,
              ),
          });
      }

      final eraRows = await _svc.loadEraDefRows();
      if (eraRows.isNotEmpty) {
        kEraDefs
          ..clear()
          ..addAll({
            for (final row in eraRows)
              row['id'] as String: EraDef.fromDefRow(row),
          });
      }
    } catch (e) {
      debugPrint(
        '[GameDefsController] load failed, keeping bundled fallback defs: $e',
      );
    }
    _loading = false;
    notifyListeners();
    _subscribeRealtime();
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
        table: 'tech_defs',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'era_defs',
        callback: (_) => load(),
      )
      ..subscribe();
  }

  // ── Tech tree auto-layout ──────────────────────────────────
  // Grouped by era first — prerequisites never cross era boundaries (only
  // the current era's tech is ever researchable, see TechDef.eraId), so each
  // era gets its own independent column/row space starting at (0,0).
  // research_screen.dart only ever renders the current era's subset, so this
  // just needs to never collide across groups, which grouping guarantees.
  Map<String, (int, int)> _computeLayout(List<Map<String, dynamic>> rows) {
    final byEra = <String?, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      byEra.putIfAbsent(row['era_id'] as String?, () => []).add(row);
    }
    final result = <String, (int, int)>{};
    for (final group in byEra.values) {
      result.addAll(_computeLayoutForGroup(group));
    }
    return result;
  }

  // col = longest-path depth from any root (no prerequisites = col 0).
  // Within a column, row is assigned sequentially (0, 1, 2, ...) ordered by
  // the average row of each tech's prerequisites — never negative, never
  // array-indexed, so research_screen.dart's canvas (sized from actual
  // col/row values, not a fixed grid) can never crash regardless of tree
  // shape. A tech that would introduce a cycle is treated as a root (logged,
  // not dropped) rather than crashing the whole layout.
  Map<String, (int, int)> _computeLayoutForGroup(
    List<Map<String, dynamic>> rows,
  ) {
    final prereqsById = <String, List<String>>{
      for (final row in rows)
        row['id'] as String: ((row['prerequisites'] as List?) ?? const [])
            .cast<String>(),
    };

    final col = <String, int>{};
    final visiting = <String>{};

    int colOf(String id) {
      if (col.containsKey(id)) return col[id]!;
      if (!prereqsById.containsKey(id)) return 0;
      if (visiting.contains(id)) {
        debugPrint(
          '[GameDefsController] cycle detected at tech "$id" — treating as root',
        );
        return 0;
      }
      visiting.add(id);
      int depth = 0;
      for (final p in prereqsById[id]!) {
        if (!prereqsById.containsKey(p)) continue; // dangling prerequisite id
        final pc = colOf(p);
        if (pc + 1 > depth) depth = pc + 1;
      }
      visiting.remove(id);
      col[id] = depth;
      return depth;
    }

    final ids = prereqsById.keys.toList()..sort();
    for (final id in ids) {
      colOf(id);
    }

    final byCol = <int, List<String>>{};
    for (final id in ids) {
      byCol.putIfAbsent(col[id]!, () => []).add(id);
    }

    final row = <String, int>{};
    for (final c in (byCol.keys.toList()..sort())) {
      final idsInCol = byCol[c]!;
      final preferred = <String, double>{
        for (final id in idsInCol) id: _preferredRow(id, prereqsById, row),
      };
      idsInCol.sort((a, b) {
        final cmp = preferred[a]!.compareTo(preferred[b]!);
        return cmp != 0 ? cmp : a.compareTo(b);
      });
      for (var i = 0; i < idsInCol.length; i++) {
        row[idsInCol[i]] = i;
      }
    }

    return {for (final id in ids) id: (col[id]!, row[id]!)};
  }

  double _preferredRow(
    String id,
    Map<String, List<String>> prereqsById,
    Map<String, int> assignedRows,
  ) {
    final prereqRows = prereqsById[id]!
        .where(assignedRows.containsKey)
        .map((p) => assignedRows[p]!);
    if (prereqRows.isEmpty) return 0.0;
    return prereqRows.reduce((a, b) => a + b) / prereqRows.length;
  }
}
