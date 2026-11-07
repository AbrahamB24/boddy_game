import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../settlement/settlement_controller.dart';
import '../social/widgets/social_kit.dart';
import 'models/ability_def.dart';
import 'models/creature_instance.dart';
import 'services/creatures_controller.dart';
import 'services/training_cost.dart';
import 'widgets/creature_family.dart';
import 'widgets/slot_kit.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';

/// The Combat School (user 2026-09-05; laid out like the Healing Hut since
/// 2026-09-20, "Variante 2, Slot-Karten") — where a creature actually learns a
/// move, taking real time that scales with the move's own Power.
///
/// The practice places on top (the pupil, what they are learning, a bar, the time
/// left, gold to finish now), the line beside them, and everyone with a move
/// still to learn as tiles below. It differs from the Healing Hut in one way:
/// starting a lesson needs a choice of WHICH move, so a tile's button opens the
/// move picker instead of acting directly.
class CombatSchoolScreen extends StatefulWidget {
  const CombatSchoolScreen({super.key});

  @override
  State<CombatSchoolScreen> createState() => _CombatSchoolScreenState();
}

class _CombatSchoolScreenState extends State<CombatSchoolScreen> {
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
        .where(
          (c) => c.learnableAbilities.any(
            (a) => !c.learnedAbilityIds.contains(a.id),
          ),
        )
        .toList();
    list.sort(
      (a, b) =>
          a.equippedAbilityIds.length.compareTo(b.equippedAbilityIds.length),
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
    if (err != null) context.snack(err, error: true);
  }

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_creatures, _ctrl]),
    builder: (context, _) {
      final training = _training;
      final queued = _queued;
      final eligible = _eligible;
      final cap = _ctrl.trainCapacity;
      final qCap = _ctrl.trainQueueCapacity;
      return MenuScaffold(
        title: 'Combat School',
        trailing: _readout(training.length, cap, queued.length, qCap),
        child: SlotFamilyLayout(
          slots: [
            for (final c in training) _deskCard(c),
            ..._freeDesks(cap, training.length, eligible.isNotEmpty),
          ],
          line: _line(queued, qCap),
          tilesTitle: 'Ready to learn · ${eligible.length}',
          tiles: [for (final c in eligible) _tile(c)],
          whenNoTiles: slotEmptyNote(
            training.isEmpty && queued.isEmpty
                ? 'Nobody has anything left to learn.'
                : 'Everyone else already knows everything they can right now.',
            'New moves open up as monsters level up.',
          ),
        ),
      );
    },
  );

  Widget _readout(int training, int? cap, int queued, int? qCap) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(9),
    ),
    child: Text(
      '${cap == null ? training : '$training/${cap < training ? training : cap}'}'
      ' training · '
      '${qCap == null ? queued : '$queued/${qCap < queued ? queued : qCap}'}'
      ' in line',
      style: FoE.value(size: 11).copyWith(color: kBoxInk),
    ),
  );

  // ── The practice places ───────────────────────────────────────────────

  Widget _deskCard(CreatureInstance c) {
    final ability = kAbilityDefs[c.trainingAbilityId];
    final total = ability == null ? Duration.zero : trainingDuration(ability);
    final left = c.trainingRemaining;
    final progress = total.inMilliseconds <= 0
        ? 1.0
        : (1 - left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final skip = _creatures.trainSkipCost(c);
    final key = 'skip_${c.id}';
    return SlotCard(
      avatar: CreatureAvatar.of(c, size: 44),
      name: c.displayName,
      sub: 'Learning ${ability?.name ?? c.trainingAbilityId}',
      progress: progress,
      time: _fmt(left),
      action: skip > 0
          ? SlotPill(
              '🪙 $skip',
              gold: true,
              onTap: _busy == key || _ctrl.gold < skip
                  ? null
                  : () => _run(key, () => _creatures.skipTrainWithGold(c)),
            )
          : null,
    );
  }

  List<Widget> _freeDesks(int? cap, int used, bool anyEligible) {
    final free = cap == null ? (anyEligible ? 1 : 0) : cap - used;
    return [
      for (var i = 0; i < free; i++)
        const FreeSlotCard(label: 'Free practice spot'),
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
                            await _creatures.unqueueTraining(c);
                            if (mounted) setState(() => _busy = null);
                          },
                  ),
              ],
            ),
          ),
        ),
    ],
  );

  // ── Everyone who can learn something ──────────────────────────────────

  Widget _tile(CreatureInstance c) => SlotTile(
    avatar: CreatureAvatar.of(c, size: 40),
    name: c.displayName,
    sub: '${c.equippedAbilityIds.length + 1}/$kMaxAbilitiesTotal moves',
    actionLabel: 'Learn…',
    onAction: _busy == null ? () => _openPicker(c) : null,
    onTap: _busy == null ? () => _openPicker(c) : null,
  );

  Future<void> _openPicker(CreatureInstance c) async {
    final options =
        c.learnableAbilities
            .where((a) => !c.learnedAbilityIds.contains(a.id))
            .toList()
          ..sort((a, b) => a.totalPower.compareTo(b.totalPower));
    if (options.isEmpty) return;
    final chosen = await pushMenu<String>(
      context,
      _MovePickerScreen(creature: c, options: options),
    );
    if (chosen == null || !mounted) return;
    await _run('queue_${c.id}', () => _creatures.queueForTraining(c, chosen));
  }
}

