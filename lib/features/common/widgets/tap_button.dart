import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';

// A small tappable control (stepper +/-, filter/sort icon, back chevron, …)
// that carries a real Material hover/press overlay — a plain GestureDetector
// container has none. Draws its own background/border, then clips an InkWell on
// top so the hover ripple stays inside the shape. A null onTap disables it
// (greyed by the caller, no hover).
class TapButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final Color background;
  final bool circle; // true = circle, else a rounded rect using [radius]
  final double? radius; // corner radius for non-circle; null = FoE.radius
  final Color? borderColor;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  const TapButton({
    super.key,
    required this.onTap,
    required this.child,
    required this.background,
    this.circle = false,
    this.radius,
    this.borderColor,
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
            borderRadius: BorderRadius.circular(radius ?? FoE.radius),
            side: side,
          );
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: shape,
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
