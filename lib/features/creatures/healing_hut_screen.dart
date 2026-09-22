import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../settlement/data/goods_definitions.dart';
import '../settlement/settlement_controller.dart';
import '../social/widgets/social_kit.dart';
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';
import 'services/healing_cost.dart';
import 'widgets/creature_family.dart';
import 'widgets/slot_kit.dart';

/// The Healing Hut (user 2026-09-20, "Variante 2, Slot-Karten").
///
/// The places on top: every bed as a big card (the patient, a bar, the time
/// left, and a gold button to finish it now), free beds dashed, and the line as
/// small chips beside them. Under them everyone still hurt, as tiles with one
/// button each — worst off first — and "Heal all" at the head of that grid.
///
/// The rules are unchanged: the hut treats [SettlementController.healCapacity]
/// at once, the rest stand in a line capped by `healQueue`, and each pays its own
/// bill the moment its treatment actually starts.
class HealingHutScreen extends StatefulWidget {
  const HealingHutScreen({super.key});

  @override
  State<HealingHutScreen> createState() => _HealingHutScreenState();
}

class _HealingHutScreenState extends State<HealingHutScreen> {
  final _creatures = CreaturesController();
  final _ctrl = SettlementController();
  Timer? _ticker;

  /// The action in flight, or null.
  String? _busy;

  @override
  void initState() {
    super.initState();
    // Live countdowns; it also finishes a treatment that ran out while you were
    // standing here, pulls the next one in, and trims a line standing beyond
    // its capacity — so the page ticks whenever EITHER list has anybody in it.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_creatures.healingCreatures.isEmpty && _creatures.healQueue.isEmpty) {
        return;
      }
      _creatures.resolveFinishedHeals();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<CreatureInstance> get _inTreatment => _creatures.healingCreatures;

  /// Who is standing in line, in line order (migration 0029).
  List<CreatureInstance> get _queued => _creatures.healQueue;

  /// The wounded who are neither being treated nor queued, worst off first —
  /// the order the hut itself uses when a cap forces the choice, so the grid
  /// reads as "who needs it most".
  List<CreatureInstance> get _waiting {
    final list = _creatures.hurtCreatures
        .where((c) => !c.isHealing && !c.isQueuedForHealing)
        .toList();
    list.sort((a, b) {
      if (a.isKo != b.isKo) return a.isKo ? -1 : 1;
      return (b.maxHp - b.hp).compareTo(a.maxHp - a.hp);
    });
    return list;
  }

  /// What treating [c] alone costs, in the goods its own era is billed in.
  Map<String, double> _costOf(CreatureInstance c) => healCost(
    [c],
    _ctrl.resources?.asMap ?? const {},
    costMult: 1 - _ctrl.healReduction('cost'),
  );

  /// How long [c] will be out — the base wound time cut by the hut's healers.
  Duration _durationOf(CreatureInstance c) =>
      healDuration(c) * (1 - _ctrl.healReduction('speed'));

  /// Free treatment slots, or null when the hut has no cap authored.
  int? get _freeSlots {
    final cap = _ctrl.healCapacity;
    return cap == null ? null : cap - _inTreatment.length;
  }

  /// Free places in the line, or null when the waiting room is uncapped.
  int? get _freeQueue => _creatures.freeHealQueueSlots;

