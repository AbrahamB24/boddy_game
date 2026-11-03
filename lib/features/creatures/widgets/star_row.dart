import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/voxel_icons.dart';

/// Three stars, [count] of them lit — a battle's best result on the map, the
/// fight card and the overview (user 2026-09-28).
class StarRow extends StatelessWidget {
  final int count;
  final double size;

  /// The colour of an unearned star. Defaults to a faint ink, right on cream;
  /// pass a light tone to sit on the wood ground.
  final Color? empty;

  const StarRow({super.key, required this.count, this.size = 14, this.empty});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count of 3 stars',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          PixelIcon(
            Icons.star_rounded,
            size: size,
            color: i < count
                ? CreamPalette.gold
                : (empty ?? kBoxInk.withValues(alpha: 0.18)),
          ),
      ],
    ),
  );
}
