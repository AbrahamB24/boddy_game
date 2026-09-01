import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import 'plain_icon_button.dart';

// THE back button for the whole game — a chrome-less chevron, no floating
// circle. Every screen that can be popped uses this so back always looks and
// behaves the same. [color] lets each screen match its own palette.
class AppBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  /// See [PlainIconButton.shadows] — the header band's own back arrow
  /// passes its engraved-ink shadows through here instead of drawing a
  /// second back control by hand.
  final List<Shadow>? shadows;

  const AppBackButton({
    super.key,
    required this.onTap,
    this.color = FoE.parchment,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) => PlainIconButton(
    icon: Icons.arrow_back_ios_new,
    size: 22,
    color: color,
    shadows: shadows,
    onTap: onTap,
  );
}
