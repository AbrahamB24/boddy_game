import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/app_navigator.dart';
import '../../creatures/pvp_lobby_screen.dart';
import '../models/pvp_match.dart';
import '../services/message_notifier.dart';
import '../services/pvp_notifier.dart';
import '../services/pvp_service.dart';
import '../social_screen.dart';
import 'social_kit.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/ui/game_text.dart';

/// Where a banner's main button goes: into the lobby (loading the match
/// fresh — what the banner saw may be minutes old), or to the PvP list for a
/// challenge. Works from anywhere: it uses the app's navigator key, not a
/// screen's context.
Future<void> joinPvpAlert(PvpAlert alert) async {
  final nav = appNavigatorKey.currentState;
  final notifier = PvpNotifier.instance;
  notifier.dismiss(alert);
  if (nav == null) return;

  if (alert.kind == PvpAlertKind.challenged) {
    pushMenu(nav.context, const SocialScreen(startOnPvp: true));
    return;
  }
  // Already looking at this lobby.
  if (notifier.openLobbyId == alert.matchId) return;
  try {
    final match = await PvpService().loadMatch(alert.matchId);
    if (match.status == PvpMatchStatus.abandoned ||
        match.status == PvpMatchStatus.finished) {
      return;
    }
    nav.push(
      MaterialPageRoute(
        builder: (_) =>
            PvpLobbyScreen(match: match, opponentName: alert.opponentName),
      ),
    );
  } catch (_) {
    // The match is gone or the network is; the list shows the truth.
  }
}

/// Where a message banner goes: the chat with that friend, in Social.
void joinMessageAlert(MessageAlert alert) {
  final nav = appNavigatorKey.currentState;
  MessageNotifier.instance.dismiss(alert);
  if (nav == null) return;
  pushMenu(nav.context, SocialScreen(startChatWith: alert.friendId));
}

/// One line of banner, whatever it is about.
class _BannerItem {
  final String key;
  final String name;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;
  final DateTime at;

  const _BannerItem({
    required this.key,
    required this.name,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    required this.at,
  });
}

/// Everything waiting to be shown — PvP alerts and new messages — newest first.
List<_BannerItem> _bannerItems() {
  final pvp = PvpNotifier.instance;
  final msg = MessageNotifier.instance;
  final items = [
    for (final a in pvp.alerts)
      _BannerItem(
        key: 'pvp:${a.matchId}:${a.kind.name}',
        name: a.opponentName,
        text: a.text,
        actionLabel: a.actionLabel,
        onAction: () => joinPvpAlert(a),
        onDismiss: () => pvp.dismiss(a),
        at: a.at,
      ),
    for (final a in msg.alerts)
      _BannerItem(
        key: 'msg:${a.friendId}:${a.at.microsecondsSinceEpoch}',
        name: a.friendName,
        text: '${a.friendName}: ${a.text}',
        actionLabel: 'Reply',
        onAction: () => joinMessageAlert(a),
        onDismiss: () => msg.dismiss(a),
        at: a.at,
      ),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return items;
}

/// The banner for PvP and messages, hung above the navigator so it shows on
/// whatever screen the player is on. One banner at a time (the newest); a count
/// says how many more wait behind it. Dismissing it does not end anything — the match stays
/// in the PvP list, and the lobby can be entered from there.
class PvpBannerHost extends StatelessWidget {
  const PvpBannerHost({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      PvpNotifier.instance,
      MessageNotifier.instance,
    ]),
    builder: (context, _) {
      final alerts = _bannerItems();
      return Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, -0.4),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: alerts.isEmpty
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : _Banner(
                      key: ValueKey(alerts.first.key),
                      item: alerts.first,
                      more: alerts.length - 1,
                    ),
            ),
          ),
        ),
      );
    },
  );
}

class _Banner extends StatelessWidget {
  final _BannerItem item;
  final int more;

  const _Banner({super.key, required this.item, required this.more});

  @override
  Widget build(BuildContext context) {
    final action = item.actionLabel;
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: vr(14),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
            ),
            border: Border.all(color: CreamPalette.gold, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SocialAvatar(item.name, size: 32),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    item.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(
                      size: 13,
                    ).copyWith(color: kBoxInk, fontWeight: FontWeight.w400),
                  ),
                ),
                if (more > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '+$more',
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  ),
                ],
                const SizedBox(width: 10),
                if (action != null) ...[
                  SocialGoldButton(action, height: 30, onTap: item.onAction),
                  const SizedBox(width: 8),
                ],
                SocialGlyphButton(Icons.close, size: 28, onTap: item.onDismiss),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
