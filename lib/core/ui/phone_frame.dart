import 'package:flutter/material.dart';

import '../theme/foe_theme.dart';

/// Frames the whole app to a phone-sized viewport when it runs on a screen
/// wider than a phone.
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
/// On an actual phone this is a no-op — [FoE.phoneMaxWidth] is never exceeded,
/// so the app renders edge to edge exactly as before.
class PhoneFrame extends StatelessWidget {
  final Widget child;

  /// Tallest we let the framed viewport get. Roughly a large phone; without a
  /// cap, a maximised desktop window would render a 430x1400 sliver that is
  /// no more honest than the stretched version.
  static const double _maxHeight = 932;

  const PhoneFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      if (w <= FoE.phoneMaxWidth) return child;

      final frameW = FoE.phoneMaxWidth;
      final frameH = h > _maxHeight ? _maxHeight : h;

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
