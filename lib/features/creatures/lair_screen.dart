import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../settlement/settlement_controller.dart';
import 'models/creature_instance.dart';
import 'models/legendary_lair.dart';
import 'models/legendary_math.dart';
import 'models/species_def.dart';
import 'services/creatures_controller.dart';
import 'services/lair_controller.dart';

/// The lairs of the legendaries (user 2026-11-07).
///
/// Two pages: MY LAIRS (raise a legendary: pay, then wait — trainers shorten
/// the wait) and the MARKETPLACE (open trainer slots in other players' lairs,
/// where one of my legendaries can train for a share of what the owner paid).
class LairScreen extends StatefulWidget {
  const LairScreen({super.key});

  @override
  State<LairScreen> createState() => _LairScreenState();
}

class _LairScreenState extends State<LairScreen> {
  final _lairs = LairController();
  Timer? _ticker;
  int _tab = 0;
  List<OpenLairSlot>? _slots;
  bool _slotsLoading = false;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _lairs.addListener(_rebuild);
    _lairs.load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // A finished upgrade is settled by the server the next time anyone asks.
      if (_lairs.lairs.any((l) => l.isDone) && !_lairs.loading) {
        _lairs.load();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lairs.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSlots() async {
    setState(() => _slotsLoading = true);
    try {
      _slots = await _lairs.openSlots();
    } catch (e) {
      _slots = const [];
    }
    if (mounted) setState(() => _slotsLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return MenuScaffold(
      timber: true,
      title: 'Legendary Lairs',
      child: Column(
        children: [
          Row(
            children: [
              _tabButton(0, 'My lairs'),
              const SizedBox(width: 8),
              _tabButton(1, 'Marketplace'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: !_lairs.available
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'The lairs need the server update (migration 0068) '
                        'before they can be used.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kBoxInk),
                      ),
                    ),
                  )
                : _tab == 0
                ? _myLairs()
                : _market(),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int i, String label) => Expanded(
    child: Pressable(
      onTap: () {
        setState(() => _tab = i);
        if (i == 1 && _slots == null) _loadSlots();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _tab == i
              ? CreamPalette.tan.withValues(alpha: 0.55)
              : CreamPalette.tan.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(color: kBoxInk, fontWeight: FontWeight.bold),
        ),
      ),
    ),
  );

  // ── My lairs ───────────────────────────────────────────────
  Widget _myLairs() {
    final creatures = CreaturesController().creatures;
    if (_lairs.lairs.isEmpty) {
      return Center(
        child: Text(
          _lairs.loading
              ? 'Loading…'
              : 'Defeat a region boss to win its legendary — it moves into '
                    'a lair of its own.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: kBoxInk),
        ),
      );
    }
    return ListView(
      children: [
        for (final lair in _lairs.lairs)
          _lairCard(lair, creatures.where((c) => c.id == lair.creatureId)),
        if (_lairs.busyTrainers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${_lairs.busyTrainers.length} of my legendaries are training '
            'someone else right now.',
            style: TextStyle(color: kBoxInk.withValues(alpha: 0.8)),
          ),
        ],
      ],
    );
  }

  Widget _lairCard(LegendaryLair lair, Iterable<CreatureInstance> match) {
    final c = match.isEmpty ? null : match.first;
    final species = kSpeciesDefs[lair.speciesId];
    final name = c?.displayName ?? species?.name ?? lair.speciesId;
    final cost = species == null ? null : _lairs.costOf(lair, species);
    final res = SettlementController().resources;
    final canPay =
        cost != null &&
        res != null &&
        cost.entries.every((e) => (res.asMap[e.key] ?? 0) >= e.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: zoneBox(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$name · Lv ${lair.level}',
                    style: const TextStyle(
                      color: kBoxInk,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (c != null && c.isOnCooldown)
                  Text(
                    '😴 ${_fmt(c.cooldownUntil!.difference(DateTime.now()))}',
                    style: const TextStyle(color: kBoxInk),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (lair.upgrading) ...[
              LinearProgressIndicator(value: lair.progress.clamp(0.0, 1.0)),
              const SizedBox(height: 6),
              Text(
                'Level ${lair.level + 1} in ${_fmt(lair.remaining)}'
                '  ·  ×${lair.rate.toStringAsFixed(1)} speed'
                '  ·  trainers ${lair.trainers.length}/${LegendaryMath.maxTrainers}',
                style: const TextStyle(color: kBoxInk),
              ),
              if (lair.trainers.isEmpty)
                Text(
                  'Without trainers this takes very long — other players '
                  'can speed it up from the marketplace.',
                  style: TextStyle(color: kBoxInk.withValues(alpha: 0.75)),
                ),
            ] else ...[
              Text(
                cost == null
                    ? ''
                    : 'Level ${lair.level + 1}: ${_costText(cost)}  ·  '
                          '${_fmt(Duration(seconds: LegendaryMath.workSeconds(lair.level).round()))} '
                          'without trainers',
                style: const TextStyle(color: kBoxInk),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Pressable(
                  onTap: !canPay || _busy != null
                      ? () => context.snack(
                          'Not enough resources',
                          error: true,
                        )
                      : () => _start(lair),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: canPay
                          ? CreamPalette.tan.withValues(alpha: 0.7)
                          : CreamPalette.tan.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Upgrade',
                      style: TextStyle(
                        color: kBoxInk,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _start(LegendaryLair lair) async {
    setState(() => _busy = lair.id);
    final err = await _lairs.startUpgrade(lair);
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) context.snack(err, error: true);
  }

  // ── Marketplace ────────────────────────────────────────────
  Widget _market() {
    final slots = _slots;
    if (slots == null || _slotsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Pressable(
            onTap: _loadSlots,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Text('↻ Refresh', style: TextStyle(color: kBoxInk)),
            ),
          ),
        ),
        Expanded(
          child: slots.isEmpty
              ? const Center(
                  child: Text(
                    'No open trainer slots right now.',
                    style: TextStyle(color: kBoxInk),
                  ),
                )
              : ListView(children: [for (final s in slots) _slotCard(s)]),
        ),
      ],
    );
  }

  Widget _slotCard(OpenLairSlot s) {
    final species = kSpeciesDefs[s.speciesId];
    final shares = LegendaryMath.shares;
    final myShare = s.trainers < shares.length ? shares[s.trainers] : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: zoneBox(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${species?.name ?? s.speciesId} · Lv ${s.level}',
                    style: const TextStyle(
                      color: kBoxInk,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${s.ownerName}  ·  ${_fmt(s.remaining)} left  ·  '
                    'trainers ${s.trainers}/${LegendaryMath.maxTrainers}',
                    style: const TextStyle(color: kBoxInk),
                  ),
                  Text(
                    'Your slot: #${s.nextSlot} · ${(myShare * 100).round()} % '
                    'of the payment (more when fewer trainers follow)',
                    style: TextStyle(color: kBoxInk.withValues(alpha: 0.75)),
                  ),
                ],
              ),
            ),
            Pressable(
              onTap: () => _pickTrainer(s),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CreamPalette.tan.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Train',
                  style: TextStyle(
                    color: kBoxInk,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTrainer(OpenLairSlot s) async {
    final free = _lairs.freeTrainers;
    if (free.isEmpty) {
      context.snack(
        _lairs.myLegendaries.isEmpty
            ? 'Only a legendary can train.'
            : 'All your legendaries are already training.',
        error: true,
      );
      return;
    }
    final picked = await showDialog<CreatureInstance>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text(
          'Who trains? It stays until the upgrade is done.',
        ),
        children: [
          for (final c in free)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: Text(
                '${c.displayName} · Lv ${c.level} · '
                '+${(_lairs.trainerEffectOf(c) * 100).round()} % speed',
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final err = await _lairs.joinAsTrainer(s, picked);
    if (!mounted) return;
    if (err != null) {
      context.snack(err, error: true);
    } else {
      context.snack('${picked.displayName} is training.');
      _loadSlots();
    }
  }

  // ── Formatting ─────────────────────────────────────────────
  String _costText(Map<String, double> cost) => cost.entries
      .map((e) => '${e.value.round()} ${e.key}')
      .join(' + ');

  String _fmt(Duration d) {
    if (d.isNegative || d == Duration.zero) return '0m';
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}

/// Used by the collection hub to show a one-number state on its door.
String lairHubLine() {
  final l = LairController().lairs;
  if (l.isEmpty) return 'Legendaries';
  final up = l.where((x) => x.upgrading).length;
  return up > 0 ? '$up upgrading' : '${l.length} lairs';
}
