import 'package:flutter/foundation.dart';

import '../../../core/supabase/supabase_client.dart';

// Live, dev-tunable knobs for the damage formula (user request 2026-07-17:
// "gib mir die Möglichkeit, power der Angriffe im Vergleich zu der Defense zu
// verändern"). A single global row — this is a game-wide balance dial, not a
// per-account setting — read by CombatEngine on every hit and edited in the
// Dev Mode ▸ Balance tab, which also renders the exact formula these feed.
//
// Loads with a graceful fallback: if the combat_tuning table doesn't exist
// yet (migration 0012 not applied), the defaults below stand and saves are a
// silent no-op, so the app never breaks on a pre-migration schema.
class CombatTuning extends ChangeNotifier {
  static final CombatTuning _instance = CombatTuning._();
  factory CombatTuning() => _instance;
  CombatTuning._();

  /// One row holds the whole config.
  static const _rowId = 'global';

  // ── Defaults (the previously-hardcoded calibration) ─────────
  /// Global damage multiplier — the overall "how hard does everything hit"
  /// dial. Was CombatEngine.damageScale (docs/balancing.md §4).
  static const double kDefaultDamageScale = 0.55;

  /// How strongly DEFENSE mitigates, via the atk/(atk + def·w) term:
  /// 1.0 = the calibrated default, >1 = defense matters more (softer hits),
  /// <1 = defense matters less (attack dominates). This is the "attack power
  /// vs. defense" balance the dev tool exposes.
  static const double kDefaultDefenseWeight = 1.0;

  double damageScale = kDefaultDamageScale;
  double defenseWeight = kDefaultDefenseWeight;

  /// Reads the global row; keeps defaults on any error (missing table,
  /// offline, no row yet). Called once from the settlement load path.
  Future<void> load() async {
    try {
      final row = await supabase
          .from('combat_tuning')
          .select()
          .eq('id', _rowId)
          .maybeSingle();
      if (row != null) {
        damageScale =
            (row['damage_scale'] as num?)?.toDouble() ?? kDefaultDamageScale;
        defenseWeight =
            (row['defense_weight'] as num?)?.toDouble() ??
            kDefaultDefenseWeight;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[CombatTuning] load skipped ($e) — using defaults');
    }
  }

  /// Applies new values immediately (combat reads the statics live) and
  /// persists them. Returns null on success or a message if the write failed
  /// (e.g. the table isn't there yet) — the in-memory change still stands for
  /// the session so the simulator reflects it.
  Future<String?> save({
    required double damageScale,
    required double defenseWeight,
  }) async {
    this.damageScale = damageScale;
    this.defenseWeight = defenseWeight;
    notifyListeners();
    try {
      await supabase.from('combat_tuning').upsert({
        'id': _rowId,
        'damage_scale': damageScale,
        'defense_weight': defenseWeight,
      });
      return null;
    } catch (e) {
      return 'Applied for this session, but not saved: $e';
    }
  }

  /// Back to the calibrated defaults (dev "reset" button).
  Future<String?> resetToDefaults() =>
      save(damageScale: kDefaultDamageScale, defenseWeight: kDefaultDefenseWeight);
}
