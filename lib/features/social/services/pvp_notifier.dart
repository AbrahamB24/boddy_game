import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/pvp_match.dart';
import 'alert_effects.dart';
import 'alert_prefs.dart';
import 'friends_service.dart';
import 'pvp_service.dart';

/// What happened in a match that the player, who may be doing something else
/// entirely, should be told about.
enum PvpAlertKind {
  /// Someone challenged me.
  challenged,

  /// My challenge was accepted — their lobby is open to me.
  accepted,

  /// They opened the lobby: they are waiting there now.
  opponentInLobby,

  /// They picked their team.
  opponentReady,

  /// The match is over before it began: they left, declined, withdrew, or it
  /// expired.
  ended,

  /// A fight I stepped out of is waiting on MY move.
  yourTurn,

  /// A fight I was not watching finished — the opponent gave up, a clock ran
  /// out.
  matchOver,
}

/// One thing to tell the player about, shown as a banner until they dismiss it
/// or join.
class PvpAlert {
  final String matchId;
  final PvpAlertKind kind;
  final String opponentId;
  final String opponentName;

  /// Why a match ended (only for [PvpAlertKind.ended]) — the match row's
  /// `abandon_reason`.
  final String? reason;

  /// Whether I won (only for [PvpAlertKind.matchOver]).
  final bool? won;

  final DateTime at;

  PvpAlert({
    required this.matchId,
    required this.kind,
    required this.opponentId,
    required this.opponentName,
    this.reason,
    this.won,
  }) : at = DateTime.now();

  /// The one line the banner shows.
  String get text => switch (kind) {
    PvpAlertKind.challenged => '$opponentName challenged you',
    PvpAlertKind.accepted => '$opponentName accepted your challenge',
    PvpAlertKind.opponentInLobby => '$opponentName is waiting in the lobby',
    PvpAlertKind.opponentReady => '$opponentName is ready',
    PvpAlertKind.ended => switch (reason) {
      'declined' => '$opponentName declined your challenge',
      'left' => '$opponentName left the lobby',
      'cancelled' => '$opponentName withdrew the challenge',
      'lobby_expired' => 'The lobby with $opponentName expired',
      _ => 'The match with $opponentName ended',
    },
    PvpAlertKind.yourTurn => 'It is your move against $opponentName',
    PvpAlertKind.matchOver => switch ((won, reason)) {
      (true, 'timeout') => '$opponentName ran out of time — you won',
      (false, 'timeout') => 'You ran out of time — $opponentName won',
      (true, _) => 'You won against $opponentName',
      (false, _) => '$opponentName won the match',
      _ => 'The match with $opponentName is over',
    },
  };

  /// What the banner's main button says, or null when there is nothing to do
  /// but dismiss it.
  String? get actionLabel => switch (kind) {
    PvpAlertKind.challenged => 'View',
    PvpAlertKind.accepted ||
    PvpAlertKind.opponentInLobby ||
    PvpAlertKind.opponentReady => 'Join',
    PvpAlertKind.yourTurn => 'Resume',
    PvpAlertKind.ended || PvpAlertKind.matchOver => null,
  };
}

/// Which alerts the change from [prev] to [next] deserves, seen from [myId].
/// Pure, so the rules can be tested without a database.
///
/// [prev] is what this device knew before; null means the match is new to it.
List<PvpAlertKind> pvpTransitions(
  PvpMatch? prev,
  PvpMatch next,
  String myId, {
  DateTime? now,
}) {
  final out = <PvpAlertKind>[];
  final iAmA = next.playerA == myId;
  final wasOver =
      prev != null &&
      (prev.status == PvpMatchStatus.abandoned ||
          prev.status == PvpMatchStatus.finished);
  if (wasOver) return out;

  if (next.status == PvpMatchStatus.finished) {
    // A fight I saw running that has ended now.
    if (prev != null && prev.status == PvpMatchStatus.active) {
      out.add(PvpAlertKind.matchOver);
    }
    return out;
  }

  if (next.status == PvpMatchStatus.abandoned) {
    // Only if I had seen it alive — a match I never knew about that arrives
    // already dead is not news.
    if (prev != null) out.add(PvpAlertKind.ended);
    return out;
  }

  if (prev == null) {
    if (!iAmA && next.status == PvpMatchStatus.pending) {
      out.add(PvpAlertKind.challenged);
    }
    return out;
  }

  if (iAmA &&
      prev.status == PvpMatchStatus.pending &&
      next.status == PvpMatchStatus.accepted) {
    out.add(PvpAlertKind.accepted);
  }
  // "Arrived" is judged by the HEARTBEAT, not the flag alone: a client that
  // crashed leaves its flag set, and coming back sets it to what it already
  // was — but the old heartbeat has run out, so it still counts as arriving.
  if (!prev.opponentInLobby(myId, now: now) &&
      next.opponentInLobby(myId, now: now)) {
    out.add(PvpAlertKind.opponentInLobby);
  }
  if (!prev.opponentReady(myId) && next.opponentReady(myId)) {
    out.add(PvpAlertKind.opponentReady);
  }
  // The move passed to me in a fight.
  if (next.status == PvpMatchStatus.active &&
      next.waitingOn == myId &&
      prev.waitingOn != myId) {
    out.add(PvpAlertKind.yourTurn);
  }
  return out;
}

