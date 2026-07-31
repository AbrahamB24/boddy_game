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
      final abilityRows = await _svc.loadAbilityDefRows();
      kAbilityDefs
        ..clear()
        ..addAll({
          for (final row in abilityRows)
            row['id'] as String: AbilityDef.fromDefRow(row),
        });

      final speciesRows = await _svc.loadSpeciesDefRows();
      kSpeciesDefs
        ..clear()
        ..addAll({
          for (final row in speciesRows)
            row['id'] as String: SpeciesDef.fromDefRow(row),
        });

      // Global species-balance config (per-rarity budgets + attribute caps).
      final balance = await _svc.loadSpeciesBalance();
      if (balance != null) kSpeciesBalance = balance;

      // Global XP config (curve + passive/training rates + era multiplier).
      final xp = await _svc.loadXpBalance();
      if (xp != null) kXpBalance = xp;

      // Global healing config (treatment time + goods per HP + K.O. factor).
      final heal = await _svc.loadHealBalance();
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
