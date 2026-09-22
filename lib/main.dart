import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/ui/feel.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/parchment_theme.dart';
import 'core/ui/phone_frame.dart';
import 'core/ui/app_navigator.dart';
import 'features/auth/auth_screens.dart';
import 'features/settlement/settlement_screen.dart';
import 'features/social/services/alert_prefs.dart';
import 'features/social/services/message_notifier.dart';
import 'features/social/services/pvp_notifier.dart';
import 'features/social/widgets/pvp_banner.dart';

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
  // LANDSCAPE, APP-WIDE (2026-09-18 redesign) — one lock here rather than
  // per-screen: every screen's chrome (the phone frame, headers, sheets, the
  // settlement's own bottom carousel) is now built for a wide-short
  // viewport. This used to be SettlementScreen's own OrientationLock
  // override (portraitUp/portraitDown); that mixin is gone along with it —
  // nothing else in the app ever locked orientation, so one global call
  // covers every screen with nothing left to override it.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  // The system bars are hidden for the whole game from the first frame. The
  // settlement screen used to switch them off only when it appeared — the very
  // moment the map loads — and hiding the navigation bar resizes the window, so
  // the surface changed size mid-load (a half-drawn map on some phones).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  // IN PARALLEL, because none of the three needs another's result
  // (2026-09-21). They ran one after the other, and two of them are
  // SharedPreferences reads that each pay their own platform-channel round
  // trip while Supabase's own disk read sits waiting its turn — serial cost
  // on the one stretch of the launch where nothing is on screen yet.
  //
  // The sound/vibration switches are in here so they are settled before the
  // first frame: a player who muted the game last time must not get one cue
  // back on launch.
  await Future.wait([
    Feel.load(),
    AlertPrefs.load(),
    Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey),
  ]);
  runApp(const BoddyGameApp());
}

class BoddyGameApp extends StatelessWidget {
  const BoddyGameApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: appNavigatorKey,
    title: 'Bøddy Game',
    debugShowCheckedModeBanner: false,
    // ONE theme for the whole app (user 2026-07-27) — see parchment_theme.dart
    // for why a theme rather than a sweep of call sites.
    theme: buildParchmentTheme(),
    // Wraps the Navigator, so pushed routes, dialogs and sheets are all inside
    // the phone viewport rather than around it.
    // The PvP banner hangs above the navigator, so a lobby invitation shows on
    // whatever screen the player is on.
    builder: (context, child) => PhoneFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [child!, const PvpBannerHost()],
      ),
    ),
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
      // PvP is watched for as long as somebody is signed in — challenges and
      // lobby arrivals are announced wherever the player happens to be.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (session == null) {
          PvpNotifier.instance.stop();
          MessageNotifier.instance.stop();
        } else {
          PvpNotifier.instance.start();
          MessageNotifier.instance.start();
        }
      });
      if (session == null) return const LoginScreen();
      if (_recovering) {
        return ResetPasswordScreen(
          onDone: () => setState(() => _recovering = false),
        );
      }
      return const SettlementScreen();
    },
  );
}
