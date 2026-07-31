import 'package:flutter/material.dart';

import '../../../core/tuning/game_tuning.dart';

// One expedition sent out from the settlement onto the overworld — the core
// of the new away-mission system (see [[expedition-overworld-redesign]]).
//
// A group of the player's creatures (locked via CreatureInstance
// .assignedExpeditionId while away) is sent to an overworld area for one of
// three purposes:
//   • gather  — mine a resource spot; group Abbauwert (Σ gather stat) = speed,
//               group carry (Σ carry stat) = load cap per trip. Idle/timed.
//   • capture — weaken-then-catch a wild species; Σ catchRate = base chance,
//               fighters weaken the target. Idle/timed, optional intervention.
//   • battle  — fight/boss node, played actively via the CTB battle engine.
//
// gather/capture resolve on a real-time timer (offline-capable, like breeding);
// battle opens the interactive battle screen instead. This model is the shared
// record for all three — type-specific inputs/outputs live in [payload].
// ── Slots ───────────────────────────────────────────────────
// How many timed expeditions can run at once WITHOUT any building — ZERO since
// 2026-07-29 (user: "ohne scout post darf keine expedition möglich sein, d.h
// nur was ich beim dev menü bei scout post einstelle gilt zu den anzahl
// möglichen Expeditionen").
//
// It was 2, and those two seats were the last hardcoded grant in the expedition
// system: a settlement with no Scout Post could still send parties out, so the
// building the whole system is supposed to hang off (user 2026-07-26:
// "Expeditionen werden an scout geknüpft") was optional in practice, and no
// number in Dev Mode could take those two seats away.
//
// The Scout Post's per-level `expeditionSlots` effect is now the WHOLE supply —
// summed by SettlementController.buildingExpeditionSlots. Kept as a named
// constant rather than deleted so the seat count still has one place to be
// read from, and so the Dev-Mode "on top of the settlement's own N" note keeps
// telling the truth on its own.
// A DIAL since 2026-07-29 (Settlement → Slots ohne Gebäude): 0 is the decision,
// not the mechanism, and the decision is the author's to revisit.
int get kBaseExpeditionSlots => GameTuning.i.count(Dials.baseExpeditionSlots);

/// How many trade CARAVANS can be on the road at once, before buildings.
///
/// A separate pool from [kBaseExpeditionSlots] (user 2026-07-29: "unterscheide
/// expeditions und karawanen für den Markt"). They were one number, which meant
/// sending a load of wood to market cost you a hunt — two activities with
/// nothing to do with each other, competing for the same seats. Buildings top
/// each pool up separately too: the Scout Post grants `expeditionSlots`, the
/// Caravanserai `caravanSlots`.
int get kBaseCaravanSlots => GameTuning.i.count(Dials.baseCaravanSlots);

/// The [Expedition.areaId] a trade caravan carries. A caravan travels a trade
/// ROUTE, not an overworld area (user 2026-07-26: no destination is picked),
/// but the column is required and everything downstream keys off it — and
/// `areaById` returning null for it is exactly right: no area means no danger
/// level, so a caravan rolls no casualties.
const String kTradeRouteAreaId = 'trade_route';

enum ExpeditionType {
  gather('Gather', '⛏️'),
  capture('Capture', '🪤'),
  battle('Battle', '⚔️'),
  // A trade is a TRIP now (user 2026-07-26). Its cargo is paid in at send and
  // its return is paid out on arrival — see ExpeditionController.startTrade.
  trade('Trade', '🐎');

  final String label;
  final String emoji;
  const ExpeditionType(this.label, this.emoji);

  /// Idle/timed types resolve on a countdown; [battle] is played actively and
  /// carries no meaningful timer.
  bool get isTimed => this != ExpeditionType.battle;

  static ExpeditionType fromName(String? name) => ExpeditionType.values
      .firstWhere((t) => t.name == name, orElse: () => ExpeditionType.gather);
}

/// Lifecycle of a timed expedition. [active] = running; once the timer elapses
/// it is ready to collect (see [isReadyToCollect]); [collected] = its rewards
/// have been granted and its members released.
enum ExpeditionState {
  active,
  collected;

  static ExpeditionState fromName(String? name) => ExpeditionState.values
      .firstWhere((s) => s.name == name, orElse: () => ExpeditionState.active);
}

class Expedition {
  final String id; // uuid (DB-generated on insert)
  final String userId;
  final ExpeditionType type;

  /// The overworld area this expedition is in.
  final String areaId;

  /// The specific target within the area — a resource-spot id (gather), a
  /// wild-species id (capture) or a map-node id (battle). Null until chosen.
  final String? targetId;