/// Which move should this monster learn? The monster on the left with what it
/// already knows; on the right the moves it could learn, each with its Power and
/// how long the lesson takes. Pops with the chosen ability's id.
class _MovePickerScreen extends StatelessWidget {
  final CreatureInstance creature;
  final List<AbilityDef> options;

  const _MovePickerScreen({required this.creature, required this.options});

  @override
  Widget build(BuildContext context) {
    final known = [
      for (final id in creature.learnedAbilityIds) kAbilityDefs[id]?.name ?? id,
    ];
    return MenuScaffold(
      title: 'Combat School',
      trailing: Text(
        'Teach ${creature.displayName}',
        style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
      ),
      // The monster's own identity card is a different Gebiet from the list
      // of moves it could learn (user 2026-09-29, "Trennlinien und Zonen
      // gemischt", app-wide), so it gets a [zoneBox] of its own.
      // (MenuScaffold is the one card now — no [pageCard] here.)
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 270,
              child: zoneBox(
                padding: const EdgeInsets.all(8),
                child: Column(
                    children: [
                      CreatureAvatar.of(creature, size: 76),
                      const SizedBox(height: 8),
                      Text(
                        creature.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: kBoxInk,
                        ),
                      ),
                      Text(
                        'Lv ${creature.level} · '
                        '${creature.equippedAbilityIds.length + 1}/'
                        '$kMaxAbilitiesTotal moves (Attack included)',
                        style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          'KNOWS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0.9,
                            color: kBoxAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final k in known)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: raisedTile(radius: 9),
                                    child: Text(
                                      k,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                        color: kBoxInk,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                      child: Row(
                        children: [
                          const Text(
                            'MOVES IT CAN LEARN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.9,
                              color: kBoxAccent,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            "time grows with the move's Power",
                            style: FoE.dim(
                              size: 10.5,
                            ).copyWith(color: kBoxInkSoft),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                        itemCount: options.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, i) =>
                            _moveRow(context, options[i]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  Widget _moveRow(BuildContext context, AbilityDef a) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.pop(context, a.id),
    child: Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: raisedTile(),
      child: Row(
        children: [
          Text(a.element.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: kBoxInk,
                  ),
                ),
                Text(
                  '${a.kind.label} · Power ${a.power}',
                  style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'takes',
                style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft),
              ),
              Text(
                _CombatSchoolScreenState._fmt(trainingDuration(a)),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: kBoxInk,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          SocialGoldButton(
            'Learn',
            height: 28,
            fontSize: 12,
            onTap: () => Navigator.pop(context, a.id),
          ),
        ],
      ),
    ),
  );
}
