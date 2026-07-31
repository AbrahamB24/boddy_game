import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import 'plain_icon_button.dart';

// THE back button for the whole game — a chrome-less chevron, no floating
// circle. Every screen that can be popped uses this so back always looks and
// behaves the same. [color] lets each screen match its own palette.
class AppBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const AppBackButton({super.key, required this.onTap, this.color = FoE.parchment});

  @override
  Widget build(BuildContext context) => PlainIconButton(
    icon: Icons.arrow_back_ios_new,
    size: 22,
    color: color,
    onTap: onTap,
  );
}
