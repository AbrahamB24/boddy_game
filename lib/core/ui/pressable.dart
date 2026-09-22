import 'package:flutter/material.dart';

/// Wraps ANY tappable widget with the same physical "pressed" feel the
/// QuickPad tiles already had (user 2026-09-07: "bei allen Buttons, den
/// Drückeffekt wie bei diesen Buttons einfügen") — every custom button in
/// the app used a bare [GestureDetector] with no visual feedback at all
/// beyond whatever its own [onTap] eventually did, so nothing ever
/// registered as having been pressed.
///
/// Two things happen on a tap, in order:
///
///  1. The child visibly travels DOWN by [depth] on press, and back up on
///     release — the same "the whole depth is the travel" idea the
///     QuickPad tiles use, generalised to a plain translate + a soft
///     darkening wash so it works on any shape (a pill, an icon, a full
///     card) without needing that widget's specific plinth-and-face boxes.
///  2. [onTap] itself does NOT fire the instant the finger lifts — it waits
///     for the release animation to finish first (user: "die Animation
///     abwarten, bevor der Effekt ausgelöst wird, so dass man spürt, dass
///     ein Button gedrückt wurde"). Firing it immediately, the way a bare
///     GestureDetector does, means whatever the tap causes (a navigation, a
///     dialog, a rebuild) lands in the SAME frame the button is still
///     shown mid-spring — so the press is never actually seen before its
///     consequence is.
///
/// A disabled button ([onTap] null) never animates and never eats the
/// gesture — exactly like a bare GestureDetector with a null onTap.
class Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  final HitTestBehavior behavior;

  /// How far the child travels down when pressed.
  static const double depth = 2;

  /// How long the press/release travel takes — also the delay before
  /// [onTap] fires, so the two always finish together.
  static const Duration duration = Duration(milliseconds: 90);

  const Pressable({
    super.key,
    required this.onTap,
    this.onLongPress,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  int _pressToken = 0;

  void _setDown(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  Future<void> _release() async {
    _setDown(false);
    final token = ++_pressToken;
    await Future.delayed(Pressable.duration);
    // A second, faster tap while the first was still waiting out its own
    // release must not let the FIRST one's delayed timer fire a stale
    // callback after the second press already started its own — the token
    // makes only the most recent press's timer actually call onTap.
    if (mounted && token == _pressToken) widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: active ? (_) => _setDown(true) : null,
      onTapUp: active ? (_) => _release() : null,
      onTapCancel: active ? () => _setDown(false) : null,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: Pressable.duration,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _down ? Pressable.depth : 0, 0),
        child: Stack(
          // PASSTHROUGH, not Stack's own default `loose` (user 2026-09-08,
          // reported as "die 'add monster' Boxen sind überall geschrumpft"):
          // `loose` hands non-positioned children the incoming constraints
          // with their MINIMUM dropped to zero, so a child that only fills
          // its slot because the parent's constraints are TIGHT (a grid
          // cell, e.g. EmptyMonsterSlot's LayoutBuilder) is suddenly free to
          // shrink to its own content size instead — every such tile across
          // the app shrank the moment it was wrapped here. `passthrough`
          // hands [widget.child] the exact constraints Pressable itself
          // received, so wrapping a widget can never change how big it
          // renders — only the darken overlay needs `Positioned.fill`,
          // which ignores this fit entirely.
          fit: StackFit.passthrough,
          children: [
            widget.child,
            // A soft, uniform darkening rather than a shape-matched overlay
            // — matching every possible child's own corner radius exactly
            // would need that radius as a parameter everywhere this wraps,
            // and at this opacity the plain rectangle's corners poking past
            // a rounded child's are not something a press this brief draws
            // the eye to.
            if (active)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _down ? 0.16 : 0.0,
                    duration: Pressable.duration,
                    curve: Curves.easeOut,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
