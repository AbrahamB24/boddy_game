import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/guild/guild_studs.dart';

void main() {
  test('a board row reads into a listing with its genes and resting time', () {
    final future = DateTime.now().add(const Duration(hours: 3));
    final s = StudListing.fromRow({
      'id': 'a',
      'owner_id': 'o',
      'owner_name': 'Mira',
      'creature_id': 'c',
      'species_id': 'blazeling',
      'name': 'Ember',
      'gender': 'female',
      'level': 7,
      'rarity': 'rare',
      'genes': {
        'base': {CreatureStat.values.first.name: 12.5},
        'slope': {CreatureStat.values.first.name: 1.5},
      },
      'ready_at': future.toUtc().toIso8601String(),
      'fee': 240,
    });
    expect(s.gender, CreatureGender.female);
    expect(s.rarity, CreatureRarity.rare);
    expect(s.base[CreatureStat.values.first], 12.5);
    expect(s.slope[CreatureStat.values.first], 1.5);
    expect(s.isResting, isTrue);
    expect(s.fee, 240);
  });
}
