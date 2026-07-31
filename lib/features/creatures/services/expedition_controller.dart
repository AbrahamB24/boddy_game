import '../../settlement/data/resource_icons.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/notifications/game_notifications.dart';

import '../../../core/supabase/supabase_client.dart';
import '../../common/events/game_events.dart';
import '../../onboarding/intro_flow.dart';
import '../../settlement/data/goods_definitions.dart' show kGoodsDefs;
import '../../settlement/services/daily_tasks.dart' show DailyTaskKind;
import '../../settlement/services/gold_economy.dart';
import '../../settlement/services/trade_caravan.dart';
import '../../settlement/settlement_controller.dart';
import '../models/area.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart' show CreatureStat, maxHuntOptionCount;
import '../models/creature_instance.dart';
import '../models/expedition.dart';
import '../models/spot_state.dart';
import 'capture_math.dart';
import 'creatures_controller.dart';
import 'expedition_risk.dart';
import 'expedition_service.dart';
import 'gather_math.dart';

// Singleton owning the running expeditions (Phase 3: gather), same
// ChangeNotifier + offline-resolution pattern as BreedingController. Sending an
// expedition locks its members out of battles/work (CreaturesController
// .expeditionIds); once the timer elapses the trip resolves — resources are
// credited, the mined spot is depleted and the members are freed. Resolution
// is idempotent and happens on load, so a trip that finished while the app was
// closed pays out on next launch.
//
// Requires supabase/migrations/0001_expeditions.sql. Loads are wrapped so a
// missing table degrades to "no expeditions" instead of crashing game load.
class ExpeditionController extends ChangeNotifier {
  static final ExpeditionController _instance = ExpeditionController._();
  factory ExpeditionController() => _instance;
  ExpeditionController._();

  final _svc = ExpeditionService();
  final _spotSvc = SpotStateService();
  final _rng = math.Random();

  List<Expedition> expeditions = [];
  Map<String, SpotState> spotStates = {};
  bool isLoading = false;
  bool _loadedOnce = false;

  /// One-line outcome messages, queued for a screen to surface as a snackbar.
  /// Drained by the reader so each is shown once.
  ///
  /// This is the "right now" channel and is deliberately separate from
  /// [GameEventLog], which is the "what happened while I was away" one — an
  /// expedition that resolved offline has no screen to snack at. Both are fed
  /// through [_emit] so they can never tell different stories.
  final List<String> _results = [];

  List<String> drainResults() {
    final out = List<String>.from(_results);
    _results.clear();
    return out;
  }

  /// THE one way an outcome leaves this controller: snackbar queue + event log.
  /// [at] = when it actually happened (a trip's endsAt) so an offline-resolved
  /// trip is timestamped to its finish, not to screen-open.
  void _emit(GameEventKind kind, String message, {DateTime? at}) {
    _results.add(message);
    GameEventLog().add(kind, message, at: at);
  }

  String? get _userId => supabase.auth.currentUser?.id;

  /// Expeditions still OUT — the ones whose timer has not elapsed.
  ///
  /// A capture hunt that is back but whose encounter has not been played yet is
  /// deliberately NOT one of them (user 2026-07-27: "wenn eine expedition
  /// beendet ist / bsp fangen und diese schon zurück ist, aber ich das
  /// minispiel noch nicht gemacht habe, soll der slot für die karawana trotzdem
  /// freigegeben werden"). The party is home; what is left is a pending
  /// encounter sitting at the settlement, and holding a travel slot for it
  /// stopped you sending anyone anywhere until you got round to playing it.
  List<Expedition> travelling([DateTime? now]) {
    final at = now ?? DateTime.now();
    return [
      for (final e in expeditions)
        if (!e.isFinished(at)) e,
    ];
  }

  /// Expeditions that are HOME but still owe the player something to do — in
  /// practice the capture hunts waiting for their encounter, since gather and
  /// trade resolve themselves the moment they land.
  List<Expedition> get awaitingPlay => [
    for (final e in expeditions)
      if (e.isFinished(DateTime.now())) e,
  ];

  /// A TRADE CARAVAN, not an expedition. The two share this table and this
  /// controller — a caravan is still a group of monsters away on a timer — but
  /// they are counted, capped and amplified apart (user 2026-07-29).
  static bool isCaravan(Expedition e) => e.type == ExpeditionType.trade;

