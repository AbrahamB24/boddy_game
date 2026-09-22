import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/creature_family.dart' show CreatureAvatar;
import '../social/social_actions.dart' show confirmDialog;
import '../social/widgets/social_kit.dart';
import 'build_menu_request.dart';
import 'data/building_definitions.dart' show BuildingCategory, BuildingDef;
import 'data/workshop_role_effects.dart' show workshopRoleEmoji;
import 'models/placed_building.dart';
import 'services/game_engine.dart';
import 'services/housing_overview.dart';
import 'services/work_overview.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'widgets/building_icon.dart';

/// THE WORKFORCE PAGE (user 2026-09-19, "Variante 6, Besetzung im Blick", with
/// two additions the user asked for: good SORTING, and what is PRODUCED — in
/// total and per monster).
///
/// At the top the goal and its state: seats staffed (with a bar), seats empty,
/// free monsters, and one gold button that fills every empty seat with the best
/// free monster available. (The settlement-wide "produced per hour" cell was
/// dropped 2026-09-20 — it stops being readable with many resources; every row
/// carries its own building's total.) The two tabs stand as a rail at the left.
/// Under it the sort chips (Need, Output, Level, Name, Post — tap the chosen one
/// again to reverse it) and a "needs workers" filter. Then one row per workshop
/// with each seat's monster, name and what IT makes, and the building's total on
/// the right. A workshop no road reaches is not in the list — a warning under it
/// says so.
///
/// Every figure comes from [buildWorkSites], which uses the economy's own
/// formulas (see work_overview.dart). A tap on a row opens the building's dialog,
/// where the crew is changed.
/// The two halves of the page (user 2026-09-20, "Variante 1, Zwei Reiter"): who
/// works where, and who lives where.
enum WorkTab { work, housing }

class WorkScreen extends StatefulWidget {
  /// Which half opens first — Housing when the header cell or a house sent you.
  final WorkTab startOn;

