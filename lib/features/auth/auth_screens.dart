import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/fachwerk.dart';
import '../../core/ui/pressable.dart';
import '../settlement/widgets/building_icon.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';

// ── The front door ──────────────────────────────────────────
// "Variante 1, Karte rechts, im Holz" (user 2026-09-20): the game's name as a
// wood plate on the left, with the sentence the welcome card uses and the castle
// under it; on the right a cream card with the Sign in / Register switch, the
// fields and the one gold button. Landscape first (a portrait column of title +
// tabs + fields + button does not fit a 430px-tall screen once the keyboard is
// up), and the card scrolls, so a field is never hidden behind the keyboard.

/// The sentence the guided intro's welcome card opens with.
const String kGameTagline =
    'Grow a settlement, raise monsters, and send them out to fight, gather and '
    'explore.';

/// The front door's frame: [heading] on a wood plate with [tagline] under it, and
/// [child] on a cream card beside it. Under ~720px wide the card goes below the
/// plate instead of beside it.
class AuthShell extends StatelessWidget {
  final String heading;
  final String tagline;
  final Widget child;

  const AuthShell({
    super.key,
    required this.heading,
    required this.child,
    this.tagline = kGameTagline,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CreamPalette.groundBottom,
    body: DecoratedBox(
      decoration: const BoxDecoration(gradient: kMenuGround),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: LayoutBuilder(
                builder: (context, box) {
                  final card = SizedBox(
                    width: box.maxWidth >= 720 ? 394 : null,
                    child: creamCard(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      framed: true,
                      roof: true,
                      child: child,
                    ),
                  );
                  final brand = _Brand(heading: heading, tagline: tagline);
                  return box.maxWidth >= 720
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: brand),
                            const SizedBox(width: 28),
                            card,
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [brand, const SizedBox(height: 18), card],
                        );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The name on a wood plate (a gold hairline under it), the tagline, the castle.
class _Brand extends StatelessWidget {
  final String heading;
  final String tagline;
  const _Brand({required this.heading, required this.tagline});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fachwerk (2026-11-02): the name hangs as a timber SIGN under a
        // course of roof tiles, the way the buildings wear them.
        IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                child: RoofTileStrip(height: 14, tileWidth: 16),
              ),
              TimberPlate(
                radius: 6,
                padding: const EdgeInsets.fromLTRB(30, 8, 30, 12),
                child: Text(
                  heading,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 44,
                    height: 1.05,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.4,
                    color: Fachwerk.windowGlow,
                    shadows: [
                      Shadow(color: Color(0x99000000), offset: Offset(0, 2)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            tagline,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: kBoxInk.withValues(alpha: 0.78),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const BuildingIcon(defId: 'castle', emoji: '🏰', size: 96),
      ],
    ),
  );
}

/// A cream input: its caption in small capitals above, an inset well with a gold
/// ring while it has the focus. The theme's own InputDecoration is bypassed
/// ([InputDecoration.collapsed]) — the well is drawn here.
class _CreamField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputAction action;
  final TextInputType? keyboardType;
  final bool autofocus;
  final VoidCallback? onDone;

  const _CreamField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.action = TextInputAction.next,
    this.keyboardType,
    this.autofocus = false,
    this.onDone,
  });

  @override
  State<_CreamField> createState() => _CreamFieldState();
}

class _CreamFieldState extends State<_CreamField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        widget.label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
          letterSpacing: 1.1,
          color: kBoxAccent,
        ),
      ),
      const SizedBox(height: 4),
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: vr(11),
          border: Border.all(
            color: _focus.hasFocus
                ? CreamPalette.gold
                : CreamPalette.tan.withValues(alpha: 0.55),
            width: _focus.hasFocus ? 2 : 1.5,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          obscureText: widget.obscure,
          autofocus: widget.autofocus,
          keyboardType: widget.keyboardType,
          textInputAction: widget.action,
          cursorColor: kBoxInk,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: kBoxInk,
          ),
          decoration: const InputDecoration.collapsed(hintText: null),
          // Enter submits — moves to the next field, or logs in/signs up from
          // the last one, whichever mode is active.
          onSubmitted: (_) {
            if (widget.action == TextInputAction.done) {
              widget.onDone?.call();
            } else {
              FocusScope.of(context).nextFocus();
            }
          },
        ),
      ),
    ],
  );
}

/// The gold commit button, with a spinner while [busy].
class _SubmitButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;
  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: busy ? null : onTap,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: goldButton(active: !busy),
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: kBoxInk),
            )
          : Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: goldButtonInk(),
              ),
            ),
    ),
  );
}

/// The Sign in / Register switch: two halves in a sand track, the live one gold.
class _ModeSwitch extends StatelessWidget {
  final bool signUp;
  final ValueChanged<bool> onChanged;
  const _ModeSwitch({required this.signUp, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget half(String label, bool on, bool value) => Expanded(
      child: Pressable(
        onTap: () => onChanged(value),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: on
              ? BoxDecoration(
                  color: CreamPalette.gold,
                  borderRadius: vr(9),
                  boxShadow: const [
                    BoxShadow(
                      color: CreamPalette.goldDeep,
                      offset: Offset(0, 2),
                    ),
                  ],
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: on ? kBoxInk : kBoxInkSoft,
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: CreamPalette.tan.withValues(alpha: 0.18),
        borderRadius: vr(12),
      ),
      child: Row(
        children: [
          half('Sign in', !signUp, false),
          const SizedBox(width: 3),
          half('Register', signUp, true),
        ],
      ),
    );
  }
}

/// An error (warn colour) or an info line under the fields.
Widget _messageLine(String text, {required bool error}) => Padding(
  padding: const EdgeInsets.only(top: 2),
  child: Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: error ? CreamPalette.warn : kBoxInkSoft,
    ),
  ),
);

