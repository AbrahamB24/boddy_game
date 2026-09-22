import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/social/models/pvp_match.dart';
import 'package:boddygame/features/social/services/pvp_notifier.dart';

// PvP lobby (user 2026-09-19): the lobby is a room you can step out of, and the
// other player's stage — not yet accepted, not in the lobby, waiting in the
// lobby, ready — is shown everywhere. These pin how the stage is read from a
// match row and which changes deserve a banner.
void main() {
  final now = DateTime(2026, 9, 19, 12);
  const me = 'me';
  const her = 'her';

  PvpMatch match({
    String a = me,
    String b = her,
    PvpMatchStatus status = PvpMatchStatus.accepted,
    bool readyA = false,
    bool readyB = false,
    bool inA = false,
    bool inB = false,
    DateTime? seenA,
    DateTime? seenB,
    String? reason,
    String? waitingOn,
    String? winnerId,
  }) => PvpMatch(
    id: 'm',
    playerA: a,
    playerB: b,
    status: status,
    readyA: readyA,
    readyB: readyB,
    inLobbyA: inA,
    inLobbyB: inB,
    lobbySeenA: seenA,
    lobbySeenB: seenB,
    createdAt: now,
    abandonReason: reason,
    waitingOn: waitingOn,
    winnerId: winnerId,
  );

  group('the opponent stage', () {
    test('a challenge nobody answered is "not yet accepted"', () {
      expect(
        match(status: PvpMatchStatus.pending).opponentStage(me, now: now),
        PvpOpponentStage.notAccepted,
      );
    });

    test('accepted but their lobby is closed', () {
      expect(match().opponentStage(me, now: now), PvpOpponentStage.notInLobby);
    });

    test('their lobby is open and the heartbeat is fresh: waiting in the lobby',
        () {
      final m = match(inB: true, seenB: now.subtract(const Duration(seconds: 10)));
      expect(m.opponentStage(me, now: now), PvpOpponentStage.inLobby);
    });

    test('a heartbeat that ran out stops counting — a crashed client is not there',
        () {
      final m = match(inB: true, seenB: now.subtract(const Duration(minutes: 3)));
      expect(m.opponentStage(me, now: now), PvpOpponentStage.notInLobby);
    });

    test('ready outranks being in the lobby, and survives minimising it', () {
      expect(
        match(readyB: true, inB: false).opponentStage(me, now: now),
        PvpOpponentStage.ready,
      );
    });

    test('the same row reads from the other side', () {
      final m = match(inA: true, seenA: now, readyB: true);
      // I am B: A is waiting in the lobby.
      expect(m.opponentStage(her, now: now), PvpOpponentStage.inLobby);
      // I am A: B is ready.
      expect(m.opponentStage(me, now: now), PvpOpponentStage.ready);
    });

    test('a running fight and a finished match', () {
      expect(
        match(status: PvpMatchStatus.active).opponentStage(me, now: now),
        PvpOpponentStage.inBattle,
      );
      expect(
        match(status: PvpMatchStatus.abandoned).opponentStage(me, now: now),
        PvpOpponentStage.over,
      );
    });
  });

  group('what deserves a banner', () {
    test('a new challenge to me', () {
      final next = match(a: her, b: me, status: PvpMatchStatus.pending);
      expect(pvpTransitions(null, next, me), [PvpAlertKind.challenged]);
    });

    test('my own new challenge is not news to me', () {
      final next = match(status: PvpMatchStatus.pending);
      expect(pvpTransitions(null, next, me), isEmpty);
    });

    test('my challenge accepted', () {
      final prev = match(status: PvpMatchStatus.pending);
      expect(pvpTransitions(prev, match(), me), [PvpAlertKind.accepted]);
    });

    test('the opponent opens the lobby — once, not on every heartbeat', () {
      final prev = match();
      final arrived = match(inB: true, seenB: now);
      expect(pvpTransitions(prev, arrived, me, now: now), [PvpAlertKind.opponentInLobby]);
      final beat = match(inB: true, seenB: now.add(const Duration(seconds: 15)));
      expect(pvpTransitions(arrived, beat, me, now: now), isEmpty);
    });

    test('a crashed client that comes back still arrives (its old heartbeat ran out)',
        () {
      final stale = match(inB: true, seenB: now.subtract(const Duration(minutes: 5)));
      final back = match(inB: true, seenB: now);
      expect(
        pvpTransitions(stale, back, me, now: now),
        [PvpAlertKind.opponentInLobby],
      );
    });

    test('the opponent picks a team', () {
      final prev = match(inB: true, seenB: now);
      final next = match(inB: true, seenB: now, readyB: true);
      expect(pvpTransitions(prev, next, me, now: now), [PvpAlertKind.opponentReady]);
    });

    test('my own arrival and my own ready are not announced to me', () {
      final prev = match();
      final next = match(inA: true, seenA: now, readyA: true);
      expect(pvpTransitions(prev, next, me, now: now), isEmpty);
    });

    test('the opponent leaving ends it, with the reason on the row', () {
      final prev = match();
      final next = match(status: PvpMatchStatus.abandoned, reason: 'left');
      expect(pvpTransitions(prev, next, me, now: now), [PvpAlertKind.ended]);
      expect(
        PvpAlert(
          matchId: 'm',
          kind: PvpAlertKind.ended,
          opponentId: her,
          opponentName: 'Mira',
          reason: 'left',
        ).text,
        'Mira left the lobby',
      );
    });

    test('a match that was already dead says nothing more', () {
      final dead = match(status: PvpMatchStatus.abandoned, reason: 'left');
      expect(pvpTransitions(dead, dead, me), isEmpty);
      expect(pvpTransitions(null, dead, me), isEmpty);
    });
  });

  group('a fight I stepped out of', () {
    test('my move comes round — once', () {
      final prev = match(status: PvpMatchStatus.active, waitingOn: her);
      final mine = match(status: PvpMatchStatus.active, waitingOn: me);
      expect(pvpTransitions(prev, mine, me, now: now), [PvpAlertKind.yourTurn]);
      // The same row again (a heartbeat) is not another announcement.
      expect(pvpTransitions(mine, mine, me, now: now), isEmpty);
    });

    test('their move is not news', () {
      final prev = match(status: PvpMatchStatus.active, waitingOn: me);
      final theirs = match(status: PvpMatchStatus.active, waitingOn: her);
      expect(pvpTransitions(prev, theirs, me, now: now), isEmpty);
    });

    test('a finished fight says who won, and why when a clock ran out', () {
      final prev = match(status: PvpMatchStatus.active, waitingOn: her);
      final won = match(
        status: PvpMatchStatus.finished,
        winnerId: me,
        reason: 'timeout',
      );
      expect(pvpTransitions(prev, won, me, now: now), [PvpAlertKind.matchOver]);
      String text(bool iWon, String? reason) => PvpAlert(
        matchId: 'm',
        kind: PvpAlertKind.matchOver,
        opponentId: her,
        opponentName: 'Mira',
        reason: reason,
        won: iWon,
      ).text;
      expect(text(true, 'timeout'), 'Mira ran out of time — you won');
      expect(text(false, 'timeout'), 'You ran out of time — Mira won');
      expect(text(true, null), 'You won against Mira');
      expect(text(false, null), 'Mira won the match');
    });

    test('a match that ends before it began is "ended", not "over"', () {
      final prev = match(status: PvpMatchStatus.active);
      final next = match(status: PvpMatchStatus.abandoned, reason: 'desync');
      expect(pvpTransitions(prev, next, me, now: now), [PvpAlertKind.ended]);
    });
  });
}
