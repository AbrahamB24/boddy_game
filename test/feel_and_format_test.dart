import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/ui/feel.dart';
import 'package:boddygame/core/ui/number_format.dart';
import 'package:boddygame/features/settlement/data/workshop_role_effects.dart';

// ── How the game reads and feels (user 2026-07-30) ──────────
// "Finde in der gesamten App Verbesserungen zum Ui und UX … bitte alles
// umsetzen."
//
// Two of those are pure functions with a right answer, so they get pinned here:
// the number vocabulary (which existed in ONE screen and disagreed with every
// other) and the event→sensation mapping (which has to cover every event or a
// moment lands silently).
void main() {
  // The haptics channel needs a binding — and a plain Dart test not having one
  // is exactly the environment Feel must survive.
  TestWidgetsFlutterBinding.ensureInitialized();
  group('numbers read the same everywhere', () {
    test('under a thousand is a figure, above it a magnitude', () {
      expect(shortNumber(0), '0');
      expect(shortNumber(840), '840');
      expect(shortNumber(999), '999');
      expect(shortNumber(1000), '1.0k');
      expect(shortNumber(1240), '1.2k');
      // Past five digits the decimal is noise.
      expect(shortNumber(12400), '12k');
      expect(shortNumber(96000), '96k');
      expect(shortNumber(1400000), '1.4M');
    });

    test('a negative keeps its sign', () {
      expect(shortNumber(-2500), '-2.5k');
    });

    test('a CEILING stays exact until the digits stop informing', () {
      // The bug this closes: the header said "96k" and the building dialog under
      // it said "96000" for the same store.
      expect(formatBuildingEffect('storage', 'wood', 500), '500');
      expect(formatBuildingEffect('storage', 'gold', 2000), '2000');
      expect(formatBuildingEffect('storage', 'wood', 96000), '96k');
    });

    test('shortNumberAbove leaves the small end alone', () {
      expect(shortNumberAbove(9999), '9999');
      expect(shortNumberAbove(10000), '10k');
      expect(shortNumberAbove(1500, from: 1000), '1.5k');
    });
  });

  group('every moment has a sensation', () {
    test('nothing in the vocabulary is missing a mapping', () {
      // A new FeelEvent with no clip would throw on the switch in _sound, and a
      // silent catch would hide it — so the asset table is checked exhaustively.
      Feel.debugMute();
      addTearDown(Feel.debugReset);
      for (final e in FeelEvent.values) {
        // Neither channel may throw for any event, with either switch state.
        expect(() => Feel.of(e), returnsNormally, reason: e.name);
      }
    });

    test('the switches are independent', () async {
      Feel.debugMute();
      addTearDown(Feel.debugReset);
      await Feel.setSoundOn(false);
      expect(Feel.soundOn, isFalse);
      expect(Feel.hapticsOn, isTrue, reason: 'silent but buzzing is a real one');
      await Feel.setHapticsOn(false);
      expect(Feel.hapticsOn, isFalse);
      // And a muted game still resolves every call.
      for (final e in FeelEvent.values) {
        expect(() => Feel.of(e), returnsNormally, reason: e.name);
      }
    });
  });
}
