import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash reporting through Firebase Crashlytics (user 2026-09-28).
///
/// It does nothing — and nothing about the app changes — unless ALL of these
/// hold, so a checkout without a Firebase project still builds and runs:
///  * a phone build: Crashlytics has no web support, and the web build is what
///    is playtested on a phone's home screen;
///  * a RELEASE build, or one started with `--dart-define=CRASH_REPORTING=true`
///    (so a debug session's own errors do not pollute the reports, and the wiring
///    can still be tried out);
///  * the project's `google-services.json` in `android/app/` (see
///    android/app/build.gradle.kts) — without it [Firebase.initializeApp] fails
///    and that failure is swallowed here.
///
/// Once on, every uncaught Flutter error is recorded as a non-fatal report and
/// every uncaught async error as a fatal one; the previous handlers still run, so
/// the console keeps printing.
class CrashReporting {
  CrashReporting._();

  /// Turns reporting on in a debug build too — for trying the wiring out.
  static const bool _forced = bool.fromEnvironment('CRASH_REPORTING');

  static bool _active = false;

  /// Whether reports are actually being sent.
  static bool get active => _active;

  /// Call once at startup, before `runApp`. Never throws.
  static Future<void> init() async {
    if (kIsWeb) return;
    if (!kReleaseMode && !_forced) return;
    try {
      await Firebase.initializeApp();
      final crashlytics = FirebaseCrashlytics.instance;
      await crashlytics.setCrashlyticsCollectionEnabled(true);

      final previousFlutter = FlutterError.onError;
      FlutterError.onError = (details) {
        previousFlutter?.call(details);
        crashlytics.recordFlutterError(details);
      };
      final previousPlatform = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return previousPlatform?.call(error, stack) ?? false;
      };
      _active = true;
    } catch (e) {
      // No google-services.json, no Play services, an emulator without them …
      // none of that may stop the game from starting.
      debugPrint('[CrashReporting] off: $e');
    }
  }

  /// A handled problem worth knowing about (a save that failed, a load that
  /// came back wrong) — shows up as a non-fatal report. A no-op while off.
  static void note(Object error, StackTrace? stack, {String? reason}) {
    if (!_active) return;
    FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      fatal: false,
    );
  }

  /// Tags every later report with who it happened to — the account id, never a
  /// name or an address. Pass null to clear it (sign-out). A no-op while off.
  static void setUser(String? id) {
    if (!_active) return;
    FirebaseCrashlytics.instance.setUserIdentifier(id ?? '');
  }
}