  const WorkScreen({super.key, this.startOn = WorkTab.work});

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> {
  final _settlement = SettlementController();
  final _creatures = CreaturesController();

  late WorkTab _tab = widget.startOn;

  HouseSort _houseSort = HouseSort.rooms;
  bool _houseReversed = false;

  WorkSort _sort = WorkSort.need;
  bool _reversed = false;
  bool _needsOnly = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_settlement, _creatures]),
    builder: (context, _) {
      final connected = _settlement.connectedBuildingIds;
      final sites = buildWorkSites(
        buildings: _settlement.buildings,
        creatures: _creatures.creatures,
        connectedIds: connected,
        isWorking: _creatures.isWorkingNow,
        absenceOf: _absence,
        era: _settlement.dungeonMaxStage,
        energy: _settlement.energyMultiplier,
      );
      final summary = WorkSummary.of(sites);
      final free = _creatures.creatures.where(_isFree).toList();
      final plan = planFill(sites: sites, free: free);
      final shown = sortedSites(
        _needsOnly ? sites.where((s) => s.empty > 0) : sites,
        _sort,
        reversed: _reversed,
      );
      final unlinked = disconnectedWorkshops(
        buildings: _settlement.buildings,
        connectedIds: connected,
      );
      final used = _settlement.housingUsed;
      final cap = _settlement.housingCapacity;
      final houses = buildHouseRows(
        buildings: _settlement.buildings,
        functional: (b) => GameEngine.functional(b, connected),
        era: _settlement.dungeonMaxStage,
      );
      // The two tabs are a RAIL beside the card (user 2026-09-20: "Work und
      // Housing buttons an einem anderen Ort platzieren"), not a row above the
      // list: on a landscape screen height is the scarce axis, width is not, so
      // the list keeps every pixel of height (user: "der wichtige Teil ist unten
      // ganz klein scrollbar").
      return MenuScaffold(
        title: 'Work & Housing',
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 108,
                child: creamCard(
                  padding: const EdgeInsets.all(8),
                  child: _tabs(summary, used, cap),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: creamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_tab == WorkTab.work) ...[
                        _header(summary, free.length, plan),
                        _sortBar(),
                        Expanded(child: _list(shown, unlinked, sites.isEmpty)),
                      ] else ...[
                        _housingHeader(used, cap),
                        _houseSortBar(houses.length),
                        Expanded(child: _houseList(houses, used, cap)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  // ── Who is where ─────────────────────────────────────────────────────

  /// Why a posted monster is not at its post — the building dialog's words.
  String? _absence(CreatureInstance c) => c.isKo
      ? '💀 K.O.'
      : _creatures.isBreeding(c.id)
      ? '🥚 breeding'
      : _creatures.isOnExpedition(c.id)
      ? '🎒 away'
      : c.isHealing
      ? '🩺 treatment'
      : null;

  /// A monster nobody has posted and who could go to work now.
  bool _isFree(CreatureInstance c) =>
      !c.isAssigned &&
      !c.isKo &&
      !c.isHealing &&
      !_creatures.isBreeding(c.id) &&
      !_creatures.isOnExpedition(c.id) &&
      !c.isTraining &&
      !c.isQueuedForTraining;

  // ── The two tabs ─────────────────────────────────────────────────────

  Widget _tabs(WorkSummary s, int used, int cap) {
    final full = used >= cap;
    Widget tab(WorkTab t, IconData icon, String title, String sub) {
      final on = _tab == t;
      return Expanded(
        child: Pressable(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = t),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: on ? goldButton() : raisedTile(radius: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: kBoxInk),
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: kBoxInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  sub,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: !on && t == WorkTab.housing && full
                        ? CreamPalette.warn
                        : kBoxInkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tab(
          WorkTab.work,
          Icons.construction,
          'Work',
          s.cap == 0 ? 'no workshops' : '${s.staffed}/${s.cap} staffed',
        ),
        const SizedBox(height: 8),
        tab(
          WorkTab.housing,
          Icons.home_work_outlined,
          'Housing',
          full ? '$used/$cap · full' : '$used/$cap · ${cap - used} free',
        ),
      ],
    );
  }

  // ── Housing ──────────────────────────────────────────────────────────

  Widget _housingHeader(int used, int cap) {
    final full = used >= cap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: SizedBox(
        height: 58,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cell(
              flex: 2,
              top: '$used/$cap',
              label: 'housing used',
              warn: full,
              bottom: _bar(
                cap == 0 ? 0 : used / cap,
                color: full ? CreamPalette.warn : CreamPalette.gold,
              ),
            ),
            const SizedBox(width: 8),
            _cell(
              flex: 1,
              top: '${cap > used ? cap - used : 0}',
              label: 'free rooms',
              warn: full,
            ),
            const SizedBox(width: 8),
            _cell(flex: 1, top: '$used', label: 'monsters'),
            const SizedBox(width: 10),
            Center(
              child: SocialGoldButton(
                'Build a house',
                height: 40,
                fontSize: 12.5,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Closes back to the map and opens the build strip on Housing.
                onTap: () => BuildMenuRequest.open(
                  context,
                  category: BuildingCategory.housing,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _houseSortBar(int count) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
    child: Row(
      children: [
        Text(
          'HOUSES · $count',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: kBoxAccent,
          ),
        ),
        const Spacer(),
        for (final s in HouseSort.values) ...[
          _pill(
            s.label + (s == _houseSort ? (_houseReversed ? '  ↑' : '  ↓') : ''),
            on: s == _houseSort,
            onTap: () => setState(() {
              if (s == _houseSort) {
                _houseReversed = !_houseReversed;
              } else {
                _houseSort = s;
                _houseReversed = false;
              }
            }),
          ),
          if (s != HouseSort.values.last) const SizedBox(width: 6),
        ],
      ],
    ),
  );

  Widget _houseList(List<HouseRow> houses, int used, int cap) {
    final sorted = sortedHouses(houses, _houseSort, reversed: _houseReversed);
    final full = used >= cap;
    final onlyCastle =
        houses.isNotEmpty && houses.every((h) => h.def.isMainBuilding);
    final maxRooms = houses.fold<double>(
      0,
      (m, h) => h.rooms > m ? h.rooms : m,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      children: [
        // What "full" means, in the words of what it stops.
        if (full) ...[
          _note(
            'Full — a catch, a hatch or an adoption would be turned away. '
            'Build a house or raise a dwelling.',
            warn: true,
          ),
          const SizedBox(height: 7),
        ],
        if (houses.isEmpty)
          _note('Nothing shelters monsters yet — build a House.')
        else if (onlyCastle) ...[
          _note(
            'Only the Castle houses monsters so far. A House shelters more.',
          ),
          const SizedBox(height: 7),
        ],
        for (final h in sorted) ...[
          _houseRow(h, maxRooms),
          const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _note(String text, {bool warn = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: warn
        ? BoxDecoration(
            color: CreamPalette.warn.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CreamPalette.warn.withValues(alpha: 0.4)),
          )
        : null,
    child: Text(
      text,
      style: warn
          ? const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: CreamPalette.warn,
            )
          : FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
    ),
  );

  Widget _houseRow(HouseRow h, double maxRooms) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => showBuildingDetailDialog(context, _settlement, h.building),
    child: Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
      decoration: raisedTile(radius: 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Center(
              child: BuildingIcon(
                imageUrl: h.def.imageUrl,
                defId: h.def.id,
                size: 42,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(
                    size: 12.5,
                  ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Lv ${h.building.level}',
                  style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _bar(
                maxRooms <= 0 ? 0 : h.rooms / maxRooms,
                color: CreamPalette.better,
              ),
            ),
          ),
          Text(
            '+${h.rooms.round()}',
            style: FoE.value(size: 14).copyWith(color: kBoxAccent),
          ),
          const SizedBox(width: 4),
          Text(
            'rooms',
            style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: kBoxInkFaint),
        ],
      ),
    ),
  );

  // ── Header: the goal and its state ───────────────────────────────────

  Widget _header(WorkSummary s, int freeCount, List<PlannedSeat> plan) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: SizedBox(
        height: 58,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cell(
              flex: 3,
              top: '${s.staffed}/${s.cap}',
              label: 'seats staffed',
              bottom: _bar(s.cap == 0 ? 0 : s.staffed / s.cap),
            ),
            const SizedBox(width: 8),
            _cell(
              flex: 2,
              top: '${s.empty}',
              label: 'seats empty',
              warn: s.empty > 0,
            ),
            const SizedBox(width: 8),
            _cell(flex: 2, top: '$freeCount', label: 'free monsters'),
            // No "produced per hour" cell any more (user 2026-09-20: it stops
            // being readable once there are many resources) — each row already
            // carries its own building's total.
            const SizedBox(width: 10),
            Center(
              child: SocialGoldButton(
                plan.isEmpty
                    ? 'Fill empty seats'
                    : 'Fill ${plan.length} seat${plan.length == 1 ? '' : 's'}',
                height: 40,
                fontSize: 12.5,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onTap: plan.isEmpty ? null : () => _fill(plan),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell({
    required int flex,
    required String label,
    String? top,
    Widget? bottom,
    bool warn = false,
  }) => Expanded(
    flex: flex,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: CreamPalette.tan.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (top != null)
            Text(
              top,
              style: FoE.value(
                size: 17,
              ).copyWith(color: warn ? CreamPalette.warn : kBoxAccent),
            ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(
              size: 10.5,
            ).copyWith(color: kBoxInkSoft, fontWeight: FontWeight.w700),
          ),
          if (bottom != null) ...[const SizedBox(height: 3), bottom],
        ],
      ),
    ),
  );

  Widget _bar(double fraction, {double width = 120, Color? color}) => SizedBox(
    width: width,
    height: 7,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          ColoredBox(color: kBoxInk.withValues(alpha: 0.15)),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0.0, 1.0),
            child: ColoredBox(
              color:
                  color ??
                  (fraction >= 1 ? CreamPalette.better : CreamPalette.gold),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _fill(List<PlannedSeat> plan) async {
    final ok = await confirmDialog(
      context,
      title: 'Fill ${plan.length} empty seat${plan.length == 1 ? '' : 's'}?',
      body:
          'Your best free monsters take the empty seats, the best pairing '
          'first. You can change any of them afterwards.',
      confirmLabel: 'Fill',
    );
    if (!ok || !mounted) return;
    var done = 0;
    String? lastError;
    for (final p in plan) {
      final err = await _settlement.assignCreatureToWorkshop(
        p.creature.id,
        p.building.id,
        p.role.stat,
      );
      if (err == null) {
        done++;
      } else {
        lastError = err;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lastError == null
              ? 'Filled $done seat${done == 1 ? '' : 's'}.'
              : 'Filled $done of ${plan.length} — $lastError',
        ),
      ),
    );
  }

  // ── Sorting ──────────────────────────────────────────────────────────

  Widget _sortBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
    child: Row(
      children: [
        Text(
          'SORT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: kBoxAccent,
          ),
        ),
        const SizedBox(width: 8),
        for (final s in WorkSort.values) ...[
          _pill(
            s.label + (s == _sort ? (_reversed ? '  ↑' : '  ↓') : ''),
            on: s == _sort,
            onTap: () => setState(() {
              if (s == _sort) {
                _reversed = !_reversed;
              } else {
                _sort = s;
                _reversed = false;
              }
            }),
          ),
          const SizedBox(width: 6),
        ],
        const Spacer(),
        _pill(
          'Needs workers only',
          on: _needsOnly,
          onTap: () => setState(() => _needsOnly = !_needsOnly),
        ),
      ],
    ),
  );

  Widget _pill(String text, {required bool on, required VoidCallback onTap}) =>
      Pressable(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: on ? goldButton() : raisedTile(radius: 11),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: kBoxInk,
            ),
          ),
        ),
      );

  // ── The list ─────────────────────────────────────────────────────────

  Widget _list(
    List<WorkSite> shown,
    List<({PlacedBuilding building, BuildingDef def})> unlinked,
    bool noWorkshops,
  ) {
    if (noWorkshops && unlinked.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No functional workshops yet — build (and road-connect) a work '
            'building first.',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      children: [
        if (shown.isEmpty && !noWorkshops)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Every seat is staffed.',
              textAlign: TextAlign.center,
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            ),
          ),
        for (final s in shown) ...[_siteRow(s), const SizedBox(height: 7)],
        for (final u in unlinked) ...[
          _unlinkedRow(u.def),
          const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _siteRow(WorkSite s) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => showBuildingDetailDialog(context, _settlement, s.building),
    child: Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
      decoration: raisedTile(radius: 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Center(
              child: BuildingIcon(
                imageUrl: s.def.imageUrl,
                defId: s.def.id,
                size: 42,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 132,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.label(
                    size: 12.5,
                  ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Lv ${s.building.level} · '
                  '${s.def.workshops.map((r) => workshopRoleEmoji(r.resource)).toSet().join(' ')}'
                  '${s.paused ? '  ⏸️ paused' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                ),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [for (final seat in s.seats) _seat(seat)],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 128,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s.staffed}/${s.cap}',
                  style: FoE.value(size: 13).copyWith(
                    color: s.empty > 0
                        ? CreamPalette.warn
                        : CreamPalette.better,
                  ),
                ),
                const SizedBox(height: 3),
                _bar(s.cap == 0 ? 0 : s.staffed / s.cap, width: 54),
                const SizedBox(height: 4),
                for (final part in s.totalParts.take(3))
                  Text(
                    part,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.value(size: 11).copyWith(color: kBoxInk),
                  ),
                if (s.totalParts.isEmpty)
                  Text(
                    '—',
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkFaint),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: kBoxInkFaint),
        ],
      ),
    ),
  );

  Widget _seat(WorkSeat seat) {
    final c = seat.creature;
    final away = seat.absence != null;
    return SizedBox(
      width: 66,
      child: Column(
        children: [
          if (c == null)
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CreamPalette.gold.withValues(alpha: 0.3),
                border: Border.all(color: CreamPalette.goldDeep, width: 2),
              ),
              child: const Text(
                '+',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: CreamPalette.goldDeep,
                  height: 1,
                ),
              ),
            )
          else
            // The monster family's small tile, like everywhere else (user
            // 2026-09-20): element foot, the monster over it, HP along the edge.
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Opacity(
                opacity: away ? 0.5 : 1,
                child: CreatureAvatar.of(c, size: 32),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            c?.displayName ?? 'empty',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: c == null ? CreamPalette.warn : kBoxInkSoft,
            ),
          ),
          if (c != null)
            Text(
              seat.absence ?? seat.figure ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: away ? kBoxInkFaint : kBoxInk,
              ),
            ),
        ],
      ),
    );
  }

  Widget _unlinkedRow(BuildingDef def) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: CreamPalette.warn.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: CreamPalette.warn.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        BuildingIcon(imageUrl: def.imageUrl, defId: def.id, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${def.name} · not connected to a road',
                style: FoE.label(size: 12.5).copyWith(
                  color: CreamPalette.warn,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Nobody can work here until a road reaches it.',
                style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
