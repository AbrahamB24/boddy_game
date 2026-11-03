import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/creatures/models/creature_enums.dart';

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
// shared_preferences and default to on. The switches live in the Profile's
// Preferences (user 2026-09-20 — the old header speaker icon is gone).
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

  /// Somebody or something is waiting on you: a friend in the PvP lobby, a
  /// message, your turn in a match you stepped out of (user 2026-09-19).
  alert,
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
    // ── "der Sound am Handy verschwindet nach der ersten Aktion" (user
    //    2026-08-29) ──
    // A known audioplayers/mobile gotcha, not a bug in any one clip: every
    // FeelEvent, every attack element and the battle theme each get their OWN
    // AudioPlayer (see _sound/attackSound/startBattleMusic above), and without
    // an explicit AudioContext, iOS leaves the shared AVAudioSession in
    // whatever ad-hoc state the FIRST player's own activate/deactivate cycle
    // left it in — the second player's .play() can then land on a session
    // that already tore itself down and produce nothing, silently. Setting
    // ONE global context up front (mixWithOthers, so no player's session
    // lifecycle fights another's for exclusive focus) is the documented fix.
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(
          focus: AudioContextConfigFocus.mixWithOthers,
        ).build(),
      );
    } catch (e) {
      debugPrint('[Feel] audio context unavailable: $e');
    }
  }

  static Future<void> setSoundOn(bool on) async {
    _soundOn = on;
    // SAVED FIRST (user 2026-09-28: "wenn ich Musik und Sounds ausschalte, bleibt
    // dies nicht gespeichert"). Stopping the players used to come before this
    // write, and an audioplayers `stop()` that never completes — it can, in a
    // browser — meant the switch was never stored at all.
    await _write(_soundKey, on);
    if (!on) {
      for (final p in _players.values) {
        try {
          await p.stop();
        } catch (_) {}
      }
      // The music player is not in [_players] (see [startBattleMusic]) and,
      // unlike a one-shot cue, keeps looping until told to stop — muting sound
      // mid-battle must silence it too, not just future cues.
      final music = _musicPlayer;
      if (music != null) {
        try {
          await music.stop();
        } catch (_) {}
      }
    }
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
  static void alert() => of(FeelEvent.alert);

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
        case FeelEvent.alert:
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
    // No clip of its own yet: the success chime is the closest to "look here".
    FeelEvent.alert => 'sfx/success.wav',
  };

  /// Every bundled clip, readied before the game shows (user 2026-11-03:
  /// "alle Assets beim Ladescreen vorladen"). On a phone an [AssetSource] is
  /// first copied out of the app bundle into a temp file the native player
  /// can open — the first tap or the first hit of a battle paid that copy
  /// as an audible delay. [AudioCache] does the copy now, behind the loading
  /// bar; the players then find the file already there. Never throws.
  static Future<void> preloadClips() async {
    if (kIsWeb == false && _muteForTests) return;
    final clips = <String>{
      for (final e in FeelEvent.values) _asset(e),
      for (final el in CreatureElement.values) 'sfx/${el.name}_attack.mp3',
      'music/battle_theme.mp3',
    };
    await Future.wait([
      for (final clip in clips)
        // One at a time per clip, so a missing one (not every element has
        // its own attack clip yet) cannot fail the rest.
        AudioCache.instance.load(clip).then<void>((_) {}, onError: (Object _) {}),
    ]);
  }

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

  // ── Attack sounds, by element (user 2026-08-29) ──────────────
  // "Hier sind die Sound effects für die Attacken. Bitte für die jeweiligen
  // Elemente hinzufügen." One clip per CreatureElement (including `neutral`,
  // the basic attack's type). Kept OUT of FeelEvent on purpose: FeelEvent
  // names UI moments (tap, place, success…), not "which of six battle clips
  // to play", and battle_screen already knows the struck event's element —
  // no mapping to a UI moment would add anything. Same soundOn switch (one
  // mute for the whole game) and the same lazy-player/low-latency/test-mute
  // technique as [_sound], just keyed by element instead of by FeelEvent.
  static final Map<CreatureElement, AudioPlayer> _attackPlayers = {};

  /// Elements whose own clip has FAILED to load at least once this session
  /// (2026-09-14: not every element has one bundled yet — ice/lightning/
  /// stone were missing entirely, which used to mean a silent hit for a
  /// third of the game's types). Routed to neutral's clip from then on
  /// instead of re-attempting — and re-failing — the same missing asset on
  /// every single hit.
  static final Set<CreatureElement> _missingAttackClip = {};

  static String _attackAsset(CreatureElement element) =>
      'sfx/'
      '${(_missingAttackClip.contains(element) ? CreatureElement.neutral : element).name}'
      '_attack.mp3';

  /// Plays the element's attack clip. Called from battle_screen at the
  /// moment a struck event lands (hit or miss — the clip is the attack being
  /// thrown, not the impact).
  static void attackSound(CreatureElement element) {
    if (!_soundOn) return;
    if (kIsWeb == false && _muteForTests) return;
    final asset = _attackAsset(element);
    try {
      final player = _attackPlayers.putIfAbsent(element, () {
        final p = AudioPlayer();
        _fireAndForget(p.setPlayerMode(PlayerMode.lowLatency), 'player mode');
        _fireAndForget(p.setReleaseMode(ReleaseMode.stop), 'release mode');
        return p;
      });
      player.play(AssetSource(asset), volume: 1.0).catchError((Object e) {
        debugPrint('[Feel] $asset unavailable: $e');
        // First failure for this element: fall back to neutral's clip
        // immediately rather than leaving this hit silent. `.add` returns
        // false on a repeat, so a broken neutral clip can't recurse forever.
        if (element != CreatureElement.neutral &&
            _missingAttackClip.add(element)) {
          attackSound(element);
        }
      });
    } catch (e) {
      debugPrint('[Feel] could not play $asset: $e');
    }
  }

  // ── Battle music (user 2026-08-29) ────────────────────────────
  // "Hier die Musik einfügen für den Battle screen als Loop." One long track
  // for the length of a battle. mediaPlayer mode (the default), not
  // lowLatency — that mode is built for short one-shot cues, not a streamed
  // loop — with ReleaseMode.loop so it repeats without a gap. Ducked to half
  // volume so it sits under the attack/hit cues above rather than fighting
  // them; those keep playing at full volume.
  static AudioPlayer? _musicPlayer;

  /// Starts the battle theme looping. Safe to call again while it's already
  /// playing (a no-op, since the source doesn't change). Call from
  /// battle_screen when a fight begins.
  static void startBattleMusic() {
    if (!_soundOn) return;
    if (kIsWeb == false && _muteForTests) return;
    try {
      final player = _musicPlayer ??= AudioPlayer();
      _fireAndForget(
        player.setReleaseMode(ReleaseMode.loop),
        'music release mode',
      );
      _fireAndForget(
        player.play(AssetSource('music/battle_theme.mp3'), volume: 0.5),
        'battle music',
      );
    } catch (e) {
      debugPrint('[Feel] could not play battle music: $e');
    }
  }

  /// Stops the battle theme. Call when the battle screen closes (win, loss,
  /// flee, or the player navigating away) — a loop left running is the one
  /// sound bug a player cannot miss.
  static void stopBattleMusic() {
    final player = _musicPlayer;
    if (player == null) return;
    _fireAndForget(player.stop(), 'stop battle music');
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
