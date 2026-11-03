import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';

import '../theme/foe_theme.dart';
import '../theme/voxel_kit.dart' show vr;
import '../theme/voxel_icons.dart';

/// Frames the whole app to a landscape-phone-sized viewport when it runs on a
/// screen bigger than that.
///
/// WHY: this is a phone game, but it is developed and playtested in a desktop
/// browser at ~2500px. Without this, every screen stretches into a shape that
/// will never exist on a device — phone-first layouts read as broken, and
/// desktop-looking bugs get "fixed" into real ones. Framing means what you see
/// while testing IS what ships.
///
/// Hung off MaterialApp.builder so it wraps the Navigator itself: pushed
/// routes, dialogs and bottom sheets are all inside the frame, not around it.
///
/// LANDSCAPE (2026-09-18, the app-wide orientation switch): the phone shape
/// this frames to is now wide-short rather than narrow-tall, so both axes get
/// their own cap — [FoE.phoneMaxWidth] (430) is the SHORT axis now (a
/// landscape phone's height), and [_maxLong] (932) is the LONG one (its
/// width). On an actual landscape phone this is a no-op — neither cap is
/// exceeded, so the app renders edge to edge exactly as before.
class PhoneFrame extends StatelessWidget {
  final Widget child;

  /// The long axis' cap — a landscape phone's width. Without one, a
  /// maximised desktop window would render a 1400x430 sliver that is no
  /// more honest than the stretched version.
  static const double _maxLong = 932;

  const PhoneFrame({super.key, required this.child});

  /// True for a phone held upright IN A BROWSER. The game is landscape-only
  /// (main.dart locks it natively), but a web page cannot lock the screen: an
  /// Android home-screen shortcut honours the manifest's `landscape`, iOS
  /// ignores it and simply follows the phone. Framed as a desktop window this
  /// would squash the game into a 390x430 box, so it asks for a turn instead.
  /// Web only, and only for a phone-narrow window — desktop and the tests
  /// never see it.
  @visibleForTesting
  static bool needsRotation(Size size, {bool web = kIsWeb}) =>
      web && size.height > size.width && size.width < 600;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      if (needsRotation(Size(w, h))) {
        // The game stays mounted underneath, so turning the phone back keeps
        // whatever was on screen (a fight, a placement) instead of restarting.
        return Stack(
          children: [
            Positioned.fill(child: Offstage(child: child)),
            const Positioned.fill(child: _RotatePrompt()),
          ],
        );
      }
      final shortMax = FoE.phoneMaxWidth;
      if (w <= _maxLong && h <= shortMax) return child;

      final frameW = w > _maxLong ? _maxLong : w;
      final frameH = h > shortMax ? shortMax : h;

      return ColoredBox(
        color: const Color(0xFF07080A),
        child: Center(
          child: ClipRRect(
            // Smaller than it was (28→14, matching the cream kit's own card
            // radius) — user 2026-09-30, "der Rahmen wird durch das Handy
            // abgeschnitten": every menu is now ONE card going edge to edge
            // (no margin left for [kMenuGround] to show through), so a
            // corner control like the close button sits right where this
            // clip used to bite into it. A smaller radius here clears
            // corner content without needing to bring the margin back.
            borderRadius: vr(14),
            child: SizedBox(
              width: frameW,
              height: frameH,
              // The app inside must BELIEVE it is phone-sized: plenty of code
              // reads MediaQuery.size rather than its own constraints, and
              // would otherwise lay out for the desktop window it can't see.
              // Insets are dropped too — a desktop has no notch to dodge.
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(frameW, frameH),
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  viewInsets: EdgeInsets.zero,
                ),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// "Turn your phone" — shown instead of the game while a browser holds it
/// upright. See [PhoneFrame.needsRotation].
class _RotatePrompt extends StatelessWidget {
  const _RotatePrompt();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFF26120B),
    child: Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelIcon(Icons.screen_rotation, size: 56, color: Color(0xFFF5B83A)),
            SizedBox(height: 16),
            Text(
              'Turn your phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF7F0E2),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Bøddy Game is played in landscape. If nothing happens, switch '
              'off your phone\'s rotation lock.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFE9DABE),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
