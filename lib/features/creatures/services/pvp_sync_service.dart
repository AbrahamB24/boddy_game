import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../social/services/pvp_service.dart';

/// One relayed combat action — the ONLY thing that crosses the network for a
/// live PvP turn (lockstep, not full state sync; see the plan's "Real-time
/// 6v6 PvP" section). [seq] is a monotonic per-match counter so a duplicate
/// or out-of-order broadcast delivery can be detected and dropped rather
/// than replayed twice.
class PvpAction {
  final int seq;

  /// 'attack' | 'ability' | 'switch' | 'endTurn'. Named `kind`, NOT `type` —
  /// `RealtimeChannel.send()` mutates the outgoing payload map in place and
  /// sets its OWN `'type': 'broadcast'` key before it goes over the wire
  /// (realtime_client's `send()`), which would silently clobber a same-named
  /// field. Found by reading the SDK source rather than assuming; the fix is
  /// just avoiding the reserved key.
  final String kind;
  final String actorId;
  final String? abilityId;
  final String? targetId;

  /// [CombatEngine.stateHash] AFTER this action was applied on the sender's
  /// side — battle_screen.dart compares it to its own post-apply hash to
  /// catch the two engines quietly diverging. Optional/nullable so an old
  /// persisted action_log entry (from before this field existed) still
  /// parses fine; a null just skips the check for that one action.
  final int? stateHash;

  /// The user id that actually SENT this action. [actorId] identifies a
  /// combatant, not a person, and for 'flee' it carries no information at
  /// all (see battle_screen.dart's `_confirmFlee` doc) — this is what lets
  /// `_applyRemoteAction` tell "the OPPONENT gave up" apart from "I gave up"
  /// when replaying my own past actions back from the persisted action_log
  /// (reconnect catch-up replays BOTH sides' history through the same
  /// method the live broadcast uses). Nullable so an old persisted entry
  /// from before this field existed still parses.
  final String? senderId;

  const PvpAction({
    required this.seq,
    required this.kind,
    required this.actorId,
    this.abilityId,
    this.targetId,
    this.stateHash,
    this.senderId,
  });

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'kind': kind,
    'actorId': actorId,
    if (abilityId != null) 'abilityId': abilityId,
    if (targetId != null) 'targetId': targetId,
    if (stateHash != null) 'stateHash': stateHash,
    if (senderId != null) 'senderId': senderId,
  };

  factory PvpAction.fromJson(Map<String, dynamic> m) => PvpAction(
    seq: (m['seq'] as num).toInt(),
    kind: m['kind'] as String,
    actorId: m['actorId'] as String,
    abilityId: m['abilityId'] as String?,
    targetId: m['targetId'] as String?,
    stateHash: (m['stateHash'] as num?)?.toInt(),
    senderId: m['senderId'] as String?,
  );
}

/// Live delivery of PvP turns via a Supabase Realtime broadcast channel, with
/// [PvpService.appendAction] as the persisted checkpoint (see
/// supabase/migrations/0050_social_pvp.sql's `action_log`) a reconnecting
/// client replays from. Broadcast is fire-and-forget and unordered over the
/// wire, so [seq] plus [PvpSyncService]'s own dedupe is what keeps two clients
/// applying the exact same sequence — the whole lockstep bet the
/// pvp_determinism_test.dart spike validated.
class PvpSyncService {
  final _pvpService = PvpService();
  RealtimeChannel? _channel;
  int _nextSeq = 0;
  final Set<int> _seen = {};
  Timer? _heartbeat;
  String? _opponentId;

  /// True while the opponent's client is tracked as present on this match's
  /// channel — Realtime Presence, not the DB heartbeat (that one is for the
  /// server-authoritative timeout claim; this one is for instant UI
  /// feedback, see battle_screen.dart's connection banner). Starts `true`
  /// (optimistic) so the banner doesn't flash on while presence sync is
  /// still arriving right after `connect()`.
  final ValueNotifier<bool> opponentOnline = ValueNotifier(true);