  /// Expeditions on the road. Caravans are NOT in here: they have their own
  /// pool, so a trade run must not eat a hunt's seat.
  int get activeCount => travelling().where((e) => !isCaravan(e)).length;

  /// Caravans on the road.
  int get caravanCount => travelling().where(isCaravan).length;

  /// How many timed expeditions may run at once: the base, plus whatever the
  /// settlement's buildings grant through their per-era `expeditionSlots`
  /// effects — the Scout Post (user 2026-07-26).
  int get maxSlots =>
      kBaseExpeditionSlots + SettlementController().buildingExpeditionSlots;

  /// The caravan pool's ceiling — the base plus the Caravanserai's
  /// `caravanSlots` effect.
  int get maxCaravanSlots =>
      kBaseCaravanSlots + SettlementController().buildingCaravanSlots;

  bool get slotsFull => activeCount >= maxSlots;

  /// NO seat exists at all — no Scout Post, or one whose authored
  /// `expeditionSlots` add up to nothing (user 2026-07-29: "ohne scout post
  /// darf keine expedition möglich sein").
  ///
  /// Its own state because it is a different answer from [slotsFull]: "every
  /// slot is busy, recall one" is advice you can act on, and printing it at
  /// 0/0 would send the player looking for a party that does not exist.
  bool get noSlots => maxSlots <= 0;

  /// Why an expedition can't go out right now, or null when a seat is free.
  String? get slotBlockReason => noSlots
      ? 'No expedition slots. A Scout Post is what grants them — build one, '
          'or level it up.'
      : slotsFull
          ? 'All expedition slots are busy ($activeCount/$maxSlots).'
          : null;

  bool get caravansFull => caravanCount >= maxCaravanSlots;

  Future<void> load({bool force = false}) async {
    if (isLoading || (_loadedOnce && !force)) return;
    final userId = _userId;
    if (userId == null) return;
    isLoading = true;
    try {
      expeditions = await _svc.loadActive(userId);
      spotStates = await _spotSvc.loadOwn(userId);
      _loadedOnce = true;
    } catch (e) {
      // Table not migrated yet (or offline) — treat as no expeditions so the
      // rest of the game still loads.
      debugPrint('[ExpeditionController] load failed: $e');
      expeditions = [];
      spotStates = {};
    }
    // Never let lock-sync or offline resolution bubble up — this runs on the
    // settlement load path and must not be able to break game startup.
    try {
      _syncLocks();
      await _resolveDue();
    } catch (e) {
      debugPrint('[ExpeditionController] resolve-on-load failed: $e');
    } finally {
      isLoading = false;
    }
    notifyListeners();
  }

  /// Rebuilds the creature expedition-lock set from the members who are still
  /// AWAY.
  ///
  /// A monster whose hunt has landed is free again even though its encounter is
  /// unplayed (user 2026-07-27) — it is standing in the settlement, so it can
  /// join a caravan or a battle team like anyone else. It used to stay locked
  /// until the mini-game was played, which meant an unopened encounter quietly
  /// impounded the party that went on it.
  ///
  /// The set is therefore TIME-DEPENDENT: whoever calls this decides the moment
  /// it is read for. [_resolveDue] re-runs it on every tick, load and collect,
  /// which is what makes the release land on its own.
  ///
  /// (A trip's casualties are still rolled when its encounter ends, not on
  /// landing. A monster that was hurt on the hunt therefore learns about it
  /// when you play the find — possibly while it is already out on a caravan.
  /// That is the honest reading: the wound happened out there, you just heard
  /// about it late.)
  void _syncLocks() {
    CreaturesController().expeditionIds
      ..clear()
      ..addAll(travelling().expand((e) => e.memberIds));
    CreaturesController().notifyListeners();
  }

  /// Live-regenerated stock of a spot right now.
  double availableStock(ResourceSpotDef def) {
    final now = DateTime.now();
    final state = spotStates[def.id] ?? SpotState.full(def, now);
    return state.currentStock(def, now);
  }

  /// Projects a gather trip without committing it (for the planner UI).
  /// Settlement amplifiers (warehouse carry, scout-post travel) are read HERE
  /// so plan and send always agree with the live building roster.
  GatherPlan preview({
    required AreaDef area,
    required ResourceSpotDef spot,
    required List<CreatureInstance> members,
  }) {
    final bonuses = SettlementController().expeditionBonuses;
    return planGather(
      area: area,
      spot: spot,
      members: members,
      availableStock: availableStock(spot),
      timeScale: _timeScale,
      carryMult: bonuses.carryMult,
      travelMult: bonuses.travelMult,
    );
  }

