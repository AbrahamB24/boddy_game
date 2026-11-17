import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/theme/voxel_kit.dart' show vr, VoxelBar;
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../settlement/settlement_controller.dart';
import '../social/social_actions.dart' show confirmDialog;
import '../social/widgets/social_kit.dart';
import 'guild_crest.dart';
import 'guild_help.dart';
import 'guild_boss.dart';
import 'guild_models.dart';
import 'guild_studs.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/models/species_def.dart';
import '../creatures/services/breeding_controller.dart';
import '../creatures/services/creatures_controller.dart';
import 'guild_quests.dart';
import 'guild_service.dart';

enum _Tab { overview, members, chat, help, board, boss, ranking, requests, manage }

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
  GuildCrest _newCrest = GuildCrest.random(math.Random());

  // Guild page
  _Tab _tab = _Tab.overview;
  List<GuildQuest> _quests = [];
  DateTime? _questsEnd;

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
    GuildHelp.instance.addListener(_onHelp);
    GuildStuds.instance.addListener(_onHelp);
    unawaited(GuildStuds.instance.refresh());
    unawaited(GuildHelp.instance.refresh());
    _reload();
  }

  @override
  void dispose() {
    GuildHelp.instance.removeListener(_onHelp);
    GuildStuds.instance.removeListener(_onHelp);
    _searchDebounce?.cancel();
    _chatChannel?.unsubscribe();
    _searchCtrl.dispose();
    _newName.dispose();
    _newDesc.dispose();
    _chatInput.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  void _onHelp() {
    if (mounted) setState(() {});
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
      final q = await GuildQuests.current();
      final me = members.where((m) => m.userId == _svc.myId);
      final canModerate = me.isNotEmpty && me.first.role.canModerate;
      final requests = canModerate
          ? await _svc.loadRequests(g.id)
          : <GuildRequest>[];
      if (!mounted) return;
      setState(() {
        _guild = g;
        _quests = q?.quests ?? _quests;
        _questsEnd = q?.endsAt ?? _questsEnd;
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
      const SizedBox(height: 10),
      socialSection('Crest'),
      CrestCreator(
        crest: _newCrest,
        onChanged: (c) => setState(() => _newCrest = c),
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
                      crest: _newCrest,
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
          CrestView(g.crest, size: 34),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _crestPanel(_guild!),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 16, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _seg(),
                ),
              ),
              Expanded(
                child: switch (_tab) {
                  _Tab.overview => _overviewTab(),
                  _Tab.members => _membersTab(),
                  _Tab.chat => _chatTab(),
                  _Tab.help => _helpTab(),
                  _Tab.board => _boardTab(),
                  _Tab.boss => _bossTab(),
                  _Tab.ranking => _rankingTab(),
                  _Tab.requests => _requestsTab(),
                  _Tab.manage => _manageTab(),
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Fixed left panel: crest, name, level progress, member count.
  Widget _crestPanel(Guild g) {
    final lv = g.level.clamp(1, kGuildLevelPoints.length);
    final maxed = lv >= kGuildLevelPoints.length;
    final from = kGuildLevelPoints[lv - 1];
    final to = maxed ? from : kGuildLevelPoints[lv];
    final frac = maxed ? 1.0 : ((g.points - from) / (to - from)).clamp(0.0, 1.0);
    const light = Color(0xFFEBF5F5);
    const soft = Color(0xFFB7CBCC);
    return Container(
      width: 176,
      margin: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF275058),
        borderRadius: vr(10),
        border: Border.all(color: const Color(0xFF18383E), width: 3),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            CrestView(g.crest, size: 76),
            const SizedBox(height: 8),
            Text(
              g.name,
              textAlign: TextAlign.center,
              style: FoE.label(size: 17).copyWith(color: light),
            ),
            const SizedBox(height: 2),
            Text(
              'Level $lv · ${g.memberCount} / $kGuildMaxMembers members'
              '${g.isOpen ? '' : ' · by request'}',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 10.5).copyWith(color: soft),
            ),
            const SizedBox(height: 10),
            VoxelBar(value: frac, height: 10, block: 8, color: CreamPalette.gold),
            const SizedBox(height: 4),
            Text(
              maxed ? '${g.points} points · top level' : '${g.points} / $to points',
              style: FoE.dim(size: 10.5).copyWith(color: CreamPalette.gold),
            ),
            if (g.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                g.description,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: FoE.dim(size: 10.5).copyWith(color: soft),
              ),
            ],
          ],
        ),
      ),
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
        _segItem('Guild', _Tab.overview),
        _segItem('Members', _Tab.members),
        _segItem('Chat', _Tab.chat),
        _segItem('Help', _Tab.help, badge: GuildHelp.instance.open.length),
        _segItem('Board', _Tab.board),
        _segItem('Boss', _Tab.boss),
        _segItem('Ranking', _Tab.ranking),
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
        if (tab == _Tab.boss) unawaited(_loadBoss());
        if (tab == _Tab.ranking) unawaited(_loadRanking());
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

  // Boss and ranking ---------------------------------------

  GuildBossState? _boss;
  List<BossDamageRow> _bossBoard = [];
  List<RankedGuild> _ranking = [];

  Future<void> _loadBoss() async {
    final gold = await GuildBoss.claim();
    if (gold > 0 && mounted) {
      context.snack('Boss reward collected: $gold gold.');
    }
    final b = await GuildBoss.current();
    final board = await GuildBoss.board();
    if (!mounted) return;
    setState(() {
      _boss = b;
      _bossBoard = board;
    });
  }

  Future<void> _loadRanking() async {
    final r = await GuildBoss.ranking();
    if (mounted) setState(() => _ranking = r);
  }

  Future<void> _fightBoss() async {
    final boss = _boss;
    if (boss == null || _busy) return;
    setState(() => _busy = true);
    final msg = await GuildBoss.fight(context, boss);
    if (!mounted) return;
    setState(() => _busy = false);
    if (msg != null) context.snack(msg);
    await _loadBoss();
  }

  Widget _bossTab() {
    final b = _boss;
    if (b == null) {
      return Center(child: socialHint('Loading the boss…'));
    }
    final left = b.endsAt.difference(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      children: [
        socialSection(
          'This week’s boss',
          trailing: Text(
            left.inDays >= 1 ? '${left.inDays} d left' : '${left.inHours.clamp(0, 99)} h left',
            style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
          ),
        ),
        socialRow(
          height: 92,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${b.name} · level ${b.level}',
                    style: FoE.label(size: 15).copyWith(color: kBoxInk),
                  ),
                  const Spacer(),
                  Text(
                    b.defeated
                        ? 'Defeated!'
                        : '${b.damage} / ${b.maxHp} damage',
                    style: FoE.dim(size: 11).copyWith(
                      color: b.defeated ? CreamPalette.better : kBoxInkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              VoxelBar(
                value: 1 - b.fraction,
                height: 12,
                block: 8,
                color: b.defeated ? CreamPalette.better : CreamPalette.warn,
              ),
              const SizedBox(height: 6),
              Text(
                'The whole guild fights this one health bar. You have done '
                '${b.myDamage} so far.',
                style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SocialGoldButton(
              b.defeated
                  ? 'Boss defeated'
                  : (b.attemptsLeft > 0
                        ? 'Fight · ${b.attemptsLeft}/$kBossAttemptsPerDay left today'
                        : 'No attempts left today'),
              onTap: b.defeated || b.attemptsLeft <= 0 || _busy
                  ? null
                  : _fightBoss,
            ),
          ],
        ),
        socialHint(
          'A normal battle against a strong monster; the share of its health '
          'your team takes counts for the guild. Gold for every point of '
          'damage, and a bonus if the boss falls before the week ends.',
        ),
        socialSection('Damage this week'),
        if (_bossBoard.isEmpty) socialHint('Nobody has hit it yet.'),
        for (var i = 0; i < _bossBoard.length; i++)
          _gap(
            socialRow(
              height: 38,
              child: Row(
                children: [
                  Text('${i + 1}.', style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft)),
                  const SizedBox(width: 8),
                  _name(_bossBoard[i].name),
                  Text(
                    '${_bossBoard[i].damage}',
                    style: FoE.value(size: 12).copyWith(color: kBoxInk),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _rankingTab() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
    children: [
      socialHint('The 50 guilds with the most points.'),
      if (_ranking.isEmpty) socialHint('Loading the ranking…'),
      for (final r in _ranking)
        _gap(
          socialRow(
            height: 50,
            warm: r.id == _guild?.id,
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    '${r.rank}',
                    style: FoE.value(size: 13).copyWith(color: kBoxInk),
                  ),
                ),
                CrestView(r.crest, size: 30),
                const SizedBox(width: 10),
                _name(
                  r.name,
                  'Level ${r.level} · ${r.members}/$kGuildMaxMembers members',
                ),
                Text(
                  '${r.points} pts',
                  style: FoE.value(size: 12).copyWith(color: kBoxInk),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  // Board: monster loans for breeding ----------------------

  String _speciesName(String id) => kSpeciesDefs[id]?.name ?? id;

  /// Asks which of my monsters, from those that pass [ok].
  Future<CreatureInstance?> _pickMonster(
    String title,
    bool Function(CreatureInstance) ok,
  ) async {
    final list = CreaturesController().creatures.where(ok).toList()
      ..sort((a, b) => b.level.compareTo(a.level));
    return showDialog<CreatureInstance>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: creamCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              socialSection(title),
              if (list.isEmpty) socialHint('None of your monsters fit.'),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in list)
                      _gap(
                        socialRow(
                          onTap: () => Navigator.pop(ctx, c),
                          child: Row(
                            children: [
                              _name(
                                '${c.displayName} ${c.gender.symbol}',
                                '${_speciesName(c.speciesId)} · level ${c.level}',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: SocialTileButton('Cancel', onTap: () => Navigator.pop(ctx)),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Future<void> _listMonster() async {
    final c = await _pickMonster(
      'List which monster?',
      (c) => GuildStuds.canList(c) && !GuildStuds.instance.isListed(c.id),
    );
    if (c == null || !mounted) return;
    try {
      await GuildStuds.instance.list(c);
      if (mounted) context.snack('${c.displayName} is on the board.');
    } catch (e) {
      if (mounted) context.snack(guildErrorText(e), error: true);
    }
  }

  Future<void> _borrow(StudListing s) async {
    final breeding = BreedingController();
    final mine = await _pickMonster(
      'Breed ${_speciesName(s.speciesId)} ${s.gender.symbol} with…',
      (c) =>
          c.speciesId == s.speciesId &&
          c.gender != s.gender &&
          !c.isKo &&
          !c.isHealing &&
          !CreaturesController().breedingIds.contains(c.id),
    );
    if (mine == null || !mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Borrow ${s.name}?',
      body:
          '${s.ownerName} keeps ${s.name}; you breed with a copy of its genes '
          'once. It costs ${s.fee} gold, paid to ${s.ownerName}, plus the usual '
          'breeding supplies.',
      confirmLabel: 'Borrow · ${s.fee} gold',
      cancelLabel: 'Cancel',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final err = await breeding.startWithLoan(mine, s);
    if (!mounted) return;
    setState(() => _busy = false);
    context.snack(
      err ?? 'Breeding started with ${s.name}.',
      error: err != null,
    );
    await GuildStuds.instance.refresh();
  }

  String _rest(DateTime end) {
    final d = end.difference(DateTime.now());
    return d.inHours >= 1 ? 'rests ${d.inHours} h' : 'rests ${d.inMinutes.clamp(1, 59)} min';
  }

  Widget _boardTab() {
    final st = GuildStuds.instance;
    final mine = st.mine;
    final others = st.others;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      children: [
        socialHint(
          'List up to $kStudMaxListed of your monsters. A guild mate can breed '
          'with a copy of its genes once; the monster stays with you, rests '
          '12 hours, and you earn the fee. Legendaries cannot be listed.',
        ),
        socialSection(
          'Yours · ${mine.length}/$kStudMaxListed',
          trailing: mine.length >= kStudMaxListed
              ? null
              : SocialGoldButton('List a monster', height: 26, onTap: _listMonster),
        ),
        if (mine.isEmpty) socialHint('Nothing listed.'),
        for (final s in mine)
          _gap(
            socialRow(
              child: Row(
                children: [
                  _name(
                    '${s.name} ${s.gender.symbol}',
                    '${_speciesName(s.speciesId)} · level ${s.level} · '
                    '${s.isResting ? _rest(s.readyAt) : 'ready'} · ${s.fee} gold',
                  ),
                  SocialTileButton(
                    'Take off',
                    height: 28,
                    onTap: () => GuildStuds.instance.unlist(s.creatureId),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        socialSection(
          'Available · loans today ${st.used}/${st.limit}',
        ),
        if (others.isEmpty) socialHint('Nobody has listed a monster yet.'),
        for (final s in others)
          _gap(
            socialRow(
              child: Row(
                children: [
                  _name(
                    '${s.name} ${s.gender.symbol} · ${s.ownerName}',
                    '${_speciesName(s.speciesId)} · ${s.rarity.label} · level '
                    '${s.level} · ${s.fee} gold',
                  ),
                  if (s.isResting)
                    _tag(_rest(s.readyAt))
                  else
                    SocialGoldButton(
                      'Borrow',
                      height: 28,
                      onTap: _busy || st.used >= st.limit
                          ? null
                          : () => _borrow(s),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Overview: level, bonuses, weekly quests ----------------

  String _pct(double f) => '+${(f * 100).round()}%';

  Widget _overviewTab() {
    final g = _guild!;
    final lv = g.level.clamp(1, kGuildLevelPoints.length);
    final maxed = lv >= kGuildLevelPoints.length;
    final from = kGuildLevelPoints[lv - 1];
    final to = maxed ? from : kGuildLevelPoints[lv];
    final frac = maxed ? 1.0 : ((g.points - from) / (to - from)).clamp(0.0, 1.0);
    final now = kGuildBonusByLevel[lv - 1];
    final next = maxed ? now : kGuildBonusByLevel[lv];
    final left = _questsEnd?.difference(DateTime.now());
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      children: [
        socialSection('Guild level'),
        socialRow(
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Level $lv',
                    style: FoE.label(size: 15).copyWith(color: kBoxInk),
                  ),
                  const Spacer(),
                  Text(
                    maxed
                        ? '${g.points} points · top level'
                        : '${g.points} / $to points',
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              VoxelBar(value: frac, height: 10, block: 8, color: CreamPalette.gold),
            ],
          ),
        ),
        const SizedBox(height: 14),
        socialSection('What it gives every member'),
        socialRow(
          height: 64,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_pct(now)} build speed · wood and stone yield · battle XP',
                      style: FoE.label(size: 12.5).copyWith(color: kBoxInk),
                    ),
                    Text(
                      maxed
                          ? 'The highest bonus.'
                          : 'Next level: ${_pct(next)}',
                      style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        socialSection(
          'This week’s quests',
          trailing: left == null
              ? null
              : Text(
                  left.inDays >= 1
                      ? '${left.inDays} d left'
                      : '${left.inHours.clamp(0, 99)} h left',
                  style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                ),
        ),
        if (_quests.isEmpty) socialHint('No quests yet — check back soon.'),
        for (final q in _quests)
          _gap(
            socialRow(
              height: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          q.title,
                          style: FoE.label(size: 13).copyWith(color: kBoxInk),
                        ),
                      ),
                      Text(
                        q.rewarded
                            ? 'Done · +${GuildQuest.reward} points'
                            : '${q.progress} / ${q.goal} · +${GuildQuest.reward} points',
                        style: FoE.dim(size: 10.5).copyWith(
                          color: q.rewarded ? CreamPalette.better : kBoxInkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  VoxelBar(
                    value: q.goal <= 0 ? 0 : q.progress / q.goal,
                    height: 9,
                    block: 8,
                    color: q.rewarded ? CreamPalette.better : CreamPalette.gold,
                  ),
                ],
              ),
            ),
          ),
        socialHint(
          'Helping a guild mate earns a point; a finished quest earns '
          '${GuildQuest.reward}. Points raise the guild level.',
        ),
      ],
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

  // Help ---------------------------------------------------

  String _left(DateTime end) {
    final d = end.difference(DateTime.now());
    if (d.inHours >= 1) return '${d.inHours} h left';
    return '${d.inMinutes.clamp(0, 59)} min left';
  }

  Future<void> _giveHelp(GuildHelpRequest r) async {
    final res = await GuildHelp.instance.give(r);
    if (!mounted) return;
    switch (res) {
      case 'ok':
        context.snack('Helped ${r.requesterName}.');
      case 'capped':
        context.snack('That one has all the help it can take.');
      case 'expired':
        context.snack('That one is already done.');
      case 'already':
        context.snack('You already helped with that.');
      default:
        context.snack(res.replaceFirst('!', ''), error: true);
    }
    await GuildHelp.instance.refresh();
  }

  Future<void> _helpAll() async {
    var n = 0;
    for (final r in [...GuildHelp.instance.open]) {
      if (await GuildHelp.instance.give(r) == 'ok') n++;
    }
    if (!mounted) return;
    context.snack(n == 0 ? 'Nothing to help with.' : 'Helped $n.');
    await GuildHelp.instance.refresh();
  }

  Widget _helpTab() {
    final open = GuildHelp.instance.open;
    final cut = (kGuildHelpFraction * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      children: [
        socialHint(
          'Each help takes $cut% off the time that is still to run — for '
          'building, breeding, hatching and healing. Ask your guild from the '
          'building or the monster itself.',
        ),
        if (open.isEmpty) socialHint('Nobody is waiting for help right now.'),
        if (open.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SocialGoldButton('Help everyone', onTap: _helpAll),
            ),
          ),
        for (final r in open)
          _gap(
            socialRow(
              child: Row(
                children: [
                  SocialAvatar(r.requesterName),
                  const SizedBox(width: 10),
                  _name(
                    '${r.requesterName} · ${r.label}',
                    '${r.kind.noun} · ${_left(r.expiresAt)} · '
                    '${r.helps}/$kGuildHelpCap helped',
                  ),
                  SocialGoldButton(
                    'Help',
                    height: 28,
                    onTap: () => _giveHelp(r),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
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

  GuildCrest? _editCrest;

  Widget _manageTab() {
    final g = _guild!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      children: [
        socialSection('Crest'),
        CrestCreator(
          crest: _editCrest ?? g.crest,
          onChanged: (c) => setState(() => _editCrest = c),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: SocialGoldButton(
            'Save crest',
            onTap: _busy || _editCrest == null
                ? null
                : () async {
                    final c = _editCrest!;
                    await _do(() => _svc.update(crest: c), done: 'Crest saved.');
                    _editCrest = null;
                  },
          ),
        ),
        const SizedBox(height: 14),
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
