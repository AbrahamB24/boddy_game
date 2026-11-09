import 'package:flutter/material.dart';

import '../../../core/theme/ui_art.dart';
import '../../../core/theme/voxel_kit.dart';
import '../../../core/ui/pressable.dart';

/// THE SETTLEMENT HUD IN THE VOXEL KIT (user 2026-11-08, "Voxel-Block mit
/// Pixel-Icons"): the same stepped corners, dark outline, lit top edge, hard
/// offset shadow, flat fills and block bars as the monster detail screen, so the
/// map's chrome and that screen read as one app.
abstract final class VoxelHud {
  /// The one plate colour every cell shares, and the deeper one behind the
  /// energy block.
  static const Color plate = Color(0xFF2A6A80);
  static const Color plateDeep = Color(0xFF1F4A5C);

  /// Text on the plates: bright ink, a quieter weight, and the two states.
  static const Color ink = Color(0xFFEAF4F8);
  static const Color inkSoft = Color(0xFFB4CEDB);
  static const Color warn = Color(0xFFFF8A5C);
  static const Color good = Color(0xFF4AE08F);

  /// A pixel glyph from assets/images/ui_px/, drawn [size] logical px on its
  /// longer side and never smoothed.
  static Widget px(String name, double size) => Image.asset(
    UiArt.px(name),
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.none,
    isAntiAlias: false,
    gaplessPlayback: true,
  );

  /// The colour of a resource's stock bar (the store's fill under its figure).
  static Color stockColor(String resourceId) => switch (resourceId) {
    'wood' => const Color(0xFFD8A060),
    'stone' => const Color(0xFFB9C6CC),
    'fish' => const Color(0xFF7FC8E8),
    'gold' => const Color(0xFFFFD96A),
    'housing' => const Color(0xFFC9A0E8),
    _ => const Color(0xFF7FD6E8),
  };
}

/// One block of the HUD: a stepped plate with the kit's outline and a hard
/// shadow. Tappable when [onTap] is given.
class VoxelCell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final EdgeInsetsGeometry padding;
  final int notch;

  const VoxelCell({
    super.key,
    required this.child,
    this.onTap,
    this.color = VoxelHud.plate,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    this.notch = 2,
  });

  @override
  Widget build(BuildContext context) {
    final block = DecoratedBox(
      decoration: ShapeDecoration(
        color: color,
        shape: VoxelShape(notch: notch),
        shadows: voxelDrop(depth: 2),
      ),
      child: Padding(padding: padding, child: child),
    );
    return onTap == null ? block : Pressable(onTap: onTap, child: block);
  }
}

/// ENERGY, THE BIGGEST THING ON THE BAR (user 2026-11-08): a big percentage and
/// a wide block bar in the middle, the time it will last on the right and the
/// treasure chest only a small button on the corner.
class VoxelEnergyBlock extends StatelessWidget {
  /// The pool in percent, 0..[maxPercent].
  final double percent;
  final double maxPercent;

  /// "2 h 54 min" — how long the pool lasts at the steady drain.
  final String timeLeft;
  final VoidCallback onTap;
  final VoidCallback onChest;

  const VoxelEnergyBlock({
    super.key,
    required this.percent,
    required this.maxPercent,
    required this.timeLeft,
    required this.onTap,
    required this.onChest,
  });

  @override
  Widget build(BuildContext context) {
    final over = percent > 100;
    final bar = over ? const Color(0xFFFFD96A) : VoxelHud.good;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Semantics(
          label: 'Energy',
          button: true,
          child: VoxelCell(
            onTap: onTap,
            color: VoxelHud.plateDeep,
            padding: const EdgeInsets.fromLTRB(8, 6, 30, 6),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: const Color(0xFF175034),
                    shape: const VoxelShape(notch: 1),
                  ),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(child: VoxelHud.px('badge_bolt_bare', 30)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${percent.round()}%',
                            style: Voxel.text(
                              size: 32,
                              color: over ? bar : VoxelHud.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Energy',
                            style: Voxel.text(
                              size: 15,
                              color: VoxelHud.inkSoft,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      VoxelBar(
                        value: percent / maxPercent,
                        color: bar,
                        height: 14,
                        block: 9,
                        onDark: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeLeft,
                      style: Voxel.text(size: 16, color: VoxelHud.ink),
                    ),
                    Text(
                      'left',
                      style: Voxel.text(size: 13, color: VoxelHud.inkSoft),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: -6,
          top: -8,
          child: Semantics(
            label: 'All resources',
            button: true,
            child: VoxelCell(
              onTap: onChest,
              color: const Color(0xFFA8821A),
              padding: const EdgeInsets.all(6),
              child: VoxelHud.px('chest_s', 22),
            ),
          ),
        ),
      ],
    );
  }
}