  /// The jumpstart's trip-time multiplier while the intro chain runs (1.0
  /// otherwise). Read at send time, so a trip already under way keeps the
  /// duration it was promised even if the intro ends mid-flight.
  double get _timeScale =>
      jumpstartTimeScale(SettlementController().jumpstartActive);

  /// Sends a gather expedition. Returns null on success or a user-facing error.

  // ── "The same again" (user 2026-07-30) ──────────────────────
  // Sending a party is the most repeated action in the game and it was a fresh
  // decision every single time: open the roster, hunt for the same three
  // monsters, tap each one. Nothing remembered that you had just done exactly
  // this.
  //
  // Kept in memory rather than persisted on purpose: it is a convenience for the
  // session you are in, and a "last party" restored from a week ago — half of it
  // K.O., stationed or already out — would be a list of monsters that cannot go.

  /// Ids of the last party sent, per trip type. Read by the launch sheet's
  /// "Same as last time" shortcut; whoever is no longer free is simply skipped.
  final Map<ExpeditionType, List<String>> lastParty = {};

  void _rememberParty(ExpeditionType type, List<String> memberIds) {
    if (memberIds.isEmpty) return;
    lastParty[type] = List.of(memberIds);
  }

  // ── Telling the player when it lands (user 2026-07-30) ──────
  // A trip is the longest wait in the game (up to 24 h) and it resolves while the
  // app is closed. The bell and the welcome-back digest cover the RETURN; this is
  // what gets the player to come back for it.

  /// Promises a notification for [e]'s arrival. Fire-and-forget — nothing about
  /// sending a party may depend on it.
  void _promiseArrival(Expedition e) {
    if (!e.type.isTimed) return;
    final (kind, title, body) = switch (e.type) {
      ExpeditionType.trade => (
        NotifyKind.caravan,
        '🐎 Caravan home',
        'Your trade run has arrived — the goods are waiting.',
      ),
      ExpeditionType.capture => (
        NotifyKind.expedition,
        '🪤 Hunt over',
        'Your hunters are back with what they found.',
      ),
      _ => (
        NotifyKind.expedition,
        '⛏️ Expedition back',
        'Your party has returned with its load.',
      ),
    };
    unawaited(GameNotifications.schedule(
      kind: kind,
      key: e.id,
      at: e.endsAt,
      title: title,
      body: body,
    ));
  }

  /// Takes the promise back — collected, resolved offline, or hurried with gold.
  void _cancelArrival(Expedition e) {
    unawaited(GameNotifications.cancel(
      e.type == ExpeditionType.trade
          ? NotifyKind.caravan
          : NotifyKind.expedition,
      e.id,
    ));
  }

  Future<String?> startGather({
    required AreaDef area,
    required ResourceSpotDef spot,
    required List<CreatureInstance> members,
  }) async {
    final userId = _userId;
    if (userId == null) return 'Not logged in.';
    // NOTHING RUNS ON AN EMPTY TANK (user 2026-07-27) — expeditions included.
    if (!SettlementController().hasEnergy) {
      return SettlementController.kNoEnergyMessage;
    }
    if (slotBlockReason != null) return slotBlockReason;
    if (members.isEmpty) return 'Pick at least one creature.';
    final creatures = CreaturesController();
    if (members.length > creatures.teamSizeCap) {
      return 'Your team holds ${creatures.teamSizeCap} — research team size '
          'to bring more.';
    }
    for (final c in members) {
      // Stationed creatures are fair game — their building just goes quiet
      // while they're out (see availableForExpedition).
      if (c.isKo ||
          c.isHealing ||
          creatures.isBreeding(c.id) ||
          creatures.isOnExpedition(c.id)) {
        return '${c.displayName} is not available.';
      }
    }
    final plan = preview(area: area, spot: spot, members: members);
    if (!plan.isViable) {
      return 'This group can\'t gather ${spot.resource} here — no '
          '${CreatureStat.gathering.label} skill or the spot is empty.';
    }

    final expedition = Expedition(
      id: '',
      userId: userId,
      type: ExpeditionType.gather,
      areaId: area.id,
      targetId: spot.id,
      memberIds: members.map((c) => c.id).toList(),
      startedAt: DateTime.now(),
      duration: plan.duration,
      payload: {
        'resource': spot.resource,
        'amount': plan.amount,
      },
    );

    try {
      final created = await _svc.insert(expedition);
      expeditions.add(created);
      _rememberParty(created.type, created.memberIds);
      _promiseArrival(created);
      _syncLocks();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Failed to start expedition: $e';
    }
  }

