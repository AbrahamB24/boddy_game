import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../social/models/pvp_match.dart';
import '../social/services/pvp_service.dart';
import 'battle_prep_screen.dart';
import 'battle_screen.dart';
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';
import 'services/pvp_combatant_snapshot.dart';

/// The PvP lobby (user 2026-09-15): opened once BOTH sides have accepted a
/// challenge (`status == accepted`). Each player picks their team here — via
/// the SAME [BattlePrepScreen] every other fight uses, not a bespoke picker —
/// and confirms it as "ready". Only once BOTH `ready_a`/`ready_b` are true
/// does [PvpService.setReady] flip the match to `active` with a shared seed;
/// both lobby screens are watching the row live and jump to the real
/// [BattleScreen] (its `isPvp` mode) the instant that happens.
///
/// A match that's ALREADY `active` when this screen opens (a reconnect) skips
/// the lobby UI entirely and goes straight back into the fight.
class PvpLobbyScreen extends StatefulWidget {
  final PvpMatch match;
  final String opponentName;

  const PvpLobbyScreen({super.key, required this.match, required this.opponentName});

  @override
  State<PvpLobbyScreen> createState() => _PvpLobbyScreenState();
}

class _PvpLobbyScreenState extends State<PvpLobbyScreen> {
  final _pvpSvc = PvpService();
  late PvpMatch _match;
  RealtimeChannel? _channel;
  bool _navigating = false;
  bool _busy = false;

  String get _myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _match = widget.match;
    if (_match.status == PvpMatchStatus.active) {
      _goToBattle(_match);
      return;
    }
    _watch();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
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
            final updated = PvpMatch.fromMap(payload.newRecord);
            if (!mounted) return;
            setState(() => _match = updated);
            if (updated.status == PvpMatchStatus.active) {
              _goToBattle(updated);
            } else if (updated.status == PvpMatchStatus.abandoned) {
              Navigator.of(context).pop();
            }
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
          partySize: 6,
          rewards: const [],
          showEnemyPreview: false,
        ),
      ),
    );
    if (team == null || team.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await _pvpSvc.setReady(_match.id, snapshotTeam(team));
      if (!mounted) return;
      setState(() => _match = updated);
      if (updated.status == PvpMatchStatus.active) _goToBattle(updated);
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
        if (ctrl.byId(j['instanceId'] as String) != null) ctrl.byId(j['instanceId'] as String)!,
    ];
    final enemies = [for (final j in oppSnap) combatantFromSnapshot(j, isPlayerSide: false)];
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
    final oppReady = _match.opponentReady(_myId);
    return Scaffold(
      backgroundColor: FoE.bg,
      appBar: AppBar(backgroundColor: FoE.bg, title: Text('Lobby — vs. ${widget.opponentName}')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _readyRow('You', myReady),
            const SizedBox(height: 8),
            _readyRow(widget.opponentName, oppReady),
            const SizedBox(height: 24),
            if (_busy)
              const CircularProgressIndicator()
            else if (!myReady)
              Pressable(
                onTap: _pickTeam,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: FoE.btn(active: true),
                  child: const Text('Pick your team', style: TextStyle(color: Colors.white)),
                ),
              )
            else
              Text(
                'Waiting for ${widget.opponentName}…',
                style: FoE.label().copyWith(color: FoE.textDim),
              ),
          ],
        ),
      ),
    );
  }

  Widget _readyRow(String name, bool ready) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        ready ? Icons.check_circle : Icons.hourglass_empty,
        color: ready ? FoE.positive : FoE.textDim,
        size: 20,
      ),
      const SizedBox(width: 8),
      Text('$name: ${ready ? 'Ready' : 'Picking team…'}', style: FoE.label(size: 14)),
    ],
  );
}
