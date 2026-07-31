import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import 'tap_button.dart';

// Chrome-less icon button — just the icon with the shared hover/press
// feedback, no floating circle. Used for header/toolbar icons and, via
// AppBackButton, the back chevron.
class PlainIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final double size;

  const PlainIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = FoE.parchment,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) => TapButton(
    onTap: onTap,
    background: Colors.transparent,
    radius: FoE.radiusSmall,
    padding: const EdgeInsets.all(6),
    child: Icon(icon, color: color, size: size),
  );
}