  /// Sends a capture expedition. [finds] picks the hunt length (see
  /// kCaptureHuntOptions) — every find is rolled NOW from the area's pool
  /// (rarity odds shift with the area's danger) and stored hidden in the
  /// payload; the player learns them one by one as the encounters open.
  /// Returns null on success or a user-facing error.
  /// Starts a hunt. [option] is the chosen variant (10 min … 24 h); the
  /// number of [members] must match its exact hunter count — the variant IS
  /// the team size (user design 2026-07-17), so a longer/rarer hunt is gated
  /// by simply owning enough ready monsters, not by tech.
  Future<String?> startCapture({
    required AreaDef area,
    required List<CreatureInstance> members,
    required CaptureHuntOption option,
  }) async {
    final userId = _userId;
    if (userId == null) return 'Not logged in.';
    if (!SettlementController().hasEnergy) {
      return SettlementController.kNoEnergyMessage;
    }
    if (slotBlockReason != null) return slotBlockReason;
    if (members.length != option.hunters) {
      return 'The ${option.label} hunt needs exactly ${option.hunters} '
          'hunter${option.hunters > 1 ? 's' : ''}.';
    }
    // Scouting gate (user 2026-07-26: "jagdt an scout"): longer variants are
    // opened by the settlement's `huntOptions` — the Scout Post and its level —
    // on top of the hunter-count requirement.
    final optionIndex = kCaptureHuntOptions.indexOf(option);
    if (optionIndex >=
        maxHuntOptionCount(SettlementController().buildingHuntOptions)) {
      return 'Build or upgrade a Scout Post to scout longer hunts.';
    }
    final creatures = CreaturesController();
    for (final c in members) {
      // Stationed creatures are fair game — see availableForExpedition.
      if (c.isKo ||
          c.isHealing ||
          creatures.isBreeding(c.id) ||
          creatures.isOnExpedition(c.id)) {
        return '${c.displayName} is not available.';
      }
    }
    // EVERY species is in the pool (user 2026-07-27) — the area supplies the
    // danger the rarity odds are read from, not a guest list. Only the
    // legendaries are gated, and only by having been beaten.
    final stage = SettlementController().dungeonMaxStage;
    final rolled = <String>[
      for (var i = 0; i < option.finds; i++)
        if (rollEncounter(
              area,
              _rng,
              dungeonMaxStage: stage,
              rareBias: option.rareBias,
            )
            case final found?)
          found.id,
    ];
    if (rolled.isEmpty) {
      return 'Nothing lives here yet — define species in Dev Mode first.';
    }

    // Scout posts speed the whole hunt (the trip IS mostly travel): the same
    // travelMult that cuts gather travel scales the capture duration.
    var duration = captureDuration(
      option,
      timeScale: _timeScale * SettlementController().expeditionBonuses.travelMult,
    );
    // Tutorial: even jumpstart-scaled, a hunt is ~40s of dead waiting — the
    // guided catch should be playable the moment the player checks Trips.
    if (SettlementController().introStep.isActive &&
        duration.inSeconds > kIntroMaxTripSeconds) {
      duration = const Duration(seconds: kIntroMaxTripSeconds);
    }

    final expedition = Expedition(
      id: '',
      userId: userId,
      type: ExpeditionType.capture,
      areaId: area.id,
      memberIds: members.map((c) => c.id).toList(),
      startedAt: DateTime.now(),
      duration: duration,
      payload: {
        'speciesIds': rolled,
        'level': captureTargetLevel(area),
        'done': 0,
      },
    );

    try {
      final created = await _svc.insert(expedition);
      expeditions.add(created);
      _rememberParty(created.type, created.memberIds);
      _promiseArrival(created);
      _syncLocks();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Failed to start expedition: $e';
    }
  }