/// Sign-in AND sign-up against the shared Supabase project — an account
/// created in the fitness app signs in here just the same, but this no
/// longer requires that app: _signUp() below registers one directly.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  bool _busy = false;
  bool _isSignUp = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    super.dispose();
  }

  /// Flips the form; the message of the other mode goes with it.
  void _setMode(bool signUp) {
    if (signUp == _isSignUp) return;
    setState(() {
      _isSignUp = signUp;
      _error = null;
      _info = null;
    });
  }

  Future<void> _submit() => _isSignUp ? _signUp() : _signIn();

  /// "Forgot password?" (user 2026-09-15). Asks for the email once more in
  /// its own small dialog (pre-filled from the form) rather than reusing
  /// [_password]'s neighbour field inline — the request has nothing to do
  /// with whatever half-typed password is currently in that field, and a
  /// dialog makes the "a link is on its way" confirmation its own moment
  /// instead of overloading the sign-in form's single `_info` line.
  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ResetDialog(initialEmail: _email.text.trim()),
    );
    if (email == null || email.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await supabase.auth.resetPasswordForEmail(
        email,
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
          _info =
              'If an account exists for that email, a reset link is on its way.';
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
        _passwordConfirm.clear();
        setState(() {
          _isSignUp = false;
          _info =
              'Account created — check your email to confirm it, '
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
  Widget build(BuildContext context) => AuthShell(
    heading: 'Bøddy Game',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeSwitch(signUp: _isSignUp, onChanged: _setMode),
        const SizedBox(height: 12),
        _CreamField(
          controller: _email,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 10),
        _CreamField(
          controller: _password,
          label: 'Password',
          obscure: true,
          // One more field follows while registering — Enter should
          // move on, not submit a form that isn't filled in yet.
          action: _isSignUp ? TextInputAction.next : TextInputAction.done,
          onDone: _busy ? null : _submit,
        ),
        if (_isSignUp) ...[
          const SizedBox(height: 10),
          _CreamField(
            controller: _passwordConfirm,
            label: 'Repeat password',
            obscure: true,
            action: TextInputAction.done,
            onDone: _busy ? null : _submit,
          ),
        ] else
          Align(
            alignment: Alignment.centerRight,
            child: Pressable(
              onTap: _busy ? null : _forgotPassword,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 0, 4),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: kBoxAccent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        if (_error != null) _messageLine(_error!, error: true),
        if (_info != null) _messageLine(_info!, error: false),
        const SizedBox(height: 10),
        _SubmitButton(
          label: _isSignUp ? 'Create account' : 'Sign in',
          busy: _busy,
          onTap: _submit,
        ),
      ],
    ),
  );
}

/// The small "Reset password" dialog: the address once more, pre-filled. Pops
/// with the trimmed address, or null on Cancel.
class _ResetDialog extends StatefulWidget {
  final String initialEmail;
  const _ResetDialog({required this.initialEmail});

  @override
  State<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends State<_ResetDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _send() => Navigator.pop(context, _email.text.trim());

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: creamCard(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        framed: true,
        roof: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Reset password',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: kBoxInk,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'We send a link to this address.',
              style: TextStyle(fontSize: 11, color: kBoxInkSoft),
            ),
            const SizedBox(height: 12),
            _CreamField(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              action: TextInputAction.done,
              onDone: _send,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Pressable(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    alignment: Alignment.center,
                    decoration: raisedTile(radius: 12),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: kBoxInk,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Pressable(
                  onTap: _send,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    alignment: Alignment.center,
                    decoration: goldButton(),
                    child: Text(
                      'Send link',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: goldButtonInk(),
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

/// The far end of the "Forgot password?" email link: sets a new password on
/// the short-lived recovery session [_AuthGate] detected, then hands back
/// via [onDone] so the gate re-evaluates into the settlement.
class ResetPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const ResetPasswordScreen({super.key, required this.onDone});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
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
  Widget build(BuildContext context) => AuthShell(
    heading: 'Bøddy Game',
    tagline:
        'You came back through the link in your email. Pick a password you '
        'will remember.',
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose a new password',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            color: kBoxInk,
          ),
        ),
        const SizedBox(height: 12),
        _CreamField(
          controller: _password,
          label: 'New password',
          obscure: true,
          autofocus: true,
        ),
        const SizedBox(height: 10),
        _CreamField(
          controller: _confirm,
          label: 'Repeat new password',
          obscure: true,
          action: TextInputAction.done,
          onDone: _busy ? null : _submit,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          _messageLine(_error!, error: true),
        ],
        const SizedBox(height: 12),
        _SubmitButton(label: 'Save password', busy: _busy, onTap: _submit),
      ],
    ),
  );
}
