import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../social/models/pvp_match.dart';
import '../social/services/pvp_notifier.dart';
import '../social/services/pvp_service.dart';
import '../social/social_actions.dart' show leaveMatchFlow;
import '../social/widgets/social_kit.dart';
import 'battle_prep_screen.dart';
import 'battle_screen.dart';
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';
import 'services/pvp_combatant_snapshot.dart';
import 'widgets/creature_card.dart';
import 'widgets/versus_kit.dart';

/// The PvP lobby (user 2026-09-15): opened once BOTH sides have accepted a
/// challenge (`status == accepted`). Each player picks their team here — via
/// the SAME [BattlePrepScreen] every other fight uses, not a bespoke picker —
/// and confirms it as "ready". Only once BOTH `ready_a`/`ready_b` are true
/// does [PvpService.setReady] flip the match to `active` with a shared seed;
/// both lobby screens are watching the row live and jump to the real
/// [BattleScreen] (its `isPvp` mode) the instant that happens — the lobby
/// countdown at the top is cosmetic only (see [_timerChip]'s doc), so this
/// already happens the moment both are ready, whether or not it has run out.
///
/// Dressed the same as [BattlePrepScreen] (user 2026-09-17: "soll so
/// aussehen, wie wenn ich auf ein Node bei der Kampagne gedrückt habe") —
/// "You face"/"Your team" over a bottom action bar — except the opponent's
/// pick is shown SHROUDED ([CreatureCard.shrouded]): PvP hides what you're
/// up against until the fight actually starts.
///
/// THE LOBBY IS A ROOM YOU CAN STEP OUT OF (user 2026-09-19): going BACK only
/// minimises it — the match stays open, you are told (a banner, anywhere in the
/// app) when the opponent arrives, and the PvP list lets you back in whenever
/// you like. "Leave lobby" is the real exit: it ends the match and the other side
/// is told. While the screen is open it says "I am here" every few seconds
/// ([PvpService.setLobbyPresence]); the opponent's stage — not yet accepted, not
/// in the lobby, waiting in the lobby, ready — is shown in the header.
///
/// A match that's ALREADY `active` when this screen opens (a reconnect) skips
/// the lobby UI entirely and goes straight back into the fight.
class PvpLobbyScreen extends StatefulWidget {
  final PvpMatch match;
  final String opponentName;

  const PvpLobbyScreen({
    super.key,
    required this.match,
    required this.opponentName,
  });

  @override
  State<PvpLobbyScreen> createState() => _PvpLobbyScreenState();
}

class _PvpLobbyScreenState extends State<PvpLobbyScreen> {
  final _pvpSvc = PvpService();
  late PvpMatch _match;
  RealtimeChannel? _channel;
  bool _navigating = false;
  bool _busy = false;
  // 1s tick: repaints the opponent's stage (a heartbeat that ran out turns
  // "waiting in the lobby" back into "not in the lobby" with no row change).
  Timer? _ticker;
  // "I am here" — repeated while the lobby is open.
  Timer? _heartbeat;
  // Set once the match ends, so leaving is not announced to me.
  bool _leftByMe = false;

  // The same party size [_pickTeam] hands [BattlePrepScreen] — kept as one
  // constant so the empty-slot count below can't silently drift from it.
  static const int _kPartySize = 6;

