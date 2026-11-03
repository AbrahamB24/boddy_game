import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/ui/phone_frame.dart';

// A browser cannot lock the screen, so an upright phone must be asked to turn
// instead of getting the game squashed into a 390x430 box.
void main() {
  group('PhoneFrame.needsRotation', () {
    test('an upright phone in a browser needs a turn', () {
      expect(
        PhoneFrame.needsRotation(const Size(390, 800), web: true),
        isTrue,
      );
    });

    test('a landscape phone does not', () {
      expect(
        PhoneFrame.needsRotation(const Size(844, 390), web: true),
        isFalse,
      );
    });

    test('a tall desktop window is not a phone', () {
      expect(
        PhoneFrame.needsRotation(const Size(900, 1400), web: true),
        isFalse,
      );
    });

    test('native builds are locked by main.dart and never see the prompt', () {
      expect(
        PhoneFrame.needsRotation(const Size(390, 800), web: false),
        isFalse,
      );
    });
  });

  testWidgets('the game stays mounted under the prompt, and is not framed', (
    t,
  ) async {
    // Force the web branch through a portrait window: kIsWeb is false in the
    // VM, so this only checks the native path is untouched.
    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      const MaterialApp(home: PhoneFrame(child: Text('the game'))),
    );
    expect(find.text('the game'), findsOneWidget);
    expect(find.text('Turn your phone'), findsNothing);
  });
}
