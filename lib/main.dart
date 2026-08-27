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
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: supabase.auth.onAuthStateChange,
    builder: (context, _) {
      final session = supabase.auth.currentSession;
      return session == null ? const _LoginScreen() : const SettlementScreen();
    },
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
              ],
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
