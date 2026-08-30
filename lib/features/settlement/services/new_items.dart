import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many of each item arrived since the Bag was last opened (user
/// 2026-08-29: the QuickPad's bag badge used to show the TOTAL held —
/// always a number, whether or not you'd looked. "Wenn ich einmal den
/// entsprechenden Reiter geöffnet habe, dann soll der Counter für neue
/// Items verschwinden. Dafür die entsprechenden Items markieren, welche neu
/// sind und wieviele").
///
/// Loot drops and finished crafts count; a deliberate Trade Center purchase
/// does not — you were already looking straight at it when it happened, the
/// same reason [GameEventLog] doesn't announce things you did yourself.
///
/// Per-device, like [GameEventLog]: this is "what's new to ME", not
/// settlement state, so it is never written to the DB.
class NewItems extends ChangeNotifier {
  static final NewItems _instance = NewItems._();
  factory NewItems() => _instance;
  NewItems._() {
    _load();
  }

  static const _prefsKey = 'new_items.v1';

  final Map<String, int> _counts = {};
  bool _loaded = false;

  /// itemId → how many are unseen. The badge's own number is [total]; the
  /// Bag screen reads this directly (via [snapshot]) to mark individual
  /// slots.
  int get total => _counts.values.fold(0, (s, n) => s + n);

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = (jsonDecode(raw) as Map).cast<String, dynamic>();
        for (final e in decoded.entries) {
          final n = (e.value as num).toInt();
          if (n > 0) _counts[e.key] = n;
        }
      }
    } catch (_) {
      // A corrupt or missing store starts empty — never worth blocking on.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_counts));
    } catch (_) {
      // Non-fatal: a failed write just means this session's tail isn't kept.
    }
  }

  /// [itemId] gained [n] more, unseen.
  void add(String itemId, int n) {
    if (n <= 0) return;
    _counts[itemId] = (_counts[itemId] ?? 0) + n;
    _persist();
    notifyListeners();
  }

  /// A copy of the live counts, for the Bag screen to hold onto for its own
  /// lifetime. Read this BEFORE calling [markSeen] — that clears the live
  /// map (so the QuickPad badge goes to 0 immediately), but the screen
  /// itself keeps showing what WAS new, off its own snapshot, for as long
  /// as it stays open.
  Map<String, int> snapshot() => Map.of(_counts);

  /// Clears the live counts. Called once, when the Bag screen opens — this
  /// is what makes "Wenn ich einmal den entsprechenden Reiter geöffnet
  /// habe... soll der Counter verschwinden" true.
  void markSeen() {
    if (_counts.isEmpty) return;
    _counts.clear();
    _persist();
    notifyListeners();
  }
}
