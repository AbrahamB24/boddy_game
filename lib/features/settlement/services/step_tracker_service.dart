import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/supabase/supabase_client.dart';
import '../settlement_controller.dart';

/// Where the automatic step sync currently stands — the energy sheet renders
/// this so the player knows whether steps are flowing in by themselves.
enum StepTrackerStatus {
  /// start() not called yet, or stopped.
  idle,

  /// No step sensor on this device/platform (web, desktop, sensorless phone).
  unavailable,

  /// The player denied the activity-recognition permission; a re-request can
  /// be triggered from the energy sheet.
  permissionDenied,

  /// Live: the hardware counter is being watched and steps auto-credit.
  active,
}

/// The REAL step counter (user 2026-07-18): reads the phone's hardware
/// step counter (Android TYPE_STEP_COUNTER via the pedometer plugin) and
/// credits new steps as energy through [SettlementController.addSteps].
///
/// The sensor reports CUMULATIVE steps since device boot and keeps counting
/// while the app is closed, so the service persists the last credited reading
/// (per user, locally — the baseline is device state, not game state) and on
/// every event credits only the delta. A reading below the baseline means the
/// device rebooted; the whole reading is then new steps.
class StepTrackerService extends ChangeNotifier {
  static final StepTrackerService _instance = StepTrackerService._();
  factory StepTrackerService() => _instance;
  StepTrackerService._();

  StepTrackerStatus _status = StepTrackerStatus.idle;
  StepTrackerStatus get status => _status;

  /// Steps credited by auto-sync since app start — surfaced in the energy
  /// sheet as feedback that the tracker is really doing something.
  int get sessionSteps => _sessionSteps;
  int _sessionSteps = 0;

  StreamSubscription<StepCount>? _sub;
  SharedPreferences? _prefs;

  // Steps seen but not yet pushed through addSteps (each flush is a Supabase
  // write, so tiny deltas are batched).
  int _pending = 0;
  Timer? _flushTimer;
  bool _flushing = false;

  static const _flushThreshold = 25; // steps
  static const _flushInterval = Duration(seconds: 45);

  String get _baselineKey {
    final uid = supabase.auth.currentUser?.id ?? 'anon';
    return 'step_baseline_$uid';
  }

  /// Starts watching the hardware counter. Safe to call repeatedly (e.g. on
  /// app resume) — it re-subscribes, which also forces a fresh reading so
  /// steps walked while the app was backgrounded credit immediately.
  Future<void> start() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      _setStatus(StepTrackerStatus.unavailable);
      return;
    }

    final permission = await Permission.activityRecognition.request();
    if (!permission.isGranted) {
      _setStatus(StepTrackerStatus.permissionDenied);
      return;
    }

    _prefs ??= await SharedPreferences.getInstance();

    await _sub?.cancel();
    _sub = Pedometer.stepCountStream.listen(
      _onReading,
      // Typical on emulators / devices without the sensor: the stream errors
      // instead of emitting.
      onError: (Object e) {
        debugPrint('[StepTracker] sensor unavailable: $e');
        _setStatus(StepTrackerStatus.unavailable);
      },
      cancelOnError: true,
    );

    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
    _setStatus(StepTrackerStatus.active);
  }

  /// Stops watching and pushes any buffered steps out.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
    _setStatus(StepTrackerStatus.idle);
  }

  void _onReading(StepCount event) {
    final prefs = _prefs;
    if (prefs == null) return;
    final reading = event.steps;
    final baseline = prefs.getInt(_baselineKey);

    if (baseline == null) {
      // First ever reading for this user on this device: steps before install
      // aren't earned in-game — just anchor the baseline.
      prefs.setInt(_baselineKey, reading);
      return;
    }

    // reading < baseline ⇒ the counter restarted (device reboot): everything
    // on it is new. Otherwise the delta since the last credited reading is.
    final delta = reading < baseline ? reading : reading - baseline;
    prefs.setInt(_baselineKey, reading);
    if (delta <= 0) return;

    _pending += delta;
    if (_pending >= _flushThreshold) _flush();
  }

  Future<void> _flush() async {
    if (_flushing || _pending == 0) return;
    _flushing = true;
    final credit = _pending;
    _pending = 0;
    try {
      await SettlementController().addSteps(credit);
      _sessionSteps += credit;
      notifyListeners();
    } catch (e) {
      // Credit failed (e.g. offline) — put the steps back for the next flush.
      _pending += credit;
      debugPrint('[StepTracker] flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  /// Opens the system app settings — the only way back once the player chose
  /// "don't ask again" on the permission dialog.
  Future<void> openPermissionSettings() => openAppSettings();

  void _setStatus(StepTrackerStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }
}
