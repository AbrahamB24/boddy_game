import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/ui/feel.dart';
import 'core/orientation_lock.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/foe_theme.dart';
import 'core/theme/parchment_theme.dart';
import 'features/settlement/widgets/scroll_paper.dart'
    show kParchmentLight, kParchmentMid;
import 'core/ui/phone_frame.dart';
import 'features/settlement/settlement_screen.dart';

/// Bøddy — settlement & creature game.
///
/// Split out of the BoddyQuest fitness app: this is the strategy game
/// (settlement, buildings, research, eras, creatures, breeding, dungeons) on its
/// own. It talks to the SAME Supabase project as the fitness app, so an account
/// created there signs in here — and, since account creation used to only
/// exist over there, _LoginScreen now also registers one directly.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Building art ships at up to 960px wide (tool/pack_art.py, 2026-09-06) —
  // ~92 MB of decoded RGBA for the current set, which leaves almost no
  // headroom under Flutter's 100 MB default before other art (roads,
  // creatures, UI chrome) evicts a building mid-frame. 200 MB matches the
  // decode cost with room to spare rather than fighting eviction thrash.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;
  // The sound/vibration switches, before the first frame — so a player who
  // muted the game last time does not get one cue back on launch.
  await Feel.load();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const BoddyGameApp());
}

class BoddyGameApp extends StatelessWidget {
  const BoddyGameApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bøddy Game',
    debugShowCheckedModeBanner: false,
    // ONE theme for the whole app (user 2026-07-27) — see parchment_theme.dart
    // for why a theme rather than a sweep of call sites.
    theme: buildParchmentTheme(),
    // Wraps the Navigator, so pushed routes, dialogs and sheets are all inside
    // the phone viewport rather than around it.
    builder: (context, child) => PhoneFrame(child: child!),
    // OrientationLock subscribes screens to this to re-apply their lock when
    // the route above them pops. It was never registered, so didPopNext never
    // fired and a screen's lock silently stopped being re-applied.
    navigatorObservers: [orientationRouteObserver],
    home: const _AuthGate(),
  );
}

/// Everything in the game is keyed by user id, so it waits for a Supabase
/// session before handing over to the settlement.
///
/// Also the one place that sees the password-recovery link's own auth event
/// (2026-09-15's "Passwort vergessen" — see [_LoginScreen]'s "Forgot
/// password?" button): clicking that emailed link signs the browser into a
/// short-lived RECOVERY session, which `onAuthStateChange` flags with
/// [AuthChangeEvent.passwordRecovery]. A recovery session is still a
/// non-null [Session], so without this the gate would just drop the player
/// straight into the settlement with their OLD password still active — the
/// one thing "forgot password" has to prevent. Once seen, `_recovering`
/// stays true (even across subsequent events) until [_ResetPasswordScreen]
/// reports success.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _recovering = false;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: supabase.auth.onAuthStateChange,
    builder: (context, snapshot) {
      if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
        _recovering = true;
      }
      final session = supabase.auth.currentSession;
      if (session == null) return const _LoginScreen();
      if (_recovering) {
        return _ResetPasswordScreen(
          onDone: () => setState(() => _recovering = false),
        );
      }
      return const SettlementScreen();
    },
  );
}

