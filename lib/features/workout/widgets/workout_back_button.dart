import 'package:flutter/material.dart';

import '../../../core/theme/workout_theme.dart';
import 'plain_icon_button.dart';

// THE back button for the whole app — a chrome-less chevron, no floating
// circle, exactly like leaving a chat for the chat overview. Every screen that
// can be popped uses this so back always looks and behaves the same.
//
// [color] only exists for the parked settlement/creature game, which paints on
// its own dark palette; the app itself leaves it at the default.
class WorkoutBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;

  const WorkoutBackButton({
    super.key,
    required this.onTap,
    this.color = WC.text,
  });

  @override
  Widget build(BuildContext context) => PlainIconButton(
    icon: Icons.arrow_back_ios_new,
    size: 22,
    color: color,
    onTap: onTap,
  );
}
