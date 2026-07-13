import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase/supabase_client.dart';
import 'core/theme/foe_theme.dart';
import 'features/settlement/settlement_screen.dart';

/// Bøddy — settlement & creature game.
///
/// Split out of the BoddyQuest fitness app: this is the strategy game
/// (settlement, buildings, research, eras, creatures, breeding, dungeons) on its
/// own. It talks to the SAME Supabase project as the fitness app, so an account
/// created there signs in here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const BoddyGameApp());
}

class BoddyGameApp extends StatelessWidget {
  const BoddyGameApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bøddy Game',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: FoE.bg,
    ),
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
    backgroundColor: FoE.bg,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🏰 Bøddy Game', style: FoE.title(size: 22)),
              const SizedBox(height: 6),
              Text('Sign in with your Bøddy account.', style: FoE.dim(size: 12)),
              const SizedBox(height: 24),
              _field(_email, 'Email', false),
              const SizedBox(height: 12),
              _field(_password, 'Password', true),
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
                  onPressed: _busy ? null : _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FoE.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
  );

  Widget _field(TextEditingController c, String label, bool obscure) =>
      TextField(
        controller: c,
        obscureText: obscure,
        style: FoE.value(size: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: FoE.dim(size: 12),
          filled: true,
          fillColor: FoE.panelDark,
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: FoE.border),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: FoE.gold),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
}
