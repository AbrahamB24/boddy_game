import 'package:flutter/material.dart' hide Text;

import '../models/creature_instance.dart';
import 'trading_card.dart';

/// One extra figure a screen wants on the card — the stat this seat or trip is
/// judged on, the level-1 power a breeding parent passes on. Drawn as a small
/// flag down the picture's right edge; up to three fit.
class TileValue {
  final String label;
  final Object value;

  const TileValue(this.label, this.value);
}

/// THE monster card of every screen (user 2026-11-16: "solche Kacheln sollen
/// alle durch die Trading Cards ersetzt werden in der gesamten App"). The old
/// foot-and-free-monster tile is gone; this class stays as the one entry point
/// the ~15 screens already call and simply draws a [TradingCard]. The Bestiary
/// uses [CreatureCard.shrouded] for undiscovered species.
class CreatureCard extends StatelessWidget {
  final CreatureInstance? creature;
  final String? shroudImageUrl;
  final bool shrouded;
  final VoidCallback? onTap;

  /// The HP bar along the card's bottom. Off where health is beside the point
  /// (Breeding picks a parent on its genes, not its wounds).
  final bool showHp;

  /// Up to three extra figures, as flags on the picture.
  final List<TileValue> extras;

  /// Show the level AND the power worked out AT this level (Breeding).
  final int? atLevel;

  /// Kept for the callers that still pass it: a TradingCard always carries its
  /// rarity (colour + label), so there is nothing more to switch on.
  final bool rarityFrame;
  final bool showXp;

  const CreatureCard({
    super.key,
    required CreatureInstance this.creature,
    this.onTap,
    this.showHp = true,
    this.extras = const [],
    this.atLevel,
    this.rarityFrame = false,
    this.showXp = false,
  }) : shrouded = false,
       shroudImageUrl = null;

  const CreatureCard.shrouded({super.key, this.shroudImageUrl, this.onTap})
    : shrouded = true,
      creature = null,
      showHp = false,
      extras = const [],
      atLevel = null,
      rarityFrame = false,
      showXp = false;

  @override
  Widget build(BuildContext context) => shrouded
      ? TradingCard.shrouded(shroudImageUrl: shroudImageUrl, onTap: onTap)
      : TradingCard(
          creature!,
          onTap: onTap,
          showHp: showHp,
          extras: extras,
          atLevel: atLevel,
          showXp: showXp,
        );
}
