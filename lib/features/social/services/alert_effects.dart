import 'package:flutter/widgets.dart';

import '../../../core/notifications/game_notifications.dart';
import '../../../core/ui/feel.dart';

/// What accompanies a banner: the alert sound and buzz (which the mute switch in
/// the header silences like every other cue), and — when the app is out of
/// sight — a system notification, so somebody who minimised the lobby and went
/// to another app still hears about it.
///
/// The system notification reaches a process the OS has not killed yet. For a
/// closed app it would take a push service (Firebase and a server trigger),
/// which this does not pretend to be.
void announceSocial({
  required String key,
  required String title,
  required String body,
}) {
  Feel.alert();
  final state = WidgetsBinding.instance.lifecycleState;
  // Null means no lifecycle has been reported yet (a test, or the very first
  // frame): the app is in front.
  if (state != null && state != AppLifecycleState.resumed) {
    GameNotifications.showNow(
      kind: NotifyKind.social,
      key: key,
      title: title,
      body: body,
    );
  }
}
