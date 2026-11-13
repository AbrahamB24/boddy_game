import 'dart:async';

import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../settlement/settlement_controller.dart';
import '../social/social_actions.dart' show confirmDialog;
import '../social/widgets/social_kit.dart';
import 'guild_models.dart';
import 'guild_service.dart';

enum _Tab { members, chat, requests, manage }

/// The guild menu. Without a guild it is a browse list plus "Found a guild";
/// with one it is the guild's page: members, chat, join requests (officers) and
/// the leader's settings.
///
/// The game never needs a guild — this screen is only ever opened on purpose.
class GuildScreen extends StatefulWidget {
  const GuildScreen({super.key});

  @override
  State<GuildScreen> createState() => _GuildScreenState();
}

class _GuildScreenState extends State<GuildScreen> {
  final _svc = GuildService();

  bool _loading = true;
  bool _busy = false;
  Guild? _guild;
  List<GuildMember> _members = [];
  List<GuildRequest> _requests = [];

  // Browse (no guild)
  List<Guild> _browse = [];
  Set<String> _pending = {};
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _creating = false;
  final _newName = TextEditingController();
  final _newDesc = TextEditingController();
  bool _newOpen = true;

  // Guild page
  _Tab _tab = _Tab.members;

  // Chat
  List<GuildMessage> _chat = [];
  RealtimeChannel? _chatChannel;
  final _chatInput = TextEditingController();
  final _chatScroll = ScrollController();

