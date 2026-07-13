import 'package:flutter/material.dart';

import '../../../core/theme/workout_theme.dart';
import 'workout_tap_button.dart';

// Chrome-less icon button — just the icon with the shared hover/press
// feedback, no floating circle. Used for header/toolbar icons (lobby top
// bar, calendar search, chat screen); WorkoutIconButton stays the choice for
// the round floating buttons.
class PlainIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final double size;

  const PlainIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = WC.text,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) => WorkoutTapButton(
    onTap: onTap,
    background: Colors.transparent,
    radius: WC.radiusSmall,
    padding: const EdgeInsets.all(6),
    child: Icon(icon, color: color, size: size),
  );
}
