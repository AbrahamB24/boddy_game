import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/supabase/supabase_client.dart';
import 'player_portrait.dart';

/// Reads and writes `profiles.avatar_species` (migration 0070): which monster
/// portrait a player uses.
///
/// Other players are looked up BY USERNAME (that is what every list in the app
/// has to hand, and the username is unique), batched: everything asked for within
/// a few milliseconds goes out as one query. Never throws: a player with no
/// portrait, a failed read, or a database without migration 0070 simply leave the
/// plain letter avatar in place.
class AvatarService extends ChangeNotifier {
  AvatarService._();
  static final AvatarService instance = AvatarService._();

  /// lower-cased username -> portrait (null inside the map = "has none").
  final Map<String, PortraitRef?> _known = {};
  final Map<String, Completer<PortraitRef?>> _waiting = {};
  final Map<String, String> _spelling = {}; // lower-cased -> as given
  Timer? _flush;
  bool _unavailable = false;

  static String _k(String name) => name.trim().toLowerCase();

  /// What is known right now: [known] false = not asked yet.
  ({bool known, PortraitRef? ref}) peek(String username) {
    final k = _k(username);
    return (known: _known.containsKey(k), ref: _known[k]);
  }

  Future<PortraitRef?> fetch(String username) {
    final k = _k(username);
    if (k.isEmpty || _unavailable) return Future.value(null);
    if (_known.containsKey(k)) return Future.value(_known[k]);
    _spelling[k] = username.trim();
    final c = _waiting.putIfAbsent(k, () => Completer<PortraitRef?>());
    _flush ??= Timer(const Duration(milliseconds: 40), _send);
    return c.future;
  }

  Future<void> _send() async {
    _flush = null;
    final batch = Map<String, Completer<PortraitRef?>>.of(_waiting);
    _waiting.clear();
    if (batch.isEmpty) return;
    try {
      // The names the lists hold come straight from `profiles`, so their
      // spelling matches the stored username exactly.
      final rows = await supabase
          .from('profiles')
          .select('username, avatar_species')
          .inFilter('username', [
            for (final k in batch.keys) _spelling[k] ?? k,
          ]);
      final found = <String, PortraitRef?>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final name = r['username'] as String?;
        if (name != null) {
          found[_k(name)] = PortraitRef.parse(r['avatar_species']);
        }
      }
      for (final e in batch.entries) {
        _known[e.key] = found[e.key];
        e.value.complete(found[e.key]);
      }
      notifyListeners();
    } catch (e) {
      // Most likely the column is not there yet: stop asking.
      debugPrint('[AvatarService] read failed: $e');
      _unavailable = true;
      for (final c in batch.values) {
        c.complete(null);
      }
    }
  }

  // ── my own ──────────────────────────────────────────────────────────────

  String get _me => supabase.auth.currentUser!.id;

  /// My portrait, or null when I have not picked one.
  Future<PortraitRef?> loadMine() async {
    try {
      final row = await supabase
          .from('profiles')
          .select('username, avatar_species')
          .eq('id', _me)
          .maybeSingle();
      final ref = PortraitRef.parse(row?['avatar_species']);
      final name = row?['username'] as String?;
      if (name != null) {
        _known[_k(name)] = ref;
        notifyListeners();
      }
      return ref;
    } catch (e) {
      debugPrint('[AvatarService] loadMine failed: $e');
      return null;
    }
  }

  /// Saves my portrait (null = back to the letter). Returns false when the
  /// database refused (no migration yet, offline ...).
  Future<bool> saveMine(PortraitRef? ref, {String? username}) async {
    try {
      await supabase.from('profiles').upsert({
        'id': _me,
        'avatar_species': ref?.code,
      });
      if (username != null) _known[_k(username)] = ref;
      _unavailable = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AvatarService] save failed: $e');
      return false;
    }
  }
}