  GuildRole get _myRole => _members
      .firstWhere(
        (m) => m.userId == _svc.myId,
        orElse: () => GuildMember(
          userId: _svc.myId,
          name: '',
          role: GuildRole.member,
          joinedAt: DateTime.now(),
        ),
      )
      .role;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _chatChannel?.unsubscribe();
    _searchCtrl.dispose();
    _newName.dispose();
    _newDesc.dispose();
    _chatInput.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final g = await _svc.loadMyGuild();
      unawaited(GuildMembership.instance.refresh());
      if (g == null) {
        _chatChannel?.unsubscribe();
        _chatChannel = null;
        final results = await Future.wait([
          _svc.browse(query: _searchCtrl.text),
          _svc.myPendingRequests(),
        ]);
        if (!mounted) return;
        setState(() {
          _guild = null;
          _members = [];
          _requests = [];
          _browse = results[0] as List<Guild>;
          _pending = results[1] as Set<String>;
          _loading = false;
        });
        return;
      }
      final members = await _svc.loadMembers(g.id);
      final me = members.where((m) => m.userId == _svc.myId);
      final canModerate = me.isNotEmpty && me.first.role.canModerate;
      final requests = canModerate
          ? await _svc.loadRequests(g.id)
          : <GuildRequest>[];
      if (!mounted) return;
      setState(() {
        _guild = g;
        _members = members;
        _requests = requests;
        _loading = false;
        if (!canModerate && (_tab == _Tab.requests)) _tab = _Tab.members;
        if (_myRole != GuildRole.leader && _tab == _Tab.manage) {
          _tab = _Tab.members;
        }
      });
      await _openChat(g.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.snack(guildErrorText(e), error: true);
    }
  }

  Future<void> _openChat(String guildId) async {
    if (_chatChannel != null) return;
    _chat = await _svc.loadChat(guildId);
    _chatChannel = _svc.subscribeChat(guildId, (m) {
      if (!mounted || _chat.any((x) => x.id == m.id)) return;
      setState(() => _chat = [..._chat, m]);
      _scrollChatDown();
    });
    if (mounted) setState(() {});
    _scrollChatDown();
  }

  void _scrollChatDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_chatScroll.hasClients) {
      _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
    }
  });

  /// Runs a guild action, shows its failure as a toast, reloads afterwards.
  Future<void> _do(Future<void> Function() action, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (done != null && mounted) context.snack(done);
    } catch (e) {
      if (mounted) context.snack(guildErrorText(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
    await _reload();
  }

  // ── build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: _guild?.name ?? 'Guilds',
    trailing: _guild == null
        ? null
        : _pill('${_members.length}/$kGuildMaxMembers members'),
    child: _loading
        ? const Center(child: CircularProgressIndicator(color: CreamPalette.gold))
        : (_guild == null
              ? (SettlementController().introStep.isActive
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: socialHint(
                          'Guilds open up once you have finished the tutorial.',
                        ),
                      )
                    : _noGuild())
              : _guildPage()),
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(9),
    ),
    child: Text(text, style: FoE.value(size: 11).copyWith(color: kBoxInk)),
  );

  Widget _field(
    TextEditingController c,
    String hint, {
    ValueChanged<String>? onChanged,
    int? maxLength,
    int maxLines = 1,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(12),
    ),
    child: TextField(
      controller: c,
      onChanged: onChanged,
      maxLength: maxLength,
      maxLines: maxLines,
      style: FoE.label(size: 12.5).copyWith(color: kBoxInk),
      cursorColor: CreamPalette.accent,
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        counterText: '',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        hintText: hint,
        hintStyle: FoE.label(size: 12.5).copyWith(color: kBoxInkFaint),
      ),
    ),
  );

  Widget _name(String name, [String? sub]) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.label(size: 13).copyWith(color: kBoxInk),
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

  Widget _gap(Widget w) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: w);

  // ── no guild: browse + found ──────────────────────────────

  Widget _noGuild() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    children: [
      socialHint(
        'A guild is optional. Members help each other finish building, '
        'breeding and healing faster, and play for shared goals.',
      ),
      if (_creating) _createForm() else _foundButton(),
      const SizedBox(height: 14),
      socialSection('Find a guild'),
      _field(
        _searchCtrl,
        'Search by name',
        onChanged: (_) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 350), _reload);
        },
      ),
      const SizedBox(height: 10),
      if (_browse.isEmpty) socialHint('No guilds found.'),
      for (final g in _browse) _gap(_guildRow(g)),
    ],
  );

  Widget _foundButton() => Align(
    alignment: Alignment.centerLeft,
    child: SocialGoldButton(
      'Found a guild',
      onTap: () => setState(() => _creating = true),
    ),
  );

  Widget _createForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      socialSection('Found a guild'),
      _field(_newName, 'Guild name (3–24 characters)', maxLength: 24),
      const SizedBox(height: 8),
      _field(
        _newDesc,
        'Description (optional)',
        maxLength: 280,
        maxLines: 2,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          SocialTileButton(
            _newOpen ? 'Open to everyone' : 'Join by request',
            onTap: () => setState(() => _newOpen = !_newOpen),
          ),
          const Spacer(),
          SocialTileButton(
            'Cancel',
            onTap: () => setState(() => _creating = false),
          ),
          const SizedBox(width: 8),
          SocialGoldButton(
            'Found it',
            onTap: _busy
                ? null
                : () => _do(
                    () => _svc.create(
                      name: _newName.text,
                      description: _newDesc.text,
                      emblem: 0,
                      isOpen: _newOpen,
                    ),
                    done: 'Guild founded.',
                  ),
          ),
        ],
      ),
    ],
  );

  Widget _guildRow(Guild g) {
    final asked = _pending.contains(g.id);
    final Widget action;
    if (g.isFull) {
      action = _tag('Full');
    } else if (asked) {
      action = SocialTileButton(
        'Cancel request',
        height: 28,
        onTap: _busy ? null : () => _do(() => _svc.cancelRequest(g.id)),
      );
    } else {
      action = SocialGoldButton(
        g.isOpen ? 'Join' : 'Request',
        height: 28,
        onTap: _busy
            ? null
            : () => _do(() async {
                final r = await _svc.join(g.id);
                if (r == 'requested' && mounted) {
                  context.snack('Request sent.');
                }
              }),
      );
    }
    return socialRow(
      height: 54,
      child: Row(
        children: [
          SocialAvatar.letter(g.name),
          const SizedBox(width: 10),
          _name(
            g.name,
            'Level ${g.level} · ${g.memberCount}/$kGuildMaxMembers'
            '${g.isOpen ? '' : ' · by request'}'
            '${g.description.isEmpty ? '' : ' · ${g.description}'}',
          ),
          action,
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: vr(8),
      border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.55)),
    ),
    child: Text(text, style: FoE.dim(size: 10).copyWith(color: kBoxInkFaint)),
  );

  // ── with a guild ──────────────────────────────────────────

  Widget _guildPage() {
    final g = _guild!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              SocialAvatar.letter(g.name, size: 40),
              const SizedBox(width: 10),
              _name(
                'Level ${g.level}${g.isOpen ? '' : ' · by request'}',
                g.description.isEmpty ? 'No description yet.' : g.description,
              ),
              _seg(),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            _Tab.members => _membersTab(),
            _Tab.chat => _chatTab(),
            _Tab.requests => _requestsTab(),
            _Tab.manage => _manageTab(),
          },
        ),
      ],
    );
  }

  Widget _seg() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _segItem('Members', _Tab.members),
        _segItem('Chat', _Tab.chat),
        if (_myRole.canModerate)
          _segItem('Requests', _Tab.requests, badge: _requests.length),
        if (_myRole == GuildRole.leader) _segItem('Manage', _Tab.manage),
      ],
    ),
  );

  Widget _segItem(String label, _Tab tab, {int badge = 0}) {
    final on = _tab == tab;
    return Pressable(
      onTap: () {
        setState(() => _tab = tab);
        if (tab == _Tab.chat) _scrollChatDown();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: on
            ? BoxDecoration(
                color: CreamPalette.gold,
                borderRadius: vr(9),
                boxShadow: const [
                  BoxShadow(color: CreamPalette.tanShadow, offset: Offset(0, 2)),
                ],
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: on ? kBoxInk : kBoxInkSoft,
              ),
            ),
            if (badge > 0) ...[const SizedBox(width: 5), CountBadge(badge)],
          ],
        ),
      ),
    );
  }

  // Members ------------------------------------------------

  Widget _membersTab() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    children: [
      for (final m in _members) _gap(_memberRow(m)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: SocialTileButton('Leave guild', onTap: _busy ? null : _leave),
      ),
    ],
  );

  Widget _memberRow(GuildMember m) {
    final mine = m.userId == _svc.myId;
    final me = _myRole;
    final canKick =
        !mine &&
        m.role != GuildRole.leader &&
        (me == GuildRole.leader ||
            (me == GuildRole.officer && m.role == GuildRole.member));
    return socialRow(
      child: Row(
        children: [
          SocialAvatar(m.name),
          const SizedBox(width: 10),
          _name(mine ? '${m.name} (you)' : m.name, m.role.label),
          if (me == GuildRole.leader && !mine) ...[
            SocialTileButton(
              m.role == GuildRole.officer ? 'Demote' : 'Promote',
              height: 28,
              onTap: _busy
                  ? null
                  : () => _do(
                      () => _svc.setRole(
                        m.userId,
                        m.role == GuildRole.officer
                            ? GuildRole.member
                            : GuildRole.officer,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
          ],
          if (canKick)
            SocialTileButton(
              'Remove',
              height: 28,
              onTap: _busy ? null : () => _kick(m),
            ),
        ],
      ),
    );
  }

  Future<void> _kick(GuildMember m) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove ${m.name}?',
      body: 'They leave the guild and can apply again.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep',
    );
    if (ok && mounted) await _do(() => _svc.kick(m.userId));
  }

  Future<void> _leave() async {
    final onlyOne = _members.length == 1;
    final ok = await confirmDialog(
      context,
      title: 'Leave ${_guild!.name}?',
      body: onlyOne
          ? 'You are the last member: the guild will be closed.'
          : (_myRole == GuildRole.leader
                ? 'Leadership passes to your longest-standing officer.'
                : 'You can join again later.'),
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
    );
    if (ok && mounted) await _do(_svc.leave, done: 'You left the guild.');
  }

  // Chat ---------------------------------------------------

  String _nameOf(String userId) => _members
      .firstWhere(
        (m) => m.userId == userId,
        orElse: () => GuildMember(
          userId: userId,
          name: 'Former member',
          role: GuildRole.member,
          joinedAt: DateTime.now(),
        ),
      )
      .name;

  Widget _chatTab() => Column(
    children: [
      Expanded(
        child: _chat.isEmpty
            ? Center(child: socialHint('No messages yet. Say hello!'))
            : ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                itemCount: _chat.length,
                itemBuilder: (_, i) {
                  final m = _chat[i];
                  final mine = m.senderId == _svc.myId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? CreamPalette.gold.withValues(alpha: 0.4)
                              : CreamPalette.tan.withValues(alpha: 0.18),
                          borderRadius: vr(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!mine)
                              Text(
                                _nameOf(m.senderId),
                                style: FoE.dim(
                                  size: 10,
                                ).copyWith(color: kBoxAccent),
                              ),
                            Text(
                              m.body,
                              style: FoE.label(
                                size: 12.5,
                              ).copyWith(color: kBoxInk),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _field(_chatInput, 'Write to your guild', maxLength: 1000),
            ),
            const SizedBox(width: 8),
            SocialGoldButton('Send', onTap: _sendChat),
          ],
        ),
      ),
    ],
  );

  Future<void> _sendChat() async {
    final text = _chatInput.text;
    if (text.trim().isEmpty) return;
    _chatInput.clear();
    try {
      await _svc.sendChat(_guild!.id, text);
    } catch (e) {
      if (mounted) context.snack(guildErrorText(e), error: true);
    }
  }

  // Requests -----------------------------------------------

  Widget _requestsTab() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    children: [
      if (_requests.isEmpty) socialHint('No one is waiting to join.'),
      for (final r in _requests)
        _gap(
          socialRow(
            child: Row(
              children: [
                SocialAvatar(r.name),
                const SizedBox(width: 10),
                _name(r.name, 'wants to join'),
                SocialTileButton(
                  'Decline',
                  height: 28,
                  onTap: _busy
                      ? null
                      : () => _do(
                          () => _svc.decideRequest(r.userId, accept: false),
                        ),
                ),
                const SizedBox(width: 6),
                SocialGoldButton(
                  'Accept',
                  height: 28,
                  onTap: _busy
                      ? null
                      : () => _do(
                          () => _svc.decideRequest(r.userId, accept: true),
                        ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  // Manage (leader) ---------------------------------------

  late final TextEditingController _editDesc = TextEditingController(
    text: _guild?.description ?? '',
  );

  Widget _manageTab() {
    final g = _guild!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      children: [
        socialSection('Description'),
        _field(_editDesc, 'Describe your guild', maxLength: 280, maxLines: 3),
        const SizedBox(height: 10),
        Row(
          children: [
            SocialTileButton(
              g.isOpen ? 'Open to everyone' : 'Join by request',
              onTap: _busy
                  ? null
                  : () => _do(() => _svc.update(isOpen: !g.isOpen)),
            ),
            const Spacer(),
            SocialGoldButton(
              'Save description',
              onTap: _busy
                  ? null
                  : () => _do(
                      () => _svc.update(description: _editDesc.text),
                      done: 'Saved.',
                    ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        socialHint(
          'Promote members to officers from the Members tab — officers can '
          'accept requests and remove plain members. To hand over the guild, '
          'leave it: leadership passes to your longest-standing officer.',
        ),
      ],
    );
  }
}
