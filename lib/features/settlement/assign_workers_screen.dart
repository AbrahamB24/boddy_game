import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/scroll_cue.dart';
import '../common/widgets/filter_pills.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/creature_family.dart' show CreatureAvatar;
import 'data/building_definitions.dart';
import 'data/resource_icons.dart';
import 'data/workshop_role_effects.dart';
import 'models/placed_building.dart';
import 'settlement_controller.dart';

/// Posting monsters to a work post — "Sitze + Liste" (user 2026-09-22, picked from
/// ten; it replaces the bottom sheet `AssignWorkersSheet`).
///
/// Two cards. On top the SEATS this post has, big, each with what that monster
/// makes here per hour, and the post's total beside them. Below, everyone else as
/// slim rows: a stat bar (the stat THIS post reads), a status pill (free / works
/// somewhere / away / unfit) and what the monster would make here — sorted, searched
/// and filtered by the shared pills. A tap on a row hires; a tap on a filled seat
/// makes the next row tap REPLACE that monster; its ✕ vacates the seat.
///
/// The per-hour figures are the economy's own formula ([WorkshopRole.contribution],
/// times today's energy), the same one the building dialog's Total prints — so a
/// seat's "+10.4/h" is what it banks.
Future<void> showAssignWorkers(
  BuildContext context, {
  required SettlementController ctrl,
  required PlacedBuilding building,
  required WorkshopRole role,
  String? swapId,
}) => pushMenu(
  context,
  AssignWorkersScreen(
    ctrl: ctrl,
    building: building,
    role: role,
    swapTargetId: swapId,
  ),
);

class AssignWorkersScreen extends StatefulWidget {
  final SettlementController ctrl;
  final PlacedBuilding building;
  final WorkshopRole role;

  /// Opens with the next pick already REPLACING this monster — set by a tap on
  /// that monster's seat in the building dialog. Null = a plain hire.
  final String? swapTargetId;

  const AssignWorkersScreen({
    super.key,
    required this.ctrl,
    required this.building,
    required this.role,
    this.swapTargetId,
  });

  @override
  State<AssignWorkersScreen> createState() => _AssignWorkersScreenState();
}

class _AssignWorkersScreenState extends State<AssignWorkersScreen> {
  /// The "already employed somewhere else" mark: a MOVE, which costs another
  /// building its worker — neither the green of a free hire nor an error.
  static const Color _takenInk = CreamPalette.warn;

  /// Set when a filled seat was tapped: the next roster pick REPLACES this
  /// monster instead of filling a fresh seat.
  String? _swapTargetId;

  /// The sort pill: null key = the post's own order (best stat first, lowest
  /// level first for Training).
  String? _sortKey;
  late bool _sortDescending = !_training;

  final _search = TextEditingController();
  String _query = '';
  CreatureElement? _filterElement;

