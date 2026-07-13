import 'package:flutter/material.dart';

import '../../../core/theme/workout_theme.dart';

// A small tappable control (stepper +/-, duration +/-, filter/sort icon, …)
// that carries a real Material hover/press overlay — the plain GestureDetector
// containers used before had none. Draws its own background/border/shadow, then
// clips an InkWell on top so the hover ripple stays inside the shape. A null
// onTap disables it (greyed by the caller, no hover).
class WorkoutTapButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final Color background;
  final bool circle; // true = circle, else a rounded rect using [radius]
  final double? radius; // corner radius for non-circle; null = WC.radius
  final Color? borderColor;
  final bool shadow;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  const WorkoutTapButton({
    super.key,
    required this.onTap,
    required this.child,
    required this.background,
    this.circle = false,
    this.radius,
    this.borderColor,
    this.shadow = false,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final side = borderColor != null
        ? BorderSide(color: borderColor!)
        : BorderSide.none;
    final ShapeBorder shape = circle
        ? CircleBorder(side: side)
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius ?? WC.radius),
            side: side,
          );
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: shape,
        shadows: shadow ? WC.cardShadow : null,
      ),
      child: Material(
        color: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(padding: padding, child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}
