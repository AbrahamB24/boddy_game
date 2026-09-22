import 'package:flutter/material.dart';

import '../theme/foe_theme.dart';

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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      final shortMax = FoE.phoneMaxWidth;
      if (w <= _maxLong && h <= shortMax) return child;

      final frameW = w > _maxLong ? _maxLong : w;
      final frameH = h > shortMax ? shortMax : h;

      return ColoredBox(
        color: const Color(0xFF07080A),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
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
