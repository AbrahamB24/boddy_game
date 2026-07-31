import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The game's event feed (user request 2026-07-16: "einen notification button
/// für alle Events — Monster aufgestiegen, Expedition beendet etc.").
///
/// WHY IT EXISTS: almost everything here happens while you are NOT looking —
/// expeditions resolve offline, research completes on a timer, monsters level
/// up passively in their buildings. Before this, those either flashed past as
/// a SnackBar on whatever screen happened to be open, or were silently
/// dropped. A player coming back after a night away had no way to learn what
/// their settlement had done.
///
/// PERSISTED (user request): the feed is now written to local storage so past
/// events survive a restart — a player can scroll back through what happened,
/// not just what landed since the app last launched. Kept per-device (not on
/// the server): it is a personal "what happened" log, and offline outcomes are
/// still resolved authoritatively from the DB, each firing its event exactly
/// once, so reloading history never double-counts them.
enum GameEventKind {
  levelUp('⭐'),
  expedition('🎒'),
  caught('🐾'),
  research('🔬'),
  building('🏕'),
  breeding('🥚'),
  craft('🔨'),
  casualty('💔');

  final String emoji;
  const GameEventKind(this.emoji);
}

class GameEvent {
  final GameEventKind kind;
  final String message;
  final DateTime at;

  /// Whether the player has already been shown this one — by the bell, or by
  /// the welcome-back digest, which reports the SAME set (user 2026-07-27:
  /// "alles was bei den notifications angezeigt wird, soll auch beim while you
  /// were away screen sein").
  ///
  /// Per event rather than the single counter it replaced. A counter could only
  /// answer "how many are new", and the digest needs to know WHICH — it used to
  /// guess by cutting the feed at the away window, which silently dropped
  /// anything that had gone unread from an earlier session.
  bool read;

  GameEvent({
    required this.kind,
    required this.message,
    required this.at,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
        // Store the NAME, not the index — reordering the enum then can't
        // silently relabel old events.
        'k': kind.name,
        'm': message,
        'a': at.millisecondsSinceEpoch,
        'r': read,
      };

  static GameEvent? fromJson(Map<String, dynamic> j) {
    final name = j['k'] as String?;
    final message = j['m'] as String?;
    final millis = j['a'] as int?;
    if (name == null || message == null || millis == null) return null;
    final kind = GameEventKind.values.firstWhere(
      (e) => e.name == name,
      orElse: () => GameEventKind.building,
    );
    return GameEvent(
      kind: kind,
      message: message,
      at: DateTime.fromMillisecondsSinceEpoch(millis),
      // A row written before the flag existed counts as READ. The alternative
      // is to greet everyone upgrading with a digest of their entire history.
      read: j['r'] as bool? ?? true,
    );
  }
}

class GameEventLog extends ChangeNotifier {
  static final GameEventLog _instance = GameEventLog._();
  factory GameEventLog() => _instance;
  GameEventLog._() {
    // Pull the persisted history in as soon as the singleton exists; the bell
    // listens and rebuilds when it lands.
    _load();
  }

  static const String _prefsKey = 'game_event_log.v1';

  /// Newest first. Capped — this is a feed, not an audit trail, and an
  /// unbounded list would grow forever. 100 is plenty to scroll back a few
  /// days of outcomes without bloating storage.
  static const int _maxEvents = 100;

  final List<GameEvent> events = [];

  /// How many the player has not been shown yet — the bell's badge.
  int get unread {
    var n = 0;
    for (final e in events) {
      if (!e.read) n++;
    }
    return n;
  }

  /// The new ones, newest first. THE list both the bell's badge and the
  /// welcome-back digest are about, so the two can never disagree about what
  /// "happened while you were away" means.
  List<GameEvent> get unreadEvents => [
    for (final e in events)
      if (!e.read) e,
  ];

  /// Set once the persisted history has been read; guards [_persist] so an
  /// early write can't clobber the file before we've loaded it.
  bool _loaded = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final e = GameEvent.fromJson((item as Map).cast<String, dynamic>());
          // Insert-sorted so persisted history slots correctly around any live
          // events that were added while the file was still loading.
          if (e != null) _insertSorted(e);
        }
        _cap();
      }
    } catch (_) {
      // A corrupt or missing store must never break startup — worst case the
      // feed just starts empty.
    }
    _loaded = true;
    // Capture anything added during the async gap, then let the bell refresh.
    _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode([for (final e in events) e.toJson()]),
      );
    } catch (_) {
      // Non-fatal: a failed write just means this session's tail isn't kept.
    }
  }

  /// [at] is WHEN the event actually happened — pass it for offline outcomes
  /// (an expedition that finished hours ago, passive level-ups) so the feed
  /// shows the real time, not when the resolver happened to run on screen
  /// open. Defaults to now for live events.
  void add(GameEventKind kind, String message, {DateTime? at}) {
    _insertSorted(
      GameEvent(kind: kind, message: message, at: at ?? DateTime.now()),
    );
    _cap();
    _persist();
    notifyListeners();
  }

  /// Adds several at once with a single notify — offline resolution can land
  /// a dozen results in one frame. [at] applies to every message (they share
  /// an event time); omit for live events.
  void addAll(GameEventKind kind, Iterable<String> messages, {DateTime? at}) {
    final list = messages.toList();
    if (list.isEmpty) return;
    final when = at ?? DateTime.now();
    for (final m in list.reversed) {
      _insertSorted(GameEvent(kind: kind, message: m, at: when));
    }
    _cap();
    _persist();
    notifyListeners();
  }

  /// Inserts keeping the feed newest-first by event time. An offline batch can
  /// carry a timestamp OLDER than events already logged, so it slots into the
  /// right place rather than always jumping to the top. For equal timestamps
  /// the just-added event wins the tie (stays ahead) — deterministic, unlike a
  /// full re-sort.
  void _insertSorted(GameEvent e) {
    var i = 0;
    while (i < events.length && events[i].at.isAfter(e.at)) {
      i++;
    }
    events.insert(i, e);
  }

  void _cap() {
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }
  }

  /// Marks the whole feed seen. Called by the bell when it opens and by the
  /// welcome-back digest when it is dismissed — both have just SHOWN the unread
  /// set, so leaving the badge nagging about what is already on screen would be
  /// wrong either way.
  void markAllRead() {
    var changed = false;
    for (final e in events) {
      if (!e.read) {
        e.read = true;
        changed = true;
      }
    }
    if (!changed) return;
    _persist();
    notifyListeners();
  }

  void clear() {
    if (events.isEmpty) return;
    events.clear();
    _persist();
    notifyListeners();
  }
}
