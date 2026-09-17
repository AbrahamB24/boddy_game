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

  const PvpAction({
    required this.seq,
    required this.kind,
    required this.actorId,
    this.abilityId,
    this.targetId,
  });

  Map<String, dynamic> toJson() => {
    'seq': seq,
    'kind': kind,
    'actorId': actorId,
    if (abilityId != null) 'abilityId': abilityId,
    if (targetId != null) 'targetId': targetId,
  };

  factory PvpAction.fromJson(Map<String, dynamic> m) => PvpAction(
    seq: (m['seq'] as num).toInt(),
    kind: m['kind'] as String,
    actorId: m['actorId'] as String,
    abilityId: m['abilityId'] as String?,
    targetId: m['targetId'] as String?,
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

  /// Starts (or resumes, from [resumeFromSeq]) listening on [matchId]'s
  /// channel. [onRemoteAction] fires once per action, in [seq] order, never
  /// twice for the same seq — callers don't need their own dedupe.
  void connect({
    required String matchId,
    required void Function(PvpAction action) onRemoteAction,
    int resumeFromSeq = 0,
  }) {
    _nextSeq = resumeFromSeq;
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
        .subscribe();
    _channel = channel;
  }

  void disconnect() {
    _channel?.unsubscribe();
    _channel = null;
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
  }) async {
    final action = PvpAction(
      seq: _nextSeq++,
      kind: kind,
      actorId: actorId,
      abilityId: abilityId,
      targetId: targetId,
    );
    _seen.add(action.seq);
    await _channel?.sendBroadcastMessage(event: 'action', payload: action.toJson());
    await _pvpService.appendAction(matchId, action.toJson());
    return action;
  }
}
