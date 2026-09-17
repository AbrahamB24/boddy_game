import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/ability_def.dart';
import '../models/heal_balance.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';
import '../models/xp_balance.dart';
import 'creature_defs_service.dart';

// Singleton, mirroring GameDefsController: loads species/ability defs from
// Supabase, overwrites kSpeciesDefs/kAbilityDefs' CONTENTS in place (so bare
// references pick up changes) and subscribes to realtime so dev-mode edits
// appear live on every client. Unlike GameDefsController there is no bundled
// fallback — the maps are simply empty until content exists.
class CreatureDefsController extends ChangeNotifier {
  static final CreatureDefsController _instance = CreatureDefsController._();
  factory CreatureDefsController() => _instance;
  CreatureDefsController._();

  final _svc = CreatureDefsService();
  RealtimeChannel? _channel;
  bool _loading = false;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    try {
      // PARALLEL, not sequential (found 2026-09-12 auditing "loading feels
      // slow") — five independent rows/tables used to await one after
      // another, each its own network round trip. Starting every fetch
      // BEFORE awaiting any of them (an async call runs up to its own first
      // await the moment it's invoked) turns that into the time of the
      // slowest one instead of the sum of all five — this is one of the
      // branches [SettlementController.load] itself awaits, so that sum
      // landed directly on the loading screen's own duration.
      final abilityRowsF = _svc.loadAbilityDefRows();
      final speciesRowsF = _svc.loadSpeciesDefRows();
      final balanceF = _svc.loadSpeciesBalance();
      final xpF = _svc.loadXpBalance();
      final healF = _svc.loadHealBalance();

      final abilityRows = await abilityRowsF;
      kAbilityDefs
        ..clear()
        ..addAll({
          for (final row in abilityRows)
            row['id'] as String: AbilityDef.fromDefRow(row),
        });

      final speciesRows = await speciesRowsF;
      kSpeciesDefs
        ..clear()
        ..addAll({
          for (final row in speciesRows)
            row['id'] as String: SpeciesDef.fromDefRow(row),
        });

      // Global species-balance config (per-rarity budgets + attribute caps).
      final balance = await balanceF;
      if (balance != null) kSpeciesBalance = balance;

      // Global XP config (curve + passive/training rates + era multiplier).
      final xp = await xpF;
      if (xp != null) kXpBalance = xp;

      // Global healing config (treatment time + goods per HP + K.O. factor).
      final heal = await healF;
      if (heal != null) kHealBalance = heal;
    } catch (e) {
      // Tables not migrated yet / offline: keep whatever is in the maps.
      debugPrint('[CreatureDefsController] load failed: $e');
    }
    _loading = false;
    notifyListeners();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    if (_channel != null) return; // already subscribed
    _channel = supabase.channel('creature_defs_changes')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'species_defs',
        callback: (_) => load(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'ability_defs',
        callback: (_) => load(),
      )
      ..subscribe();
  }
}
