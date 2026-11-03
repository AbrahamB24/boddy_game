import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/ability_def.dart';

// What a player reads about a move is SHORT (user 2026-09-28): the first
// sentence of its description, cut at a word, never the whole rulebook.
void main() {
  group('shortAbilityDescription', () {
    test('keeps only the first sentence', () {
      expect(
        shortAbilityDescription('Hits hard. Then it burns the target for a while.'),
        'Hits hard.',
      );
    });

    test('a short text is left alone', () {
      expect(shortAbilityDescription('A quick jab.'), 'A quick jab.');
    });

    test('a long sentence is cut at a word with an ellipsis', () {
      final s = shortAbilityDescription(
        'A sweeping strike that lashes every enemy on the field with a wave of '
        'burning embers and smoke',
        max: 40,
      );
      expect(s.length, lessThanOrEqualTo(40));
      expect(s.endsWith('…'), isTrue);
      expect(s.contains('  '), isFalse);
    });

    test('whitespace and line breaks collapse', () {
      expect(shortAbilityDescription('  A\n\n  jab.  '), 'A jab.');
    });
  });
}
