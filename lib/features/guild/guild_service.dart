import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import 'guild_crest.dart';
import 'guild_models.dart';

/// Whether the signed-in player is in a guild — one cheap flag the rest of the
/// game can listen to (the Build menu offers the Guild Hall only to members,
/// and the hall leaves the map when its owner does). [GuildScreen] and the
/// settlement load keep it fresh.
/// Points needed for level 1..10 (mirrors `_guild_level_for` in migration 0072).
const List<int> kGuildLevelPoints = [0, 50, 150, 350, 700, 1200, 2000, 3200, 5000, 8000];

/// The bonus a guild of level 1..10 gives each member, as a fraction. The same
/// share applies to build speed, wood and stone yield and battle XP.
const List<double> kGuildBonusByLevel = [0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.10];

class GuildMembership extends ChangeNotifier {
  GuildMembership._();
  static final GuildMembership instance = GuildMembership._();

  /// Null = not asked yet (treated as "no guild", but nothing is torn down).
  bool? _inGuild;
  int level = 1;

  bool get inGuild => _inGuild ?? false;

  /// The level bonus (0 outside a guild).
  double get bonus =>
      inGuild ? kGuildBonusByLevel[(level - 1).clamp(0, kGuildBonusByLevel.length - 1)] : 0;
  bool get known => _inGuild != null;

  /// Never throws: a failed read leaves the last answer in place.
  Future<void> refresh() async {
    try {
      final g = await GuildService().loadMyGuild();
      final now = g != null;
      if (now != _inGuild || (g?.level ?? 1) != level) {
        _inGuild = now;
        level = g?.level ?? 1;
        notifyListeners();
      }
    } catch (_) {}
  }
}

/// Guild reads and actions. Every change goes through a database function
/// (`guild_*`, see migration 0069) — those enforce the rules; this class only
/// calls them and reads what the row-level security lets us see.
class GuildService {
  String get myId => supabase.auth.currentUser!.id;

  /// My guild, or null when I am in none.
  Future<Guild?> loadMyGuild() async {
    final mine = await supabase
        .from('guild_members')
        .select('guild_id')
        .eq('user_id', myId)
        .maybeSingle();
    if (mine == null) return null;
    final row = await supabase
        .from('guilds')
        .select()
        .eq('id', mine['guild_id'] as String)
        .single();
    final members = await supabase
        .from('guild_members')
        .select('user_id')
        .eq('guild_id', row['id'] as String);
    return Guild.fromMap(row, memberCount: (members as List).length);
  }