/// The far end of the "Forgot password?" email link: sets a new password on
/// the short-lived recovery session [_AuthGate] detected, then hands back
/// via [onDone] so the gate re-evaluates into the settlement.
class _ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const _ResetPasswordScreen({required this.onDone});

  @override
  State<_ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<_ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await supabase.auth.updateUser(UserAttributes(password: _password.text));
      widget.onDone();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kParchmentMid,
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kParchmentLight, kParchmentMid],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Choose a new password', style: FoE.title(size: 18), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  style: FoE.value(size: 14),
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_busy) _submit();
                  },
                  style: FoE.value(size: 14),
                  decoration: const InputDecoration(labelText: 'Repeat new password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: FoE.dim(size: 12).copyWith(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save password'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Sign-in AND sign-up against the shared Supabase project — an account
/// created in the fitness app signs in here just the same, but this no
/// longer requires that app: _signUp() below registers one directly.
class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() {
      // TabController fires this mid-swipe too (indexIsChanging toggles
      // separately) — only the settled index should clear the message and
      // flip the form, or a half-drag repaints the button label back and
      // forth under the player's thumb.
      if (!_tabs.indexIsChanging) {
        setState(() {
          _error = null;
          _info = null;
        });
      }
    });
  bool _busy = false;
  bool get _isSignUp => _tabs.index == 1;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _tabs.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  Future<void> _submit() => _isSignUp ? _signUp() : _signIn();

  /// "Forgot password?" (user 2026-09-15). Asks for the email once more in
  /// its own small dialog (pre-filled from the form) rather than reusing
  /// [_password]'s neighbour field inline — the request has nothing to do
  /// with whatever half-typed password is currently in that field, and a
  /// dialog makes the "a link is on its way" confirmation its own moment
  /// instead of overloading the sign-in form's single `_info` line.
  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _email.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: emailCtrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
          onSubmitted: (_) => Navigator.pop(dialogContext, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (sent != true || emailCtrl.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await supabase.auth.resetPasswordForEmail(
        emailCtrl.text.trim(),
        // Only meaningful on web (Netlify — see netlify.toml): the emailed
        // link brings the browser back here with a recovery session, which
        // _AuthGate picks up. On mobile there is no registered deep-link
        // scheme for this yet, so redirectTo is left unset there and
        // Supabase falls back to its own default (still emails a working
        // link, just not one that reopens this app directly).
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
      if (mounted) {
        setState(() {
          _info = 'If an account exists for that email, a reset link is on its way.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await supabase.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    if (_password.text != _passwordConfirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await supabase.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
      );
      // With email confirmation ON (the project default), signUp returns a
      // user but no session — there is nothing to sign in TO yet. Without
      // it, the session comes back populated and _AuthGate's own stream
      // picks it up on its own; nothing else to do here either way.
      if (mounted && res.session == null) {
        _tabs.index = 0;
        _passwordConfirm.clear();
        setState(() {
          _info = 'Account created — check your email to confirm it, '
              'then sign in.';
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // The front door is the same sheet of paper as everything behind it.
    backgroundColor: kParchmentMid,
    body: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kParchmentLight, kParchmentMid],
        ),
      ),
      child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bøddy Game', style: FoE.title(size: 22)),
              const SizedBox(height: 18),
              // The theme's own tabBarTheme (parchment_theme.dart) already
              // draws the underline in the game's accent colour — no local
              // styling needed here to get "two tabs with an underline".
              TabBar(
                controller: _tabs,
                tabs: const [Tab(text: 'Sign in'), Tab(text: 'Register')],
              ),
              const SizedBox(height: 20),
              _field(_email, 'Email', false, action: TextInputAction.next),
              const SizedBox(height: 12),
              _field(
                _password,
                'Password',
                true,
                // One more field follows while registering — Enter should
                // move on, not submit a form that isn't filled in yet.
                action: _isSignUp
                    ? TextInputAction.next
                    : TextInputAction.done,
              ),
              if (_isSignUp) ...[
                const SizedBox(height: 12),
                _field(
                  _passwordConfirm,
                  'Repeat password',
                  true,
                  action: TextInputAction.done,
                ),
              ] else
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    child: const Text('Forgot password?'),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: FoE.dim(size: 12).copyWith(color: Colors.redAccent),
                ),
              ],
              if (_info != null) ...[
                const SizedBox(height: 12),
                Text(
                  _info!,
                  textAlign: TextAlign.center,
                  style: FoE.dim(size: 12),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                // No styleFrom: the theme's ElevatedButton IS the commit green
                // every other button in the game wears.
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignUp ? 'Create account' : 'Sign in'),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    ),
  );

  Widget _field(
    TextEditingController c,
    String label,
    bool obscure, {
    TextInputAction action = TextInputAction.next,
  }) =>
      TextField(
        controller: c,
        obscureText: obscure,
        textInputAction: action,
        // Enter submits — moves to the next field, or logs in/signs up from
        // the last one, whichever mode is active.
        onSubmitted: (_) {
          if (action == TextInputAction.done && !_busy) {
            _submit();
          } else {
            FocusScope.of(context).nextFocus();
          }
        },
        style: FoE.value(size: 14),
        decoration: InputDecoration(labelText: label),
      );
}