  // ── Trade caravans (user 2026-07-26) ────────────────────────
  /// Sends a trade out as a CARAVAN instead of settling it over the counter.
  ///
  /// The cargo ([from] × [amountFrom]) is paid in HERE, at send: the goods
  /// leave the storehouse with the caravan. What it brings back ([to] ×
  /// [amountTo]) is priced HERE too, at the rate the Trade Center offered when
  /// the player accepted it, and lands only when the trip resolves. Pricing
  /// mid-flight would mean a caravan silently renegotiating on the road.
  ///
  /// Returns null on success or a user-facing error.
  Future<String?> startTrade({
    required List<CreatureInstance> members,
    required String from,
    required double amountFrom,
    required String to,
    required double amountTo,
  }) async {
    final userId = _userId;
    if (userId == null) return 'Not logged in.';
    if (!SettlementController().hasEnergy) {
      return SettlementController.kNoEnergyMessage;
    }
    if (caravansFull) {
      return 'Every caravan is on the road '
          '($caravanCount/$maxCaravanSlots).';
    }
    if (!caravanCanHaul(members)) {
      return 'Pick at least one creature that can carry something.';
    }
    final creatures = CreaturesController();
    if (members.length > creatures.teamSizeCap) {
      return 'Your caravan holds ${creatures.teamSizeCap} — research team size '
          'to bring more.';
    }
    for (final c in members) {
      if (c.isKo ||
          c.isHealing ||
          creatures.isBreeding(c.id) ||
          creatures.isOnExpedition(c.id)) {
        return '${c.displayName} is not available.';
      }
    }
    if (amountFrom <= 0 || amountTo <= 0) return 'Nothing to trade.';
    final settlement = SettlementController();
    final capacity = tradeCapacity(
      from,
      members,
      carryMult: settlement.caravanBonuses.carryMult,
    );
    if (amountFrom > capacity) {
      return 'That is more than the caravan can haul '
          '(${capacity.floor()} $from).';
    }
    // Cargo out FIRST: if the storehouse can't cover it there is no trip, and
    // no way for a failed insert below to have spent it for nothing.
    if (!await settlement.spendResources({from: amountFrom})) {
      return 'Not enough $from.';
    }

    final expedition = Expedition(
      id: '',
      userId: userId,
      type: ExpeditionType.trade,
      areaId: kTradeRouteAreaId,
      memberIds: members.map((c) => c.id).toList(),
      startedAt: DateTime.now(),
      duration: tradeTripDuration(
        members,
        travelMult: settlement.caravanBonuses.travelMult,
        timeScale: _timeScale,
      ),
      payload: {
        'from': from,
        'amountFrom': amountFrom,
        'to': to,
        'amountTo': amountTo,
      },
    );

    try {
      final created = await _svc.insert(expedition);
      expeditions.add(created);
      _rememberParty(created.type, created.memberIds);
      _promiseArrival(created);
      _syncLocks();
      notifyListeners();
      return null;
    } catch (e) {
      // Put the cargo back — it left the storehouse a moment ago and the trip
      // it was loaded onto does not exist.
      await settlement.grantResources({from: amountFrom});
      return 'Failed to send the caravan: $e';
    }
  }

  /// Pays out a returned caravan. The cargo was already spent at send, so this
  /// only grants — which also makes it safe to run twice (the row is deleted
  /// in [_finishTrip], and resolution only ever runs for rows still present).
  Future<void> _resolveTrade(Expedition e) async {
    final to = e.payload['to'] as String?;
    final amount = (e.payload['amountTo'] as num?)?.toDouble() ?? 0;
    if (to != null && amount > 0) {
      await SettlementController().grantResources({to: amount});
      _emit(
        GameEventKind.expedition,
        '${ExpeditionType.trade.emoji} The caravan is back: '
        '${resourceEmoji(to)} ${amount.toStringAsFixed(0)} $to',
        at: e.endsAt,
      );
    }
    await _finishTrip(e, at: e.endsAt);
  }

  // ── Capture encounter bookkeeping (multi-find hunts) ────────
  /// Credits one caught wild immediately (housing permitting) and queues the
  /// result line. Called per find, mid-hunt — the trip itself keeps going.
  Future<void> recordCatch(Combatant wild) async {
    final kept = await CreaturesController().captureWild(wild);
    _emit(
      GameEventKind.caught,
      kept != null
          ? 'Caught ${kept.displayName}! (Lv ${kept.level})'
          : '${wild.name} was caught, but there was no room to house it.',
    );
    if (kept != null) {
      // Party size is now a rule of position on the linear path (the first five
      // battles are always 1v1), so there is no early "second slot" to hand out
      // on the first catch any more — the second monster arrives at battle 6.
      await SettlementController().advanceIntro(IntroStep.firstCapture);
    }
  }