  Future<Map<String, String>> _names(List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await supabase
        .from('profiles')
        .select('id, username')
        .inFilter('id', ids);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['id'] as String: (r['username'] as String?) ?? 'Player',
    };
  }

  /// The roster, leader first, then officers, then by seniority.
  Future<List<GuildMember>> loadMembers(String guildId) async {
    final rows = await supabase
        .from('guild_members')
        .select()
        .eq('guild_id', guildId);
    final list = (rows as List).cast<Map<String, dynamic>>();
    final names = await _names([for (final r in list) r['user_id'] as String]);
    final out = [
      for (final r in list)
        GuildMember(
          userId: r['user_id'] as String,
          name: names[r['user_id']] ?? 'Player',
          role: GuildRole.parse(r['role'] as String?),
          joinedAt: DateTime.parse(r['joined_at'] as String),
        ),
    ];
    out.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      return byRole != 0 ? byRole : a.joinedAt.compareTo(b.joinedAt);
    });
    return out;
  }

  /// Guilds to browse, optionally filtered by name; fullest-but-not-full first.
  Future<List<Guild>> browse({String query = ''}) async {
    var q = supabase.from('guilds').select();
    final text = query.trim();
    if (text.isNotEmpty) q = q.ilike('name', '%$text%');
    final rows = await q.limit(60);
    final counts = await supabase.rpc('guild_member_counts') as List;
    final byGuild = {
      for (final c in counts.cast<Map<String, dynamic>>())
        c['guild_id'] as String: (c['members'] as num).toInt(),
    };
    final out = [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        Guild.fromMap(r, memberCount: byGuild[r['id']] ?? 0),
    ];
    out.sort((a, b) {
      if (a.isFull != b.isFull) return a.isFull ? 1 : -1;
      return b.memberCount.compareTo(a.memberCount);
    });
    return out;
  }

  /// Ids of the guilds I have asked to join (closed guilds).
  Future<Set<String>> myPendingRequests() async {
    final rows = await supabase
        .from('guild_join_requests')
        .select('guild_id')
        .eq('user_id', myId);
    return {
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        r['guild_id'] as String,
    };
  }

  Future<List<GuildRequest>> loadRequests(String guildId) async {
    final rows = await supabase
        .from('guild_join_requests')
        .select()
        .eq('guild_id', guildId)
        .order('created_at');
    final list = (rows as List).cast<Map<String, dynamic>>();
    final names = await _names([for (final r in list) r['user_id'] as String]);
    return [
      for (final r in list)
        GuildRequest(
          userId: r['user_id'] as String,
          name: names[r['user_id']] ?? 'Player',
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }

  // ── actions ───────────────────────────────────────────────

  Future<void> create({
    required String name,
    required String description,
    required GuildCrest crest,
    required bool isOpen,
  }) => supabase.rpc(
    'guild_create',
    params: {
      'p_name': name,
      'p_description': description,
      'p_crest': crest.toJson(),
      'p_open': isOpen,
    },
  );

  /// 'joined' (open guild) or 'requested' (closed guild).
  Future<String> join(String guildId) async =>
      (await supabase.rpc('guild_join', params: {'p_guild': guildId}))
          as String;

  Future<void> cancelRequest(String guildId) =>
      supabase.rpc('guild_cancel_request', params: {'p_guild': guildId});

  Future<void> decideRequest(String userId, {required bool accept}) =>
      supabase.rpc(
        'guild_decide_request',
        params: {'p_user': userId, 'p_accept': accept},
      );

  Future<void> leave() => supabase.rpc('guild_leave');

  Future<void> setRole(String userId, GuildRole role) => supabase.rpc(
    'guild_set_role',
    params: {'p_user': userId, 'p_role': role.name},
  );

  Future<void> kick(String userId) =>
      supabase.rpc('guild_kick', params: {'p_user': userId});

  Future<void> update({
    String? description,
    GuildCrest? crest,
    bool? isOpen,
  }) =>
      supabase.rpc(
        'guild_update',
        params: {
          'p_description': description,
          'p_crest': crest?.toJson(),
          'p_open': isOpen,
        },
      );

  // ── chat ──────────────────────────────────────────────────

  /// The latest 100 messages, oldest first.
  Future<List<GuildMessage>> loadChat(String guildId) async {
    final rows = await supabase
        .from('guild_messages')
        .select()
        .eq('guild_id', guildId)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(GuildMessage.fromMap)
        .toList()
        .reversed
        .toList();
  }

  Future<void> sendChat(String guildId, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await supabase.from('guild_messages').insert({
      'guild_id': guildId,
      'sender_id': myId,
      'body': text,
    });
  }

  RealtimeChannel subscribeChat(
    String guildId,
    void Function(GuildMessage) onInsert,
  ) {
    final channel = supabase.channel('guild_chat:$guildId');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'guild_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'guild_id',
            value: guildId,
          ),
          callback: (p) => onInsert(GuildMessage.fromMap(p.newRecord)),
        )
        .subscribe();
    return channel;
  }
}

/// A short, player-facing reason for a failed guild call.
String guildErrorText(Object e) {
  final s = e.toString();
  if (s.contains('guild_full')) return 'That guild is full.';
  if (s.contains('already_in_guild')) return 'Already in a guild.';
  if (s.contains('stud_resting')) return 'That monster is resting after its last loan.';
  if (s.contains('loan_limit')) return 'You have used today2019s loans.';
  if (s.contains('stud_limit')) return 'You can list 3 monsters at most.';
  if (s.contains('not_in_guild')) return 'You are not in a guild.';
  if (s.contains('not_allowed')) return 'You are not allowed to do that.';
  if (s.contains('23505') || s.contains('guilds_name_key')) {
    return 'That guild name is taken.';
  }
  if (s.contains('violates check constraint')) {
    return 'The name must be 3 to 24 characters.';
  }
  return 'That did not work. Try again.';
}
