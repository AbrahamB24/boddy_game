import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import 'models/pvp_match.dart';
import 'social_actions.dart';
import 'social_controller.dart';
import 'widgets/social_kit.dart';
import '../../core/ui/game_text.dart';

/// The PvP list: challenges waiting on you, and every match that is under way —
/// a challenge I sent nobody accepted yet, an accepted match whose lobby anyone
/// may enter at any time, a fight in progress. Each match row says where the
/// OTHER player is (not yet accepted, not in the lobby yet, waiting in the
/// lobby, ready) and offers the way in and the way out for good.
///
/// Challenging someone starts from their chat (or the friend list); this is
/// where it comes back.
class PvpPane extends StatefulWidget {
  final SocialController ctrl;

  const PvpPane({super.key, required this.ctrl});

  @override
  State<PvpPane> createState() => _PvpPaneState();
}

class _PvpPaneState extends State<PvpPane> {
  String? _busyMatchId;
  // "Waiting in the lobby" is a heartbeat that ages, so the stage is repainted
  // now and then even when no row changed.
  Timer? _ticker;

  SocialController get _ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl.refreshPvp();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _accept(PvpMatch m) async {
    setState(() => _busyMatchId = m.id);
    try {
      await acceptChallenge(context, _ctrl, m);
    } finally {
      if (mounted) setState(() => _busyMatchId = null);
    }
  }

  Future<void> _leave(PvpMatch m) async {
    final name = _ctrl.nameOf(m.otherUserId(_ctrl.myId));
    if (await leaveMatchFlow(context, m, name)) await _ctrl.refreshPvp();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _ctrl,
    builder: (context, _) {
      final incoming = _ctrl.incoming;
      final matches = [..._ctrl.open, ..._ctrl.sent];
      if (incoming.isEmpty && matches.isEmpty) {
        return Center(
          child: Text(
            'No pending challenges.\nChallenge a friend from their chat.',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        children: [
          if (incoming.isNotEmpty) ...[
            socialSection('Incoming challenges · ${incoming.length}'),
            for (final m in incoming) _incomingRow(m),
            const SizedBox(height: 10),
          ],
          if (matches.isNotEmpty) ...[
            socialSection('Matches · ${matches.length}'),
            for (final m in matches) _matchRow(m),
          ],
        ],
      );
    },
  );

  Widget _gap(Widget row) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: row);

  Widget _title(String title, [String? sub]) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.label(
            size: 13,
          ).copyWith(color: kBoxInk, fontWeight: FontWeight.w400),
        ),
        if (sub != null)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
          ),
      ],
    ),
  );

  Widget _incomingRow(PvpMatch m) {
    final name = _ctrl.nameOf(m.playerA);
    final busy = _busyMatchId == m.id;
    final stats = _ctrl.stats[m.playerA];
    return _gap(
      socialRow(
        warm: true,
        child: Row(
          children: [
            SocialAvatar(name, size: 30),
            const SizedBox(width: 10),
            _title(
              '$name challenged you',
              stats == null
                  ? 'Rating unknown'
                  : 'Rating ${recordLine(stats.rating, stats.wins, stats.losses)}',
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CreamPalette.goldDeep,
                ),
              )
            else ...[
              SocialGoldButton('Accept', height: 28, onTap: () => _accept(m)),
              const SizedBox(width: 8),
              SocialGlyphButton(
                Icons.close,
                size: 28,
                tooltip: 'Decline',
                onTap: () => _ctrl.declineChallenge(m),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One match, from either state: the stage of the other player as the chip,
  /// Enter (any time — the lobby is a room, not an appointment) and, unless
  /// the fight is already running, the way out for good.
  Widget _matchRow(PvpMatch m) {
    final name = _ctrl.nameOf(m.otherUserId(_ctrl.myId));
    final stage = m.opponentStage(_ctrl.myId);
    final active = m.status == PvpMatchStatus.active;
    final pending = m.status == PvpMatchStatus.pending;
    return _gap(
      socialRow(
        onTap: () => openMatch(context, _ctrl, m),
        child: Row(
          children: [
            SocialAvatar(name, size: 30),
            const SizedBox(width: 10),
            _title('vs $name'),
            StageChip(stage),
            const SizedBox(width: 8),
            SocialGoldButton(
              active
                  ? 'Resume'
                  : pending
                  ? 'Enter lobby'
                  : 'Enter',
              height: 28,
              onTap: () => openMatch(context, _ctrl, m),
            ),
            if (!active) ...[
              const SizedBox(width: 8),
              SocialGlyphButton(
                Icons.close,
                size: 28,
                tooltip: pending ? 'Withdraw challenge' : 'Leave lobby',
                onTap: () => _leave(m),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
