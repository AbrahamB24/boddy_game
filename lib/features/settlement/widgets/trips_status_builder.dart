import 'dart:async';

import 'package:flutter/material.dart';

import '../../creatures/services/expedition_controller.dart';

/// What the header's Trips cell needs to know about the expeditions right now.
class TripsStatus {
  /// Expeditions and caravans still away.
  final int out;

  /// Trips that are home but owe the player something to play (a capture hunt
  /// whose encounter has not been done yet).
  final int ready;

  /// Time until the first trip still away is back; null when none are.
  final Duration? soonest;

  /// No expedition seat exists at all (no Scout Post) — a different answer
  /// from "none out".
  final bool noSlots;

  const TripsStatus({
    required this.out,
    required this.ready,
    required this.soonest,
    required this.noSlots,
  });
}

/// Rebuilds [builder] whenever the expeditions change, and once a second while
/// any are out — so a countdown in the header can tick without the whole
/// settlement screen rebuilding around it.
class TripsStatusBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, TripsStatus status) builder;

  const TripsStatusBuilder({super.key, required this.builder});

  @override
  State<TripsStatusBuilder> createState() => _TripsStatusBuilderState();
}

class _TripsStatusBuilderState extends State<TripsStatusBuilder> {
  final _trips = ExpeditionController();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _trips.addListener(_rebuild);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _trips.travelling().isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _trips.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final away = _trips.travelling(now);
    Duration? soonest;
    for (final e in away) {
      // A hunt runs on real steps now — it has no ETA to contribute here
      // (see Expedition.isStepGated).
      if (e.isStepGated) continue;
      final left = e.remaining(now);
      if (soonest == null || left < soonest) soonest = left;
    }
    return widget.builder(
      context,
      TripsStatus(
        out: away.length,
        ready: _trips.awaitingPlay.length,
        soonest: soonest,
        noSlots: _trips.noSlots && _trips.maxCaravanSlots <= 0,
      ),
    );
  }
}
