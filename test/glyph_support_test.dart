import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

// ── Zeichen, die die Schrift nicht hat (user 2026-08-01) ────
// "Could not find a set of Noto fonts to display all missing characters."
//
// The app is set in Outfit, which has Latin and nothing else. A glyph outside
// that — Greek Σ, the technical pictographs ⏸ ▶ ↩ — sends Flutter hunting for a
// Noto fallback that is not bundled, and it throws ON EVERY FRAME. One caption
// with a sigma in it fills the console with hundreds of exceptions and buries
// the real error underneath.
//
// Emoji are fine: they resolve to the colour-emoji font. What is NOT fine is a
// pictograph in its TEXT presentation — the same code point without U+FE0F.
void main() {
  // Code points that exist in both a text and an emoji presentation. Bare, they
  // ask for the text one.
  const dualPresentation = {
    '⏸': 'pause',
    '▶': 'play',
    '◀': 'reverse',
    '⏯': 'play/pause',
    '↩': 'undo arrow',
  };
  // Not emoji at all — no variation selector saves these.
  const noGlyph = {
    'Σ': 'Greek capital sigma',
    '⟲': 'anticlockwise gapped circle arrow',
  };

  test('no UI string asks for a glyph the app cannot draw', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        // Comments are for humans reading the source, not for the renderer.
        if (trimmed.startsWith('//')) continue;
        if (!line.contains("'") && !line.contains('"')) continue;
        for (final e in dualPresentation.entries) {
          // With U+FE0F it is an emoji request, which resolves fine.
          if (line.contains(e.key) && !line.contains('${e.key}️')) {
            offenders.add('${f.path}:${i + 1} — ${e.value} without U+FE0F');
          }
        }
        for (final e in noGlyph.entries) {
          if (line.contains(e.key)) {
            offenders.add('${f.path}:${i + 1} — ${e.value}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these throw a Noto-fallback exception every frame:\n'
            '${offenders.join('\n')}');
  });
}