  static String _goodsLabel(Map<String, double> cost) => cost.entries
      .map((e) => '${kGoodsDefs[e.key]?.emoji ?? e.key} ${e.value.toInt()}')
      .join(' ');

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _run(String key, Future<String?> Function() action) async {
    setState(() => _busy = key);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) context.snack(err, error: true);
  }

  static String _hp(CreatureInstance c) =>
      c.isKo ? 'K.O. · HP 0/${c.maxHp}' : 'HP ${c.hp}/${c.maxHp}';

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_creatures, _ctrl]),
    builder: (context, _) {
      final treating = _inTreatment;
      final queued = _queued;
      final waiting = _waiting;
      final cap = _ctrl.healCapacity;
      final qCap = _ctrl.healQueueCapacity;
      return MenuScaffold(
        title: 'Healing Hut',
        trailing: _readout(treating.length, cap, queued.length, qCap),
        child: SlotFamilyLayout(
          slots: [
            for (final c in treating) _bedCard(c),
            ..._freeBeds(cap, treating.length, waiting.isNotEmpty),
          ],
          line: _line(queued, qCap),
          tilesTitle: 'Wounded · ${waiting.length}',
          tilesTrailing: waiting.isEmpty ? null : _healAll(waiting),
          tiles: [for (final c in waiting) _tile(c)],
          whenNoTiles: slotEmptyNote(
            treating.isEmpty && queued.isEmpty
                ? 'Everyone is at full health.'
                : 'Everyone hurt is in the hut or in line.',
            'Wounded monsters turn up here after a fight.',
          ),
        ),
      );
    },
  );

  Widget _readout(int treating, int? cap, int queued, int? qCap) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      '${cap == null ? treating : '$treating/${cap < treating ? treating : cap}'}'
      ' treating · '
      '${qCap == null ? queued : '$queued/${qCap < queued ? queued : qCap}'}'
      ' in line',
      style: FoE.value(size: 11).copyWith(color: kBoxInk),
    ),
  );

  // ── The beds ──────────────────────────────────────────────────────────

  Widget _bedCard(CreatureInstance c) {
    final total = _durationOf(c);
    final left = c.healingRemaining;
    final progress = total.inMilliseconds <= 0
        ? 1.0
        : (1 - left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final skip = _creatures.healSkipCost(c);
    final key = 'skip_${c.id}';
    return SlotCard(
      avatar: CreatureAvatar.of(c, size: 44),
      name: c.displayName,
      sub: _hp(c),
      progress: progress,
      time: _fmt(left),
      // Finish it now for gold — the same buy-out the build queue and the
      // Hatchery offer, priced on the REAL time left.
      action: skip > 0
          ? SlotPill(
              '🪙 $skip',
              gold: true,
              onTap: _busy == key || _ctrl.gold < skip
                  ? null
                  : () => _run(key, () => _creatures.skipHealWithGold(c)),
            )
          : null,
    );
  }

  List<Widget> _freeBeds(int? cap, int used, bool anyWaiting) {
    // No cap authored = no ceiling: one open bed shows while somebody waits.
    final free = cap == null ? (anyWaiting ? 1 : 0) : cap - used;
    return [
      for (var i = 0; i < free; i++) const FreeSlotCard(label: 'Free bed'),
    ];
  }

  Widget _line(List<CreatureInstance> queued, int? qCap) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      slotLineHeading(
        'In line',
        qCap == null ? '${queued.length}' : '${queued.length}/$qCap',
      ),
      if (queued.isEmpty)
        Text(
          'Nobody is waiting.',
          style: FoE.dim(size: 11).copyWith(color: kBoxInkFaint),
        )
      else
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in queued)
                  SlotChip(
                    avatar: CreatureAvatar.of(c, size: 22),
                    name: c.displayName,
                    onRemove: _busy == 'unqueue_${c.id}'
                        ? null
                        : () async {
                            setState(() => _busy = 'unqueue_${c.id}');
                            await _creatures.unqueueHealing(c);
                            if (mounted) setState(() => _busy = null);
                          },
                  ),
              ],
            ),
          ),
        ),
    ],
  );

  // ── Everyone hurt ─────────────────────────────────────────────────────

  Widget _tile(CreatureInstance c) {
    final key = 'heal_${c.id}';
    final cost = _costOf(c);
    final affordable = canAfford(cost, _ctrl.resources?.asMap ?? const {});
    final slots = _freeSlots;
    // FULL IS NOT A REFUSAL — it means "join the line". The bill is only checked
    // for a treatment that starts NOW; a queued monster pays when its slot comes
    // up, so a bare purse must not stop it getting in line.
    final queueing = slots != null && slots <= 0;
    final lineFull = queueing && (_freeQueue ?? 1) <= 0;
    final live = _busy == null && !lineFull && (queueing || affordable);
    final hpFrac = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    return SlotTile(
      avatar: CreatureAvatar.of(c, size: 40),
      name: c.displayName,
      sub: _hp(c),
      bar: hpFrac,
      barColor: hpFrac < 0.3 ? CreamPalette.warn : CreamPalette.better,
      // What it costs and how long it takes, ON the tile, so a grid of them
      // lines up into figures you can compare.
      note: '${_goodsLabel(cost)} · ⏱ ${_fmt(_durationOf(c))}',
      noteWarn: !affordable && !queueing,
      actionLabel: lineFull
          ? 'Full'
          : queueing
          ? 'Line up'
          : 'Treat',
      onAction: live
          ? () => _run(key, () => _creatures.queueForHealing(c))
          : null,
    );
  }

  /// Everyone still wounded, in one move — the shortcut for the case the hut
  /// exists for: you just lost a fight and the whole party is bleeding.
  Widget _healAll(List<CreatureInstance> waiting) {
    final cost = _creatures.healAllCost;
    final slots = _freeSlots;
    // How many the hut can actually take right now: its free slots plus the
    // free places in the line. Null on either side means unlimited there.
    final room = slots == null || _freeQueue == null
        ? waiting.length
        : slots + _freeQueue!;
    final takes = room < waiting.length ? room : waiting.length;
    final live = _busy == null && takes > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          takes <= 0
              ? 'No room — treat somebody first'
              : takes < waiting.length
              ? 'only $takes fit for now'
              : _goodsLabel(cost),
          style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
        ),
        const SizedBox(width: 8),
        SocialGoldButton(
          'Heal all ${waiting.length}',
          height: 28,
          fontSize: 11.5,
          onTap: live ? () => _run('all', _creatures.healAll) : null,
        ),
      ],
    );
  }
}
