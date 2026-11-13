import 'package:flutter/material.dart';

import '../creatures/models/species_def.dart';
import '../creatures/widgets/creature_sprite.dart';

/// A player's picture: one stage of one monster line from their bestiary
/// (user 2026-11-13: "wir nehmen dafür ein Portrait von den Monster").
/// Stored as `species:stage` in `profiles.avatar_species` (migration 0070).
class PortraitRef {
  final String speciesId;
  final int stage;
  const PortraitRef(this.speciesId, this.stage);

  String get code => '$speciesId:$stage';

  /// Null for anything that is not a known species and stage, so a species that
  /// is renamed or dropped later just falls back to the letter avatar.
  static PortraitRef? parse(Object? raw) {
    if (raw is! String) return null;
    final i = raw.lastIndexOf(':');
    if (i <= 0) return null;
    final stage = int.tryParse(raw.substring(i + 1));
    final id = raw.substring(0, i);
    if (kSpeciesDefs[id] == null || stage == null || stage < 0 || stage > 2) {
      return null;
    }
    return PortraitRef(id, stage);
  }

  SpeciesDef? get species => kSpeciesDefs[speciesId];
  String? get imageUrl => species?.stageAt(stage).imageUrl;
  String get name => species?.stageAt(stage).name ?? speciesId;

  @override
  bool operator ==(Object other) => other is PortraitRef && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// The monster's picture, to fill a square of [size].
class PortraitView extends StatelessWidget {
  final PortraitRef ref;
  final double size;

  const PortraitView({super.key, required this.ref, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = ref.imageUrl;
    return SizedBox(
      width: size,
      height: size,
      child: url == null
          ? null
          : CreatureSprite(url: url, width: size, height: size),
    );
  }
}