  /// Queues a result line (escapes, defeated finds, cold trails).
  void logResult(String message) => _emit(GameEventKind.caught, message);

  /// Checkpoints that one more find has been played — persisted immediately
  /// so leaving/reopening the encounter can never replay (or double-credit)
  /// a find. Returns the updated expedition.
  Future<Expedition> advanceCaptureFind(Expedition e) async {
    final idx = expeditions.indexWhere((x) => x.id == e.id);
    final current = idx >= 0 ? expeditions[idx] : e;
    final updated = current.copyWith(
      payload: {...current.payload, 'done': current.captureFindsDone + 1},
    );
    if (idx >= 0) expeditions[idx] = updated;
    notifyListeners();
    try {
      await _svc.update(updated);
    } catch (err) {
      debugPrint('[ExpeditionController] advance persist failed: $err');
    }
    return updated;
  }

  /// Ends the whole hunt once every find is played (or forfeited): rolls trip
  /// casualties, frees the members and removes the expedition. [note] adds a
  /// closing line (defeated group, fled, cold trail).
  Future<void> finishCaptureTrip(Expedition e, {String? note}) async {
    if (note != null) _emit(GameEventKind.expedition, note);
    await _finishTrip(e);
  }

  /// Shared tail of every resolved trip: casualties, lock release, row delete.
  /// [casualties] can be passed in when the caller already rolled them (gather
  /// needs them early for the loot penalty); otherwise they're rolled here.
  /// [at] timestamps the casualty events to the trip's finish (offline gather);
  /// omit for a live capture finish, where "now" is correct.
  Future<void> _finishTrip(
    Expedition e, {
    List<Casualty>? casualties,
    DateTime? at,
  }) async {
    // The trip is over, however it got here (collected, resolved on load, or
    // hurried with gold) — so the promise about its arrival is spent.
    _cancelArrival(e);
    final creatures = CreaturesController();
    final area = areaById(e.areaId);
    final members = e.memberIds
        .map(creatures.byId)
        .whereType<CreatureInstance>()
        .toList();
    casualties ??= area == null
        ? const <Casualty>[]
        : rollCasualties(area.dangerLevel, members, _rng);
    if (casualties.isNotEmpty) {
      await creatures.applyExpeditionCasualties(casualties);
      for (final cas in casualties) {
        final name = creatures.byId(cas.creatureId)?.displayName ?? 'A creature';
        _emit(
          GameEventKind.casualty,
          cas.ko
              ? '$name was knocked out on the expedition!'
              : '$name came back wounded.',
          at: at,
        );
      }
    }
    expeditions.removeWhere((x) => x.id == e.id);
    _syncLocks();
    notifyListeners();
    try {
      await _svc.delete(e.id);
    } catch (err) {
      debugPrint('[ExpeditionController] delete failed: $err');
    }
  }

  /// Resolves every GATHER and TRADE expedition whose timer has elapsed —
  /// both pay out on their own, offline included. Capture expeditions never
  /// auto-resolve: their encounter is played by hand and simply waits
  /// (occupying its slot) until the player opens it.
  Future<void> _resolveDue() async {
    final now = DateTime.now();
    final due = expeditions
        .where(
          (e) =>
              (e.type == ExpeditionType.gather ||
                  e.type == ExpeditionType.trade) &&
              e.isReadyToCollect(now),
        )
        .toList();
    for (final e in due) {
      if (e.type == ExpeditionType.trade) {
        await _resolveTrade(e);
      } else {
        await _resolve(e);
      }
    }
    // A hunt that landed while nothing else happened frees its party HERE: the
    // lock set is time-dependent (see _syncLocks) and nothing else would notice
    // the boundary being crossed. Cheap, and this is the one method every
    // screen's tick already runs.
    _syncLocks();
  }

  /// Public entry so a screen can pull rewards forward when it opens.
  Future<void> collectFinished() async {
    await _resolveDue();
    notifyListeners();
  }

