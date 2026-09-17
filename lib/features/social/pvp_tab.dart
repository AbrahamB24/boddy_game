import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../creatures/pvp_lobby_screen.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/pvp_match.dart';
import 'services/friends_service.dart';
import 'services/pvp_service.dart';

/// PvP: incoming challenges (accept → straight into the Lobby — see
/// pvp_lobby_screen.dart; decline), open matches either side can still act
/// on (`accepted` → re-enter the Lobby, `active` → resume a live fight),
/// and — purely informational — challenges I've sent that are still
/// awaiting a response.
class PvpTab extends StatefulWidget {
  const PvpTab({super.key});

  @override
  State<PvpTab> createState() => _PvpTabState();
}

class _PvpTabState extends State<PvpTab> {
  final _pvpSvc = PvpService();
  final _friendsSvc = FriendsService();

  String get _myId => supabase.auth.currentUser!.id;

  bool _loading = true;
  List<PvpMatch> _incoming = [];
  List<PvpMatch> _open = [];
  List<PvpMatch> _sent = [];
  Map<String, String?> _names = {};
  String? _busyMatchId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _pvpSvc.loadPendingChallenges(),
      _pvpSvc.loadOpenMatches(),
      _pvpSvc.loadSentChallenges(),
    ]);
    final incoming = results[0];
    final open = results[1];
    final sent = results[2];
    final otherIds = {
      ...incoming.map((m) => m.playerA),
      ...open.map((m) => m.otherUserId(_myId)),
      ...sent.map((m) => m.playerB),
    }.toList();
    final names = await _friendsSvc.usernamesFor(otherIds);
    if (!mounted) return;
    setState(() {
      _incoming = incoming;
      _open = open;
      _sent = sent;
      _names = names;
      _loading = false;
    });
  }

  Future<void> _accept(PvpMatch match) async {
    setState(() => _busyMatchId = match.id);
    try {
      final accepted = await _pvpSvc.acceptChallenge(match.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PvpLobbyScreen(
            match: accepted,
            opponentName: _names[match.playerA] ?? '(unknown)',
          ),
        ),
      );
      _load();
    } finally {
      if (mounted) setState(() => _busyMatchId = null);
    }
  }

  Future<void> _decline(PvpMatch match) async {
    await _pvpSvc.declineChallenge(match.id);
    _load();
  }

  Future<void> _openMatch(PvpMatch match) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PvpLobbyScreen(
          match: match,
          opponentName: _names[match.otherUserId(_myId)] ?? '(unknown)',
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_incoming.isEmpty && _open.isEmpty && _sent.isEmpty) {
      return Center(
        child: Text(
          'No pending challenges.\nChallenge a friend from the Friends tab.',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 12).copyWith(color: ParchmentSheet.inkFaint),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        if (_incoming.isNotEmpty) ...[
          _section('Incoming challenges'),
          for (final m in _incoming) _incomingRow(m),
          const SizedBox(height: 16),
        ],
        if (_open.isNotEmpty) ...[
          _section('Open matches'),
          for (final m in _open) _openRow(m),
          const SizedBox(height: 16),
        ],
        if (_sent.isNotEmpty) ...[
          _section('Sent — awaiting response'),
          for (final m in _sent) _sentRow(m),
        ],
      ],
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: FoE.label(size: 12).copyWith(
        color: ParchmentSheet.accent,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _incomingRow(PvpMatch m) {
    final name = _names[m.playerA] ?? '(unknown)';
    final busy = _busyMatchId == m.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: ParchmentSheet.card,
      child: Row(
        children: [
          Icon(Icons.sports_martial_arts, color: ParchmentSheet.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$name challenged you',
              style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
            ),
          ),
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            Pressable(
              onTap: () => _accept(m),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.check_circle_outline, color: FoE.positive),
              ),
            ),
            Pressable(
              onTap: () => _decline(m),
              child: Icon(Icons.cancel_outlined, color: ParchmentSheet.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _openRow(PvpMatch m) {
    final name = _names[m.otherUserId(_myId)] ?? '(unknown)';
    final label = m.status == PvpMatchStatus.active
        ? 'vs $name — in progress, tap to resume'
        : 'vs $name — enter the lobby';
    return Pressable(
      onTap: () => _openMatch(m),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: ParchmentSheet.card,
        child: Row(
          children: [
            Icon(
              m.status == PvpMatchStatus.active ? Icons.play_circle_outline : Icons.meeting_room_outlined,
              color: ParchmentSheet.accent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink)),
            ),
            Icon(Icons.chevron_right_rounded, color: ParchmentSheet.inkFaint),
          ],
        ),
      ),
    );
  }

  Widget _sentRow(PvpMatch m) {
    final name = _names[m.playerB] ?? '(unknown)';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: ParchmentSheet.card,
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, color: ParchmentSheet.inkFaint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Waiting for $name to respond',
              style: FoE.label(size: 13).copyWith(color: ParchmentSheet.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
