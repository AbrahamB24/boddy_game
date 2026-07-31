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
/// created there signs in here.
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

/// Minimal sign-in against the shared Supabase project — the fitness app owns
/// the real onboarding/registration flow.
class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
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
              const SizedBox(height: 6),
              Text('Sign in with your Bøddy account.', style: FoE.dim(size: 12)),
              const SizedBox(height: 24),
              _field(_email, 'Email', false, action: TextInputAction.next),
              const SizedBox(height: 12),
              _field(_password, 'Password', true, action: TextInputAction.done),
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
                // No styleFrom: the theme's ElevatedButton IS the commit green
                // every other button in the game wears.
                child: ElevatedButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
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
        // Enter submits — moves to the next field, or logs in from the last one.
        onSubmitted: (_) {
          if (action == TextInputAction.done && !_busy) {
            _signIn();
          } else {
            FocusScope.of(context).nextFocus();
          }
        },
        style: FoE.value(size: 14),
        decoration: InputDecoration(labelText: label),
      );
}