  /// Ids of the creatures on this expedition (each has its
  /// [CreatureInstance.assignedExpeditionId] set to this expedition's id).
  final List<String> memberIds;

  final DateTime startedAt;

  /// Planned duration for timed expeditions; 0 for [ExpeditionType.battle].
  final Duration duration;

  ExpeditionState state;

  /// Type-specific inputs/outputs, e.g. gather {'resource':'wood',
  /// 'amount':120.0}, capture {'speciesId':.., 'level':..} (the hidden find,
  /// rolled at start — revealed when the encounter opens). Kept as a
  /// free-form jsonb bag so each type can evolve without a schema change.
  final Map<String, dynamic> payload;

  Expedition({
    required this.id,
    required this.userId,
    required this.type,
    required this.areaId,
    this.targetId,
    this.memberIds = const [],
    required this.startedAt,
    this.duration = Duration.zero,
    this.state = ExpeditionState.active,
    this.payload = const {},
  });

  /// Wall-clock time the timer completes (== startedAt for untimed battles).
  DateTime get endsAt => startedAt.add(duration);

  /// Time left until the timer elapses (never negative).
  Duration remaining(DateTime now) {
    final left = endsAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 0.0 → 1.0 timer progress (1.0 for zero-duration expeditions).
  double progress(DateTime now) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 1.0;
    final done = now.difference(startedAt).inMilliseconds;
    return (done / total).clamp(0.0, 1.0);
  }

  bool isFinished(DateTime now) => !now.isBefore(endsAt);

  /// A timed expedition whose timer has elapsed but whose rewards haven't been
  /// granted yet — the signal for the controller to resolve it.
  bool isReadyToCollect(DateTime now) =>
      type.isTimed && state == ExpeditionState.active && isFinished(now);

  // ── Capture payload helpers ─────────────────────────────────
  /// The hidden finds rolled at start (species ids, in encounter order).
  /// Legacy single-find rows ({'speciesId': ..}) read as one find.
  List<String> get captureFindSpeciesIds {
    final list = payload['speciesIds'];
    if (list is List) return list.map((e) => e as String).toList();
    final single = payload['speciesId'] as String?;
    return single == null ? const [] : [single];
  }

  /// How many of the finds have already been played (persisted after every
  /// encounter so re-opening never replays — or double-credits — one).
  int get captureFindsDone => (payload['done'] as num?)?.toInt() ?? 0;

  // ── Row mapping (future `expeditions` table) ───────────────
  factory Expedition.fromRow(Map<String, dynamic> row) => Expedition(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    type: ExpeditionType.fromName(row['type'] as String?),
    areaId: row['area_id'] as String,
    targetId: row['target_id'] as String?,
    memberIds: ((row['member_ids'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    startedAt: DateTime.parse(row['started_at'] as String),
    duration: Duration(seconds: (row['duration_seconds'] as num?)?.toInt() ?? 0),
    state: ExpeditionState.fromName(row['state'] as String?),
    payload: ((row['payload'] as Map?) ?? const {}).cast<String, dynamic>(),
  );

  /// Row for inserts/updates. `id` is omitted when empty so the DB generates
  /// the uuid on first insert.
  Map<String, dynamic> toRow() => {
    if (id.isNotEmpty) 'id': id,
    'user_id': userId,
    'type': type.name,
    'area_id': areaId,
    'target_id': targetId,
    'member_ids': memberIds,
    // ALWAYS UTC (user 2026-07-25: "8min57 in der Vorschau, 2h08 effektiv").
    // A local DateTime serialises WITHOUT a zone suffix, and Postgres reads a
    // zoneless string into `timestamptz` as UTC — so a CEST send was stored two
    // hours in the future and every countdown came back two hours too long.
    // toUtc() appends the 'Z' that makes the instant unambiguous.
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_seconds': duration.inSeconds,
    'state': state.name,
    'payload': payload,
  };

  Expedition copyWith({
    String? targetId,
    List<String>? memberIds,
    ExpeditionState? state,
    Map<String, dynamic>? payload,
  }) => Expedition(
    id: id,
    userId: userId,
    type: type,
    areaId: areaId,
    targetId: targetId ?? this.targetId,
    memberIds: memberIds ?? this.memberIds,
    startedAt: startedAt,
    duration: duration,
    state: state ?? this.state,
    payload: payload ?? this.payload,
  );
}

/// Convenience for tinting expedition chips/icons by purpose in the UI.
extension ExpeditionTypeColor on ExpeditionType {
  Color get color => switch (this) {
    ExpeditionType.gather => const Color(0xFF3BAE78),
    ExpeditionType.capture => const Color(0xFF018ABE),
    ExpeditionType.battle => const Color(0xFFE25822),
    ExpeditionType.trade => const Color(0xFFD4A017),
  };
}
