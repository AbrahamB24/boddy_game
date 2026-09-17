import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/scroll_paper.dart' show kParchmentInk, kParchmentLight;
import 'models/ability_def.dart';
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';
import 'services/training_cost.dart';
import 'widgets/creature_sprite.dart';
import '../../core/ui/pressable.dart';

/// The Combat School (user 2026-09-05) — where a creature actually learns a
/// move, taking real time that scales with the move's own Power. Structurally
/// the Healing Hut's own screen (capacity + a line, both level-scaled
/// building effects), with one difference: starting a lesson needs a choice
/// of WHICH move, not just a monster, so the "eligible" group opens a picker
/// instead of acting directly.
class CombatSchoolScreen extends StatefulWidget {
  const CombatSchoolScreen({super.key});

  @override
  State<CombatSchoolScreen> createState() => _CombatSchoolScreenState();
}

enum _Row { training, queued, eligible }

class _CombatSchoolScreenState extends State<CombatSchoolScreen> {
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);
  static const Color _accent = FoE.gold;
  static final Color _cardFill = kParchmentInk.withValues(alpha: 0.06);
  static final Color _hairline = kParchmentInk.withValues(alpha: 0.13);

  final _creatures = CreaturesController();
  final _ctrl = SettlementController();
  Timer? _ticker;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_creatures.trainingCreatures.isEmpty &&
          _creatures.trainQueue.isEmpty) {
        return;
      }
      _creatures.resolveFinishedTrainings();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<CreatureInstance> get _training => _creatures.trainingCreatures;
  List<CreatureInstance> get _queued => _creatures.trainQueue;

  /// Everyone with at least one move still to learn, worst-equipped first
  /// (fewest equipped abilities), so a bare-bones team surfaces above one
  /// that's already well rounded out.
  List<CreatureInstance> get _eligible {
    final list = _creatures.creatures
        .where((c) => !c.isTraining && !c.isQueuedForTraining)
        .where((c) => c.learnableAbilities.any(
              (a) => !c.learnedAbilityIds.contains(a.id),
            ))
        .toList();
    list.sort(
      (a, b) => a.equippedAbilityIds.length.compareTo(b.equippedAbilityIds.length),
    );
    return list;
  }

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
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_creatures, _ctrl]),
    builder: (context, _) => ParchmentPage(
      title: 'Combat School',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ParchmentPage.kParchmentPagePad,
          12,
          ParchmentPage.kParchmentPagePad,
          24,
        ),
        children: _body(),
      ),
    ),
  );

  List<Widget> _body() {
    final training = _training;
    final queued = _queued;
    final eligible = _eligible;

    if (training.isEmpty && queued.isEmpty && eligible.isEmpty) {
      return [const SizedBox(height: 60), _allDone()];
    }

    return [
      _stateBand(training.length, queued.length),
      const SizedBox(height: 16),
      if (training.isNotEmpty) ...[
        _group(
          title: 'Training',
          stripe: FoE.positive,
          rows: [for (final c in training) _row(c, _Row.training)],
        ),
        const SizedBox(height: 14),
      ],
      if (queued.isNotEmpty) ...[
        _group(
          title: 'In line',
          stripe: _accent,
          note: 'They start as slots free, in this order.',
          rows: [
            for (var i = 0; i < queued.length; i++)
              _row(queued[i], _Row.queued, place: i + 1),
          ],
        ),
        const SizedBox(height: 14),
      ],
      if (eligible.isNotEmpty)
        _group(
          title: 'Ready to learn',
          stripe: FoE.gold,
          rows: [for (final c in eligible) _row(c, _Row.eligible)],
        )
      else if (queued.isNotEmpty || training.isNotEmpty)
        Text(
          'Everyone else already knows everything they can right now.',
          style: FoE.dim(size: 12).copyWith(color: _inkFaint),
        ),
    ];
  }

  Widget _allDone() => Column(
    children: [
      Text('🥋', style: TextStyle(fontSize: 30, color: FoE.gold)),
      const SizedBox(height: 10),
      Text(
        'Nobody has anything left to learn.',
        textAlign: TextAlign.center,
        style: FoE.label(size: 13).copyWith(color: _inkSoft),
      ),
      const SizedBox(height: 4),
      Text(
        'New moves open up as your monsters evolve.',
        textAlign: TextAlign.center,
        style: FoE.dim(size: 11).copyWith(color: _inkFaint),
      ),
    ],
  );

  Widget _stateBand(int training, int queued) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    decoration: ShapeDecoration(
      color: _cardFill,
      shape: FoE.facet(radius: 12, side: BorderSide(color: kParchmentInk.withValues(alpha: 0.15))),
    ),
    child: Row(
      children: [
        _bandFact('🥋', training, _ctrl.trainCapacity, 'training', FoE.positive),
        _bandDivider(),
        _bandFact('⏳', queued, _ctrl.trainQueueCapacity, 'in line', _accent),
      ],
    ),
  );

  Widget _bandFact(String glyph, int n, int? cap, String label, Color tint) =>
      Expanded(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(glyph, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 5),
                Text(
                  cap == null ? '$n' : '$n/${cap < n ? n : cap}',
                  style: FoE.value(size: 15).copyWith(color: tint),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(label, style: FoE.dim(size: 9).copyWith(color: _inkFaint)),
          ],
        ),
      );

  Widget _bandDivider() => Container(width: 1, height: 26, color: _hairline);

  Widget _group({
    required String title,
    required Color stripe,
    required List<Widget> rows,
    String? note,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(width: 3, height: 13, color: stripe),
          const SizedBox(width: 7),
          Text(
            title.toUpperCase(),
            style: FoE.dim(size: 10).copyWith(
              color: _inkSoft,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text('${rows.length}', style: FoE.value(size: 11).copyWith(color: _inkFaint)),
        ],
      ),
      if (note != null) ...[
        const SizedBox(height: 4),
        Text(note, style: FoE.dim(size: 10).copyWith(color: _inkFaint)),
      ],
      const SizedBox(height: 7),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: _cardFill,
          shape: FoE.facet(radius: 12, side: BorderSide(color: kParchmentInk.withValues(alpha: 0.15))),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: _hairline),
              rows[i],
            ],
          ],
        ),
      ),
    ],
  );

  Widget _row(CreatureInstance c, _Row kind, {int? place}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          if (place != null)
            SizedBox(
              width: 16,
              child: Text('$place', style: FoE.value(size: 11).copyWith(color: _inkFaint)),
            ),
          _portrait(c),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 12).copyWith(color: _ink),
                ),
                const SizedBox(height: 4),
                Text(
                  _rowSubtitle(c, kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10).copyWith(color: _inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _rowTrailing(c, kind),
        ],
      ),
    );
  }

  String _rowSubtitle(CreatureInstance c, _Row kind) {
    if (kind == _Row.training) {
      final ability = kAbilityDefs[c.trainingAbilityId];
      return 'Learning ${ability?.name ?? c.trainingAbilityId}';
    }
    if (kind == _Row.queued) {
      final ability = kAbilityDefs[c.trainingAbilityId];
      return 'Waiting to learn ${ability?.name ?? c.trainingAbilityId}';
    }
    return '${c.equippedAbilityIds.length}/$kMaxEquippedAbilities equipped';
  }

  Widget _rowTrailing(CreatureInstance c, _Row kind) {
    switch (kind) {
      case _Row.training:
        final skip = _creatures.trainSkipCost(c);
        final key = 'skip_${c.id}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _fmt(c.trainingRemaining),
              style: FoE.value(size: 12).copyWith(color: FoE.positive),
            ),
            if (skip > 0) ...[
              const SizedBox(width: 8),
              _pill(
                '🪙 $skip',
                _accent,
                _busy == key || _ctrl.gold < skip
                    ? null
                    : () => _run(key, () => _creatures.skipTrainWithGold(c)),
              ),
            ],
          ],
        );
      case _Row.queued:
        final key = 'unqueue_${c.id}';
        return _pill(
          'Leave',
          _inkFaint,
          _busy == key
              ? null
              : () async {
                  setState(() => _busy = key);
                  await _creatures.unqueueTraining(c);
                  if (mounted) setState(() => _busy = null);
                },
        );
      case _Row.eligible:
        return _pill('Learn…', FoE.positive, () => _openPicker(c), filled: true);
    }
  }

  Future<void> _openPicker(CreatureInstance c) async {
    final options = c.learnableAbilities
        .where((a) => !c.learnedAbilityIds.contains(a.id))
        .toList()
      ..sort((a, b) => a.totalPower.compareTo(b.totalPower));
    if (options.isEmpty) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FoE.panelDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Teach ${c.displayName}',
                style: FoE.title(size: 15),
              ),
              const SizedBox(height: 10),
              ...[
                for (final a in options)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(a.element.emoji, style: const TextStyle(fontSize: 18)),
                    title: Text(a.name, style: FoE.label(size: 13)),
                    subtitle: Text(
                      '${a.kind.label} · Power ${a.power} · '
                      '⏱ ${_fmt(trainingDuration(a))}',
                      style: FoE.dim(size: 11),
                    ),
                    onTap: () => Navigator.pop(ctx, a.id),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await _run('queue_${c.id}', () => _creatures.queueForTraining(c, chosen));
  }

  Widget _portrait(CreatureInstance c) => SizedBox(
    width: 34,
    height: 34,
    child: c.imageUrl == null
        ? Icon(Icons.pets, size: 20, color: _accent)
        : CreatureSprite(url: c.imageUrl!, fallback: Icon(Icons.pets, size: 20, color: _accent)),
  );

  Widget _pill(String label, Color color, VoidCallback? onTap, {bool filled = false}) =>
      Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: color.withValues(alpha: filled ? 0.9 : 0.07),
              shape: FoE.facet(radius: 9, side: BorderSide(color: color.withValues(alpha: filled ? 0.9 : 0.5))),
            ),
            child: Text(
              label,
              style: FoE.label(size: 11).copyWith(color: filled ? kParchmentLight : color),
            ),
          ),
        ),
      );
}
