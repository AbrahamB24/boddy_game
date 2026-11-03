import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/pressable.dart';
import '../creatures/services/creatures_controller.dart';
import '../social/models/pvp_match.dart';
import '../social/services/alert_prefs.dart';
import '../social/services/friends_service.dart';
import '../social/services/pvp_service.dart';
import '../social/social_actions.dart' show confirmDialog;
import '../social/widgets/social_kit.dart';
import 'data/building_definitions.dart';
import 'settlement_controller.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

/// The player's page (user 2026-09-19, "Variante 2, Spielerkarte"): on the left
/// a PLAYER CARD — avatar, @username, e-mail, "Edit username" and four figures
/// (PvP rating, wins–losses, monsters, buildings); on the right the
/// PREFERENCES (sound, vibration, banners) and the ACCOUNT row of sign out,
/// reset and — for a developer — Dev Mode.
///
/// The three dialogs it opens are cream: username (max 24), sign out, and the
/// reset, which stays locked until the word RESET is typed — wiping a whole
/// settlement should not be one careless tap.
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onOpenDevMode;
  const ProfileScreen({super.key, this.onOpenDevMode});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _friendsSvc = FriendsService();
  String? _username;
  bool _usernameLoaded = false;
  PvpStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final name = await _friendsSvc.loadMyUsername();
      if (mounted) {
        setState(() {
          _username = name;
          _usernameLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _usernameLoaded = true);
    }
    try {
      final stats = await PvpService().loadMyStats();
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // The card shows dashes; nothing else depends on it.
    }
  }

  String get _email => supabase.auth.currentUser?.email ?? 'Unknown account';

  /// Finished buildings the player has — roads and plots are ground, not
  /// buildings, and unfinished ones are still a plan.
  int get _buildingCount => SettlementController().buildings.where((b) {
    if (!b.isComplete) return false;
    final def = kBuildingDefs[b.buildingTypeId];
    return def != null && !def.isRoad && !def.isBuildPlot;
  }).length;

  @override
  Widget build(BuildContext context) {
    final isDev = SettlementController().isDev;
    return MenuScaffold(
      title: 'Profile',
      trailing: _username == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: CreamPalette.tan.withValues(alpha: 0.18),
                borderRadius: vr(9),
              ),
              child: Text(
                '@$_username',
                style: FoE.value(size: 11).copyWith(color: kBoxInk),
              ),
            ),
      // Identity/stats and Settings ARE different Gebiete (user 2026-09-29,
      // "Trennlinien und Zonen gemischt", app-wide), so the player card gets
      // a [zoneBox] of its own; its edge is separation enough beside the
      // settings list, which already sections itself. (MenuScaffold is the
      // one card now — no [pageCard] here.)
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 330,
              child: zoneBox(padding: EdgeInsets.zero, child: _playerCard()),
            ),
            const SizedBox(width: 14),
            Expanded(child: _settings(isDev)),
          ],
        ),
      ),
    );
  }

  // ── The player card ───────────────────────────────────────────────────

  Widget _playerCard() {
    final s = _stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        children: [
          SocialAvatar(_username ?? _email, size: 84),
          const SizedBox(height: 10),
          Text(
            _usernameLoaded
                ? (_username == null ? 'No username yet' : '@$_username')
                : '…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.title(size: 19).copyWith(color: kBoxInk),
          ),
          const SizedBox(height: 2),
          Text(
            _email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
          ),
          const SizedBox(height: 10),
          SocialTileButton(
            _username == null ? 'Set a username' : 'Edit username',
            height: 30,
            onTap: _editUsername,
          ),
          const Spacer(),
          Row(
            children: [
              _stat(s == null ? '–' : '${s.rating}', 'PvP rating'),
              const SizedBox(width: 8),
              _stat(s == null ? '–' : '${s.wins}–${s.losses}', 'Wins – losses'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _stat('${CreaturesController().creatures.length}', 'Monsters'),
              const SizedBox(width: 8),
              _stat('$_buildingCount', 'Buildings'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: CreamPalette.tan.withValues(alpha: 0.18),
        borderRadius: vr(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            style: FoE.value(size: 19).copyWith(color: kBoxAccent),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(
              size: 10,
            ).copyWith(color: kBoxInkSoft, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );

  // ── Preferences and account ───────────────────────────────────────────

  Widget _settings(bool isDev) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        socialSection('Preferences'),
        _switchRow(
          icon: Icons.volume_up_outlined,
          title: 'Sound & music',
          subtitle: 'Cues when something lands, and the battle music.',
          value: Feel.soundOn,
          onChanged: (v) async {
            await Feel.setSoundOn(v);
            if (v) Feel.tap();
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 8),
        _switchRow(
          icon: Icons.vibration,
          title: 'Vibration',
          subtitle: 'A nudge for placing, hiring, hatching and refusals.',
          value: Feel.hapticsOn,
          onChanged: (v) async {
            await Feel.setHapticsOn(v);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 8),
        _switchRow(
          icon: Icons.notifications_active_outlined,
          title: 'Banners',
          subtitle:
              'A friend in the PvP lobby, a message, your move. Off: the '
              'badge on Social still counts.',
          value: AlertPrefs.bannersOn,
          onChanged: (v) async {
            await AlertPrefs.setBannersOn(v);
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 16),
        socialSection('Account'),
        Row(
          children: [
            Expanded(
              child: _accountTile(
                icon: Icons.logout,
                label: 'Sign out',
                onTap: _confirmSignOut,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _accountTile(
                icon: Icons.restart_alt,
                label: 'Reset progress',
                danger: true,
                onTap: _confirmReset,
              ),
            ),
            if (isDev && widget.onOpenDevMode != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _accountTile(
                  icon: Icons.build_outlined,
                  label: 'Dev Mode',
                  onTap: () {
                    Navigator.pop(context);
                    widget.onOpenDevMode!();
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => socialRow(
    height: 54,
    onTap: () => onChanged(!value),
    child: Row(
      children: [
        PixelIcon(icon, size: 20, color: kBoxAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: FoE.label(
                  size: 13,
                ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _Switch(value: value),
      ],
    ),
  );

  Widget _accountTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) => socialRow(
    height: 46,
    onTap: onTap,
    child: Row(
      children: [
        PixelIcon(icon, size: 19, color: danger ? CreamPalette.warn : kBoxAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.label(size: 12.5).copyWith(
              color: danger ? CreamPalette.warn : kBoxInk,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Dialogs ───────────────────────────────────────────────────────────

  Future<void> _editUsername() async {
    final ctrl = TextEditingController(text: _username ?? '');
    final result = await showDialog<String>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 320,
          child: creamCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: StatefulBuilder(
              builder: (ctx, setInner) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Username',
                    textAlign: TextAlign.center,
                    style: FoE.title(size: 15).copyWith(color: kBoxInk),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'How friends find you in Social search.',
                    textAlign: TextAlign.center,
                    style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                  ),
                  const SizedBox(height: 12),
                  _dialogField(
                    ctrl,
                    maxLength: 24,
                    onChanged: (_) => setInner(() {}),
                    onSubmitted: (v) => Navigator.pop(ctx, v),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${ctrl.text.length}/24',
                        style: FoE.dim(
                          size: 10.5,
                        ).copyWith(color: kBoxInkFaint),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _dialogButton(
                          'Cancel',
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dialogButton(
                          'Save',
                          gold: true,
                          onTap: () => Navigator.pop(ctx, ctrl.text),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final name = result?.trim();
    if (name == null || name.isEmpty || name == _username) return;
    try {
      await _friendsSvc.setUsername(name);
      if (!mounted) return;
      setState(() => _username = name);
    } catch (e) {
      if (!mounted) return;
      final taken =
          e.toString().toLowerCase().contains('duplicate') ||
          e.toString().contains('23505');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            taken ? 'That username is taken.' : 'Could not save: $e',
          ),
        ),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await confirmDialog(
      context,
      title: 'Sign out?',
      body: 'You can sign back in any time with the same account.',
      confirmLabel: 'Sign out',
    );
    if (!ok || !mounted) return;
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Resetting wipes the whole settlement, so the button stays locked until the
  /// player has typed the word.
  Future<void> _confirmReset() async {
    const word = 'RESET';
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: SizedBox(
          width: 360,
          child: creamCard(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: StatefulBuilder(
              builder: (ctx, setInner) {
                final unlocked = ctrl.text.trim() == word;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Reset EVERYTHING?',
                      textAlign: TextAlign.center,
                      style: FoE.title(size: 15).copyWith(color: kBoxInk),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Wipes this account back to a first launch: every '
                      'monster you own, all buildings, resources, breeding, '
                      'expeditions, and your level and region progress. The '
                      'intro starts over.\n\nThis cannot be undone.',
                      textAlign: TextAlign.center,
                      style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                    ),
                    const SizedBox(height: 12),
                    Text.rich(
                      TextSpan(
                        text: 'Type ',
                        children: [
                          TextSpan(
                            text: word,
                            style: const TextStyle(
                              color: CreamPalette.warn,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const TextSpan(text: ' to confirm'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
                    ),
                    const SizedBox(height: 6),
                    _dialogField(
                      ctrl,
                      center: true,
                      onChanged: (_) => setInner(() {}),
                      onSubmitted: (_) {
                        if (unlocked) Navigator.pop(ctx, true);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _dialogButton(
                            'Cancel',
                            onTap: () => Navigator.pop(ctx, false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _dialogButton(
                            'Reset',
                            gold: true,
                            onTap: unlocked
                                ? () => Navigator.pop(ctx, true)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await SettlementController().resetSettlement();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _dialogField(
    TextEditingController ctrl, {
    int? maxLength,
    bool center = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) => Container(
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(12),
    ),
    child: TextField(
      controller: ctrl,
      autofocus: true,
      maxLength: maxLength,
      textAlign: center ? TextAlign.center : TextAlign.start,
      style: FoE.label(size: 13).copyWith(color: kBoxInk),
      cursorColor: CreamPalette.accent,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: const InputDecoration(
        isDense: true,
        counterText: '',
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 11),
      ),
    ),
  );

  Widget _dialogButton(
    String label, {
    required VoidCallback? onTap,
    bool gold = false,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      height: 36,
      alignment: Alignment.center,
      decoration: gold
          ? goldButton(active: onTap != null)
          : raisedTile(radius: 12),
      child: Text(
        label,
        style: FoE.label(size: 13).copyWith(
          color: gold ? goldButtonInk(active: onTap != null) : kBoxInk,
        ),
      ),
    ),
  );
}

/// The kit's on/off switch: an amber track with a dark knob when on, a sunk
/// groove with a tan knob when off. The row around it takes the tap.
class _Switch extends StatelessWidget {
  final bool value;
  const _Switch({required this.value});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 140),
    width: 40,
    height: 23,
    padding: const EdgeInsets.all(3),
    alignment: value ? Alignment.centerRight : Alignment.centerLeft,
    decoration: BoxDecoration(
      color: value
          ? CreamPalette.gold
          : CreamPalette.tan.withValues(alpha: 0.22),
      borderRadius: vr(12),
      boxShadow: value
          ? const [
              BoxShadow(color: CreamPalette.goldDeep, offset: Offset(0, 2)),
            ]
          : null,
    ),
    child: Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
        color: value ? CreamPalette.ink : CreamPalette.tan,
      ),
    ),
  );
}
