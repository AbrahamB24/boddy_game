/// One row of `messages` — see supabase/migrations/0048_social_messages.sql.
class ChatMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: m['id'] as String,
    senderId: m['sender_id'] as String,
    recipientId: m['recipient_id'] as String,
    body: m['body'] as String,
    createdAt: DateTime.parse(m['created_at'] as String),
    readAt: m['read_at'] == null
        ? null
        : DateTime.parse(m['read_at'] as String),
  );

  bool sentByMe(String myUserId) => senderId == myUserId;
}

/// One row of a thread list: the other user plus the latest message and how
/// many are unread — what [MessagesScreen] shows per friend.
class MessageThreadSummary {
  final String otherUserId;
  final String otherUsername;
  final ChatMessage lastMessage;
  final int unreadCount;

  const MessageThreadSummary({
    required this.otherUserId,
    required this.otherUsername,
    required this.lastMessage,
    required this.unreadCount,
  });
}
