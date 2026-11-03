import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boddygame/core/ui/feel.dart';

// The sound and vibration switches in the Profile must survive a restart (user
// 2026-09-28: "wenn ich Musik und Sounds ausschalte, bleibt dies nicht
// gespeichert"). The value is written before anything is stopped, so a player
// that never finishes stopping cannot lose it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('switching sound off is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await Feel.setSoundOn(false);
    expect((await SharedPreferences.getInstance()).getBool('feel_sound_on'), false);
    expect(Feel.soundOn, isFalse);
    await Feel.setSoundOn(true);
    expect((await SharedPreferences.getInstance()).getBool('feel_sound_on'), true);
  });

  test('switching vibration off is stored', () async {
    SharedPreferences.setMockInitialValues({});
    await Feel.setHapticsOn(false);
    expect((await SharedPreferences.getInstance()).getBool('feel_haptics_on'), false);
    await Feel.setHapticsOn(true);
  });
}