  @override
  void initState() {
    super.initState();
    _swapTargetId = widget.swapTargetId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  WorkshopRole get _role => widget.role;
  bool get _training => _role.resource == WorkshopRole.kTraining;

  /// The live building — the one handed in is a snapshot and goes stale when it
  /// is upgraded.
  PlacedBuilding get _building => widget.ctrl.buildings.firstWhere(
    (b) => b.id == widget.building.id,
    orElse: () => widget.building,
  );

  int get _slots => effectiveSlots(_role, _building.level);

  CreatureInstance? get _swapTarget {
    final id = _swapTargetId;
    if (id == null) return null;
    for (final c in CreaturesController().creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Everyone posted to THIS building on THIS role.
  List<CreatureInstance> get _posted =>
      CreaturesController().creatures
          .where(
            (c) =>
                c.assignedBuildingId == widget.building.id &&
                c.assignedStat == _role.stat,
          )
          .toList()
        ..sort(_cmp);

  /// Everyone else — PLUS the seat's own occupant while it is being swapped (it
  /// is still a real, pickable option). A TRAINING post ranks lowest LEVEL first:
  /// every trainee earns the same XP/h, and it is worth most to the least-levelled
  /// monster.
  List<CreatureInstance> get _candidates {
    final hereIds = _posted.map((c) => c.id).toSet()..remove(_swapTargetId);
    final q = _query.trim().toLowerCase();
    return CreaturesController().creatures
        .where(
          (c) =>
              !hereIds.contains(c.id) &&
              (_filterElement == null ||
                  c.species?.element == _filterElement) &&
              (q.isEmpty || c.displayName.toLowerCase().contains(q)),
        )
        .toList()
      ..sort(_cmp);
  }

  int _cmp(CreatureInstance x, CreatureInstance y) {
    final cmp = switch (_sortKey) {
      'level' => x.level.compareTo(y.level),
      'name' => x.displayName.compareTo(y.displayName),
      _ =>
        _training
            ? x.level.compareTo(y.level)
            : x.statValue(_role.stat).compareTo(y.statValue(_role.stat)),
    };
    return _sortDescending ? -cmp : cmp;
  }

  /// The building a monster is posted to, when it is NOT this one.
  String? _postedElsewhere(CreatureInstance c) {
    final id = c.assignedBuildingId;
    if (id == null || id == widget.building.id) return null;
    for (final b in widget.ctrl.buildings) {
      if (b.id == id) return kBuildingDefs[b.buildingTypeId]?.name ?? b.id;
    }
    return null;
  }

  // ── What a monster makes here ─────────────────────────────
  /// [c]'s output at this post, level factor and today's energy applied — the
  /// building dialog's own tally.
  Map<String, double> _power(CreatureInstance c) {
    final energy = widget.ctrl.energyMultiplier;
    return {
      for (final e
          in _role
              .contribution((s) => c.statValue(s).toDouble(), _building.level)
              .entries)
        e.key: e.value * energy,
    };
  }

  /// "+10.4/h 🪵", "+30 points", "−12 %" … null for Training (its reward is XP,
  /// the same for everyone).
  String? _figureOf(Map<String, double> power) {
    if (_training || power.isEmpty) return null;
    if (_role.producesResource && !_role.isCombined) {
      final v = power[_role.resource] ?? 0;
      return '+${v.toStringAsFixed(1)}/h ${resourceEmoji(_role.resource)}';
    }
    if (_role.resource == WorkshopRole.kConstruction) {
      return '+${(power[_role.resource] ?? 0).toStringAsFixed(0)} points';
    }
    return workshopPowerLabel(power, withGlyph: _role.isCombined);
  }

  /// Whether [c] adds anything right now: posted here and actually IN the
  /// building (not away, K.O., breeding, healing, or in a paused building).
  bool _working(CreatureInstance c) => CreaturesController().isWorkingNow(c);

  Map<String, double> _sum(Iterable<CreatureInstance> crew) {
    final total = <String, double>{};
    for (final c in crew.where(_working)) {
      for (final e in _power(c).entries) {
        total[e.key] = (total[e.key] ?? 0) + e.value;
      }
    }
    return total;
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _set(CreatureInstance c, bool post) async {
    final err = post
        ? await widget.ctrl.assignCreatureToWorkshop(
            c.id,
            widget.building.id,
            _role.stat,
          )
        : await widget.ctrl.assignCreatureToWorkshop(c.id, null, null);
    if (!mounted) return;
    if (err != null) {
      // The buzz alone (user 2026-08-29: no pop-up messages).
      Feel.deny();
      return;
    }
    Feel.success();
  }

  /// A pick made while a seat is being swapped: the outgoing monster is freed
  /// FIRST — the seat is already full, so posting the new one before that would
  /// bounce off the same capacity check.
  Future<void> _swapWith(CreatureInstance candidate) async {
    final outgoing = _swapTarget;
    if (outgoing != null) await _set(outgoing, false);
    await _set(candidate, true);
    if (!mounted) return;
    setState(() => _swapTargetId = null);
  }

  Future<void> _remove(CreatureInstance c) async {
    await _set(c, false);
    if (!mounted) return;
    if (_swapTargetId == c.id) setState(() => _swapTargetId = null);
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.ctrl, CreaturesController()]),
    builder: (context, _) {
      final posted = _posted;
      final free = _slots - posted.length;
      return MenuScaffold(
        title:
            kBuildingDefs[widget.building.buildingTypeId]?.name ??
            widget.building.buildingTypeId,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _training ? 'Training' : _role.stat.label,
              style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
            ),
            const SizedBox(width: 6),
            Text(
              '${posted.length} / $_slots',
              style: FoE.value(
                size: 13,
              ).copyWith(color: free <= 0 ? kBoxAccent : kBoxInk),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _seatsCard(posted),
            const SizedBox(height: 12),
            Expanded(child: _rosterCard()),
          ],
        ),
      );
    },
  );