  /// Starts (or resumes, from [resumeFromSeq]) listening on [matchId]'s
  /// channel. [onRemoteAction] fires once per action, in [seq] order, never
  /// twice for the same seq — callers don't need their own dedupe.
  ///
  /// Also tracks Realtime Presence on the SAME channel ([opponentOnline])
  /// and starts a periodic DB heartbeat ([PvpService.touchPresence]) — both
  /// piggyback on the existing broadcast channel/connection rather than
  /// opening a second one.
  void connect({
    required String matchId,
    required String myUserId,
    required String opponentUserId,
    required void Function(PvpAction action) onRemoteAction,
    int resumeFromSeq = 0,
  }) {
    _nextSeq = resumeFromSeq;
    _opponentId = opponentUserId;
    _seen
      ..clear()
      ..addAll(List.generate(resumeFromSeq, (i) => i));
    final channel = supabase.channel('pvp:$matchId');
    channel
        .onBroadcast(
          event: 'action',
          callback: (payload) {
            // realtime_client's send() flattens {..myFields, type, event}
            // into ONE map before it goes over the wire (see the [kind]
            // field's doc comment) — the callback here receives that same
            // flat map back, not a nested {payload: {...}} envelope.
            final action = PvpAction.fromJson(payload);
            if (!_seen.add(action.seq)) return; // duplicate delivery
            // Converge with whichever side has acted furthest — see
            // [sendAction]'s doc comment for why this can't just be "my own
            // sends increment it".
            if (action.seq >= _nextSeq) _nextSeq = action.seq + 1;
            onRemoteAction(action);
          },
        )
        .onPresenceSync((_) => _refreshOpponentOnline(channel))
        .onPresenceJoin((_) => _refreshOpponentOnline(channel))
        .onPresenceLeave((_) => _refreshOpponentOnline(channel))
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            channel.track({'user_id': myUserId});
          }
        });
    _channel = channel;
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _pvpService.touchPresence(matchId),
    );
    _pvpService.touchPresence(matchId); // don't wait 15s for the first one
  }

  void _refreshOpponentOnline(RealtimeChannel channel) {
    final online = channel.presenceState().any(
      (s) => s.presences.any((p) => p.payload['user_id'] == _opponentId),
    );
    opponentOnline.value = online;
  }

  void disconnect() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _channel?.untrack();
    _channel?.unsubscribe();
    _channel = null;
    opponentOnline.dispose();
  }

  /// Sends MY chosen action: broadcasts it live and appends it to the
  /// match's persisted `action_log` as a reconnect checkpoint. The caller
  /// applies the action to its OWN local engine separately (this service
  /// only relays — see battle_screen.dart's `_relayPvpAction`, called right
  /// after the matching CombatEngine method already applied it locally).
  ///
  /// [_nextSeq] is shared across sends AND receives (not "my own counter"):
  /// turn-based play means only one side is ever unlocked to act at a time,
  /// so the two clients' sequence numbers naturally interleave correctly as
  /// long as each side advances its notion of "next" past whatever it has
  /// SEEN, not just what it has SENT — otherwise both sides' very first
  /// action would independently compute seq 0 and the second one would be
  /// silently dropped as a "duplicate".
  Future<PvpAction> sendAction(
    String matchId, {
    required String kind,
    required String actorId,
    String? abilityId,
    String? targetId,
    int? stateHash,
    String? senderId,
  }) async {
    final action = PvpAction(
      seq: _nextSeq++,
      kind: kind,
      actorId: actorId,
      abilityId: abilityId,
      targetId: targetId,
      stateHash: stateHash,
      senderId: senderId,
    );
    _seen.add(action.seq);
    await _channel?.sendBroadcastMessage(
      event: 'action',
      payload: action.toJson(),
    );
    await _pvpService.appendAction(matchId, action.toJson());
    return action;
  }
}
