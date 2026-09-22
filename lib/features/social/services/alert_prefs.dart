import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one switch behind Profile's "Banners" (user 2026-09-19): whether a friend
/// arriving in the PvP lobby, a new message or your move in a fight raises a
/// banner (with its sound and, out of sight, a system notification).
///
/// Off silences the ANNOUNCEMENT only. The badge on the Social button and the
/// lists still show everything that is waiting, so nothing is lost — you just
/// are not interrupted. Persisted on this device; defaults to on.
class AlertPrefs {
  AlertPrefs._();

  static const _key = 'social_banners_on';
  static bool _on = true;

  static bool get bannersOn => _on;

  /// Reads the saved choice. Safe to skip (the default is on) and safe to call
  /// twice.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _on = prefs.getBool(_key) ?? true;
    } catch (e) {
      debugPrint('[AlertPrefs] preferences unavailable, using defaults: $e');
    }
  }

  static Future<void> setBannersOn(bool on) async {
    _on = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, on);
    } catch (e) {
      debugPrint('[AlertPrefs] could not persist: $e');
    }
  }
}
