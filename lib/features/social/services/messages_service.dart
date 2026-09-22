import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_client.dart';
import '../models/message.dart';

/// 1:1 direct messages between friends. Realtime delivery via a Postgres
/// Changes subscription, with [loadThread]/[listRecentMessages] as the
/// fallback/on-open sync for whatever arrived while the socket was down —
/// same "Realtime for live, a plain select as the backstop" shape the plan
/// calls for, and this is the first thing in the codebase to use Realtime.
class MessagesService {
  String get _myId => supabase.auth.currentUser!.id;

  Future<void> sendMessage(String toUserId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await supabase.from('messages').insert({
      'sender_id': _myId,
      'recipient_id': toUserId,
      'body': text,
    });
  }

  /// Every message with [otherUserId], oldest first.
  Future<List<ChatMessage>> loadThread(String otherUserId) async {
    final rows = await supabase
        .from('messages')
        .select()
        .or(
          'and(sender_id.eq.$_myId,recipient_id.eq.$otherUserId),'
          'and(sender_id.eq.$otherUserId,recipient_id.eq.$_myId)',
        )
        .order('created_at');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromMap)
        .toList();
  }

  /// The last 200 messages touching me, newest first — enough to build a
  /// thread-list summary (last message + unread count per friend) without a
  /// dedicated aggregate query.
  Future<List<ChatMessage>> listRecentMessages() async {
    final rows = await supabase
        .from('messages')
        .select()
        .or('sender_id.eq.$_myId,recipient_id.eq.$_myId')
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ChatMessage.fromMap)
        .toList();
  }

  Future<void> markThreadRead(String otherUserId) async {
    await supabase
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('sender_id', otherUserId)
        .eq('recipient_id', _myId)
        .filter('read_at', 'is', null);
  }

  Future<int> unreadCount() async {
    final rows = await supabase
        .from('messages')
        .select('id')
        .eq('recipient_id', _myId)
        .filter('read_at', 'is', null);
    return (rows as List).length;
  }

  /// Live delivery: fires [onInsert] for every new row where I'm the sender
  /// OR the recipient (a single filtered subscription can't OR two columns,
  /// so this subscribes unfiltered on the table and lets the callback check).
  /// Callers must `unsubscribe()` in dispose.
  RealtimeChannel subscribeToMessages(void Function(ChatMessage) onInsert) {
    final channel = supabase.channel('messages:$_myId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = payload.newRecord;
            final msg = ChatMessage.fromMap(row);
            if (msg.senderId == _myId || msg.recipientId == _myId) {
              onInsert(msg);
            }
          },
        )
        .subscribe();
    return channel;
  }
}
