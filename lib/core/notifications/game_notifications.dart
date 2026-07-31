import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ── Being told when a timer lands (user 2026-07-30) ──────────
// "Finde in der gesamten App Verbesserungen zum Ui und UX, so dass es sich
// besser anfühlt, das Spiel zu spielen."
//
// Almost everything in this game finishes while the app is closed: expeditions,
// caravans, matings, incubations, crafts, treatments, construction. The IN-app
// half of that was already built — the bell with its badge, the welcome-back
// digest — but nothing ever reached out, so a two-hour hunt landed in silence
// and the game only got credit for it the next time the player happened to open
// it.
//
// Design rules, all of them about not becoming a nuisance:
//
//  • ONE notification per thing, scheduled at the moment it is started and
//    CANCELLED if it is collected early, sped up or thrown away. A promise that
//    fires after the player already dealt with it is worse than none.
//  • Ids are DERIVED from the thing's own id ([_idFor]), so re-scheduling the
//    same job replaces its notification instead of adding a second.
//  • Nothing here is awaited by gameplay and nothing throws: an unsupported
//    platform, a denied permission or a missing plugin must never break sending
//    an expedition.
//  • No permission prompt on launch. It is asked for the first time something is
//    actually scheduled — i.e. right after the player sent a party out, which is
//    the one moment the request explains itself.
class GameNotifications {
  GameNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _available = true;

  /// Channel per KIND of wait, so a player can silence trade runs and keep
  /// hunts (Android lets them do that per channel, and lumping everything into
  /// one channel makes that impossible).
  static const _channels = {
    NotifyKind.expedition: ('expeditions', 'Expeditions & hunts'),
    NotifyKind.caravan: ('caravans', 'Trade caravans'),
    NotifyKind.breeding: ('breeding', 'Breeding & hatching'),
    NotifyKind.crafting: ('crafting', 'Workshop'),
    NotifyKind.healing: ('healing', 'Healing Hut'),
    NotifyKind.building: ('building', 'Construction'),
  };

  static Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      // The zone database, then the DEVICE's zone. Without the second step
      // `tz.local` is UTC, and a reminder built from wall-clock components would
      // land hours out on iOS.
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
      } catch (e) {
        debugPrint('[GameNotifications] device timezone unknown, using UTC: $e');
      }
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // The app asks when it first schedules something, not at launch.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[GameNotifications] unavailable on this platform: $e');
      _available = false;
    }
  }

  /// Asks for permission the first time it matters. Returns false when the
  /// player said no (or the platform has no such concept) — callers ignore the
  /// answer, because a silent no-op is the correct outcome either way.
  static Future<bool> _ensurePermission() async {
    await _init();
    if (!_available) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e) {
      debugPrint('[GameNotifications] permission request failed: $e');
    }
    return false;
  }

  /// A stable, collision-free notification id for [key] within [kind].
  ///
  /// Hashing rather than a counter: the same job must map to the same id across
  /// app restarts, or an early collect could not cancel a notification scheduled
  /// in a previous session.
  static int _idFor(NotifyKind kind, String key) {
    final h = '${kind.name}:$key'.hashCode;
    // Android ids are 32-bit signed; keep it positive and out of 0.
    return (h & 0x7fffffff) | 1;
  }

  /// Promises to tell the player at [at] that [title] happened.
  ///
  /// A time already past is DROPPED rather than fired immediately: those are the
  /// resolve-on-load cases, which the digest and the bell already cover.
  static Future<void> schedule({
    required NotifyKind kind,
    required String key,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!at.isAfter(DateTime.now())) return;
    if (!await _ensurePermission()) return;
    final (channelId, channelName) = _channels[kind]!;
    try {
      await _plugin.zonedSchedule(
        _idFor(kind, key),
        title,
        body,
        _localTimeOf(at),
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      // Exact-alarm permission, a full schedule table, an OEM restriction —
      // none of them are the player's problem mid-action.
      debugPrint('[GameNotifications] schedule failed: $e');
    }
  }

  /// Takes back the promise for [key] — collected early, sped up, cancelled.
  static Future<void> cancel(NotifyKind kind, String key) async {
    await _init();
    if (!_available) return;
    try {
      await _plugin.cancel(_idFor(kind, key));
    } catch (e) {
      debugPrint('[GameNotifications] cancel failed: $e');
    }
  }

  /// Drops every pending promise — used when a save is reset, so a fresh game is
  /// not haunted by the old one's timers.
  static Future<void> cancelAll() async {
    await _init();
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('[GameNotifications] cancelAll failed: $e');
    }
  }
}

/// What kind of wait finished — one Android channel each, so a player can
/// silence the chatty ones and keep the rest.
enum NotifyKind { expedition, caravan, breeding, crafting, healing, building }

/// `zonedSchedule` works in a named zone, so an absolute instant has to be
/// re-expressed in the device's own — see [GameNotifications._init].
tz.TZDateTime _localTimeOf(DateTime at) => tz.TZDateTime.from(at, tz.local);
