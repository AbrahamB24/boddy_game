import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/friend.dart';
import 'services/friends_service.dart';
import 'services/pvp_service.dart';
import 'visit_city_screen.dart';

/// The Friends tab of [SocialScreen]: search + add, pending requests, and the
/// accepted friends list (each row offering "Visit" and "Challenge").
class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final _svc = FriendsService();
  final _searchCtrl = TextEditingController();

  String get _myId => supabase.auth.currentUser!.id;

  List<Friendship> _friendships = [];
  Map<String, String?> _names = {};
  List<FriendSearchResult> _searchResults = [];
  bool _loading = true;
  bool _searching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final friendships = await _svc.listFriendships();
      final otherIds = friendships.map((f) => f.otherUserId(_myId)).toList();
      final names = await _svc.usernamesFor(otherIds);
      if (!mounted) return;
      setState(() {
        _friendships = friendships;
        _names = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _svc.searchByUsername(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(String userId) async {
    await _svc.sendRequest(userId);
    await _search(_searchCtrl.text);
    await _load();
  }

  Future<void> _accept(Friendship f) async {
    await _svc.acceptRequest(f.id);
    await _load();
  }

  Future<void> _decline(Friendship f) async {
    await _svc.declineRequest(f.id);
    await _load();
  }

  Future<void> _remove(Friendship f) async {
    await _svc.removeFriendship(f.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load friends.\n$_error',
          textAlign: TextAlign.center,
          style: FoE.label().copyWith(color: FoE.textDim),
        ),
      );
    }

    final incoming = _friendships.where((f) => f.awaitingMyResponse(_myId));
    final outgoing = _friendships.where((f) => f.sentByMe(_myId));
    final accepted = _friendships.where(
      (f) => f.status == FriendshipStatus.accepted,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _searchBox(),
        if (_searchCtrl.text.trim().length >= 2) ...[
          const SizedBox(height: 10),
          if (_searching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchResults.isEmpty)
            _hint('No player found with that name.')
          else
            ..._searchResults.map(_searchResultRow),
          const SizedBox(height: 8),
        ],
        if (incoming.isNotEmpty) ...[
          _section('Friend requests'),
          ...incoming.map(_incomingRow),
          const SizedBox(height: 16),
        ],
        _section('Friends (${accepted.length})'),
        if (accepted.isEmpty && outgoing.isEmpty)
          _hint('No friends yet — search for a username above.'),
        ...accepted.map(_friendRow),
        ...outgoing.map(_outgoingRow),
      ],
    );
  }

  Widget _searchBox() => TextField(
    controller: _searchCtrl,
    onChanged: _search,
    style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
    decoration: InputDecoration(
      hintText: 'Search by username',
      hintStyle: FoE.label(size: 13).copyWith(color: ParchmentSheet.inkFaint),
      prefixIcon: Icon(Icons.search, color: ParchmentSheet.accent),
      filled: true,
      fillColor: ParchmentSheet.ink.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: ParchmentSheet.ink.withValues(alpha: 0.15)),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    ),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: FoE.label(size: 12).copyWith(
        color: ParchmentSheet.accent,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      text,
      style: FoE.dim(size: 12).copyWith(color: ParchmentSheet.inkFaint),
    ),
  );

  Widget _row({
    required String name,
    required List<Widget> actions,
    IconData icon = Icons.person_outline,
    VoidCallback? onTap,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: ParchmentSheet.card,
      child: Row(
        children: [
          Icon(icon, color: ParchmentSheet.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );

  Widget _searchResultRow(FriendSearchResult r) {
    final f = r.friendship;
    Widget action;
    if (f == null) {
      action = _smallButton('Add', Icons.person_add_alt, () => _sendRequest(r.userId));
    } else if (f.status == FriendshipStatus.accepted) {
      action = _tag('Friends');
    } else if (f.awaitingMyResponse(_myId)) {
      action = _tag('Respond below');
    } else if (f.sentByMe(_myId)) {
      action = _tag('Pending');
    } else {
      action = _tag(f.status.name);
    }
    return _row(name: r.username, actions: [action]);
  }

  Widget _incomingRow(Friendship f) => _row(
    name: _names[f.otherUserId(_myId)] ?? '(unknown)',
    actions: [
      _smallButton('Accept', Icons.check, () => _accept(f)),
      const SizedBox(width: 6),
      _smallIconButton(Icons.close, () => _decline(f)),
    ],
  );

  Widget _outgoingRow(Friendship f) => _row(
    name: _names[f.otherUserId(_myId)] ?? '(unknown)',
    actions: [_tag('Requested'), const SizedBox(width: 6), _smallIconButton(Icons.close, () => _remove(f))],
  );

  Widget _friendRow(Friendship f) {
    final otherId = f.otherUserId(_myId);
    final name = _names[otherId] ?? '(unknown)';
    return _row(
      name: name,
      icon: Icons.people_alt_outlined,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VisitCityScreen(friendUserId: otherId, friendName: name),
        ),
      ),
      actions: [
        _smallIconButton(Icons.sports_martial_arts, () => _challenge(otherId, name)),
        _smallIconButton(Icons.person_remove_outlined, () => _remove(f)),
      ],
    );
  }

  /// Fire-and-forget (user 2026-09-15): sends the challenge and stays right
  /// here — no navigation. The opponent sees it in their PvP tab's
  /// "Incoming" list; once they accept, BOTH sides build their team and
  /// ready up in the Lobby (see PvpTab's "Open matches").
  Future<void> _challenge(String opponentId, String opponentName) async {
    await PvpService().createChallenge(opponentId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Challenge sent to $opponentName.')),
    );
  }

  Widget _smallButton(String label, IconData icon, VoidCallback onTap) => Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: ParchmentSheet.accent.withValues(alpha: 0.15),
        shape: FoE.facet(radius: 8, side: BorderSide(color: ParchmentSheet.accent)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ParchmentSheet.accent),
          const SizedBox(width: 4),
          Text(label, style: FoE.label(size: 11).copyWith(color: ParchmentSheet.accent)),
        ],
      ),
    ),
  );

  Widget _smallIconButton(IconData icon, VoidCallback onTap) => Pressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 18, color: ParchmentSheet.inkFaint),
    ),
  );

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: ShapeDecoration(
      color: ParchmentSheet.ink.withValues(alpha: 0.06),
      shape: FoE.facet(radius: 8),
    ),
    child: Text(text, style: FoE.dim(size: 10).copyWith(color: ParchmentSheet.inkFaint)),
  );
}