  /// Resolves a finished GATHER trip: casualties can cost part of the haul in
  /// transit, the spot still loses everything that was mined.
  Future<void> _resolve(Expedition e) async {
    final userId = _userId;
    if (userId == null) return;

    final creatures = CreaturesController();
    final area = areaById(e.areaId);
    final members = e.memberIds
        .map(creatures.byId)
        .whereType<CreatureInstance>()
        .toList();
    // Rolled up front — the loot penalty needs them before granting.
    final casualties = area == null
        ? const <Casualty>[]
        : rollCasualties(area.dangerLevel, members, _rng);

    final resource = e.payload['resource'] as String?;
    final amount = (e.payload['amount'] as num?)?.toDouble() ?? 0;
    if (resource != null && amount > 0) {
      // Smokehouses boost GOODS hauls (fish/fur — the dungeon-entry currency),
      // applied at homecoming: the spot still only loses what was mined.
      final goodsMult = kGoodsDefs.containsKey(resource)
          ? SettlementController().expeditionBonuses.goodsMult
          : 1.0;
      final granted = amount * goodsMult * (1 - lootPenalty(casualties));
      await SettlementController().grantResources({resource: granted});
      // Daily-task hooks: a trip came home, possibly hauling wood.
      SettlementController().reportDailyProgress(DailyTaskKind.gatherTrips);
      if (resource == 'wood') {
        SettlementController()
            .reportDailyProgress(DailyTaskKind.haulWood, granted.round());
      }
      // A gather trip used to land in complete silence: the resources simply
      // appeared, and a trip that resolved offline was never mentioned at all.
      _emit(
        GameEventKind.expedition,
        '${resourceEmoji(resource)} ${granted.toStringAsFixed(0)} '
        '$resource from ${areaById(e.areaId)?.name ?? e.areaId}',
        at: e.endsAt,
      );
      final def = e.targetId == null ? null : findSpot(e.targetId!);
      if (def != null) {
        final now = DateTime.now();
        final state = spotStates[def.id] ?? SpotState.full(def, now);
        final next = state.afterMining(def, amount, now);
        spotStates[def.id] = next;
        try {
          await _spotSvc.upsert(userId, next);
        } catch (err) {
          debugPrint('[ExpeditionController] spot persist failed: $err');
        }
      }
    }

    await _finishTrip(e, casualties: casualties, at: e.endsAt);
  }

  /// Recalls an expedition early — frees the members, no rewards.
  ///
  /// A recalled CARAVAN turns around with its load: the cargo was paid in at
  /// send, so keeping it would make "recall" a way to destroy your own goods
  /// (user-facing trap). Only the trade it was going to make is lost.
  Future<void> cancel(Expedition e) async {
    if (e.type == ExpeditionType.trade) {
      final from = e.payload['from'] as String?;
      final amount = (e.payload['amountFrom'] as num?)?.toDouble() ?? 0;
      if (from != null && amount > 0) {
        await SettlementController().grantResources({from: amount});
      }
    }
    expeditions.removeWhere((x) => x.id == e.id);
    _syncLocks();
    notifyListeners();
    try {
      await _svc.delete(e.id);
    } catch (err) {
      debugPrint('[ExpeditionController] cancel failed: $err');
    }
  }

  /// Dev-mode shortcut: finish a running expedition immediately, then resolve.
  Future<void> devFinishNow(Expedition e) async {
    try {
      await _svc.finishNow(e.id);
    } catch (err) {
      debugPrint('[ExpeditionController] devFinishNow failed: $err');
    }
    await load(force: true);
  }

  // ── Gold: bring a trip home now ─────────────────────────────
  /// Gold to end [e]'s travel immediately. 0 once it's already back.
  int goldSkipCost(Expedition e) =>
      goldToSkip(e.endsAt.difference(DateTime.now()));

  /// Pays gold to bring [e] home now. Returns null on success or a
  /// user-facing error.
  ///
  /// Note this only ends the TRAVEL. A capture hunt still has to be played by
  /// hand afterwards — gold buys time, never a result.
  Future<String?> skipWithGold(Expedition e) async {
    final cost = goldSkipCost(e);
    if (cost <= 0) return 'It is already back.';
    final settlement = SettlementController();
    if (!await settlement.spendResources({'gold': cost.toDouble()})) {
      return 'Not enough gold (need $cost, have ${settlement.gold.toInt()}).';
    }
    try {
      await _svc.finishNow(e.id);
    } catch (err) {
      debugPrint('[ExpeditionController] skipWithGold failed: $err');
      return 'Could not reach the expedition — try again.';
    }
    await load(force: true);
    // Gather trips resolve on their own; a capture waits to be played.
    await _resolveDue();
    notifyListeners();
    return null;
  }
}