  // ── The seats ─────────────────────────────────────────────
  Widget _seatsCard(List<CreatureInstance> posted) {
    final total = _figureOf(_sum(posted));
    return creamCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        height: 104,
        child: Row(
          children: [
            Expanded(
              child: ScrollCue(
                axis: Axis.horizontal,
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _slots; i++) ...[
                        i < posted.length
                            ? _filledSeat(posted[i])
                            : _emptySeat(),
                        const SizedBox(width: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 170,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'TOTAL HERE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: kBoxInkFaint,
                    ),
                  ),
                  if (posted.isEmpty)
                    Text(
                      'Nobody works here.\nThis building produces nothing.',
                      textAlign: TextAlign.end,
                      style: FoE.dim(size: 11).copyWith(color: FoE.danger),
                    )
                  else ...[
                    Text(
                      total ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.value(size: 20).copyWith(color: kBoxInk),
                    ),
                    Text(
                      'Lv ${_building.level} · energy '
                      '×${widget.ctrl.energyMultiplier.toStringAsFixed(2)}',
                      style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A seat with a monster: its face, name and what it makes here. A tap sets it
  /// as the swap target; the ✕ vacates it.
  Widget _filledSeat(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final breeding = creatures.isBreeding(c.id);
    final swapping = _swapTargetId == c.id;
    final figure = _working(c) ? _figureOf(_power(c)) : null;
    return SizedBox(
      width: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Pressable(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _swapTargetId = c.id),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: swapping
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: CreamPalette.gold,
                            width: 2.5,
                          ),
                        )
                      : null,
                  child: CreatureAvatar.of(c, size: 46),
                ),
                const SizedBox(height: 2),
                Text(
                  c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(size: 11).copyWith(color: kBoxInk),
                ),
                // A posted monster that is not actually IN the building is the one
                // thing a seat must not hide: it looks staffed and yields nothing.
                if (away || breeding || c.isKo)
                  Text(
                    away
                        ? '🎒 no output'
                        : c.isKo
                        ? '💀 no output'
                        : '💤 no output',
                    style: FoE.label(size: 9.5).copyWith(color: _takenInk),
                  )
                else if (figure != null)
                  Text(
                    figure,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.value(
                      size: 11,
                    ).copyWith(color: CreamPalette.better),
                  ),
              ],
            ),
          ),
          Positioned(
            right: 4,
            top: -4,
            child: Pressable(
              key: ValueKey('remove-${c.id}'),
              onTap: () => _remove(c),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: CreamPalette.warn,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A place waiting to be filled. The roster below is always on screen, so a
  /// tap here only clears a pending swap.
  Widget _emptySeat() => SizedBox(
    width: 88,
    child: Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _swapTargetId = null),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(3),
            child: SizedBox(
              width: 46,
              height: 46,
              child: const EmptySeat(radius: 12),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Free seat',
            style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
          ),
        ],
      ),
    ),
  );

