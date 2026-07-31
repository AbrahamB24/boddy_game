import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── How an action FEELS (user 2026-07-30) ────────────────────
// "Finde in der gesamten App Verbesserungen zum Ui und UX, so dass es sich
// besser anfühlt, das Spiel zu spielen."
//
// Before this, the whole game was silent and only the BATTLE buzzed: three
// HapticFeedback calls in battle_screen and nothing anywhere else. Placing a
// building, hiring a worker, sending an expedition, finishing a craft — every
// one of them landed with no sensation at all, which is why they felt like form
// submissions rather than things that happened.
//
// One facade for both channels, named by WHAT HAPPENED rather than by which
// vibration or clip to use ([Feel.tap], [Feel.place], [Feel.success] …). Call
// sites therefore say what the moment is, and the mapping stays in one file —
// which is the only way a game keeps a consistent voice as it grows.
//
// Both channels are OPTIONAL and independently switchable, persisted with
// shared_preferences and default to on. The switch is the speaker icon in the
// settlement header (FeelButton): one tap mutes, a long press opens both
// switches — a mute buried in a settings page is a mute nobody finds on the bus.
//
// Everything is fire-and-forget and error-swallowing: a missing asset, a device
// with no vibrator, a headless test — none of them may break a tap. Note that
// this needs [_fireAndForget] rather than a try/catch, because the failure of a
// call nobody awaits arrives later and lands as an unhandled async error.
enum FeelEvent {
  /// An ordinary confirm: a button that did something small.
  tap,

  /// Something was SET DOWN in the world — a building placed or dropped after a
  /// drag, a road painted.
  place,

  /// A thing finished or was accepted: a worker hired, an expedition sent, a
  /// treatment started.
  success,

  /// Resources or items arrived — loot claimed, a craft collected, a trade paid.
  collect,

  /// Earned something bigger: a level, an evolution, an era.
  fanfare,

  /// REFUSED. Not enough goods, no room, not your turn.
  deny,
}

/// The one place that decides what each moment sounds and feels like.
class Feel {
  Feel._();

  static const _soundKey = 'feel_sound_on';
  static const _hapticsKey = 'feel_haptics_on';

  static bool _soundOn = true;
  static bool _hapticsOn = true;
  static bool _loaded = false;

  /// Whether sound effects play. Persisted.
  static bool get soundOn => _soundOn;

  /// Whether the phone buzzes. Persisted. Independent of [soundOn] on purpose:
  /// silent-but-buzzing is a real preference (and the usual one in public).
  static bool get hapticsOn => _hapticsOn;

  /// One player per event so a fanfare cannot cut off a tap, and so the same
  /// clip re-triggering restarts cleanly. Created lazily — a session that never
  /// makes a sound never opens an audio channel.
  static final Map<FeelEvent, AudioPlayer> _players = {};