/// The app-wide watcher for PvP: keeps every open match of mine in view over
/// one realtime channel, turns changes into [PvpAlert]s (the banner host shows
/// them wherever the player is), and counts what is waiting on them (the
/// Social button's badge).
///
/// Started once a session exists, stopped on sign-out. The lobby screen tells
/// it which lobby is open ([openLobbyId]) so an opponent's arrival is not
/// announced to someone already looking at them, and tells it about my own
/// leaving ([markMine]) so I am not notified about what I just did.
class PvpNotifier extends ChangeNotifier {
  static final PvpNotifier instance = PvpNotifier._();
  PvpNotifier._();

  final _pvp = PvpService();
  final _friends = FriendsService();

  final Map<String, PvpMatch> _matches = {};
  final Map<String, String> _names = {};
  final List<PvpAlert> _alerts = [];
  final Set<String> _mine = {};
  RealtimeChannel? _channel;
  String? _userId;
  Timer? _tick;
  int _sweepCounter = 0;

  /// The lobby that is on screen right now, if any.
  String? openLobbyId;

  /// The fight that is on screen right now, if any.
  String? openBattleId;

  /// Newest first.
  List<PvpAlert> get alerts => List.unmodifiable(_alerts);

  /// Every match I am in that is not over. A challenge or lobby whose time has
  /// run out counts as over even before the server sweeps it, so a dead entry
  /// never lingers in a list.
  List<PvpMatch> get openMatches {
    final now = DateTime.now();
    return [
      for (final m in _matches.values)
        if (m.status == PvpMatchStatus.active ||
            ((m.status == PvpMatchStatus.pending ||
                    m.status == PvpMatchStatus.accepted) &&
                (m.lobbyExpiresAt == null || m.lobbyExpiresAt!.isAfter(now))))
          m,
    ];
  }

  /// What is waiting on me: challenges I have not answered, and opponents who
  /// are sitting in a lobby or already ready. The Social button's badge.
  int get attention {
    final me = _userId;
    if (me == null) return 0;
    var n = 0;
    for (final m in openMatches) {
      if (m.status == PvpMatchStatus.pending && m.playerB == me) {
        n++;
      } else if (m.status == PvpMatchStatus.active && m.waitingOn == me) {
        n++; // my move in a fight I am not looking at
      } else if (m.status == PvpMatchStatus.accepted) {
        final s = m.opponentStage(me);
        if (s == PvpOpponentStage.inLobby || s == PvpOpponentStage.ready) n++;
      }
    }
    return n;
  }

  /// What the last time-driven refresh looked like — see the timer in [start].
  int _tickSignature = -1;