  // ── The roster ────────────────────────────────────────────
  Widget _rosterCard() {
    final candidates = _candidates;
    final swapping = _swapTarget;
    return creamCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: _searchPill()),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _sortPill()),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _filterPill()),
            ],
          ),
          const SizedBox(height: 6),
          // Only while a filled seat is being swapped.
          if (swapping != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Swapping ${swapping.displayName} — pick the replacement',
                      style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                    ),
                  ),
                  Pressable(
                    onTap: () => setState(() => _swapTargetId = null),
                    child: Icon(Icons.close, size: 16, color: kBoxInkSoft),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Tap a monster to post it',
                style: FoE.dim(size: 11).copyWith(color: kBoxInkFaint),
              ),
            ),
          Expanded(
            child: candidates.isEmpty
                ? Center(
                    child: Text(
                      'No other monsters.',
                      style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                    ),
                  )
                : ScrollCue(
                    builder: (context, controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.only(bottom: 4),
                      children: [for (final c in candidates) _rosterRow(c)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// One row: face, name, the stat THIS post reads (bar and number — that number
  /// is the whole reason to sort the list), a status pill, what the monster would
  /// make here, and the honest action icon (a TRANSFER arrow when it means taking
  /// the monster off another post).
  Widget _rosterRow(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    final elsewhere = _postedElsewhere(c);
    final taken = elsewhere != null && !away && !idle;
    final unavailable = away || idle;
    final (status, pill) = away
        ? ('🎒 Away', _Pill.no)
        : idle
        ? ('💤 Unfit', _Pill.no)
        : taken
        ? ('At $elsewhere', _Pill.warn)
        : ('Free', _Pill.free);
    final statValue = _training ? c.level : c.statValue(_role.stat);
    // Stat bars read against the largest value in the collection.
    final gain = unavailable ? null : _figureOf(_power(c));
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => _swapTargetId == null ? _set(c, true) : _swapWith(c),
        child: Opacity(
          opacity: unavailable ? 0.6 : 1,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: raisedTile(radius: 11),
            child: Row(
              children: [
                CreatureAvatar.of(c, size: 28, showHp: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 13).copyWith(color: kBoxInk),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Row(
                    children: [
                      Expanded(child: _statBar(statValue)),
                      const SizedBox(width: 6),
                      Text(
                        '$statValue',
                        style: FoE.value(size: 13).copyWith(color: kBoxAccent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 128,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _statusPill(status, pill),
                  ),
                ),
                SizedBox(
                  width: 84,
                  child: Text(
                    gain ?? '—',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.value(size: 12.5).copyWith(
                      color: gain == null ? kBoxInkFaint : CreamPalette.better,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // The honest icon (user 2026-07-26): a TRANSFER arrow in the
                // warning colour instead of the plus, because that is what the tap
                // does.
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: taken ? _takenInk : CreamPalette.gold,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    taken ? Icons.swap_horiz : Icons.add,
                    size: 15,
                    color: taken ? Colors.white : CreamPalette.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statBar(int value) {
    final top = CreaturesController().creatures.fold<int>(
      1,
      (m, c) => (_training ? c.level : c.statValue(_role.stat)) > m
          ? (_training ? c.level : c.statValue(_role.stat))
          : m,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: kBoxInk.withValues(alpha: 0.16)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (value / top).clamp(0.0, 1.0),
                child: const ColoredBox(color: CreamPalette.gold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String text, _Pill kind) => Container(
    constraints: const BoxConstraints(maxWidth: 128),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: switch (kind) {
        _Pill.free => CreamPalette.better.withValues(alpha: 0.18),
        _Pill.warn => CreamPalette.warn.withValues(alpha: 0.18),
        _Pill.no => kBoxInk.withValues(alpha: 0.12),
      },
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: switch (kind) {
          _Pill.free => CreamPalette.better,
          _Pill.warn => CreamPalette.warn,
          _Pill.no => kBoxInkSoft,
        },
      ),
    ),
  );

  // ── Search, sort, filter ──────────────────────────────────
  Widget _searchPill() => SearchPill(
    controller: _search,
    palette: PillPalette.cream,
    onChanged: (v) => setState(() => _query = v),
  );

  /// Field-picks-then-flips, the same pill the Work tab uses.
  Widget _sortPill() {
    final defaultLabel = _training ? 'Level' : _role.stat.label;
    return MenuPill<String>(
      palette: PillPalette.cream,
      icon: Icons.swap_vert,
      label: switch (_sortKey) {
        'level' => 'Level',
        'name' => 'Name',
        _ => defaultLabel,
      },
      engaged: _sortKey != null || _sortDescending != !_training,
      value: _sortKey ?? '',
      entries: [
        MapEntry('', defaultLabel),
        // Training's default IS level, so a separate entry would repeat it.
        if (!_training) const MapEntry('level', 'Level'),
        const MapEntry('name', 'Name'),
      ],
      trailing: Icon(
        _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
        size: 14,
        color: kBoxAccent,
      ),
      selectedTrailing: _sortDescending ? '↓' : '↑',
      onSelected: (v) => setState(() {
        final picked = v.isEmpty ? null : v;
        if (picked == _sortKey) {
          _sortDescending = !_sortDescending;
        } else {
          _sortKey = picked;
          _sortDescending = true;
        }
      }),
    );
  }

  Widget _filterPill() => MenuPill<String>(
    palette: PillPalette.cream,
    icon: Icons.filter_alt_outlined,
    label: _filterElement?.label ?? 'Every type',
    engaged: _filterElement != null,
    value: _filterElement?.name ?? '',
    entries: [
      const MapEntry('', 'Every type'),
      for (final e in CreatureElement.values)
        if (e != CreatureElement.neutral)
          MapEntry(e.name, '${e.emoji} ${e.label}'),
    ],
    onSelected: (v) => setState(
      () => _filterElement = v.isEmpty ? null : CreatureElement.fromName(v),
    ),
  );
}

enum _Pill { free, warn, no }