  /// Loads the two switches. Safe to call more than once; safe to skip entirely
  /// (the defaults are on).
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _soundOn = prefs.getBool(_soundKey) ?? true;
      _hapticsOn = prefs.getBool(_hapticsKey) ?? true;
    } catch (e) {
      debugPrint('[Feel] preferences unavailable, using defaults: $e');
    }
  }

  static Future<void> setSoundOn(bool on) async {
    _soundOn = on;
    if (!on) {
      for (final p in _players.values) {
        try {
          await p.stop();
        } catch (_) {}
      }
    }
    await _write(_soundKey, on);
  }

  static Future<void> setHapticsOn(bool on) async {
    _hapticsOn = on;
    // Confirm the switch with the thing it switches — the only honest preview.
    if (on) _fireAndForget(HapticFeedback.selectionClick(), 'haptics');
    await _write(_hapticsKey, on);
  }

  static Future<void> _write(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('[Feel] could not persist $key: $e');
    }
  }

  /// THE call site's whole job: say what happened.
  ///
  /// Never awaited by callers and never throws — a moment that cannot be felt
  /// still has to happen.
  static void of(FeelEvent event) {
    _haptic(event);
    _sound(event);
  }

  // Shorthands, so a call reads as the moment rather than as a lookup.
  static void tap() => of(FeelEvent.tap);
  static void place() => of(FeelEvent.place);
  static void success() => of(FeelEvent.success);
  static void collect() => of(FeelEvent.collect);
  static void fanfare() => of(FeelEvent.fanfare);
  static void deny() => of(FeelEvent.deny);

  /// Starts [work] and DISCARDS its outcome, errors included.
  ///
  /// Both channels are async platform calls, and a plain try/catch around a call
  /// that is never awaited catches nothing: the failure arrives later, as an
  /// unhandled async error. That is a red screen in debug and log noise in
  /// production for something as inconsequential as a device with no vibrator.
  static void _fireAndForget(Future<void> work, String what) {
    work.catchError((Object e) {
      debugPrint('[Feel] $what unavailable: $e');
    });
  }

  static void _haptic(FeelEvent event) {
    if (!_hapticsOn) return;
    try {
      switch (event) {
        // A selection click is the lightest thing the OS offers — right for
        // something that happens dozens of times a session.
        case FeelEvent.tap:
        case FeelEvent.collect:
          _fireAndForget(HapticFeedback.selectionClick(), 'haptics');
        case FeelEvent.success:
          _fireAndForget(HapticFeedback.lightImpact(), 'haptics');
        case FeelEvent.place:
          _fireAndForget(HapticFeedback.mediumImpact(), 'haptics');
        case FeelEvent.fanfare:
          _fireAndForget(HapticFeedback.heavyImpact(), 'haptics');
        // A refusal should feel like one: the sharpest pattern available, so it
        // registers as "no" without a dialog.
        case FeelEvent.deny:
          _fireAndForget(HapticFeedback.vibrate(), 'haptics');
      }
    } catch (e) {
      debugPrint('[Feel] no haptics here: $e');
    }
  }

  static String _asset(FeelEvent event) => switch (event) {
    FeelEvent.tap => 'sfx/tap.wav',
    FeelEvent.place => 'sfx/place.wav',
    FeelEvent.success => 'sfx/success.wav',
    FeelEvent.collect => 'sfx/collect.wav',
    FeelEvent.fanfare => 'sfx/fanfare.wav',
    FeelEvent.deny => 'sfx/deny.wav',
  };

  static void _sound(FeelEvent event) {
    if (!_soundOn) return;
    // Tests and headless runs have no audio platform channel; trying to open one
    // there logs a wall of noise for no benefit.
    if (kIsWeb == false && _muteForTests) return;
    try {
      final player = _players.putIfAbsent(event, () {
        final p = AudioPlayer();
        // LOW LATENCY is the mode for short cues (SoundPool on Android,
        // AVAudioPlayer preloaded on iOS). The default mediaPlayer mode spins up
        // a full media pipeline per play: on a 130 ms click that is audible as a
        // delay, and short clips are sometimes dropped outright — which is
        // exactly the "I hear nothing" this had (user 2026-07-30).
        _fireAndForget(p.setPlayerMode(PlayerMode.lowLatency), 'player mode');
        // One-shot: never loop, and release nothing between plays so a repeated
        // cue does not re-prepare its source every time.
        _fireAndForget(p.setReleaseMode(ReleaseMode.stop), 'release mode');
        return p;
      });
      // FULL volume. The clips are levelled to −2 dBFS and are the only thing
      // the game plays; the phone's media slider is the player's control, and
      // ducking them here just made quiet cues inaudible.
      _fireAndForget(
        player.play(AssetSource(_asset(event)), volume: 1.0),
        _asset(event),
      );
    } catch (e) {
      debugPrint('[Feel] could not play ${_asset(event)}: $e');
    }
  }

  /// Set by the test harness (and anything else that must stay silent) so a
  /// widget test does not try to open six audio channels.
  static bool _muteForTests = false;

  @visibleForTesting
  static void debugMute() => _muteForTests = true;

  @visibleForTesting
  static void debugReset() {
    _muteForTests = false;
    _soundOn = true;
    _hapticsOn = true;
    _loaded = false;
  }
}
