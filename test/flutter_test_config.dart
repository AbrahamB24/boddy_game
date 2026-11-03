import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/ui/feel.dart';

/// Runs once around every test file.
///
///  • Mutes [Feel] — audioplayers has no plugin when running headless.
///  • Loads the app's pixel face (Jersey 10, pubspec `fonts:`). `flutter test`
///    does not load pubspec fonts by itself, so without this every text would
///    be measured in the test font's wide square glyphs instead of the narrow
///    ones a device draws, and a tight layout would "overflow" in a test it
///    does not overflow in the app.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Feel.debugMute();
  final loader = FontLoader('Jersey10')
    ..addFont(rootBundle.load('assets/fonts/Jersey10-Regular.ttf'));
  await loader.load();
  await testMain();
}
