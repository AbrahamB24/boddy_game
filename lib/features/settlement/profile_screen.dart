import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/parchment_page.dart';
import '../social/services/friends_service.dart';
import 'settlement_controller.dart';
import 'widgets/parchment_sheet.dart';

/// The account-level home every player was missing (user 2026-09-15: "füge
/// noch ein Profil mit allen notwendigen Einstellungen hinzu").
///
/// Before this the only account-facing controls anywhere in the app were the
/// sound/haptics switch (a header icon, easy to miss) and Reset — which sat
/// behind `SettlementController.isDev`, in a row of icons its own doc
/// comment says will be deleted outright ("da sie später so oder so gelöscht
/// werden"). There was no sign-out at all: once you were in, you stayed in.
///
/// [onOpenDevMode] is a callback rather than an import of dev_mode.dart
/// itself — that library loads lazily via `deferred as dev_mode` from
/// settlement_screen.dart, and this screen has no reason to pull it into
/// its own load path just to offer the one shortcut.
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

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final name = await _friendsSvc.loadMyUsername();
    if (!mounted) return;
    setState(() {
      _username = name;
      _usernameLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? 'Unknown account';
    final ctrl = SettlementController();
    return ParchmentPage(
      title: 'Profile',
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: ParchmentPage.kParchmentPagePad,
          vertical: 16,
        ),
        children: [
          _section('Account'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: ParchmentSheet.card,
            child: Row(
              children: [
                Icon(Icons.person_outline, color: ParchmentSheet.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    email,
                    style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _actionRow(
            icon: Icons.badge_outlined,
            label: _usernameLoaded
                ? (_username == null ? 'Set a username' : '@$_username')
                : '…',
            onTap: _editUsername,
          ),
          const SizedBox(height: 8),
          _actionRow(
            icon: Icons.logout,
            label: 'Sign out',
            onTap: _confirmSignOut,
          ),
          const SizedBox(height: 20),

          _section('Preferences'),
          Container(
            decoration: ParchmentSheet.card,
            child: Column(
              children: [
                _switchRow(
                  title: 'Sound effects',
                  subtitle: 'Short cues when something lands.',
                  value: Feel.soundOn,
                  onChanged: (v) async {
                    await Feel.setSoundOn(v);
                    if (v) Feel.tap();
                    if (mounted) setState(() {});
                  },
                ),
                Divider(height: 1, color: ParchmentSheet.ink.withValues(alpha: 0.12)),
                _switchRow(
                  title: 'Vibration',
                  subtitle: 'A nudge for placing, hiring, hatching and refusals.',
                  value: Feel.hapticsOn,
                  onChanged: (v) async {
                    await Feel.setHapticsOn(v);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (ctrl.isDev && widget.onOpenDevMode != null) ...[
            _section('Developer'),
            _actionRow(
              icon: Icons.build_outlined,
              label: 'Open Dev Mode',
              onTap: () {
                Navigator.pop(context);
                widget.onOpenDevMode!();
              },
            ),
            const SizedBox(height: 20),
          ],

          _section('Danger zone'),
          _actionRow(
            icon: Icons.restart_alt,
            label: 'Reset progress',
            danger: true,
            onTap: _confirmReset,
          ),
        ],
      ),
    );
  }

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

  Widget _switchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
    activeThumbColor: FoE.gold,
    value: value,
    onChanged: onChanged,
    title: Text(
      title,
      style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
    ),
    subtitle: Text(
      subtitle,
      style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkFaint),
    ),
  );

  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: ParchmentSheet.card,
      child: Row(
        children: [
          Icon(icon, color: danger ? FoE.danger : ParchmentSheet.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: FoE.label(size: 13).copyWith(
                color: danger ? FoE.danger : ParchmentSheet.ink,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: ParchmentSheet.inkFaint),
        ],
      ),
    ),
  );

  /// Sets (or changes) the username the Social tab's friend search matches
  /// on — see supabase/migrations/0046_profiles_username.sql. Required
  /// before anyone can find this account to add as a friend.
  Future<void> _editUsername() async {
    final ctrl = TextEditingController(text: _username ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 280,
          decoration: FoE.panel(radius: 12),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Username', style: FoE.title(size: 14), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                'How friends find you in Social search.',
                textAlign: TextAlign.center,
                style: FoE.label(size: 11).copyWith(color: FoE.textDim),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 24,
                style: FoE.label().copyWith(color: Colors.white),
                decoration: const InputDecoration(counterText: ''),
                onSubmitted: (v) => Navigator.pop(context, v),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: FoE.btn(),
                      child: Text('Cancel', style: FoE.label().copyWith(color: FoE.textDim)),
                    ),
                  ),
                  Pressable(
                    onTap: () => Navigator.pop(context, ctrl.text),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: FoE.btn(active: true),
                      child: Text('Save', style: FoE.label().copyWith(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
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
      final taken = e.toString().toLowerCase().contains('duplicate') ||
          e.toString().contains('23505');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(taken ? 'That username is taken.' : 'Could not save: $e')),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await _confirmDialog(
      title: 'Sign out?',
      message: 'You can sign back in any time with the same account.',
      confirmLabel: 'Sign out',
      danger: false,
    );
    if (ok != true || !mounted) return;
    await supabase.auth.signOut();
    if (!mounted) return;
    // Collapses every pushed route (this screen included) back to the
    // root, so _AuthGate's rebuild into _LoginScreen isn't left with a
    // stale Profile/Settlement screen still stacked on top of it — the
    // auth swap happens INSIDE MaterialApp.home, not via a pop, so nothing
    // else clears the stack for us.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmReset() async {
    final ok = await _confirmDialog(
      title: 'Reset EVERYTHING?',
      message:
          'Wipes this account back to a first launch: every monster you '
          'own, all buildings, resources, tech gates, breeding, '
          'expeditions, and your level and region progress. The intro '
          'starts over.\n\nThis cannot be undone.',
      confirmLabel: 'Reset',
      danger: true,
    );
    if (ok != true || !mounted) return;
    await SettlementController().resetSettlement();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required bool danger,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 280,
        decoration: FoE.panel(radius: 12),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: FoE.title(size: 14), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FoE.label().copyWith(color: FoE.textDim),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Pressable(
                  onTap: () => Navigator.pop(context, false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: FoE.btn(),
                    child: Text('Cancel', style: FoE.label().copyWith(color: FoE.textDim)),
                  ),
                ),
                Pressable(
                  onTap: () => Navigator.pop(context, true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: danger
                        ? ShapeDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.4),
                            shape: FoE.facet(
                              radius: 6,
                              side: BorderSide(color: Colors.red.shade700),
                            ),
                          )
                        : FoE.btn(active: true),
                    child: Text(
                      confirmLabel,
                      style: FoE.label().copyWith(
                        color: danger ? Colors.red.shade300 : Colors.white,
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
  );
}
