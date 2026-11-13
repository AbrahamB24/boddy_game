import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/supabase/supabase_client.dart';
import 'avatar_spec.dart';

/// Reads and writes `profiles.avatar` (migration 0070).
///
/// Other players are looked up BY USERNAME (that is what every list in the app
/// has to hand, and the username is unique), batched: all the avatars asked for
/// within a few milliseconds go out as one query. Never throws: a player with no
/// avatar, a failed read, or a database that has not had migration 0070 yet all
/// simply leave the plain letter avatar in place.
class AvatarService extends ChangeNotifier {
  AvatarService._();
  static final AvatarService instance = AvatarService._();

  /// lower-cased username -> avatar (null inside the map = "has none").
  final Map<String, AvatarSpec?> _known = {};
  final Map<String, Completer<AvatarSpec?>> _waiting = {};
  final Map<String, String> _spelling = {}; // lower-cased -> as given (exact match in the query)
  Timer? _flush;
  bool _unavailable = false;

  static String _k(String name) => name.trim().toLowerCase();

  /// What is known right now: [known] false = not asked yet.
  ({bool known, AvatarSpec? spec}) peek(String username) {
    final k = _k(username);
    return (known: _known.containsKey(k), spec: _known[k]);
  }

  Future<AvatarSpec?> fetch(String username) {
    final k = _k(username);
    if (k.isEmpty || _unavailable) return Future.value(null);
    if (_known.containsKey(k)) return Future.value(_known[k]);
    _spelling[k] = username.trim();
    final c = _waiting.putIfAbsent(k, () => Completer<AvatarSpec?>());
    _flush ??= Timer(const Duration(milliseconds: 40), _send);
    return c.future;
  }

  Future<void> _send() async {
    _flush = null;
    final batch = Map<String, Completer<AvatarSpec?>>.of(_waiting);
    _waiting.clear();
    if (batch.isEmpty) return;
    try {
      // The names the lists hold come straight from `profiles`, so their
      // spelling matches the stored username exactly.
      final rows = await supabase
          .from('profiles')
          .select('username, avatar')
          .inFilter('username', [for (final k in batch.keys) _spelling[k] ?? k]);
      final found = <String, AvatarSpec?>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final name = r['username'] as String?;
        if (name == null) continue;
        found[_k(name)] = r['avatar'] == null
            ? null
            : AvatarSpec.fromJson(r['avatar']);
      }
      for (final e in batch.entries) {
        _known[e.key] = found[e.key];
        e.value.complete(found[e.key]);
      }
      notifyListeners();
    } catch (e) {
      // Most likely the avatar column is not there yet: stop asking.
      debugPrint('[AvatarService] read failed: $e');
      _unavailable = true;
      for (final c in batch.values) {
        c.complete(null);
      }
    }
  }

  // ── my own ──────────────────────────────────────────────────────────────

  String get _me => supabase.auth.currentUser!.id;

  /// My avatar, or null when I have not made one yet.
  Future<AvatarSpec?> loadMine() async {
    try {
      final row = await supabase
          .from('profiles')
          .select('username, avatar')
          .eq('id', _me)
          .maybeSingle();
      final spec = row?['avatar'] == null
          ? null
          : AvatarSpec.fromJson(row!['avatar']);
      final name = row?['username'] as String?;
      if (name != null) {
        _known[_k(name)] = spec;
        notifyListeners();
      }
      return spec;
    } catch (e) {
      debugPrint('[AvatarService] loadMine failed: $e');
      return null;
    }
  }

  /// Saves my avatar. Returns false when the database refused (no migration
  /// yet, offline ...).
  Future<bool> saveMine(AvatarSpec spec, {String? username}) async {
    try {
      await supabase.from('profiles').upsert({
        'id': _me,
        'avatar': spec.toJson(),
      });
      if (username != null) _known[_k(username)] = spec;
      _unavailable = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AvatarService] save failed: $e');
      return false;
    }
  }
}
