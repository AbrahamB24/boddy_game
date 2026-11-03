import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/cream_kit.dart';
import '../theme/voxel_kit.dart' show vr;

/// THE call site for a one-line message.
///
/// History: switched OFF on 2026-08-29 (user: "bitte wirklich alle pop up
/// nachrichten ... löschen") and back ON on 2026-11-02 (user: "Meldungen
/// dürfen wieder kommen") — with the silence, every refusal in the game
/// (not enough goods, settlement full, no free slot…) had become a bare buzz
/// with no reason given.
///
/// Drawn as a small cream toast in the ROOT overlay rather than a
/// [SnackBar]: many screens here are plain routes without a [Scaffold] of
/// their own, and a SnackBar would then surface on whatever screen sits
/// underneath — or not at all above a dialog. One toast at a time: a new
/// message replaces the one showing.
extension SnackX on BuildContext {
  void snack(String message, {bool error = false}) =>
      _Toast.show(this, message, error: error);
}

class _Toast {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static final bool _inTest = WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  static void show(BuildContext context, String message, {bool error = false}) {
    if (message.trim().isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _hide();
    final entry = OverlayEntry(
      builder: (_) => _ToastView(message: message, error: error),
    );
    _entry = entry;
    overlay.insert(entry);
    // Under flutter_test a pending Timer fails the test it outlives, so the
    // toast simply stays up there (and can be found by `find.text`).
    if (_inTest) return;
    // Long enough to read a two-line refusal, short enough not to linger.
    final ms = 1800 + 35 * message.length.clamp(0, 120);
    _timer = Timer(Duration(milliseconds: ms), _hide);
  }

  static void _hide() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    // The overlay it sat in may be gone already (route torn down, a test's
    // tree replaced) — removing from a dead overlay must not throw.
    if (entry != null && entry.mounted) entry.remove();
  }
}

class _ToastView extends StatelessWidget {
  final String message;
  final bool error;
  const _ToastView({required this.message, required this.error});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 14;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - t)),
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
                    ),
                    borderRadius: vr(12),
                    border: Border.all(
                      color: error ? CreamPalette.warn : CreamPalette.tan,
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x552A1A0C),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: error ? CreamPalette.warn : CreamPalette.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