  Future<void> start() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null || _userId == me) return;
    stop();
    _userId = me;
    try {
      final results = await Future.wait([
        _pvp.loadPendingChallenges(),
        _pvp.loadSentChallenges(),
        _pvp.loadOpenMatches(),
      ]);
      for (final list in results) {
        for (final m in list) {
          _matches[m.id] = m;
        }
      }
      await _learnNames(_matches.values.map((m) => m.otherUserId(me)));
    } catch (_) {
      // Nothing to show yet; the channel below still catches what changes.
    }
    _channel = supabase
        .channel('pvp_notifier:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pvp_matches',
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.delete) return;
            _onRow(PvpMatch.fromMap(payload.newRecord));
          },
        )
        .subscribe();
    // The badge depends on heartbeat freshness, which changes with time alone.
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      // Only when the passage of time actually changed something — every
      // listener (the settlement screen, the banner host, the social tab)
      // rebuilds on this, and it used to fire every 20 s regardless.
      final signature = attention * 1000 + openMatches.length;
      if (signature != _tickSignature) {
        _tickSignature = signature;
        notifyListeners();
      }
      _sweepCounter++;
      // About every three minutes: have the server drop lobbies and challenges
      // whose time has run out, and read the truth again. There is no server
      // timer (see migration 0055); whoever has the app open does the sweeping.
      if (_sweepCounter % 9 == 0) _sweep();
    });
    notifyListeners();
  }

  /// Re-reads every open match from the database — after the app was away, or
  /// when a screen wants to be sure it is looking at the truth.
  Future<void> reload() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return;
    final results = await Future.wait([
      _pvp.loadPendingChallenges(),
      _pvp.loadSentChallenges(),
      _pvp.loadOpenMatches(),
    ]);
    final fresh = {
      for (final list in results)
        for (final m in list) m.id: m,
    };
    // A match that was open and no longer comes back has ended meanwhile.
    _matches.removeWhere(
      (id, m) =>
          !fresh.containsKey(id) &&
          (m.status == PvpMatchStatus.pending ||
              m.status == PvpMatchStatus.accepted ||
              m.status == PvpMatchStatus.active),
    );
    _matches.addAll(fresh);
    await _learnNames(fresh.values.map((m) => m.otherUserId(me)));
    notifyListeners();
  }

  void stop() {
    _channel?.unsubscribe();
    _channel = null;
    _tick?.cancel();
    _tick = null;
    _matches.clear();
    _alerts.clear();
    _mine.clear();
    _userId = null;
    openLobbyId = null;
    openBattleId = null;
    notifyListeners();
  }

  Future<void> _sweep() async {
    try {
      await _pvp.expireStale();
      await reload();
    } catch (_) {}
  }

  Future<void> _learnNames(Iterable<String> ids) async {
    final missing = ids.where((id) => !_names.containsKey(id)).toSet().toList();
    if (missing.isEmpty) return;
    try {
      final found = await _friends.usernamesFor(missing);
      for (final e in found.entries) {
        _names[e.key] = e.value ?? '(unknown)';
      }
    } catch (_) {}
  }

  Future<void> _onRow(PvpMatch next) async {
    final me = _userId;
    if (me == null) return;
    if (next.playerA != me && next.playerB != me) return;
    final prev = _matches[next.id];
    _matches[next.id] = next;
    final opponent = next.otherUserId(me);
    await _learnNames([opponent]);

    final quiet =
        _mine.contains(next.id) ||
        openLobbyId == next.id ||
        openBattleId == next.id;
    for (final kind in pvpTransitions(prev, next, me)) {
      // My own doing, or something happening in the lobby I am looking at.
      if (quiet && kind != PvpAlertKind.challenged) continue;
      _add(
        PvpAlert(
          matchId: next.id,
          kind: kind,
          opponentId: opponent,
          opponentName: _names[opponent] ?? '(unknown)',
          reason: next.abandonReason,
          won: next.winnerId == null ? null : next.winnerId == me,
        ),
      );
    }
    if (next.status == PvpMatchStatus.abandoned ||
        next.status == PvpMatchStatus.finished) {
      // A dead match has nothing left to join: its old alerts go, and only the
      // "ended" line (if any) stays.
      _alerts.removeWhere(
        (a) => a.matchId == next.id && a.kind != PvpAlertKind.ended,
      );
    }
    notifyListeners();
  }

  void _add(PvpAlert alert) {
    // Banners switched off in Profile: the badge and the lists still tell.
    if (!AlertPrefs.bannersOn) return;
    // One alert per match: the newest replaces what it supersedes.
    _alerts.removeWhere((a) => a.matchId == alert.matchId);
    _alerts.insert(0, alert);
    announceSocial(key: 'pvp:${alert.matchId}', title: 'PvP', body: alert.text);
  }

  void dismiss(PvpAlert alert) {
    _alerts.remove(alert);
    notifyListeners();
  }

  /// Call before I leave, decline or cancel a match myself, so the row's change
  /// does not come back to me as news.
  void markMine(String matchId) => _mine.add(matchId);

  /// Learns of a match this device just created or loaded itself (a challenge
  /// I sent), so its later changes are compared against something.
  void remember(PvpMatch m) {
    _matches[m.id] = m;
    notifyListeners();
  }

  PvpMatch? matchById(String id) => _matches[id];
}
