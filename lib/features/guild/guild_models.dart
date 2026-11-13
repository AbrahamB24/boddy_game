// Guild data — see supabase/migrations/0069_guilds.sql.

/// The most members a guild can have (enforced by the database too).
const int kGuildMaxMembers = 50;

enum GuildRole {
  leader,
  officer,
  member;

  static GuildRole parse(String? s) => switch (s) {
    'leader' => GuildRole.leader,
    'officer' => GuildRole.officer,
    _ => GuildRole.member,
  };

  String get label => switch (this) {
    GuildRole.leader => 'Leader',
    GuildRole.officer => 'Officer',
    GuildRole.member => 'Member',
  };

  /// Officers and the leader let people in and may remove plain members.
  bool get canModerate => this != GuildRole.member;
}

class Guild {
  final String id;
  final String name;
  final String description;
  final int emblem;
  final bool isOpen;
  final String leaderId;
  final int level;
  final int points;
  final int memberCount;

  const Guild({
    required this.id,
    required this.name,
    required this.description,
    required this.emblem,
    required this.isOpen,
    required this.leaderId,
    required this.level,
    required this.points,
    this.memberCount = 0,
  });

  factory Guild.fromMap(Map<String, dynamic> m, {int memberCount = 0}) => Guild(
    id: m['id'] as String,
    name: m['name'] as String,
    description: (m['description'] as String?) ?? '',
    emblem: (m['emblem'] as num?)?.toInt() ?? 0,
    isOpen: (m['is_open'] as bool?) ?? true,
    leaderId: m['leader_id'] as String,
    level: (m['level'] as num?)?.toInt() ?? 1,
    points: (m['points'] as num?)?.toInt() ?? 0,
    memberCount: memberCount,
  );

  bool get isFull => memberCount >= kGuildMaxMembers;
}

class GuildMember {
  final String userId;
  final String name;
  final GuildRole role;
  final DateTime joinedAt;

  const GuildMember({
    required this.userId,
    required this.name,
    required this.role,
    required this.joinedAt,
  });
}

class GuildRequest {
  final String userId;
  final String name;
  final DateTime createdAt;

  const GuildRequest({
    required this.userId,
    required this.name,
    required this.createdAt,
  });
}

class GuildMessage {
  final String id;
  final String senderId;
  final String body;
  final DateTime createdAt;

  const GuildMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory GuildMessage.fromMap(Map<String, dynamic> m) => GuildMessage(
    id: m['id'] as String,
    senderId: m['sender_id'] as String,
    body: m['body'] as String,
    createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
  );
}
