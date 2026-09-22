import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../creatures/pvp_lobby_screen.dart';
import 'models/pvp_match.dart';
import 'services/pvp_notifier.dart';
import 'services/pvp_service.dart';
import 'social_controller.dart';
import 'widgets/social_kit.dart' show recordLine;
import 'visit_city_screen.dart';

/// The verbs several panes share — the chat header, the friend list and the
/// PvP list all offer "visit", "challenge" and "enter the lobby", and they all
/// have to do exactly the same thing.

/// Opens the friend's city. Returns true when "Message" was tapped there, so
/// a caller that is not already in that friend's chat can jump to it.
Future<bool> visitCity(
  BuildContext context,
  SocialController ctrl,
  SocialFriend friend,
) async {
  final stats = ctrl.stats[friend.userId];
  final result = await pushMenu<bool>(
    context,
    VisitCityScreen(
      friendUserId: friend.userId,
      friendName: friend.name,
      record: stats == null
          ? null
          : recordLine(stats.rating, stats.wins, stats.losses),
      onChallenge: () => challengeFriend(context, ctrl, friend),
    ),
  );
  return result ?? false;
}

Future<void> challengeFriend(
  BuildContext context,
  SocialController ctrl,
  SocialFriend friend,
) async {
  final messenger = ScaffoldMessenger.of(context);
  // One open challenge per friend: a second one would only stack up in their
  // list. The chat and the PvP list both offer the cancel.
  if (ctrl.sent.any((m) => m.playerB == friend.userId)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'You already challenged ${friend.name} - cancel that one first.',
        ),
      ),
    );
    return;
  }
  try {
    await ctrl.challenge(friend.userId);
    messenger.showSnackBar(
      SnackBar(content: Text('Challenge sent to ${friend.name}.')),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not send it: $e')));
  }
}

/// Answers a challenge with yes and walks into the lobby — the flow the PvP
/// list always had: accepting is only a consent, both sides then build a team
/// and ready up in the lobby.
Future<void> acceptChallenge(
  BuildContext context,
  SocialController ctrl,
  PvpMatch match,
) async {
  final accepted = await ctrl.acceptChallenge(match);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PvpLobbyScreen(
        match: accepted,
        opponentName: ctrl.nameOf(match.playerA),
      ),
    ),
  );
  await ctrl.refreshPvp();
}

/// Enters a match both sides already agreed to — the lobby, or straight back
/// into a fight that is running.
Future<void> openMatch(
  BuildContext context,
  SocialController ctrl,
  PvpMatch match,
) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PvpLobbyScreen(
        match: match,
        opponentName: ctrl.nameOf(match.otherUserId(ctrl.myId)),
      ),
    ),
  );
  await ctrl.refreshPvp();
}

/// "Remove Mira?" — ending a friendship cannot be undone (a new request has to
/// be sent and accepted), so it is asked first.
Future<bool> confirmRemoveFriend(BuildContext context, String name) =>
    confirmDialog(
      context,
      title: 'Remove $name?',
      body: 'You will need a new request to be friends again.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep',
    );

/// Leaves a match for good. A challenge nobody answered is withdrawn (no
/// question); an accepted match's lobby is left after asking, and the other side
/// is told.
/// Returns whether it was left. (Going BACK out of a lobby is not this: that
/// only minimises it.)
Future<bool> leaveMatchFlow(
  BuildContext context,
  PvpMatch match,
  String opponentName,
) async {
  final pending = match.status == PvpMatchStatus.pending;
  // Taking back a challenge nobody answered costs nothing: no question. Leaving
  // an accepted lobby ends a match the other side agreed to, so that one asks.
  if (!pending) {
    final ok = await confirmDialog(
      context,
      title: 'Leave the lobby?',
      body:
          'The match with $opponentName ends. Going back instead keeps the '
          'lobby open.',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
    );
    if (!ok) return false;
  }
  // My own doing — the row's change must not come back as a banner.
  PvpNotifier.instance.markMine(match.id);
  final svc = PvpService();
  if (pending) {
    await svc.cancelChallenge(match.id);
  } else {
    await svc.leaveMatch(match.id);
  }
  return true;
}

/// A small cream yes/no dialog.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: CreamPalette.dim,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: SizedBox(
        width: 300,
        child: creamCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: FoE.title(size: 15).copyWith(color: kBoxInk),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: raisedTile(radius: 12),
                        child: Text(
                          cancelLabel,
                          style: FoE.label(size: 13).copyWith(color: kBoxInk),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        height: 36,
                        alignment: Alignment.center,
                        decoration: goldButton(),
                        child: Text(
                          confirmLabel,
                          style: FoE.label(size: 13).copyWith(color: kBoxInk),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return ok ?? false;
}