  String get _myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _match = widget.match;
    if (_match.status == PvpMatchStatus.active) {
      _goToBattle(_match);
      return;
    }
    // Lazy cleanup (no cron needed): sweeps THIS lobby (and any other stale
    // match/lobby) if its own `lobby_expires_at` has already passed. [_watch]
    // already pops on the resulting `abandoned` update.
    _pvpSvc.expireStale();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    PvpNotifier.instance.openLobbyId = _match.id;
    _watch();
    _enter();
  }

  /// Says "I am here", keeps saying it, and reads the match fresh — what this
  /// screen was opened with may be minutes old. Both being ready and both being
  /// here is what starts the battle, and arriving is one of the ways to make
  /// that true.
  Future<void> _enter() async {
    try {
      await _pvpSvc.setLobbyPresence(_match.id, true);
      _heartbeat = Timer.periodic(kLobbyHeartbeat, (_) {
        _pvpSvc.setLobbyPresence(_match.id, true).catchError((_) {});
      });
      final fresh = await _pvpSvc.loadMatch(_match.id);
      if (!mounted) return;
      _apply(fresh);
    } catch (_) {
      // Offline: the screen still shows the last known state; the next
      // heartbeat or realtime update catches up.
    }
  }

  /// Takes in a newer row: shows it, starts the battle if it is time, leaves if
  /// the match is over.
  Future<void> _apply(PvpMatch updated) async {
    if (!mounted) return;
    setState(() => _match = updated);
    if (updated.status == PvpMatchStatus.active) {
      _goToBattle(updated);
    } else if (updated.status == PvpMatchStatus.abandoned) {
      _endedByOpponent(updated);
    } else if (updated.status == PvpMatchStatus.accepted) {
      final started = await _pvpSvc.tryStart(updated);
      if (mounted && started.status == PvpMatchStatus.active) {
        _goToBattle(started);
      }
    }
  }

  void _endedByOpponent(PvpMatch m) {
    if (_leftByMe) return;
    final name = widget.opponentName;
    final text = switch (m.abandonReason) {
      'declined' => '$name declined the challenge.',
      'cancelled' => '$name withdrew the challenge.',
      'lobby_expired' => 'The lobby expired.',
      _ => '$name left the lobby.',
    };
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _heartbeat?.cancel();
    _channel?.unsubscribe();
    if (PvpNotifier.instance.openLobbyId == _match.id) {
      PvpNotifier.instance.openLobbyId = null;
    }
    // Stepping out: the match stays open, but I am no longer "in the lobby".
    // (A no-op on the server once the match is over or started.)
    _pvpSvc.setLobbyPresence(_match.id, false).catchError((_) {});
    super.dispose();
  }

  void _watch() {
    final channel = supabase.channel('pvp_lobby:${_match.id}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'pvp_matches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _match.id,
          ),
          callback: (payload) {
            _apply(PvpMatch.fromMap(payload.newRecord));
          },
        )
        .subscribe();
    _channel = channel;
  }

  Future<void> _pickTeam() async {
    final team = await Navigator.push<List<CreatureInstance>>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePrepScreen(
          title: 'vs. ${widget.opponentName}',
          enemies: const [],
          partySize: _kPartySize,
          rewards: const [],
          showEnemyPreview: false,
          confirmLabel: 'Ready',
        ),
      ),
    );
    if (team == null || team.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await _pvpSvc.setReady(_match.id, snapshotTeam(team));
      await _apply(updated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goToBattle(PvpMatch m) {
    if (_navigating) return;
    _navigating = true;
    final amA = m.playerA == _myId;
    final mySnap = amA ? m.teamA! : m.teamB!;
    final oppSnap = amA ? m.teamB! : m.teamA!;
    final ctrl = CreaturesController();
    final myTeam = [
      for (final j in mySnap)
        if (ctrl.byId(j['instanceId'] as String) != null)
          ctrl.byId(j['instanceId'] as String)!,
    ];
    final enemies = [
      for (final j in oppSnap) combatantFromSnapshot(j, isPlayerSide: false),
    ];
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: myTeam,
          enemies: enemies,
          title: 'vs. ${widget.opponentName}',
          isPvp: true,
          pvpSeed: m.seed,
          pvpMatch: m,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myReady = _match.myReady(_myId);
    final amA = _match.playerA == _myId;
    final mySnap = amA ? _match.teamA : _match.teamB;
    final oppSnap = amA ? _match.teamB : _match.teamA;
    // THE CARD DUEL (user 2026-09-20, "Variante 8"): their team's cards face-down
    // on top — shrouded, the duel's whole point — yours below, a plain VS between
    // (their power is unknown, so there is no comparison bar here).
    return MenuScaffold(
      title: 'vs. ${widget.opponentName}',
      trailing: _stageChip(),
      child: VersusStage(
        enemy: VersusSide(caption: 'You face', fan: _enemyFan(oppSnap)),
        middle: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: VsDivider(),
        ),
        mine: VersusSide(caption: 'Your team', fan: _teamFan(mySnap)),
        actions: _actions(myReady),
      ),
    );
  }

  PvpOpponentStage get _stage => _match.opponentStage(_myId);

  /// Where the other player is, as a small cream chip — the same words every
  /// list and the chat cards use.
  Widget _stageChip() => StageChip(_stage);

  Future<void> _leaveForGood() async {
    final left = await leaveMatchFlow(context, _match, widget.opponentName);
    if (!left || !mounted) return;
    _leftByMe = true;
    Navigator.of(context).pop();
  }

  Widget _enemyFan(List<Map<String, dynamic>>? oppSnap) {
    if (oppSnap == null) {
      final name = widget.opponentName;
      return versusHint(switch (_stage) {
        PvpOpponentStage.notAccepted =>
          'Waiting for $name to accept the challenge…',
        PvpOpponentStage.notInLobby =>
          '$name has not opened the lobby yet.\nYou can go back — you will be '
              'told when they arrive.',
        _ => 'Choosing their team…',
      });
    }
    return VersusFan(
      cards: [
        for (var i = 0; i < oppSnap.length; i++) const CreatureCard.shrouded(),
      ],
      tileW: 60,
      tileH: 100,
    );
  }

  Widget _teamFan(List<Map<String, dynamic>>? mySnap) {
    if (_busy) {
      return const CircularProgressIndicator(color: CreamPalette.goldDeep);
    }
    if (mySnap == null) {
      return VersusFan(
        cards: [
          for (var i = 0; i < _kPartySize; i++)
            EmptyMonsterSlot(label: i == 0 ? 'Add' : null, onTap: _pickTeam),
        ],
        tileW: 60,
        tileH: 100,
        down: true,
      );
    }
    final ctrl = CreaturesController();
    final team = [
      for (final j in mySnap)
        if (ctrl.byId(j['instanceId'] as String) case final c?) c,
    ];
    return VersusFan(
      cards: [for (final c in team) CreatureCard(creature: c)],
      tileW: 60,
      tileH: 100,
      down: true,
    );
  }

  /// Leave (or withdraw), what we are waiting on, and Ready / Change team.
  Widget _actions(bool myReady) {
    final pending = _match.status == PvpMatchStatus.pending;
    final name = widget.opponentName;
    final waiting = switch (_stage) {
      PvpOpponentStage.notAccepted => 'Waiting for $name to accept…',
      PvpOpponentStage.notInLobby => 'Waiting for $name to join…',
      _ => 'Waiting for $name to get ready…',
    };
    return Row(
      children: [
        Pressable(
          behavior: HitTestBehavior.opaque,
          onTap: _leaveForGood,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: raisedTile(radius: 11),
            child: Text(
              pending ? 'Withdraw' : 'Leave lobby',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: CreamPalette.warn,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              myReady
                  ? waiting
                  : 'Going back keeps the lobby open — you are told when '
                        '$name arrives.',
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
            ),
          ),
        ),
        myReady
            ? Pressable(
                behavior: HitTestBehavior.opaque,
                onTap: !_busy ? _pickTeam : null,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 26),
                  alignment: Alignment.center,
                  decoration: raisedTile(radius: 13),
                  child: const Text(
                    'Change team',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: kBoxInk,
                    ),
                  ),
                ),
              )
            : SocialGoldButton(
                'Ready',
                height: 38,
                fontSize: 14,
                padding: const EdgeInsets.symmetric(horizontal: 40),
                onTap: !_busy ? _pickTeam : null,
              ),
      ],
    );
  }
}
