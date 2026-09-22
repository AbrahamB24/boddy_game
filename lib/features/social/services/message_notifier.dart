import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/message.dart';
import 'alert_effects.dart';
import 'alert_prefs.dart';
import 'friends_service.dart';
import 'messages_service.dart';

/// One new message, as a banner.
class MessageAlert {
  final String friendId;
  final String friendName;
  final String text;
  final DateTime at;

  MessageAlert({
    required this.friendId,
    required this.friendName,
    required String body,
  }) : text = body.length > 70 ? '${body.substring(0, 70)}…' : body,
       at = DateTime.now();
}

/// The app-wide watcher for messages (user 2026-09-19): how many are unread —
/// the Social button's badge — and a banner for a new one while the player is
/// anywhere but Social.
///
/// Started with the session, like [PvpNotifier]. Two things keep it quiet: the
/// Social screen being open (it shows its own unread counts and the chat) and
/// the chat with that very friend being on screen.
class MessageNotifier extends ChangeNotifier {
  static final MessageNotifier instance = MessageNotifier._();
  MessageNotifier._();

  final _messages = MessagesService();
  final _friends = FriendsService();

  final List<MessageAlert> _alerts = [];
  final Map<String, String> _names = {};
  RealtimeChannel? _channel;
  String? _userId;

  /// Unread messages addressed to me, as of the last count.
  int unread = 0;

  /// Set by the Social screen while it is open.
  bool socialOpen = false;

  /// The friend whose chat is on screen, if any.
  String? openChatWith;

  /// Newest first.
  List<MessageAlert> get alerts => List.unmodifiable(_alerts);

  Future<void> start() async {
    final me = supabase.auth.currentUser?.id;
    if (me == null || _userId == me) return;
    stop();
    _userId = me;
    await refreshUnread();
    _channel = supabase
        .channel('message_notifier:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) =>
              _onInsert(ChatMessage.fromMap(payload.newRecord)),
        )
        .subscribe();
  }

  void stop() {
    _channel?.unsubscribe();
    _channel = null;
    _alerts.clear();
    _userId = null;
    unread = 0;
    socialOpen = false;
    openChatWith = null;
    notifyListeners();
  }

  /// Reads the real count — after a chat marked its messages read, or on start.
  Future<void> refreshUnread() async {
    if (_userId == null) return;
    try {
      unread = await _messages.unreadCount();
      notifyListeners();
    } catch (_) {
      // The badge stays as it was; the next message or open fixes it.
    }
  }

  Future<void> _onInsert(ChatMessage m) async {
    final me = _userId;
    if (me == null || m.recipientId != me) return;
    final quiet = socialOpen || openChatWith == m.senderId;
    if (quiet) {
      // The chat or list marks it read on its own; the count catches up then.
      unread++;
      notifyListeners();
      return;
    }
    unread++;
    // Banners switched off in Profile: the count above still shows.
    if (!AlertPrefs.bannersOn) {
      notifyListeners();
      return;
    }
    var name = _names[m.senderId];
    if (name == null) {
      try {
        final found = await _friends.usernamesFor([m.senderId]);
        name = found[m.senderId] ?? '(unknown)';
        _names[m.senderId] = name;
      } catch (_) {
        name = '(unknown)';
      }
    }
    // One banner per friend: the newest message replaces their earlier one.
    _alerts.removeWhere((a) => a.friendId == m.senderId);
    final alert = MessageAlert(
      friendId: m.senderId,
      friendName: name,
      body: m.body,
    );
    _alerts.insert(0, alert);
    announceSocial(key: 'msg:${m.senderId}', title: name, body: alert.text);
    notifyListeners();
  }

  void dismiss(MessageAlert alert) {
    _alerts.remove(alert);
    notifyListeners();
  }
}
