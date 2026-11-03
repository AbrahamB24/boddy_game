import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/snack.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/scroll_cue.dart';
import '../common/widgets/filter_pills.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/creature_card.dart';
import '../creatures/widgets/creature_family.dart' show CreatureAvatar;
import '../creatures/widgets/picker_detail_panel.dart';
import '../creatures/widgets/roster_row.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import 'data/building_definitions.dart';
import 'data/resource_icons.dart';
import 'data/workshop_role_effects.dart';
import 'models/placed_building.dart';
import 'settlement_controller.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

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

  /// Tapping a roster row only PREVIEWS it here (user 2026-10-05, "Konzept
  /// 4") — the detail panel's own button is what actually posts or swaps it.
  CreatureInstance? _preview;

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

  /// The tutorial's own step for this screen (user 2026-09-30: "muss auch
  /// wieder nur das Starter möglich sein anzuwählen und nichts anderes") —
  /// a fresh account only ever OWNS the starter at this point, so
  /// [_candidates] can never actually hold anyone else; what this locks
  /// down is the search/sort/filter pills and the seats column, not the
  /// roster's contents.
  bool get _isTutorial =>
      widget.ctrl.introStep == IntroStep.assignHealer &&
      widget.building.buildingTypeId == kHealingHutBuildingId;

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
        // Energy scales what is PRODUCED only — not build points and not the time
        // cuts of the system roles, which run in real time (user 2026-09-28).
        e.key:
            e.value *
            (e.key == WorkshopRole.kConstruction ||
                    workshopRoleFeedsSystem(e.key)
                ? 1.0
                : energy),
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
      return buildPointsLabel(power[_role.resource] ?? 0);
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
      Feel.deny();
      context.snack(err, error: true);
      return;
    }
    Feel.success();
    // The preview has done its job — leaving the just-posted monster in the
    // panel kept a live "Post here" button for a monster already posted.
    if (post && _preview?.id == c.id) setState(() => _preview = null);
    // Straight back to the Healing Hut's own detail dialog (user 2026-09-30:
    // "soll ich direkt wieder auf den Healing Hut Detailscreen kommen") —
    // this screen was pushed FROM that dialog's "+" tile, so popping lands
    // right back on it, already showing the posted worker.
    if (post && _isTutorial) Navigator.pop(context);
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
      return Stack(
        children: [
          MenuScaffold(
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
            // TWO COLUMNS (user 2026-09-28: "Die Liste der Monster ist zu
            // klein"): the seats and their total on the left, the roster on
            // the right over the FULL height. Stacked, the seats card ate
            // ~130 px of a 430 px screen and left the list about two rows.
            //
            // Seats (who works here now) and the roster (who else could) ARE
            // different Gebiete (user 2026-09-29, "Trennlinien und Zonen
            // gemischt", app-wide), so Seats gets a [zoneBox] of its own.
            // (MenuScaffold is the one card now — no [pageCard] here.)
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _kSeatsColumnW,
                  child: zoneBox(
                    padding: EdgeInsets.zero,
                    child: _seatsCard(posted),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: _rosterCard()),
              ],
            ),
          ),
          // Sibling of MenuScaffold, not nested in its `child` (same fix as
          // battle_prep_screen.dart's two tutorial overlays, user
          // 2026-10-01: "hier auch" — nested, the dim only reached
          // MenuScaffold's content slot, leaving the title/count header and
          // its hairline undimmed). Names WHY the choice matters (user
          // 2026-09-30: "erklären, dass Monster unterschiedliche Stats
          // haben, welche sich auf die Effektivität ihrer Arbeit auswirken
          // können") — dead-zones the seats column and the search/sort/
          // filter pills too, though a fresh account only ever owns the one
          // candidate this points at.
          if (_isTutorial)
            const IntroSpotlightOverlay(
              anchorName: 'assignworkers-candidate',
              hint:
                  'Tap to station it. Different monsters have different '
                  'stats, which changes how well they work here.',
            ),
        ],
      );
    },
  );

  /// The seats column: three 88 px seats side by side, with the card's padding.
  static const double _kSeatsColumnW = 320;

  // ── The seats ─────────────────────────────────────────────
  Widget _seatsCard(List<CreatureInstance> posted) {
    final total = _figureOf(_sum(posted));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The total first: it is what the seats add up to.
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
              'Nobody works here. This building produces nothing.',
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
          const SizedBox(height: 8),
          Container(height: 1, color: CreamPalette.tan.withValues(alpha: 0.4)),
          // Seats wrap into rows and scroll when a building has many.
          Expanded(
            child: ScrollCue(
              builder: (context, controller) => SingleChildScrollView(
                controller: controller,
                // Room for the ✕ that hangs off a seat's top-right corner.
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < _slots; i++)
                      i < posted.length ? _filledSeat(posted[i]) : _emptySeat(),
                  ],
                ),
              ),
            ),
          ),
        ],
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
                          borderRadius: vr(14),
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
                  shape: BoxShape.rectangle,
                ),
                child: const PixelIcon(Icons.close, size: 13, color: Colors.white),
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
    return Padding(
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
                    child: PixelIcon(Icons.close, size: 16, color: kBoxInkSoft),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Tap a monster to see its details',
                style: FoE.dim(size: 11).copyWith(color: kBoxInkFaint),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _detail(),
                const SizedBox(width: 10),
                Expanded(
                  child: candidates.isEmpty
                      ? RosterRow.emptyState('No other monsters.')
                      : ScrollCue(
                          builder: (context, controller) => ListView(
                            controller: controller,
                            padding: const EdgeInsets.only(bottom: 4),
                            children: [
                              for (var i = 0; i < candidates.length; i++)
                                _isTutorial && i == 0
                                    ? KeyedSubtree(
                                        key: IntroSpotlightAnchors.of(
                                          'assignworkers-candidate',
                                        ),
                                        child: _rosterRow(candidates[i]),
                                      )
                                    : _rosterRow(candidates[i]),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The left panel: the stat THIS post reads, status (free / posted
  /// elsewhere / away / unfit) and what it would make here — the detail
  /// panel every monster picker now shares. [action] is the only thing that
  /// actually posts or swaps a worker now; tapping a roster row just fills
  /// this in first.
  Widget _detail() {
    final c = _preview;
    if (c == null) {
      return const PickerDetailPanel(
        placeholder: 'Tap a monster to see its details.',
      );
    }
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    final elsewhere = _postedElsewhere(c);
    final taken = elsewhere != null && !away && !idle;
    final unavailable = away || idle;
    final (status, statusColor) = away
        ? ('Away', CreamPalette.warn)
        : idle
        ? ('Unfit', CreamPalette.warn)
        : taken
        ? ('At $elsewhere', CreamPalette.warn)
        : ('Free', CreamPalette.better);
    final gain = unavailable ? null : _figureOf(_power(c));
    return PickerDetailPanel(
      art: CreatureCard(creature: c, showHp: false),
      title: c.displayName,
      subtitle: _training ? 'Lv ${c.level}' : null,
      rows: [
        pickerStatRow(
          _training ? 'Level' : _role.stat.label,
          '${_training ? c.level : c.statValue(_role.stat)}',
        ),
        pickerStatRow('Status', status, valueColor: statusColor),
        if (gain != null) pickerStatRow('Yield here', gain),
      ],
      action: pickerChooseButton(
        label: _swapTargetId != null ? 'Swap in' : 'Post here',
        onTap: () => _swapTargetId == null ? _set(c, true) : _swapWith(c),
      ),
    );
  }

  /// One row via the shared [RosterRow] (user 2026-10-05: "wirklich überall
  /// den gleichen [Monsterpicker] nehmen") — the stat THIS post reads (bar
  /// and number — that number is the whole reason to sort the list), a
  /// status pill, what the monster would make here, and the honest action
  /// icon (a TRANSFER arrow when it means taking the monster off another
  /// post). A tap only PREVIEWS it in [_detail] now — that panel's own
  /// button is what actually posts or swaps it.
  Widget _rosterRow(CreatureInstance c) {
    final creatures = CreaturesController();
    final away = creatures.isOnExpedition(c.id);
    final idle = c.isKo || creatures.isBreeding(c.id);
    final elsewhere = _postedElsewhere(c);
    final taken = elsewhere != null && !away && !idle;
    final unavailable = away || idle;
    final (status, pill) = away
        ? ('🎒 Away', RosterPillKind.no)
        : idle
        ? ('💤 Unfit', RosterPillKind.no)
        : taken
        ? ('At $elsewhere', RosterPillKind.warn)
        : ('Free', RosterPillKind.free);
    final statValue = _training ? c.level : c.statValue(_role.stat);
    final statMax = creatures.creatures.fold<int>(
      1,
      (m, o) => (_training ? o.level : o.statValue(_role.stat)) > m
          ? (_training ? o.level : o.statValue(_role.stat))
          : m,
    );
    // Stat bars read against the largest value in the collection.
    final gain = unavailable ? null : _figureOf(_power(c));
    return pickerPreviewFrame(
      active: _preview?.id == c.id,
      child: RosterRow(
        creature: c,
        statValue: statValue,
        statMax: statMax,
        status: status,
        statusKind: pill,
        figureText: gain,
        dimmed: unavailable,
        // The honest icon (user 2026-07-26): a TRANSFER arrow in the warning
        // colour instead of the plus, because that is what the tap does.
        actionIcon: taken ? Icons.swap_horiz : Icons.add,
        actionColor: taken ? _takenInk : CreamPalette.gold,
        actionIconColor: taken ? Colors.white : CreamPalette.ink,
        // The tutorial's one candidate still posts on a single tap (user
        // 2026-09-30: its spotlight hint literally says "Tap to station
        // it") — everywhere else, a tap only previews.
        onTap: () => _isTutorial
            ? (_swapTargetId == null ? _set(c, true) : _swapWith(c))
            : setState(() => _preview = c),
      ),
    );
  }

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
      trailing: PixelIcon(
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
